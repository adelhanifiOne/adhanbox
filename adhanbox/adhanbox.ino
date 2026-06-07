// AdhanBox - minimal sketch adding AP configuration via smartphone geolocation
// - Starts an AP when a long-press is detected on CONFIG_BUTTON_PIN
// - Serves a small webpage that requests navigator.geolocation and POSTs lat/lon
// - Stores lat/lon/accuracy/timestamp in Preferences (NVS)
//Version: 1.4.0
#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <WebServer.h>
#include <Preferences.h>
#include <RTClib.h>
#include <DFRobotDFPlayerMini.h>
#include <Adafruit_NeoPixel.h>
// ESP32 LEDC helpers (provides ledcSetup, ledcAttachPin, ledcWrite)
#include <esp32-hal-ledc.h>
// DNS server for captive portal behavior
#include <DNSServer.h>
// mDNS support for discovery via adhanbox.local
#include <ESPmDNS.h>
// OTA firmware updates
#include <ArduinoOTA.h>
#include <Update.h>
// Ensure low-level LEDC declarations are available on all toolchains
#include <driver/ledc.h>
#include <driver/gpio.h>

// LEDC prototypes are provided by <esp32-hal-ledc.h> from the ESP32 core.

#include <soc/gpio_struct.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <time.h>
#include <math.h>
// BLE provisioning (first-boot WiFi setup without leaving the app)
#define ENABLE_BLE 1

#if ENABLE_BLE
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ── BLE Provisioning ─────────────────────────────────────────────────────────
// Custom GATT service for WiFi credential exchange
#define BLE_SVC_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"    // write
#define BLE_PASS_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a9"    // write
#define BLE_STATUS_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26aa"   // read+notify
#define BLE_WIFI_SCAN_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ab"   // write+notify (wifi scan)

static BLEServer *_bleServer = nullptr;
static BLECharacteristic *_bleStatusChar = nullptr;
static BLECharacteristic *_bleWifiScanChar = nullptr;  // WiFi scan results
static bool _bleActive = false;
static bool _bleClientConn = false;
static String _blePendingSSID;
static String _blePendingPass;
static volatile bool _bleCredsReady = false;  // set in BLE task, handled in loop()

class _BLEServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    _bleClientConn = true;
    Serial.println("[BLE] client connected");
  }
  void onDisconnect(BLEServer *s) override {
    _bleClientConn = false;
    Serial.println("[BLE] client disconnected");
    if (_bleActive) s->startAdvertising();  // keep advertising for retry
  }
};

class _BLESsidCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    _blePendingSSID = c->getValue().c_str();
    Serial.printf("[BLE] SSID: %s\n", _blePendingSSID.c_str());
  }
};

class _BLEPassCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    _blePendingPass = c->getValue().c_str();
    Serial.println("[BLE] password received");
    if (_blePendingSSID.length() > 0) _bleCredsReady = true;
  }
};

// ── BLE WiFi Scan callback ─────────────────────────────────────────────────────
// When the app writes "scan" to this characteristic, the ESP32 scans nearby
// WiFi networks and notifies the result as JSON (max 20 networks, sorted by RSSI).
class _BLEWifiScanCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String cmd = String(c->getValue().c_str());
    cmd.trim();
    if (cmd != "scan") return;

    Serial.println("[BLE] WiFi scan requested by client");

    // Run scan in a FreeRTOS task to avoid blocking BLE stack
    xTaskCreate([](void*) {
      // Switch to STA mode temporarily for scan (doesn't disconnect if already STA)
      WiFi.mode(WIFI_STA);
      int n = WiFi.scanNetworks(false, true);  // async=false, show_hidden=true
      Serial.printf("[BLE] WiFi scan found %d networks\n", n);

      int count = min(n, 20);
      if (_bleWifiScanChar && _bleClientConn) {
        // Send start packet
        String startJson = "{\"type\":\"start\",\"count\":" + String(count) + "}";
        _bleWifiScanChar->setValue(startJson.c_str());
        _bleWifiScanChar->notify();
        delay(40);

        for (int i = 0; i < count; i++) {
          if (!_bleClientConn) break;
          String ssid = WiFi.SSID(i);
          ssid.replace("\\", "\\\\");
          ssid.replace("\"", "\\\"");

          String itemJson = "{\"type\":\"item\",\"ssid\":\"" + ssid + "\",\"rssi\":" + String(WiFi.RSSI(i)) + ",\"secure\":" + String(WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? 0 : 1) + "}";
          _bleWifiScanChar->setValue(itemJson.c_str());
          _bleWifiScanChar->notify();
          delay(40);
        }

        if (_bleClientConn) {
          String endJson = "{\"type\":\"end\"}";
          _bleWifiScanChar->setValue(endJson.c_str());
          _bleWifiScanChar->notify();
        }
        Serial.printf("[BLE] Streamed %d WiFi networks via BLE notifications\n", count);
      }
      WiFi.scanDelete();
      vTaskDelete(nullptr);
    }, "ble_wifi_scan", 8192, nullptr, 1, nullptr);
  }
};
#else
static bool _bleActive = false;
#endif
// ─────────────────────────────────────────────────────────────────────────────

// ── MQTT ─────────────────────────────────────────────────────────────────────
WiFiClient mqttWifiClient;
PubSubClient mqtt(mqttWifiClient);

#define MQTT_PORT 1883
#define MQTT_CLIENT_ID "adhanbox"
#define MQTT_RECONNECT_MS 5000UL

// Subscribe topics
#define TOPIC_ADHAN_TRIGGER "adhanbox/adhan/trigger"
#define TOPIC_AUDIO_PLAY "adhanbox/audio/play"
#define TOPIC_AUDIO_STOP "adhanbox/audio/stop"
#define TOPIC_AUDIO_VOLUME "adhanbox/audio/volume"
#define TOPIC_LED_SCENARIO "adhanbox/led/scenario"
#define TOPIC_LED_BRIGHTNESS "adhanbox/led/brightness"

// Publish topics
#define TOPIC_STATUS "adhanbox/status"
#define TOPIC_AUDIO_STATUS "adhanbox/audio/status"
#define TOPIC_PRAYER_FIRED "adhanbox/prayer/fired"
// ─────────────────────────────────────────────────────────────────────────────

// ── OTA ──────────────────────────────────────────────────────────────────────
#define OTA_HOSTNAME "adhanbox"
// OTA password and API token are generated randomly at first boot and stored in NVS.
// Never hardcoded — unique per device.
static String _otaPass;   // loaded/generated in setup()
static String _apiToken;  // loaded/generated in setup()

// ── Async WiFi connect state machine ─────────────────────────────────────────
// handleConnectWifi() stores the request here and returns 202 immediately.
// loop() drives the actual connection and updates wifiConnectState.
enum WifiConnectState { WCS_IDLE,
                        WCS_CONNECTING,
                        WCS_CONNECTED,
                        WCS_FAILED };
static WifiConnectState wifiConnectState = WCS_IDLE;
static String wifiConnectSSID;
static String wifiConnectPass;
static unsigned long wifiConnectStart = 0;
#define WIFI_CONNECT_TIMEOUT_MS 20000UL

// Addressable LED configuration
#ifndef LED_NUM
#define LED_NUM 16  // change to the number of LEDs on your strip (updated to 60)
#endif
const uint8_t LED_START_INDEX = 0;  // start from first pixel (all LEDs enabled)
// Data pin for addressable strip (default user wiring)
#ifndef LED_DATA_PIN
#define LED_DATA_PIN 13
#endif
// If you later want a PWM fallback (non-addressable), set to false.
bool useAddressableLEDs = true;
// Adafruit_NeoPixel: NEO_GRB = WS2812B with G,R,B byte order
Adafruit_NeoPixel leds(LED_NUM, LED_DATA_PIN, NEO_GRB + NEO_KHZ800);
// Button to start config AP (long press)
#ifndef CONFIG_BUTTON_PIN
// Default config button pin: GPIO11 is often used by flash/SPI on ESP32
// and can behave unpredictably. Use a safe GPIO (for example GPIO4).
// Change this if your button is wired to a different pin.
#define CONFIG_BUTTON_PIN 11  // change according to your wiring
#endif

#define AP_SSID_PREFIX "AdhanBox-"
#define AP_TIMEOUT_MS (5 * 60 * 1000UL)  // AP auto-stop after 5 minutes

WebServer server(80);
Preferences prefs;
bool apRunning = false;
unsigned long apStartTime = 0;
// DNS server instance for captive portal redirection
DNSServer dnsServer;
const byte DNS_PORT = 53;

RTC_DS3231 rtc;
DFRobotDFPlayerMini dfplayer;
bool dfAvailable = false;
// If DFPlayer reports missing files, avoid repeatedly attempting to play
bool dfFileMissing = false;
// Last DFPlayer error observed (set by printDetail)
volatile int dfLastError = 0;
#define DFERR_NONE 0
#define DFERR_TIMEOUT 1
#define DFERR_FILEINDEXOUT 2
#define DFERR_OTHER 3

// DS3231 interrupt pin (connect INT/SQW -> this pin)
#ifndef DS3231_INT_PIN
#define DS3231_INT_PIN 7
#endif

// Alarm scheduling state
volatile bool ds3231AlarmFlag = false;
int scheduledPrayerIndex = 0;  // 1-based prayer index (1=Fajr,2=Sunrise,...6=Isha)
DateTime scheduledPrayerTime;
// Software fallback alarm (millis target) to trigger prayer if RTC interrupt fails
unsigned long softwareAlarmAt = 0;
// Persistent option: force playing track 1 for all prayers
bool forcePlayTrack1 = false;
// Global LED brightness (0-100, default 50%)
int ledBrightness = 50;
// Track sequence: adhan plays first, then duaa (track 1) plays after adhan finishes
bool shouldPlayDuaaAfterAdhan = false;
int adhanTrackBeforeDuaa = 0;
// LED scene saved before prayer adhan started (-1 = none saved)
int prayerPrevLedScenario = -1;

// LED / button state
// Scene mapping:
// 0..6 : static colors (off, red, pink, blue, violet, green, yellow)
// 7    : BLINK (reserved for AP/config indication)
// 8    : dynamic hue (all LEDs same color, hue cycling)
// 9    : dynamic palette fade (all LEDs fade between palette colors)
int ledScenario = 8;  // start with dynamic hue by default
bool isPlaying = false;
// ledc PWM channel for LED brightness
const int LEDC_CHANNEL = 0;
const int LEDC_FREQ = 5000;
const int LEDC_RES = 8;  // 0-255

// Forward declarations for new HTTP handlers
void handleSetRTC();
void handleSetAlarmTest();
void handleCancelAlarms();
void handleShowNextAlarm();
void handleShowLoc();
void handleShowTime();
void handlePlayTrack();
void handleStopPlay();
bool tryRecoverDFPlayer(int retries);
void playTrack(int track);
void handleSetVolume();
void handleGetVolume();
void handleSetBrightness();
void handleGetBrightness();
void handleSetLedScenario();
void handleConnectWifi();
void handleScanWifi();
void handleDisconnectWifi();
void handleMawaqitConfig();
void handleMawaqitSync();
bool performMawaqitSync(String &errorMsg);
void handleCalculationConfig();
void handleAdhanConfig();
bool syncTimeFromNtp(unsigned long timeoutMs = 10000);
void handleDumpStatus();
void scheduleNextPrayerAlarm();
bool computeNextPrayer(const DateTime &now, DateTime &nextDt, int &idx);
void handleLedTest();
void handleMqttConfig();
void handleWifiStatus();
void handleOtaUpload();
void handleOtaUploadComplete();
void handleDeviceInfo();
bool requireApiKey();
void setupOTA();
void setupServerRoutes();
void mqttCallback(char *topic, byte *payload, unsigned int len);
void reconnectMQTT();
void mqttPublishStatus();
void mqttPublishPrayerFired(int prayerIndex);
void stopConfigAP();
#if ENABLE_BLE
void startBLEProvisioning();
void stopBLEProvisioning();
void handleBLEProvisioning();
#endif
void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName);
void scanI2CBusAndReport();
void probeIP5306();
bool getPrayerPlaybackForIndex(int prayerIndex, int &trackToPlay, bool &playDuaaAfter);

// LED timing and bit-bang functions removed - using Adafruit_NeoPixel instead

// HSV (8-bit) -> RGB helper (no white channel)
static inline void hsv2rgb(uint8_t h, uint8_t s, uint8_t v, uint8_t &r, uint8_t &g, uint8_t &b) {
  if (s == 0) {
    r = g = b = v;
    return;
  }
  uint8_t region = h / 43;  // 0..5
  uint8_t remainder = (h - (region * 43)) * 6;
  uint8_t p = (v * (255 - s)) >> 8;
  uint8_t q = (v * (255 - ((s * remainder) >> 8))) >> 8;
  uint8_t t = (v * (255 - ((s * (255 - remainder)) >> 8))) >> 8;
  switch (region) {
    case 0:
      r = v;
      g = t;
      b = p;
      break;
    case 1:
      r = q;
      g = v;
      b = p;
      break;
    case 2:
      r = p;
      g = v;
      b = t;
      break;
    case 3:
      r = p;
      g = q;
      b = v;
      break;
    case 4:
      r = t;
      g = p;
      b = v;
      break;
    default:
      r = v;
      g = p;
      b = q;
      break;
  }
}

// Forward declarations for functions defined later but used above
bool ds3231SetAlarm2Daily(uint8_t hour, uint8_t minute);
void ds3231DisableAlarms();
bool loadStoredLocation(double &outLat, double &outLon, double &outAcc);
void stopPlay();
void playTrack(int track);

// LED helper using driver API (some cores don't expose ledcSetup/ledcAttachPin)
static inline void setLedDuty(uint32_t duty) {
  // If using an addressable strip driven by the native protocol, don't use LEDC
  // on the data pin — that would corrupt the data stream and can cause the
  // first pixel to flicker. Only apply PWM duty when not using addressable LEDs.
  if (useAddressableLEDs) return;
  uint32_t max = (1u << LEDC_RES) - 1u;
  if (duty > max) duty = max;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL, duty);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL);
}

// Helper: set all addressable pixels to RGB
static inline void stripSetAll(uint8_t r, uint8_t g, uint8_t b) {
  // Apply global brightness scaling
  r = (r * ledBrightness) / 100;
  g = (g * ledBrightness) / 100;
  b = (b * ledBrightness) / 100;
  // Set all pixels via Adafruit_NeoPixel
  for (uint16_t i = 0; i < LED_NUM; i++) {
    leds.setPixelColor(i, r, g, b);
  }
  leds.show();
}

// Forcefully clear the strip
static void clearStrip() {
  for (int i = 0; i < 3; i++) {
    stripSetAll(0, 0, 0);
    delay(20);
  }
  delay(120);
}

// LED test timer (non-blocking): when >0, overrides scenario until expiry
unsigned long ledTestUntil = 0;
int prevLedScenario = -1;

// static color table (R,G,B) for WS2812B RGB LEDs
static const uint8_t STATIC_COLORS[][3] = {
  { 0, 0, 0 },      // off
  { 255, 0, 0 },    // red
  { 255, 0, 180 },  // pink
  { 0, 60, 255 },   // blue
  { 180, 0, 255 },  // violet
  { 0, 255, 0 },    // green
  { 255, 255, 0 },  // yellow
};
static const uint8_t NUM_STATIC_COLORS = sizeof(STATIC_COLORS) / sizeof(STATIC_COLORS[0]);
const int BLINK_INDEX = 7;
const int DYN_HUE_INDEX = 8;
const int DYN_FADE_INDEX = 9;
const int SCENE_PRAYER = 10;
const int SCENE_BREATH = 11;
const int SCENE_CANDLE = 12;
const int TOTAL_SCENES = 13;

// DFPlayer pin mapping requested: DFPlayer on GPIO1 and GPIO2
// DFPlayer TX -> ESP RX (GPIO1)  // <-- WARNING: GPIO1 is also UART0 TX (console)
// DFPlayer RX <- ESP TX (GPIO2)
// The DFPlayer TX (5V) MUST be level-shifted / use a resistor divider before GPIO1.
#define DFPLAYER_RX_PIN 2  // ESP RX (connect to DFPlayer TX through divider)
#define DFPLAYER_TX_PIN 1  // ESP TX (connect to DFPlayer RX)

// Move LED data pin to a free GPIO to avoid conflicts with UART0
// User wired the LED data line to GPIO13
// (already defined above)

