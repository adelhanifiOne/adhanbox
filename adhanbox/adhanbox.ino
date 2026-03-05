// AdhanBox - minimal sketch adding AP configuration via smartphone geolocation
// - Starts an AP when a long-press is detected on CONFIG_BUTTON_PIN
// - Serves a small webpage that requests navigator.geolocation and POSTs lat/lon
// - Stores lat/lon/accuracy/timestamp in Preferences (NVS)
//Version: 1.3.0
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
// Ensure low-level LEDC declarations are available on all toolchains
#include <driver/ledc.h>

// LEDC prototypes are provided by <esp32-hal-ledc.h> from the ESP32 core.

#include <soc/gpio_struct.h>
#include <HTTPClient.h>
#include <time.h>
#include <math.h>

// Addressable LED configuration
#ifndef LED_NUM
#define LED_NUM 16 // change to the number of LEDs on your strip (updated to 60)
#endif
const uint8_t LED_START_INDEX = 0; // start from first pixel (all LEDs enabled)
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
#define CONFIG_BUTTON_PIN 11// change according to your wiring
#endif

#define AP_SSID_PREFIX "AdhanBox-"
#define AP_TIMEOUT_MS (5 * 60 * 1000UL) // AP auto-stop after 5 minutes

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
int scheduledPrayerIndex = 0; // 1-based prayer index (1=Fajr,2=Sunrise,...6=Isha)
DateTime scheduledPrayerTime;
// Software fallback alarm (millis target) to trigger prayer if RTC interrupt fails
unsigned long softwareAlarmAt = 0;
// Persistent option: force playing track 1 for all prayers
bool forcePlayTrack1 = false;
// Global LED brightness (0-100, default 50%)
int ledBrightness = 50;
// Track sequence: after adhan finishes, play duaa (track 3)
bool shouldPlayDuaaNext = false;

// LED / button state
// Scene mapping:
// 0..6 : static colors (off, red, pink, blue, violet, green, yellow)
// 7    : BLINK (reserved for AP/config indication)
// 8    : dynamic hue (all LEDs same color, hue cycling)
// 9    : dynamic palette fade (all LEDs fade between palette colors)
int ledScenario = 8; // start with dynamic hue by default
bool isPlaying = false;
// ledc PWM channel for LED brightness
const int LEDC_CHANNEL = 0;
const int LEDC_FREQ = 5000;
const int LEDC_RES = 8; // 0-255

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
void handleCalculationConfig();
void handleAdhanConfig();
bool syncTimeFromNtp(unsigned long timeoutMs = 10000);
void handleDumpStatus();
void scheduleNextPrayerAlarm();
bool computeNextPrayer(const DateTime &now, DateTime &nextDt, int &idx);
void handleLedTest();
void setupServerRoutes();
void stopConfigAP();
void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName);

// LED timing and bit-bang functions removed - using Adafruit_NeoPixel instead

// HSV (8-bit) -> RGB helper (no white channel)
static inline void hsv2rgb(uint8_t h, uint8_t s, uint8_t v, uint8_t &r, uint8_t &g, uint8_t &b){
  if(s == 0){ r = g = b = v; return; }
  uint8_t region = h / 43; // 0..5
  uint8_t remainder = (h - (region * 43)) * 6;
  uint8_t p = (v * (255 - s)) >> 8;
  uint8_t q = (v * (255 - ((s * remainder) >> 8))) >> 8;
  uint8_t t = (v * (255 - ((s * (255 - remainder)) >> 8))) >> 8;
  switch(region){
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    default: r = v; g = p; b = q; break;
  }
}

// Forward declarations for functions defined later but used above
bool ds3231SetAlarm2Daily(uint8_t hour, uint8_t minute);
void ds3231DisableAlarms();
bool loadStoredLocation(double &outLat, double &outLon, double &outAcc);
void stopPlay();
void playTrack(int track);

// LED helper using driver API (some cores don't expose ledcSetup/ledcAttachPin)
static inline void setLedDuty(uint32_t duty){
  // If using an addressable strip driven by the native protocol, don't use LEDC
  // on the data pin — that would corrupt the data stream and can cause the
  // first pixel to flicker. Only apply PWM duty when not using addressable LEDs.
  if(useAddressableLEDs) return;
  uint32_t max = (1u << LEDC_RES) - 1u;
  if(duty > max) duty = max;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL, duty);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)LEDC_CHANNEL);
}

// Helper: set all addressable pixels to RGB
static inline void stripSetAll(uint8_t r, uint8_t g, uint8_t b){
  // Apply global brightness scaling
  r = (r * ledBrightness) / 100;
  g = (g * ledBrightness) / 100;
  b = (b * ledBrightness) / 100;
  // Set all pixels via Adafruit_NeoPixel
  for(uint16_t i=0;i<LED_NUM;i++){
    leds.setPixelColor(i, r, g, b);
  }
  leds.show();
}

// Forcefully clear the strip
static void clearStrip(){
  for(int i=0;i<3;i++){
    stripSetAll(0,0,0);
    delay(20);
  }
  delay(120);
}

// LED test timer (non-blocking): when >0, overrides scenario until expiry
unsigned long ledTestUntil = 0;
int prevLedScenario = -1;

// static color table (R,G,B) for WS2812B RGB LEDs
static const uint8_t STATIC_COLORS[][3] = {
  {0,0,0},      // off
  {255,0,0},    // red
  {255,0,180},  // pink
  {0,60,255},   // blue
  {180,0,255},  // violet
  {0,255,0},    // green
  {255,255,0},  // yellow
};
static const uint8_t NUM_STATIC_COLORS = sizeof(STATIC_COLORS)/sizeof(STATIC_COLORS[0]);
const int BLINK_INDEX = 7;
const int DYN_HUE_INDEX = 8;
const int DYN_FADE_INDEX = 9;
const int TOTAL_SCENES = 10;