// Simple webpage (served from RAM) — improved multi‑page UI with CSS
const char index_html[] PROGMEM = R"HTML(
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AdhanBox — Configuration</title>
  <style>
    :root{ --bg:#0f1724; --card:#111827; --muted:#9CA3AF; --accent:#EF4444; --accent2:#06B6D4; --card-pad:14px; --radius:10px; color-scheme: dark; }
    html,body{ height:100%; margin:0; font-family:system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background:linear-gradient(180deg,#071022 0%, #071630 60%); color:#E5E7EB; }
    .container{ max-width:900px; margin:18px auto; padding:16px; }
    header{ display:flex; align-items:center; gap:12px; }
    header h1{ font-size:20px; margin:0; }
    nav{ margin-top:12px; display:flex; gap:8px; }
    .tab{ background:transparent; border:1px solid rgba(255,255,255,0.04); padding:8px 12px; border-radius:8px; cursor:pointer; color:var(--muted); }
    .tab.active{ background:linear-gradient(90deg,var(--accent)55,var(--accent2)22); color:#081225; font-weight:600; }
    .grid{ display:grid; grid-template-columns:1fr 320px; gap:16px; margin-top:16px; }
    .card{ background:var(--card); padding:var(--card-pad); border-radius:var(--radius); box-shadow:0 6px 18px rgba(2,6,23,0.6); }
    .small{ font-size:13px; color:var(--muted); }
    .field{ display:flex; flex-direction:column; gap:6px; margin-bottom:10px; }
    input[type=text], input[type=number], input[type=password]{ background:#0b1220; border:1px solid rgba(255,255,255,0.04); padding:8px 10px; color:#fff; border-radius:6px; }
    button.btn{ background:var(--accent); color:#fff; border:none; padding:8px 12px; border-radius:8px; cursor:pointer; }
    button.ghost{ background:transparent; border:1px solid rgba(255,255,255,0.06); color:var(--muted); padding:8px 10px; border-radius:8px; cursor:pointer; }
    table{ width:100%; border-collapse:collapse; }
    td, th{ padding:6px 4px; }
    tr:nth-child(odd) td{ background:rgba(255,255,255,0.01); }
    .muted{ color:var(--muted); font-size:13px; }
    footer{ margin-top:18px; text-align:center; color:var(--muted); font-size:13px; }
    @media(max-width:880px){ .grid{ grid-template-columns:1fr; } .container{ padding:10px; } }
    /* start overlay */
    .overlay{ position:fixed; inset:0; background:rgba(7, 10, 19, 0.85); backdrop-filter: blur(8px); display:flex; align-items:center; justify-content:center; z-index:40; }
    .overlay-card{ background:#111827; border: 1px solid rgba(255,255,255,0.08); padding:24px; border-radius:14px; width:min(500px,94%); box-shadow:0 20px 50px rgba(0,0,0,0.7); }
    .net-list{ max-height:260px; overflow-y:auto; margin-top:16px; border-radius:8px; background:#0b1220; border:1px solid rgba(255,255,255,0.04); }
    
    /* WiFi list items */
    .net-row{ display:flex; align-items:center; justify-content:space-between; padding:12px 16px; border-bottom:1px solid rgba(255,255,255,0.02); cursor:pointer; transition:background 0.2s ease, transform 0.1s ease; }
    .net-row:last-child{ border-bottom:none; }
    .net-row:hover{ background:rgba(255,255,255,0.04); }
    .net-row:active{ transform:scale(0.99); }
    
    .net-details{ display:flex; align-items:center; gap:12px; }
    .net-name{ font-weight:600; font-size:15px; color:#f3f4f6; text-align:left; }
    .net-rssi-val{ font-size:12px; color:var(--muted); text-align:left; }
    
    .net-icons{ display:flex; align-items:center; gap:8px; }
    
    /* Icon SVGs */
    .icon-svg{ width:20px; height:20px; display:block; }
    .icon-lock{ width:16px; height:16px; fill:#9CA3AF; display:block; }

    /* Modal for Password Entry */
    .modal-overlay{ position:fixed; inset:0; background:rgba(7, 10, 19, 0.8); backdrop-filter: blur(6px); display:flex; align-items:center; justify-content:center; z-index:50; }
    .modal-card{ background:#111827; border:1px solid rgba(255,255,255,0.08); padding:24px; border-radius:14px; width:min(400px,90%); box-shadow:0 20px 45px rgba(0,0,0,0.8); }
    .modal-title{ font-size:18px; font-weight:600; margin:0 0 16px 0; color:#fff; }
    
    /* Password field with toggle button */
    .pwd-wrapper{ position:relative; display:flex; align-items:center; width: 100%; }
    .pwd-wrapper input{ width:100%; padding-right:40px; box-sizing:border-box; }
    .pwd-toggle{ position:absolute; right:10px; background:transparent; border:none; color:var(--muted); cursor:pointer; font-size:16px; padding:4px; display:flex; align-items:center; justify-content:center; }
    
    /* Spinner for loading state */
    .spinner{ display:inline-block; width:14px; height:14px; border:2px solid rgba(255,255,255,0.3); border-top-color:#fff; border-radius:50%; animation:spin-ani 0.8s linear infinite; }
    @keyframes spin-ani { to { transform:rotate(360deg); } }
  </style>
</head>
<body>
  <div class="container">
    <!-- Start overlay: choose WiFi available / not available -->
    <div id="startOverlay" class="overlay">
      <div class="overlay-card">
        <h2 style="margin:0 0 12px 0; text-align:center; font-size:22px;">Bienvenue — Configuration</h2>
        <p class="small" style="text-align:center; margin-bottom:18px;">Commencez par indiquer si vous avez un réseau Wi‑Fi à portée.</p>
        <!-- Buttons stacked and larger for clarity -->
        <div style="display:flex;flex-direction:column;gap:12px;margin-top:12px;">
          <button class="btn" id="startWifiBtn" style="font-size:18px;padding:14px;font-weight:600;">WiFi disponible</button>
          <button class="ghost" id="startNoWifiBtn" style="font-size:18px;padding:14px;">WiFi non disponible</button>
        </div>
        <div id="scanContainer" style="margin-top:20px; display:none;">
          <div style="display:flex;gap:8px;align-items:center;margin-bottom:12px;">
            <strong style="font-size:16px;">Réseaux trouvés</strong>
            <button class="ghost" id="refreshScanBtn" style="margin-left:auto; padding:6px 12px; font-size:13px;">Rafraîchir</button>
          </div>
          <div id="netList" class="net-list"></div>
        </div>
      </div>
    </div>

    <!-- WiFi Password Modal -->
    <div id="wifiModal" class="modal-overlay" style="display:none;">
      <div class="modal-card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
          <h3 class="modal-title" style="margin:0;">Connexion Wi‑Fi</h3>
          <button class="ghost" id="closeWifiModalBtn" style="border:none; padding:4px 8px; font-size:20px; line-height:1; cursor:pointer;">&times;</button>
        </div>
        
        <div class="field" style="margin-bottom:14px;">
          <label class="small" style="color:var(--muted); margin-bottom:6px; font-weight:500; text-align:left;">SSID</label>
          <input id="selSsid" type="text" readonly style="background:#090d16; border-color:rgba(255,255,255,0.06); font-weight:600; color:#fff;" />
        </div>
        
        <div class="field" style="margin-bottom:18px;">
          <label class="small" style="color:var(--muted); margin-bottom:6px; font-weight:500; text-align:left;">Mot de passe</label>
          <div class="pwd-wrapper">
            <input id="selPass" type="password" placeholder="Entrez le mot de passe" />
            <button id="toggleShowPassBtn" type="button" class="pwd-toggle">👁️</button>
          </div>
          <span class="small" style="margin-top:4px; font-size:11px; color:var(--muted); text-align:left;">(laissez vide si réseau ouvert)</span>
        </div>
        
        <div style="display:flex; gap:10px; justify-content:flex-end;">
          <button class="ghost" id="cancelWifiModalBtn" style="padding:10px 16px;">Annuler</button>
          <button class="btn" id="overlayConnectBtn" style="padding:10px 20px; font-weight:600; display:flex; align-items:center; gap:8px;">
            <span>Se connecter</span>
            <span id="connectSpinner" style="display:none;" class="spinner"></span>
          </button>
        </div>
        <div id="overlayWifiStatus" class="muted" style="margin-top:16px; text-align:center; font-weight:500;"></div>
      </div>
    </div>
    <header>
      <img src="data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='28' height='28' viewBox='0 0 24 24' fill='%23EF4444'><path d='M12 2l2.1 4.8L19 8l-3.5 3.1L16 16l-4-2.4L8 16l.5-4.9L5 8l4.9-.9L12 2z'/></svg>" alt="logo">
      <h1>AdhanBox — Configuration</h1>
      <button class="ghost" id="showWifiAutoBtn" style="margin-left:12px; height:36px; align-self:center;">Afficher paramètres Wi‑Fi</button>
    </header>

    <nav>
      <div class="tab active" data-page="dashboard">Tableau</div>
      <div class="tab" data-page="location">Localisation</div>
      <div class="tab" data-page="prayers">Horaires</div>
      <div class="tab" data-page="advanced">Avancé</div>
    </nav>

    <div class="grid">
      <div>
        <!-- Dashboard -->
        <section class="card page" id="page-dashboard">
          <h3>Statut</h3>
          <p class="small">Heure du module (DS3231)</p>
          <div style="display:flex;align-items:center;gap:12px;">
            <div style="font-size:18px;font-weight:600;"> <span id="rtcTime">--:--:--</span></div>
            <button class="ghost" id="rtcRefresh">Actualiser</button>
            <!-- removed duplicate Test Adhan from dashboard -->
          </div>
          <div style="margin-top:10px; display:flex; align-items:center; gap:10px;">
            <label class="small" for="volSlider">Volume</label>
            <input id="volSlider" type="range" min="0" max="30" value="20" style="width:220px; height:18px;">
            <span id="volLbl" class="small" style="font-size:16px; font-weight:600;">20</span>
            <button class="ghost" id="volSetBtn">Set</button>
          </div>
          <div style="margin-top:10px; display:flex; align-items:center; gap:10px;">
            <label class="small" for="brightSlider">Luminosité</label>
            <input id="brightSlider" type="range" min="0" max="100" value="50" style="width:220px; height:18px;">
            <span id="brightLbl" class="small" style="font-size:16px; font-weight:600;">50%</span>
            <button class="ghost" id="brightSetBtn">Appliquer</button>
          </div>
          <div style="margin-top:12px; display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
            <label class="small">Tester pistes:</label>
            <button class="ghost" id="testTrack1Btn">Duaa (piste 1)</button>
            <button class="ghost" id="testTrack2Btn">Adhan (piste 2)</button>
            <button class="ghost" id="testTrack3Btn">Adhan alt (piste 3)</button>
            <button class="btn" id="stopTestBtn" style="background:#EF4444;">Arrêter</button>
          </div>
          <div style="margin-top:12px; display:flex; gap:8px; align-items:center;">
            <label class="small">Scénario lumineux</label>
            <select id="dashLedSelect" style="min-width:160px;">
              <option value="0">Off</option>
              <option value="1">Red</option>
              <option value="2">Pink</option>
              <option value="3">Blue</option>
              <option value="4">Violet</option>
              <option value="5">Green</option>
              <option value="6">Yellow</option>
              <option value="8">Dynamic hue</option>
              <option value="9">Dynamic fade</option>
            </select>
            <button class="ghost" id="dashSetSceneBtn">Appliquer</button>
            <button class="btn" id="dashStopAPBtn" style="margin-left:auto;background:#10B981;">Sauvegarder la configuration et arrêter l'AP</button>
          </div>
          <p class="muted" id="statusMsg">Connectez votre téléphone au réseau AdhanBox pour configurer.</p>
          <hr style="margin:12px 0; opacity:0.06">
          <h4 style="margin:6px 0">Infos rapides</h4>
          <div class="small">Localisation: <span id="quick_loc">--</span></div>
          <div class="small">Fuseau utilisé: <span id="quick_tz">--</span></div>
          <div style="margin-top:10px;">
            <h4 style="margin:8px 0 6px 0">Horaires (aperçu)</h4>
            <table style="width:100%;font-size:14px;">
              <tbody>
                <tr><td>Fajr</td><td id="dash_p_fajr">--:--</td></tr>
                <tr><td>Dhuhr</td><td id="dash_p_dhuhr">--:--</td></tr>
                <tr><td>Asr</td><td id="dash_p_asr">--:--</td></tr>
                <tr><td>Maghrib</td><td id="dash_p_maghrib">--:--</td></tr>
                <tr><td>Isha</td><td id="dash_p_isha">--:--</td></tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- Location page -->
        <section class="card page" id="page-location" style="display:none;">
              <h3>Localisation</h3>
              <p class="small">Entrez manuellement la position utilisée pour calculer les horaires.</p>
              <hr>
              <div class="field">
                      <label>Latitude: <input id="latInput" type="text" placeholder="48.8566"></label>
                      <label>Longitude: <input id="lonInput" type="text" placeholder="2.3522"></label>
                      <label>Précision (m): <input id="accInput" type="number" placeholder="10"></label>
                      <div style="display:flex;gap:8px"><button class="btn" id="manualBtn">Enregistrer manuellement</button><div id="manualStatus" class="muted"></div></div>
                      <div style="margin-top:10px; display:flex; gap:8px; align-items:center;"><button class="btn" id="locAutoBtn">Auto-locate (ESP)</button><div id="locAutoStatus" class="muted"></div></div>
                            <details style="margin-top:12px; border-top:1px solid rgba(255,255,255,0.03); padding-top:10px;">
                              <summary style="cursor:pointer; color:var(--muted);">Paramètres avancés de localisation</summary>
                              <div style="margin-top:8px; display:flex; flex-direction:column; gap:8px;">
                                <label>Clé API HERE (optionnelle): <input id="geoKeyInput" type="text" placeholder="paste HERE API key"></label>
                                <div style="display:flex;gap:8px;"><button class="btn" id="saveGeoKeyBtn">Enregistrer la clé</button><div id="geoStatus" class="muted"></div></div>
                              </div>
                            </details>
              </div>
            </section>

        <!-- Timezone page -->
        <!-- Timezone settings moved into Advanced / manual time section per UI request -->

        <!-- Prayer times page -->
        <section class="card page" id="page-prayers" style="display:none;">
          <h3>Horaires de prière</h3>
          <p class="small">Horaires calculés localement à partir de la position et fuseau.</p>
          <table>
            <tbody>
              <tr><td>Fajr</td><td id="p_fajr">--:--</td></tr>
              <tr><td>Sunrise</td><td id="p_sunrise">--:--</td></tr>
              <tr><td>Dhuhr</td><td id="p_dhuhr">--:--</td></tr>
              <tr><td>Asr</td><td id="p_asr">--:--</td></tr>
              <tr><td>Maghrib</td><td id="p_maghrib">--:--</td></tr>
              <tr><td>Isha</td><td id="p_isha">--:--</td></tr>
            </tbody>
          </table>
          <p class="muted">Fuseau: <span id="tzUsed">--</span> (<span id="tzSource">--</span>)</p>
          <div style="margin-top:10px;">
            <button class="ghost" id="recalcTimesBtn">Recalculer horaires</button>
          </div>
        </section>

        <!-- Advanced page -->
        <section class="card page" id="page-advanced" style="display:none;">
          <h3>Avancé</h3>
          <p class="small">Commandes utiles et diagnostics.</p>
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn" id="setrtcBtn">Réglage horaire(compilation)</button>
            <div style="display:flex;gap:6px;align-items:center;">
              <input type="date" id="rtcDate" />
              <input type="time" id="rtcTimeInput" step="1" />
              <button class="btn" id="setRtcManualBtn">Réglage horaire manuel</button>
            </div>
            <div style="display:flex;gap:8px;align-items:center;margin-top:8px;">
              <label class="small">Fuseau (offset minutes):</label>
              <input id="tzInput" type="number" placeholder="60" style="width:100px;padding:8px;">
              <select id="tzSelect">
                <option value="">Choisir...</option>
                <option value="-120">UTC-2 (-120)</option>
                <option value="-60">UTC-1 (-60)</option>
                <option value="0">UTC+0 (0)</option>
                <option value="60">UTC+1 (60)</option>
                <option value="120">UTC+2 (120)</option>
                <option value="180">UTC+3 (180)</option>
                <option value="330">UTC+5:30 (330)</option>
              </select>
              <div style="display:flex;gap:8px"><button class="btn" id="tzBtn">Enregistrer fuseau</button><div id="tzStatus" class="muted"></div></div>
            </div>
            <button class="ghost" id="ledTestBtn">Test LED</button>
            <select id="ledSceneSelect" style="min-width:140px">
              <option value="0">Off</option>
              <option value="1">Red</option>
              <option value="2">Pink</option>
              <option value="3">Blue</option>
              <option value="4">Violet</option>
              <option value="5">Green</option>
              <option value="6">Yellow</option>
              <option value="8">Dynamic hue</option>
              <option value="9">Dynamic fade</option>
            </select>
            <button class="ghost" id="setSceneBtn">Set Scene</button>
            <button class="ghost" id="ledOffBtn">Éteindre LEDs</button>
            <button class="btn" id="advPlayTestBtn">Test Adhan</button>
            <button class="ghost" id="finishConfigBtn">Sauvegarder la configuration et arrêter l'AP</button>
            <button class="ghost" id="dumpStatusBtn">Dump status</button>
          </div>
          <pre id="dumpArea" style="margin-top:8px; max-height:220px; overflow:auto; background:#051018; padding:8px; border-radius:8px; color:#9CA3AF;">(dump)</pre>
          <hr style="margin:8px 0; opacity:0.06">
          <p class="muted">Options avancées retirées de cette page pour simplifier l'interface. Voir l'onglet « Localisation » pour la clé HERE.</p>
        </section>

      </div>

      <aside>
        <div class="card">
          <h4>Prochaine Adhan</h4>
          <div style="font-size:20px;font-weight:700;text-align:center;padding:10px;" id="aside_next">--:--</div>
        </div>
        <div class="card" style="margin-top:12px;">
          <h4>Actions rapides</h4>
          <div style="display:flex;gap:8px;flex-direction:column;">
            <button class="ghost" id="openAP">Rouvrir la page de configuration</button>
          </div>
        </div>
      </aside>
    </div>

    <footer>AdhanBox — Configurez la position et le fuseau pour obtenir des horaires précis.</footer>
  </div>

  <script>
    // Surface JS errors in the page so users see why handlers may not run
    window.onerror = function(message, source, lineno, colno, error){
      try{
        var s = document.getElementById('statusMsg');
        if(s) s.innerText = 'JS error: ' + message + ' (line ' + lineno + ')';
      }catch(e){}
      console.error('JS error', message, 'at', lineno, colno, error);
      return false;
    };
    // simple page navigation
    document.querySelectorAll('.tab').forEach(t=>t.addEventListener('click', function(){
      document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));
      this.classList.add('active');
      let page = this.getAttribute('data-page');
      document.querySelectorAll('.page').forEach(p=>p.style.display='none');
      document.getElementById('page-'+page).style.display='block';
    }));

    // Start overlay handlers: scan/select/connect WiFi or skip to config
    var hideStartOverlay = function(){ document.getElementById('startOverlay').style.display = 'none'; document.querySelector('.tab.active').click(); };
    var hideWifiModal = function() { document.getElementById('wifiModal').style.display = 'none'; };

    // Bind overlay buttons safely
    var btnNoWifi = document.getElementById('startNoWifiBtn');
    if(btnNoWifi) btnNoWifi.addEventListener('click', function(){
      // skip WiFi: go directly to dashboard (Tableau) page
      hideStartOverlay();
      var dashTab = document.querySelector('.tab[data-page="dashboard"]'); if(dashTab) dashTab.click();
    });
    var btnWifi = document.getElementById('startWifiBtn');
    if(btnWifi) btnWifi.addEventListener('click', function(){
      var sc = document.getElementById('scanContainer'); if(sc) sc.style.display = 'block';
      try{ doScan(); }catch(e){ console.error('doScan failed', e); }
    });

    document.getElementById('refreshScanBtn').onclick = function(){ doScan(); };
    document.getElementById('closeWifiModalBtn').onclick = hideWifiModal;
    document.getElementById('cancelWifiModalBtn').onclick = hideWifiModal;

    document.getElementById('toggleShowPassBtn').onclick = function() {
      var passInput = document.getElementById('selPass');
      if (passInput.type === 'password') {
        passInput.type = 'text';
        this.innerText = '🔒';
      } else {
        passInput.type = 'password';
        this.innerText = '👁️';
      }
    };

    var getWifiIcon = function(rssi, secure) {
      var color = '#EF4444'; // poor
      if (rssi >= -55) color = '#06B6D4'; // excellent (cyan)
      else if (rssi >= -70) color = '#10B981'; // good (green)
      else if (rssi >= -85) color = '#F59E0B'; // fair (orange)
      
      var lockSvg = secure ? '<svg class="icon-lock" viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg>' : '';
      var wifiSvg = '<svg class="icon-svg" viewBox="0 0 24 24" style="fill: ' + color + ';"><path d="M12 21l-12-14.3c.7-.6 5-4.7 12-4.7s11.3 4.1 12 4.7l-12 14.3z"/></svg>';
      return '<div class="net-icons">' + lockSvg + wifiSvg + '</div>';
    };

    var doScan = function(){
      document.getElementById('netList').innerHTML = '<div class="muted" style="padding: 16px; text-align:center;">Recherche des réseaux...</div>';
      fetch('/scan_wifi').then(r=>{ if(!r.ok) throw r.status; return r.json(); }).then(list=>{
        if(!list || list.length==0){ document.getElementById('netList').innerHTML = '<div class="muted" style="padding: 16px; text-align:center;">Aucun réseau trouvé</div>'; return; }
        let html='';
        list.sort((a,b)=>b.rssi - a.rssi);
        list.forEach(n=>{
          html += '<div class="net-row" data-ssid="' + n.ssid + '"><div class="net-details"><div class="net-name">' + n.ssid + '</div><div class="net-rssi-val">' + n.rssi + ' dBm</div></div>' + getWifiIcon(n.rssi, n.secure) + '</div>';
        });
        document.getElementById('netList').innerHTML = html;
        document.querySelectorAll('.net-row').forEach(row => row.addEventListener('click', function(){
          var ssid = this.getAttribute('data-ssid');
          document.getElementById('selSsid').value = ssid;
          document.getElementById('selPass').value = '';
          document.getElementById('overlayWifiStatus').innerText = '';
          document.getElementById('toggleShowPassBtn').innerText = '👁️';
          document.getElementById('selPass').type = 'password';
          document.getElementById('wifiModal').style.display = 'flex';
        }));
      }).catch(e=>{ document.getElementById('netList').innerHTML = '<div class="muted" style="padding: 16px; text-align:center;">Scan error</div>'; });
    }

    document.getElementById('overlayConnectBtn').onclick = function(){
      var ssid = document.getElementById('selSsid').value.trim();
      var pass = document.getElementById('selPass').value || '';
      if(!ssid) return alert('Choisissez un SSID');
      document.getElementById('overlayWifiStatus').innerText = 'Connexion en cours...';
      document.getElementById('overlayConnectBtn').disabled = true;
      var spinner = document.getElementById('connectSpinner');
      if(spinner) spinner.style.display = 'inline-block';
      fetch('/connect_wifi', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ ssid: ssid, pass: pass }) }).then(r=>r.text()).then(t=>{
        document.getElementById('overlayWifiStatus').innerText = t;
        // on success, hide overlay and open dashboard, refresh location/status
        if(t && (t.indexOf('Connected')>=0 || t.indexOf('Already connected')>=0)){
          setTimeout(()=>{
            hideWifiModal();
            hideStartOverlay();
            document.querySelector('.tab[data-page="dashboard"]').click();
            // hide Wi-Fi auto block in advanced page as it's now redundant
            var wab = document.getElementById('wifiAutoBlock'); if(wab) wab.style.display='none';
            // refresh UI and fetch stored location to show in dashboard
            refreshAll();
            fetch('/show_loc').then(r=>r.json()).then(j=>{ if(j && j.lat){ document.getElementById('quick_loc').innerText = j.lat+','+j.lon; } }).catch(e=>{});
          }, 1200);
        }
      }).catch(e=>{ document.getElementById('overlayWifiStatus').innerText = 'Erreur'; }).finally(()=>{
        document.getElementById('overlayConnectBtn').disabled = false;
        if(spinner) spinner.style.display = 'none';
      });
    };

    // reuse existing handlers (re-bind buttons to new IDs)
    // Geolocation via browser removed for security reasons; manual entry only

    document.getElementById('manualBtn').onclick = function(){
      var lat = parseFloat(document.getElementById('latInput').value);
      var lon = parseFloat(document.getElementById('lonInput').value);
      var acc = parseFloat(document.getElementById('accInput').value) || 9999;
      if(isNaN(lat) || isNaN(lon)){
        document.getElementById('manualStatus').innerText = 'Latitude et longitude valides requises.';
        return;
      }
      var data = { lat: lat, lon: lon, accuracy: acc, timestamp: Date.now() };
      fetch('/set_location', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(data) })
        .then(r=>r.text()).then(t=>{ document.getElementById('manualStatus').innerText='Réponse: '+t; refreshAll(); })
        .catch(e=>{ document.getElementById('manualStatus').innerText='Erreur: '+e; });
    };

    var tzSelect = document.getElementById('tzSelect'); if(tzSelect) tzSelect.onchange = function(){ if(this.value){ var tzInput = document.getElementById('tzInput'); if(tzInput) tzInput.value = this.value; } };
    var tzBtnEl = document.getElementById('tzBtn'); if(tzBtnEl) tzBtnEl.onclick = function(){ var tzInput = document.getElementById('tzInput'); var tzStatus = document.getElementById('tzStatus'); var tz = tzInput ? parseInt(tzInput.value) : NaN; if(isNaN(tz)){ if(tzStatus) tzStatus.innerText = 'Offset invalide.'; return; } var data = { tz_min: tz }; fetch('/set_tz', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(data) }).then(r=>r.text()).then(t=>{ if(tzStatus) tzStatus.innerText='Réponse: '+t; refreshAll(); }).catch(e=>{ if(tzStatus) tzStatus.innerText='Erreur: '+e; }); };

    // play test buttons
    var doPlayTest = function(){ fetch('/playtest').then(r=>r.text()).then(t=>{ document.getElementById('playStatus') && (document.getElementById('playStatus').innerText = t); }).catch(e=>{ console.log('play err',e); }); };
    // Test Adhan button moved to Advanced page (binding below)

    // Volume slider handling
    var refreshVolume = function(){ fetch('/get_volume').then(r=>r.json()).then(j=>{ if(j && typeof j.vol !== 'undefined'){ document.getElementById('volSlider').value = j.vol; document.getElementById('volLbl').innerText = j.vol; } }).catch(e=>{}); };
    var volSlider = document.getElementById('volSlider'); if(volSlider) volSlider.oninput = function(){ var volLbl = document.getElementById('volLbl'); if(volLbl) volLbl.innerText = this.value; };
    var volSetBtn = document.getElementById('volSetBtn'); if(volSetBtn) volSetBtn.onclick = function(){ var vs = document.getElementById('volSlider'); var v = vs ? parseInt(vs.value) : 0; fetch('/set_volume', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ vol: v }) }).then(r=>r.text()).then(t=>{ alert('Volume saved: '+v); }).catch(e=>{ alert('Erreur'); }); };
    refreshVolume();
    // Brightness slider handling
    var refreshBrightness = function(){ fetch('/get_brightness').then(r=>r.json()).then(j=>{ if(j && typeof j.bright !== 'undefined'){ document.getElementById('brightSlider').value = j.bright; document.getElementById('brightLbl').innerText = j.bright+'%'; } }).catch(e=>{}); };
    var brightSlider = document.getElementById('brightSlider'); if(brightSlider) brightSlider.oninput = function(){ var brightLbl = document.getElementById('brightLbl'); if(brightLbl) brightLbl.innerText = this.value+'%'; };
    var brightSetBtn = document.getElementById('brightSetBtn'); if(brightSetBtn) brightSetBtn.onclick = function(){ var bs = document.getElementById('brightSlider'); var b = bs ? parseInt(bs.value) : 50; fetch('/set_brightness', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ bright: b }) }).then(r=>r.text()).then(t=>{ alert('Luminosité appliquée: '+b+'%'); refreshBrightness(); }).catch(e=>{ alert('Erreur'); }); };
    refreshBrightness();
    // Test track buttons
    var testTrack1Btn = document.getElementById('testTrack1Btn'); if(testTrack1Btn) testTrack1Btn.onclick = function(){ fetch('/play?track=1').then(r=>r.text()).then(t=>{ console.log('Playing track 1:', t); }).catch(e=>{ alert('Erreur lecture piste 1'); }); };
    var testTrack2Btn = document.getElementById('testTrack2Btn'); if(testTrack2Btn) testTrack2Btn.onclick = function(){ fetch('/play?track=2').then(r=>r.text()).then(t=>{ console.log('Playing track 2:', t); }).catch(e=>{ alert('Erreur lecture piste 2'); }); };
    var testTrack3Btn = document.getElementById('testTrack3Btn'); if(testTrack3Btn) testTrack3Btn.onclick = function(){ fetch('/play?track=3').then(r=>r.text()).then(t=>{ console.log('Playing track 3:', t); }).catch(e=>{ alert('Erreur lecture piste 3'); }); };
    var stopTestBtn = document.getElementById('stopTestBtn'); if(stopTestBtn) stopTestBtn.onclick = function(){ fetch('/stopplay').then(r=>r.text()).then(t=>{ console.log('Stopped:', t); }).catch(e=>{ alert('Erreur arrêt'); }); };

    // advanced actions
    var setrtcBtn = document.getElementById('setrtcBtn'); if(setrtcBtn) setrtcBtn.onclick = function(){ fetch('/setrtc').then(r=>r.text()).then(t=>{ alert(t); refreshAll(); }).catch(e=>{ alert('Erreur'); }); };
    var setRtcManualBtn = document.getElementById('setRtcManualBtn');
    if(setRtcManualBtn) setRtcManualBtn.onclick = function(){
      var dateEl = document.getElementById('rtcDate'); var timeEl = document.getElementById('rtcTimeInput');
      var d = dateEl ? dateEl.value : '';
      var t = timeEl ? timeEl.value : '';
      if(!d){ alert('Choisir une date'); return; }
      // time optional, default to 00:00:00
      if(!t) t = '00:00:00';
      var payload = JSON.stringify({ date: d, time: t });
      fetch('/set_rtc_manual', { method: 'POST', headers: {'Content-Type':'application/json'}, body: payload }).then(r=>r.text()).then(txt=>{ alert(txt); refreshAll(); }).catch(e=>{ alert('Erreur: '+e); });
    };
    var setAlarmTestBtn = document.getElementById('setAlarmTest'); if(setAlarmTestBtn) setAlarmTestBtn.onclick = function(){ fetch('/set_alarm_test').then(r=>r.text()).then(t=>{ alert(t); refreshAll(); }).catch(e=>{ alert('Erreur'); }); };
    var cancelAlarmsBtn = document.getElementById('cancelAlarms'); if(cancelAlarmsBtn) cancelAlarmsBtn.onclick = function(){ fetch('/cancel_alarms').then(r=>r.text()).then(t=>{ alert(t); refreshAll(); }).catch(e=>{ alert('Erreur'); }); };
    var openAPBtn = document.getElementById('openAP'); if(openAPBtn) openAPBtn.onclick = function(){ alert('La page de configuration est déjà ouverte via cet AP.'); };
    var ledTestBtn = document.getElementById('ledTestBtn'); if(ledTestBtn) ledTestBtn.onclick = function(){ fetch('/led_test').then(r=>r.text()).then(t=>{ alert(t); refreshAll(); }).catch(e=>{ alert('Erreur'); }); };
    var setSceneBtn = document.getElementById('setSceneBtn');
    var ledSceneSelect = document.getElementById('ledSceneSelect');
    if(setSceneBtn) setSceneBtn.onclick = function(){
      var s = ledSceneSelect ? ledSceneSelect.value : '0';
      // Preview the selected scene for 2.5s (does not persist)
      fetch('/set_led?scene='+encodeURIComponent(s)+'&preview=1').then(r=>r.text()).then(t=>{
        // short visual confirmation
        console.log('Previewing scene', s, t);
        // after 2.5s restore the config blink indicator (BLINK_INDEX = 7)
        setTimeout(function(){ fetch('/set_led?scene=7&preview=1').then(()=>{ refreshAll(); }).catch(()=>{ refreshAll(); }); }, 2500);
      }).catch(e=>{ alert('Erreur'); });
    };
    // Dashboard scene controls
    var dashSetSceneBtn = document.getElementById('dashSetSceneBtn');
    var dashLedSelect = document.getElementById('dashLedSelect');
    if(dashSetSceneBtn){
      dashSetSceneBtn.onclick = function(){
        var s = dashLedSelect ? dashLedSelect.value : '0';
        fetch('/set_led?scene='+encodeURIComponent(s)).then(r=>r.text()).then(t=>{ alert('Scène appliquée'); refreshAll(); }).catch(e=>{ alert('Erreur'); });
      };
    }
    var dashStopAPBtn = document.getElementById('dashStopAPBtn'); if(dashStopAPBtn) dashStopAPBtn.onclick = function(){ fetch('/stop_ap').then(r=>r.text()).then(t=>{ alert('Fin de configuration: '+t); }).catch(e=>{ alert('Erreur arrêt AP'); }); };
    var ledOffBtn = document.getElementById('ledOffBtn'); if(ledOffBtn) ledOffBtn.onclick = function(){ fetch('/led_off').then(r=>r.text()).then(t=>{ alert(t); refreshAll(); }).catch(e=>{ alert('Erreur'); }); };
    var advPlayTestBtn = document.getElementById('advPlayTestBtn'); if(advPlayTestBtn) advPlayTestBtn.onclick = doPlayTest;
    var recalcTimesBtn = document.getElementById('recalcTimesBtn'); if(recalcTimesBtn) recalcTimesBtn.onclick = function(){ refreshAll(); alert('Horaires recalculés (si localisation stockée).'); };
    var dumpBtn = document.getElementById('dumpStatusBtn');
    if(dumpBtn){
      dumpBtn.onclick = function(){ var dumpArea = document.getElementById('dumpArea'); if(dumpArea) dumpArea.innerText = 'Fetching...'; fetch('/dump_status').then(r=>r.json()).then(j=>{ if(dumpArea) dumpArea.innerText = JSON.stringify(j, null, 2); }).catch(e=>{ if(dumpArea) dumpArea.innerText = 'Error'; }); };
    }
    var finishConfigBtn = document.getElementById('finishConfigBtn'); if(finishConfigBtn) finishConfigBtn.onclick = function(){ fetch('/stop_ap').then(r=>r.text()).then(t=>{ alert('Fin de configuration: '+t); }).catch(e=>{ alert('Erreur arrêt AP'); }); };
    // Toggle to show/hide the Wi-Fi auto-localisation block (useful if hidden)
    var showWifiAutoBtn = document.getElementById('showWifiAutoBtn');
    if(showWifiAutoBtn){
      showWifiAutoBtn.onclick = function(){
        var wab = document.getElementById('wifiAutoBlock');
        if(!wab){ alert('Bloc wifiAutoBlock introuvable'); return; }
        wab.style.display = (wab.style.display === 'none' || wab.style.display === '') ? 'block' : 'none';
        // scroll to it if now visible
        if(wab.style.display === 'block') wab.scrollIntoView({behavior: 'smooth', block: 'center'});
      };
    }
    // Wi-Fi connect & auto-locate
    var wifiConnectBtn = document.getElementById('wifiConnectBtn'); if(wifiConnectBtn) wifiConnectBtn.onclick = function(){ var ssidEl = document.getElementById('wifiSsid'); var passEl = document.getElementById('wifiPass'); var statusEl = document.getElementById('wifiStatus'); var ssid = ssidEl ? ssidEl.value.trim() : ''; var pass = passEl ? passEl.value : ''; if(!ssid){ alert('Please enter SSID'); return; } if(statusEl) statusEl.innerText = 'Connecting...'; fetch('/connect_wifi', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ ssid: ssid, pass: pass }) }).then(r=>r.text()).then(t=>{ if(statusEl) statusEl.innerText = t; refreshAll(); }).catch(e=>{ if(statusEl) statusEl.innerText = 'Error'; }); };
    var wifiDisconnectBtn = document.getElementById('wifiDisconnectBtn'); if(wifiDisconnectBtn) wifiDisconnectBtn.onclick = function(){ var statusEl = document.getElementById('wifiStatus'); fetch('/disconnect_wifi').then(r=>r.text()).then(t=>{ if(statusEl) statusEl.innerText = t; refreshAll(); }).catch(e=>{ if(statusEl) statusEl.innerText='Error'; }); };
    var saveBtn = document.getElementById('saveGeoKeyBtn');
    if(saveBtn){
      saveBtn.onclick = function(){ var keyEl = document.getElementById('geoKeyInput'); var geoStatusEl = document.getElementById('geoStatus'); var k = keyEl ? keyEl.value.trim() : ''; if(!k){ alert('Enter key'); return; } fetch('/set_geo_key', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ key: k }) }).then(r=>r.text()).then(t=>{ if(geoStatusEl) geoStatusEl.innerText = t; }).catch(e=>{ if(geoStatusEl) geoStatusEl.innerText = 'Error'; }); };
    }
    var locBtn = document.getElementById('locAutoBtn');
    if(locBtn){
      locBtn.onclick = function(){ var locAutoStatus = document.getElementById('locAutoStatus'); if(locAutoStatus) locAutoStatus.innerText = 'Locating...'; fetch('/geo_wifi').then(r=>{ if(!r.ok) throw r.status; return r.json(); }).then(j=>{ if(j.lat){ if(locAutoStatus) locAutoStatus.innerText = 'Located: '+j.lat+','+j.lon; var q = document.getElementById('quick_loc'); if(q) q.innerText = j.lat+','+j.lon; refreshAll(); } else if(locAutoStatus) locAutoStatus.innerText='No result'; }).catch(e=>{ if(locAutoStatus) locAutoStatus.innerText='Error'; }); };
    }

    // RTC and prayer times polling (defensive: avoid exceptions if elements are missing or fetch fails)
    var updateRTCTime = function(){
      fetch('/rtc_time')
        .then(function(r){ if(!r.ok) throw new Error('HTTP '+r.status); return r.text(); })
        .then(function(t){ var el = document.getElementById('rtcTime'); if(el) el.innerText = t; var aside = document.getElementById('aside_rtc'); if(aside) aside.innerText = t; })
        .catch(function(e){ var el = document.getElementById('rtcTime'); if(el) el.innerText = 'Erreur'; var aside = document.getElementById('aside_rtc'); if(aside) aside.innerText = 'Erreur'; if(window && window.console) console.log('updateRTCTime error', e); });
    };
    var rtcRefreshBtn = document.getElementById('rtcRefresh'); if(rtcRefreshBtn) rtcRefreshBtn.onclick = updateRTCTime;
    setInterval(updateRTCTime, 5000);
    updateRTCTime();

    var updatePrayerTimes = function(){ fetch('/prayer_times').then(r=>r.json()).then(j=>{ if(j.error){ var el = document.getElementById('page-prayers'); if(el) el.querySelector('.small').innerText = 'Erreur: '+j.error; return; } var pf = document.getElementById('p_fajr'); if(pf) pf.innerText = j.fajr; var ps = document.getElementById('p_sunrise'); if(ps) ps.innerText = j.sunrise; var pd = document.getElementById('p_dhuhr'); if(pd) pd.innerText = j.dhuhr; var pa = document.getElementById('p_asr'); if(pa) pa.innerText = j.asr; var pm = document.getElementById('p_maghrib'); if(pm) pm.innerText = j.maghrib; var pi = document.getElementById('p_isha'); if(pi) pi.innerText = j.isha; var tzu = document.getElementById('tzUsed'); if(tzu) tzu.innerText = j.tz_min; var tzs = document.getElementById('tzSource'); if(tzs) tzs.innerText = j.tz_source; var aside = document.getElementById('aside_next'); if(aside){ if(typeof j.next !== 'undefined') aside.innerText = j.next; else aside.innerText = j.dhuhr; } var qt = document.getElementById('quick_tz'); if(qt) qt.innerText = j.tz_min; // also update dashboard compact view if present
      var d_pf = document.getElementById('dash_p_fajr'); if(d_pf) d_pf.innerText = j.fajr;
      var d_pd = document.getElementById('dash_p_dhuhr'); if(d_pd) d_pd.innerText = j.dhuhr;
      var d_pa = document.getElementById('dash_p_asr'); if(d_pa) d_pa.innerText = j.asr;
      var d_pm = document.getElementById('dash_p_maghrib'); if(d_pm) d_pm.innerText = j.maghrib;
      var d_pi = document.getElementById('dash_p_isha'); if(d_pi) d_pi.innerText = j.isha;
    }).catch(e=>{ /* ignore */ }); };
    setInterval(updatePrayerTimes, 10000); updatePrayerTimes();
    // On load show stored location (if any) and populate inputs
    fetch('/show_loc').then(r=>r.json()).then(j=>{
      if(j && j.lat){
        document.getElementById('quick_loc').innerText = j.lat+','+j.lon;
        var li = document.getElementById('latInput'); if(li) li.value = j.lat;
        var lo = document.getElementById('lonInput'); if(lo) lo.value = j.lon;
        var ac = document.getElementById('accInput'); if(ac) ac.value = j.acc || '';
      } else {
        document.getElementById('quick_loc').innerText = 'Non configurée';
      }
    }).catch(e=>{ document.getElementById('quick_loc').innerText = 'Erreur'; });
    
    // convenience refresh after changes (hoisted so handlers can call it earlier)
    function refreshAll(){ updateRTCTime(); updatePrayerTimes(); }

  </script>
</body>
</html>
 )HTML";

// Helpers to get request body robustly
static String getRequestBody() {
  if (server.hasArg("plain")) return server.arg("plain");
  if (server.args() > 0) return server.arg(0);
  return "";
}

// Helpers to parse simple JSON payload without ArduinoJson
static double parseJsonValue(const String &s, const char *key) {
  int k = s.indexOf(String('"') + String(key) + String('"'));
  if (k < 0) k = s.indexOf(String(key));
  if (k < 0) return NAN;
  int colon = s.indexOf(':', k);
  if (colon < 0) return NAN;
  int start = colon + 1;
  // skip spaces and optional quotes
  while (start < s.length() && (s[start] == ' ' || s[start] == '\"')) start++;
  int end = start;
  while (end < s.length() && ((s[end] >= '0' && s[end] <= '9') || s[end] == '.' || s[end] == '-' || s[end] == '+' || s[end] == 'e' || s[end] == 'E')) end++;
  String num = s.substring(start, end);
  return num.toFloat();
}

static String parseJsonString(const String &s, const char *key) {
  int k = s.indexOf(String('"') + String(key) + String('"'));
  if (k < 0) k = s.indexOf(String(key));
  if (k < 0) return "";
  int colon = s.indexOf(':', k);
  if (colon < 0) return "";
  int q1 = s.indexOf('"', colon + 1);
  if (q1 < 0) return "";
  int q2 = s.indexOf('"', q1 + 1);
  if (q2 < 0) return "";
  return s.substring(q1 + 1, q2);
}

void handleRoot() {
  // Prevent browsers from caching the configuration page so updates appear immediately
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.sendHeader("Pragma", "no-cache");
  server.sendHeader("Expires", "0");
  server.send_P(200, "text/html", index_html);
}

void handleSetLocation() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  String body = getRequestBody();
  double lat = parseJsonValue(body, "lat");
  double lon = parseJsonValue(body, "lon");
  double acc = parseJsonValue(body, "accuracy");
  unsigned long ts = (unsigned long)parseJsonValue(body, "timestamp");
  if (isnan(lat) || isnan(lon)) {
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  prefs.begin("adhancfg", false);
  prefs.putString("lat", String(lat, 6));
  prefs.putString("lon", String(lon, 6));
  prefs.putString("acc", String(acc));
  prefs.putULong("ts", ts);
  prefs.end();
  server.send(200, "text/plain", "Position enregistrée");
  Serial.printf("Stored location: %f , %f (acc=%f)\n", lat, lon, acc);
}

void handleSetTZ() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  if (!requireApiKey()) return;
  String body = getRequestBody();
  double tz = parseJsonValue(body, "tz_min");
  if (isnan(tz)) {
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  prefs.begin("adhancfg", false);
  prefs.putInt("tz_offset_min", (int)tz);
  prefs.end();
  server.send(200, "text/plain", "Timezone offset saved");
  Serial.printf("Stored tz_offset_min=%d\n", (int)tz);
}

void handlePlayTest() {
  server.send(200, "text/plain", "Playing test track");
  // play track 1 as test
  if (dfAvailable) dfplayer.playMp3Folder(1);
}

// HTTP handlers implementing serial commands
void handleSetRTC() {
  if (!requireApiKey()) return;
  if (!rtc.begin()) {
    server.send(200, "text/plain", "RTC not present");
    return;
  }
  rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  scheduleNextPrayerAlarm();
  server.send(200, "text/plain", "RTC set to compile time");
}

// Set RTC manually via POST JSON { "date": "YYYY-MM-DD", "time": "HH:MM:SS" }
void handleSetRtcManual() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  String body = getRequestBody();
  String dateStr = "";
  String timeStr = "";
  int p = body.indexOf("\"date\"");
  if (p >= 0) {
    int c = body.indexOf(':', p);
    int q1 = body.indexOf('"', c);
    int q2 = body.indexOf('"', q1 + 1);
    if (q1 >= 0 && q2 > q1) dateStr = body.substring(q1 + 1, q2);
  }
  p = body.indexOf("\"time\"");
  if (p >= 0) {
    int c = body.indexOf(':', p);
    int q1 = body.indexOf('"', c);
    int q2 = body.indexOf('"', q1 + 1);
    if (q1 >= 0 && q2 > q1) timeStr = body.substring(q1 + 1, q2);
  }
  if (dateStr.length() == 0) {
    server.send(400, "text/plain", "Missing date");
    return;
  }
  // parse date YYYY-MM-DD
  if (dateStr.length() < 10) {
    server.send(400, "text/plain", "Invalid date format");
    return;
  }
  int y = dateStr.substring(0, 4).toInt();
  int m = dateStr.substring(5, 7).toInt();
  int d = dateStr.substring(8, 10).toInt();
  int hh = 0, mm = 0, ss = 0;
  if (timeStr.length() >= 5) {  // HH:MM or HH:MM:SS
    hh = timeStr.substring(0, 2).toInt();
    mm = timeStr.substring(3, 5).toInt();
    if (timeStr.length() >= 8) ss = timeStr.substring(6, 8).toInt();
  }
  if (!rtc.begin()) {
    server.send(500, "text/plain", "RTC not present");
    return;
  }
  DateTime dt;
  try {
    dt = DateTime(y, m, d, hh, mm, ss);
  } catch (...) {
    server.send(400, "text/plain", "Invalid date/time");
    return;
  }
  rtc.adjust(dt);
  scheduleNextPrayerAlarm();
  char buf[64];
  snprintf(buf, sizeof(buf), "RTC set to %04d-%02d-%02d %02d:%02d:%02d", y, m, d, hh, mm, ss);
  server.send(200, "text/plain", String(buf));
  Serial.println(buf);
}

void handleSetAlarmTest() {
  if (!rtc.begin()) {
    server.send(200, "text/plain", "RTC not present");
    return;
  }
  DateTime now = rtc.now();
  int mm = (now.minute() + 1) % 60;
  int hh = now.hour() + (now.minute() == 59 ? 1 : 0);
  ds3231SetAlarm2Daily(hh % 24, mm);
  scheduledPrayerIndex = 1;
  scheduledPrayerTime = DateTime(now.year(), now.month(), now.day(), hh % 24, mm, 0);

  // Clear last trigger NVS to ensure the test alarm fires
  prefs.begin("adhancfg", false);
  prefs.putInt("last_trig_idx", 0);
  prefs.putInt("last_trig_day", 0);
  prefs.putInt("last_trig_mon", 0);
  prefs.putInt("last_trig_yr", 0);
  prefs.end();

  char buf[64];
  snprintf(buf, sizeof(buf), "Test alarm set for %02d:%02d", hh % 24, mm);
  server.send(200, "text/plain", buf);
}

void handleCancelAlarms() {
  ds3231DisableAlarms();
  server.send(200, "text/plain", "DS3231 alarms disabled");
}

void handleShowNextAlarm() {
  if (scheduledPrayerIndex > 0) {
    char buf[128];
    snprintf(buf, sizeof(buf), "%d|%04u-%02u-%02u %02d:%02d", scheduledPrayerIndex, scheduledPrayerTime.year(), scheduledPrayerTime.month(), scheduledPrayerTime.day(), scheduledPrayerTime.hour(), scheduledPrayerTime.minute());
    server.send(200, "text/plain", buf);
  } else {
    server.send(200, "text/plain", "none");
  }
}

void handleShowLoc() {
  double lat, lon, acc;
  if (loadStoredLocation(lat, lon, acc)) {
    char buf[128];
    snprintf(buf, sizeof(buf), "{\"lat\":%.6f,\"lon\":%.6f,\"acc\":%.1f}", lat, lon, acc);
    server.send(200, "application/json", String(buf));
  } else {
    server.send(200, "application/json", "{}");
  }
}

void handleShowTime() {
  if (!rtc.begin()) {
    server.send(200, "text/plain", "RTC not present");
    return;
  }
  DateTime now = rtc.now();
  char buf[64];
  snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
  server.send(200, "text/plain", buf);
}

void handlePlayTrack() {
  String t = server.arg("track");
  int track = t.length() ? t.toInt() : 1;

  Serial.printf("handlePlayTrack: track=%d, dfAvailable=%d\n", track, dfAvailable);

  if (!dfAvailable) {
    Serial.println("DFPlayer not available, attempting recovery...");
    if (!tryRecoverDFPlayer(3)) {
      server.send(503, "text/plain", "DFPlayer not available and recovery failed");
      return;
    }
  }

  if (dfAvailable) {
    Serial.printf("Playing track %d\n", track);
    dfplayer.playMp3Folder(track);
    isPlaying = true;
    server.send(200, "text/plain", "Playing");
  } else {
    server.send(503, "text/plain", "DFPlayer not available");
  }
}

void handleStopPlay() {
  stopPlay();
  server.send(200, "text/plain", "Stopped");
}

// Set volume via POST JSON {"vol":number}
void handleSetVolume() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  String body = getRequestBody();
  double v = parseJsonValue(body, "vol");
  if (isnan(v)) {
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  int vol = (int)round(v);
  if (vol < 0) vol = 0;
  if (vol > 30) vol = 30;
  prefs.begin("adhancfg", false);
  prefs.putInt("volume", vol);
  prefs.end();
  if (dfAvailable) { dfplayer.volume(vol); }
  server.send(200, "text/plain", "OK");
  Serial.printf("Volume set to %d via HTTP\n", vol);
}

// Return stored volume as JSON {"vol":N}
void handleGetVolume() {
  prefs.begin("adhancfg", true);
  int vol = prefs.getInt("volume", 20);
  prefs.end();
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"vol\":%d}", vol);
  server.send(200, "application/json", String(buf));
}

// Set brightness via POST JSON {"bright":number}
void handleSetBrightness() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  String body = getRequestBody();
  double b = parseJsonValue(body, "bright");
  if (isnan(b)) {
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  int bright = (int)round(b);
  if (bright < 0) bright = 0;
  if (bright > 100) bright = 100;
  ledBrightness = bright;
  prefs.begin("adhancfg", false);
  prefs.putInt("brightness", bright);
  prefs.end();
  server.send(200, "text/plain", "OK");
  Serial.printf("Brightness set to %d%% via HTTP\n", bright);
}

// Return stored brightness as JSON {"bright":N}
void handleGetBrightness() {
  prefs.begin("adhancfg", true);
  int bright = prefs.getInt("brightness", 50);
  prefs.end();
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"bright\":%d}", bright);
  server.send(200, "application/json", String(buf));
}

// ===== API Handlers for Flutter App (JSON wrappers) =====

// Set LED scenario via POST JSON {"scenario": number}
void handleSetLedScenario() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  String body = getRequestBody();
  double sc = parseJsonValue(body, "scenario");
  if (isnan(sc)) {
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  int scenario = (int)round(sc);
  if (scenario < 0 || scenario >= TOTAL_SCENES) {
    server.send(400, "text/plain", "Invalid scenario");
    return;
  }

  ledScenario = scenario;
  if (ledScenario == 0) {
    setLedDuty(0);
    if (useAddressableLEDs) stripSetAll(0, 0, 0);
  } else {
    setLedDuty(128);
  }

  prefs.begin("adhancfg", false);
  prefs.putInt("led_scenario", ledScenario);
  prefs.end();

  Serial.printf("LED scenario set to %d via API\n", scenario);
  server.send(200, "application/json", String("{\"scenario\":") + scenario + "}");
}

// LED test handler: starts a short blink for 5 seconds and returns status
void handleLedTest() {
  // start blinking for 5 seconds
  if (ledTestUntil == 0) {
    prevLedScenario = ledScenario;
  }
  ledScenario = 2;  // blink
  ledTestUntil = millis() + 5000UL;
  server.send(200, "text/plain", "LED test started for 5s");
  Serial.println("LED test triggered via HTTP");
}

// Set LED scenario via query ?scene=N
void handleSetLed() {
  String s = server.arg("scene");
  if (s.length() == 0) {
    server.send(400, "text/plain", "Missing scene");
    return;
  }
  int sc = s.toInt();
  if (sc < 0 || sc >= TOTAL_SCENES) {
    server.send(400, "text/plain", "Invalid scene");
    return;
  }
  ledScenario = sc;
  if (ledScenario == 0) {
    setLedDuty(0);
    if (useAddressableLEDs) stripSetAll(0, 0, 0);
  } else {
    setLedDuty(128);
  }
  // If this is a preview (preview=1) do not persist the choice to prefs
  String pv = server.arg("preview");
  bool isPreview = (pv == "1" || pv.equalsIgnoreCase("true"));
  if (!isPreview) {
    prefs.begin("adhancfg", false);
    prefs.putInt("led_scenario", ledScenario);
    prefs.end();
  }
  Serial.printf("LED scenario set via HTTP: %d (preview=%d)\n", ledScenario, isPreview ? 1 : 0);
  server.send(200, "text/plain", String("OK: ") + ledScenario + (isPreview ? " (preview)" : ""));
}

// Turn off LEDs
void handleLedOff() {
  ledScenario = 0;
  setLedDuty(0);
  if (useAddressableLEDs) stripSetAll(0, 0, 0);
  if (useAddressableLEDs) clearStrip();
  prefs.begin("adhancfg", false);
  prefs.putInt("led_scenario", ledScenario);
  prefs.end();
  Serial.println("LEDs turned off via HTTP");
  server.send(200, "text/plain", "LEDs off");
}

// Return current RTC time as plain text (YYYY-MM-DD HH:MM:SS) and tz offset if set
void handleGetRTC() {
  Serial.println("HTTP GET /rtc_time -> handleGetRTC called");
  if (!rtc.begin()) {
    Serial.println("handleGetRTC: rtc.begin() failed");
    server.send(200, "text/plain", "RTC not present");
    return;
  }
  DateTime now = rtc.now();
  char buf[64];
  snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
  // append tz info if stored
  prefs.begin("adhancfg", true);
  int tz = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  String out = String(buf);
  if (tz != 0x7fffffff) {
    char tzb[32];
    snprintf(tzb, sizeof(tzb), " (UTC%+d)", tz / 60);
    out += String(tzb);
  }
  Serial.printf("handleGetRTC: returning '%s'\n", out.c_str());
  server.send(200, "text/plain", out);
}

// forward declaration so it can be registered earlier
void handlePrayerTimes();

// Try to fetch location from ip-api.com and store in prefs. Returns true on success.


// Handler to connect to WiFi (POST JSON {"ssid":"...","pass":"..."})
// Returns 202 immediately — loop() drives the actual connection.
// Poll GET /api/wifi/status to track progress.
void handleConnectWifi() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  // Pas d'auth sur cet endpoint : accessible uniquement en étant sur le réseau AP/local
  String body = getRequestBody();
  // Do not log body — contains WiFi password

  String ssid = "", pass = "";
  int i1 = body.indexOf("ssid");
  int i2 = body.indexOf("pass");
  auto extractVal = [&](int keyPos, String &out) {
    if (keyPos < 0) return;
    int colon = body.indexOf(':', keyPos);
    if (colon < 0) return;
    int fq = body.indexOf('"', colon);
    if (fq >= 0) {
      int sq = body.indexOf('"', fq + 1);
      if (sq > fq) out = body.substring(fq + 1, sq);
    } else {
      int endp = body.indexOf(',', colon);
      if (endp < 0) endp = body.indexOf('}', colon);
      if (endp > colon) {
        out = body.substring(colon + 1, endp);
        out.trim();
      }
    }
  };
  extractVal(i1, ssid);
  extractVal(i2, pass);

  Serial.printf("Parsed SSID='%s' PASS len=%u\n", ssid.c_str(), (unsigned)pass.length());
  if (ssid.length() == 0) {
    server.send(400, "text/plain", "Missing SSID");
    return;
  }

  // If already connected to the same SSID, return OK immediately
  if (WiFi.status() == WL_CONNECTED && WiFi.SSID() == ssid) {
    server.send(200, "application/json",
                "{\"status\":\"connected\",\"ip\":\"" + WiFi.localIP().toString() + "\",\"ssid\":\"" + ssid + "\"}");
    return;
  }

  // Queue the async connect
  wifiConnectSSID = ssid;
  wifiConnectPass = pass;
  wifiConnectState = WCS_CONNECTING;
  wifiConnectStart = millis();

  WiFi.disconnect(true);
  delay(100);
  WiFi.mode(WIFI_AP_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(ssid.c_str(), pass.c_str());
  Serial.printf("Async WiFi connect started for '%s'\n", ssid.c_str());

  server.send(202, "application/json", "{\"status\":\"connecting\"}");
}

// GET /api/wifi/status — returns current WiFi state for app polling
void handleWifiStatus() {
  String status;
  String ip = "";
  String ssid = "";
  switch (wifiConnectState) {
    case WCS_CONNECTING: status = "connecting"; break;
    case WCS_CONNECTED:
      status = "connected";
      ip = WiFi.localIP().toString();
      ssid = WiFi.SSID();
      break;
    case WCS_FAILED: status = "failed"; break;
    default:
      if (WiFi.status() == WL_CONNECTED) {
        status = "connected";
        ip = WiFi.localIP().toString();
        ssid = WiFi.SSID();
      } else status = "idle";
  }
  char buf[256];
  snprintf(buf, sizeof(buf),
           "{\"status\":\"%s\",\"ip\":\"%s\",\"ssid\":\"%s\"}",
           status.c_str(), ip.c_str(), ssid.c_str());
  server.send(200, "application/json", buf);
}

// Scan for nearby WiFi networks and return JSON array
void handleScanWifi() {
  if (server.method() != HTTP_GET) {
    server.send(405, "text/plain", "Method not allowed");
    return;
  }
  int n = WiFi.scanNetworks();
  String out = "[";
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    int rssi = WiFi.RSSI(i);
    int enc = (int)WiFi.encryptionType(i);
    // escape quotes in SSID
    ss.replace("\"", "\\\"");
    out += "{\"ssid\":\"" + ss + "\",\"rssi\":" + String(rssi) + ",\"secure\":" + String(enc != WIFI_AUTH_OPEN ? 1 : 0) + "}";
    if (i < n - 1) out += ",";
  }
  out += "]";
  server.send(200, "application/json", out);
}