// DFPlayer pin mapping requested: DFPlayer on GPIO1 and GPIO2
// DFPlayer TX -> ESP RX (GPIO1)  // <-- WARNING: GPIO1 is also UART0 TX (console)
// DFPlayer RX <- ESP TX (GPIO2)
// The DFPlayer TX (5V) MUST be level-shifted / use a resistor divider before GPIO1.
#define DFPLAYER_RX_PIN 2 // ESP RX (connect to DFPlayer TX through divider)
#define DFPLAYER_TX_PIN 1 // ESP TX (connect to DFPlayer RX)

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
    input[type=text], input[type=number]{ background:#0b1220; border:1px solid rgba(255,255,255,0.04); padding:8px 10px; color:#fff; border-radius:6px; }
    button.btn{ background:var(--accent); color:#fff; border:none; padding:8px 12px; border-radius:8px; cursor:pointer; }
    button.ghost{ background:transparent; border:1px solid rgba(255,255,255,0.06); color:var(--muted); padding:8px 10px; border-radius:8px; cursor:pointer; }
    table{ width:100%; border-collapse:collapse; }
    td, th{ padding:6px 4px; }
    tr:nth-child(odd) td{ background:rgba(255,255,255,0.01); }
    .muted{ color:var(--muted); font-size:13px; }
    footer{ margin-top:18px; text-align:center; color:var(--muted); font-size:13px; }
    @media(max-width:880px){ .grid{ grid-template-columns:1fr; } .container{ padding:10px; } }
    /* start overlay */
    .overlay{ position:fixed; inset:0; background:linear-gradient(180deg, rgba(2,6,23,0.95), rgba(2,6,23,0.9)); display:flex; align-items:center; justify-content:center; z-index:40; }
    .overlay-card{ background:#071825; padding:18px; border-radius:12px; width:min(720px,94%); box-shadow:0 10px 40px rgba(0,0,0,0.6); }
    .net-list{ max-height:240px; overflow:auto; margin-top:10px; }
    .net-item{ display:flex; justify-content:space-between; padding:8px; border-bottom:1px solid rgba(255,255,255,0.02); }
    .net-item button{ margin-left:8px; }
  </style>
</head>
<body>
  <div class="container">
    <!-- Start overlay: choose WiFi available / not available -->
    <div id="startOverlay" class="overlay">
      <div class="overlay-card">
        <h2 style="margin:0 0 8px 0">Bienvenue — Configuration</h2>
        <p class="small">Commencez par indiquer si vous avez un réseau Wi‑Fi à portée.</p>
        <!-- Buttons stacked and larger for clarity -->
        <div style="display:flex;flex-direction:column;gap:12px;margin-top:12px;">
          <button class="btn" id="startWifiBtn" style="font-size:18px;padding:14px;">WiFi disponible</button>
          <button class="ghost" id="startNoWifiBtn" style="font-size:18px;padding:14px;">WiFi non disponible</button>
        </div>
        <div id="scanContainer" style="margin-top:16px; display:none;">
          <div style="display:flex;gap:8px;align-items:center;">
            <strong>Réseaux trouvés</strong>
            <button class="ghost" id="refreshScanBtn" style="margin-left:auto">Rafraîchir</button>
          </div>
          <div id="netList" class="net-list"></div>
            <div style="margin-top:14px; display:none; text-align:center;" id="netConnectForm">
            <div class="field"><label>SSID: <input id="selSsid" type="text" readonly style="text-align:center; font-size:16px; padding:10px;"></label></div>
            <div class="field"><label>Mot de passe: <input id="selPass" type="text" placeholder="(laisser vide si ouvert)" style="text-align:center; font-size:16px; padding:10px;"></label></div>
            <div style="display:flex;gap:8px;justify-content:center;align-items:center;"><button class="btn" id="overlayConnectBtn" style="font-size:18px;padding:12px 26px;">Se connecter</button></div>
            <div id="overlayWifiStatus" class="muted" style="margin-top:8px;text-align:center;"></div>
          </div>
        </div>
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
            <button class="ghost" id="testTrack1Btn">Adhan standard (piste 1)</button>
            <button class="ghost" id="testTrack2Btn">Adhan Fajr (piste 2)</button>
            <button class="ghost" id="testTrack3Btn">Duaa (piste 3)</button>
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

    var doScan = function(){
      document.getElementById('netList').innerHTML = '<div class="muted">Recherche...</div>';
      fetch('/scan_wifi').then(r=>{ if(!r.ok) throw r.status; return r.json(); }).then(list=>{
        if(!list || list.length==0){ document.getElementById('netList').innerHTML = '<div class="muted">Aucun réseau trouvé</div>'; return; }
        let html='';
        list.sort((a,b)=>b.rssi - a.rssi);
        list.forEach(n=>{
          html += `<div class="net-item"><div style="flex:1">${n.ssid} <span class=\"muted\">(${n.rssi}dBm)</span></div><div><button class=\"btn\" data-ssid=\"${n.ssid}\">Choisir</button></div></div>`;
        });
        document.getElementById('netList').innerHTML = html;
        document.querySelectorAll('.net-item button').forEach(b=>b.addEventListener('click', function(){ document.getElementById('selSsid').value = this.getAttribute('data-ssid'); document.getElementById('netConnectForm').style.display='block'; }));
      }).catch(e=>{ document.getElementById('netList').innerHTML = '<div class="muted">Scan error</div>'; });
    }

    document.getElementById('overlayConnectBtn').onclick = function(){
      var ssid = document.getElementById('selSsid').value.trim();
      var pass = document.getElementById('selPass').value || '';
      if(!ssid) return alert('Choisissez un SSID');
      document.getElementById('overlayWifiStatus').innerText = 'Connecting...';
      document.getElementById('overlayConnectBtn').disabled = true;
      fetch('/connect_wifi', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ ssid: ssid, pass: pass }) }).then(r=>r.text()).then(t=>{
        document.getElementById('overlayWifiStatus').innerText = t;
        // on success, hide overlay and open dashboard, refresh location/status
        if(t && (t.indexOf('Connected')>=0 || t.indexOf('Already connected')>=0)){
          setTimeout(()=>{
            hideStartOverlay();
            document.querySelector('.tab[data-page="dashboard"]').click();
            // hide Wi-Fi auto block in advanced page as it's now redundant
            var wab = document.getElementById('wifiAutoBlock'); if(wab) wab.style.display='none';
            // refresh UI and fetch stored location to show in dashboard
            refreshAll();
            fetch('/show_loc').then(r=>r.json()).then(j=>{ if(j && j.lat){ document.getElementById('quick_loc').innerText = j.lat+','+j.lon; } }).catch(e=>{});
          }, 600);
        }
      }).catch(e=>{ document.getElementById('overlayWifiStatus').innerText = 'Erreur'; }).finally(()=>{ document.getElementById('overlayConnectBtn').disabled = false; });
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

// Helpers to parse simple JSON payload without ArduinoJson
static double parseJsonValue(const String &s, const char* key){
  int k = s.indexOf(String('"') + String(key) + String('"'));
  if(k<0) k = s.indexOf(String(key) );
  if(k<0) return NAN;
  int colon = s.indexOf(':', k);
  if(colon<0) return NAN;
  int start = colon+1;
  // skip spaces and optional quotes
  while(start < s.length() && (s[start]==' '||s[start]=='\"')) start++;
  int end = start;
  while(end < s.length() && ( (s[end]>='0'&&s[end]<='9') || s[end]=='.' || s[end]=='-' || s[end]=='+' || s[end]=='e' || s[end]=='E')) end++;
  String num = s.substring(start, end);
  return num.toFloat();
}

void handleRoot(){
  // Prevent browsers from caching the configuration page so updates appear immediately
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.sendHeader("Pragma", "no-cache");
  server.sendHeader("Expires", "0");
  server.send_P(200, "text/html", index_html);
}

void handleSetLocation(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
    double lat = parseJsonValue(body, "lat");
    double lon = parseJsonValue(body, "lon");
    double acc = parseJsonValue(body, "accuracy");
    unsigned long ts = (unsigned long)parseJsonValue(body, "timestamp");
  if(isnan(lat) || isnan(lon)){
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

void handleSetTZ(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
    double tz = parseJsonValue(body, "tz_min");
  if(isnan(tz)){
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  prefs.begin("adhancfg", false);
  prefs.putInt("tz_offset_min", (int)tz);
  prefs.end();
  server.send(200, "text/plain", "Timezone offset saved");
  Serial.printf("Stored tz_offset_min=%d\n", (int)tz);
}

void handlePlayTest(){
  server.send(200, "text/plain", "Playing test track");
  // play track 1 as test
  if(dfAvailable) dfplayer.play(1);
}

// HTTP handlers implementing serial commands
void handleSetRTC(){
  if(!rtc.begin()){ server.send(200,"text/plain","RTC not present"); return; }
  rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  server.send(200, "text/plain", "RTC set to compile time");
}

// Set RTC manually via POST JSON { "date": "YYYY-MM-DD", "time": "HH:MM:SS" }
void handleSetRtcManual(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
  String dateStr = "";
  String timeStr = "";
  int p = body.indexOf("\"date\"");
  if(p >= 0){ int c = body.indexOf(':', p); int q1 = body.indexOf('"', c); int q2 = body.indexOf('"', q1+1); if(q1>=0 && q2>q1) dateStr = body.substring(q1+1, q2); }
  p = body.indexOf("\"time\"");
  if(p >= 0){ int c = body.indexOf(':', p); int q1 = body.indexOf('"', c); int q2 = body.indexOf('"', q1+1); if(q1>=0 && q2>q1) timeStr = body.substring(q1+1, q2); }
  if(dateStr.length() == 0){ server.send(400, "text/plain", "Missing date"); return; }
  // parse date YYYY-MM-DD
  if(dateStr.length() < 10){ server.send(400, "text/plain", "Invalid date format"); return; }
  int y = dateStr.substring(0,4).toInt();
  int m = dateStr.substring(5,7).toInt();
  int d = dateStr.substring(8,10).toInt();
  int hh = 0, mm = 0, ss = 0;
  if(timeStr.length() >= 5){ // HH:MM or HH:MM:SS
    hh = timeStr.substring(0,2).toInt();
    mm = timeStr.substring(3,5).toInt();
    if(timeStr.length() >= 8) ss = timeStr.substring(6,8).toInt();
  }
  if(!rtc.begin()){ server.send(500, "text/plain", "RTC not present"); return; }
  DateTime dt;
  try{
    dt = DateTime(y,m,d,hh,mm,ss);
  }catch(...){ server.send(400, "text/plain", "Invalid date/time"); return; }
  rtc.adjust(dt);
  char buf[64]; snprintf(buf, sizeof(buf), "RTC set to %04d-%02d-%02d %02d:%02d:%02d", y, m, d, hh, mm, ss);
  server.send(200, "text/plain", String(buf));
  Serial.println(buf);
}

void handleSetAlarmTest(){
  if(!rtc.begin()){ server.send(200,"text/plain","RTC not present"); return; }
  DateTime now = rtc.now();
  int mm = (now.minute() + 1) % 60;
  int hh = now.hour() + (now.minute() == 59 ? 1 : 0);
  ds3231SetAlarm2Daily(hh%24, mm);
  scheduledPrayerIndex = 1;
  scheduledPrayerTime = DateTime(now.year(), now.month(), now.day(), hh%24, mm, 0);
  char buf[64]; snprintf(buf, sizeof(buf), "Test alarm set for %02d:%02d", hh%24, mm);
  server.send(200, "text/plain", buf);
}

void handleCancelAlarms(){
  ds3231DisableAlarms();
  server.send(200, "text/plain", "DS3231 alarms disabled");
}

void handleShowNextAlarm(){
  if(scheduledPrayerIndex>0){
    char buf[128]; snprintf(buf, sizeof(buf), "%d|%04u-%02u-%02u %02d:%02d", scheduledPrayerIndex, scheduledPrayerTime.year(), scheduledPrayerTime.month(), scheduledPrayerTime.day(), scheduledPrayerTime.hour(), scheduledPrayerTime.minute());
    server.send(200, "text/plain", buf);
  }else{
    server.send(200, "text/plain", "none");
  }
}

void handleShowLoc(){
  double lat, lon, acc; if(loadStoredLocation(lat, lon, acc)){
    char buf[128]; snprintf(buf, sizeof(buf), "{\"lat\":%.6f,\"lon\":%.6f,\"acc\":%.1f}", lat, lon, acc);
    server.send(200, "application/json", String(buf));
  }else{
    server.send(200, "application/json", "{}");
  }
}

void handleShowTime(){
  if(!rtc.begin()){ server.send(200,"text/plain","RTC not present"); return; }
  DateTime now = rtc.now(); char buf[64]; snprintf(buf,sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
  server.send(200, "text/plain", buf);
}

void handlePlayTrack(){
  String t = server.arg("track");
  int track = t.length()? t.toInt() : 1;
  
  Serial.printf("handlePlayTrack: track=%d, dfAvailable=%d\n", track, dfAvailable);
  
  if(!dfAvailable){
    Serial.println("DFPlayer not available, attempting recovery...");
    if(!tryRecoverDFPlayer(3)){
      server.send(503, "text/plain", "DFPlayer not available and recovery failed");
      return;
    }
  }
  
  if(dfAvailable){ 
    Serial.printf("Playing track %d\n", track);
    dfplayer.play(track); 
    isPlaying = true; 
    server.send(200, "text/plain", "Playing"); 
  }
  else {
    server.send(503, "text/plain", "DFPlayer not available");
  }
}

void handleStopPlay(){
  stopPlay();
  server.send(200, "text/plain", "Stopped");
}

// Set volume via POST JSON {"vol":number}
void handleSetVolume(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
  double v = parseJsonValue(body, "vol");
  if(isnan(v)){
    server.send(400, "text/plain", "Invalid payload");
    return;
  }
  int vol = (int)round(v);
  if(vol < 0) vol = 0; if(vol > 30) vol = 30;
  prefs.begin("adhancfg", false);
  prefs.putInt("volume", vol);
  prefs.end();
  if(dfAvailable){ dfplayer.volume(vol); }
  server.send(200, "text/plain", "OK");
  Serial.printf("Volume set to %d via HTTP\n", vol);
}

// Return stored volume as JSON {"vol":N}
void handleGetVolume(){
  prefs.begin("adhancfg", true);
  int vol = prefs.getInt("volume", 20);
  prefs.end();
  char buf[64]; snprintf(buf, sizeof(buf), "{\"vol\":%d}", vol);
  server.send(200, "application/json", String(buf));
}

// Set brightness via POST JSON {"bright":number}
void handleSetBrightness(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
  double b = parseJsonValue(body, "bright");
  if(isnan(b)){ server.send(400, "text/plain", "Invalid payload"); return; }
  int bright = (int)round(b);
  if(bright < 0) bright = 0; if(bright > 100) bright = 100;
  ledBrightness = bright;
  prefs.begin("adhancfg", false);
  prefs.putInt("brightness", bright);
  prefs.end();
  server.send(200, "text/plain", "OK");
  Serial.printf("Brightness set to %d%% via HTTP\n", bright);
}

// Return stored brightness as JSON {"bright":N}
void handleGetBrightness(){
  prefs.begin("adhancfg", true);
  int bright = prefs.getInt("brightness", 50);
  prefs.end();
  char buf[64]; snprintf(buf, sizeof(buf), "{\"bright\":%d}", bright);
  server.send(200, "application/json", String(buf));
}

// ===== API Handlers for Flutter App (JSON wrappers) =====

// Set LED scenario via POST JSON {"scenario": number}
void handleSetLedScenario(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
  double sc = parseJsonValue(body, "scenario");
  if(isnan(sc)){ server.send(400, "text/plain", "Invalid payload"); return; }
  int scenario = (int)round(sc);
  if(scenario < 0 || scenario >= TOTAL_SCENES){ server.send(400, "text/plain", "Invalid scenario"); return; }
  
  ledScenario = scenario;
  if(ledScenario == 0){ setLedDuty(0); if(useAddressableLEDs) stripSetAll(0,0,0); }
  else { setLedDuty(128); }
  
  prefs.begin("adhancfg", false);
  prefs.putInt("led_scenario", ledScenario);
  prefs.end();
  
  Serial.printf("LED scenario set to %d via API\n", scenario);
  server.send(200, "application/json", String("{\"scenario\":") + scenario + "}");
}

// LED test handler: starts a short blink for 5 seconds and returns status
void handleLedTest(){
  // start blinking for 5 seconds
  if(ledTestUntil == 0){
    prevLedScenario = ledScenario;
  }
  ledScenario = 2; // blink
  ledTestUntil = millis() + 5000UL;
  server.send(200, "text/plain", "LED test started for 5s");
  Serial.println("LED test triggered via HTTP");
}

// Set LED scenario via query ?scene=N
void handleSetLed(){
  String s = server.arg("scene");
  if(s.length() == 0){ server.send(400, "text/plain", "Missing scene"); return; }
  int sc = s.toInt();
  if(sc < 0 || sc >= TOTAL_SCENES){ server.send(400, "text/plain", "Invalid scene"); return; }
  ledScenario = sc;
  if(ledScenario == 0){ setLedDuty(0); if(useAddressableLEDs) stripSetAll(0,0,0); }
  else { setLedDuty(128); }
  // If this is a preview (preview=1) do not persist the choice to prefs
  String pv = server.arg("preview");
  bool isPreview = (pv == "1" || pv.equalsIgnoreCase("true"));
  if(!isPreview){ prefs.begin("adhancfg", false); prefs.putInt("led_scenario", ledScenario); prefs.end(); }
  Serial.printf("LED scenario set via HTTP: %d (preview=%d)\n", ledScenario, isPreview ? 1 : 0);
  server.send(200, "text/plain", String("OK: ") + ledScenario + (isPreview?" (preview)":""));
}

// Turn off LEDs
void handleLedOff(){
  ledScenario = 0;
  setLedDuty(0);
  if(useAddressableLEDs) stripSetAll(0,0,0);
  if(useAddressableLEDs) clearStrip();
  prefs.begin("adhancfg", false); prefs.putInt("led_scenario", ledScenario); prefs.end();
  Serial.println("LEDs turned off via HTTP");
  server.send(200, "text/plain", "LEDs off");
}

// Return current RTC time as plain text (YYYY-MM-DD HH:MM:SS) and tz offset if set
void handleGetRTC(){
  Serial.println("HTTP GET /rtc_time -> handleGetRTC called");
  if(!rtc.begin()){
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
  if(tz != 0x7fffffff){
    char tzb[32]; snprintf(tzb, sizeof(tzb), " (UTC%+d)", tz/60);
    out += String(tzb);
  }
  Serial.printf("handleGetRTC: returning '%s'\n", out.c_str());
  server.send(200, "text/plain", out);
}

// forward declaration so it can be registered earlier
void handlePrayerTimes();

// Try to fetch location from ip-api.com and store in prefs. Returns true on success.


// Handler to connect to WiFi (POST JSON {"ssid":"...","pass":"..."}) and attempt auto-location
void handleConnectWifi(){
  if(server.method() != HTTP_POST){ server.send(405, "text/plain", "Method not allowed"); return; }
  String body = server.arg(0);
  Serial.print("/connect_wifi body: "); Serial.println(body);
  // parse simple JSON values
  int i1 = body.indexOf("ssid");
  int i2 = body.indexOf("pass");
  String ssid="", pass="";
  // improved parsing: find colon after the key, then extract quoted string or unquoted token
  if(i1 >= 0){
    int colon = body.indexOf(':', i1);
    if(colon >= 0){
      int firstQuote = body.indexOf('"', colon);
      if(firstQuote >= 0){
        int secondQuote = body.indexOf('"', firstQuote+1);
        if(secondQuote > firstQuote) ssid = body.substring(firstQuote+1, secondQuote);
      } else {
        // unquoted value (until comma or })
        int endp = body.indexOf(',', colon);
        if(endp < 0) endp = body.indexOf('}', colon);
        if(endp > colon) ssid = body.substring(colon+1, endp);
        ssid.trim();
      }
    }
  }
  if(i2 >= 0){
    int colon = body.indexOf(':', i2);
    if(colon >= 0){
      int firstQuote = body.indexOf('"', colon);
      if(firstQuote >= 0){
        int secondQuote = body.indexOf('"', firstQuote+1);
        if(secondQuote > firstQuote) pass = body.substring(firstQuote+1, secondQuote);
      } else {
        int endp = body.indexOf(',', colon);
        if(endp < 0) endp = body.indexOf('}', colon);
        if(endp > colon) pass = body.substring(colon+1, endp);
        pass.trim();
      }
    }
  }
  Serial.printf("Parsed SSID='%s' (len=%u) PASS='%s' (len=%u)\n", ssid.c_str(), (unsigned)ssid.length(), pass.c_str(), (unsigned)pass.length());
  if(ssid.length()==0){ server.send(400, "text/plain", "Missing SSID"); return; }
  // If already connected to the same SSID, return OK
  if(WiFi.status() == WL_CONNECTED){
    String cur = WiFi.SSID();
    if(cur == ssid){ server.send(200, "text/plain", "Already connected"); return; }
  }
  // Ensure previous STA config/connection is cleared to avoid "cannot set config" errors
  WiFi.disconnect(true);
  unsigned long ddstart = millis();
  // wait a bit for the driver to release resources
  while(millis() - ddstart < 1200){ if(WiFi.status() != WL_CONNECTED) break; delay(50); }
  // Try to connect as STA while keeping AP active
  WiFi.mode(WIFI_AP_STA);
  WiFi.setAutoReconnect(true);
  Serial.printf("Connecting to SSID '%s'...\n", ssid.c_str());
  WiFi.begin(ssid.c_str(), pass.c_str());
  unsigned long start = millis();
  while(millis() - start < 20000){
    wl_status_t st = WiFi.status();
    if(st == WL_CONNECTED) break;
    delay(200);
  }
  if(WiFi.status() != WL_CONNECTED){
    server.send(500, "text/plain", "WiFi connect failed");
    Serial.println("WiFi connection failed");
    return;
  }
  Serial.printf("WiFi connected, IP=%s\n", WiFi.localIP().toString().c_str());
  
  // Initialize mDNS responder so device can be found at adhanbox.local
  if (!MDNS.begin("adhanbox")) {
    Serial.println("Error setting up MDNS responder!");
  } else {
    MDNS.addService("http", "tcp", 80);
    Serial.println("mDNS responder started: adhanbox.local");
  }
  
  String resp = "Connected";
  // Location will be set by mobile device via /set_location endpoint
  // Sync time from NTP and update RTC + recalculate prayer times
  bool ntpOk = syncTimeFromNtp(15000);
  if(ntpOk){
    resp += "; time synced";
    // Reschedule prayer alarm using new RTC time
    if(rtc.begin()) scheduleNextPrayerAlarm();
  }else{
    resp += "; time sync failed";
  }
  
  // Save WiFi credentials for auto-reconnect on reboot
  prefs.begin("adhancfg", false);
  prefs.putString("wifi_ssid", ssid);
  prefs.putString("wifi_pass", pass);
  prefs.end();
  Serial.printf("WiFi credentials saved for auto-reconnect: SSID=%s\n", ssid.c_str());
  
  server.send(200, "text/plain", resp);
}

// Scan for nearby WiFi networks and return JSON array
void handleScanWifi(){
  if(server.method() != HTTP_GET){ server.send(405, "text/plain", "Method not allowed"); return; }
  int n = WiFi.scanNetworks();
  String out = "[";
  for(int i=0;i<n;i++){
    String ss = WiFi.SSID(i);
    int rssi = WiFi.RSSI(i);
    int enc = (int)WiFi.encryptionType(i);
    // escape quotes in SSID
    ss.replace("\"", "\\\"");
    out += "{\"ssid\":\"" + ss + "\",\"rssi\":" + String(rssi) + ",\"secure\":" + String(enc != WIFI_AUTH_OPEN ? 1 : 0) + "}";
    if(i < n-1) out += ",";
  }
  out += "]";
  server.send(200, "application/json", out);
}

// Helper function: add offset (in minutes) to time string "HH:MM"
// Returns adjusted time, handling day wraparound
String addMinutesToTime(String timeStr, int offsetMinutes){
  if(timeStr.length() < 5) return timeStr; // Invalid format
  
  int h = timeStr.substring(0, 2).toInt();
  int m = timeStr.substring(3, 5).toInt();
  
  int totalMinutes = h * 60 + m + offsetMinutes;
  
  // Handle day wraparound
  while(totalMinutes < 0) totalMinutes += 1440;
  while(totalMinutes >= 1440) totalMinutes -= 1440;
  
  h = totalMinutes / 60;
  m = totalMinutes % 60;
  
  char buffer[6];
  sprintf(buffer, "%02d:%02d", h, m);
  return String(buffer);
}

// GET /api/mawaqit/offsets - Return current offsets
void handleMawaqitGetOffsets(){
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
void handleMawaqitSetOffsets(){
  if(server.method() != HTTP_POST){
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }
  
  String body = server.arg(0);
  Serial.print("/api/mawaqit/offsets body: ");
  Serial.println(body);
  
  // Simple JSON parsing for integers
  auto extractJsonInt = [&](const String &src, const char* key)->int {
    int k = src.indexOf(String("\"") + key + "\"");
    if(k < 0) return 0;
    int colon = src.indexOf(':', k);
    if(colon < 0) return 0;
    int numStart = colon + 1;
    while(numStart < src.length() && (src.charAt(numStart) == ' ' || src.charAt(numStart) == '\t')) numStart++;
    int numEnd = numStart;
    if(src.charAt(numStart) == '-') numEnd++;
    while(numEnd < src.length() && isDigit(src.charAt(numEnd))) numEnd++;
    if(numEnd <= numStart) return 0;
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
  
  prefs.begin("adhancfg", false);
  prefs.putInt("mq_off_fajr", fajrOff);
  prefs.putInt("mq_off_sunrise", sunriseOff);
  prefs.putInt("mq_off_dhuhr", dhuhrOff);
  prefs.putInt("mq_off_asr", asrOff);
  prefs.putInt("mq_off_maghrib", maghribOff);
  prefs.putInt("mq_off_isha", ishaOff);
  prefs.end();
  
  Serial.printf("Offsets saved: Fajr=%d Sunrise=%d Dhuhr=%d Asr=%d Maghrib=%d Isha=%d\n",
                fajrOff, sunriseOff, dhuhrOff, asrOff, maghribOff, ishaOff);
  
  server.send(200, "application/json", "{\"ok\":true}");
}

// Configure selected mosque for Mawaqit from app
// Expected body JSON: {"mosque_uuid":"...", "name":"...", "city":"...", "lat":..., "lon":...}
void handleMawaqitConfig(){
  if(server.method() != HTTP_POST){ server.send(405, "application/json", "{\"error\":\"Method not allowed\"}"); return; }

  String body = server.arg(0);
  Serial.print("/api/mawaqit/config body: ");
  Serial.println(body);

  auto extractJsonString = [&](const String &src, const char* key)->String {
    int k = src.indexOf(String("\"") + key + "\"");
    if(k < 0) return "";
    int colon = src.indexOf(':', k);
    if(colon < 0) return "";
    int q1 = src.indexOf('"', colon + 1);
    if(q1 < 0) return "";
    int q2 = src.indexOf('"', q1 + 1);
    if(q2 < 0) return "";
    return src.substring(q1 + 1, q2);
  };

  String uuid = extractJsonString(body, "mosque_uuid");
  if(uuid.length() == 0) uuid = extractJsonString(body, "uuid");
  String name = extractJsonString(body, "name");
  String city = extractJsonString(body, "city");

  if(uuid.length() == 0){
    server.send(400, "application/json", "{\"error\":\"Missing mosque_uuid\"}");
    return;
  }

  prefs.begin("adhancfg", false);
  prefs.putString("mq_uuid", uuid);
  prefs.putString("mq_name", name);
  prefs.putString("mq_city", city);
  prefs.putULong("mq_ts", millis());
  prefs.end();

  Serial.printf("Mawaqit mosque saved uuid=%s name=%s city=%s\n", uuid.c_str(), name.c_str(), city.c_str());
  server.send(200, "application/json", "{\"ok\":true,\"message\":\"mosque saved\"}");
}

// Trigger a sync placeholder (keeps API compatibility with app)
void handleMawaqitSync(){
  if(server.method() != HTTP_POST){ 
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}"); 
    return; 
  }

  prefs.begin("adhancfg", true);
  String uuid = prefs.getString("mq_uuid", "");
  prefs.end();

  if(uuid.length() == 0){
    server.send(400, "application/json", "{\"error\":\"No mosque configured\"}");
    return;
  }

  // Download real Mawaqit times from API
  // IMPORTANT: current app sends OSM/Photon ids (osm-xxxx / photon-xxxx),
  // which are not valid Mawaqit mosque ids. For those, use lat/lon endpoint.
  Serial.printf(">>> Syncing Mawaqit times for UUID: %s\n", uuid.c_str());

  double lat = 0.0, lon = 0.0, acc = 0.0;
  bool hasLocation = loadStoredLocation(lat, lon, acc);
  bool looksOsmId = uuid.startsWith("osm-") || uuid.startsWith("photon-");

  String host = "api.mawaqit.net";
  String urls[2] = {"", ""};
  int attempts = 0;

  if(looksOsmId && hasLocation){
    urls[attempts++] = "/v1/times?latitude=" + String(lat, 6) + "&longitude=" + String(lon, 6);
    Serial.println("UUID is OSM/Photon id -> using lat/lon endpoint first");
  }else{
    urls[attempts++] = "/2.0/mosque/" + uuid + "/prayer-times";
    if(hasLocation){
      urls[attempts++] = "/v1/times?latitude=" + String(lat, 6) + "&longitude=" + String(lon, 6);
    }
  }

  const char* timeNames[6] = {"fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"};
  const char* altNames[6] = {"Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"};
  String times[6] = {"", "", "", "", "", ""};
  bool anyValid = false;

  for(int attempt = 0; attempt < attempts && !anyValid; attempt++){
    WiFiClientSecure client;
    client.setInsecure();

    String url = urls[attempt];
    Serial.printf("Mawaqit request [%d/%d]: https://%s%s\n", attempt + 1, attempts, host.c_str(), url.c_str());

    if(!client.connect(host.c_str(), 443)){
      Serial.println("Connection to Mawaqit API failed");
      continue;
    }

    client.print("GET " + url + " HTTP/1.1\r\n");
    client.print("Host: " + host + "\r\n");
    client.print("User-Agent: AdhanBox/1.0\r\n");
    client.print("Accept: application/json\r\n");
    client.print("Connection: close\r\n");
    client.print("\r\n");

    String response = "";
    unsigned long startTime = millis();
    while((millis() - startTime < 15000) && (client.connected() || client.available())){
      if(client.available()){
        response += (char)client.read();
      }
    }
    client.stop();

    int bodyStart = response.indexOf("\r\n\r\n");
    int skipLen = 4;
    if(bodyStart < 0){
      bodyStart = response.indexOf("\n\n");
      skipLen = 2;
    }
    if(bodyStart < 0){
      Serial.println("No response body found");
      continue;
    }

    String jsonBody = response.substring(bodyStart + skipLen);
    jsonBody.trim();

    // Handle possible chunked body beginning with hex chunk-size (e.g. "7b")
    int firstNl = jsonBody.indexOf('\n');
    if(firstNl > 0){
      String firstLine = jsonBody.substring(0, firstNl);
      firstLine.trim();
      bool looksHex = firstLine.length() > 0 && firstLine.length() <= 8;
      for(size_t i = 0; i < firstLine.length(); i++){
        char c = firstLine.charAt(i);
        bool isHexChar = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if(!isHexChar){ looksHex = false; break; }
      }
      if(looksHex){
        String dechunked = jsonBody.substring(firstNl + 1);
        int endChunk = dechunked.lastIndexOf("\n0");
        if(endChunk > 0){
          dechunked = dechunked.substring(0, endChunk);
        }
        dechunked.trim();
        jsonBody = dechunked;
      }
    }

    Serial.printf("Response body (first 500 chars): %.500s\n", jsonBody.c_str());

    if(jsonBody.indexOf("<!DOCTYPE") >= 0 || jsonBody.indexOf("<html") >= 0){
      Serial.println("ERROR: Received HTML instead of JSON");
      continue;
    }

    for(int i = 0; i < 6; i++){
      int pos = jsonBody.indexOf(String("\"") + timeNames[i] + "\"");
      if(pos < 0){
        pos = jsonBody.indexOf(String("\"") + altNames[i] + "\"");
      }

      if(pos >= 0){
        int colonPos = jsonBody.indexOf(":", pos);
        int q1 = jsonBody.indexOf('"', colonPos + 1);
        int q2 = jsonBody.indexOf('"', q1 + 1);
        if(q1 >= 0 && q2 > q1){
          times[i] = jsonBody.substring(q1 + 1, q2);
          if(times[i].length() > 5 && times[i].charAt(5) == ':'){
            times[i] = times[i].substring(0, 5);
          }
          Serial.printf("  %s = %s\n", timeNames[i], times[i].c_str());
        }
      }
    }

    for(int i = 0; i < 6; i++){
      if(times[i].length() >= 5){
        anyValid = true;
        break;
      }
    }

    if(!anyValid){
      Serial.println("No valid times parsed from this endpoint, trying fallback...");
      for(int i = 0; i < 6; i++) times[i] = "";
    }
  }

  if(!anyValid){
    Serial.println("No valid times parsed from Mawaqit endpoints, trying coordinate fallback (Aladhan)...");

    double flat = 0.0, flon = 0.0, facc = 0.0;
    if(!loadStoredLocation(flat, flon, facc)){
      server.send(502, "application/json", "{\"error\":\"No valid times and no location for fallback\"}");
      return;
    }

    HTTPClient http;
    String fallbackUrl = "https://api.aladhan.com/v1/timings?latitude=" + String(flat, 6) + "&longitude=" + String(flon, 6) + "&method=12&school=1";
    Serial.printf("Fallback request: %s\n", fallbackUrl.c_str());

    http.begin(fallbackUrl);
    http.setTimeout(15000);
    int httpCode = http.GET();

    if(httpCode != 200){
      Serial.printf("Fallback HTTP error: %d\n", httpCode);
      http.end();
      server.send(503, "application/json", "{\"error\":\"Fallback request failed\"}");
      return;
    }

    String fallbackBody = http.getString();
    http.end();
    Serial.printf("Fallback body (first 300 chars): %.300s\n", fallbackBody.c_str());

    for(int i = 0; i < 6; i++){
      int pos = fallbackBody.indexOf(String("\"") + altNames[i] + "\"");
      if(pos >= 0){
        int colonPos = fallbackBody.indexOf(":", pos);
        int q1 = fallbackBody.indexOf('"', colonPos + 1);
        int q2 = fallbackBody.indexOf('"', q1 + 1);
        if(q1 >= 0 && q2 > q1){
          times[i] = fallbackBody.substring(q1 + 1, q2);
          if(times[i].length() > 5 && times[i].charAt(5) == ':'){
            times[i] = times[i].substring(0, 5);
          }
          Serial.printf("  fallback %s = %s\n", altNames[i], times[i].c_str());
        }
      }
    }

    anyValid = false;
    for(int i = 0; i < 6; i++){
      if(times[i].length() >= 5){
        anyValid = true;
        break;
      }
    }

    if(!anyValid){
      Serial.println("No valid times parsed from any endpoint (Mawaqit + fallback)");
      server.send(502, "application/json", "{\"error\":\"No valid times in response\"}");
      return;
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
  for(int i = 0; i < 6; i++){
    if(offsets[i] != 0 && times[i].length() >= 5){
      String original = times[i];
      times[i] = addMinutesToTime(times[i], offsets[i]);
      Serial.printf("  %s: %s + %d min = %s\n", timeNames[i], original.c_str(), offsets[i], times[i].c_str());
    }
  }
  
  // Save to Preferences with RTC timestamp (not millis!)
  if(!rtc.begin()){
    Serial.println("RTC missing - cannot timestamp sync");
    server.send(500, "application/json", "{\"error\":\"RTC missing\"}");
    return;
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
  server.send(200, "application/json", "{\"ok\":true,\"message\":\"times synced\"}");
}

// Debug endpoint: dump stored Mawaqit times and freshness status
void handleMawaqitDebug(){
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
  
  if(rtc.begin()){
    unsigned long now_epoch = rtc.now().unixtime();
    unsigned long age_sec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
    float age_hours = age_sec / 3600.0;
    bool fresh = (age_sec < 25UL * 3600UL);
    json += "\"now_epoch\":" + String(now_epoch) + ",";
    json += "\"age_seconds\":" + String(age_sec) + ",";
    json += "\"age_hours\":" + String(age_hours, 2) + ",";
    json += "\"fresh\":" + String(fresh ? "true" : "false");
  }else{
    json += "\"rtc_error\":true";
  }
  
  json += "}";
  server.send(200, "application/json", json);
}

void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName){
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

  if(method == "isna"){
    fajrAngle = 15.0;
    ishaAngle = 15.0;
  }else if(method == "uoif"){
    fajrAngle = 12.0;
    ishaAngle = 12.0;
  }else if(method == "egypt"){
    fajrAngle = 19.5;
    ishaAngle = 17.5;
  }else if(method == "karachi"){
    fajrAngle = 18.0;
    ishaAngle = 18.0;
  }else if(method == "custom"){
    fajrAngle = customFajr;
    ishaAngle = customIsha;
  }else{
    methodName = "mwl";
    fajrAngle = 18.0;
    ishaAngle = 17.0;
  }
}

// Configure calculation method/angles for fallback prayer times
// GET -> current config, POST -> save config
void handleCalculationConfig(){
  if(server.method() == HTTP_GET){
    double fajrAngle, ishaAngle;
    String methodName;
    getCalculationAngles(fajrAngle, ishaAngle, methodName);
    String out = "{\"method\":\"" + methodName + "\",\"fajr_angle\":" + String(fajrAngle, 1) + ",\"isha_angle\":" + String(ishaAngle, 1) + "}";
    server.send(200, "application/json", out);
    return;
  }

  if(server.method() != HTTP_POST){
    server.send(405, "application/json", "{\"error\":\"Method not allowed\"}");
    return;
  }

  String body = server.arg(0);
  Serial.print("/api/calculation/config body: ");
  Serial.println(body);

  auto extractJsonString = [&](const String &src, const char* key)->String {
    int k = src.indexOf(String("\"") + key + "\"");
    if(k < 0) return "";
    int colon = src.indexOf(':', k);
    if(colon < 0) return "";
    int q1 = src.indexOf('"', colon + 1);
    if(q1 < 0) return "";
    int q2 = src.indexOf('"', q1 + 1);
    if(q2 < 0) return "";
    return src.substring(q1 + 1, q2);
  };

  auto extractJsonNumber = [&](const String &src, const char* key, double defVal)->double {
    int k = src.indexOf(String("\"") + key + "\"");
    if(k < 0) return defVal;
    int colon = src.indexOf(':', k);
    if(colon < 0) return defVal;
    int endp = src.indexOf(',', colon);
    if(endp < 0) endp = src.indexOf('}', colon);
    if(endp < 0) return defVal;
    String v = src.substring(colon + 1, endp);
    v.trim();
    return v.toFloat();
  };

  String method = extractJsonString(body, "method");
  if(method.length() == 0) method = "mwl";
  method.toLowerCase();

  if(!(method == "mwl" || method == "isna" || method == "uoif" || method == "egypt" || method == "karachi" || method == "custom")){
    server.send(400, "application/json", "{\"error\":\"Invalid method\"}");
    return;
  }

  double customFajr = extractJsonNumber(body, "fajr_angle", 18.0);
  double customIsha = extractJsonNumber(body, "isha_angle", 17.0);
  if(customFajr < 10.0 || customFajr > 25.0) customFajr = 18.0;
  if(customIsha < 10.0 || customIsha > 25.0) customIsha = 17.0;

  prefs.begin("adhancfg", false);
  prefs.putString("calc_method", method);
  prefs.putFloat("calc_fajr_angle", (float)customFajr);
  prefs.putFloat("calc_isha_angle", (float)customIsha);
  prefs.end();

  if(rtc.begin()) scheduleNextPrayerAlarm();

  String out = "{\"ok\":true,\"method\":\"" + method + "\",\"fajr_angle\":" + String(customFajr,1) + ",\"isha_angle\":" + String(customIsha,1) + "}";
  server.send(200, "application/json", out);
}

// GET/POST /api/adhan/config - Manage adhan track selection and duaa settings
void handleAdhanConfig(){
  if(server.method() == HTTP_GET){
    // Return current adhan configuration
    prefs.begin("adhancfg", true);
    int fajr_track = prefs.getInt("adhan_fajr_track", 1);
    int dhuhr_track = prefs.getInt("adhan_dhuhr_track", 1);
    int asr_track = prefs.getInt("adhan_asr_track", 1);
    int maghrib_track = prefs.getInt("adhan_maghrib_track", 1);
    int isha_track = prefs.getInt("adhan_isha_track", 1);
    bool fajr_duaa = prefs.getBool("adhan_fajr_duaa", true);
    bool dhuhr_duaa = prefs.getBool("adhan_dhuhr_duaa", true);
    bool asr_duaa = prefs.getBool("adhan_asr_duaa", true);
    bool maghrib_duaa = prefs.getBool("adhan_maghrib_duaa", true);
    bool isha_duaa = prefs.getBool("adhan_isha_duaa", true);
    prefs.end();

    String json = "{";
    json += "\"fajr_track\":" + String(fajr_track) + ",";
    json += "\"fajr_duaa\":" + String(fajr_duaa ? "true" : "false") + ",";
    json += "\"dhuhr_track\":" + String(dhuhr_track) + ",";
    json += "\"dhuhr_duaa\":" + String(dhuhr_duaa ? "true" : "false") + ",";
    json += "\"asr_track\":" + String(asr_track) + ",";
    json += "\"asr_duaa\":" + String(asr_duaa ? "true" : "false") + ",";
    json += "\"maghrib_track\":" + String(maghrib_track) + ",";
    json += "\"maghrib_duaa\":" + String(maghrib_duaa ? "true" : "false") + ",";
    json += "\"isha_track\":" + String(isha_track) + ",";
    json += "\"isha_duaa\":" + String(isha_duaa ? "true" : "false");
    json += "}";
    server.send(200, "application/json", json);
    return;
  }

  if(server.method() == HTTP_POST){
    // Parse and save adhan configuration
    String body = server.arg("plain");
    Serial.print("/api/adhan/config POST body: ");
    Serial.println(body);

    auto extractJsonBool = [&](const String &src, const char* key, bool defVal)->bool {
      int idx = src.indexOf(String("\"") + key + "\":");
      if(idx < 0) return defVal;
      idx += strlen(key) + 3;
      while(idx < src.length() && (src[idx] == ' ' || src[idx] == '\t')) idx++;
      if(src.substring(idx, idx+4) == "true") return true;
      if(src.substring(idx, idx+5) == "false") return false;
      return defVal;
    };

    auto extractJsonNumber = [&](const String &src, const char* key, double defVal)->double {
      int idx = src.indexOf(String("\"") + key + "\":");
      if(idx < 0) return defVal;
      idx += strlen(key) + 3;
      while(idx < src.length() && (src[idx] == ' ' || src[idx] == '\t')) idx++;
      int endIdx = idx;
      while(endIdx < src.length() && (isdigit(src[endIdx]) || src[endIdx] == '-' || src[endIdx] == '.')) endIdx++;
      if(endIdx > idx) return src.substring(idx, endIdx).toDouble();
      return defVal;
    };

    int fajr_track = (int)extractJsonNumber(body, "fajr_track", 1);
    int dhuhr_track = (int)extractJsonNumber(body, "dhuhr_track", 1);
    int asr_track = (int)extractJsonNumber(body, "asr_track", 1);
    int maghrib_track = (int)extractJsonNumber(body, "maghrib_track", 1);
    int isha_track = (int)extractJsonNumber(body, "isha_track", 1);
    
    // Constrain to 1-11
    fajr_track = constrain(fajr_track, 1, 11);
    dhuhr_track = constrain(dhuhr_track, 1, 11);
    asr_track = constrain(asr_track, 1, 11);
    maghrib_track = constrain(maghrib_track, 1, 11);
    isha_track = constrain(isha_track, 1, 11);

    bool fajr_duaa = extractJsonBool(body, "fajr_duaa", true);
    bool dhuhr_duaa = extractJsonBool(body, "dhuhr_duaa", true);
    bool asr_duaa = extractJsonBool(body, "asr_duaa", true);
    bool maghrib_duaa = extractJsonBool(body, "maghrib_duaa", true);
    bool isha_duaa = extractJsonBool(body, "isha_duaa", true);

    prefs.begin("adhancfg", false);
    prefs.putInt("adhan_fajr_track", fajr_track);
    prefs.putInt("adhan_dhuhr_track", dhuhr_track);
    prefs.putInt("adhan_asr_track", asr_track);
    prefs.putInt("adhan_maghrib_track", maghrib_track);
    prefs.putInt("adhan_isha_track", isha_track);
    prefs.putBool("adhan_fajr_duaa", fajr_duaa);
    prefs.putBool("adhan_dhuhr_duaa", dhuhr_duaa);
    prefs.putBool("adhan_asr_duaa", asr_duaa);
    prefs.putBool("adhan_maghrib_duaa", maghrib_duaa);
    prefs.putBool("adhan_isha_duaa", isha_duaa);
    prefs.end();

    Serial.printf("Adhan config saved: Fajr=%d (duaa:%d), Dhuhr=%d (duaa:%d), Asr=%d (duaa:%d), Maghrib=%d (duaa:%d), Isha=%d (duaa:%d)\n",
      fajr_track, fajr_duaa, dhuhr_track, dhuhr_duaa, asr_track, asr_duaa, maghrib_track, maghrib_duaa, isha_track, isha_duaa);

    server.send(200, "application/json", "{\"ok\":true}");
    return;
  }

  server.send(405, "text/plain", "Method not allowed");
}



void handleDisconnectWifi(){
  WiFi.disconnect(true);
  WiFi.mode(WIFI_AP);
  server.send(200, "text/plain", "WiFi disconnected");
}

// Sync time from NTP server. Returns true on success.
bool syncTimeFromNtp(unsigned long timeoutMs){
  if(!WiFi.isConnected()){
    Serial.println("Cannot sync NTP: no WiFi");
    return false;
  }
  // Use UTC time from NTP, then apply stored timezone offset when setting RTC
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  struct tm timeinfo;
  unsigned long start = millis();
  while(millis() - start < timeoutMs){
    if(getLocalTime(&timeinfo)){ break; }
    delay(200);
  }
  if(!getLocalTime(&timeinfo)){
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
  if(tzMin != 0x7fffffff) tzOffset = tzMin; // minutes
  // Construct DateTime adjusted to local time
  time_t utc = mktime(&timeinfo);
  time_t localt = utc + tzOffset * 60;
  struct tm *lt = gmtime(&localt);
  if(!lt){ Serial.println("Failed to convert local time"); return false; }
  if(!rtc.begin()){ Serial.println("RTC not present; cannot set time"); return false; }
  rtc.adjust(DateTime(lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec));
  Serial.printf("RTC set to local time (tz offset %d min): %04d-%02d-%02d %02d:%02d:%02d\n", tzOffset, lt->tm_year+1900, lt->tm_mon+1, lt->tm_mday, lt->tm_hour, lt->tm_min, lt->tm_sec);
  return true;
}

void startConfigAP(){
  if(apRunning) return;
  // remember previous LED scenario and enter BLINK mode for indication
  if(prevLedScenario < 0) prevLedScenario = ledScenario;
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
  server.onNotFound([&](){
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
void setupServerRoutes(){
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
  server.on("/stop_ap", HTTP_GET, [](){ server.send(200,"text/plain","AP stopped"); stopConfigAP(); });
  server.on("/api/calculation/config", HTTP_GET, handleCalculationConfig);
  server.on("/api/calculation/config", HTTP_POST, handleCalculationConfig);
  server.on("/sync_time", HTTP_GET, [](){ bool ok = syncTimeFromNtp(10000); if(ok){ if(rtc.begin()) scheduleNextPrayerAlarm(); server.send(200,"text/plain","Time synced"); } else server.send(500,"text/plain","Time sync failed"); });
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
}

void stopConfigAP(){
  if(!apRunning) return;
  // Stop DNS captive server
  dnsServer.stop();
  Serial.println("DNS captive portal stopped");
  server.stop();
  WiFi.softAPdisconnect(true);
  apRunning = false;
  Serial.println("Config AP stopped");
  // restore previous LED scenario if present
  if(prevLedScenario >= 0){ ledScenario = prevLedScenario; prevLedScenario = -1; }
}

// Button handling (long press)
void checkConfigButton(){
  // Simplified: only handle short press to cycle LED scenarios.
  static bool wasPressed = false;
  int val = digitalRead(CONFIG_BUTTON_PIN);
  // detect press -> release sequence
  if(val == LOW){
    if(!wasPressed){
      wasPressed = true; // button now considered pressed
    }
  } else {
    if(wasPressed){
      // release detected -> treat as short press
      wasPressed = false;
      if(isPlaying){
        stopPlay();
        // also stop LED scenario
        ledScenario = 0; setLedDuty(0);
        if(useAddressableLEDs) stripSetAll(0,0,0);
      } else {
        // cycle through scenes but skip the BLINK_INDEX (reserved for AP)
        do {
          ledScenario = (ledScenario + 1) % TOTAL_SCENES;
        } while(ledScenario == BLINK_INDEX);
        // if we switch to off ensure LEDs are off
        if(ledScenario == 0){ setLedDuty(0); if(useAddressableLEDs) stripSetAll(0,0,0); }
      }
    }
  }
}

// Load stored location (returns true if exists)
bool loadStoredLocation(double &outLat, double &outLon, double &outAcc){
  prefs.begin("adhancfg", true);
  String latS = prefs.getString("lat", "");
  String lonS = prefs.getString("lon", "");
  String accS = prefs.getString("acc", "");
  prefs.end();
  if(latS.length()==0 || lonS.length()==0) return false;
  outLat = latS.toFloat();
  outLon = lonS.toFloat();
  outAcc = accS.length()? accS.toFloat() : 9999.0;
  return true;
}

// --- Prayer times calculation (simplified, NOAA-based + twilight angles) ---
static double deg2rad(double d){ return d * M_PI / 180.0; }
static double rad2deg(double r){ return r * 180.0 / M_PI; }

// day of year from RTClib DateTime
static int dayOfYear(const DateTime &dt){
  // month lengths non-leap/leap handling
  int mdays[] = {0,31,28,31,30,31,30,31,31,30,31,30,31};
  int y = dt.year();
  bool leap = ( (y%4==0 && y%100!=0) || (y%400==0) );
  if(leap) mdays[2]=29; else mdays[2]=28;
  int doy = 0;
  for(int m=1;m<dt.month();m++) doy += mdays[m];
  doy += dt.day();
  return doy;
}

// Calculate equation of time (minutes) and solar declination (radians) for given day
static void solarDeclinationAndEqtime(int doy, double &declRad, double &eqTimeMin){
  double gamma = 2.0 * M_PI / 365.0 * (doy - 1 + 0.5); // approximate at midday
  eqTimeMin = 229.18*(0.000075 + 0.001868*cos(gamma) - 0.032077*sin(gamma) - 0.014615*cos(2*gamma) - 0.040849*sin(2*gamma));
  declRad = 0.006918 - 0.399912*cos(gamma) + 0.070257*sin(gamma) - 0.006758*cos(2*gamma) + 0.000907*sin(2*gamma) - 0.002697*cos(3*gamma) + 0.00148*sin(3*gamma);
}

// compute hour angle degrees for given zenith (degrees), latitude (rad) and decl (rad)
static bool hourAngleForZenith(double zenithDeg, double latRad, double declRad, double &Hdeg){
  double zenRad = deg2rad(zenithDeg);
  double cosH = (cos(zenRad) - sin(latRad)*sin(declRad)) / (cos(latRad)*cos(declRad));
  if(cosH > 1.0 || cosH < -1.0) return false; // sun never reaches this zenith
  double H = acos(cosH);
  Hdeg = rad2deg(H);
  return true;
}

// format minutes (local) into hh:mm string
static String formatTimeFromMinutes(double minutes){
  if(isnan(minutes)) return String("--:--");
  int mins = (int)round(minutes);
  mins = (mins + 24*60) % (24*60);
  int h = mins / 60;
  int m = mins % 60;
  char buf[8];
  snprintf(buf, sizeof(buf), "%02d:%02d", h, m);
  return String(buf);
}

// Compute and print prayer times for a given date using stored location
void computeAndPrintPrayerTimes(const DateTime &date){
  double lat, lon, acc;
  if(!loadStoredLocation(lat, lon, acc)){
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
  if(tzOffsetMin != 0x7fffffff){
    tzMin = tzOffsetMin;
    tz = tzOffsetMin / 60;
  }else{
    tz = (int)round(lon / 15.0);
    tzMin = tz * 60;
  }
  // solar noon in minutes (local time)
  double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
  // sunrise/sunset (zenith 90.833)
  double Hsun_deg;
  bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
  double sunrise = NAN, sunset = NAN;
  if(okSun){
    sunrise = solarNoon - 4.0 * Hsun_deg;
    sunset  = solarNoon + 4.0 * Hsun_deg;
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
  double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl)))); // elevation in radians (approx)
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
bool computePrayerTimesForDate(const DateTime &date, double outTimes[6], int &tzUsedMin, String &tzSource){
  double lat, lon, acc;
  if(!loadStoredLocation(lat, lon, acc)) return false;
  int doy = dayOfYear(date);
  double decl, eqt;
  solarDeclinationAndEqtime(doy, decl, eqt);
  prefs.begin("adhancfg", true);
  int tzOffsetMin = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  int tzMin;
  if(tzOffsetMin != 0x7fffffff){
    tzMin = tzOffsetMin;
    tzUsedMin = tzMin;
    tzSource = "preference";
  }else{
    int tz = (int)round(lon / 15.0);
    tzMin = tz * 60;
    tzUsedMin = tzMin;
    tzSource = "estimate";
  }
  double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
  double Hsun_deg; bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
  double sunrise = okSun ? solarNoon - 4.0 * Hsun_deg : NAN;
  double sunset  = okSun ? solarNoon + 4.0 * Hsun_deg : NAN;
  double fajrAngle, ishaAngle; String calcMethod;
  getCalculationAngles(fajrAngle, ishaAngle, calcMethod);
  double Hfajr, Hisha; bool okF = hourAngleForZenith(90.0 + fajrAngle, deg2rad(lat), decl, Hfajr);
  bool okI = hourAngleForZenith(90.0 + ishaAngle, deg2rad(lat), decl, Hisha);
  double fajr = okF ? (solarNoon - 4.0 * Hfajr) : NAN;
  double isha = okI ? (solarNoon + 4.0 * Hisha) : NAN;
  double dhuhr = solarNoon;
  double latRad = deg2rad(lat);
  double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl))));
  double asrZenith = 90.0 - rad2deg(angle);
  double Hasr_deg; bool okAsr = hourAngleForZenith(asrZenith, latRad, decl, Hasr_deg);
  double asr = okAsr ? (solarNoon + 4.0 * Hasr_deg) : NAN;
  outTimes[0]=fajr; outTimes[1]=sunrise; outTimes[2]=dhuhr; outTimes[3]=asr; outTimes[4]=sunset; outTimes[5]=isha;
  return true;
}

// HTTP handler to return today's prayer times as JSON
void handlePrayerTimes(){
  if(!rtc.begin()){
    server.send(200, "application/json", "{\"error\":\"RTC missing\"}");
    return;
  }
  DateTime now = rtc.now();
  
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
  unsigned long now_epoch = rtc.now().unixtime();
  unsigned long timeSinceSyncSec = (mq_sync_ts > 0 && now_epoch >= mq_sync_ts) ? (now_epoch - mq_sync_ts) : 999999UL;
  bool mawaqitValid = (mq_fajr.length() >= 5) && (mq_isha.length() >= 5) && (timeSinceSyncSec < 25UL * 3600UL);
  
  if(mawaqitValid){
    Serial.printf("handlePrayerTimes: Returning MAWAQIT times (synced %lu sec ago = %.1f hours)\n", timeSinceSyncSec, timeSinceSyncSec/3600.0);
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
  Serial.printf("handlePrayerTimes: Returning CALCULATED times (Mawaqit age: %lu sec, valid: %s)\n", timeSinceSyncSec, mawaqitValid ? "yes":"no");
  double times[6]; int tzMin; String tzSrc;
  if(!computePrayerTimesForDate(now, times, tzMin, tzSrc)){
    server.send(200, "application/json", "{\"error\":\"location missing\"}");
    return;
  }
  // build JSON manually
  char buf[512];
  const char *names[6] = {"fajr","sunrise","dhuhr","asr","maghrib","isha"};
  String json = "{";
  for(int i=0;i<6;i++){
    String t = formatTimeFromMinutes(times[i]);
    json += "\"" + String(names[i]) + "\":\"" + t + "\",";
  }
  // compute the next upcoming prayer (if possible) so UI can display it directly
  DateTime nowDt = rtc.now();
  DateTime nextDt; int nextIdx = 0;
  if(computeNextPrayer(nowDt, nextDt, nextIdx)){
    char nbuf[32]; snprintf(nbuf, sizeof(nbuf), "%02d:%02d", nextDt.hour(), nextDt.minute());
    char idxbuf[32]; snprintf(idxbuf, sizeof(idxbuf), "\"next\":\"%s\",\"next_index\":%d,", nbuf, nextIdx);
    json += String(idxbuf);
  }
  char tzbuf[64]; snprintf(tzbuf, sizeof(tzbuf), "\"tz_min\":%d,\"tz_source\":\"%s\",\"source\":\"calculated\"", tzMin, tzSrc.c_str());
  json += String(tzbuf);
  double fajrAngle, ishaAngle; String methodName;
  getCalculationAngles(fajrAngle, ishaAngle, methodName);
  json += ",\"calc_method\":\"" + methodName + "\",\"fajr_angle\":" + String(fajrAngle,1) + ",\"isha_angle\":" + String(ishaAngle,1);
  json += "}";
  server.send(200, "application/json", json);
}

// Debug endpoint: dump runtime status and stored prefs for quick inspection
void handleDumpStatus(){
  Serial.println("HTTP GET /dump_status -> handler entered");
  Serial.print("WiFi connected: "); Serial.println(WiFi.isConnected() ? "yes" : "no");
  Serial.print("IP: "); Serial.println(WiFi.localIP().toString());
  prefs.begin("adhancfg", true);
  String lat = prefs.getString("lat", "");
  String lon = prefs.getString("lon", "");
  String acc = prefs.getString("acc", "");
  int tz = prefs.getInt("tz_offset_min", 0x7fffffff);
  String key = prefs.getString("geo_key", "");
  Serial.print("prefs: lat="); Serial.print(lat); Serial.print(" lon="); Serial.print(lon); Serial.print(" acc="); Serial.print(acc); Serial.print(" geo_key_len="); Serial.println((int)key.length());
  prefs.end();

  bool rtc_ok = rtc.begin();
  String rtc_time = "";
  if(rtc_ok){
    DateTime now = rtc.now();
    char b[64]; snprintf(b, sizeof(b), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    rtc_time = String(b);
  }

  String wifi_state = WiFi.isConnected() ? "connected" : "disconnected";
  String ip = WiFi.isConnected() ? WiFi.localIP().toString() : "";

  char out[1024];
  snprintf(out, sizeof(out), "{\"wifi\":\"%s\",\"ip\":\"%s\",\"rtc_ok\":%d,\"rtc\":\"%s\",\"lat\":\"%s\",\"lon\":\"%s\",\"acc\":\"%s\",\"tz\":%d,\"geo_key_len\":%d}",
           wifi_state.c_str(), ip.c_str(), rtc_ok?1:0, rtc_time.c_str(), lat.c_str(), lon.c_str(), acc.c_str(), (tz==0x7fffffff? -9999:tz), (int)key.length());
  server.send(200, "application/json", String(out));
}

// ---------------- DS3231 alarm helpers (I2C register access + Alarm2 daily) ----------------
static inline uint8_t decToBcd(uint8_t val){ return ((val/10)<<4) | (val%10); }
static inline uint8_t bcdToDec(uint8_t val){ return ((val>>4)*10) + (val & 0x0F); }

// Write a single register to DS3231 (addr 0x68)
void ds3231WriteReg(uint8_t reg, uint8_t value){
  Wire.beginTransmission(0x68);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

// Read a single register from DS3231
uint8_t ds3231ReadReg(uint8_t reg){
  Wire.beginTransmission(0x68);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(0x68, (uint8_t)1);
  if(Wire.available()) return Wire.read();
  return 0;
}

// Clear alarm flags A1F/A2F in status register (0x0F)
void ds3231ClearAlarmFlags(){
  uint8_t status = ds3231ReadReg(0x0F);
  status &= ~0x03; // clear A2F (bit1) and A1F (bit0)
  ds3231WriteReg(0x0F, status);
}

// Enable Alarm2 interrupt (and INTCN) in control reg (0x0E)
void ds3231EnableAlarm2Interrupt(){
  uint8_t ctrl = ds3231ReadReg(0x0E);
  ctrl |= 0x06; // INTCN (bit2) + A2IE (bit1)
  ds3231WriteReg(0x0E, ctrl);
  ds3231ClearAlarmFlags();
}

// Disable alarm interrupts
void ds3231DisableAlarms(){
  uint8_t ctrl = ds3231ReadReg(0x0E);
  ctrl &= ~0x06; // clear INTCN and A2IE
  ds3231WriteReg(0x0E, ctrl);
  ds3231ClearAlarmFlags();
}

// Set Alarm2 to trigger daily at given hour/minute (minute resolution)
// Uses Alarm2 registers 0x0B (min), 0x0C (hour), 0x0D (day/date)
bool ds3231SetAlarm2Daily(uint8_t hour, uint8_t minute){
  if(hour > 23 || minute > 59) return false;
  // A2M2 (min) = 0 -> match minute
  uint8_t minReg = decToBcd(minute) & 0x7F; // ensure MSB=0
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

// ISR for DS3231 INT pin
void IRAM_ATTR ds3231_isr(){
  ds3231AlarmFlag = true;
}

// Compute the next prayer time (DateTime) and index (1..6) from now
// Returns true if found and fills nextDt and idx
bool computeNextPrayer(const DateTime &now, DateTime &nextDt, int &idx){
  double timesToday[6];
  double timesTomorrow[6];
  // helper to compute minutes since midnight into DateTime
  auto minutesToDateTime = [&](const DateTime &d, double mins)->DateTime{
    int m = (int)round(mins);
    m = (m + 24*60) % (24*60);
    int h = m/60; int mm = m%60;
    return DateTime(d.year(), d.month(), d.day(), h, mm, 0);
  };
  // Compute today
  {
    double lat, lon, acc;
    if(!loadStoredLocation(lat, lon, acc)) return false;
    int doy = dayOfYear(now);
    double decl, eqt;
    solarDeclinationAndEqtime(doy, decl, eqt);
    prefs.begin("adhancfg", true);
    int tzOffsetMin = prefs.getInt("tz_offset_min", 0x7fffffff);
    prefs.end();
    int tzMin = (tzOffsetMin != 0x7fffffff) ? tzOffsetMin : (int)round(lon/15.0)*60;
    double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
    double Hsun_deg; bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
    double sunrise = okSun ? solarNoon - 4.0 * Hsun_deg : NAN;
    double sunset  = okSun ? solarNoon + 4.0 * Hsun_deg : NAN;
    double Hfajr, Hisha; bool okF = hourAngleForZenith(108.0, deg2rad(lat), decl, Hfajr); // 90+18
    bool okI = hourAngleForZenith(107.0, deg2rad(lat), decl, Hisha); // 90+17
    double fajr = okF ? (solarNoon - 4.0 * Hfajr) : NAN;
    double isha = okI ? (solarNoon + 4.0 * Hisha) : NAN;
    double dhuhr = solarNoon;
    double latRad = deg2rad(lat);
    double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl))));
    double asrZenith = 90.0 - rad2deg(angle);
    double Hasr_deg; bool okAsr = hourAngleForZenith(asrZenith, latRad, decl, Hasr_deg);
    double asr = okAsr ? (solarNoon + 4.0 * Hasr_deg) : NAN;
    timesToday[0]=fajr; timesToday[1]=sunrise; timesToday[2]=dhuhr; timesToday[3]=asr; timesToday[4]=sunset; timesToday[5]=isha;
  }
  // Compute tomorrow by adding one day
  DateTime tomorrow = now + TimeSpan(1,0,0,0);
  {
    double lat, lon, acc;
    loadStoredLocation(lat, lon, acc);
    int doy = dayOfYear(tomorrow);
    double decl, eqt;
    solarDeclinationAndEqtime(doy, decl, eqt);
    prefs.begin("adhancfg", true);
    int tzOffsetMin = prefs.getInt("tz_offset_min", 0x7fffffff);
    prefs.end();
    int tzMin = (tzOffsetMin != 0x7fffffff) ? tzOffsetMin : (int)round(lon/15.0)*60;
    double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
    double Hsun_deg; bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun_deg);
    double sunrise = okSun ? solarNoon - 4.0 * Hsun_deg : NAN;
    double sunset  = okSun ? solarNoon + 4.0 * Hsun_deg : NAN;
    double Hfajr, Hisha; bool okF = hourAngleForZenith(108.0, deg2rad(lat), decl, Hfajr);
    bool okI = hourAngleForZenith(107.0, deg2rad(lat), decl, Hisha);
    double fajr = okF ? (solarNoon - 4.0 * Hfajr) : NAN;
    double isha = okI ? (solarNoon + 4.0 * Hisha) : NAN;
    double dhuhr = solarNoon;
    double latRad = deg2rad(lat);
    double angle = atan(1.0 / (1.0 + fabs(tan(latRad - decl))));
    double asrZenith = 90.0 - rad2deg(angle);
    double Hasr_deg; bool okAsr = hourAngleForZenith(asrZenith, latRad, decl, Hasr_deg);
    double asr = okAsr ? (solarNoon + 4.0 * Hasr_deg) : NAN;
    timesTomorrow[0]=fajr; timesTomorrow[1]=sunrise; timesTomorrow[2]=dhuhr; timesTomorrow[3]=asr; timesTomorrow[4]=sunset; timesTomorrow[5]=isha;
  }
  // Compare today then tomorrow to find the next > now
  for(int i=0;i<6;i++){
    double tmin = timesToday[i];
    if(!isnan(tmin)){
      DateTime candidate = DateTime(now.year(), now.month(), now.day(), 0,0,0) + TimeSpan(0, (int)(tmin/60), (int)fmod(tmin,60), 0);
      // candidate rounding: use minutes precision
      int candMin = (int)round(tmin);
      int ch = (candMin/60)%24; int cm = candMin%60;
      candidate = DateTime(now.year(), now.month(), now.day(), ch, cm, 0);
      if(candidate.unixtime() > now.unixtime() + 5){ // a small safety margin
        nextDt = candidate; idx = i+1; return true;
      }
    }
  }
  for(int i=0;i<6;i++){
    double tmin = timesTomorrow[i];
    if(!isnan(tmin)){
      int candMin = (int)round(tmin);
      int ch = (candMin/60)%24; int cm = candMin%60;
      nextDt = DateTime(tomorrow.year(), tomorrow.month(), tomorrow.day(), ch, cm, 0);
      idx = i+1; return true;
    }
  }
  return false;
}

// Schedule next prayer alarm: computes next prayer, programs Alarm2 daily at that hh:mm
void scheduleNextPrayerAlarm(){
  if(!rtc.begin()) return;
  DateTime now = rtc.now();
  DateTime nextDt; int idx;
  if(computeNextPrayer(now, nextDt, idx)){
    scheduledPrayerIndex = idx;
    scheduledPrayerTime = nextDt;
    ds3231SetAlarm2Daily(nextDt.hour(), nextDt.minute());
    // Also schedule a software fallback alarm based on millis() to ensure
    // the prayer triggers even if the DS3231 interrupt/flag is missed.
    unsigned long deltaSec = 0;
    uint32_t nowUnix = now.unixtime();
    uint32_t nextUnix = nextDt.unixtime();
    if(nextUnix > nowUnix) deltaSec = nextUnix - nowUnix;
    if(deltaSec > 0 && deltaSec < (7UL*24UL*3600UL)){
      // convert to ms, guard overflow
      unsigned long deltaMs = (unsigned long)deltaSec * 1000UL;
      softwareAlarmAt = millis() + deltaMs;
      Serial.printf("Scheduled alarm for prayer %d at %04u-%02u-%02u %02d:%02d (in %lu s, software fallback set)\n", idx, nextDt.year(), nextDt.month(), nextDt.day(), nextDt.hour(), nextDt.minute(), deltaSec);
    }else{
      softwareAlarmAt = 0;
      Serial.printf("Scheduled alarm for prayer %d at %04u-%02u-%02u %02d:%02d (software fallback not set)\n", idx, nextDt.year(), nextDt.month(), nextDt.day(), nextDt.hour(), nextDt.minute());
    }
  }else{
    Serial.println("Could not compute next prayer to schedule alarm.");
  }
}

// Try to (re)initialize the DFPlayer module and clear missing-file state.
bool tryRecoverDFPlayer(int retries=2){
  for(int i=0;i<retries;i++){
    Serial.printf("Attempting DFPlayer reinit (%d/%d)\n", i+1, retries);
    // re-init over Serial2; ask the library to reset the module on first attempt
    if(dfplayer.begin(Serial2, /*isACK=*/true, /*doReset=*/(i==0))){
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
// For prayer adhan: Fajr plays track 2, others play track 1, then track 3 (duaa) plays after
void playTrack(int track){
  // Always attempt to ensure DFPlayer available
  if(!dfAvailable){
    Serial.println("DFPlayer not available, attempting reinit...");
    if(!tryRecoverDFPlayer(2)){
      Serial.println("Cannot play: DFPlayer unavailable");
      return;
    }
  }

  // If the DFPlayer previously reported missing files, try to recover
  if(dfFileMissing){
    Serial.println("DFPlayer previously reported missing files; attempting recovery before play");
    tryRecoverDFPlayer(2);
    // clear the missing flag to allow play attempts
    dfFileMissing = false;
  }

  Serial.printf("Playing track %d\n", track);
  // Clear last DFPlayer error and request play
  dfLastError = DFERR_NONE;
  dfplayer.play(track);
  isPlaying = true;

  // Wait briefly to catch immediate DFPlayer errors (FileIndexOut / TimeOut)
  unsigned long start = millis();
  while(millis() - start < 800){
    if(dfLastError != DFERR_NONE){
      // If an error occurs even after recovery, log and stop trying
      Serial.printf("DFPlayer error after play request: %d\n", dfLastError);
      break;
    }
    delay(50);
  }
}

void stopPlay(){
  if(dfAvailable){
    dfplayer.stop();
    Serial.println("Stopped playback");
    isPlaying = false;
  }
}

// Print DFPlayer event/error details (copied/adapted from DFPlayer example)
void printDetail(uint8_t type, int value){
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
        // After adhan finishes, play duaa (track 3)
        if(shouldPlayDuaaNext){
          shouldPlayDuaaNext = false;
          Serial.println("Adhan finished, playing duaa (track 3)...");
          delay(500); // short pause before duaa
          playTrack(3);
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

void setup(){
  Serial.begin(115200);
  delay(100);
  Serial.println("AdhanBox config AP sketch starting...");

  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);

  // Initialize Serial2 for DFPlayer on GPIO1 (RX) and GPIO2 (TX)
  // Note: using GPIO1 may interfere with USB-serial console output.
  Serial2.begin(9600, SERIAL_8N1, DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);
  Serial.printf("Serial2 for DFPlayer configured RX=%d TX=%d\n", DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);

  // Initialize DFPlayer over Serial2 with ACK and reset (better detection)
  if(dfplayer.begin(Serial2, /*isACK=*/true, /*doReset=*/true)){
    dfAvailable = true;
    Serial.println("DFPlayer initialized");
    // restore saved volume if any, otherwise default to 20
    prefs.begin("adhancfg", true);
    int storedVol = prefs.getInt("volume", 20);
    // load forcePlayTrack1 preference (0 = false, 1 = true)
    forcePlayTrack1 = prefs.getBool("force_t1", false);
    // load brightness preference (default 50%)
    ledBrightness = prefs.getInt("brightness", 50);
    prefs.end();
    storedVol = constrain(storedVol, 0, 30);
    dfplayer.volume(storedVol);
    Serial.printf("DFPlayer volume set to %d\n", storedVol);
    Serial.printf("forcePlayTrack1 preference = %s\n", forcePlayTrack1?"ON":"OFF");
  }else{
    dfAvailable = false;
    Serial.println("DFPlayer not detected. Check wiring and power.");
  }

  // Initialize I2C using the pins you connected:
  // SDA -> GPIO5, SCL -> GPIO4 (user wiring)
  Wire.begin(/*sda=*/5, /*scl=*/4);
  delay(50);
  Serial.println("I2C initialized SDA=5 SCL=4");

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
    Serial.print("Current RTC time: "); Serial.println(buf);
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
  if(!useAddressableLEDs){
    ledc_channel_config(&ledc_channel);
  } else {
    Serial.println("Skipping LEDC attach because addressable LEDs are enabled");
  }
  setLedDuty(0);

  // If no geo_key stored, seed with provided HERE API key (user-supplied)
  prefs.begin("adhancfg", true);
  String existingKey = prefs.getString("geo_key", "");
  prefs.end();
  if(existingKey.length() == 0){
    prefs.begin("adhancfg", false);
    prefs.putString("geo_key", "bGuRaRQN7kTgVCUQhL5He5ffERIa-4rVRfVJ6lEKK0g");
    prefs.end();
    Serial.println("Default HERE geo_key written to prefs");
  }

  // Initialize addressable strip (native driver) if enabled
  if(useAddressableLEDs){
    // Initialize Adafruit_NeoPixel library
    leds.begin();
    // send initial black frame to clear strip
    leds.clear();
    leds.show();
    delay(50);
    // send a couple more zero frames to ensure reset
    for(int i=0;i<2;i++){
      stripSetAll(0,0,0);
      delay(20);
    }
    Serial.printf("Addressable LED strip (Adafruit_NeoPixel) initialized (%u LEDs) on pin %d\n", (uint32_t)LED_NUM, LED_DATA_PIN);
  }

  // Print stored location if any
  double lat, lon, acc;
  if(loadStoredLocation(lat, lon, acc)){
    Serial.printf("Loaded stored location: %f, %f (acc=%f)\n", lat, lon, acc);
    // If RTC present, schedule the next prayer alarm
    if(rtc.begin()){
      scheduleNextPrayerAlarm();
    }
  } else {
    Serial.println("No stored location yet.");
  }
  
  // Try to auto-reconnect to last WiFi
  bool wifiConnected = false;
  prefs.begin("adhancfg", true);
  String savedSSID = prefs.getString("wifi_ssid", "");
  String savedPass = prefs.getString("wifi_pass", "");
  prefs.end();
  
  if(savedSSID.length() > 0){
    Serial.printf("Found saved WiFi credentials: SSID=%s\n", savedSSID.c_str());
    WiFi.mode(WIFI_AP_STA);
    WiFi.setAutoReconnect(true);
    Serial.printf("Attempting auto-reconnect to '%s'...\n", savedSSID.c_str());
    WiFi.begin(savedSSID.c_str(), savedPass.c_str());
    
    unsigned long start = millis();
    while(millis() - start < 15000){  // Wait up to 15 seconds
      wl_status_t st = WiFi.status();
      if(st == WL_CONNECTED) break;
      delay(500);
      Serial.print(".");
    }
    
    if(WiFi.status() == WL_CONNECTED){
      Serial.printf("\n✓ WiFi auto-connect successful! IP=%s\n", WiFi.localIP().toString().c_str());
      wifiConnected = true;
    } else {
      Serial.printf("\n✗ WiFi auto-connect failed. Starting configuration AP.\n");
    }
  } else {
    Serial.println("No saved WiFi credentials. Starting configuration AP.");
  }
  
  // If auto-connect failed or no credentials, start config AP
  if(!wifiConnected){
    Serial.println("Starting configuration AP for user to connect.");
    startConfigAP();
  } else {
    // WiFi connected, don't start AP but still init web server for normal operations
    Serial.println("WiFi connected, initializing web server (AP not started).");
    setupServerRoutes();
    server.begin();
    delay(500);  // Give the server time to fully initialize
    Serial.println("Web server started on normal WiFi connection");
    Serial.println("API available at http://" + WiFi.localIP().toString());
    Serial.println("To reconfigure WiFi, connect to AP and use: /stop_ap");
  }
  
  Serial.println("You can also control WiFi via serial commands: startap, stopap, showloc");
}

void loop(){
  // If you have a config button connected, you can re-enable checkConfigButton();
  checkConfigButton();

  // Simple serial command interface for testing without a button
  if(Serial.available()){
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if(cmd.equalsIgnoreCase("startap")){
      startConfigAP();
      Serial.println("AP started via serial command");
    }else if(cmd.equalsIgnoreCase("stopap")){
      stopConfigAP();
      Serial.println("AP stopped via serial command");
    }else if(cmd.equalsIgnoreCase("showloc")){
      double lt, ln, ac;
      if(loadStoredLocation(lt, ln, ac)){
        Serial.printf("Stored location: %f, %f (acc=%f)\n", lt, ln, ac);
      }else{
        Serial.println("No stored location saved yet.");
      }
    }else if(cmd.equalsIgnoreCase("showtime")){
      if(rtc.begin()){
        DateTime now = rtc.now();
        char buf[64];
        snprintf(buf, sizeof(buf), "%04u-%02u-%02u %02u:%02u:%02u", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
        Serial.print("RTC: "); Serial.println(buf);
      }else{
        Serial.println("RTC not initialized or not present.");
      }
    }else if(cmd.equalsIgnoreCase("setrtc")){
      // set RTC to compile time
      if(rtc.begin()){
        rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
        Serial.println("RTC set to compile time.");
      }else{
        Serial.println("RTC not initialized or not present.");
      }
    }else if(cmd.startsWith("settz")){
      // format: settz <minutes>  e.g. settz 60 or settz -120
      String arg = cmd.substring(5);
      arg.trim();
      int val = arg.toInt();
      prefs.begin("adhancfg", false);
      prefs.putInt("tz_offset_min", val);
      prefs.end();
      Serial.printf("Timezone offset stored: %d minutes\n", val);
    }else if(cmd.equalsIgnoreCase("showtimes")){
      if(rtc.begin()){
        DateTime now = rtc.now();
        computeAndPrintPrayerTimes(now);
      }else{
        // if RTC not available, use compile date as fallback
        Serial.println("RTC not present, using compile date for times (approx)." );
        DateTime fallback(F(__DATE__), F(__TIME__));
        computeAndPrintPrayerTimes(fallback);
      }
    }else if(cmd.equalsIgnoreCase("setalarmtest")){
      // set an alarm for the next minute (test)
      if(rtc.begin()){
        DateTime now = rtc.now();
        int mm = (now.minute() + 1) % 60;
        int hh = now.hour() + (now.minute() == 59 ? 1 : 0);
        ds3231SetAlarm2Daily(hh, mm);
        scheduledPrayerIndex = 1; // test play track 1
        scheduledPrayerTime = DateTime(now.year(), now.month(), now.day(), hh%24, mm, 0);
        Serial.printf("Test alarm set for %02d:%02d\n", hh%24, mm);
      }else{
        Serial.println("RTC not present; cannot set alarm.");
      }
    }else if(cmd.equalsIgnoreCase("cancelalarms")){
      ds3231DisableAlarms();
      Serial.println("DS3231 alarms disabled and cleared.");
    }else if(cmd.equalsIgnoreCase("shownextalarm")){
      if(scheduledPrayerIndex>0){
        Serial.printf("Next scheduled prayer %d at %04u-%02u-%02u %02d:%02d\n", scheduledPrayerIndex, scheduledPrayerTime.year(), scheduledPrayerTime.month(), scheduledPrayerTime.day(), scheduledPrayerTime.hour(), scheduledPrayerTime.minute());
      }else{
        Serial.println("No prayer alarm scheduled.");
      }
    }else if(cmd.equalsIgnoreCase("dfreset") || cmd.equalsIgnoreCase("dfreprobe") || cmd.equalsIgnoreCase("dfinit")){
      // Try to reinitialize the DFPlayer and clear missing-file state
      dfFileMissing = false; // clear previous FileIndexOut state before reprobe
      if(tryRecoverDFPlayer(3)){
        Serial.println("DFPlayer recovered via serial command");
      }else{
        Serial.println("DFPlayer recovery failed");
      }
    }else if(cmd.startsWith("forcetrack1")){
      // formats: forcetrack1 on | forcetrack1 off | forcetrack1 status
      String arg = cmd.substring(11);
      arg.trim();
      if(arg.equalsIgnoreCase("on")){
        prefs.begin("adhancfg", false);
        prefs.putBool("force_t1", true);
        prefs.end();
        forcePlayTrack1 = true;
        Serial.println("forcePlayTrack1 set: ON (persisted)");
      }else if(arg.equalsIgnoreCase("off")){
        prefs.begin("adhancfg", false);
        prefs.putBool("force_t1", false);
        prefs.end();
        forcePlayTrack1 = false;
        Serial.println("forcePlayTrack1 set: OFF (persisted)");
      }else if(arg.equalsIgnoreCase("status") || arg.length()==0){
        Serial.printf("forcePlayTrack1 is %s\n", forcePlayTrack1?"ON":"OFF");
      }else{
        Serial.println("Usage: forcetrack1 on|off|status");
      }
    }else{
      Serial.printf("Unknown command: %s\n", cmd.c_str());
    }
    // playback commands
    if(cmd.startsWith("play ")){
      int t = cmd.substring(5).toInt();
      playTrack(t);
    }else if(cmd.equalsIgnoreCase("stopplay")){
      stopPlay();
    }
  }
  // Process DFPlayer responses (events/errors)
  if(dfAvailable && dfplayer.available()){
    printDetail(dfplayer.readType(), dfplayer.read());
  }
  // Update LED pattern according to scenario
  static unsigned long lastLedTick = 0;
  static int blinkState = 0;
  unsigned long now = millis();
  // if an LED test is active and expired, restore previous scenario
  if(ledTestUntil != 0 && millis() > ledTestUntil){
    ledTestUntil = 0;
    ledScenario = (prevLedScenario >= 0) ? prevLedScenario : 0;
    prevLedScenario = -1;
  }
  // run LED updates at 50Hz max
  if(now - lastLedTick >= 20){
    lastLedTick = now;
    if(useAddressableLEDs){
      // addressable animations
      static uint32_t lastPhase = 0;
      uint32_t phase = (now/20) % 1000;
      // If a LED test is active, run a short moving rainbow/chase
      if(ledTestUntil != 0 && millis() <= ledTestUntil){
        // moving rainbow across the strip using Adafruit_NeoPixel
        uint8_t offset = (now/10) & 0xFF;
        leds.clear();
        uint16_t activeCount = LED_NUM;
        for(uint16_t i=0;i<LED_NUM;i++){
          uint8_t hue = (uint8_t)((i * 256 / activeCount) + offset);
          uint8_t r,g,b; hsv2rgb(hue, 255, 220, r, g, b); // full saturation, slightly reduced brightness
          uint8_t r_adj = (r * ledBrightness) / 100;
          uint8_t g_adj = (g * ledBrightness) / 100;
          uint8_t b_adj = (b * ledBrightness) / 100;
          leds.setPixelColor(i, leds.Color(r_adj, g_adj, b_adj));
        }
        leds.show();
      }else{
        // New scene handling: static colors, blink (reserved), dynamic unified scenes
        if(ledScenario >= 0 && ledScenario < NUM_STATIC_COLORS){
          // static color scene
          uint8_t r = STATIC_COLORS[ledScenario][0];
          uint8_t g = STATIC_COLORS[ledScenario][1];
          uint8_t b = STATIC_COLORS[ledScenario][2];
          stripSetAll(r,g,b);
        } else if(ledScenario == BLINK_INDEX){
          // blink indication for AP/config mode: solid red, faster
          if((now / 300) % 2 == 0) {
            // ON: solid red
            stripSetAll(200,0,0);
          } else {
            // OFF: ensure fully black frame (no stray channels)
            stripSetAll(0,0,0);
          }
        } else if(ledScenario == DYN_HUE_INDEX){
          // dynamic hue: all LEDs same hue, cycling over time
          uint8_t hue = (now / 20) & 0xFF; // slow hue sweep
          const uint8_t vMax = 180;
          float breath = 0.8f + 0.2f * sinf((float)now * (2.0f * 3.14159265f / 5000.0f));
          uint8_t v = (uint8_t)constrain((int)(vMax * breath), 0, 255);
          uint8_t r,g,b; hsv2rgb(hue, 255, v, r, g, b);
          stripSetAll(r, g, b);
        } else if(ledScenario == DYN_FADE_INDEX){
          // dynamic fade between static palette colors (all LEDs same color)
          const uint32_t period = 4000; // ms per transition
          uint32_t t = now % (period * NUM_STATIC_COLORS);
          uint8_t idx = t / period;
          uint8_t next = (idx + 1) % NUM_STATIC_COLORS;
          float ft = (float)(t % period) / (float)period;
          // linear interpolate between STATIC_COLORS[idx] -> [next]
          uint8_t r = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][0] + ft * STATIC_COLORS[next][0]);
          uint8_t g = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][1] + ft * STATIC_COLORS[next][1]);
          uint8_t b = (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][2] + ft * STATIC_COLORS[next][2]);
          stripSetAll(r, g, b);
        } else {
          stripSetAll(0,0,0);
        }
      }
    } else {
      // single-channel PWM fallback (original behavior)
      // PWM fallback: approximate by setting global brightness from chosen scene
      if(ledScenario >= 0 && ledScenario < NUM_STATIC_COLORS){
        uint8_t r = STATIC_COLORS[ledScenario][0];
        uint8_t g = STATIC_COLORS[ledScenario][1];
        uint8_t b = STATIC_COLORS[ledScenario][2];
        // convert RGB to perceived brightness (simple average)
        uint16_t bright = ((uint16_t)r + (uint16_t)g + (uint16_t)b) / 3;
        bright = (bright * ledBrightness) / 100;
        // map 0..255 -> 0..(max duty)
        setLedDuty(bright);
      } else if(ledScenario == BLINK_INDEX){
        if((now/300) % 2 == 0) setLedDuty((220 * ledBrightness) / 100); else setLedDuty(0);
      } else if(ledScenario == DYN_HUE_INDEX){
        const uint8_t vMax = 180;
        float breath = 0.8f + 0.2f * sinf((float)now * (2.0f * 3.14159265f / 5000.0f));
        uint8_t v = (uint8_t)constrain((int)(vMax * breath), 0, 255);
        v = (v * ledBrightness) / 100;
        setLedDuty(v);
      } else if(ledScenario == DYN_FADE_INDEX){
        const uint32_t period = 4000; // ms per transition
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
      } else {
        setLedDuty(0);
      }
    }
  }
  // Handle DS3231 alarm event (flag set in ISR)
  // Fallback: if INT/SQW isn't wired we still trigger the prayer when RTC reaches the scheduled time.
  static uint32_t lastPrayerTriggeredUnix = 0;
  // software alarm fallback based on millis()
  if(softwareAlarmAt != 0 && millis() >= softwareAlarmAt){
    Serial.println("Software fallback alarm triggered (millis)");
    softwareAlarmAt = 0;
    ds3231ClearAlarmFlags();
    // Play correct track: Fajr=2, others=1
    if(scheduledPrayerIndex > 0){
      int trackToPlay = (scheduledPrayerIndex == 1) ? 2 : 1;
      shouldPlayDuaaNext = true;
      playTrack(trackToPlay);
    }
    scheduleNextPrayerAlarm();
  }
  if(rtc.begin() && scheduledPrayerIndex > 0){
    DateTime nowRtc = rtc.now();
    uint32_t nowUnix = nowRtc.unixtime();
    if(nowUnix >= scheduledPrayerTime.unixtime() && nowUnix != lastPrayerTriggeredUnix){
      Serial.println("RTC reached scheduled prayer time (fallback polling), triggering prayer.");
      lastPrayerTriggeredUnix = nowUnix;
      // clear DS3231 alarm flags if present
      ds3231ClearAlarmFlags();
      // Play correct track: Fajr=2, others=1
      int trackToPlay = (scheduledPrayerIndex == 1) ? 2 : 1;
      shouldPlayDuaaNext = true;
      playTrack(trackToPlay);
      // Re-schedule next prayer
      scheduleNextPrayerAlarm();
    }
  }

  if(ds3231AlarmFlag){
    ds3231AlarmFlag = false;
    // Clear alarm flags on chip
    ds3231ClearAlarmFlags();
    Serial.println("DS3231 alarm triggered.");
    // Play scheduled prayer: Fajr (index 1) plays track 2, all others play track 1
    int trackToPlay = 1;
    if(scheduledPrayerIndex == 1){
      trackToPlay = 2; // Fajr plays track 2
      Serial.println("Prayer: Fajr (playing track 2)");
    } else if(scheduledPrayerIndex > 0){
      trackToPlay = 1; // All other prayers play track 1
      Serial.printf("Prayer index %d (playing track 1)\n", scheduledPrayerIndex);
    }
    // Set flag to play duaa (track 3) after adhan finishes
    shouldPlayDuaaNext = true;
    playTrack(trackToPlay);
    // Re-schedule next prayer
    scheduleNextPrayerAlarm();
  }
  
  // Handle HTTP server requests (always, whether in AP mode or normal WiFi)
  server.handleClient();
  
  if(apRunning){
    // process captive DNS requests so clients are redirected to our AP IP
    dnsServer.processNextRequest();
    // auto-stop after timeout removed: AP will stop only when requested
    // by the UI ("Arrêter AP") or via serial command to avoid unwanted
    // disconnections during configuration.
  }
  // small delay to reduce CPU while idle
  delay(10);
}