// OTA update via HTTP multipart upload (POST /ota/upload)
void handleOtaUpload() {
  // Verify authorization at the start of the upload to prevent writing unauthorized chunks
  bool auth = true;
  if (_apiToken.length() > 0 && !apRunning) {
    String key = server.header("X-API-Key");
    if (key.length() == 0) {
      key = server.arg("token");
    }
    if (key != _apiToken) {
      auth = false;
    }
  }

  if (!auth) {
    return;
  }

  HTTPUpload &upload = server.upload();
  if (upload.status == UPLOAD_FILE_START) {
    Serial.printf("OTA upload start: %s (%u bytes)\n", upload.filename.c_str(), upload.totalSize);
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) {
      Update.printError(Serial);
    }
  } else if (upload.status == UPLOAD_FILE_WRITE) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) {
      Update.printError(Serial);
    }
  } else if (upload.status == UPLOAD_FILE_END) {
    if (Update.end(true)) {
      Serial.printf("OTA success: %u bytes written\n", upload.totalSize);
    } else {
      Update.printError(Serial);
    }
  }
}

void handleUpdatePage() {
  String html = R"HTML(
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Mise à jour AdhanBox</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: sans-serif; background: #121212; color: #e0e0e0; text-align: center; padding: 30px; margin: 0; }
    .card { background: #1e1e1e; max-width: 400px; margin: 50px auto; padding: 30px; border-radius: 12px; border: 1px solid #333; box-shadow: 0 4px 12px rgba(0,0,0,0.5); }
    h2 { color: #059669; margin-top: 0; }
    p { font-size: 14px; color: #a0a0a0; line-height: 1.5; }
    input[type=file], input[type=text], input[type=submit] { display: block; width: 100%; margin: 15px 0; padding: 12px; box-sizing: border-box; border-radius: 8px; font-size: 14px; }
    input[type=text] { background: #2a2a2a; border: 1px solid #444; color: #fff; }
    input[type=file] { background: #1a1a1a; border: 1px dashed #555; color: #ccc; cursor: pointer; }
    input[type=submit] { background: #059669; border: none; color: #fff; font-weight: bold; cursor: pointer; transition: background 0.2s; }
    input[type=submit]:hover { background: #047857; }
    .footer { font-size: 11px; color: #555; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>Mise à jour Firmware</h2>
    <p>Sélectionnez le fichier <code>adhanbox.ino.bin</code> compilé pour mettre à jour le logiciel de l'AdhanBox.</p>
    <form method="POST" action="/ota/upload" enctype="multipart/form-data" id="upForm">
      <input type="text" name="token" id="tokenField" placeholder="Clé d'API (Token)">
      <input type="file" name="update" accept=".bin" required>
      <input type="submit" value="Démarrer la mise à jour">
    </form>
    <div class="footer">AdhanBox OTA Manager</div>
    <script>
      fetch('/api/device/info')
        .then(r => r.json())
        .then(j => {
          if (j.token) {
            document.getElementById('tokenField').value = j.token;
          }
        }).catch(() => {});
      
      document.getElementById('upForm').onsubmit = function() {
        var t = document.getElementById('tokenField').value;
        this.action = '/ota/upload?token=' + encodeURIComponent(t);
      };
    </script>
  </div>
</body>
</html>
)HTML";
  server.send(200, "text/html", html);
}

void handleOtaUploadComplete() {
  if (!requireApiKey()) { return; }
  if (Update.hasError()) {
    server.send(500, "application/json", "{\"ok\":false,\"error\":\"Update failed\"}");
  } else {
    server.send(200, "application/json", "{\"ok\":true,\"msg\":\"Firmware updated — rebooting\"}");
    delay(200);
    ESP.restart();
  }
}

// GET /api/firmware/version
void handleFirmwareVersion() {
  server.send(200, "application/json",
              "{\"version\":\"1.4.0\",\"build\":\"" __DATE__ " " __TIME__ "\"}");
}

// Returns true if the request carries the correct API key (or if token not yet set).
// Sends 401 and returns false if check fails. Call at the start of any mutating handler.
bool requireApiKey() {
  if (_apiToken.length() == 0) return true;  // not yet initialized
  if (apRunning) return true;                // AP mode: réseau isolé, pas d'auth nécessaire
  String key = server.header("X-API-Key");
  if (key.length() == 0) {
    key = server.arg("token");
  }
  if (key == _apiToken) return true;
  server.send(401, "application/json", "{\"error\":\"Unauthorized — missing or invalid X-API-Key\"}");
  return false;
}

// GET /api/device/info — unauthenticated bootstrap endpoint.
// Returns the API token so the companion app can pair on first connection.
void handleDeviceInfo() {
  char buf[512];
  snprintf(buf, sizeof(buf),
           "{\"version\":\"1.4.0\",\"hostname\":\"%s\",\"token\":\"%s\",\"ota_pass\":\"%s\"}",
           OTA_HOSTNAME, _apiToken.c_str(), _otaPass.c_str());
  server.send(200, "application/json", buf);
}

// Configure ArduinoOTA (called once WiFi is connected)
void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(_otaPass.c_str());
  ArduinoOTA.onStart([]() {
    Serial.println("ArduinoOTA start");
    // Turn LEDs orange during OTA
    if (useAddressableLEDs) stripSetAll(255, 60, 0);
  });
  ArduinoOTA.onEnd([]() {
    Serial.println("\nArduinoOTA end");
    if (useAddressableLEDs) stripSetAll(0, 255, 0);
  });
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("OTA: %u%%\r", progress * 100 / total);
  });
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("OTA Error[%u]\n", error);
    if (useAddressableLEDs) stripSetAll(255, 0, 0);
  });
  ArduinoOTA.begin();
  Serial.println("ArduinoOTA ready (hostname: adhanbox, use IDE or espota.py)");
}

// Helper function: add offset (in minutes) to time string "HH:MM"
// Returns adjusted time, handling day wraparound
String addMinutesToTime(String timeStr, int offsetMinutes) {
  if (timeStr.length() < 5) return timeStr;  // Invalid format

  int h = timeStr.substring(0, 2).toInt();
  int m = timeStr.substring(3, 5).toInt();

  int totalMinutes = h * 60 + m + offsetMinutes;

  // Handle day wraparound
  while (totalMinutes < 0) totalMinutes += 1440;
  while (totalMinutes >= 1440) totalMinutes -= 1440;

  h = totalMinutes / 60;
  m = totalMinutes % 60;

  char buffer[6];
  sprintf(buffer, "%02d:%02d", h, m);
  return String(buffer);
}

// GET /api/mawaqit/offsets - Return current offsets
void handleMawaqitGetOffsets() {
  prefs.begin("adhancfg", true);
  int fajrOff = prefs.getInt("mq_off_fajr", 0);
  int sunriseOff = prefs.getInt("mq_off_sunrise", 0);
  int dhuhrOff = prefs.getInt("mq_off_dhuhr", 0);
  int asrOff = prefs.getInt("mq_off_asr", 0);
  int maghribOff = prefs.getInt("mq_off_maghrib", 0);
  int ishaOff = prefs.getInt("mq_off_isha", 0);
  prefs.end();

  String json = "{";
  json += "\"fajr\":" + String(fajrOff) + ",";
  json += "\"sunrise\":" + String(sunriseOff) + ",";
  json += "\"dhuhr\":" + String(dhuhrOff) + ",";
  json += "\"asr\":" + String(asrOff) + ",";
  json += "\"maghrib\":" + String(maghribOff) + ",";
  json += "\"isha\":" + String(ishaOff);
  json += "}";

  server.send(200, "application/json", json);
}

// POST /api/mawaqit/offsets - Set time offsets (in minutes) for each prayer
// Body: {"fajr":-5, "sunrise":0, "dhuhr":2, "asr":0, "maghrib":3, "isha":5}
void handleMawaqitSetOffsets() {
  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }

  String body = getRequestBody();
  Serial.print("/api/mawaqit/offsets body: ");
  Serial.println(body);

  // Simple JSON parsing for integers
  auto extractJsonInt = [&](const String &src, const char *key) -> int {
    int k = src.indexOf(String("\"") + key + "\"");
    if (k < 0) return 0;
    int colon = src.indexOf(':', k);
    if (colon < 0) return 0;
    int numStart = colon + 1;
    while (numStart < src.length() && (src.charAt(numStart) == ' ' || src.charAt(numStart) == '\t')) numStart++;
    int numEnd = numStart;
    if (src.charAt(numStart) == '-') numEnd++;
    while (numEnd < src.length() && isDigit(src.charAt(numEnd))) numEnd++;
    if (numEnd <= numStart) return 0;
    return src.substring(numStart, numEnd).toInt();
  };

  int fajrOff = extractJsonInt(body, "fajr");
  int sunriseOff = extractJsonInt(body, "sunrise");
  int dhuhrOff = extractJsonInt(body, "dhuhr");
  int asrOff = extractJsonInt(body, "asr");
  int maghribOff = extractJsonInt(body, "maghrib");
  int ishaOff = extractJsonInt(body, "isha");

  // Limit offsets to ±30 minutes
  fajrOff = constrain(fajrOff, -30, 30);
  sunriseOff = constrain(sunriseOff, -30, 30);
  dhuhrOff = constrain(dhuhrOff, -30, 30);
  asrOff = constrain(asrOff, -30, 30);
  maghribOff = constrain(maghribOff, -30, 30);
  ishaOff = constrain(ishaOff, -30, 30);

  // Read old offsets and stored mawaqit times to re-adjust if needed
  prefs.begin("adhancfg", true);
  int oldOffsets[6] = {
    prefs.getInt("mq_off_fajr", 0),
    prefs.getInt("mq_off_sunrise", 0),
    prefs.getInt("mq_off_dhuhr", 0),
    prefs.getInt("mq_off_asr", 0),
    prefs.getInt("mq_off_maghrib", 0),
    prefs.getInt("mq_off_isha", 0)
  };
  const char *mqKeys[6] = { "mq_fajr", "mq_sunrise", "mq_dhuhr", "mq_asr", "mq_maghrib", "mq_isha" };
  String mqTimes[6];
  for (int i = 0; i < 6; i++) mqTimes[i] = prefs.getString(mqKeys[i], "");
  prefs.end();

  int newOffsets[6] = { fajrOff, sunriseOff, dhuhrOff, asrOff, maghribOff, ishaOff };

  // Save new offsets
  prefs.begin("adhancfg", false);
  prefs.putInt("mq_off_fajr", fajrOff);
  prefs.putInt("mq_off_sunrise", sunriseOff);
  prefs.putInt("mq_off_dhuhr", dhuhrOff);
  prefs.putInt("mq_off_asr", asrOff);
  prefs.putInt("mq_off_maghrib", maghribOff);
  prefs.putInt("mq_off_isha", ishaOff);

  // Re-adjust stored Mawaqit times: reverse old offsets, apply new ones
  for (int i = 0; i < 6; i++) {
    if (mqTimes[i].length() >= 5 && (oldOffsets[i] != newOffsets[i])) {
      String raw = addMinutesToTime(mqTimes[i], -oldOffsets[i]);  // undo old
      String adjusted = addMinutesToTime(raw, newOffsets[i]);     // apply new
      prefs.putString(mqKeys[i], adjusted);
      Serial.printf("  Re-adjusted %s: %s -> %s (old=%+d, new=%+d)\n", mqKeys[i], mqTimes[i].c_str(), adjusted.c_str(), oldOffsets[i], newOffsets[i]);
    }
  }
  prefs.end();

  Serial.printf("Offsets saved: Fajr=%d Sunrise=%d Dhuhr=%d Asr=%d Maghrib=%d Isha=%d\n",
                fajrOff, sunriseOff, dhuhrOff, asrOff, maghribOff, ishaOff);

  // Reschedule alarm with new offsets
  if (rtc.begin()) scheduleNextPrayerAlarm();

  server.send(200, "application/json", "{\"ok\":true}");
}

// Configure selected mosque for Mawaqit from app
// Expected body JSON: {"mosque_uuid":"...", "name":"...", "city":"...", "lat":..., "lon":...}
void handleMawaqitConfig() {
  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }
  if (!requireApiKey()) return;

  String body = getRequestBody();
  Serial.print("/api/mawaqit/config body: ");
  Serial.println(body);

  String uuid = parseJsonString(body, "mosque_uuid");
  if (uuid.length() == 0) uuid = parseJsonString(body, "uuid");
  String slug = parseJsonString(body, "slug");
  String name = parseJsonString(body, "name");
  String city = parseJsonString(body, "city");

  if (uuid.length() == 0) {
    server.send(400, "application/json", "{\"error\":\"Missing mosque_uuid\"}");
    return;
  }

  prefs.begin("adhancfg", false);
  prefs.putString("mq_uuid", uuid);
  prefs.putString("mq_slug", slug);
  prefs.putString("mq_name", name);
  prefs.putString("mq_city", city);
  prefs.putULong("mq_ts", millis());
  prefs.end();

  Serial.printf("Mawaqit mosque saved uuid=%s slug=%s name=%s city=%s\n", uuid.c_str(), slug.c_str(), name.c_str(), city.c_str());
  server.send(200, "application/json", "{\"ok\":true,\"message\":\"mosque saved\"}");
}

// Helper function to encode URL parameters
String urlEncode(const String &str) {
  String encoded = "";
  for (size_t i = 0; i < str.length(); i++) {
    char c = str.charAt(i);
    if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      encoded += c;
    } else {
      char hex[4];
      sprintf(hex, "%%%02X", (unsigned char)c);
      encoded += hex;
    }
  }
  return encoded;
}

bool parseMawaqitTimesFromStream(Stream &stream, const String &uuid, const String &slug, String times[6]) {
  int braceCount = 0;
  String buffer = "";
  buffer.reserve(3000); // Pre-allocate to avoid memory fragmentation

  unsigned long startTime = millis();
  while (millis() - startTime < 20000) { // 20 seconds timeout for reading the stream
    if (!stream.available()) {
      delay(10);
      continue;
    }
    char c = stream.read();
    
    if (braceCount == 0) {
      if (c == '{') {
        braceCount = 1;
        buffer = "{";
      }
    } else {
      buffer += c;
      if (c == '{') {
        braceCount++;
      } else if (c == '}') {
        braceCount--;
        if (braceCount == 0) {
          // We have a complete mosque object!
          bool match = false;
          if (uuid.length() > 0 && buffer.indexOf(uuid) >= 0) {
            match = true;
          }
          if (!match && slug.length() > 0 && buffer.indexOf(slug) >= 0) {
            match = true;
          }
          
          if (match) {
            // Parse times from this buffer
            int timesPos = buffer.indexOf("\"times\"");
            if (timesPos >= 0) {
              int curPos = buffer.indexOf("[", timesPos);
              bool allParsed = true;
              const char *timeNames[6] = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" };
              for (int i = 0; i < 6; i++) {
                int q1 = buffer.indexOf('"', curPos + 1);
                int q2 = buffer.indexOf('"', q1 + 1);
                if (q1 >= 0 && q2 > q1) {
                  times[i] = buffer.substring(q1 + 1, q2);
                  if (times[i].length() > 5 && times[i].charAt(5) == ':') {
                    times[i] = times[i].substring(0, 5);
                  }
                  curPos = q2;
                  Serial.printf("  parsed stream %s = %s\n", timeNames[i], times[i].c_str());
                } else {
                  allParsed = false;
                }
              }
              if (allParsed) {
                return true;
              }
            }
          }
          // Clear buffer for the next mosque
          buffer = "";
        }
      }
      
      // Guard against runaway buffer size (if a mosque object exceeds 4KB)
      if (buffer.length() > 4000) {
        buffer = "";
        braceCount = 0;
      }
    }
  }
  return false;
}

// Trigger a sync placeholder (keeps API compatibility with app)
bool performMawaqitSync(String &errorMsg) {
  prefs.begin("adhancfg", true);
  String uuid = prefs.getString("mq_uuid", "");
  String slug = prefs.getString("mq_slug", "");
  String name = prefs.getString("mq_name", "");
  prefs.end();

  if (uuid.length() == 0 && slug.length() == 0) {
    errorMsg = "No mosque configured";
    return false;
  }

  Serial.printf(">>> Syncing Mawaqit times. UUID: %s, Slug: %s\n", uuid.c_str(), slug.c_str());

  double lat = 0.0, lon = 0.0, acc = 0.0;
  bool hasLocation = loadStoredLocation(lat, lon, acc);

  String host = "mawaqit.net";
  String urls[3] = { "", "", "" };
  int attempts = 0;

  if (slug.length() > 0) {
    urls[attempts++] = "/api/2.0/mosque/search?word=" + urlEncode(slug);
  }
  if (name.length() > 0 && attempts < 3) {
    urls[attempts++] = "/api/2.0/mosque/search?word=" + urlEncode(name);
  }
  if (hasLocation && attempts < 3) {
    urls[attempts++] = "/api/2.0/mosque/search?lat=" + String(lat, 6) + "&lon=" + String(lon, 6) + "&distance=20";
  }

  const char *timeNames[6] = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" };
  const char *altNames[6] = { "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha" };
  String times[6] = { "", "", "", "", "", "" };
  bool anyValid = false;

  for (int attempt = 0; attempt < attempts && !anyValid; attempt++) {
    HTTPClient http;
    WiFiClientSecure client;
    client.setInsecure();

    String url = "https://" + host + urls[attempt];
    Serial.printf("Mawaqit request [%d/%d]: %s\n", attempt + 1, attempts, url.c_str());

    http.begin(client, url);
    http.addHeader("User-Agent", "AdhanBox/1.0");
    http.addHeader("Accept", "application/json");
    http.setTimeout(15000);

    int httpCode = http.GET();
    if (httpCode == 200) {
      WiFiClient* streamPtr = http.getStreamPtr();
      if (streamPtr && parseMawaqitTimesFromStream(*streamPtr, uuid, slug, times)) {
        anyValid = true;
      } else {
        Serial.println("Failed to parse times from Mawaqit stream");
      }
    } else {
      Serial.printf("Mawaqit HTTP error: %d\n", httpCode);
    }
    http.end();

    if (!anyValid) {
      for (int i = 0; i < 6; i++) times[i] = "";
    }
  }

  bool mawaqitSyncSuccess = anyValid;

  if (!anyValid) {
    Serial.println("No valid times parsed from Mawaqit endpoints, trying coordinate fallback (Aladhan)...");

    double flat = 0.0, flon = 0.0, facc = 0.0;
    if (!loadStoredLocation(flat, flon, facc)) {
      errorMsg = "No valid times and no location for fallback";
      return false;
    }

    HTTPClient http;
    String fallbackUrl = "https://api.aladhan.com/v1/timings?latitude=" + String(flat, 6) + "&longitude=" + String(flon, 6) + "&method=12&school=1";
    Serial.printf("Fallback request: %s\n", fallbackUrl.c_str());

    http.begin(fallbackUrl);
    http.setTimeout(15000);
    int httpCode = http.GET();

    if (httpCode != 200) {
      Serial.printf("Fallback HTTP error: %d\n", httpCode);
      http.end();
      errorMsg = "Fallback request failed";
      return false;
    }

    String fallbackBody = http.getString();
    http.end();
    Serial.printf("Fallback body (first 300 chars): %.300s\n", fallbackBody.c_str());

    for (int i = 0; i < 6; i++) {
      int pos = fallbackBody.indexOf(String("\"") + altNames[i] + "\"");
      if (pos >= 0) {
        int colonPos = fallbackBody.indexOf(":", pos);
        int q1 = fallbackBody.indexOf('"', colonPos + 1);
        int q2 = fallbackBody.indexOf('"', q1 + 1);
        if (q1 >= 0 && q2 > q1) {
          times[i] = fallbackBody.substring(q1 + 1, q2);
          if (times[i].length() > 5 && times[i].charAt(5) == ':') {
            times[i] = times[i].substring(0, 5);
          }
          Serial.printf("  fallback %s = %s\n", altNames[i], times[i].c_str());
        }
      }
    }

    anyValid = false;
    for (int i = 0; i < 6; i++) {
      if (times[i].length() >= 5) {
        anyValid = true;
        break;
      }
    }

    if (!anyValid) {
      errorMsg = "No valid times in response";
      return false;
    }
  }

  // Apply user-configured offsets to times
  prefs.begin("adhancfg", true);
  int offsets[6] = {
    prefs.getInt("mq_off_fajr", 0),
    prefs.getInt("mq_off_sunrise", 0),
    prefs.getInt("mq_off_dhuhr", 0),
    prefs.getInt("mq_off_asr", 0),
    prefs.getInt("mq_off_maghrib", 0),
    prefs.getInt("mq_off_isha", 0)
  };
  prefs.end();

  Serial.println("Applying offsets to times:");
  for (int i = 0; i < 6; i++) {
    if (offsets[i] != 0 && times[i].length() >= 5) {
      String original = times[i];
      times[i] = addMinutesToTime(times[i], offsets[i]);
      Serial.printf("  %s: %s + %d min = %s\n", timeNames[i], original.c_str(), offsets[i], times[i].c_str());
    }
  }

  // Save to Preferences with RTC timestamp (not millis!)
  if (!rtc.begin()) {
    errorMsg = "RTC missing";
    return false;
  }
  unsigned long now_epoch = rtc.now().unixtime();

  prefs.begin("adhancfg", false);
  prefs.putString("mq_fajr", times[0]);
  prefs.putString("mq_sunrise", times[1]);
  prefs.putString("mq_dhuhr", times[2]);
  prefs.putString("mq_asr", times[3]);
  prefs.putString("mq_maghrib", times[4]);
  prefs.putString("mq_isha", times[5]);
  prefs.putULong("mq_sync_ts", now_epoch);
  prefs.end();

  Serial.printf("Mawaqit times synced successfully at epoch %lu\n", now_epoch);
  Serial.printf("  Fajr: %s  Dhuhr: %s  Maghrib: %s  Isha: %s\n", times[0].c_str(), times[2].c_str(), times[4].c_str(), times[5].c_str());

  if (!mawaqitSyncSuccess) {
    errorMsg = "Mawaqit sync failed (using calculated times fallback)";
    return false;
  }

  return true;
}

void handleMawaqitSync() {
  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }
  if (!requireApiKey()) return;

  String err;
  if (performMawaqitSync(err)) {
    scheduleNextPrayerAlarm();
    server.send(200, "application/json", "{\"ok\":true,\"message\":\"times synced\"}");
  } else {
    server.send(500, "application/json", "{\"error\":\"" + err + "\"}");
  }
}

// Debug endpoint: dump stored Mawaqit times and freshness status
void handleMawaqitDebug() {
  prefs.begin("adhancfg", true);
  String mq_uuid = prefs.getString("mq_uuid", "");
  String mq_fajr = prefs.getString("mq_fajr", "");
  String mq_sunrise = prefs.getString("mq_sunrise", "");
  String mq_dhuhr = prefs.getString("mq_dhuhr", "");
  String mq_asr = prefs.getString("mq_asr", "");
  String mq_maghrib = prefs.getString("mq_maghrib", "");
  String mq_isha = prefs.getString("mq_isha", "");
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();

  String json = "{";
  json += "\"uuid\":\"" + mq_uuid + "\",";
  json += "\"times\":{";
  json += "\"fajr\":\"" + mq_fajr + "\",";
  json += "\"sunrise\":\"" + mq_sunrise + "\",";
  json += "\"dhuhr\":\"" + mq_dhuhr + "\",";
  json += "\"asr\":\"" + mq_asr + "\",";
  json += "\"maghrib\":\"" + mq_maghrib + "\",";
  json += "\"isha\":\"" + mq_isha + "\"";
  json += "},";
  json += "\"sync_ts\":" + String(mq_sync_ts) + ",";

  if (rtc.begin()) {
    unsigned long now_epoch = rtc.now().unixtime();
    unsigned long age_sec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
    float age_hours = age_sec / 3600.0;
    bool fresh = (age_sec < 25UL * 3600UL);
    json += "\"now_epoch\":" + String(now_epoch) + ",";
    json += "\"age_seconds\":" + String(age_sec) + ",";
    json += "\"age_hours\":" + String(age_hours, 2) + ",";
    json += "\"fresh\":" + String(fresh ? "true" : "false");
  } else {
    json += "\"rtc_error\":true";
  }

  json += "}";
  server.send(200, "application/json", json);
}

void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName) {
  fajrAngle = 18.0;
  ishaAngle = 17.0;
  methodName = "mwl";

  prefs.begin("adhancfg", true);
  String method = prefs.getString("calc_method", "mwl");
  double customFajr = prefs.getFloat("calc_fajr_angle", 18.0f);
  double customIsha = prefs.getFloat("calc_isha_angle", 17.0f);
  prefs.end();

  method.toLowerCase();
  methodName = method;

  if (method == "isna") {
    fajrAngle = 15.0;
    ishaAngle = 15.0;
  } else if (method == "uoif") {
    fajrAngle = 12.0;
    ishaAngle = 12.0;
  } else if (method == "egypt") {
    fajrAngle = 19.5;
    ishaAngle = 17.5;
  } else if (method == "karachi") {
    fajrAngle = 18.0;
    ishaAngle = 18.0;
  } else if (method == "custom") {
    fajrAngle = customFajr;
    ishaAngle = customIsha;
  } else {
    methodName = "mwl";
    fajrAngle = 18.0;
    ishaAngle = 17.0;
  }
}

// Configure calculation method/angles for fallback prayer times
// GET -> current config, POST -> save config
void handleCalculationConfig() {
  if (server.method() == HTTP_GET) {
    double fajrAngle, ishaAngle;
    String methodName;
    getCalculationAngles(fajrAngle, ishaAngle, methodName);
    String out = "{\"method\":\"" + methodName + "\",\"fajr_angle\":" + String(fajrAngle, 1) + ",\"isha_angle\":" + String(ishaAngle, 1) + "}";
    server.send(200, "application/json", out);
    return;
  }

  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }

  String body = getRequestBody();
  Serial.print("/api/calculation/config body: ");
  Serial.println(body);

  auto extractJsonNumber = [&](const String &src, const char *key, double defVal) -> double {
    int k = src.indexOf(String("\"") + key + "\"");
    if (k < 0) return defVal;
    int colon = src.indexOf(':', k);
    if (colon < 0) return defVal;
    int endp = src.indexOf(',', colon);
    if (endp < 0) endp = src.indexOf('}', colon);
    if (endp < 0) return defVal;
    String v = src.substring(colon + 1, endp);
    v.trim();
    return v.toFloat();
  };

  String method = parseJsonString(body, "method");
  if (method.length() == 0) method = "mwl";
  method.toLowerCase();

  if (!(method == "mwl" || method == "isna" || method == "uoif" || method == "egypt" || method == "karachi" || method == "custom")) {
    server.send(400, "application/json", "{\"error\":\"Invalid method\"}");
    return;
  }

  double customFajr = extractJsonNumber(body, "fajr_angle", 18.0);
  double customIsha = extractJsonNumber(body, "isha_angle", 17.0);
  if (customFajr < 10.0 || customFajr > 25.0) customFajr = 18.0;
  if (customIsha < 10.0 || customIsha > 25.0) customIsha = 17.0;

  prefs.begin("adhancfg", false);
  prefs.putString("calc_method", method);
  prefs.putFloat("calc_fajr_angle", (float)customFajr);
  prefs.putFloat("calc_isha_angle", (float)customIsha);
  prefs.end();

  if (rtc.begin()) scheduleNextPrayerAlarm();

  String out = "{\"ok\":true,\"method\":\"" + method + "\",\"fajr_angle\":" + String(customFajr, 1) + ",\"isha_angle\":" + String(customIsha, 1) + "}";
  server.send(200, "application/json", out);
}

// GET/POST /api/adhan/config - Manage adhan track selection and duaa settings
void handleAdhanConfig() {
  if (server.method() == HTTP_GET) {
    // Return current adhan configuration
    prefs.begin("adhancfg", true);
    int fajr_track = prefs.getInt("ah_fajr_trk", 3);
    int dhuhr_track = prefs.getInt("ah_dhuhr_trk", 2);
    int asr_track = prefs.getInt("ah_asr_trk", 2);
    int maghrib_track = prefs.getInt("ah_magh_trk", 2);
    int isha_track = prefs.getInt("ah_isha_trk", 2);
    bool fajr_duaa = prefs.getBool("ah_fajr_duaa", true);
    bool dhuhr_duaa = prefs.getBool("ah_dhuhr_duaa", true);
    bool asr_duaa = prefs.getBool("ah_asr_duaa", true);
    bool maghrib_duaa = prefs.getBool("ah_magh_duaa", true);
    bool isha_duaa = prefs.getBool("ah_isha_duaa", true);

    bool fajr_enabled = prefs.getBool("ah_fajr_en", true);
    bool dhuhr_enabled = prefs.getBool("ah_dhuhr_en", true);
    bool asr_enabled = prefs.getBool("ah_asr_en", true);
    bool maghrib_enabled = prefs.getBool("ah_magh_en", true);
    bool isha_enabled = prefs.getBool("ah_isha_en", true);

    int globalVol = prefs.getInt("volume", 20);
    int fajr_volume = prefs.getInt("ah_fajr_vol", globalVol);
    int dhuhr_volume = prefs.getInt("ah_dhuhr_vol", globalVol);
    int asr_volume = prefs.getInt("ah_asr_vol", globalVol);
    int maghrib_volume = prefs.getInt("ah_magh_vol", globalVol);
    int isha_volume = prefs.getInt("ah_isha_vol", globalVol);
    prefs.end();

    String json = "{";
    json += "\"fajr_track\":" + String(fajr_track) + ",";
    json += "\"fajr_duaa\":" + String(fajr_duaa ? "true" : "false") + ",";
    json += "\"fajr_enabled\":" + String(fajr_enabled ? "true" : "false") + ",";
    json += "\"fajr_volume\":" + String(fajr_volume) + ",";
    json += "\"dhuhr_track\":" + String(dhuhr_track) + ",";
    json += "\"dhuhr_duaa\":" + String(dhuhr_duaa ? "true" : "false") + ",";
    json += "\"dhuhr_enabled\":" + String(dhuhr_enabled ? "true" : "false") + ",";
    json += "\"dhuhr_volume\":" + String(dhuhr_volume) + ",";
    json += "\"asr_track\":" + String(asr_track) + ",";
    json += "\"asr_duaa\":" + String(asr_duaa ? "true" : "false") + ",";
    json += "\"asr_enabled\":" + String(asr_enabled ? "true" : "false") + ",";
    json += "\"asr_volume\":" + String(asr_volume) + ",";
    json += "\"maghrib_track\":" + String(maghrib_track) + ",";
    json += "\"maghrib_duaa\":" + String(maghrib_duaa ? "true" : "false") + ",";
    json += "\"maghrib_enabled\":" + String(maghrib_enabled ? "true" : "false") + ",";
    json += "\"maghrib_volume\":" + String(maghrib_volume) + ",";
    json += "\"isha_track\":" + String(isha_track) + ",";
    json += "\"isha_duaa\":" + String(isha_duaa ? "true" : "false") + ",";
    json += "\"isha_enabled\":" + String(isha_enabled ? "true" : "false") + ",";
    json += "\"isha_volume\":" + String(isha_volume);
    json += "}";
    server.send(200, "application/json", json);
    return;
  }

  if (server.method() == HTTP_POST) {
    if (!requireApiKey()) return;
    // Parse and save adhan configuration
    String body = server.arg("plain");

    auto extractJsonBool = [&](const String &src, const char *key, bool defVal) -> bool {
      int idx = src.indexOf(String("\"") + key + "\":");
      if (idx < 0) return defVal;
      idx += strlen(key) + 3;
      while (idx < src.length() && (src[idx] == ' ' || src[idx] == '\t')) idx++;
      if (src.substring(idx, idx + 4) == "true") return true;
      if (src.substring(idx, idx + 5) == "false") return false;
      return defVal;
    };

    auto extractJsonNumber = [&](const String &src, const char *key, double defVal) -> double {
      int idx = src.indexOf(String("\"") + key + "\":");
      if (idx < 0) return defVal;
      idx += strlen(key) + 3;
      while (idx < src.length() && (src[idx] == ' ' || src[idx] == '\t')) idx++;
      int endIdx = idx;
      while (endIdx < src.length() && (isdigit(src[endIdx]) || src[endIdx] == '-' || src[endIdx] == '.')) endIdx++;
      if (endIdx > idx) return src.substring(idx, endIdx).toDouble();
      return defVal;
    };

    prefs.begin("adhancfg", true);
    int globalVol = prefs.getInt("volume", 20);
    prefs.end();

    int fajr_track = (int)extractJsonNumber(body, "fajr_track", 3);
    int dhuhr_track = (int)extractJsonNumber(body, "dhuhr_track", 2);
    int asr_track = (int)extractJsonNumber(body, "asr_track", 2);
    int maghrib_track = (int)extractJsonNumber(body, "maghrib_track", 2);
    int isha_track = (int)extractJsonNumber(body, "isha_track", 2);

    // Constrain to 1-21
    fajr_track = constrain(fajr_track, 1, 21);
    dhuhr_track = constrain(dhuhr_track, 1, 21);
    asr_track = constrain(asr_track, 1, 21);
    maghrib_track = constrain(maghrib_track, 1, 21);
    isha_track = constrain(isha_track, 1, 21);

    bool fajr_duaa = extractJsonBool(body, "fajr_duaa", true);
    bool dhuhr_duaa = extractJsonBool(body, "dhuhr_duaa", true);
    bool asr_duaa = extractJsonBool(body, "asr_duaa", true);
    bool maghrib_duaa = extractJsonBool(body, "maghrib_duaa", true);
    bool isha_duaa = extractJsonBool(body, "isha_duaa", true);

    bool fajr_enabled = extractJsonBool(body, "fajr_enabled", true);
    bool dhuhr_enabled = extractJsonBool(body, "dhuhr_enabled", true);
    bool asr_enabled = extractJsonBool(body, "asr_enabled", true);
    bool maghrib_enabled = extractJsonBool(body, "maghrib_enabled", true);
    bool isha_enabled = extractJsonBool(body, "isha_enabled", true);

    int fajr_volume = (int)extractJsonNumber(body, "fajr_volume", globalVol);
    int dhuhr_volume = (int)extractJsonNumber(body, "dhuhr_volume", globalVol);
    int asr_volume = (int)extractJsonNumber(body, "asr_volume", globalVol);
    int maghrib_volume = (int)extractJsonNumber(body, "maghrib_volume", globalVol);
    int isha_volume = (int)extractJsonNumber(body, "isha_volume", globalVol);

    fajr_volume = constrain(fajr_volume, 0, 30);
    dhuhr_volume = constrain(dhuhr_volume, 0, 30);
    asr_volume = constrain(asr_volume, 0, 30);
    maghrib_volume = constrain(maghrib_volume, 0, 30);
    isha_volume = constrain(isha_volume, 0, 30);

    prefs.begin("adhancfg", false);
    prefs.putInt("ah_fajr_trk", fajr_track);
    prefs.putInt("ah_dhuhr_trk", dhuhr_track);
    prefs.putInt("ah_asr_trk", asr_track);
    prefs.putInt("ah_magh_trk", maghrib_track);
    prefs.putInt("ah_isha_trk", isha_track);
    prefs.putBool("ah_fajr_duaa", fajr_duaa);
    prefs.putBool("ah_dhuhr_duaa", dhuhr_duaa);
    prefs.putBool("ah_asr_duaa", asr_duaa);
    prefs.putBool("ah_magh_duaa", maghrib_duaa);
    prefs.putBool("ah_isha_duaa", isha_duaa);

    prefs.putBool("ah_fajr_en", fajr_enabled);
    prefs.putBool("ah_dhuhr_en", dhuhr_enabled);
    prefs.putBool("ah_asr_en", asr_enabled);
    prefs.putBool("ah_magh_en", maghrib_enabled);
    prefs.putBool("ah_isha_en", isha_enabled);

    prefs.putInt("ah_fajr_vol", fajr_volume);
    prefs.putInt("ah_dhuhr_vol", dhuhr_volume);
    prefs.putInt("ah_asr_vol", asr_volume);
    prefs.putInt("ah_magh_vol", maghrib_volume);
    prefs.putInt("ah_isha_vol", isha_volume);
    prefs.end();

    Serial.printf("Adhan config saved: Fajr=%d (duaa:%d, en:%d, vol:%d), Dhuhr=%d (duaa:%d, en:%d, vol:%d), Asr=%d (duaa:%d, en:%d, vol:%d), Maghrib=%d (duaa:%d, en:%d, vol:%d), Isha=%d (duaa:%d, en:%d, vol:%d)\n",
                  fajr_track, fajr_duaa, fajr_enabled, fajr_volume,
                  dhuhr_track, dhuhr_duaa, dhuhr_enabled, dhuhr_volume,
                  asr_track, asr_duaa, asr_enabled, asr_volume,
                  maghrib_track, maghrib_duaa, maghrib_enabled, maghrib_volume,
                  isha_track, isha_duaa, isha_enabled, isha_volume);

    server.send(200, "application/json", "{\"ok\":true}");
    return;
  }

  server.send(405, "text/plain", "Method not allowed");
}



void handleDisconnectWifi() {
  WiFi.disconnect(true);
  WiFi.mode(WIFI_AP);
  server.send(200, "text/plain", "WiFi disconnected");
}

// Sync time from NTP server. Returns true on success.
bool syncTimeFromNtp(unsigned long timeoutMs) {
  if (!WiFi.isConnected()) {
    Serial.println("Cannot sync NTP: no WiFi");
    return false;
  }
  // Use UTC time from NTP, then apply stored timezone offset when setting RTC
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  struct tm timeinfo;
  unsigned long start = millis();
  while (millis() - start < timeoutMs) {
    if (getLocalTime(&timeinfo)) { break; }
    delay(200);
  }
  if (!getLocalTime(&timeinfo)) {
    Serial.println("NTP getLocalTime failed");
    return false;
  }
  // timeinfo is in localtime according to configTime(0,0) (we set offset 0), so it's UTC
  int year = timeinfo.tm_year + 1900;
  int mon = timeinfo.tm_mon + 1;
  int day = timeinfo.tm_mday;
  int hour = timeinfo.tm_hour;
  int min = timeinfo.tm_min;
  int sec = timeinfo.tm_sec;
  Serial.printf("NTP UTC time: %04d-%02d-%02d %02d:%02d:%02d\n", year, mon, day, hour, min, sec);
  // Apply timezone offset stored in prefs (minutes)
  prefs.begin("adhancfg", true);
  int tzMin = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  int tzOffset = 0;
  if (tzMin != 0x7fffffff) tzOffset = tzMin;  // minutes
  // Construct DateTime adjusted to local time
  time_t utc = mktime(&timeinfo);
  time_t localt = utc + tzOffset * 60;
  struct tm *lt = gmtime(&localt);
  if (!lt) {
    Serial.println("Failed to convert local time");
    return false;
  }
  if (!rtc.begin()) {
    Serial.println("RTC not present; cannot set time");
    return false;
  }
  rtc.adjust(DateTime(lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec));
  Serial.printf("RTC set to local time (tz offset %d min): %04d-%02d-%02d %02d:%02d:%02d\n", tzOffset, lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec);
  return true;
}

#if ENABLE_BLE
// ── BLE Provisioning functions ────────────────────────────────────────────────

void startBLEProvisioning() {
  // remember previous LED scenario and enter BLINK mode for indication
  if (prevLedScenario < 0) prevLedScenario = ledScenario;
  ledScenario = BLINK_INDEX;

  // Initialize Wi-Fi STA mode so WiFi.macAddress() can read the actual hardware MAC
  WiFi.mode(WIFI_STA);

  // Build unique name from last 3 bytes of MAC
  String mac = WiFi.macAddress();    // "AA:BB:CC:DD:EE:FF"
  String suffix = mac.substring(9);  // "DD:EE:FF"
  suffix.replace(":", "");           // "DDEEFF"
  String bleName = "AdhanBox-" + suffix;

  static bool bleInitialized = false;
  if (!bleInitialized) {
    BLEDevice::init(bleName.c_str());
    _bleServer = BLEDevice::createServer();
    _bleServer->setCallbacks(new _BLEServerCB());

    BLEService *svc = _bleServer->createService(BLE_SVC_UUID);

    BLECharacteristic *ssidChar = svc->createCharacteristic(BLE_SSID_UUID, BLECharacteristic::PROPERTY_WRITE);
    ssidChar->setCallbacks(new _BLESsidCB());

    BLECharacteristic *passChar = svc->createCharacteristic(BLE_PASS_UUID, BLECharacteristic::PROPERTY_WRITE);
    passChar->setCallbacks(new _BLEPassCB());

    _bleStatusChar = svc->createCharacteristic(
      BLE_STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    _bleStatusChar->addDescriptor(new BLE2902());
    _bleStatusChar->setValue("waiting");

    // WiFi scan characteristic: app writes "scan" → ESP32 scans → notifies JSON results
    _bleWifiScanChar = svc->createCharacteristic(
      BLE_WIFI_SCAN_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
    _bleWifiScanChar->addDescriptor(new BLE2902());
    _bleWifiScanChar->setCallbacks(new _BLEWifiScanCB());

    svc->start();

    BLEAdvertising *adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(BLE_SVC_UUID);
    adv->setScanResponse(true);
    // Intervalle d'advertising court pour être détecté rapidement par iOS
    adv->setMinPreferred(0x06);  // ~3.75ms
    adv->setMaxPreferred(0x12);  // ~11.25ms
    bleInitialized = true;
  } else {
    // Reset status value when restarting provisioning
    if (_bleStatusChar) {
      _bleStatusChar->setValue("waiting");
    }
  }

  BLEDevice::startAdvertising();

  _bleActive = true;
  Serial.printf("[BLE] Advertising as '%s'\n", bleName.c_str());
}

void stopBLEProvisioning() {
  if (!_bleActive) return;
  _bleActive = false;

  // Déconnecter tout client connecté proprement avant d'arrêter l'advertising
  if (_bleServer && _bleClientConn) {
    Serial.println("[BLE] Deconnexion client avant arret...");
    _bleServer->disconnect(0);
    delay(300);  // laisser les callbacks onDisconnect se terminer
  }
  BLEDevice::stopAdvertising();
  _bleCredsReady = false;
  _bleClientConn = false;
  Serial.println("[BLE] provisioning stopped");

  // restore previous LED scenario if present
  if (prevLedScenario >= 0) {
    ledScenario = prevLedScenario;
    prevLedScenario = -1;
  }
}

void startServices() {
  static bool servicesStarted = false;
  if (servicesStarted) return;
  setupServerRoutes();
  server.begin();
  Serial.println("[WiFi] Web server started — http://" + WiFi.localIP().toString());

  if (MDNS.begin("adhanbox")) {
    MDNS.addService("http", "tcp", 80);
    Serial.println("[mDNS] adhanbox.local");
  }
  setupOTA();
  
  // Init MQTT if configured
  prefs.begin("adhancfg", true);
  String broker = prefs.getString("mqtt_broker", "");
  prefs.end();
  if (broker.length() > 0) {
    mqtt.setServer(broker.c_str(), MQTT_PORT);
    mqtt.setCallback(mqttCallback);
    Serial.printf("MQTT broker initialized: %s\n", broker.c_str());
  }
  servicesStarted = true;
}

// Called from loop() — handles WiFi connection after credentials are received via BLE
void handleBLEProvisioning() {
  if (!_bleActive || !_bleCredsReady) return;
  _bleCredsReady = false;

  String ssid = _blePendingSSID;
  String pass = _blePendingPass;

  Serial.printf("[BLE] Connecting WiFi: %s\n", ssid.c_str());
  if (_bleStatusChar && _bleClientConn) {
    _bleStatusChar->setValue("connecting");
    _bleStatusChar->notify();
  }

  // Connect WiFi (BLE + WiFi coexist on ESP32)
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());

  unsigned long t0 = millis();
  while (millis() - t0 < 20000 && WiFi.status() != WL_CONNECTED) delay(300);

  if (WiFi.status() == WL_CONNECTED) {
    String ip = WiFi.localIP().toString();
    Serial.printf("[BLE] WiFi OK — IP: %s\n", ip.c_str());

    // Save credentials
    prefs.begin("adhancfg", false);
    prefs.putString("wifi_ssid", ssid);
    prefs.putString("wifi_pass", pass);
    prefs.end();

    // Notify Flutter with IP
    String payload = "{\"ok\":true,\"ip\":\"" + ip + "\"}";
    if (_bleStatusChar) {
      _bleStatusChar->setValue(payload.c_str());
      if (_bleClientConn) {
        _bleStatusChar->notify();
        delay(400);
      }
    }

    // Stop BLE advertising and connections
    delay(100);
    stopBLEProvisioning();
    delay(100);

    // Start services
    startServices();
    wifiConnectState = WCS_CONNECTED;

    if (rtc.begin()) {
      syncTimeFromNtp(10000);
      scheduleNextPrayerAlarm();
    }

  } else {
    Serial.println("[BLE] WiFi failed — wrong password?");
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    delay(300);

    if (_bleStatusChar) {
      _bleStatusChar->setValue("{\"ok\":false,\"error\":\"wifi_failed\"}");
      if (_bleClientConn) {
        _bleStatusChar->notify();
        delay(200);
      }
    }
    // Reset for retry
    _blePendingSSID = "";
    _blePendingPass = "";
    BLEDevice::startAdvertising();
    _bleActive = true;
    Serial.println("[BLE] Advertising restarted — waiting for new credentials");
  }
}
#endif
// ─────────────────────────────────────────────────────────────────────────────

void startConfigAP() {
  if (apRunning) return;
  // remember previous LED scenario and enter BLINK mode for indication
  if (prevLedScenario < 0) prevLedScenario = ledScenario;
  ledScenario = BLINK_INDEX;
  // generate SSID with last 4 of MAC
  uint64_t mac = ESP.getEfuseMac();
  uint16_t suffix = (uint16_t)(mac & 0xFFFF);
  char ssid[32];
  snprintf(ssid, sizeof(ssid), "%s%04X", AP_SSID_PREFIX, suffix);
  WiFi.softAP(ssid);
  delay(100);
  // Start DNS server to capture all domain requests and point them to the AP IP
  IPAddress apIP = WiFi.softAPIP();
  dnsServer.start(DNS_PORT, "*", apIP);
  Serial.printf("DNS captive portal started on %s\n", apIP.toString().c_str());
  // Redirect any unknown HTTP requests to the root page (captive behaviour)
  server.onNotFound([&]() {
    String redirect = String("http://") + WiFi.softAPIP().toString();
    server.sendHeader("Location", redirect, true);
    server.send(302, "text/plain", "");
  });
  // Enregistrer toutes les routes et démarrer le serveur
  setupServerRoutes();
  server.begin();
  apRunning = true;
  apStartTime = millis();
  Serial.printf("Config AP started: %s\n", ssid);
}

/// Enregistre toutes les routes du serveur HTTP
void setupServerRoutes() {
  // Déclarer les headers HTTP personnalisés à conserver (obligatoire pour server.header())
  static const char *kCollectedHeaders[] = { "X-API-Key" };
  server.collectHeaders(kCollectedHeaders, 1);

  server.on("/", HTTP_GET, handleRoot);
  server.on("/set_location", HTTP_POST, handleSetLocation);
  server.on("/set_tz", HTTP_POST, handleSetTZ);
  server.on("/rtc_time", HTTP_GET, handleGetRTC);
  server.on("/prayer_times", HTTP_GET, handlePrayerTimes);
  server.on("/dump_status", HTTP_GET, handleDumpStatus);
  server.on("/led_test", HTTP_GET, handleLedTest);
  server.on("/set_led", HTTP_GET, handleSetLed);
  server.on("/led_off", HTTP_GET, handleLedOff);
  server.on("/scan_wifi", HTTP_GET, handleScanWifi);
  server.on("/setrtc", HTTP_GET, handleSetRTC);
  server.on("/set_rtc_manual", HTTP_POST, handleSetRtcManual);
  server.on("/set_alarm_test", HTTP_GET, handleSetAlarmTest);
  server.on("/cancel_alarms", HTTP_GET, handleCancelAlarms);
  server.on("/show_next_alarm", HTTP_GET, handleShowNextAlarm);
  server.on("/show_loc", HTTP_GET, handleShowLoc);
  server.on("/show_time", HTTP_GET, handleShowTime);
  server.on("/play", HTTP_GET, handlePlayTrack);
  server.on("/stopplay", HTTP_GET, handleStopPlay);
  server.on("/playtest", HTTP_GET, handlePlayTest);
  server.on("/set_volume", HTTP_POST, handleSetVolume);
  server.on("/get_volume", HTTP_GET, handleGetVolume);
  server.on("/set_brightness", HTTP_POST, handleSetBrightness);
  server.on("/get_brightness", HTTP_GET, handleGetBrightness);
  server.on("/connect_wifi", HTTP_POST, handleConnectWifi);
  server.on("/disconnect_wifi", HTTP_GET, handleDisconnectWifi);
  server.on("/stop_ap", HTTP_GET, []() {
    server.send(200, "text/plain", "AP stopped");
    stopConfigAP();
  });
  server.on("/api/calculation/config", HTTP_GET, handleCalculationConfig);
  server.on("/api/calculation/config", HTTP_POST, handleCalculationConfig);
  server.on("/sync_time", HTTP_GET, []() {
    bool ok = syncTimeFromNtp(10000);
    if (ok) {
      if (rtc.begin()) scheduleNextPrayerAlarm();
      server.send(200, "text/plain", "Time synced");
    } else server.send(500, "text/plain", "Time sync failed");
  });
  server.on("/api/mawaqit/config", HTTP_POST, handleMawaqitConfig);
  server.on("/api/mawaqit/sync", HTTP_POST, handleMawaqitSync);
  server.on("/api/mawaqit/debug", HTTP_GET, handleMawaqitDebug);
  server.on("/api/mawaqit/offsets", HTTP_GET, handleMawaqitGetOffsets);
  server.on("/api/mawaqit/offsets", HTTP_POST, handleMawaqitSetOffsets);
  server.on("/api/adhan/config", HTTP_GET, handleAdhanConfig);
  server.on("/api/adhan/config", HTTP_POST, handleAdhanConfig);

  // ===== API Aliases for Flutter App =====
  server.on("/api/config/timezone", HTTP_POST, handleSetTZ);
  server.on("/api/audio/volume", HTTP_POST, handleSetVolume);
  server.on("/api/led/brightness", HTTP_POST, handleSetBrightness);
  server.on("/api/led/brightness", HTTP_GET, handleGetBrightness);
  server.on("/api/led/scenario", HTTP_POST, handleSetLedScenario);
  server.on("/api/mqtt/config", HTTP_GET, handleMqttConfig);
  server.on("/api/mqtt/config", HTTP_POST, handleMqttConfig);
  server.on("/api/wifi/status", HTTP_GET, handleWifiStatus);
  server.on("/api/firmware/version", HTTP_GET, handleFirmwareVersion);
  server.on("/api/device/info", HTTP_GET, handleDeviceInfo);
  server.on("/ota/upload", HTTP_POST, handleOtaUploadComplete, handleOtaUpload);
  server.on("/update", HTTP_GET, handleUpdatePage);
#if ENABLE_BLE
  server.on("/api/start_ble", HTTP_GET, []() {
    if (!_bleActive) {
      startBLEProvisioning();
      server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE provisioning started\"}");
    } else {
      server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE already active\"}");
    }
  });
  server.on("/api/stop_ble", HTTP_GET, []() {
    stopBLEProvisioning();
    server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE stopped\"}");
  });
#endif
}

void stopConfigAP() {
  if (!apRunning) return;
  // Stop DNS captive server
  dnsServer.stop();
  Serial.println("DNS captive portal stopped");
  server.stop();
  WiFi.softAPdisconnect(true);
  apRunning = false;
  Serial.println("Config AP stopped");
  // restore previous LED scenario if present
  if (prevLedScenario >= 0) {
    ledScenario = prevLedScenario;
    prevLedScenario = -1;
  }
}

// Gestion bouton : appui simple direct (pas de latence)
// → stop adhan si en lecture, sinon cycle LED
void checkConfigButton(){
  static bool lastState = HIGH;
  static unsigned long debounceTime = 0;
  const unsigned long DEBOUNCE_MS = 100;  // anti-rebond

  int val = digitalRead(CONFIG_BUTTON_PIN);
  if(val != lastState && (millis() - debounceTime) > DEBOUNCE_MS){
    debounceTime = millis();
    if(val == LOW){
      // Appui détecté
      if(isPlaying){
        stopPlay();
        ledScenario = 0; setLedDuty(0);
        if(useAddressableLEDs) stripSetAll(0,0,0);
      } else {
        do {
          ledScenario = (ledScenario + 1) % TOTAL_SCENES;
        } while(ledScenario == BLINK_INDEX);
        if(ledScenario == 0){ setLedDuty(0); if(useAddressableLEDs) stripSetAll(0,0,0); }
      }
    }
    lastState = val;
  }
}

// Load stored location (returns true if exists)
bool loadStoredLocation(double &outLat, double &outLon, double &outAcc) {
  prefs.begin("adhancfg", true);
  String latS = prefs.getString("lat", "");
  String lonS = prefs.getString("lon", "");
  String accS = prefs.getString("acc", "");
  prefs.end();
  if (latS.length() == 0 || lonS.length() == 0) return false;
  outLat = latS.toFloat();
  outLon = lonS.toFloat();
  outAcc = accS.length() ? accS.toFloat() : 9999.0;
  return true;
}

// --- Prayer times calculation (simplified, NOAA-based + twilight angles) ---
static double deg2rad(double d) {
  return d * M_PI / 180.0;
}
static double rad2deg(double r) {
  return r * 180.0 / M_PI;
}

// day of year from RTClib DateTime
static int dayOfYear(const DateTime &dt) {
  int mdays[] = { 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
  int y = dt.year();
  bool leap = ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0));
  if (leap) mdays[2] = 29;
  else mdays[2] = 28;
  int month = dt.month();
  if (month < 1 || month > 12) return 1;  // invalid RTC data guard
  int doy = 0;
  for (int m = 1; m < month; m++) doy += mdays[m];
  doy += constrain((int)dt.day(), 1, mdays[month]);
  return doy;
}

// Calculate equation of time (minutes) and solar declination (radians) for given day
static void solarDeclinationAndEqtime(int doy, double &declRad, double &eqTimeMin) {
  double gamma = 2.0 * M_PI / 365.0 * (doy - 1 + 0.5);  // approximate at midday
  eqTimeMin = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma));
  declRad = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma);
}

// compute hour angle degrees for given zenith (degrees), latitude (rad) and decl (rad)
static bool hourAngleForZenith(double zenithDeg, double latRad, double declRad, double &Hdeg) {
  double zenRad = deg2rad(zenithDeg);
  double cosH = (cos(zenRad) - sin(latRad) * sin(declRad)) / (cos(latRad) * cos(declRad));
  if (cosH > 1.0 || cosH < -1.0) return false;  // sun never reaches this zenith
  double H = acos(cosH);
  Hdeg = rad2deg(H);
  return true;
}

// format minutes (local) into hh:mm string
static String formatTimeFromMinutes(double minutes) {
  if (isnan(minutes)) return String("--:--");
  int mins = (int)round(minutes);
  mins = (mins + 24 * 60) % (24 * 60);
  int h = mins / 60;
  int m = mins % 60;
  char buf[8];
  snprintf(buf, sizeof(buf), "%02d:%02d", h, m);
  return String(buf);
}

// Compute and print prayer times for a given date using stored location
void computeAndPrintPrayerTimes(const DateTime &date) {
  double lat, lon, acc;
  if (!loadStoredLocation(lat, lon, acc)) {
    Serial.println("No stored location - cannot compute prayer times.");
    return;
  }
  int doy = dayOfYear(date);
  double decl, eqt;
  solarDeclinationAndEqtime(doy, decl, eqt);
  // timezone offset: prefer stored tz_offset_min, otherwise estimate from longitude
  prefs.begin("adhancfg", true);
  int tzOffsetMin = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  int tzMin;
  int tz;
  if (tzOffsetMin != 0x7fffffff) {
    tzMin = tzOffsetMin;
    tz = tzOffsetMin / 60;
  } else {
    tz = (int)round(lon / 15.0);
    tzMin = tz * 60;
  }
  // solar noon in minutes (local time)
  double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
  // sunrise/sunset (zenith 90.833)
  double Hsun_deg;
  bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
  double sunrise = NAN, sunset = NAN;
  if (okSun) {
    sunrise = solarNoon - 4.0 * Hsun_deg;
    sunset = solarNoon + 4.0 * Hsun_deg;
  }

  // fajr and isha (twilight angles)
  double Hfajr_deg, Hisha_deg;
  bool okFajr = hourAngleForZenith(90.0 + 18.0, deg2rad(lat), decl, Hfajr_deg);
  bool okIsha = hourAngleForZenith(90.0 + 17.0, deg2rad(lat), decl, Hisha_deg);
  double fajr = okFajr ? (solarNoon - 4.0 * Hfajr_deg) : NAN;
  double isha = okIsha ? (solarNoon + 4.0 * Hisha_deg) : NAN;

  // dhuhr = solar noon (no refraction)
  double dhuhr = solarNoon;

  // asr: compute zenith where sun altitude = arctan(1/(factor + tan(|lat - decl|))) with factor=1
  double latRad = deg2rad(lat);
  double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl))));  // elevation in radians (approx)
  double asrZenith = 90.0 - rad2deg(angle);
  double Hasr_deg;
  bool okAsr = hourAngleForZenith(asrZenith, latRad, decl, Hasr_deg);
  double asr = okAsr ? (solarNoon + 4.0 * Hasr_deg) : NAN;

  // print results
  char buf[128];
  snprintf(buf, sizeof(buf), "Prayer times for %04u-%02u-%02u (lat=%.5f lon=%.5f tz=%d):", date.year(), date.month(), date.day(), lat, lon, tz);
  Serial.println(buf);
  Serial.printf("Fajr: %s\n", formatTimeFromMinutes(fajr).c_str());
  Serial.printf("Sunrise: %s\n", formatTimeFromMinutes(sunrise).c_str());
  Serial.printf("Dhuhr: %s\n", formatTimeFromMinutes(dhuhr).c_str());
  Serial.printf("Asr: %s\n", formatTimeFromMinutes(asr).c_str());
  Serial.printf("Maghrib (sunset): %s\n", formatTimeFromMinutes(sunset).c_str());
  Serial.printf("Isha: %s\n", formatTimeFromMinutes(isha).c_str());
}

// Compute prayer times into an array (minutes since midnight) and report tz used
// outTimes must be an array of 6 doubles
bool computePrayerTimesForDate(const DateTime &date, double outTimes[6], int &tzUsedMin, String &tzSource) {
  double lat, lon, acc;
  if (!loadStoredLocation(lat, lon, acc)) return false;
  int doy = dayOfYear(date);
  double decl, eqt;
  solarDeclinationAndEqtime(doy, decl, eqt);
  prefs.begin("adhancfg", true);
  int tzOffsetMin = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  int tzMin;
  if (tzOffsetMin != 0x7fffffff) {
    tzMin = tzOffsetMin;
    tzUsedMin = tzMin;
    tzSource = "preference";
  } else {
    int tz = (int)round(lon / 15.0);
    tzMin = tz * 60;
    tzUsedMin = tzMin;
    tzSource = "estimate";
  }
  double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
  double Hsun_deg;
  bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
  double sunrise = okSun ? solarNoon - 4.0 * Hsun_deg : NAN;
  double sunset = okSun ? solarNoon + 4.0 * Hsun_deg : NAN;
  double fajrAngle, ishaAngle;
  String calcMethod;
  getCalculationAngles(fajrAngle, ishaAngle, calcMethod);
  double Hfajr, Hisha;
  bool okF = hourAngleForZenith(90.0 + fajrAngle, deg2rad(lat), decl, Hfajr);
  bool okI = hourAngleForZenith(90.0 + ishaAngle, deg2rad(lat), decl, Hisha);
  double fajr = okF ? (solarNoon - 4.0 * Hfajr) : NAN;
  double isha = okI ? (solarNoon + 4.0 * Hisha) : NAN;
  double dhuhr = solarNoon;
  double latRad = deg2rad(lat);
  double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl))));
  double asrZenith = 90.0 - rad2deg(angle);
  double Hasr_deg;
  bool okAsr = hourAngleForZenith(asrZenith, latRad, decl, Hasr_deg);
  double asr = okAsr ? (solarNoon + 4.0 * Hasr_deg) : NAN;
  outTimes[0] = fajr;
  outTimes[1] = sunrise;
  outTimes[2] = dhuhr;
  outTimes[3] = asr;
  outTimes[4] = sunset;
  outTimes[5] = isha;

  // Apply user fine-tuning offsets (minutes) on calculated times too.
  prefs.begin("adhancfg", true);
  int offsets[6] = {
    prefs.getInt("mq_off_fajr", 0),
    prefs.getInt("mq_off_sunrise", 0),
    prefs.getInt("mq_off_dhuhr", 0),
    prefs.getInt("mq_off_asr", 0),
    prefs.getInt("mq_off_maghrib", 0),
    prefs.getInt("mq_off_isha", 0)
  };
  prefs.end();

  for (int i = 0; i < 6; i++) {
    if (!isnan(outTimes[i])) outTimes[i] += offsets[i];
  }
  return true;
}

// Determine adhan playback parameters for a prayer index.
// prayerIndex mapping in this firmware: 1=fajr,2=sunrise,3=dhuhr,4=asr,5=maghrib,6=isha
// Returns false for non-adhan entries (e.g., sunrise).
bool getPrayerPlaybackForIndex(int prayerIndex, int &trackToPlay, bool &playDuaaAfter) {
  // Sunrise is not an adhan.
  if (prayerIndex == 2) return false;

  prefs.begin("adhancfg", true);
  
  // Check if enabled
  bool enabled = true;
  if (prayerIndex == 1) enabled = prefs.getBool("ah_fajr_en", true);
  else if (prayerIndex == 3) enabled = prefs.getBool("ah_dhuhr_en", true);
  else if (prayerIndex == 4) enabled = prefs.getBool("ah_asr_en", true);
  else if (prayerIndex == 5) enabled = prefs.getBool("ah_magh_en", true);
  else if (prayerIndex == 6) enabled = prefs.getBool("ah_isha_en", true);
  
  if (!enabled) {
    prefs.end();
    return false;
  }

  // Defaults for backward compatibility.
  trackToPlay = (prayerIndex == 1) ? 3 : 2;
  playDuaaAfter = true;

  bool forceTrack1 = prefs.getBool("force_t1", forcePlayTrack1);

  if (forceTrack1) {
    trackToPlay = 2;
  } else {
    if (prayerIndex == 1) trackToPlay = prefs.getInt("ah_fajr_trk", 3);
    else if (prayerIndex == 3) trackToPlay = prefs.getInt("ah_dhuhr_trk", 2);
    else if (prayerIndex == 4) trackToPlay = prefs.getInt("ah_asr_trk", 2);
    else if (prayerIndex == 5) trackToPlay = prefs.getInt("ah_magh_trk", 2);
    else if (prayerIndex == 6) trackToPlay = prefs.getInt("ah_isha_trk", 2);
  }

  if (prayerIndex == 1) playDuaaAfter = prefs.getBool("ah_fajr_duaa", true);
  else if (prayerIndex == 3) playDuaaAfter = prefs.getBool("ah_dhuhr_duaa", true);
  else if (prayerIndex == 4) playDuaaAfter = prefs.getBool("ah_asr_duaa", true);
  else if (prayerIndex == 5) playDuaaAfter = prefs.getBool("ah_magh_duaa", true);
  else if (prayerIndex == 6) playDuaaAfter = prefs.getBool("ah_isha_duaa", true);

  prefs.end();

  trackToPlay = constrain(trackToPlay, 1, 21);
  return true;
}

// HTTP handler to return today's prayer times as JSON
void handlePrayerTimes() {
  if (!rtc.begin()) {
    server.send(200, "application/json", "{\"error\":\"RTC missing\"}");
    return;
  }
  DateTime now = rtc.now();
  if (now.month() < 1 || now.month() > 12 || now.year() < 2020 || now.year() > 2100) {
    server.send(200, "application/json", "{\"error\":\"invalid RTC date\"}");
    return;
  }

  // PRIORITY: Check if Mawaqit times are stored and valid (synced < 25 hours ago)
  prefs.begin("adhancfg", true);
  String mq_fajr = prefs.getString("mq_fajr", "");
  String mq_sunrise = prefs.getString("mq_sunrise", "");
  String mq_dhuhr = prefs.getString("mq_dhuhr", "");
  String mq_asr = prefs.getString("mq_asr", "");
  String mq_maghrib = prefs.getString("mq_maghrib", "");
  String mq_isha = prefs.getString("mq_isha", "");
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();

  // Check if Mawaqit times are fresh (synced < 25 hours ago)
  unsigned long now_epoch = now.unixtime();
  unsigned long timeSinceSyncSec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
  bool mawaqitValid = (mq_fajr.length() >= 5) && (mq_isha.length() >= 5) && (timeSinceSyncSec < 25UL * 3600UL);

  if (mawaqitValid) {
    Serial.printf("handlePrayerTimes: Returning MAWAQIT times (synced %lu sec ago = %.1f hours)\n", timeSinceSyncSec, timeSinceSyncSec / 3600.0);
    Serial.printf("  Fajr: %s  Dhuhr: %s  Maghrib: %s  Isha: %s\n", mq_fajr.c_str(), mq_dhuhr.c_str(), mq_maghrib.c_str(), mq_isha.c_str());
    String json = "{";
    json += "\"fajr\":\"" + mq_fajr + "\",";
    json += "\"sunrise\":\"" + mq_sunrise + "\",";
    json += "\"dhuhr\":\"" + mq_dhuhr + "\",";
    json += "\"asr\":\"" + mq_asr + "\",";
    json += "\"maghrib\":\"" + mq_maghrib + "\",";
    json += "\"isha\":\"" + mq_isha + "\",";
    json += "\"source\":\"mawaqit\"";
    json += "}";
    server.send(200, "application/json", json);
    return;
  }

  // Fallback: Return CALCULATED times
  Serial.printf("handlePrayerTimes: Returning CALCULATED times (Mawaqit age: %lu sec, valid: %s)\n", timeSinceSyncSec, mawaqitValid ? "yes" : "no");
  double times[6];
  int tzMin;
  String tzSrc;
  if (!computePrayerTimesForDate(now, times, tzMin, tzSrc)) {
    server.send(200, "application/json", "{\"error\":\"location missing\"}");
    return;
  }
  // build JSON manually
  char buf[512];
  const char *names[6] = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" };
  String json = "{";
  for (int i = 0; i < 6; i++) {
    String t = formatTimeFromMinutes(times[i]);
    json += "\"" + String(names[i]) + "\":\"" + t + "\",";
  }
  // compute the next upcoming prayer (if possible) so UI can display it directly
  DateTime nextDt;
  int nextIdx = 0;
  if (computeNextPrayer(now, nextDt, nextIdx)) {
    char nbuf[32];
    snprintf(nbuf, sizeof(nbuf), "%02d:%02d", nextDt.hour(), nextDt.minute());
    char idxbuf[32];
    snprintf(idxbuf, sizeof(idxbuf), "\"next\":\"%s\",\"next_index\":%d,", nbuf, nextIdx);
    json += String(idxbuf);
  }
  char tzbuf[64];
  snprintf(tzbuf, sizeof(tzbuf), "\"tz_min\":%d,\"tz_source\":\"%s\",\"source\":\"calculated\"", tzMin, tzSrc.c_str());
  json += String(tzbuf);
  double fajrAngle, ishaAngle;
  String methodName;
  getCalculationAngles(fajrAngle, ishaAngle, methodName);
  json += ",\"calc_method\":\"" + methodName + "\",\"fajr_angle\":" + String(fajrAngle, 1) + ",\"isha_angle\":" + String(ishaAngle, 1);
  json += "}";
  server.send(200, "application/json", json);
}

// Debug endpoint: dump runtime status and stored prefs for quick inspection
void handleDumpStatus() {
  Serial.println("HTTP GET /dump_status -> handler entered");
  Serial.print("WiFi connected: ");
  Serial.println(WiFi.isConnected() ? "yes" : "no");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP().toString());
  prefs.begin("adhancfg", true);
  String lat = prefs.getString("lat", "");
  String lon = prefs.getString("lon", "");
  String acc = prefs.getString("acc", "");
  int tz = prefs.getInt("tz_offset_min", 0x7fffffff);
  String key = prefs.getString("geo_key", "");
  Serial.print("prefs: lat=");
  Serial.print(lat);
  Serial.print(" lon=");
  Serial.print(lon);
  Serial.print(" acc=");
  Serial.print(acc);
  Serial.print(" geo_key_len=");
  Serial.println((int)key.length());
  prefs.end();

  bool rtc_ok = rtc.begin();
  String rtc_time = "";
  if (rtc_ok) {
    DateTime now = rtc.now();
    char b[64];
    snprintf(b, sizeof(b), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    rtc_time = String(b);
  }

  String wifi_state = WiFi.isConnected() ? "connected" : "disconnected";
  String ip = WiFi.isConnected() ? WiFi.localIP().toString() : "";

  char out[1024];
  snprintf(out, sizeof(out), "{\"wifi\":\"%s\",\"ip\":\"%s\",\"rtc_ok\":%d,\"rtc\":\"%s\",\"lat\":\"%s\",\"lon\":\"%s\",\"acc\":\"%s\",\"tz\":%d,\"geo_key_len\":%d}",
           wifi_state.c_str(), ip.c_str(), rtc_ok ? 1 : 0, rtc_time.c_str(), lat.c_str(), lon.c_str(), acc.c_str(), (tz == 0x7fffffff ? -9999 : tz), (int)key.length());
  server.send(200, "application/json", String(out));
}

// ---------------- DS3231 alarm helpers (I2C register access + Alarm2 daily) ----------------
static inline uint8_t decToBcd(uint8_t val) {
  return ((val / 10) << 4) | (val % 10);
}
static inline uint8_t bcdToDec(uint8_t val) {
  return ((val >> 4) * 10) + (val & 0x0F);
}

// Write a single register to DS3231 (addr 0x68)
void ds3231WriteReg(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(0x68);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

// Read a single register from DS3231
uint8_t ds3231ReadReg(uint8_t reg) {
  Wire.beginTransmission(0x68);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(0x68, (uint8_t)1);
  if (Wire.available()) return Wire.read();
  return 0;
}

// Clear alarm flags A1F/A2F in status register (0x0F)
void ds3231ClearAlarmFlags() {
  uint8_t status = ds3231ReadReg(0x0F);
  status &= ~0x03;  // clear A2F (bit1) and A1F (bit0)
  ds3231WriteReg(0x0F, status);
}

// Enable Alarm2 interrupt (and INTCN) in control reg (0x0E)
void ds3231EnableAlarm2Interrupt() {
  uint8_t ctrl = ds3231ReadReg(0x0E);
  ctrl |= 0x06;  // INTCN (bit2) + A2IE (bit1)
  ds3231WriteReg(0x0E, ctrl);
  ds3231ClearAlarmFlags();
}

// Disable alarm interrupts
void ds3231DisableAlarms() {
  uint8_t ctrl = ds3231ReadReg(0x0E);
  ctrl &= ~0x06;  // clear INTCN and A2IE
  ds3231WriteReg(0x0E, ctrl);
  ds3231ClearAlarmFlags();
}

// Set Alarm2 to trigger daily at given hour/minute (minute resolution)
// Uses Alarm2 registers 0x0B (min), 0x0C (hour), 0x0D (day/date)
bool ds3231SetAlarm2Daily(uint8_t hour, uint8_t minute) {
  if (hour > 23 || minute > 59) return false;
  // A2M2 (min) = 0 -> match minute
  uint8_t minReg = decToBcd(minute) & 0x7F;  // ensure MSB=0
  // A2M3 (hour) = 0 -> match hour; keep 24-hour mode (bit6=0)
  uint8_t hourReg = decToBcd(hour) & 0x3F;
  // A2M4 (day) = 1 -> ignore day/date (daily)
  uint8_t dayReg = 0x80 | decToBcd(1);
  ds3231WriteReg(0x0B, minReg);
  ds3231WriteReg(0x0C, hourReg);
  ds3231WriteReg(0x0D, dayReg);
  ds3231EnableAlarm2Interrupt();
  return true;
}

// ---------------- I2C diagnostics helpers ----------------
void scanI2CBusAndReport() {
  Serial.println("I2C bus scan start...");
  uint8_t found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    uint8_t err = Wire.endTransmission();
    if (err == 0) {
      Serial.printf("I2C device found at 0x%02X\n", addr);
      found++;
    }
  }
  if (found == 0) {
    Serial.println("I2C scan done: no devices found");
  } else {
    Serial.printf("I2C scan done: %u device(s) found\n", found);
  }
}

void probeIP5306() {
  // Try multiple possible I2C addresses for IP5306 on Wire bus (shared with DS3231)
  const uint8_t ip5306Addrs[] = { 0x74, 0x75, 0x76, 0x77 };
  bool found = false;
  for (int i = 0; i < 4; i++) {
    Wire.beginTransmission(ip5306Addrs[i]);
    uint8_t err = Wire.endTransmission();
    if (err == 0) {
      Serial.printf("IP5306 probe: detected at 0x%02X (I2C communication OK!)\n", ip5306Addrs[i]);
      found = true;
      break;
    }
  }
  if (!found) {
    Serial.println("IP5306 probe: not detected at 0x74/0x75/0x76/0x77");
    Serial.println("Check: GPIO8/9 bridged to GPIO4/5, pullups, power, and connections.");
  }
}

// ISR for DS3231 INT pin
void IRAM_ATTR ds3231_isr() {
  ds3231AlarmFlag = true;
}

// Compute the next prayer time (DateTime) and index (1..6) from now
// Returns true if found and fills nextDt and idx
bool computeNextPrayer(const DateTime &now, DateTime &nextDt, int &idx) {
  if (now.month() < 1 || now.month() > 12 || now.year() < 2020 || now.year() > 2100) return false;
  // 1) Prefer fresh stored Mawaqit times when available (already offset-adjusted at sync time).
  prefs.begin("adhancfg", true);
  String mq[6] = {
    prefs.getString("mq_fajr", ""),
    prefs.getString("mq_sunrise", ""),
    prefs.getString("mq_dhuhr", ""),
    prefs.getString("mq_asr", ""),
    prefs.getString("mq_maghrib", ""),
    prefs.getString("mq_isha", "")
  };
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();

  unsigned long now_epoch = now.unixtime();
  unsigned long age_sec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
  bool mqValid = (mq[0].length() >= 5) && (mq[5].length() >= 5) && (age_sec < 25UL * 3600UL);

  auto parseHHMM = [&](const String &t, int &h, int &m) -> bool {
    if (t.length() < 5) return false;
    h = t.substring(0, 2).toInt();
    m = t.substring(3, 5).toInt();
    return (h >= 0 && h < 24 && m >= 0 && m < 60);
  };

  if (mqValid) {
    for (int i = 0; i < 6; i++) {
      int h = 0, m = 0;
      if (!parseHHMM(mq[i], h, m)) continue;
      DateTime cand(now.year(), now.month(), now.day(), h, m, 0);
      if (cand.unixtime() > now.unixtime() + 5) {
        nextDt = cand;
        idx = i + 1;
        return true;
      }
    }
    // if all today's times are past, use tomorrow's first valid Mawaqit time
    for (int i = 0; i < 6; i++) {
      int h = 0, m = 0;
      if (!parseHHMM(mq[i], h, m)) continue;
      DateTime tomorrow = now + TimeSpan(1, 0, 0, 0);
      nextDt = DateTime(tomorrow.year(), tomorrow.month(), tomorrow.day(), h, m, 0);
      idx = i + 1;
      return true;
    }
  }

  // 2) Fallback to calculated times (with fine-tuning offsets applied).
  double timesToday[6];
  double timesTomorrow[6];
  int tzDummy = 0;
  String tzSrc;

  if (!computePrayerTimesForDate(now, timesToday, tzDummy, tzSrc)) return false;

  DateTime tomorrow = now + TimeSpan(1, 0, 0, 0);
  if (!computePrayerTimesForDate(tomorrow, timesTomorrow, tzDummy, tzSrc)) return false;

  // Compare today then tomorrow to find the next > now
  for (int i = 0; i < 6; i++) {
    double tmin = timesToday[i];
    if (!isnan(tmin)) {
      DateTime candidate = DateTime(now.year(), now.month(), now.day(), 0, 0, 0) + TimeSpan(0, (int)(tmin / 60), (int)fmod(tmin, 60), 0);
      // candidate rounding: use minutes precision
      int candMin = (int)round(tmin);
      int ch = (candMin / 60) % 24;
      int cm = candMin % 60;
      candidate = DateTime(now.year(), now.month(), now.day(), ch, cm, 0);
      if (candidate.unixtime() > now.unixtime() + 5) {  // a small safety margin
        nextDt = candidate;
        idx = i + 1;
        return true;
      }
    }
  }
  for (int i = 0; i < 6; i++) {
    double tmin = timesTomorrow[i];
    if (!isnan(tmin)) {
      int candMin = (int)round(tmin);
      int ch = (candMin / 60) % 24;
      int cm = candMin % 60;
      nextDt = DateTime(tomorrow.year(), tomorrow.month(), tomorrow.day(), ch, cm, 0);
      idx = i + 1;
      return true;
    }
  }
  return false;
}

// Schedule next prayer alarm: computes next prayer, programs Alarm2 daily at that hh:mm
void scheduleNextPrayerAlarm() {
  if (!rtc.begin()) return;
  DateTime now = rtc.now();
  // Guard against corrupt RTC data (I2C bus issue) to avoid out-of-bounds crash in dayOfYear()
  if (now.month() < 1 || now.month() > 12 || now.day() < 1 || now.day() > 31 || now.year() < 2020 || now.year() > 2100) {
    Serial.printf("scheduleNextPrayerAlarm: invalid RTC date %04u-%02u-%02u, skipping\n", now.year(), now.month(), now.day());
    return;
  }
  DateTime nextDt;
  int idx;
  if (computeNextPrayer(now, nextDt, idx)) {
    scheduledPrayerIndex = idx;
    scheduledPrayerTime = nextDt;
    ds3231SetAlarm2Daily(nextDt.hour(), nextDt.minute());
    // Also schedule a software fallback alarm based on millis() to ensure
    // the prayer triggers even if the DS3231 interrupt/flag is missed.
    unsigned long deltaSec = 0;
    uint32_t nowUnix = now.unixtime();
    uint32_t nextUnix = nextDt.unixtime();
    if (nextUnix > nowUnix) deltaSec = nextUnix - nowUnix;
    if (deltaSec > 0 && deltaSec < (7UL * 24UL * 3600UL)) {
      // convert to ms, guard overflow
      unsigned long deltaMs = (unsigned long)deltaSec * 1000UL;
      softwareAlarmAt = millis() + deltaMs;
      Serial.printf("Scheduled alarm for prayer %d at %04u-%02u-%02u %02d:%02d (in %lu s, software fallback set)\n", idx, nextDt.year(), nextDt.month(), nextDt.day(), nextDt.hour(), nextDt.minute(), deltaSec);
    } else {
      softwareAlarmAt = 0;
      Serial.printf("Scheduled alarm for prayer %d at %04u-%02u-%02u %02d:%02d (software fallback not set)\n", idx, nextDt.year(), nextDt.month(), nextDt.day(), nextDt.hour(), nextDt.minute());
    }
  } else {
    scheduledPrayerIndex = 0;
    softwareAlarmAt = 0;
    Serial.println("Could not compute next prayer to schedule alarm.");
  }
}

// Try to (re)initialize the DFPlayer module and clear missing-file state.
bool tryRecoverDFPlayer(int retries = 2) {
  for (int i = 0; i < retries; i++) {
    Serial.printf("Attempting DFPlayer reinit (%d/%d)\n", i + 1, retries);
    // re-init over Serial2; ask the library to reset the module on first attempt
    if (dfplayer.begin(Serial2, /*isACK=*/true, /*doReset=*/(i == 0))) {
      dfAvailable = true;
      dfFileMissing = false;
      dfLastError = DFERR_NONE;
      Serial.println("DFPlayer reinitialized successfully");
      // restore volume
      prefs.begin("adhancfg", true);
      int storedVol = prefs.getInt("volume", 20);
      prefs.end();
      storedVol = constrain(storedVol, 0, 30);
      dfplayer.volume(storedVol);
      Serial.printf("DFPlayer volume restored to %d\n", storedVol);
      return true;
    }
    delay(250);
  }
  dfAvailable = false;
  dfLastError = DFERR_OTHER;
  Serial.println("DFPlayer reinit attempts failed");
  return false;
}

// Play a track number on DFPlayer (1-based)
// For prayer adhan: Fajr plays track 3, others play track 2, then track 1 (duaa) plays after
void playTrack(int track) {
  // Always attempt to ensure DFPlayer available
  if (!dfAvailable) {
    Serial.println("DFPlayer not available, attempting reinit...");
    if (!tryRecoverDFPlayer(2)) {
      Serial.println("Cannot play: DFPlayer unavailable");
      return;
    }
  }

  // If the DFPlayer previously reported missing files, try to recover
  if (dfFileMissing) {
    Serial.println("DFPlayer previously reported missing files; attempting recovery before play");
    tryRecoverDFPlayer(2);
    // clear the missing flag to allow play attempts
    dfFileMissing = false;
  }

  Serial.printf("Playing track %d\n", track);
  // Clear last DFPlayer error and request play
  dfLastError = DFERR_NONE;
  dfplayer.playMp3Folder(track);
  isPlaying = true;

  // Wait briefly to catch immediate DFPlayer errors (FileIndexOut / TimeOut)
  unsigned long start = millis();
  while (millis() - start < 800) {
    if (dfLastError != DFERR_NONE) {
      // If an error occurs even after recovery, log and stop trying
      Serial.printf("DFPlayer error after play request: %d\n", dfLastError);
      break;
    }
    delay(50);
  }
}

void stopPlay() {
  // Cancel pending duaa BEFORE stopping so the PlayFinished event (if fired by stop) doesn't trigger it
  shouldPlayDuaaAfterAdhan = false;
  adhanTrackBeforeDuaa = 0;
  // Restore LED scenario if prayer scene was active
  if (prayerPrevLedScenario >= 0) {
    ledScenario = prayerPrevLedScenario;
    prayerPrevLedScenario = -1;
    Serial.printf("LED restored to scenario %d after stop\n", ledScenario);
  }
  if (dfAvailable) {
    dfplayer.stop();
    Serial.println("Stopped playback");
    isPlaying = false;
    prefs.begin("adhancfg", true);
    int storedVol = prefs.getInt("volume", 20);
    prefs.end();
    dfplayer.volume(storedVol);
    Serial.printf("DFPlayer volume restored to %d on stop\n", storedVol);
  }
}

// Print DFPlayer event/error details (copied/adapted from DFPlayer example)
void printDetail(uint8_t type, int value) {
  switch (type) {
    case TimeOut:
      Serial.println(F("Time Out!"));
      dfLastError = DFERR_TIMEOUT;
      break;
    case WrongStack:
      Serial.println(F("Stack Wrong!"));
      break;
    case DFPlayerCardInserted:
      Serial.println(F("Card Inserted!"));
      dfFileMissing = false;
      dfLastError = DFERR_NONE;
      break;
    case DFPlayerCardRemoved:
      Serial.println(F("Card Removed!"));
      break;
    case DFPlayerCardOnline:
      Serial.println(F("Card Online!"));
      dfLastError = DFERR_NONE;
      break;
    case DFPlayerUSBInserted:
      Serial.println(F("USB Inserted!"));
      break;
    case DFPlayerUSBRemoved:
      Serial.println(F("USB Removed!"));
      break;
    case DFPlayerPlayFinished:
      Serial.print(F("Number:"));
      Serial.print(value);
      Serial.println(F(" Play Finished!"));
      isPlaying = false;
      dfLastError = DFERR_NONE;
      // Play duaa (track 1) after adhan finishes.
      // NOTE: we do NOT compare value==adhanTrackBeforeDuaa because some DFPlayer
      // clones report a global file index instead of the MP3-folder track number,
      // making the comparison unreliable. stopPlay() resets shouldPlayDuaaAfterAdhan
      // to prevent duaa from firing after a manual stop.
      if (shouldPlayDuaaAfterAdhan && adhanTrackBeforeDuaa > 0) {
        int playedAdhanTrack = adhanTrackBeforeDuaa;
        shouldPlayDuaaAfterAdhan = false;
        adhanTrackBeforeDuaa = 0;
        Serial.printf("Adhan (track %d) finished, playing duaa (track 1)...\n", playedAdhanTrack);
        delay(500);  // short pause before duaa
        playTrack(1);
      } else {
        // All playback done (adhan only, or duaa just finished) — restore LED
        if (prayerPrevLedScenario >= 0) {
          ledScenario = prayerPrevLedScenario;
          prayerPrevLedScenario = -1;
          Serial.printf("LED restored to scenario %d after playback\n", ledScenario);
        }
        // Restore volume
        prefs.begin("adhancfg", true);
        int storedVol = prefs.getInt("volume", 20);
        prefs.end();
        if (dfAvailable) {
          dfplayer.volume(storedVol);
          Serial.printf("DFPlayer volume restored to %d after playback\n", storedVol);
        }
      }
      break;
    case DFPlayerError:
      Serial.print(F("DFPlayerError:"));
      switch (value) {
        case Busy:
          Serial.println(F("Card not found"));
          break;
        case Sleeping:
          Serial.println(F("Sleeping"));
          break;
        case SerialWrongStack:
          Serial.println(F("Get Wrong Stack"));
          break;
        case CheckSumNotMatch:
          Serial.println(F("Check Sum Not Match"));
          break;
        case FileIndexOut:
          Serial.println(F("File Index Out of Bound"));
          dfFileMissing = true;
          dfLastError = DFERR_FILEINDEXOUT;
          break;
        case FileMismatch:
          Serial.println(F("Cannot Find File"));
          break;
        case Advertise:
          Serial.println(F("In Advertise"));
          break;
        default:
          Serial.println(F("Unknown DFPlayer error"));
          dfLastError = DFERR_OTHER;
          break;
      }
      break;
    default:
      break;
  }
}

// ── MQTT callback ─────────────────────────────────────────────────────────────
void mqttCallback(char *topic, byte *payload, unsigned int len) {
  char msg[len + 1];
  memcpy(msg, payload, len);
  msg[len] = '\0';
  Serial.printf("[MQTT] %s → %s\n", topic, msg);

  if (strcmp(topic, TOPIC_ADHAN_TRIGGER) == 0) {
    int track = (len > 0) ? atoi(msg) : 2;
    if (track < 2) track = 2;  // jamais track 1 (duaa) comme adhan
    shouldPlayDuaaAfterAdhan = true;
    adhanTrackBeforeDuaa = track;
    // Activate prayer LED scene
    if (prayerPrevLedScenario < 0) {
      prayerPrevLedScenario = ledScenario;
      ledScenario = SCENE_PRAYER;
      Serial.printf("MQTT adhan: LED switched to PRAYER scene (was %d)\n", prayerPrevLedScenario);
    }
    playTrack(track);
    mqtt.publish(TOPIC_AUDIO_STATUS, "playing");

  } else if (strcmp(topic, TOPIC_AUDIO_PLAY) == 0) {
    int track = atoi(msg);
    if (track > 0) {
      playTrack(track);
      mqtt.publish(TOPIC_AUDIO_STATUS, "playing");
    }

  } else if (strcmp(topic, TOPIC_AUDIO_STOP) == 0) {
    stopPlay();
    mqtt.publish(TOPIC_AUDIO_STATUS, "stopped");

  } else if (strcmp(topic, TOPIC_AUDIO_VOLUME) == 0) {
    int vol = constrain(atoi(msg), 0, 30);
    if (dfAvailable) dfplayer.volume(vol);
    prefs.begin("adhancfg", false);
    prefs.putInt("volume", vol);
    prefs.end();

  } else if (strcmp(topic, TOPIC_LED_SCENARIO) == 0) {
    int sc = atoi(msg);
    if (sc >= 0 && sc < TOTAL_SCENES) {
      ledScenario = sc;
      prefs.begin("adhancfg", false);
      prefs.putInt("led_scenario", sc);
      prefs.end();
    }

  } else if (strcmp(topic, TOPIC_LED_BRIGHTNESS) == 0) {
    int br = constrain(atoi(msg), 0, 100);
    ledBrightness = br;
    prefs.begin("adhancfg", false);
    prefs.putInt("brightness", br);
    prefs.end();
  }
}

// ── MQTT reconnect ─────────────────────────────────────────────────────────────
void reconnectMQTT() {
  static unsigned long lastAttempt = 0;
  if (millis() - lastAttempt < MQTT_RECONNECT_MS) return;
  lastAttempt = millis();

  prefs.begin("adhancfg", true);
  String broker = prefs.getString("mqtt_broker", "");
  prefs.end();
  if (broker.length() == 0) return;  // broker pas encore configuré

  mqtt.setServer(broker.c_str(), MQTT_PORT);
  mqtt.setCallback(mqttCallback);

  Serial.printf("[MQTT] Connecting to %s…\n", broker.c_str());
  if (mqtt.connect(MQTT_CLIENT_ID)) {
    Serial.println("[MQTT] Connected");
    mqtt.subscribe(TOPIC_ADHAN_TRIGGER);
    mqtt.subscribe(TOPIC_AUDIO_PLAY);
    mqtt.subscribe(TOPIC_AUDIO_STOP);
    mqtt.subscribe(TOPIC_AUDIO_VOLUME);
    mqtt.subscribe(TOPIC_LED_SCENARIO);
    mqtt.subscribe(TOPIC_LED_BRIGHTNESS);
    mqttPublishStatus();
  } else {
    Serial.printf("[MQTT] Failed rc=%d — retry in %lus\n", mqtt.state(), MQTT_RECONNECT_MS / 1000);
  }
}

// ── MQTT publish helpers ────────────────────────────────────────────────────────
void mqttPublishStatus() {
  if (!mqtt.connected()) return;
  char buf[128];
  snprintf(buf, sizeof(buf),
           "{\"ip\":\"%s\",\"rssi\":%d,\"playing\":%s,\"led\":%d,\"brightness\":%d}",
           WiFi.localIP().toString().c_str(),
           WiFi.RSSI(),
           isPlaying ? "true" : "false",
           ledScenario,
           ledBrightness);
  mqtt.publish(TOPIC_STATUS, buf, /*retain=*/true);
}

void mqttPublishPrayerFired(int prayerIndex) {
  if (!mqtt.connected()) return;
  char buf[32];
  snprintf(buf, sizeof(buf), "{\"prayer\":%d}", prayerIndex);
  mqtt.publish(TOPIC_PRAYER_FIRED, buf);
}

// ── HTTP handler : config broker MQTT ─────────────────────────────────────────
void handleMqttConfig() {
  if (server.method() == HTTP_POST) {
    if (!requireApiKey()) return;
    String body = getRequestBody();
    String broker = parseJsonString(body, "broker");
    if (broker.length() == 0) {
      broker = server.arg("broker");
    }
    broker.trim();
    prefs.begin("adhancfg", false);
    prefs.putString("mqtt_broker", broker);
    prefs.end();
    mqtt.setServer(broker.c_str(), MQTT_PORT);
    mqtt.setCallback(mqttCallback);
    server.send(200, "application/json", "{\"ok\":true}");
  } else {
    prefs.begin("adhancfg", true);
    String broker = prefs.getString("mqtt_broker", "");
    prefs.end();
    String json = "{\"broker\":\"" + broker + "\",\"connected\":" + (mqtt.connected() ? "true" : "false") + "}";
    server.send(200, "application/json", json);
  }
}

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("AdhanBox config AP sketch starting...");

  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);

  // Initialize Serial2 for DFPlayer on GPIO1 (RX) and GPIO2 (TX)
  // Note: using GPIO1 may interfere with USB-serial console output.
  Serial2.begin(9600, SERIAL_8N1, DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);
  Serial.printf("Serial2 for DFPlayer configured RX=%d TX=%d\n", DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);

  // Initialize DFPlayer over Serial2 with ACK and reset (better detection)
  // Load preferences first (always loaded on boot, independent of DFPlayer detection)
  prefs.begin("adhancfg", true);
  int storedVol = prefs.getInt("volume", 20);
  forcePlayTrack1 = prefs.getBool("force_t1", false);
  ledBrightness = prefs.getInt("brightness", 50);
  ledScenario = prefs.getInt("led_scenario", 8);
  prefs.end();

  // Initialize DFPlayer over Serial2 (using fire-and-forget, no ACK to prevent boot hangs)
  if (dfplayer.begin(Serial2, /*isACK=*/false, /*doReset=*/true)) {
    dfAvailable = true;
    Serial.println("DFPlayer initialized");
    storedVol = constrain(storedVol, 0, 30);
    dfplayer.volume(storedVol);
    Serial.printf("DFPlayer volume set to %d\n", storedVol);
    Serial.printf("forcePlayTrack1 preference = %s\n", forcePlayTrack1 ? "ON" : "OFF");
  } else {
    dfAvailable = false;
    Serial.println("DFPlayer not detected. Check wiring and power.");
  }

  // Initialize I2C bus (Wire) for DS3231 + IP5306:
  // SDA -> GPIO5, SCL -> GPIO4
  // Proper I2C bus recovery: master drives both lines, clocks SCL 9 times
  // to force any stuck slave to release SDA, then generates a real STOP condition.
  pinMode(4, OUTPUT);
  digitalWrite(5, HIGH);  // SDA driven HIGH by master
  pinMode(5, OUTPUT);
  digitalWrite(4, HIGH);  // SCL HIGH
  delayMicroseconds(10);
  for (int i = 0; i < 9; i++) {
    digitalWrite(4, LOW);
    delayMicroseconds(5);  // SCL falling
    digitalWrite(4, HIGH);
    delayMicroseconds(5);  // SCL rising
  }
  // Real STOP: SDA LOW while SCL HIGH, then SDA HIGH
  digitalWrite(5, LOW);
  delayMicroseconds(5);
  digitalWrite(4, HIGH);
  delayMicroseconds(5);  // SCL already high
  digitalWrite(5, HIGH);
  delayMicroseconds(5);  // SDA rising edge = STOP
  pinMode(4, INPUT_PULLUP);
  pinMode(5, INPUT_PULLUP);
  delay(10);

  Wire.begin(/*sda=*/5, /*scl=*/4);
  // Reinforce internal pull-ups explicitly (ESP-IDF level, ~45 kΩ)
  gpio_set_pull_mode((gpio_num_t)4, GPIO_PULLUP_ONLY);
  gpio_set_pull_mode((gpio_num_t)5, GPIO_PULLUP_ONLY);
  delay(50);
  Serial.println("I2C bus initialized: SDA=GPIO5, SCL=GPIO4");
  scanI2CBusAndReport();
  probeIP5306();

  // Initialize DS3231 RTC using RTClib
  if (!rtc.begin()) {
    Serial.println("Couldn't find RTC. Check wiring (VCC/GND/SDA/SCL) and power.");
  } else {
    if (rtc.lostPower()) {
      Serial.println("RTC lost power, setting time to compile time.");
      rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
    }
    Serial.println("RTC ready.");
    DateTime now = rtc.now();
    char buf[64];
    snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    Serial.print("Current RTC time: ");
    Serial.println(buf);
    // Configure DS3231 INT pin and attach ISR (requires hardware INT from DS3231)
    Serial.printf("Attaching DS3231 INT on pin %d (SQW)\n", DS3231_INT_PIN);
    pinMode(DS3231_INT_PIN, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(DS3231_INT_PIN), ds3231_isr, FALLING);
  }

  // LED data pin (do not use GPIO1/GPIO3). Configure LEDC timer + channel using driver API.
  ledc_timer_config_t ledc_timer = {
    .speed_mode = LEDC_LOW_SPEED_MODE,
    .duty_resolution = (ledc_timer_bit_t)LEDC_RES,
    .timer_num = LEDC_TIMER_0,
    .freq_hz = LEDC_FREQ,
    .clk_cfg = LEDC_AUTO_CLK
  };
  ledc_timer_config(&ledc_timer);
  ledc_channel_config_t ledc_channel = {
    .gpio_num = LED_DATA_PIN,
    .speed_mode = LEDC_LOW_SPEED_MODE,
    .channel = (ledc_channel_t)LEDC_CHANNEL,
    .intr_type = LEDC_INTR_DISABLE,
    .timer_sel = LEDC_TIMER_0,
    .duty = 0,
    .hpoint = 0
  };
  // Only attach LEDC channel to the GPIO if not using addressable LEDs.
  if (!useAddressableLEDs) {
    ledc_channel_config(&ledc_channel);
  } else {
    Serial.println("Skipping LEDC attach because addressable LEDs are enabled");
  }
  setLedDuty(0);

  // If no geo_key stored, seed with provided HERE API key (user-supplied)
  prefs.begin("adhancfg", true);
  String existingKey = prefs.getString("geo_key", "");
  prefs.end();
  if (existingKey.length() == 0) {
    prefs.begin("adhancfg", false);
    prefs.putString("geo_key", "bGuRaRQN7kTgVCUQhL5He5ffERIa-4rVRfVJ6lEKK0g");
    prefs.end();
    Serial.println("Default HERE geo_key written to prefs");
  }

  // ── Security: generate random OTA password and API token at first boot ──────
  // Charset excludes visually ambiguous characters (0/O, 1/I/l)
  static const char SEC_CHARSET[] = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  randomSeed(esp_random());  // hardware RNG
  prefs.begin("adhancfg", true);
  _otaPass = prefs.getString("ota_pass", "");
  _apiToken = prefs.getString("api_token", "");
  prefs.end();
  if (_otaPass.length() == 0) {
    for (int i = 0; i < 12; i++) _otaPass += SEC_CHARSET[random(sizeof(SEC_CHARSET) - 1)];
    prefs.begin("adhancfg", false);
    prefs.putString("ota_pass", _otaPass);
    prefs.end();
    Serial.printf("Generated OTA password: %s (store this!)\n", _otaPass.c_str());
  }
  if (_apiToken.length() == 0) {
    for (int i = 0; i < 16; i++) _apiToken += SEC_CHARSET[random(sizeof(SEC_CHARSET) - 1)];
    prefs.begin("adhancfg", false);
    prefs.putString("api_token", _apiToken);
    prefs.end();
    Serial.printf("Generated API token: %s (store this!)\n", _apiToken.c_str());
  }

  // Initialize addressable strip (native driver) if enabled
  if (useAddressableLEDs) {
    // Initialize Adafruit_NeoPixel library
    leds.begin();
    // send initial black frame to clear strip
    leds.clear();
    leds.show();
    delay(50);
    // send a couple more zero frames to ensure reset
    for (int i = 0; i < 2; i++) {
      stripSetAll(0, 0, 0);
      delay(20);
    }
    Serial.printf("Addressable LED strip (Adafruit_NeoPixel) initialized (%u LEDs) on pin %d\n", (uint32_t)LED_NUM, LED_DATA_PIN);
  }

  // Print stored location if any
  double lat, lon, acc;
  if (loadStoredLocation(lat, lon, acc)) {
    Serial.printf("Loaded stored location: %f, %f (acc=%f)\n", lat, lon, acc);
  } else {
    Serial.println("No stored location yet.");
  }

  // Decoupled alarm scheduling: Always schedule on boot if RTC is present (covers Mawaqit-only setups)
  if (rtc.begin()) {
    Serial.println("Scheduling next prayer alarm on startup...");
    scheduleNextPrayerAlarm();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOOT : BLE actif jusqu'à config, bouton, ou 5 min d'inactivité
  // ══════════════════════════════════════════════════════════════════════════
  bool wifiConnected = false;

#if ENABLE_BLE
  Serial.println("\n══ BLE provisioning actif ══");
  Serial.println("   Appui bouton = quitter | 5 min sans connexion = quitter auto");
  startBLEProvisioning();

  // Attendre 300ms que le GPIO se stabilise avant de surveiller le bouton
  delay(300);
  bool btnWasHigh = (digitalRead(CONFIG_BUTTON_PIN) == HIGH);

  // Timeout inactivité : 5 minutes sans qu'aucun client ne se connecte
  const unsigned long BLE_INACTIVITY_TIMEOUT_MS = 5UL * 60UL * 1000UL; // 5 min
  unsigned long bleInactivityTimer = millis();
  bool bleHadClient = false;

  while (true) {
    unsigned long now = millis();

    // LED rouge clignotante
    if (useAddressableLEDs) {
      if ((now / 300) % 2 == 0) stripSetAll(200, 0, 0);
      else stripSetAll(0, 0, 0);
    } else {
      if ((now / 300) % 2 == 0) setLedDuty(220);
      else setLedDuty(0);
    }

    // Si credentials BLE reçus → traiter
    if (_bleCredsReady) {
      Serial.println("[BLE] Credentials recues — connexion WiFi en cours...");
      handleBLEProvisioning();
      if (WiFi.status() == WL_CONNECTED) {
        wifiConnected = true;
      }
      break;
    }

    // Suivre la connexion client pour réinitialiser le timer d'inactivité
    if (_bleClientConn && !bleHadClient) {
      bleHadClient = true;
      bleInactivityTimer = now;
      Serial.println("[BLE] Client connecte — timer d'inactivite reinitialise.");
    }
    if (!_bleClientConn && bleHadClient) {
      bleHadClient = false;
      bleInactivityTimer = now;
    }

    // Timeout inactivité : 5 min
    if (now - bleInactivityTimer >= BLE_INACTIVITY_TIMEOUT_MS) {
      Serial.println("[BLE] 5 min d'inactivite — arret automatique du BLE.");
      break;
    }

    // Bouton tactile : arrêt manuel (transition HIGH→LOW uniquement, anti-rebond)
    bool btnNow = (digitalRead(CONFIG_BUTTON_PIN) == HIGH);
    if (btnWasHigh && !btnNow) {
      delay(80);
      if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        Serial.println("[BLE] Bouton appuye — arret manuel du BLE.");
        break;
      }
    }
    btnWasHigh = btnNow;

    delay(100);
  }

  // Arrêter le BLE s'il est encore actif
  if (_bleActive) {
    stopBLEProvisioning();
    delay(100);
  }
#endif

  // ── Fonctionnement normal : connexion WiFi ou hors-ligne ──
  prefs.begin("adhancfg", true);
  String savedSSID = prefs.getString("wifi_ssid", "");
  String savedPass = prefs.getString("wifi_pass", "");
  prefs.end();

  // Ne tenter le WiFi que si pas déjà connecté via BLE provisioning
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.printf("WiFi deja connecte (via BLE) — IP=%s\n", WiFi.localIP().toString().c_str());
  } else if (savedSSID.length() > 0) {
    Serial.printf("Tentative WiFi: SSID=%s\n", savedSSID.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(savedSSID.c_str(), savedPass.c_str());

    unsigned long start = millis();
    while (millis() - start < 15000) {
      if (WiFi.status() == WL_CONNECTED) break;
      delay(500);
      Serial.print(".");
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("\n✓ WiFi connecte! IP=%s\n", WiFi.localIP().toString().c_str());
      wifiConnected = true;
      wifiConnectState = WCS_CONNECTED;
      Serial.println("Synchro NTP au boot...");
      if (syncTimeFromNtp(15000)) Serial.println("NTP OK.");
      else Serial.println("NTP echoue.");
      if (rtc.begin()) scheduleNextPrayerAlarm();
    } else {
      Serial.println("\n✗ WiFi echoue.");
    }
  } else {
    Serial.println("Aucun WiFi sauvegarde — mode hors-ligne.");
  }

  if (wifiConnected) {
    startServices();
  } else {
    Serial.println("Mode hors-ligne — horaires locaux (calcul/RTC) actifs.");
  }

  Serial.println("Commandes serie: startap, stopap, startble, stopble, showloc");
}

void loop() {
#if ENABLE_BLE
  // Handle BLE provisioning credentials (received in BLE task, processed here)
  if (_bleActive) {
    handleBLEProvisioning();

    // Auto-stop BLE provisioning in loop after inactivity timeout (if triggered manually)
    static bool loopBleHadClient = false;
    static unsigned long loopBleInactivityTimer = 0;
    static bool lastBleState = false;

    if (_bleActive && !lastBleState) {
      loopBleInactivityTimer = millis();
      loopBleHadClient = _bleClientConn;
    }
    lastBleState = _bleActive;

    if (_bleClientConn && !loopBleHadClient) {
      loopBleHadClient = true;
      loopBleInactivityTimer = millis();
      Serial.println("[BLE] Client connecté (loop) — timer d'inactivité réinitialisé.");
    }
    if (!_bleClientConn && loopBleHadClient) {
      loopBleHadClient = false;
      loopBleInactivityTimer = millis();
    }

    if (millis() - loopBleInactivityTimer >= 5UL * 60UL * 1000UL) {
      Serial.println("[BLE] 5 min d'inactivité (loop) — arrêt automatique du BLE.");
      stopBLEProvisioning();
    }
  }
#endif

  // If you have a config button connected, you can re-enable checkConfigButton();
  checkConfigButton();

  // Simple serial command interface for testing without a button
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.equalsIgnoreCase("startap")) {
      startConfigAP();
      Serial.println("AP started via serial command");
#if ENABLE_BLE
    } else if (cmd.equalsIgnoreCase("startble")) {
      if (!_bleActive) {
        startBLEProvisioning();
        Serial.println("BLE provisioning started via serial command");
      } else {
        Serial.println("BLE already active");
      }
    } else if (cmd.equalsIgnoreCase("stopble")) {
      stopBLEProvisioning();
      Serial.println("BLE provisioning stopped via serial command");
#endif
    } else if (cmd.equalsIgnoreCase("stopap")) {
      stopConfigAP();
      Serial.println("AP stopped via serial command");
    } else if (cmd.equalsIgnoreCase("showloc")) {
      double lt, ln, ac;
      if (loadStoredLocation(lt, ln, ac)) {
        Serial.printf("Stored location: %f, %f (acc=%f)\n", lt, ln, ac);
      } else {
        Serial.println("No stored location saved yet.");
      }
    } else if (cmd.equalsIgnoreCase("showtime")) {
      if (rtc.begin()) {
        DateTime now = rtc.now();
        char buf[64];
        snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
        Serial.print("RTC: ");
        Serial.println(buf);
      } else {
        Serial.println("RTC not initialized or not present.");
      }
    } else if (cmd.equalsIgnoreCase("setrtc")) {

      // set RTC to compile time
      if (rtc.begin()) {
        rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
        Serial.println("RTC set to compile time.");
        scheduleNextPrayerAlarm();
      } else {
        Serial.println("RTC not initialized or not present.");
      }
    } else if (cmd.equalsIgnoreCase("showtimes")) {
      if (rtc.begin()) {
        DateTime now = rtc.now();
        computeAndPrintPrayerTimes(now);
      } else {
        // if RTC not available, use compile date as fallback
        Serial.println("RTC not present, using compile date for times (approx).");
        DateTime fallback(F(__DATE__), F(__TIME__));
        computeAndPrintPrayerTimes(fallback);
      }

    } else if (cmd.equalsIgnoreCase("setalarmtest")) {
      // set an alarm for the next minute (test)
      if (rtc.begin()) {
        DateTime now = rtc.now();
        int mm = (now.minute() + 1) % 60;
        int hh = now.hour() + (now.minute() == 59 ? 1 : 0);
        ds3231SetAlarm2Daily(hh, mm);
        scheduledPrayerIndex = 1;  // test play track 1
        scheduledPrayerTime = DateTime(now.year(), now.month(), now.day(), hh % 24, mm, 0);
        Serial.printf("Test alarm set for %02d:%02d\n", hh % 24, mm);
      } else {
        Serial.println("RTC not present; cannot set alarm.");
      }
    } else if (cmd.equalsIgnoreCase("cancelalarms")) {
      ds3231DisableAlarms();
      Serial.println("DS3231 alarms disabled and cleared.");
    } else if (cmd.equalsIgnoreCase("shownextalarm")) {
      if (scheduledPrayerIndex > 0) {
        Serial.printf("Next scheduled prayer %d at %04u-%02u-%02u %02d:%02d\n", scheduledPrayerIndex, scheduledPrayerTime.year(), scheduledPrayerTime.month(), scheduledPrayerTime.day(), scheduledPrayerTime.hour(), scheduledPrayerTime.minute());
      } else {
        Serial.println("No prayer alarm scheduled.");
      }
    } else if (cmd.equalsIgnoreCase("dfreset") || cmd.equalsIgnoreCase("dfreprobe") || cmd.equalsIgnoreCase("dfinit")) {
      // Try to reinitialize the DFPlayer and clear missing-file state
      dfFileMissing = false;  // clear previous FileIndexOut state before reprobe
      if (tryRecoverDFPlayer(3)) {
        Serial.println("DFPlayer recovered via serial command");
      } else {
        Serial.println("DFPlayer recovery failed");
      }
    } else if (cmd.startsWith("forcetrack1")) {
      // formats: forcetrack1 on | forcetrack1 off | forcetrack1 status
      String arg = cmd.substring(11);
      arg.trim();
      if (arg.equalsIgnoreCase("on")) {
        prefs.begin("adhancfg", false);
        prefs.putBool("force_t1", true);
        prefs.end();
        forcePlayTrack1 = true;
        Serial.println("forcePlayTrack1 set: ON (persisted)");
      } else if (arg.equalsIgnoreCase("off")) {
        prefs.begin("adhancfg", false);
        prefs.putBool("force_t1", false);
        prefs.end();
        forcePlayTrack1 = false;
        Serial.println("forcePlayTrack1 set: OFF (persisted)");
      } else if (arg.equalsIgnoreCase("status") || arg.length() == 0) {
        Serial.printf("forcePlayTrack1 is %s\n", forcePlayTrack1 ? "ON" : "OFF");
      } else {
        Serial.println("Usage: forcetrack1 on|off|status");
      }
    } else {
      Serial.printf("Unknown command: %s\n", cmd.c_str());
    }
    // playback commands
    if (cmd.startsWith("play ")) {
      int t = cmd.substring(5).toInt();
      playTrack(t);
    } else if (cmd.equalsIgnoreCase("stopplay")) {
      stopPlay();
    }
  }
  // Process DFPlayer responses (events/errors)
  if (dfAvailable && dfplayer.available()) {
    printDetail(dfplayer.readType(), dfplayer.read());
  }
  // Update LED pattern according to scenario
  static unsigned long lastLedTick = 0;
  static int blinkState = 0;
  unsigned long now = millis();
  // if an LED test is active and expired, restore previous scenario
  if (ledTestUntil != 0 && millis() > ledTestUntil) {
    ledTestUntil = 0;
    ledScenario = (prevLedScenario >= 0) ? prevLedScenario : 0;
    prevLedScenario = -1;
  }
  // run LED updates at 50Hz max
  if (now - lastLedTick >= 20) {
    lastLedTick = now;
    if (useAddressableLEDs) {
      // addressable animations
      static uint32_t lastPhase = 0;
      uint32_t phase = (now / 20) % 1000;
      // If a LED test is active, run a short moving rainbow/chase
      if (ledTestUntil != 0 && millis() <= ledTestUntil) {
        // moving rainbow across the strip using Adafruit_NeoPixel
        uint8_t offset = (now / 10) & 0xFF;
        leds.clear();
        uint16_t activeCount = LED_NUM;
        for (uint16_t i = 0; i < LED_NUM; i++) {
          uint8_t hue = (uint8_t)((i * 256 / activeCount) + offset);
          uint8_t r, g, b;
          hsv2rgb(hue, 255, 220, r, g, b);  // full saturation, slightly reduced brightness
          uint8_t r_adj = (r * ledBrightness) / 100;
          uint8_t g_adj = (g * ledBrightness) / 100;
          uint8_t b_adj = (b * ledBrightness) / 100;
          leds.setPixelColor(i, leds.Color(r_adj, g_adj, b_adj));
        }
        leds.show();
      } else {
        // New scene handling: static colors, blink (reserved), dynamic unified scenes
        if (ledScenario >= 0 && ledScenario < NUM_STATIC_COLORS) {
          // static color scene
          uint8_t r = STATIC_COLORS[ledScenario][0];
          uint8_t g = STATIC_COLORS[ledScenario][1];
          uint8_t b = STATIC_COLORS[ledScenario][2];
          stripSetAll(r, g, b);
        } else if (ledScenario == BLINK_INDEX) {
          // blink indication for AP/config mode: solid red, faster
          if ((now / 300) % 2 == 0) {
            // ON: solid red
            stripSetAll(200, 0, 0);
          } else {
            // OFF: ensure fully black frame (no stray channels)
            stripSetAll(0, 0, 0);
          }
        } else if (ledScenario == DYN_HUE_INDEX) {
          // dynamic hue: all LEDs same hue, cycling over time
          uint8_t hue = (now / 20) & 0xFF;  // slow hue sweep
          const uint8_t vMax = 180;
          float breath = 0.8f + 0.2f * sinf((float)now * (2.0f * 3.14159265f / 5000.0f));
          uint8_t v = (uint8_t)constrain((int)(vMax * breath), 0, 255);
          uint8_t r, g, b;
          hsv2rgb(hue, 255, v, r, g, b);
          stripSetAll(r, g, b);
        } else if (ledScenario == DYN_FADE_INDEX) {
          // dynamic fade between static palette colors (all LEDs same color)
          const uint32_t period = 4000;  // ms per transition
          uint32_t t = now % (period * NUM_STATIC_COLORS);
          uint8_t idx = t / period;
          uint8_t next = (idx + 1) % NUM_STATIC_COLORS;
          float ft = (float)(t % period) / (float)period;
          // linear interpolate between STATIC_COLORS[idx] -> [next]
          uint8_t r = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][0] + ft * STATIC_COLORS[next][0]);
          uint8_t g = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][1] + ft * STATIC_COLORS[next][1]);
          uint8_t b = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][2] + ft * STATIC_COLORS[next][2]);
          stripSetAll(r, g, b);
        } else if (ledScenario == SCENE_PRAYER) {
          float breath = 0.5f + 0.5f * sinf((float)now * (2.0f * 3.14159265f / 4000.0f));
          stripSetAll(0, (uint8_t)(150 * breath), (uint8_t)(105 * breath));
        } else if (ledScenario == SCENE_BREATH) {
          float breath = 0.5f + 0.5f * sinf((float)now * (2.0f * 3.14159265f / 4000.0f));
          stripSetAll(0, (uint8_t)(180 * breath), (uint8_t)(212 * breath));
        } else if (ledScenario == SCENE_CANDLE) {
          // Candle effect: warm amber/orange with independent flickering per LED
          leds.clear();
          for (uint16_t i = 0; i < LED_NUM; i++) {
            float wave = sinf((float)now * 0.005f + i * 0.8f) * 0.3f + sinf((float)now * 0.012f - i * 1.5f) * 0.2f;
            float noise = (float)(random(0, 100) - 50) / 500.0f;
            float intensity = 0.75f + wave + noise;
            intensity = constrain(intensity, 0.4f, 1.0f);

            uint8_t r = 255;
            uint8_t g = (uint8_t)(80 + 35.0f * intensity);
            uint8_t b = 5;

            uint8_t r_adj = (uint8_t)((r * intensity * ledBrightness) / 100);
            uint8_t g_adj = (uint8_t)((g * intensity * ledBrightness) / 100);
            uint8_t b_adj = (uint8_t)((b * intensity * ledBrightness) / 100);

            leds.setPixelColor(i, leds.Color(r_adj, g_adj, b_adj));
          }
          leds.show();
        } else {
          stripSetAll(0, 0, 0);
        }
      }
    } else {
      // single-channel PWM fallback (original behavior)
      // PWM fallback: approximate by setting global brightness from chosen scene
      if (ledScenario >= 0 && ledScenario < NUM_STATIC_COLORS) {
        uint8_t r = STATIC_COLORS[ledScenario][0];
        uint8_t g = STATIC_COLORS[ledScenario][1];
        uint8_t b = STATIC_COLORS[ledScenario][2];
        // convert RGB to perceived brightness (simple average)
        uint16_t bright = ((uint16_t)r + (uint16_t)g + (uint16_t)b) / 3;
        bright = (bright * ledBrightness) / 100;
        // map 0..255 -> 0..(max duty)
        setLedDuty(bright);
      } else if (ledScenario == BLINK_INDEX) {
        if ((now / 300) % 2 == 0) setLedDuty((220 * ledBrightness) / 100);
        else setLedDuty(0);
      } else if (ledScenario == DYN_HUE_INDEX) {
        const uint8_t vMax = 180;
        float breath = 0.8f + 0.2f * sinf((float)now * (2.0f * 3.14159265f / 5000.0f));
        uint8_t v = (uint8_t)constrain((int)(vMax * breath), 0, 255);
        v = (v * ledBrightness) / 100;
        setLedDuty(v);
      } else if (ledScenario == DYN_FADE_INDEX) {
        const uint32_t period = 4000;  // ms per transition
        uint32_t t = now % (period * NUM_STATIC_COLORS);
        uint8_t idx = t / period;
        uint8_t next = (idx + 1) % NUM_STATIC_COLORS;
        float ft = (float)(t % period) / (float)period;
        uint8_t r = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][0] + ft * STATIC_COLORS[next][0]);
        uint8_t g = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][1] + ft * STATIC_COLORS[next][1]);
        uint8_t b = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][2] + ft * STATIC_COLORS[next][2]);
        uint16_t bright = ((uint16_t)r + (uint16_t)g + (uint16_t)b) / 3;
        bright = (bright * ledBrightness) / 100;
        setLedDuty(bright);
      } else if (ledScenario == SCENE_PRAYER || ledScenario == SCENE_BREATH) {
        float breath = 0.5f + 0.5f * sinf((float)now * (2.0f * 3.14159265f / 4000.0f));
        uint8_t v = (uint8_t)(150 * breath);
        v = (v * ledBrightness) / 100;
        setLedDuty(v);
      } else if (ledScenario == SCENE_CANDLE) {
        // Candle effect for single PWM pin: simple global flicker
        float wave = sinf((float)now * 0.007f) * 0.25f + sinf((float)now * 0.015f) * 0.15f;
        float intensity = 0.75f + wave + (float)(random(0, 100) - 50) / 600.0f;
        intensity = constrain(intensity, 0.4f, 1.0f);
        uint8_t v = (uint8_t)(255 * intensity);
        v = (v * ledBrightness) / 100;
        setLedDuty(v);
      } else {
        setLedDuty(0);
      }
    }
  }
  // Handle alarm triggers
  static uint32_t lastPrayerTriggeredUnix = 0;
  uint32_t nowUnix = 0;
  if (rtc.begin()) {
    DateTime _ln = rtc.now();
    if (_ln.month() >= 1 && _ln.month() <= 12 && _ln.year() >= 2020 && _ln.year() <= 2100)
      nowUnix = _ln.unixtime();
  }

  bool shouldTrigger = false;

  if (softwareAlarmAt != 0 && millis() >= softwareAlarmAt) {
    Serial.println("Software fallback alarm triggered (millis)");
    shouldTrigger = true;
  }
  if (nowUnix > 0 && scheduledPrayerIndex > 0 && nowUnix >= scheduledPrayerTime.unixtime()) {
    Serial.println("RTC reached scheduled prayer time (fallback polling)");
    shouldTrigger = true;
  }
  if (ds3231AlarmFlag) {
    Serial.println("DS3231 alarm triggered.");
    shouldTrigger = true;
  }

  if (shouldTrigger) {
    softwareAlarmAt = 0;
    ds3231AlarmFlag = false;
    ds3231ClearAlarmFlags();

    if (nowUnix == 0 || (nowUnix - lastPrayerTriggeredUnix) > 60) {
      lastPrayerTriggeredUnix = nowUnix;
      if (scheduledPrayerIndex > 0) {
        // Read once-per-day trigger info from NVS to protect against duplicate triggers
        prefs.begin("adhancfg", true);
        int lastTrigIdx = prefs.getInt("last_trig_idx", 0);
        int lastTrigDay = prefs.getInt("last_trig_day", 0);
        int lastTrigMon = prefs.getInt("last_trig_mon", 0);
        int lastTrigYr = prefs.getInt("last_trig_yr", 0);
        prefs.end();

        if (lastTrigIdx == scheduledPrayerIndex && lastTrigDay == scheduledPrayerTime.day() && lastTrigMon == scheduledPrayerTime.month() && lastTrigYr == scheduledPrayerTime.year()) {
          Serial.printf("Duplicate adhan protection: Prayer index %d on %04d-%02d-%02d already played. Skipping.\n",
                        scheduledPrayerIndex, scheduledPrayerTime.year(), scheduledPrayerTime.month(), scheduledPrayerTime.day());
        } else {
          // Write trigger info to NVS
          prefs.begin("adhancfg", false);
          prefs.putInt("last_trig_idx", scheduledPrayerIndex);
          prefs.putInt("last_trig_day", scheduledPrayerTime.day());
          prefs.putInt("last_trig_mon", scheduledPrayerTime.month());
          prefs.putInt("last_trig_yr", scheduledPrayerTime.year());
          prefs.end();

          int trackToPlay = 2;  // Default to 2
          bool playDuaaAfter = true;
          if (getPrayerPlaybackForIndex(scheduledPrayerIndex, trackToPlay, playDuaaAfter)) {
            Serial.printf("Prayer index %d\n", scheduledPrayerIndex);

            // Apply specific volume for this prayer
            int prayerVol = 20;
            prefs.begin("adhancfg", true);
            int globalVol = prefs.getInt("volume", 20);
            if (scheduledPrayerIndex == 1) prayerVol = prefs.getInt("ah_fajr_vol", globalVol);
            else if (scheduledPrayerIndex == 3) prayerVol = prefs.getInt("ah_dhuhr_vol", globalVol);
            else if (scheduledPrayerIndex == 4) prayerVol = prefs.getInt("ah_asr_vol", globalVol);
            else if (scheduledPrayerIndex == 5) prayerVol = prefs.getInt("ah_magh_vol", globalVol);
            else if (scheduledPrayerIndex == 6) prayerVol = prefs.getInt("ah_isha_vol", globalVol);
            prefs.end();
            if (dfAvailable) {
              dfplayer.volume(prayerVol);
              Serial.printf("Temporary volume set to %d for prayer %d\n", prayerVol, scheduledPrayerIndex);
            }

            // Protect against playing duaa as adhan
            if (trackToPlay == 1) trackToPlay = 2;

            // Activate prayer LED scene
            if (prayerPrevLedScenario < 0) {
              prayerPrevLedScenario = ledScenario;
              ledScenario = SCENE_PRAYER;
              Serial.printf("LED switched to PRAYER scene (was %d)\n", prayerPrevLedScenario);
            }

            if (playDuaaAfter) {
              shouldPlayDuaaAfterAdhan = true;
              adhanTrackBeforeDuaa = trackToPlay;
              Serial.printf("Playing adhan first (track %d), then duaa (track 1)\n", trackToPlay);
              playTrack(trackToPlay);
            } else {
              shouldPlayDuaaAfterAdhan = false;
              adhanTrackBeforeDuaa = 0;
              Serial.printf("Playing adhan directly (track %d) without duaa\n", trackToPlay);
              playTrack(trackToPlay);
            }
            mqttPublishPrayerFired(scheduledPrayerIndex);
          } else {
            Serial.printf("Skipping non-adhan event for index %d\n", scheduledPrayerIndex);
          }
        }
      }
    } else {
      Serial.println("Skipped duplicate alarm trigger within 60s");
    }
    scheduleNextPrayerAlarm();
  }

  // Async WiFi connect state machine
  if (wifiConnectState == WCS_CONNECTING) {
    wl_status_t st = WiFi.status();
    if (st == WL_CONNECTED) {
      wifiConnectState = WCS_CONNECTED;
      Serial.printf("✓ WiFi connected: %s (IP: %s)\n", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str());
      // Save credentials
      prefs.begin("adhancfg", false);
      prefs.putString("wifi_ssid", wifiConnectSSID);
      prefs.putString("wifi_pass", wifiConnectPass);
      prefs.end();
      // mDNS
      if (MDNS.begin("adhanbox")) {
        MDNS.addService("http", "tcp", 80);
        Serial.println("mDNS: adhanbox.local");
      }
      setupOTA();
      // NTP + prayer reschedule
      if (syncTimeFromNtp(15000) && rtc.begin()) scheduleNextPrayerAlarm();
      // Init MQTT if broker stored
      prefs.begin("adhancfg", true);
      String broker = prefs.getString("mqtt_broker", "");
      prefs.end();
      if (broker.length() > 0) {
        mqtt.setServer(broker.c_str(), MQTT_PORT);
        mqtt.setCallback(mqttCallback);
      }
    } else if (millis() - wifiConnectStart > WIFI_CONNECT_TIMEOUT_MS) {
      wifiConnectState = WCS_FAILED;
      Serial.println("✗ Async WiFi connect timed out");
      WiFi.disconnect(true);
    }
  }

  // Handle HTTP server requests (always, whether in AP mode or normal WiFi)
  server.handleClient();

  // ArduinoOTA (only when connected)
  if (WiFi.status() == WL_CONNECTED) ArduinoOTA.handle();

  // MQTT : maintenir la connexion et traiter les messages entrants
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqtt.connected()) reconnectMQTT();
    else mqtt.loop();
  }
  // MQTT : heartbeat status toutes les 30s
  static unsigned long lastMqttStatus = 0;
  if (mqtt.connected() && millis() - lastMqttStatus > 30000) {
    lastMqttStatus = millis();
    mqttPublishStatus();
  }

  // Auto-sync Mawaqit times every 20 hours when connected to WiFi
  static unsigned long lastAutoSyncCheck = 0;
  if (millis() - lastAutoSyncCheck > 60000) {  // Check once per minute
    lastAutoSyncCheck = millis();
    if (WiFi.status() == WL_CONNECTED && rtc.begin()) {
      unsigned long now_epoch = rtc.now().unixtime();
      prefs.begin("adhancfg", true);
      unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
      String uuid = prefs.getString("mq_uuid", "");
      prefs.end();

      if (uuid.length() > 0) {
        unsigned long age_sec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
        if (age_sec > 20UL * 3600UL) {  // More than 20 hours since last sync
          Serial.println("Auto-sync: Mawaqit times are older than 20 hours. Starting background sync...");
          String err;
          if (performMawaqitSync(err)) {
            Serial.println("Auto-sync: Background sync successful!");
            scheduleNextPrayerAlarm();
          } else {
            Serial.printf("Auto-sync: Background sync failed: %s. Will retry later.\n", err.c_str());
          }
        }
      }
    }
  }

  if (apRunning) {
    // process captive DNS requests so clients are redirected to our AP IP
    dnsServer.processNextRequest();
    // auto-stop after timeout removed: AP will stop only when requested
    // by the UI ("Arrêter AP") or via serial command to avoid unwanted
    // disconnections during configuration.
  }
  // small delay to reduce CPU while idle
  delay(10);
}
