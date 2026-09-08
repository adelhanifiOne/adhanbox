//Version: 1.0.0
// ═══════════════════════════════════════════════════════════════════════════
// Halo v1 : support de telephone a anneau lumineux (ESP32-C3-MINI-1, 24 LED)
//
// Derive du firmware AdhanBox V3 (adhanbox_v3/adhanbox_v3.ino), sans audio,
// sans microSD, sans RTC : l'heure vient du NTP, resynchronisee toutes les
// heures. A l'heure de la priere, l'anneau joue la scene « priere » pendant
// quelques minutes (le halo), au lieu de jouer l'adhan.
//
// Ce qui est repris tel quel de la V3, pour que l'application mobile parle au
// Halo comme a une AdhanBox : appairage BLE (memes UUID), API HTTP (memes
// routes, meme jeton X-API-Key, meme /api/device/info), calcul des horaires,
// synchro Mawaqit, methodes de calcul, decalages par priere, scenes LED
// (memes numeros), OTA signee et rollback, remise a zero usine.
//
// Ce qui est propre au Halo : le bouton utilisateur (appui court = arret du
// halo en cours ou allumer/eteindre, appui long = scene suivante, 5 s =
// appairage), le capteur de lumiere (mode nuit automatique), la respiration
// blanche « pas d'heure » tant que le NTP n'a pas repondu, le plafond de
// luminosite a 60 % (budget de puissance, SCHEMA.md §5).
//
// Brochage (SCHEMA.md §4) : LED data IO10, bouton IO3 (vers GND, pull-up
// interne), capteur de lumiere IO4 (ADC1_CH4), USB natif IO18/IO19.
//
// Carte Arduino : "ESP32C3 Dev Module", USB CDC On Boot = Enabled, partition
// "Minimal SPIFFS (1.9MB APP with OTA)", build_opt.h = -DUPDATE_SIGN.
// ═══════════════════════════════════════════════════════════════════════════
#include <Arduino.h>
#include <esp_mac.h>          // esp_read_mac() : MAC eFuse, lisible sans Wi-Fi
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <WebServer.h>
#include <Preferences.h>
#include <nvs_flash.h>        // remise a zero usine : effacement de la NVS
#include <esp_wifi.h>         // lecture des identifiants Wi-Fi memorises (usine)
#include <DNSServer.h>
#include <ESPmDNS.h>
#include <ArduinoOTA.h>
#include <Update.h>
#include <HTTPClient.h>
#include <Adafruit_NeoPixel.h>
#include <time.h>
#include <sys/time.h>       // settimeofday : heure de secours donnee par l'app
#include <math.h>
#include "esp_sntp.h"         // intervalle de resynchronisation NTP
#include "esp_task_wdt.h"     // watchdog materiel : reboot si le firmware freeze
#include "esp_ota_ops.h"      // rollback OTA : revient a la version precedente si boot-loop
#include "esp_system.h"       // esp_reset_reason : reset logiciel ou coupure de courant ?

#define HALO_VERSION  "1.0.0"
#define HALO_HARDWARE "halo"

// ── Identite reseau ──────────────────────────────────────────────────────────
// Memes prefixes que la V3 : l'app filtre les appareils sur ces noms.
#define BLE_NAME_PREFIX "AdhanBox-"
#define AP_SSID_PREFIX  "AdhanBox-"
#define OTA_HOSTNAME    "adhanbox"

// ── Brochage ─────────────────────────────────────────────────────────────────
#define LED_NUM       24
#define LED_DATA_PIN  10
#define BTN_PIN       3      // SW3 vers GND
#define ALS_PIN       4      // ALS-PT19 + R8 10k vers GND : 0 V dans le noir

// ── Luminosite ───────────────────────────────────────────────────────────────
// L'app regle 0..100 ; l'anneau ne depasse jamais BRIGHT_CAP % (24 LED d'une
// couleur a 60 % = 175 mA, n'importe quel port USB tient).
#define BRIGHT_CAP 60

static volatile bool _wdtArmed = false;   // WDT arme seulement une fois loop() lance

// ═══════════════════════════════════════════════════════════════════════════
// BLE provisioning : repris de la V3, meme service GATT
// ═══════════════════════════════════════════════════════════════════════════
#define ENABLE_BLE 1
#if ENABLE_BLE
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define BLE_SVC_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"    // write
#define BLE_PASS_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a9"    // write
#define BLE_STATUS_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26aa"    // read+notify
#define BLE_WIFI_SCAN_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ab"    // write+notify (scan Wi-Fi)

static BLEServer *_bleServer = nullptr;
static BLECharacteristic *_bleStatusChar = nullptr;
static BLECharacteristic *_bleWifiScanChar = nullptr;
static bool _bleActive = false;
static bool _bleClientConn = false;
static String _blePendingSSID;
static String _blePendingPass;
static volatile bool _bleCredsReady = false;   // pose dans la tache BLE, traite dans loop()

class _BLEServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    _bleClientConn = true;
    Serial.println("[BLE] client connecte");
  }
  void onDisconnect(BLEServer *s) override {
    _bleClientConn = false;
    Serial.println("[BLE] client deconnecte");
    if (_bleActive) s->startAdvertising();
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
    Serial.println("[BLE] mot de passe recu");
    if (_blePendingSSID.length() > 0) _bleCredsReady = true;
  }
};

// L'app ecrit "scan" : on balaye les reseaux et on notifie le resultat en JSON,
// un paquet par reseau (20 au plus). Meme protocole que la V3.
class _BLEWifiScanCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String cmd = String(c->getValue().c_str());
    cmd.trim();
    if (cmd != "scan") return;
    Serial.println("[BLE] scan Wi-Fi demande");
    xTaskCreate([](void *) {
      WiFi.mode(WIFI_STA);
      WiFi.setAutoReconnect(false);
      WiFi.disconnect(false, false);
      delay(200);
      WiFi.scanDelete();
      int n = WiFi.scanNetworks(false, true);
      for (int attempt = 0; n < 0 && attempt < 4; attempt++) {
        WiFi.scanDelete();
        delay(400);
        n = WiFi.scanNetworks(false, true);
      }
      if (n < 0) n = 0;
      WiFi.setAutoReconnect(true);
      int count = min(n, 20);
      if (_bleWifiScanChar && _bleClientConn) {
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
          _bleWifiScanChar->setValue("{\"type\":\"end\"}");
          _bleWifiScanChar->notify();
        }
      }
      WiFi.scanDelete();
      vTaskDelete(nullptr);
    }, "ble_wifi_scan", 16384, nullptr, 1, nullptr);
  }
};
#else
static bool _bleActive = false;
#endif

// ═══════════════════════════════════════════════════════════════════════════
// Etat global
// ═══════════════════════════════════════════════════════════════════════════
static String _otaPass;    // generes au premier demarrage, uniques par carte
static String _apiToken;

enum WifiConnectState { WCS_IDLE, WCS_CONNECTING, WCS_CONNECTED, WCS_FAILED };
static WifiConnectState wifiConnectState = WCS_IDLE;
static String wifiConnectSSID, wifiConnectPass;
static unsigned long wifiConnectStart = 0;
#define WIFI_CONNECT_TIMEOUT_MS 20000UL

Adafruit_NeoPixel leds(LED_NUM, LED_DATA_PIN, NEO_GRB + NEO_KHZ800);
WebServer server(80);
Preferences prefs;
DNSServer dnsServer;
const byte DNS_PORT = 53;
bool apRunning = false;
unsigned long apStartTime = 0;

// Signal "rebooter en mode appairage BLE" : memoire RTC, survit a ESP.restart()
#define PAIR_BOOT_MAGIC 0x50414952UL   // "PAIR"
RTC_NOINIT_ATTR uint32_t g_pairBootMagic;
// Halo en cours, en memoire RTC : survit a un reset logiciel (OTA, watchdog,
// appairage) pour reprendre la scene la ou elle en etait.
#define HALO_CARRY_MAGIC 0x48414C4FUL  // "HALO"
RTC_NOINIT_ATTR uint32_t g_haloCarryMagic;
RTC_NOINIT_ATTR int32_t  g_haloCarryIndex;
RTC_NOINIT_ATTR int64_t  g_haloCarryUntilUtc;   // fin du halo, epoch UTC

// LED
int ledBrightness = 50;                 // reglage de l'app, 0..100
int ledScenario = 8;                    // teinte dynamique par defaut
bool ledCustomActive = false;           // couleur libre (roue chromatique) : prime sur la scene
uint8_t ledCustomR = 255, ledCustomG = 200, ledCustomB = 0;
volatile bool _ledDirty = false;        // sauvegarde NVS differee de la couleur libre
unsigned long _ledDirtyAt = 0;
unsigned long ledTestUntil = 0;
int prevLedScenario = -1;               // scene a restaurer apres appairage / test

// Halo de priere : scene « priere » pendant halo_min minutes
static int haloPrayerIndex = 0;          // 0 = pas de halo en cours
static unsigned long haloUntilMs = 0;
static int haloPrevScenario = -1;
static bool haloPrevCustom = false;

// Horaires
static int scheduledPrayerIndex = 0;     // 1=Fajr 2=Lever 3=Dhuhr 4=Asr 5=Maghrib 6=Isha
static time_t scheduledPrayerLocal = 0;  // « epoch local » = UTC + decalage (voir plus bas)

// Capteur de lumiere
static float alsEma = -1.0f;             // moyenne glissante de l'ADC (0..4095)
static bool nightMode = false;
static int nightPct = 15;                // luminosite de nuit (als_night_pct), rafraichie par alsTick

// ── Declarations anticipees ──────────────────────────────────────────────────
void handleSetLocation(); void handleSetTZ(); void handleShowLoc(); void handleShowTime();
void handleSetBrightness(); void handleGetBrightness(); void handleSetLedScenario(); void handleSetLedRgb();
void handleLedTest(); void handleSetLed(); void handleLedOff(); void handleLedStatus();
void handleConnectWifi(); void handleWifiStatus(); void handleScanWifi(); void handleDisconnectWifi();
void handleMawaqitConfig(); void handleMawaqitSync(); void handleMawaqitDebug();
void handleMawaqitGetOffsets(); void handleMawaqitSetOffsets();
void handleCalculationConfig(); void handleAdhanConfig(); void handlePrayerTimes(); void handleDumpStatus();
void handleHaloConfig(); void handleHaloStatus(); void handleHaloStop(); void handleHaloTest();
void handleFirmwareVersion(); void handleDeviceInfo(); void handleDiag(); void handleSetRtcManual(); void handleApiTime();
void handleFactoryStatus(); void handleFactoryReset();
void handleOtaUpload(); void handleOtaUploadComplete(); void handleUpdatePage(); void handleRoot();
bool requireApiKey(); void setupOTA(); void setupServerRoutes(); void startServices();
void startConfigAP(); void stopConfigAP();
bool syncTimeFromNtp(unsigned long timeoutMs = 10000);
static void saveEpoch();
static bool restoreCarriedTime();
void scheduleNextPrayer();
bool computeNextPrayer(time_t nowLocal, time_t &nextLocal, int &idx);
bool performMawaqitSync(String &errorMsg);
void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName);
bool loadStoredLocation(double &outLat, double &outLon, double &outAcc);
void haloStart(int prayerIndex, int minutes);
void haloStop();
static String deviceIdHex();
static void bancCommande(String c);
#if ENABLE_BLE
void startBLEProvisioning(); void stopBLEProvisioning(); void handleBLEProvisioning();
#endif

// ═══════════════════════════════════════════════════════════════════════════
// LED : rendu
// ═══════════════════════════════════════════════════════════════════════════
static inline void hsv2rgb(uint8_t h, uint8_t s, uint8_t v, uint8_t &r, uint8_t &g, uint8_t &b) {
  if (s == 0) { r = g = b = v; return; }
  uint8_t region = h / 43;
  uint8_t remainder = (h - (region * 43)) * 6;
  uint8_t p = (v * (255 - s)) >> 8;
  uint8_t q = (v * (255 - ((s * remainder) >> 8))) >> 8;
  uint8_t t = (v * (255 - ((s * (255 - remainder)) >> 8))) >> 8;
  switch (region) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    default: r = v; g = p; b = q; break;
  }
}

// Luminosite reellement appliquee : reglage de l'app, plafonne, et reduit la
// nuit si le capteur le dit.
static int effectiveBrightness() {
  int b = ledBrightness;
  if (b > BRIGHT_CAP) b = BRIGHT_CAP;
  if (nightMode && b > nightPct) b = nightPct;
  return b;
}
static int _fxBright = 50;   // rafraichi une fois par image, pour ne pas lire la NVS par LED

static inline void pixel(uint16_t i, uint8_t r, uint8_t g, uint8_t b) {
  leds.setPixelColor(i, leds.Color((r * _fxBright) / 100, (g * _fxBright) / 100, (b * _fxBright) / 100));
}

static inline void stripSetAll(uint8_t r, uint8_t g, uint8_t b) {
  for (uint16_t i = 0; i < LED_NUM; i++) pixel(i, r, g, b);
  leds.show();
}

static void clearStrip() {
  for (int i = 0; i < 3; i++) { leds.clear(); leds.show(); delay(20); }
}

// Scenes : memes numeros que la V3, l'app les connait.
static const uint8_t STATIC_COLORS[][3] = {
  { 0, 0, 0 },      // 0 eteint
  { 255, 0, 0 },    // 1 rouge
  { 255, 0, 180 },  // 2 rose
  { 0, 60, 255 },   // 3 bleu
  { 180, 0, 255 },  // 4 violet
  { 0, 255, 0 },    // 5 vert
  { 255, 255, 0 },  // 6 jaune
};
static const uint8_t NUM_STATIC_COLORS = sizeof(STATIC_COLORS) / sizeof(STATIC_COLORS[0]);
const int BLINK_INDEX = 7;      // clignotant rouge : appairage / point d'acces
const int DYN_HUE_INDEX = 8;
const int DYN_FADE_INDEX = 9;
const int SCENE_PRAYER = 10;    // le halo
const int SCENE_STARS  = 11;
const int SCENE_CANDLE = 12;
const int SCENE_WAVE   = 13;    // sur un anneau, la crete qui tourne se voit vraiment
const int SCENE_DAWN   = 14;
const int TOTAL_SCENES = 15;

static void renderScene(int scene, unsigned long now) {
  if (scene >= 0 && scene < NUM_STATIC_COLORS) {
    stripSetAll(STATIC_COLORS[scene][0], STATIC_COLORS[scene][1], STATIC_COLORS[scene][2]);
  } else if (scene == BLINK_INDEX) {
    if ((now / 300) % 2 == 0) stripSetAll(200, 0, 0); else stripSetAll(0, 0, 0);
  } else if (scene == DYN_HUE_INDEX) {
    uint8_t hue = (now / 20) & 0xFF;
    float breath = 0.8f + 0.2f * sinf((float)now * (2.0f * 3.14159265f / 5000.0f));
    uint8_t v = (uint8_t)constrain((int)(180 * breath), 0, 255);
    uint8_t r, g, b;
    hsv2rgb(hue, 255, v, r, g, b);
    stripSetAll(r, g, b);
  } else if (scene == DYN_FADE_INDEX) {
    const uint32_t period = 4000;
    uint32_t t = now % (period * NUM_STATIC_COLORS);
    uint8_t idx = t / period;
    uint8_t next = (idx + 1) % NUM_STATIC_COLORS;
    float ft = (float)(t % period) / (float)period;
    stripSetAll((uint8_t)((1.0f - ft) * STATIC_COLORS[idx][0] + ft * STATIC_COLORS[next][0]),
                (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][1] + ft * STATIC_COLORS[next][1]),
                (uint8_t)((1.0f - ft) * STATIC_COLORS[idx][2] + ft * STATIC_COLORS[next][2]));
  } else if (scene == SCENE_PRAYER) {
    // Le halo : respiration turquoise, avec un point plus clair qui fait le
    // tour de l'anneau en 12 s. Sur un anneau derriere un telephone, c'est
    // le mouvement qui attire l'oeil, pas la couleur.
    float breath = 0.55f + 0.45f * sinf((float)now * (2.0f * 3.14159265f / 4000.0f));
    float head = fmodf((float)now / 12000.0f, 1.0f) * LED_NUM;
    for (uint16_t i = 0; i < LED_NUM; i++) {
      float d = fabsf((float)i - head);
      if (d > LED_NUM / 2.0f) d = LED_NUM - d;
      float local = 0.7f + 0.3f * expf(-(d * d) / 3.0f);
      float k = breath * local;
      pixel(i, 0, (uint8_t)(150 * k), (uint8_t)(105 * k));
    }
    leds.show();
  } else if (scene == SCENE_STARS) {
    static uint32_t starAt[LED_NUM];
    static uint16_t starDur[LED_NUM];
    static uint8_t  starPeak[LED_NUM];
    static bool starsReady = false;
    if (!starsReady) {
      for (uint16_t i = 0; i < LED_NUM; i++) { starAt[i] = 0; starDur[i] = 0; starPeak[i] = 0; }
      starsReady = true;
    }
    if (random(0, 100) < 6) {
      uint16_t i = random(0, LED_NUM);
      if (now - starAt[i] >= starDur[i]) {
        starAt[i] = now;
        starDur[i] = 900 + random(0, 1400);
        starPeak[i] = 150 + random(0, 106);
      }
    }
    for (uint16_t i = 0; i < LED_NUM; i++) {
      float v = 0.0f;
      if (now - starAt[i] < starDur[i]) {
        float p = (float)(now - starAt[i]) / (float)starDur[i];
        v = 0.5f * (1.0f - cosf(6.2831853f * p));
      }
      pixel(i, (uint8_t)(starPeak[i] * v * 0.80f), (uint8_t)(starPeak[i] * v * 0.88f), (uint8_t)(14.0f + starPeak[i] * v));
    }
    leds.show();
  } else if (scene == SCENE_CANDLE) {
    static float candleDrift = 0.0f, candleDriftTarget = 0.0f;
    static uint32_t candleDriftAt = 0;
    static float candleFlutter = 0.0f;
    static uint32_t candleFlutterStart = 0, candleFlutterDur = 1, candleFlutterAt = 2500;
    static float candlePhase[LED_NUM];
    static bool candleReady = false;
    if (!candleReady) {
      for (uint16_t i = 0; i < LED_NUM; i++) candlePhase[i] = (float)random(0, 628) / 100.0f;
      candleReady = true;
    }
    float ct = (float)now * 0.001f;
    if (now >= candleDriftAt) {
      candleDriftTarget = (float)(random(0, 60) - 30) / 1000.0f;
      candleDriftAt = now + 900 + random(0, 1200);
    }
    candleDrift += (candleDriftTarget - candleDrift) * 0.02f;
    if (now >= candleFlutterAt) {
      candleFlutter = 0.09f + (float)random(0, 90) / 1000.0f;
      candleFlutterStart = now;
      candleFlutterDur = 320 + random(0, 220);
      candleFlutterAt = now + 1800 + random(0, 2700);
    }
    float candleDip = 0.0f;
    if (now - candleFlutterStart < candleFlutterDur) {
      float p = (float)(now - candleFlutterStart) / (float)candleFlutterDur;
      candleDip = candleFlutter * 0.5f * (1.0f - cosf(6.2831853f * p));
    }
    float candleBase = 0.87f + 0.055f * sinf(ct * 0.90f) + 0.035f * sinf(ct * 2.30f + 1.7f)
                     + 0.022f * sinf(ct * 5.10f + 3.1f) + candleDrift - candleDip;
    for (uint16_t i = 0; i < LED_NUM; i++) {
      float intensity = candleBase + 0.040f * sinf(ct * 1.40f + candlePhase[i]);
      intensity = constrain(intensity, 0.35f, 1.0f);
      float k = (intensity - 0.35f) / 0.65f;
      pixel(i, (uint8_t)(255 * intensity), (uint8_t)((46.0f + 34.0f * k) * intensity), (uint8_t)((2.0f + 5.0f * k) * intensity));
    }
    leds.show();
  } else if (scene == SCENE_WAVE) {
    float wt = (float)now * 0.001f;
    float p = fmodf(wt / 6.0f, 1.0f);
    float swell = 0.5f * (1.0f - cosf(6.2831853f * p));
    swell = powf(swell, 1.6f);
    float head = fmodf(wt * 3.2f, (float)LED_NUM);
    uint8_t r = (uint8_t)(10.0f + 50.0f * swell);
    uint8_t g = (uint8_t)(60.0f + 160.0f * swell);
    uint8_t b = (uint8_t)(180.0f + 75.0f * swell);
    for (uint16_t i = 0; i < LED_NUM; i++) {
      float d = fabsf((float)i - head);
      if (d > LED_NUM / 2.0f) d = LED_NUM - d;
      float local = 0.78f + 0.22f * expf(-(d * d) / 9.0f);
      float intensity = (0.30f + 0.70f * swell) * local;
      pixel(i, (uint8_t)(r * intensity), (uint8_t)(g * intensity), (uint8_t)(b * intensity));
    }
    leds.show();
  } else if (scene == SCENE_DAWN) {
    static const uint8_t DAWN[][3] = {
      {   6,   8,  46 }, {  46,  22,  78 }, { 150,  54,  52 }, { 245, 132,  60 }, { 255, 198, 146 },
    };
    const uint8_t DAWN_N = 5;
    const float DAWN_PERIOD = 360.0f;
    float dt = fmodf((float)now * 0.001f, DAWN_PERIOD) / DAWN_PERIOD;
    float tri = (dt < 0.5f) ? (dt * 2.0f) : (2.0f - dt * 2.0f);
    float pos = tri * (DAWN_N - 1);
    uint8_t k = (uint8_t)pos;
    if (k >= DAWN_N - 1) k = DAWN_N - 2;
    float f = pos - k;
    float breathe = 0.94f + 0.06f * sinf((float)now * 0.00042f);
    stripSetAll((uint8_t)(((1.0f - f) * DAWN[k][0] + f * DAWN[k + 1][0]) * breathe),
                (uint8_t)(((1.0f - f) * DAWN[k][1] + f * DAWN[k + 1][1]) * breathe),
                (uint8_t)(((1.0f - f) * DAWN[k][2] + f * DAWN[k + 1][2]) * breathe));
  } else {
    stripSetAll(0, 0, 0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Heure : NTP, fuseau, « epoch local »
// ═══════════════════════════════════════════════════════════════════════════
// Convention : le systeme est en UTC (configTime(0, 0, ...)). Tous les calculs
// d'horaires se font en « epoch local » = UTC + decalage du fuseau en secondes,
// decoupe avec gmtime_r. C'est ce que la V3 faisait en reglant sa RTC a
// l'heure locale.
static bool timeSet() { return time(nullptr) > 1700000000; }
static bool _timeFromPhone = false;   // heure posee par l'app, en attendant le NTP
static bool _timeCarried = false;     // heure reprise de l'horloge interne apres un reset logiciel
static inline bool timeApprox() { return _timeFromPhone || _timeCarried; }

static int tzOffsetMinStored() {
  prefs.begin("adhancfg", true);
  int tz = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  return tz;
}

static int tzOffsetMin() {
  int tz = tzOffsetMinStored();
  if (tz != 0x7fffffff) return tz;
  double lat, lon, acc;
  if (loadStoredLocation(lat, lon, acc)) return (int)round(lon / 15.0) * 60;
  return 0;
}

static time_t nowLocal() { return time(nullptr) + (time_t)tzOffsetMin() * 60; }

static void localTm(time_t local, struct tm &lt) { gmtime_r(&local, &lt); }

// Jours depuis 1970-01-01 pour une date civile (H. Hinnant), sans dependre de TZ.
static time_t civilToEpoch(int y, int m, int d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (time_t)(era * 146097 + (int)doe - 719468) * 86400;
}

static String fmtLocal(time_t local) {
  struct tm lt; localTm(local, lt);
  char b[32];
  snprintf(b, sizeof(b), "%04d-%02d-%02d %02d:%02d:%02d", lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, lt.tm_hour, lt.tm_min, lt.tm_sec);
  return String(b);
}

// ── Heure sans RTC ───────────────────────────────────────────────────────────
// Le C3 n'a pas de puce RTC ni de pile, mais son horloge systeme tourne sur
// le timer RTC interne, qui survit a un reset LOGICIEL (ESP.restart, watchdog,
// OTA, appairage) et ne repart a zero que sur coupure de courant. On sauvegarde
// donc l'heure en NVS toutes les 15 min ; au demarrage, si le reset est
// logiciel et que l'horloge interne est coherente avec cette sauvegarde
// (jamais en arriere, moins de 7 jours devant), on la garde en attendant le
// NTP. Sur coupure de courant, l'horloge est fausse et la sauvegarde trop
// vieille pour servir : pas d'heure, respiration blanche.
static void saveEpoch() {
  if (!timeSet() || timeApprox()) return;   // on ne sauvegarde qu'une heure sure
  prefs.begin("adhancfg", false);
  prefs.putULong("last_epoch", (unsigned long)time(nullptr));
  prefs.end();
}

static bool restoreCarriedTime() {
  esp_reset_reason_t why = esp_reset_reason();
  bool soft = (why == ESP_RST_SW || why == ESP_RST_PANIC || why == ESP_RST_INT_WDT || why == ESP_RST_TASK_WDT
               || why == ESP_RST_WDT || why == ESP_RST_DEEPSLEEP);
  prefs.begin("adhancfg", true);
  unsigned long last = prefs.getULong("last_epoch", 0);
  prefs.end();
  time_t now = time(nullptr);
  bool plausible = soft && last > 1700000000UL && now >= (time_t)last - 60 && now < (time_t)last + 7 * 86400;
  Serial.printf("Reset %d, horloge interne %ld, derniere sauvegarde %lu -> %s\n", (int)why, (long)now, last,
                plausible ? "heure reprise (approx.)" : "pas d'heure");
  if (!plausible) {
    struct timeval tv = { .tv_sec = 0, .tv_usec = 0 };   // on ne garde pas une heure douteuse
    settimeofday(&tv, nullptr);
    g_haloCarryMagic = 0;
    return false;
  }
  _timeCarried = true;
  return true;
}

bool syncTimeFromNtp(unsigned long timeoutMs) {
  if (!WiFi.isConnected()) { Serial.println("NTP impossible : pas de Wi-Fi"); return false; }
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  esp_sntp_set_sync_interval(60UL * 60UL * 1000UL);   // resynchronisation toutes les heures
  unsigned long start = millis();
  while (millis() - start < timeoutMs && !timeSet()) {
    if (_wdtArmed) esp_task_wdt_reset();
    delay(200);
  }
  if (!timeSet()) { Serial.println("NTP : pas de reponse"); return false; }
  _timeFromPhone = false;
  _timeCarried = false;
  saveEpoch();
  Serial.printf("NTP OK, heure locale %s (UTC%+d min)\n", fmtLocal(nowLocal()).c_str(), tzOffsetMin());
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Horaires de priere : calcul (NOAA + angles crepusculaires), repris de la V3
// ═══════════════════════════════════════════════════════════════════════════
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

static double deg2rad(double d) { return d * M_PI / 180.0; }
static double rad2deg(double r) { return r * 180.0 / M_PI; }

static int dayOfYear(int y, int m, int d) {
  int mdays[] = { 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
  if ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)) mdays[2] = 29;
  if (m < 1 || m > 12) return 1;
  int doy = 0;
  for (int k = 1; k < m; k++) doy += mdays[k];
  return doy + constrain(d, 1, mdays[m]);
}

static void solarDeclinationAndEqtime(int doy, double &declRad, double &eqTimeMin) {
  double gamma = 2.0 * M_PI / 365.0 * (doy - 1 + 0.5);
  eqTimeMin = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma));
  declRad = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma);
}

static bool hourAngleForZenith(double zenithDeg, double latRad, double declRad, double &Hdeg) {
  double cosH = (cos(deg2rad(zenithDeg)) - sin(latRad) * sin(declRad)) / (cos(latRad) * cos(declRad));
  if (cosH > 1.0 || cosH < -1.0) return false;
  Hdeg = rad2deg(acos(cosH));
  return true;
}

static String formatTimeFromMinutes(double minutes) {
  if (isnan(minutes)) return String("--:--");
  int mins = ((int)round(minutes) + 24 * 60) % (24 * 60);
  char buf[8];
  snprintf(buf, sizeof(buf), "%02d:%02d", mins / 60, mins % 60);
  return String(buf);
}

void getCalculationAngles(double &fajrAngle, double &ishaAngle, String &methodName) {
  prefs.begin("adhancfg", true);
  String method = prefs.getString("calc_method", "mwl");
  double customFajr = prefs.getFloat("calc_fajr_angle", 18.0f);
  double customIsha = prefs.getFloat("calc_isha_angle", 17.0f);
  prefs.end();
  method.toLowerCase();
  methodName = method;
  if (method == "isna") { fajrAngle = 15.0; ishaAngle = 15.0; }
  else if (method == "uoif") { fajrAngle = 12.0; ishaAngle = 12.0; }
  else if (method == "egypt") { fajrAngle = 19.5; ishaAngle = 17.5; }
  else if (method == "karachi") { fajrAngle = 18.0; ishaAngle = 18.0; }
  else if (method == "custom") { fajrAngle = customFajr; ishaAngle = customIsha; }
  else { methodName = "mwl"; fajrAngle = 18.0; ishaAngle = 17.0; }
}

// Horaires du jour (minutes depuis minuit local), decalages utilisateur inclus.
static bool computePrayerTimesForDate(int y, int m, int d, double outTimes[6], int &tzUsedMin, String &tzSource) {
  double lat, lon, acc;
  if (!loadStoredLocation(lat, lon, acc)) return false;
  double decl, eqt;
  solarDeclinationAndEqtime(dayOfYear(y, m, d), decl, eqt);
  int tzStored = tzOffsetMinStored();
  int tzMin;
  if (tzStored != 0x7fffffff) { tzMin = tzStored; tzSource = "preference"; }
  else { tzMin = (int)round(lon / 15.0) * 60; tzSource = "estimate"; }
  tzUsedMin = tzMin;
  double solarNoon = 720.0 - 4.0 * lon - eqt + tzMin;
  double Hsun;
  bool okSun = hourAngleForZenith(90.833, deg2rad(lat), decl, Hsun);
  double fajrAngle, ishaAngle; String calcMethod;
  getCalculationAngles(fajrAngle, ishaAngle, calcMethod);
  double Hf, Hi, Ha;
  bool okF = hourAngleForZenith(90.0 + fajrAngle, deg2rad(lat), decl, Hf);
  bool okI = hourAngleForZenith(90.0 + ishaAngle, deg2rad(lat), decl, Hi);
  double latRad = deg2rad(lat);
  double asrZenith = 90.0 - rad2deg(atan(1.0 / (1.0 + fabs(tan(latRad - decl)))));
  bool okA = hourAngleForZenith(asrZenith, latRad, decl, Ha);
  outTimes[0] = okF ? solarNoon - 4.0 * Hf : NAN;
  outTimes[1] = okSun ? solarNoon - 4.0 * Hsun : NAN;
  outTimes[2] = solarNoon;
  outTimes[3] = okA ? solarNoon + 4.0 * Ha : NAN;
  outTimes[4] = okSun ? solarNoon + 4.0 * Hsun : NAN;
  outTimes[5] = okI ? solarNoon + 4.0 * Hi : NAN;
  prefs.begin("adhancfg", true);
  int offsets[6] = { prefs.getInt("mq_off_fajr", 0), prefs.getInt("mq_off_sunrise", 0), prefs.getInt("mq_off_dhuhr", 0),
                     prefs.getInt("mq_off_asr", 0), prefs.getInt("mq_off_maghrib", 0), prefs.getInt("mq_off_isha", 0) };
  prefs.end();
  for (int i = 0; i < 6; i++) if (!isnan(outTimes[i])) outTimes[i] += offsets[i];
  return true;
}

// Priere suivante en epoch local : Mawaqit d'abord si frais (< 25 h), sinon calcul.
bool computeNextPrayer(time_t nowL, time_t &nextLocal, int &idx) {
  struct tm lt; localTm(nowL, lt);
  int y = lt.tm_year + 1900, m = lt.tm_mon + 1, d = lt.tm_mday;
  time_t midnight = civilToEpoch(y, m, d);
  time_t utcNow = time(nullptr);

  prefs.begin("adhancfg", true);
  String mq[6] = { prefs.getString("mq_fajr", ""), prefs.getString("mq_sunrise", ""), prefs.getString("mq_dhuhr", ""),
                   prefs.getString("mq_asr", ""), prefs.getString("mq_maghrib", ""), prefs.getString("mq_isha", "") };
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();
  unsigned long age = (mq_sync_ts > 0 && (unsigned long)utcNow >= mq_sync_ts) ? ((unsigned long)utcNow - mq_sync_ts) : 999999UL;
  bool mqValid = (mq[0].length() >= 5) && (mq[5].length() >= 5) && (age < 25UL * 3600UL);

  auto parseHHMM = [](const String &t, int &h, int &mn) -> bool {
    if (t.length() < 5) return false;
    h = t.substring(0, 2).toInt(); mn = t.substring(3, 5).toInt();
    return (h >= 0 && h < 24 && mn >= 0 && mn < 60);
  };

  if (mqValid) {
    for (int day = 0; day < 2; day++) {
      for (int i = 0; i < 6; i++) {
        int h, mn;
        if (!parseHHMM(mq[i], h, mn)) continue;
        time_t cand = midnight + day * 86400 + h * 3600 + mn * 60;
        if (cand > nowL + 5) { nextLocal = cand; idx = i + 1; return true; }
      }
    }
  }

  int tzDummy; String tzSrc;
  double times[6];
  for (int day = 0; day < 2; day++) {
    time_t dayL = nowL + day * 86400;
    struct tm dt; localTm(dayL, dt);
    if (!computePrayerTimesForDate(dt.tm_year + 1900, dt.tm_mon + 1, dt.tm_mday, times, tzDummy, tzSrc)) return false;
    time_t dayMidnight = civilToEpoch(dt.tm_year + 1900, dt.tm_mon + 1, dt.tm_mday);
    for (int i = 0; i < 6; i++) {
      if (isnan(times[i])) continue;
      time_t cand = dayMidnight + (time_t)round(times[i]) * 60;
      if (cand > nowL + 5) { nextLocal = cand; idx = i + 1; return true; }
    }
  }
  return false;
}

void scheduleNextPrayer() {
  if (!timeSet()) { scheduledPrayerIndex = 0; return; }
  time_t nextL; int idx;
  if (computeNextPrayer(nowLocal(), nextL, idx)) {
    scheduledPrayerIndex = idx;
    scheduledPrayerLocal = nextL;
    Serial.printf("Prochaine priere %d a %s (dans %ld s)\n", idx, fmtLocal(nextL).c_str(), (long)(nextL - nowLocal()));
  } else {
    scheduledPrayerIndex = 0;
    Serial.println("Pas de priere a programmer (position manquante ?)");
  }
}

// La priere est-elle activee ? Memes cles NVS que la V3 (ah_*_en) : l'ecran
// « Prieres » de l'app fonctionne sans changement.
static bool prayerEnabled(int prayerIndex) {
  if (prayerIndex == 2) return false;   // le lever n'est pas une priere
  prefs.begin("adhancfg", true);
  bool en = true;
  if (prayerIndex == 1) en = prefs.getBool("ah_fajr_en", true);
  else if (prayerIndex == 3) en = prefs.getBool("ah_dhuhr_en", true);
  else if (prayerIndex == 4) en = prefs.getBool("ah_asr_en", true);
  else if (prayerIndex == 5) en = prefs.getBool("ah_magh_en", true);
  else if (prayerIndex == 6) en = prefs.getBool("ah_isha_en", true);
  prefs.end();
  return en;
}

// ═══════════════════════════════════════════════════════════════════════════
// Le halo : scene « priere » pendant quelques minutes, puis retour
// ═══════════════════════════════════════════════════════════════════════════
void haloStart(int prayerIndex, int minutes) {
  if (haloPrayerIndex == 0) {
    haloPrevScenario = ledScenario;
    haloPrevCustom = ledCustomActive;
  }
  haloPrayerIndex = prayerIndex;
  haloUntilMs = millis() + (unsigned long)constrain(minutes, 1, 120) * 60000UL;
  ledScenario = SCENE_PRAYER;
  ledCustomActive = false;
  g_haloCarryIndex = prayerIndex;
  g_haloCarryUntilUtc = (int64_t)time(nullptr) + (int64_t)constrain(minutes, 1, 120) * 60;
  g_haloCarryMagic = HALO_CARRY_MAGIC;
  Serial.printf("[HALO] debut, priere %d, %d min\n", prayerIndex, minutes);
}

void haloStop() {
  if (haloPrayerIndex == 0) return;
  ledScenario = (haloPrevScenario >= 0) ? haloPrevScenario : DYN_HUE_INDEX;
  ledCustomActive = haloPrevCustom;
  haloPrayerIndex = 0;
  haloUntilMs = 0;
  haloPrevScenario = -1;
  g_haloCarryMagic = 0;
  Serial.println("[HALO] fin");
}

static int haloDurationMin() {
  prefs.begin("adhancfg", true);
  int mn = prefs.getInt("halo_min", 15);
  prefs.end();
  return constrain(mn, 1, 120);
}

// ═══════════════════════════════════════════════════════════════════════════
// Mawaqit : repris de la V3 (recherche de la mosquee, repli Aladhan)
// ═══════════════════════════════════════════════════════════════════════════
String addMinutesToTime(String timeStr, int offsetMinutes) {
  if (timeStr.length() < 5) return timeStr;
  int total = timeStr.substring(0, 2).toInt() * 60 + timeStr.substring(3, 5).toInt() + offsetMinutes;
  while (total < 0) total += 1440;
  while (total >= 1440) total -= 1440;
  char buffer[6];
  sprintf(buffer, "%02d:%02d", total / 60, total % 60);
  return String(buffer);
}

String urlEncode(const String &str) {
  String encoded = "";
  for (size_t i = 0; i < str.length(); i++) {
    char c = str.charAt(i);
    if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') encoded += c;
    else { char hex[4]; sprintf(hex, "%%%02X", (unsigned char)c); encoded += hex; }
  }
  return encoded;
}

static bool parseMawaqitTimesFromStream(Stream &stream, const String &uuid, const String &slug, String times[6]) {
  int braceCount = 0;
  String buffer = "";
  buffer.reserve(3000);
  unsigned long startTime = millis();
  while (millis() - startTime < 20000) {
    if (_wdtArmed) esp_task_wdt_reset();
    if (!stream.available()) { delay(10); continue; }
    char c = stream.read();
    if (braceCount == 0) {
      if (c == '{') { braceCount = 1; buffer = "{"; }
    } else {
      buffer += c;
      if (c == '{') braceCount++;
      else if (c == '}') {
        braceCount--;
        if (braceCount == 0) {
          bool match = (uuid.length() > 0 && buffer.indexOf(uuid) >= 0) || (slug.length() > 0 && buffer.indexOf(slug) >= 0);
          if (match) {
            int timesPos = buffer.indexOf("\"times\"");
            if (timesPos >= 0) {
              int curPos = buffer.indexOf("[", timesPos);
              bool allParsed = true;
              for (int i = 0; i < 6; i++) {
                int q1 = buffer.indexOf('"', curPos + 1);
                int q2 = buffer.indexOf('"', q1 + 1);
                if (q1 >= 0 && q2 > q1) {
                  times[i] = buffer.substring(q1 + 1, q2);
                  if (times[i].length() > 5 && times[i].charAt(5) == ':') times[i] = times[i].substring(0, 5);
                  curPos = q2;
                } else allParsed = false;
              }
              if (allParsed) return true;
            }
          }
          buffer = "";
        }
      }
      if (buffer.length() > 4000) { buffer = ""; braceCount = 0; }
    }
  }
  return false;
}

bool performMawaqitSync(String &errorMsg) {
  prefs.begin("adhancfg", true);
  String uuid = prefs.getString("mq_uuid", "");
  String slug = prefs.getString("mq_slug", "");
  String name = prefs.getString("mq_name", "");
  prefs.end();
  if (uuid.length() == 0 && slug.length() == 0) { errorMsg = "No mosque configured"; return false; }
  if (!timeSet()) { errorMsg = "time not set"; return false; }

  double lat = 0.0, lon = 0.0, acc = 0.0;
  bool hasLocation = loadStoredLocation(lat, lon, acc);
  String urls[3] = { "", "", "" };
  int attempts = 0;
  if (slug.length() > 0) urls[attempts++] = "/api/2.0/mosque/search?word=" + urlEncode(slug);
  if (name.length() > 0 && attempts < 3) urls[attempts++] = "/api/2.0/mosque/search?word=" + urlEncode(name);
  if (hasLocation && attempts < 3) urls[attempts++] = "/api/2.0/mosque/search?lat=" + String(lat, 6) + "&lon=" + String(lon, 6) + "&distance=20";

  const char *altNames[6] = { "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha" };
  String times[6];
  bool anyValid = false;
  for (int attempt = 0; attempt < attempts && !anyValid; attempt++) {
    HTTPClient http;
    WiFiClientSecure client;
    client.setInsecure();
    String url = "https://mawaqit.net" + urls[attempt];
    Serial.printf("Mawaqit [%d/%d] %s\n", attempt + 1, attempts, url.c_str());
    http.begin(client, url);
    http.addHeader("User-Agent", "AdhanBox/1.0");
    http.addHeader("Accept", "application/json");
    http.setConnectTimeout(4000);
    http.setTimeout(6000);
    if (_wdtArmed) esp_task_wdt_reset();
    int httpCode = http.GET();
    if (_wdtArmed) esp_task_wdt_reset();
    if (httpCode == 200) {
      WiFiClient *s = http.getStreamPtr();
      if (s && parseMawaqitTimesFromStream(*s, uuid, slug, times)) anyValid = true;
    } else Serial.printf("Mawaqit HTTP %d\n", httpCode);
    http.end();
    if (!anyValid) for (int i = 0; i < 6; i++) times[i] = "";
  }
  bool mawaqitSyncSuccess = anyValid;

  if (!anyValid) {
    Serial.println("Mawaqit : rien de valide, repli Aladhan par coordonnees");
    if (!hasLocation) { errorMsg = "No valid times and no location for fallback"; return false; }
    HTTPClient http;
    String url = "https://api.aladhan.com/v1/timings?latitude=" + String(lat, 6) + "&longitude=" + String(lon, 6) + "&method=12&school=1";
    http.begin(url);
    http.setConnectTimeout(4000);
    http.setTimeout(6000);
    if (_wdtArmed) esp_task_wdt_reset();
    int httpCode = http.GET();
    if (_wdtArmed) esp_task_wdt_reset();
    if (httpCode != 200) { http.end(); errorMsg = "Fallback request failed"; return false; }
    String body = http.getString();
    http.end();
    for (int i = 0; i < 6; i++) {
      int pos = body.indexOf(String("\"") + altNames[i] + "\"");
      if (pos < 0) continue;
      int colonPos = body.indexOf(":", pos);
      int q1 = body.indexOf('"', colonPos + 1);
      int q2 = body.indexOf('"', q1 + 1);
      if (q1 >= 0 && q2 > q1) {
        times[i] = body.substring(q1 + 1, q2);
        if (times[i].length() > 5 && times[i].charAt(5) == ':') times[i] = times[i].substring(0, 5);
        anyValid = true;
      }
    }
    if (!anyValid) { errorMsg = "No valid times in response"; return false; }
  }

  prefs.begin("adhancfg", true);
  int offsets[6] = { prefs.getInt("mq_off_fajr", 0), prefs.getInt("mq_off_sunrise", 0), prefs.getInt("mq_off_dhuhr", 0),
                     prefs.getInt("mq_off_asr", 0), prefs.getInt("mq_off_maghrib", 0), prefs.getInt("mq_off_isha", 0) };
  prefs.end();
  for (int i = 0; i < 6; i++) if (offsets[i] != 0 && times[i].length() >= 5) times[i] = addMinutesToTime(times[i], offsets[i]);

  prefs.begin("adhancfg", false);
  prefs.putString("mq_fajr", times[0]);
  prefs.putString("mq_sunrise", times[1]);
  prefs.putString("mq_dhuhr", times[2]);
  prefs.putString("mq_asr", times[3]);
  prefs.putString("mq_maghrib", times[4]);
  prefs.putString("mq_isha", times[5]);
  prefs.putULong("mq_sync_ts", (unsigned long)time(nullptr));
  prefs.end();
  Serial.printf("Horaires synchronises : Fajr %s Dhuhr %s Maghrib %s Isha %s\n", times[0].c_str(), times[2].c_str(), times[4].c_str(), times[5].c_str());
  if (!mawaqitSyncSuccess) { errorMsg = "Mawaqit sync failed (using calculated times fallback)"; return false; }
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Capteur de lumiere : mode nuit automatique
// ═══════════════════════════════════════════════════════════════════════════
// Toutes les 500 ms : moyenne glissante de l'ADC. Nuit si la moyenne passe
// sous le seuil, jour si elle repasse au-dessus de 1,3 x le seuil (hysteresis).
// « Capteur absent » (als_present = false, ou Q1 non pose : R8 tire IO4 a 0 V)
// : mode nuit jamais actif.
static void alsTick() {
  static unsigned long lastAls = 0;
  unsigned long now = millis();
  if (now - lastAls < 500) return;
  lastAls = now;
  int raw = analogRead(ALS_PIN);
  alsEma = (alsEma < 0) ? raw : (alsEma * 0.8f + raw * 0.2f);
  prefs.begin("adhancfg", true);
  bool present = prefs.getBool("als_present", true);
  bool autoNight = prefs.getBool("als_auto", true);
  int thresh = prefs.getInt("als_thresh", 400);
  nightPct = prefs.getInt("als_night_pct", 15);
  prefs.end();
  if (!present || !autoNight) { nightMode = false; return; }
  if (!nightMode && alsEma < thresh) { nightMode = true; Serial.printf("[ALS] nuit (%.0f < %d)\n", alsEma, thresh); }
  else if (nightMode && alsEma > thresh * 1.3f) { nightMode = false; Serial.printf("[ALS] jour (%.0f)\n", alsEma); }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bouton utilisateur (IO3, actif bas)
// ═══════════════════════════════════════════════════════════════════════════
// Appui court (< 700 ms) : arrete le halo en cours, sinon allume / eteint.
// Appui long (>= 700 ms)  : scene suivante.
// Appui 5 s               : redemarre en mode appairage BLE.
static void buttonTick() {
  static bool wasDown = false;
  static unsigned long downAt = 0;
  static bool longDone = false;
  static unsigned long lastEdge = 0;
  bool down = (digitalRead(BTN_PIN) == LOW);
  unsigned long now = millis();
  if (down != wasDown && now - lastEdge < 40) return;   // anti-rebond
  if (down && !wasDown) { downAt = now; longDone = false; lastEdge = now; }
  if (down && !longDone && now - downAt >= 5000) {
    longDone = true;
    Serial.println("[BTN] 5 s : redemarrage en appairage");
    g_pairBootMagic = PAIR_BOOT_MAGIC;
    clearStrip();
    delay(200);
    ESP.restart();
  }
  if (!down && wasDown) {
    lastEdge = now;
    unsigned long held = now - downAt;
    if (held >= 700) {
      ledCustomActive = false;
      if (haloPrayerIndex) haloStop();
      do { ledScenario = (ledScenario + 1) % TOTAL_SCENES; } while (ledScenario == BLINK_INDEX || ledScenario == SCENE_PRAYER);
      prefs.begin("adhancfg", false);
      prefs.putInt("led_scenario", ledScenario);
      prefs.putBool("led_custom", false);
      prefs.end();
      Serial.printf("[BTN] long : scene %d\n", ledScenario);
    } else if (held >= 30) {
      if (haloPrayerIndex) {
        haloStop();
        Serial.println("[BTN] court : halo arrete");
      } else if (ledScenario == 0 && !ledCustomActive) {
        prefs.begin("adhancfg", true);
        ledScenario = prefs.getInt("led_last_on", DYN_HUE_INDEX);
        ledCustomActive = prefs.getBool("led_custom", false);
        prefs.end();
        if (ledScenario == 0) ledScenario = DYN_HUE_INDEX;
        Serial.println("[BTN] court : allume");
      } else {
        prefs.begin("adhancfg", false);
        prefs.putInt("led_last_on", ledCustomActive ? 1 : ledScenario);
        prefs.end();
        ledScenario = 0;
        ledCustomActive = false;
        Serial.println("[BTN] court : eteint");
      }
      prefs.begin("adhancfg", false);
      prefs.putInt("led_scenario", ledScenario);
      prefs.putBool("led_custom", ledCustomActive);
      prefs.end();
    }
  }
  wasDown = down;
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : aides
// ═══════════════════════════════════════════════════════════════════════════
static String getRequestBody() {
  if (server.hasArg("plain")) return server.arg("plain");
  if (server.args() > 0) return server.arg(0);
  return "";
}

static double parseJsonValue(const String &s, const char *key) {
  int k = s.indexOf(String('"') + String(key) + String('"'));
  if (k < 0) k = s.indexOf(String(key));
  if (k < 0) return NAN;
  int colon = s.indexOf(':', k);
  if (colon < 0) return NAN;
  int start = colon + 1;
  while (start < (int)s.length() && (s[start] == ' ' || s[start] == '\"')) start++;
  int end = start;
  while (end < (int)s.length() && ((s[end] >= '0' && s[end] <= '9') || s[end] == '.' || s[end] == '-' || s[end] == '+' || s[end] == 'e' || s[end] == 'E')) end++;
  return s.substring(start, end).toFloat();
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

static bool parseJsonBool(const String &src, const char *key, bool defVal) {
  int idx = src.indexOf(String("\"") + key + "\"");
  if (idx < 0) return defVal;
  idx = src.indexOf(':', idx);
  if (idx < 0) return defVal;
  idx++;
  while (idx < (int)src.length() && (src[idx] == ' ' || src[idx] == '\t')) idx++;
  if (src.substring(idx, idx + 4) == "true") return true;
  if (src.substring(idx, idx + 5) == "false") return false;
  return defVal;
}

static String deviceIdHex() {
  char id[13];
  snprintf(id, sizeof(id), "%012llX", (unsigned long long)ESP.getEfuseMac());
  return String(id);
}

// Jeton requis sur tout ce qui modifie l'appareil. Pas d'auth en mode point
// d'acces (reseau isole) ni tant que le jeton n'existe pas.
bool requireApiKey() {
  if (_apiToken.length() == 0) return true;
  if (apRunning) return true;
  String key = server.header("X-API-Key");
  if (key.length() == 0) key = server.arg("token");
  if (key == _apiToken) return true;
  server.send(401, "application/json", "{\"error\":\"Unauthorized — missing or invalid X-API-Key\"}");
  return false;
}

static bool requirePost() {
  if (server.method() != HTTP_POST) { server.send(405, "text/plain", "Method not allowed"); return false; }
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : page de depannage (memes boutons que la V3, sans le test audio)
// ═══════════════════════════════════════════════════════════════════════════
const char index_html[] PROGMEM = R"HTML(
<!DOCTYPE html><html lang="fr"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Halo — Dépannage</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,system-ui,sans-serif;background:#0f1512;color:#eaf2ed;padding:18px;max-width:520px;margin:0 auto;line-height:1.5}
  header{text-align:center;margin:10px 0 22px}
  header h1{font-size:20px;margin-top:2px}
  header .info{font-size:12.5px;color:#9fb0a7;margin-top:8px}
  .card{background:#16201b;border:1px solid #26332c;border-radius:16px;padding:18px;margin-bottom:16px}
  .card h2{font-size:15px;margin-bottom:6px}
  .card p.hint{font-size:13px;color:#9fb0a7;margin-bottom:12px}
  button{display:block;width:100%;border:none;border-radius:12px;padding:16px;font-size:16px;font-weight:600;cursor:pointer;color:#fff}
  .btn-pair{background:#3B82F6;font-size:18px;padding:20px}
  .btn-emerald{background:#12A67B}
  .btn-ghost{background:transparent;border:1px solid #26332c;color:#eaf2ed;font-weight:500}
  .btn-row{display:flex;gap:10px;margin-top:10px}
  .msg{font-size:13px;color:#9fb0a7;margin-top:10px;min-height:16px}
  input{width:100%;padding:14px;border-radius:12px;border:1px solid #26332c;background:#0f1512;color:#fff;font-size:16px;margin-top:8px}
  .net{display:flex;justify-content:space-between;padding:12px 14px;border:1px solid #26332c;border-radius:10px;margin-top:8px;cursor:pointer}
  .hidden{display:none}
  a.update{display:block;text-align:center;color:#EBD9A8;font-size:14px;margin-top:12px}
</style></head><body>
<header><h1>Halo — Dépannage</h1><div class="info" id="devInfo">Chargement…</div></header>
<div class="card"><h2>📱 Connecter à l'application</h2>
<p class="hint">Passe le Halo en mode appairage pour l'ajouter dans l'app AdhanBox.</p>
<button class="btn-pair" id="pairBtn">Appairer avec l'app (Bluetooth)</button><div class="msg" id="pairMsg"></div></div>
<div class="card"><h2>📶 Réseau Wi-Fi</h2>
<button class="btn-ghost" id="scanBtn">Rechercher les réseaux</button><div id="netList"></div>
<div id="wifiForm" class="hidden"><input id="ssid" type="text" readonly><input id="pass" type="password" placeholder="Mot de passe Wi-Fi">
<div class="btn-row"><button class="btn-ghost" id="wifiCancel">Annuler</button><button class="btn-emerald" id="wifiConnect">Se connecter</button></div></div>
<div class="msg" id="wifiMsg"></div></div>
<div class="card"><h2>🔧 Vérifications</h2>
<div class="btn-row"><button class="btn-emerald" id="testBtn">◉ Tester le halo (1 min)</button><button class="btn-ghost" id="stopBtn">■ Arrêter</button></div>
<a class="update" href="/update">Mise à jour du logiciel (firmware) →</a><div class="msg" id="testMsg"></div></div>
<script>
function $(id){return document.getElementById(id);}
fetch('/api/device/info').then(r=>r.json()).then(j=>{$('devInfo').textContent='Version '+(j.version||'?')+' · '+(j.hostname||location.hostname);}).catch(()=>{$('devInfo').textContent=location.hostname;});
$('pairBtn').onclick=function(){var b=this;$('pairMsg').textContent='Démarrage du Bluetooth…';b.disabled=true;
 fetch('/api/pair').then(r=>r.json()).then(()=>{$('pairMsg').textContent="Bluetooth actif (~5 min). Ouvrez l'app → Réglages → Associer un autre appareil.";}).catch(()=>{$('pairMsg').textContent='Erreur. Réessayez.';b.disabled=false;});};
$('scanBtn').onclick=function(){var b=this;b.textContent='Recherche…';b.disabled=true;$('netList').innerHTML='';$('wifiMsg').textContent='';
 fetch('/scan_wifi').then(r=>r.json()).then(list=>{b.textContent='Rechercher les réseaux';b.disabled=false;list.sort((a,c)=>c.rssi-a.rssi);var seen={};
  list.forEach(net=>{if(!net.ssid||seen[net.ssid])return;seen[net.ssid]=1;var d=document.createElement('div');d.className='net';d.textContent=net.ssid+(net.secure?' 🔒':'');
   d.onclick=function(){$('ssid').value=net.ssid;$('pass').value='';$('wifiForm').classList.remove('hidden');$('pass').focus();};$('netList').appendChild(d);});
  if(!$('netList').children.length)$('wifiMsg').textContent='Aucun réseau trouvé.';}).catch(()=>{b.textContent='Rechercher les réseaux';b.disabled=false;$('wifiMsg').textContent='Erreur de scan.';});};
$('wifiCancel').onclick=function(){$('wifiForm').classList.add('hidden');};
$('wifiConnect').onclick=function(){var b=this;var ssid=$('ssid').value.trim();var pass=$('pass').value||'';if(!ssid)return;$('wifiMsg').textContent='Connexion à '+ssid+'…';b.disabled=true;
 fetch('/connect_wifi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ssid:ssid,pass:pass})}).then(r=>r.text()).then(t=>{b.disabled=false;
  if(t&&(t.indexOf('connect')>=0)){$('wifiMsg').textContent='Connexion lancée, patientez 20 s.';$('wifiForm').classList.add('hidden');}else{$('wifiMsg').textContent='❌ Échec : '+t;}}).catch(()=>{b.disabled=false;$('wifiMsg').textContent='Erreur de connexion.';});};
$('testBtn').onclick=function(){$('testMsg').textContent='Halo de test…';fetch('/api/halo/test?minutes=1',{method:'POST'}).catch(()=>{});};
$('stopBtn').onclick=function(){$('testMsg').textContent='';fetch('/api/halo/stop',{method:'POST'}).catch(()=>{});};
</script></body></html>
)HTML";

void handleRoot() {
  server.sendHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
  server.send_P(200, "text/html", index_html);
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : position, fuseau, heure
// ═══════════════════════════════════════════════════════════════════════════
void handleSetLocation() {
  if (!requireApiKey() || !requirePost()) return;
  String body = getRequestBody();
  double lat = parseJsonValue(body, "lat");
  double lon = parseJsonValue(body, "lon");
  double acc = parseJsonValue(body, "accuracy");
  unsigned long ts = (unsigned long)parseJsonValue(body, "timestamp");
  if (isnan(lat) || isnan(lon)) { server.send(400, "text/plain", "Invalid payload"); return; }
  prefs.begin("adhancfg", false);
  prefs.putString("lat", String(lat, 6));
  prefs.putString("lon", String(lon, 6));
  prefs.putString("acc", String(acc));
  prefs.putULong("ts", ts);
  prefs.end();
  scheduleNextPrayer();
  server.send(200, "text/plain", "Position enregistrée");
}

void handleSetTZ() {
  if (!requirePost() || !requireApiKey()) return;
  double tz = parseJsonValue(getRequestBody(), "tz_min");
  if (isnan(tz)) { server.send(400, "text/plain", "Invalid payload"); return; }
  prefs.begin("adhancfg", false);
  prefs.putInt("tz_offset_min", (int)tz);
  prefs.end();
  scheduleNextPrayer();
  server.send(200, "text/plain", "Timezone offset saved");
}

void handleShowLoc() {
  double lat, lon, acc;
  if (loadStoredLocation(lat, lon, acc)) {
    char buf[128];
    snprintf(buf, sizeof(buf), "{\"lat\":%.6f,\"lon\":%.6f,\"acc\":%.1f}", lat, lon, acc);
    server.send(200, "application/json", String(buf));
  } else server.send(200, "application/json", "{}");
}

// /rtc_time et /show_time de la V3 : l'heure locale, ou "RTC not present" si
// le NTP n'a pas encore repondu (meme texte que la V3 sans RTC : l'app sait).
void handleShowTime() {
  if (!timeSet()) { server.send(200, "text/plain", "RTC not present"); return; }
  String out = fmtLocal(nowLocal());
  int tz = tzOffsetMinStored();
  if (tz != 0x7fffffff) { char tzb[32]; snprintf(tzb, sizeof(tzb), " (UTC%+d)", tz / 60); out += tzb; }
  server.send(200, "text/plain", out);
}

// L'app envoie l'heure locale du telephone a l'appairage puis toutes les
// 10 min (POST /set_rtc_manual {"date":"YYYY-MM-DD","time":"HH:MM:SS"}). Sans
// RTC ni NTP (Wi-Fi sans internet), c'est notre seule horloge : on la prend
// tant que le NTP n'a pas parle. Une fois le NTP passe, on ne touche plus a
// l'heure systeme (le SNTP la maintient).
void handleSetRtcManual() {
  if (!requireApiKey() || !requirePost()) return;
  String body = getRequestBody();
  String dateStr = parseJsonString(body, "date"), timeStr = parseJsonString(body, "time");
  if (dateStr.length() < 10) { server.send(400, "text/plain", "Missing date"); return; }
  int y = dateStr.substring(0, 4).toInt(), m = dateStr.substring(5, 7).toInt(), d = dateStr.substring(8, 10).toInt();
  int hh = 0, mm = 0, ss = 0;
  if (timeStr.length() >= 5) { hh = timeStr.substring(0, 2).toInt(); mm = timeStr.substring(3, 5).toInt(); if (timeStr.length() >= 8) ss = timeStr.substring(6, 8).toInt(); }
  if (y < 2024 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) { server.send(400, "text/plain", "Invalid date/time"); return; }
  if (!timeSet() || timeApprox()) {
    time_t local = civilToEpoch(y, m, d) + hh * 3600 + mm * 60 + ss;
    struct timeval tv = { .tv_sec = local - (time_t)tzOffsetMin() * 60, .tv_usec = 0 };
    settimeofday(&tv, nullptr);
    _timeFromPhone = true;
    _timeCarried = false;
    scheduleNextPrayer();
    Serial.printf("Heure prise du telephone : %s\n", fmtLocal(nowLocal()).c_str());
  }
  char buf[64];
  snprintf(buf, sizeof(buf), "RTC set to %04d-%02d-%02d %02d:%02d:%02d", y, m, d, hh, mm, ss);
  server.send(200, "text/plain", String(buf));
}

// GET /api/time -> {"time":"YYYY-MM-DD HH:MM:SS","tz_min":60,"ok":true,"source":"ntp"|"phone"|"none"}
void handleApiTime() {
  char buf[160];
  snprintf(buf, sizeof(buf), "{\"time\":\"%s\",\"tz_min\":%d,\"ok\":%s,\"source\":\"%s\"}",
           timeSet() ? fmtLocal(nowLocal()).c_str() : "", tzOffsetMin(), timeSet() ? "true" : "false",
           !timeSet() ? "none" : (_timeFromPhone ? "phone" : (_timeCarried ? "carry" : "ntp")));
  server.send(200, "application/json", buf);
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : LED
// ═══════════════════════════════════════════════════════════════════════════
void handleSetBrightness() {
  if (!requireApiKey() || !requirePost()) return;
  double b = parseJsonValue(getRequestBody(), "bright");
  if (isnan(b)) { server.send(400, "text/plain", "Invalid payload"); return; }
  ledBrightness = constrain((int)round(b), 0, 100);
  prefs.begin("adhancfg", false);
  prefs.putInt("brightness", ledBrightness);
  prefs.end();
  server.send(200, "text/plain", "OK");
}

void handleGetBrightness() {
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"bright\":%d}", ledBrightness);
  server.send(200, "application/json", String(buf));
}

static void applyScenario(int scenario, bool persist) {
  if (haloPrayerIndex) haloStop();   // une commande de l'app met fin au halo
  ledScenario = scenario;
  ledCustomActive = false;
  if (scenario == 0) stripSetAll(0, 0, 0);
  if (persist) {
    prefs.begin("adhancfg", false);
    prefs.putInt("led_scenario", ledScenario);
    prefs.putBool("led_custom", false);
    if (scenario != 0) prefs.putInt("led_last_on", scenario);
    prefs.end();
  }
}

void handleSetLedScenario() {
  if (!requireApiKey() || !requirePost()) return;
  double sc = parseJsonValue(getRequestBody(), "scenario");
  if (isnan(sc)) { server.send(400, "text/plain", "Invalid payload"); return; }
  int scenario = (int)round(sc);
  if (scenario < 0 || scenario >= TOTAL_SCENES) { server.send(400, "text/plain", "Invalid scenario"); return; }
  applyScenario(scenario, true);
  server.send(200, "application/json", String("{\"scenario\":") + scenario + "}");
}

void handleSetLed() {
  if (!requireApiKey()) return;
  String s = server.arg("scene");
  if (s.length() == 0) { server.send(400, "text/plain", "Missing scene"); return; }
  int sc = s.toInt();
  if (sc < 0 || sc >= TOTAL_SCENES) { server.send(400, "text/plain", "Invalid scene"); return; }
  String pv = server.arg("preview");
  bool isPreview = (pv == "1" || pv.equalsIgnoreCase("true"));
  applyScenario(sc, !isPreview);
  server.send(200, "text/plain", String("OK: ") + sc + (isPreview ? " (preview)" : ""));
}

void handleSetLedRgb() {
  if (!requireApiKey() || !requirePost()) return;
  String body = getRequestBody();
  double dr = parseJsonValue(body, "r"), dg = parseJsonValue(body, "g"), db = parseJsonValue(body, "b");
  if (isnan(dr) || isnan(dg) || isnan(db)) { server.send(400, "text/plain", "Invalid payload"); return; }
  if (haloPrayerIndex) haloStop();
  ledCustomR = (uint8_t)constrain((int)round(dr), 0, 255);
  ledCustomG = (uint8_t)constrain((int)round(dg), 0, 255);
  ledCustomB = (uint8_t)constrain((int)round(db), 0, 255);
  ledCustomActive = true;
  if (ledScenario == 0) ledScenario = 1;
  // La roue chromatique envoie des dizaines de POST/s : rendu par la boucle
  // seulement, sauvegarde NVS differee (voir ledFlushSave).
  _ledDirty = true;
  _ledDirtyAt = millis();
  server.send(200, "application/json", String("{\"r\":") + ledCustomR + ",\"g\":" + ledCustomG + ",\"b\":" + ledCustomB + "}");
}

void handleLedTest() {
  if (ledTestUntil == 0) prevLedScenario = ledScenario;
  ledTestUntil = millis() + 5000UL;
  server.send(200, "text/plain", "LED test started for 5s");
}

void handleLedOff() {
  if (!requireApiKey()) return;
  applyScenario(0, true);
  clearStrip();
  server.send(200, "text/plain", "LEDs off");
}

void handleLedStatus() {
  char buf[200];
  bool on = ledCustomActive || (ledScenario != 0);
  snprintf(buf, sizeof(buf),
           "{\"on\":%s,\"scenario\":%d,\"brightness\":%d,\"custom\":%s,\"r\":%d,\"g\":%d,\"b\":%d,\"night\":%s,\"halo\":%s}",
           on ? "true" : "false", ledScenario, ledBrightness, ledCustomActive ? "true" : "false",
           (int)ledCustomR, (int)ledCustomG, (int)ledCustomB, nightMode ? "true" : "false", haloPrayerIndex ? "true" : "false");
  server.send(200, "application/json", String(buf));
}

static void ledFlushSave() {
  if (_ledDirty && (millis() - _ledDirtyAt) > 600) {
    _ledDirty = false;
    prefs.begin("adhancfg", false);
    prefs.putBool("led_custom", true);
    prefs.putInt("led_cr", ledCustomR);
    prefs.putInt("led_cg", ledCustomG);
    prefs.putInt("led_cb", ledCustomB);
    prefs.end();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : Wi-Fi
// ═══════════════════════════════════════════════════════════════════════════
void handleConnectWifi() {
  if (!requireApiKey() || !requirePost()) return;
  String body = getRequestBody();
  String ssid = parseJsonString(body, "ssid");
  String pass = parseJsonString(body, "pass");
  if (ssid.length() == 0) { server.send(400, "text/plain", "Missing SSID"); return; }
  if (WiFi.status() == WL_CONNECTED && WiFi.SSID() == ssid) {
    server.send(200, "application/json", "{\"status\":\"connected\",\"ip\":\"" + WiFi.localIP().toString() + "\",\"ssid\":\"" + ssid + "\"}");
    return;
  }
  wifiConnectSSID = ssid;
  wifiConnectPass = pass;
  wifiConnectState = WCS_CONNECTING;
  wifiConnectStart = millis();
  WiFi.disconnect(true);
  delay(100);
  WiFi.mode(apRunning ? WIFI_AP_STA : WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(ssid.c_str(), pass.c_str());
  server.send(202, "application/json", "{\"status\":\"connecting\"}");
}

void handleWifiStatus() {
  String status, ip = "", ssid = "";
  switch (wifiConnectState) {
    case WCS_CONNECTING: status = "connecting"; break;
    case WCS_CONNECTED: status = "connected"; ip = WiFi.localIP().toString(); ssid = WiFi.SSID(); break;
    case WCS_FAILED: status = "failed"; break;
    default:
      if (WiFi.status() == WL_CONNECTED) { status = "connected"; ip = WiFi.localIP().toString(); ssid = WiFi.SSID(); }
      else status = "idle";
  }
  char buf[256];
  snprintf(buf, sizeof(buf), "{\"status\":\"%s\",\"ip\":\"%s\",\"ssid\":\"%s\"}", status.c_str(), ip.c_str(), ssid.c_str());
  server.send(200, "application/json", buf);
}

void handleScanWifi() {
  int n = WiFi.scanNetworks();
  String out = "[";
  for (int i = 0; i < n; i++) {
    String ss = WiFi.SSID(i);
    ss.replace("\"", "\\\"");
    out += "{\"ssid\":\"" + ss + "\",\"rssi\":" + String(WiFi.RSSI(i)) + ",\"secure\":" + String(WiFi.encryptionType(i) != WIFI_AUTH_OPEN ? 1 : 0) + "}";
    if (i < n - 1) out += ",";
  }
  out += "]";
  server.send(200, "application/json", out);
}

void handleDisconnectWifi() {
  if (!requireApiKey()) return;
  WiFi.disconnect(true);
  WiFi.mode(WIFI_AP);
  server.send(200, "text/plain", "WiFi disconnected");
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : Mawaqit, methode de calcul, prieres
// ═══════════════════════════════════════════════════════════════════════════
void handleMawaqitGetOffsets() {
  prefs.begin("adhancfg", true);
  String json = "{\"fajr\":" + String(prefs.getInt("mq_off_fajr", 0)) + ",\"sunrise\":" + String(prefs.getInt("mq_off_sunrise", 0))
              + ",\"dhuhr\":" + String(prefs.getInt("mq_off_dhuhr", 0)) + ",\"asr\":" + String(prefs.getInt("mq_off_asr", 0))
              + ",\"maghrib\":" + String(prefs.getInt("mq_off_maghrib", 0)) + ",\"isha\":" + String(prefs.getInt("mq_off_isha", 0)) + "}";
  prefs.end();
  server.send(200, "application/json", json);
}

void handleMawaqitSetOffsets() {
  if (!requirePost()) return;
  String body = getRequestBody();
  const char *keys[6] = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" };
  const char *offKeys[6] = { "mq_off_fajr", "mq_off_sunrise", "mq_off_dhuhr", "mq_off_asr", "mq_off_maghrib", "mq_off_isha" };
  const char *mqKeys[6] = { "mq_fajr", "mq_sunrise", "mq_dhuhr", "mq_asr", "mq_maghrib", "mq_isha" };
  int newOff[6], oldOff[6];
  String mqTimes[6];
  prefs.begin("adhancfg", true);
  for (int i = 0; i < 6; i++) { oldOff[i] = prefs.getInt(offKeys[i], 0); mqTimes[i] = prefs.getString(mqKeys[i], ""); }
  prefs.end();
  for (int i = 0; i < 6; i++) {
    double v = parseJsonValue(body, keys[i]);
    newOff[i] = constrain(isnan(v) ? 0 : (int)round(v), -30, 30);
  }
  prefs.begin("adhancfg", false);
  for (int i = 0; i < 6; i++) {
    prefs.putInt(offKeys[i], newOff[i]);
    // Les horaires Mawaqit memorises portent deja l'ancien decalage : on le
    // retire et on applique le nouveau.
    if (mqTimes[i].length() >= 5 && oldOff[i] != newOff[i]) prefs.putString(mqKeys[i], addMinutesToTime(addMinutesToTime(mqTimes[i], -oldOff[i]), newOff[i]));
  }
  prefs.end();
  scheduleNextPrayer();
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleMawaqitConfig() {
  if (!requirePost() || !requireApiKey()) return;
  String body = getRequestBody();
  String uuid = parseJsonString(body, "mosque_uuid");
  if (uuid.length() == 0) uuid = parseJsonString(body, "uuid");
  if (uuid.length() == 0) { server.send(400, "application/json", "{\"error\":\"Missing mosque_uuid\"}"); return; }
  prefs.begin("adhancfg", false);
  prefs.putString("mq_uuid", uuid);
  prefs.putString("mq_slug", parseJsonString(body, "slug"));
  prefs.putString("mq_name", parseJsonString(body, "name"));
  prefs.putString("mq_city", parseJsonString(body, "city"));
  prefs.putULong("mq_ts", millis());
  prefs.end();
  server.send(200, "application/json", "{\"ok\":true,\"message\":\"mosque saved\"}");
}

void handleMawaqitSync() {
  if (!requirePost() || !requireApiKey()) return;
  String err;
  if (performMawaqitSync(err)) { scheduleNextPrayer(); server.send(200, "application/json", "{\"ok\":true,\"message\":\"times synced\"}"); }
  else server.send(500, "application/json", "{\"error\":\"" + err + "\"}");
}

void handleMawaqitDebug() {
  prefs.begin("adhancfg", true);
  String json = "{\"uuid\":\"" + prefs.getString("mq_uuid", "") + "\",\"times\":{"
                "\"fajr\":\"" + prefs.getString("mq_fajr", "") + "\",\"sunrise\":\"" + prefs.getString("mq_sunrise", "") + "\","
                "\"dhuhr\":\"" + prefs.getString("mq_dhuhr", "") + "\",\"asr\":\"" + prefs.getString("mq_asr", "") + "\","
                "\"maghrib\":\"" + prefs.getString("mq_maghrib", "") + "\",\"isha\":\"" + prefs.getString("mq_isha", "") + "\"},";
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();
  json += "\"sync_ts\":" + String(mq_sync_ts) + ",";
  if (timeSet()) {
    unsigned long nowE = (unsigned long)time(nullptr);
    unsigned long age = (mq_sync_ts > 0 && nowE >= mq_sync_ts) ? (nowE - mq_sync_ts) : 999999UL;
    json += "\"now_epoch\":" + String(nowE) + ",\"age_seconds\":" + String(age) + ",\"age_hours\":" + String(age / 3600.0, 2) + ",\"fresh\":" + String(age < 25UL * 3600UL ? "true" : "false");
  } else json += "\"rtc_error\":true";
  json += "}";
  server.send(200, "application/json", json);
}

void handleCalculationConfig() {
  if (server.method() == HTTP_GET) {
    double fa, ia; String mn;
    getCalculationAngles(fa, ia, mn);
    double lat = 0, lon = 0, acc = 0;
    bool hasLoc = loadStoredLocation(lat, lon, acc);
    server.send(200, "application/json", "{\"method\":\"" + mn + "\",\"fajr_angle\":" + String(fa, 1) + ",\"isha_angle\":" + String(ia, 1)
                + ",\"school\":\"standard\",\"lat\":" + (hasLoc ? String(lat, 6) : String("null")) + ",\"lon\":" + (hasLoc ? String(lon, 6) : String("null")) + "}");
    return;
  }
  if (!requirePost()) return;
  String body = getRequestBody();
  String method = parseJsonString(body, "method");
  if (method.length() == 0) method = "mwl";
  method.toLowerCase();
  if (!(method == "mwl" || method == "isna" || method == "uoif" || method == "egypt" || method == "karachi" || method == "custom")) {
    server.send(400, "application/json", "{\"error\":\"Invalid method\"}");
    return;
  }
  double fa = parseJsonValue(body, "fajr_angle"), ia = parseJsonValue(body, "isha_angle");
  if (isnan(fa) || fa < 10.0 || fa > 25.0) fa = 18.0;
  if (isnan(ia) || ia < 10.0 || ia > 25.0) ia = 17.0;
  prefs.begin("adhancfg", false);
  prefs.putString("calc_method", method);
  prefs.putFloat("calc_fajr_angle", (float)fa);
  prefs.putFloat("calc_isha_angle", (float)ia);
  prefs.end();
  scheduleNextPrayer();
  server.send(200, "application/json", "{\"ok\":true,\"method\":\"" + method + "\",\"fajr_angle\":" + String(fa, 1) + ",\"isha_angle\":" + String(ia, 1) + "}");
}

// /api/adhan/config : meme forme que la V3 pour l'ecran « Prieres » de l'app.
// Seuls les *_enabled comptent ici ; pistes, duaa et volumes sont rendus a
// des valeurs neutres et ignores a l'ecriture (pas de son sur le Halo).
void handleAdhanConfig() {
  const char *names[5] = { "fajr", "dhuhr", "asr", "maghrib", "isha" };
  const char *enKeys[5] = { "ah_fajr_en", "ah_dhuhr_en", "ah_asr_en", "ah_magh_en", "ah_isha_en" };
  if (server.method() == HTTP_GET) {
    prefs.begin("adhancfg", true);
    String json = "{";
    for (int i = 0; i < 5; i++) {
      bool en = prefs.getBool(enKeys[i], true);
      json += String("\"") + names[i] + "_track\":" + (i == 0 ? "3" : "2") + ",\"" + names[i] + "_duaa\":false,\"" + names[i] + "_enabled\":" + (en ? "true" : "false") + ",\"" + names[i] + "_volume\":0";
      if (i < 4) json += ",";
    }
    json += ",\"halo_min\":" + String(prefs.getInt("halo_min", 15)) + ",\"hardware\":\"" HALO_HARDWARE "\"}";
    prefs.end();
    server.send(200, "application/json", json);
    return;
  }
  if (!requirePost() || !requireApiKey()) return;
  String body = getRequestBody();
  prefs.begin("adhancfg", false);
  for (int i = 0; i < 5; i++) prefs.putBool(enKeys[i], parseJsonBool(body, (String(names[i]) + "_enabled").c_str(), true));
  double hm = parseJsonValue(body, "halo_min");
  if (!isnan(hm) && hm >= 1) prefs.putInt("halo_min", constrain((int)round(hm), 1, 120));
  prefs.end();
  scheduleNextPrayer();
  server.send(200, "application/json", "{\"ok\":true}");
}

void handlePrayerTimes() {
  if (!timeSet()) { server.send(200, "application/json", "{\"error\":\"RTC missing\"}"); return; }
  time_t nowL = nowLocal();
  struct tm lt; localTm(nowL, lt);

  prefs.begin("adhancfg", true);
  String mq[6] = { prefs.getString("mq_fajr", ""), prefs.getString("mq_sunrise", ""), prefs.getString("mq_dhuhr", ""),
                   prefs.getString("mq_asr", ""), prefs.getString("mq_maghrib", ""), prefs.getString("mq_isha", "") };
  unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
  prefs.end();
  unsigned long nowE = (unsigned long)time(nullptr);
  unsigned long age = (mq_sync_ts > 0 && nowE >= mq_sync_ts) ? (nowE - mq_sync_ts) : 999999UL;
  const char *names[6] = { "fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha" };
  String json = "{";
  if ((mq[0].length() >= 5) && (mq[5].length() >= 5) && (age < 25UL * 3600UL)) {
    for (int i = 0; i < 6; i++) json += "\"" + String(names[i]) + "\":\"" + mq[i] + "\",";
    json += "\"source\":\"mawaqit\"";
  } else {
    double times[6]; int tzMin; String tzSrc;
    if (!computePrayerTimesForDate(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, times, tzMin, tzSrc)) {
      server.send(200, "application/json", "{\"error\":\"location missing\"}");
      return;
    }
    for (int i = 0; i < 6; i++) json += "\"" + String(names[i]) + "\":\"" + formatTimeFromMinutes(times[i]) + "\",";
    double fa, ia; String mn;
    getCalculationAngles(fa, ia, mn);
    json += "\"tz_min\":" + String(tzMin) + ",\"tz_source\":\"" + tzSrc + "\",\"source\":\"calculated\",\"calc_method\":\"" + mn + "\",\"fajr_angle\":" + String(fa, 1) + ",\"isha_angle\":" + String(ia, 1);
  }
  time_t nextL; int nextIdx;
  if (computeNextPrayer(nowL, nextL, nextIdx)) {
    struct tm nt; localTm(nextL, nt);
    char nb[64];
    snprintf(nb, sizeof(nb), ",\"next\":\"%02d:%02d\",\"next_index\":%d", nt.tm_hour, nt.tm_min, nextIdx);
    json += nb;
  }
  json += "}";
  server.send(200, "application/json", json);
}

void handleDumpStatus() {
  prefs.begin("adhancfg", true);
  String lat = prefs.getString("lat", ""), lon = prefs.getString("lon", ""), acc = prefs.getString("acc", "");
  int tz = prefs.getInt("tz_offset_min", 0x7fffffff);
  prefs.end();
  char out[512];
  snprintf(out, sizeof(out), "{\"wifi\":\"%s\",\"ip\":\"%s\",\"rtc_ok\":%d,\"rtc\":\"%s\",\"lat\":\"%s\",\"lon\":\"%s\",\"acc\":\"%s\",\"tz\":%d}",
           WiFi.isConnected() ? "connected" : "disconnected", WiFi.isConnected() ? WiFi.localIP().toString().c_str() : "",
           timeSet() ? 1 : 0, timeSet() ? fmtLocal(nowLocal()).c_str() : "", lat.c_str(), lon.c_str(), acc.c_str(), (tz == 0x7fffffff ? -9999 : tz));
  server.send(200, "application/json", String(out));
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : le halo et le capteur (propre au Halo)
// ═══════════════════════════════════════════════════════════════════════════
// GET /api/halo/config -> {"duration_min":15,"night_auto":true,"night_threshold":400,"night_brightness":15,"sensor_present":true}
// POST : memes cles, toutes optionnelles.
void handleHaloConfig() {
  if (server.method() == HTTP_GET) {
    prefs.begin("adhancfg", true);
    char buf[256];
    snprintf(buf, sizeof(buf), "{\"duration_min\":%d,\"night_auto\":%s,\"night_threshold\":%d,\"night_brightness\":%d,\"sensor_present\":%s,\"brightness_cap\":%d}",
             prefs.getInt("halo_min", 15), prefs.getBool("als_auto", true) ? "true" : "false", prefs.getInt("als_thresh", 400),
             prefs.getInt("als_night_pct", 15), prefs.getBool("als_present", true) ? "true" : "false", BRIGHT_CAP);
    prefs.end();
    server.send(200, "application/json", buf);
    return;
  }
  if (!requirePost() || !requireApiKey()) return;
  String body = getRequestBody();
  prefs.begin("adhancfg", false);
  double v = parseJsonValue(body, "duration_min");
  if (!isnan(v) && body.indexOf("duration_min") >= 0) prefs.putInt("halo_min", constrain((int)round(v), 1, 120));
  v = parseJsonValue(body, "night_threshold");
  if (!isnan(v) && body.indexOf("night_threshold") >= 0) prefs.putInt("als_thresh", constrain((int)round(v), 0, 4095));
  v = parseJsonValue(body, "night_brightness");
  if (!isnan(v) && body.indexOf("night_brightness") >= 0) prefs.putInt("als_night_pct", constrain((int)round(v), 1, BRIGHT_CAP));
  if (body.indexOf("night_auto") >= 0) prefs.putBool("als_auto", parseJsonBool(body, "night_auto", true));
  if (body.indexOf("sensor_present") >= 0) prefs.putBool("als_present", parseJsonBool(body, "sensor_present", true));
  prefs.end();
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleHaloStatus() {
  char buf[320];
  long remaining = haloPrayerIndex ? (long)(haloUntilMs - millis()) / 1000 : 0;
  if (remaining < 0) remaining = 0;
  String next = "";
  if (scheduledPrayerIndex) { struct tm nt; localTm(scheduledPrayerLocal, nt); char nb[8]; snprintf(nb, sizeof(nb), "%02d:%02d", nt.tm_hour, nt.tm_min); next = nb; }
  snprintf(buf, sizeof(buf),
           "{\"active\":%s,\"prayer_index\":%d,\"remaining_s\":%ld,\"als\":%d,\"night\":%s,\"time_ok\":%s,\"time_approx\":%s,\"time\":\"%s\",\"next\":\"%s\",\"next_index\":%d,\"brightness_effective\":%d}",
           haloPrayerIndex ? "true" : "false", haloPrayerIndex, remaining, (int)(alsEma < 0 ? -1 : alsEma), nightMode ? "true" : "false",
           timeSet() ? "true" : "false", timeApprox() ? "true" : "false", timeSet() ? fmtLocal(nowLocal()).c_str() : "", next.c_str(), scheduledPrayerIndex, effectiveBrightness());
  server.send(200, "application/json", buf);
}

void handleHaloStop() {
  if (!requireApiKey()) return;
  haloStop();
  server.send(200, "application/json", "{\"ok\":true}");
}

void handleHaloTest() {
  if (!requireApiKey()) return;
  int minutes = server.hasArg("minutes") ? server.arg("minutes").toInt() : 1;
  haloStart(99, constrain(minutes, 1, 10));   // 99 = test, distinct d'une vraie priere
  server.send(200, "application/json", "{\"ok\":true}");
}

// ═══════════════════════════════════════════════════════════════════════════
// HTTP : identite, diagnostic, usine
// ═══════════════════════════════════════════════════════════════════════════
void handleFirmwareVersion() {
  server.send(200, "application/json", "{\"version\":\"" HALO_VERSION "\",\"hardware\":\"" HALO_HARDWARE "\",\"build\":\"" __DATE__ " " __TIME__ "\"}");
}

// Le jeton n'est lisible que pendant la fenetre d'appairage (point d'acces,
// ou 10 min apres le boot), ou par un appelant qui l'a deja. Meme regle que la V3.
void handleDeviceInfo() {
  String key = server.header("X-API-Key");
  if (key.length() == 0) key = server.arg("token");
  bool hasValidToken = (_apiToken.length() > 0 && key == _apiToken);
  bool pairingWindow = apRunning || (millis() < 10UL * 60UL * 1000UL);
  char buf[512];
  if (pairingWindow || hasValidToken) {
    snprintf(buf, sizeof(buf), "{\"version\":\"" HALO_VERSION "\",\"hardware\":\"" HALO_HARDWARE "\",\"hostname\":\"%s\",\"device_id\":\"%s\",\"token\":\"%s\",\"ota_pass\":\"%s\",\"audio\":false}",
             OTA_HOSTNAME, deviceIdHex().c_str(), _apiToken.c_str(), _otaPass.c_str());
  } else {
    snprintf(buf, sizeof(buf), "{\"version\":\"" HALO_VERSION "\",\"hardware\":\"" HALO_HARDWARE "\",\"hostname\":\"%s\",\"device_id\":\"%s\",\"paired\":true,\"audio\":false}",
             OTA_HOSTNAME, deviceIdHex().c_str());
  }
  server.send(200, "application/json", buf);
}

void handleDiag() {
  char buf[400];
  snprintf(buf, sizeof(buf),
           "{\"hardware\":\"" HALO_HARDWARE "\",\"version\":\"" HALO_VERSION "\",\"uptime_s\":%lu,\"free_heap\":%u,\"min_free_heap\":%u,"
           "\"wifi\":\"%s\",\"rssi\":%d,\"time_ok\":%s,\"als\":%d,\"night\":%s,\"scene\":%d,\"halo\":%d,\"next_prayer\":%d,\"ble\":%s}",
           (unsigned long)(millis() / 1000), (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(),
           WiFi.isConnected() ? WiFi.SSID().c_str() : "", WiFi.isConnected() ? WiFi.RSSI() : 0, timeSet() ? "true" : "false",
           (int)(alsEma < 0 ? -1 : alsEma), nightMode ? "true" : "false", ledScenario, haloPrayerIndex, scheduledPrayerIndex, _bleActive ? "true" : "false");
  server.send(200, "application/json", buf);
}

static void usineEtatJson(char *buf, size_t n) {
  wifi_config_t wc;
  bool wifiInit = (esp_wifi_get_config(WIFI_IF_STA, &wc) == ESP_OK);
  String savedSsid = wifiInit ? String((const char *)wc.sta.ssid) : String("");
  prefs.begin("adhancfg", true);
  String mq = prefs.getString("mq_uuid", "");
  String lat = prefs.getString("lat", "");
  bool hasTok = prefs.getString("api_token", "").length() > 0;
  prefs.end();
  snprintf(buf, n, "{\"wifi_init\":%s,\"saved_ssid\":\"%s\",\"mq_uuid\":\"%s\",\"lat\":\"%s\",\"api_token\":%s,\"device_id\":\"%s\"}",
           wifiInit ? "true" : "false", savedSsid.c_str(), mq.c_str(), lat.c_str(), hasTok ? "true" : "false", deviceIdHex().c_str());
}

// Efface tout ce qui distingue cette carte d'une carte neuve. Ne redemarre
// pas : l'appelant repond d'abord, puis reboot. Meme sequence que la V3.
static void usineEffacer(char *buf, size_t n) {
#if ENABLE_BLE
  if (_bleActive) stopBLEProvisioning();
#endif
  WiFi.disconnect(true, true);
  delay(100);
  WiFi.mode(WIFI_OFF);
  prefs.begin("adhancfg", false); prefs.clear(); prefs.end();
  esp_err_t e1 = nvs_flash_deinit();
  esp_err_t e2 = nvs_flash_erase();
  esp_err_t e3 = nvs_flash_init();
  g_pairBootMagic = 0;
  snprintf(buf, n, "{\"ok\":%s,\"nvs\":{\"deinit\":%d,\"erase\":%d,\"init\":%d},\"reboot\":true}", (e2 == ESP_OK) ? "true" : "false", (int)e1, (int)e2, (int)e3);
}

void handleFactoryStatus() {
  if (!requireApiKey()) return;
  char buf[320];
  usineEtatJson(buf, sizeof(buf));
  server.send(200, "application/json", buf);
}

void handleFactoryReset() {
  if (!requireApiKey() || !requirePost()) return;
  String confirm = parseJsonString(getRequestBody(), "confirm");
  if (confirm != deviceIdHex()) { server.send(400, "application/json", "{\"error\":\"confirm doit etre l'identifiant de cette carte\"}"); return; }
  char buf[160];
  usineEffacer(buf, sizeof(buf));
  server.send(200, "application/json", buf);
  server.client().flush();
  delay(400);
  ESP.restart();
}

// ═══════════════════════════════════════════════════════════════════════════
// OTA : upload signe (meme cle publique que la V3) + ArduinoOTA
// ═══════════════════════════════════════════════════════════════════════════
#ifdef UPDATE_SIGN
#include <Updater_Signing.h>
static const char OTA_PUBLIC_KEY[] = R"KEY(-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEe2grqFMJBQNxxMJ5r2v9f6GM1TZp
vZhqqmANmLvW36L72tuB1dDT/1G5mxqn2Rk6n3dz2bCL7oeN+60HAfbmHQ==
-----END PUBLIC KEY-----
)KEY";
static UpdaterECDSAVerifier *_otaVerifier = nullptr;
#endif

void handleOtaUpload() {
  bool auth = true;
  if (_apiToken.length() > 0 && !apRunning) {
    String key = server.header("X-API-Key");
    if (key.length() == 0) key = server.arg("token");
    if (key != _apiToken) auth = false;
  }
  if (!auth) return;
  HTTPUpload &upload = server.upload();
  if (upload.status == UPLOAD_FILE_START) {
    size_t total = (size_t)server.arg("size").toInt();
    Serial.printf("OTA : debut %s (%u octets)\n", upload.filename.c_str(), (unsigned)total);
    stripSetAll(255, 60, 0);
#ifdef UPDATE_SIGN
    if (total == 0) { Serial.println("OTA REFUSE : ?size= manquant"); return; }
    if (!_otaVerifier) _otaVerifier = new UpdaterECDSAVerifier((const uint8_t *)OTA_PUBLIC_KEY, sizeof(OTA_PUBLIC_KEY), HASH_SHA256);
    Update.installSignature(_otaVerifier);
    if (!Update.begin(total)) Update.printError(Serial);
#else
    if (!Update.begin(total ? total : UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
#endif
  } else if (upload.status == UPLOAD_FILE_WRITE) {
    if (Update.write(upload.buf, upload.currentSize) != upload.currentSize) Update.printError(Serial);
  } else if (upload.status == UPLOAD_FILE_END) {
    if (Update.end(true)) Serial.printf("OTA OK : %u octets\n", upload.totalSize);
    else Update.printError(Serial);
  }
}

void handleOtaUploadComplete() {
  if (!requireApiKey()) return;
  if (Update.hasError()) { stripSetAll(255, 0, 0); server.send(500, "application/json", "{\"ok\":false,\"error\":\"Update failed\"}"); }
  else {
    stripSetAll(0, 255, 0);
    server.send(200, "application/json", "{\"ok\":true,\"msg\":\"Firmware updated — rebooting\"}");
    delay(2000);
    ESP.restart();
  }
}

void handleUpdatePage() {
  server.send(200, "text/html", R"HTML(<!DOCTYPE html><html><head><meta charset="utf-8"><title>Mise à jour Halo</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{font-family:sans-serif;background:#121212;color:#e0e0e0;text-align:center;padding:30px}.card{background:#1e1e1e;max-width:400px;margin:50px auto;padding:30px;border-radius:12px;border:1px solid #333}
h2{color:#059669}input{display:block;width:100%;margin:15px 0;padding:12px;box-sizing:border-box;border-radius:8px}input[type=submit]{background:#059669;border:none;color:#fff;font-weight:bold;cursor:pointer}</style></head>
<body><div class="card"><h2>Mise à jour Firmware</h2><p>Sélectionnez le fichier <code>halo.ino.bin</code> signé.</p>
<form method="POST" action="/ota/upload" enctype="multipart/form-data" id="upForm"><input type="text" name="token" id="tokenField" placeholder="Clé d'API (Token)">
<input type="file" name="update" id="fileField" accept=".bin" required><input type="submit" value="Démarrer la mise à jour"></form>
<script>fetch('/api/device/info').then(r=>r.json()).then(j=>{if(j.token)document.getElementById('tokenField').value=j.token;}).catch(()=>{});
document.getElementById('upForm').onsubmit=function(){var t=document.getElementById('tokenField').value;var f=document.getElementById('fileField').files[0];this.action='/ota/upload?token='+encodeURIComponent(t)+'&size='+(f?f.size:0);};</script>
</div></body></html>)HTML");
}

void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(_otaPass.c_str());
  ArduinoOTA.onStart([]() { stripSetAll(255, 60, 0); });
  ArduinoOTA.onEnd([]() { stripSetAll(0, 255, 0); });
  ArduinoOTA.onError([](ota_error_t error) { Serial.printf("OTA erreur %u\n", error); stripSetAll(255, 0, 0); });
  ArduinoOTA.begin();
}

// ═══════════════════════════════════════════════════════════════════════════
// Routes
// ═══════════════════════════════════════════════════════════════════════════
void setupServerRoutes() {
  static const char *kCollectedHeaders[] = { "X-API-Key" };
  server.collectHeaders(kCollectedHeaders, 1);

  server.on("/", HTTP_GET, handleRoot);
  server.on("/set_location", HTTP_POST, handleSetLocation);
  server.on("/set_tz", HTTP_POST, handleSetTZ);
  server.on("/rtc_time", HTTP_GET, handleShowTime);
  server.on("/show_time", HTTP_GET, handleShowTime);
  server.on("/show_loc", HTTP_GET, handleShowLoc);
  server.on("/prayer_times", HTTP_GET, handlePrayerTimes);
  server.on("/dump_status", HTTP_GET, handleDumpStatus);
  server.on("/led_test", HTTP_GET, handleLedTest);
  server.on("/set_led", HTTP_GET, handleSetLed);
  server.on("/led_off", HTTP_GET, handleLedOff);
  server.on("/scan_wifi", HTTP_GET, handleScanWifi);
  server.on("/set_brightness", HTTP_POST, handleSetBrightness);
  server.on("/get_brightness", HTTP_GET, handleGetBrightness);
  server.on("/connect_wifi", HTTP_POST, handleConnectWifi);
  server.on("/disconnect_wifi", HTTP_GET, handleDisconnectWifi);
  server.on("/stop_ap", HTTP_GET, []() { server.send(200, "text/plain", "AP stopped"); stopConfigAP(); });
  server.on("/sync_time", HTTP_GET, []() {
    if (syncTimeFromNtp(10000)) { scheduleNextPrayer(); server.send(200, "text/plain", "Time synced"); }
    else server.send(500, "text/plain", "Time sync failed");
  });
  server.on("/api/calculation/config", HTTP_GET, handleCalculationConfig);
  server.on("/api/calculation/config", HTTP_POST, handleCalculationConfig);
  server.on("/api/mawaqit/config", HTTP_POST, handleMawaqitConfig);
  server.on("/api/mawaqit/sync", HTTP_POST, handleMawaqitSync);
  server.on("/api/mawaqit/debug", HTTP_GET, handleMawaqitDebug);
  server.on("/api/mawaqit/offsets", HTTP_GET, handleMawaqitGetOffsets);
  server.on("/api/mawaqit/offsets", HTTP_POST, handleMawaqitSetOffsets);
  server.on("/api/adhan/config", HTTP_GET, handleAdhanConfig);
  server.on("/api/adhan/config", HTTP_POST, handleAdhanConfig);
  server.on("/api/config/timezone", HTTP_POST, handleSetTZ);
  server.on("/api/led/brightness", HTTP_POST, handleSetBrightness);
  server.on("/api/led/brightness", HTTP_GET, handleGetBrightness);
  server.on("/api/led/scenario", HTTP_POST, handleSetLedScenario);
  server.on("/api/led/rgb", HTTP_POST, handleSetLedRgb);
  server.on("/api/led/status", HTTP_GET, handleLedStatus);
  server.on("/api/wifi/status", HTTP_GET, handleWifiStatus);
  server.on("/api/firmware/version", HTTP_GET, handleFirmwareVersion);
  server.on("/api/device/info", HTTP_GET, handleDeviceInfo);
  server.on("/api/diag", HTTP_GET, handleDiag);
  server.on("/api/halo/config", HTTP_GET, handleHaloConfig);
  server.on("/api/halo/config", HTTP_POST, handleHaloConfig);
  server.on("/api/halo/status", HTTP_GET, handleHaloStatus);
  server.on("/api/halo/stop", HTTP_POST, handleHaloStop);
  server.on("/api/halo/test", HTTP_POST, handleHaloTest);
  server.on("/api/factory_status", HTTP_GET, handleFactoryStatus);
  server.on("/api/factory_reset", HTTP_POST, handleFactoryReset);
  server.on("/ota/upload", HTTP_POST, handleOtaUploadComplete, handleOtaUpload);
  server.on("/update", HTTP_GET, handleUpdatePage);
  // Routes que l'app AdhanBox appelle sur toutes les generations
  server.on("/set_rtc_manual", HTTP_POST, handleSetRtcManual);
  server.on("/api/time", HTTP_GET, handleApiTime);
  server.on("/api/wifi/scan", HTTP_GET, handleScanWifi);
  server.on("/api/status", HTTP_GET, []() {
    char buf[256];
    bool c = WiFi.isConnected();
    snprintf(buf, sizeof(buf), "{\"wifi\":{\"connected\":%s,\"ssid\":\"%s\",\"ip\":\"%s\",\"signal\":%d},\"ip\":\"%s\",\"hardware\":\"" HALO_HARDWARE "\"}",
             c ? "true" : "false", c ? WiFi.SSID().c_str() : "", c ? WiFi.localIP().toString().c_str() : "", c ? WiFi.RSSI() : 0, c ? WiFi.localIP().toString().c_str() : "");
    server.send(200, "application/json", buf);
  });
  server.on("/api/config/timezone", HTTP_GET, []() {
    int tz = tzOffsetMinStored();
    server.send(200, "application/json", String("{\"tz_min\":") + (tz == 0x7fffffff ? String("null") : String(tz)) + ",\"effective_tz_min\":" + tzOffsetMin() + "}");
  });
  server.on("/api/config/location", HTTP_GET, handleShowLoc);
  server.on("/api/prayer/test", HTTP_POST, []() {      // « tester la priere » de l'app : un halo d'une minute
    if (!requireApiKey()) return;
    double idx = parseJsonValue(getRequestBody(), "prayer_index");
    haloStart(isnan(idx) ? 99 : (int)idx, 1);
    server.send(200, "application/json", "{\"ok\":true}");
  });
  // Pas de son sur le Halo : l'app lit ces routes sur toutes les box, on
  // repond « rien ne joue » plutot qu'une erreur.
  server.on("/api/audio/status", HTTP_GET, []() { server.send(200, "application/json", "{\"playing\":false,\"paused\":false,\"file\":\"\",\"pos\":0,\"size\":0,\"volume\":0,\"audio\":false}"); });
  server.on("/api/audio/list", HTTP_GET, []() { server.send(200, "application/json", "[]"); });
  server.on("/get_volume", HTTP_GET, []() { server.send(200, "application/json", "{\"vol\":0,\"audio\":false}"); });
  server.on("/api/content/status", HTTP_GET, []() { server.send(200, "application/json", "{\"running\":false,\"added\":0,\"audio\":false}"); });
  server.on("/api/azkarcoran", HTTP_GET, []() {
    server.send(200, "application/json", "{\"sabah\":{\"en\":0,\"h\":0,\"m\":0,\"vol\":0,\"days\":0},\"masaa\":{\"en\":0,\"h\":0,\"m\":0,\"vol\":0,\"days\":0},"
                                          "\"kahf\":{\"en\":0,\"h\":0,\"m\":0,\"vol\":0,\"days\":0},\"mulk\":{\"en\":0,\"h\":0,\"m\":0,\"vol\":0,\"days\":0},\"audio\":false}");
  });
  auto noAudio = []() { server.send(200, "application/json", "{\"ok\":true,\"audio\":false}"); };
  server.on("/play", HTTP_GET, noAudio);
  server.on("/stopplay", HTTP_GET, noAudio);
  server.on("/set_volume", HTTP_POST, noAudio);
  server.on("/api/audio/volume", HTTP_POST, noAudio);
  server.on("/api/audio/play", HTTP_GET, noAudio);
  server.on("/api/audio/pause", HTTP_GET, noAudio);
  server.on("/api/audio/resume", HTTP_GET, noAudio);
  server.on("/api/azkarcoran", HTTP_POST, noAudio);
  server.on("/api/content/sync", HTTP_POST, noAudio);
#if ENABLE_BLE
  // Appairage a chaud : on memorise la demande et on REBOOTE (RAM fraiche),
  // comme la V3.
  server.on("/api/pair", HTTP_GET, []() {
    g_pairBootMagic = PAIR_BOOT_MAGIC;
    server.send(200, "application/json", "{\"ok\":true,\"msg\":\"Redemarrage en mode appairage (LED clignote ~5 min)\"}");
    delay(400);
    ESP.restart();
  });
  server.on("/api/start_ble", HTTP_GET, []() {
    if (!_bleActive) { startBLEProvisioning(); server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE provisioning started\"}"); }
    else server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE already active\"}");
  });
  server.on("/api/stop_ble", HTTP_GET, []() { stopBLEProvisioning(); server.send(200, "application/json", "{\"ok\":true,\"message\":\"BLE stopped\"}"); });
#endif
}

void startServices() {
  static bool servicesStarted = false;
  if (servicesStarted) return;
  setupServerRoutes();
  server.begin();
  Serial.println("[WiFi] serveur web : http://" + WiFi.localIP().toString());
  if (MDNS.begin(OTA_HOSTNAME)) { MDNS.addService("http", "tcp", 80); }
  setupOTA();
  servicesStarted = true;
}

void startConfigAP() {
  if (apRunning) return;
  if (prevLedScenario < 0) prevLedScenario = ledScenario;
  ledScenario = BLINK_INDEX;
  uint64_t mac = ESP.getEfuseMac();
  char ssid[32];
  snprintf(ssid, sizeof(ssid), "%s%04X", AP_SSID_PREFIX, (uint16_t)(mac & 0xFFFF));
  WiFi.softAP(ssid);
  delay(100);
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
  server.onNotFound([&]() {
    server.sendHeader("Location", String("http://") + WiFi.softAPIP().toString(), true);
    server.send(302, "text/plain", "");
  });
  setupServerRoutes();
  server.begin();
  apRunning = true;
  apStartTime = millis();
  Serial.printf("Point d'acces : %s\n", ssid);
}

void stopConfigAP() {
  if (!apRunning) return;
  dnsServer.stop();
  server.stop();
  WiFi.softAPdisconnect(true);
  apRunning = false;
  if (prevLedScenario >= 0) { ledScenario = prevLedScenario; prevLedScenario = -1; }
}

// ═══════════════════════════════════════════════════════════════════════════
// BLE : demarrage, arret, traitement des identifiants (repris de la V3)
// ═══════════════════════════════════════════════════════════════════════════
#if ENABLE_BLE
void startBLEProvisioning() {
  if (prevLedScenario < 0) prevLedScenario = ledScenario;
  ledScenario = BLINK_INDEX;
  WiFi.mode(WIFI_STA);
  uint8_t macBytes[6] = { 0 };
  esp_read_mac(macBytes, ESP_MAC_WIFI_STA);   // eFuse : jamais 00:00:00 au boot
  char sufBuf[7];
  snprintf(sufBuf, sizeof(sufBuf), "%02X%02X%02X", macBytes[3], macBytes[4], macBytes[5]);
  String bleName = String(BLE_NAME_PREFIX) + sufBuf;

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
    _bleStatusChar = svc->createCharacteristic(BLE_STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    _bleStatusChar->addDescriptor(new BLE2902());
    _bleStatusChar->setValue("waiting");
    _bleWifiScanChar = svc->createCharacteristic(BLE_WIFI_SCAN_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
    _bleWifiScanChar->addDescriptor(new BLE2902());
    _bleWifiScanChar->setCallbacks(new _BLEWifiScanCB());
    svc->start();
    BLEAdvertising *adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(BLE_SVC_UUID);
    adv->setScanResponse(true);
    adv->setMinPreferred(0x06);
    adv->setMaxPreferred(0x12);
    bleInitialized = true;
  } else if (_bleStatusChar) {
    _bleStatusChar->setValue("waiting");
  }
  BLEDevice::startAdvertising();
  _bleActive = true;
  Serial.printf("[BLE] annonce '%s'\n", bleName.c_str());
}

void stopBLEProvisioning() {
  if (!_bleActive) return;
  _bleActive = false;
  if (_bleServer && _bleClientConn) { _bleServer->disconnect(0); delay(300); }
  BLEDevice::stopAdvertising();
  BLEDevice::deinit(true);
  _bleCredsReady = false;
  _bleClientConn = false;
  Serial.println("[BLE] arrete");
  if (prevLedScenario >= 0) { ledScenario = prevLedScenario; prevLedScenario = -1; }
}

void handleBLEProvisioning() {
  if (!_bleActive || !_bleCredsReady) return;
  _bleCredsReady = false;
  String ssid = _blePendingSSID, pass = _blePendingPass;
  Serial.printf("[BLE] connexion Wi-Fi : %s\n", ssid.c_str());
  if (_bleStatusChar && _bleClientConn) { _bleStatusChar->setValue("connecting"); _bleStatusChar->notify(); }
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());
  unsigned long t0 = millis();
  while (millis() - t0 < 20000 && WiFi.status() != WL_CONNECTED) { if (_wdtArmed) esp_task_wdt_reset(); delay(300); }
  if (WiFi.status() == WL_CONNECTED) {
    String ip = WiFi.localIP().toString();
    Serial.printf("[BLE] Wi-Fi OK, IP %s\n", ip.c_str());
    prefs.begin("adhancfg", false);
    prefs.putString("wifi_ssid", ssid);
    prefs.putString("wifi_pass", pass);
    prefs.end();
    String payload = "{\"ok\":true,\"ip\":\"" + ip + "\"}";
    if (_bleStatusChar) { _bleStatusChar->setValue(payload.c_str()); if (_bleClientConn) { _bleStatusChar->notify(); delay(400); } }
    delay(100);
    stopBLEProvisioning();
    delay(100);
    startServices();
    wifiConnectState = WCS_CONNECTED;
    syncTimeFromNtp(10000);
    scheduleNextPrayer();
  } else {
    Serial.println("[BLE] Wi-Fi refuse (mot de passe ?)");
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    delay(300);
    if (_bleStatusChar) { _bleStatusChar->setValue("{\"ok\":false,\"error\":\"wifi_failed\"}"); if (_bleClientConn) { _bleStatusChar->notify(); delay(200); } }
    _blePendingSSID = ""; _blePendingPass = "";
    BLEDevice::startAdvertising();
    _bleActive = true;
  }
}
#endif

// ═══════════════════════════════════════════════════════════════════════════
// Banc de production par le cable USB : t:info, t:diag, t:led N, t:usine
// ═══════════════════════════════════════════════════════════════════════════
static void bancRep(const String &json) {
  String line = "<BANC>" + json + "\n";
  Serial.write((const uint8_t *)line.c_str(), line.length());
}

static void bancCommande(String c) {
  c.trim();
  if (c == "info") {
    bancRep("{\"hardware\":\"" HALO_HARDWARE "\",\"version\":\"" HALO_VERSION "\",\"device_id\":\"" + deviceIdHex() + "\",\"token\":\"" + _apiToken + "\"}");
  } else if (c == "diag") {
    char buf[200];
    snprintf(buf, sizeof(buf), "{\"free_heap\":%u,\"als\":%d,\"btn\":%d,\"time_ok\":%s,\"wifi\":%s}", (unsigned)ESP.getFreeHeap(), analogRead(ALS_PIN),
             digitalRead(BTN_PIN), timeSet() ? "true" : "false", WiFi.isConnected() ? "true" : "false");
    bancRep(buf);
  } else if (c.startsWith("led")) {
    int sc = c.substring(3).toInt();
    if (sc < 0 || sc >= TOTAL_SCENES) sc = 1;
    if (prevLedScenario < 0) prevLedScenario = ledScenario;
    ledScenario = sc;
    bancRep("{\"ok\":true,\"scene\":" + String(sc) + "}");
  } else if (c == "usine") {
    char buf[160];
    usineEffacer(buf, sizeof(buf));
    bancRep(buf);
    delay(200);
    ESP.restart();
  } else {
    bancRep("{\"error\":\"commande inconnue\"}");
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// setup
// ═══════════════════════════════════════════════════════════════════════════
void setup() {
#if ARDUINO_USB_CDC_ON_BOOT
  Serial.setTxBufferSize(2048);      // avant begin(), voir V3 3.0.17
#endif
  Serial.begin(115200);
#if ARDUINO_USB_CDC_ON_BOOT
  Serial.setTxTimeoutMs(0);          // sans hote USB, les traces sont perdues, pas bloquantes
#endif
  delay(100);
  Serial.println("Halo v1 firmware " HALO_VERSION);

  // Watchdog : regle ici, arme dans loop() a la 1re iteration (setup() peut
  // durer 5 min d'appairage).
  {
    esp_task_wdt_config_t wdtCfg = { .timeout_ms = 30000, .idle_core_mask = 0, .trigger_panic = true };
    esp_task_wdt_reconfigure(&wdtCfg);
  }

  pinMode(BTN_PIN, INPUT_PULLUP);
  analogReadResolution(12);
  analogSetPinAttenuation(ALS_PIN, ADC_11db);

  prefs.begin("adhancfg", true);
  ledBrightness = prefs.getInt("brightness", 50);
  ledScenario = prefs.getInt("led_scenario", DYN_HUE_INDEX);
  ledCustomActive = prefs.getBool("led_custom", false);
  ledCustomR = (uint8_t)prefs.getInt("led_cr", 255);
  ledCustomG = (uint8_t)prefs.getInt("led_cg", 200);
  ledCustomB = (uint8_t)prefs.getInt("led_cb", 0);
  prefs.end();
  if (ledScenario == BLINK_INDEX || ledScenario == SCENE_PRAYER) ledScenario = DYN_HUE_INDEX;

  // Jeton d'API et mot de passe OTA : generes une fois, uniques par carte.
  static const char SEC_CHARSET[] = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
  randomSeed(esp_random());
  prefs.begin("adhancfg", true);
  _otaPass = prefs.getString("ota_pass", "");
  _apiToken = prefs.getString("api_token", "");
  prefs.end();
  if (_otaPass.length() == 0) {
    for (int i = 0; i < 12; i++) _otaPass += SEC_CHARSET[random(sizeof(SEC_CHARSET) - 1)];
    prefs.begin("adhancfg", false); prefs.putString("ota_pass", _otaPass); prefs.end();
  }
  if (_apiToken.length() == 0) {
    for (int i = 0; i < 16; i++) _apiToken += SEC_CHARSET[random(sizeof(SEC_CHARSET) - 1)];
    prefs.begin("adhancfg", false); prefs.putString("api_token", _apiToken); prefs.end();
  }

  leds.begin();
  leds.clear();
  leds.show();
  delay(50);
  _fxBright = effectiveBrightness();

  // Rollback OTA : arrive ici = peripheriques initialises sans crash, le
  // firmware est confirme valide.
  if (esp_ota_mark_app_valid_cancel_rollback() == ESP_OK) Serial.println("[OTA] firmware confirme valide");

  // Heure et halo repris de l'horloge interne si le reset est logiciel
  if (restoreCarriedTime()) {
    scheduleNextPrayer();
    if (g_haloCarryMagic == HALO_CARRY_MAGIC && g_haloCarryUntilUtc > (int64_t)time(nullptr)) {
      int remaining = (int)((g_haloCarryUntilUtc - (int64_t)time(nullptr) + 59) / 60);
      Serial.printf("[HALO] reprise apres reset, %d min restantes\n", remaining);
      haloStart(g_haloCarryIndex, remaining);
    }
  }
  g_haloCarryMagic = (haloPrayerIndex != 0) ? HALO_CARRY_MAGIC : 0;

  // ── Demarrage : Wi-Fi memorise d'abord, appairage BLE en repli ──
  bool wifiConnected = false;
  bool pairBoot = (g_pairBootMagic == PAIR_BOOT_MAGIC);
  g_pairBootMagic = 0;
  prefs.begin("adhancfg", true);
  String bootSSID = prefs.getString("wifi_ssid", "");
  String bootPass = prefs.getString("wifi_pass", "");
  prefs.end();

  if (bootSSID.length() > 0 && !pairBoot) {
    Serial.printf("Wi-Fi memorise : %s\n", bootSSID.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(bootSSID.c_str(), bootPass.c_str());
    unsigned long t0 = millis();
    while (millis() - t0 < 15000 && WiFi.status() != WL_CONNECTED) {
      // respiration blanche faible pendant l'attente : « pas d'heure »
      _fxBright = effectiveBrightness();
      float k = 0.15f + 0.15f * sinf((float)millis() * (2.0f * 3.14159265f / 3000.0f));
      stripSetAll((uint8_t)(255 * k), (uint8_t)(230 * k), (uint8_t)(200 * k));
      delay(50);
    }
    if (WiFi.status() == WL_CONNECTED) {
      wifiConnected = true;
      wifiConnectState = WCS_CONNECTED;
      Serial.printf("Wi-Fi connecte, IP %s\n", WiFi.localIP().toString().c_str());
    } else Serial.println("Wi-Fi memorise indisponible -> appairage BLE");
  } else if (pairBoot) {
    Serial.println("Appairage demande -> BLE pur");
  }

#if ENABLE_BLE
  if (!wifiConnected) {
    startBLEProvisioning();
    delay(300);
    const unsigned long BLE_INACTIVITY_TIMEOUT_MS = 5UL * 60UL * 1000UL;
    unsigned long bleInactivityTimer = millis();
    bool bleHadClient = false;
    bool btnWasUp = (digitalRead(BTN_PIN) == HIGH);
    while (true) {
      unsigned long now = millis();
      _fxBright = effectiveBrightness();
      if ((now / 300) % 2 == 0) stripSetAll(200, 0, 0); else stripSetAll(0, 0, 0);
      if (_bleCredsReady) {
        handleBLEProvisioning();
        if (WiFi.status() == WL_CONNECTED) wifiConnected = true;
        break;
      }
      if (_bleClientConn && !bleHadClient) { bleHadClient = true; bleInactivityTimer = now; }
      if (!_bleClientConn && bleHadClient) { bleHadClient = false; bleInactivityTimer = now; }
      if (now - bleInactivityTimer >= BLE_INACTIVITY_TIMEOUT_MS) { Serial.println("[BLE] 5 min sans client, arret"); break; }
      // Banc de production : une carte neuve sort tout de suite de l'attente.
      if (Serial.available()) {
        String tcmd = Serial.readStringUntil('\n');
        tcmd.trim();
        if (tcmd.startsWith("t:")) { bancCommande(tcmd.substring(2)); break; }
      }
      // Bouton : sortie manuelle (sauf appairage demande explicitement)
      bool btnUp = (digitalRead(BTN_PIN) == HIGH);
      if (!pairBoot && btnWasUp && !btnUp) {
        delay(80);
        if (digitalRead(BTN_PIN) == LOW) { Serial.println("[BLE] bouton : arret"); break; }
      }
      btnWasUp = btnUp;
      delay(100);
    }
    if (_bleActive) { stopBLEProvisioning(); delay(100); }
  }
  if (pairBoot && !wifiConnected && bootSSID.length() > 0) {
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(bootSSID.c_str(), bootPass.c_str());
    unsigned long t0 = millis();
    while (millis() - t0 < 15000 && WiFi.status() != WL_CONNECTED) delay(300);
    if (WiFi.status() == WL_CONNECTED) { wifiConnected = true; wifiConnectState = WCS_CONNECTED; }
  }
#endif

  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    if (!timeSet() || timeApprox()) syncTimeFromNtp(15000);
    scheduleNextPrayer();
    startServices();
  } else {
    Serial.println("Hors ligne : respiration blanche jusqu'au NTP.");
  }
  Serial.println("Commandes serie : startap, stopap, startble, stopble, showloc, showtimes, t:info, t:diag, t:led N, t:usine");
}

// ═══════════════════════════════════════════════════════════════════════════
// loop
// ═══════════════════════════════════════════════════════════════════════════
void loop() {
  if (!_wdtArmed) { esp_task_wdt_add(NULL); _wdtArmed = true; }
  esp_task_wdt_reset();
  unsigned long now = millis();

#if ENABLE_BLE
  if (_bleActive) {
    handleBLEProvisioning();
    static unsigned long loopBleTimer = 0;
    static bool lastBleState = false, loopBleHadClient = false;
    if (_bleActive && !lastBleState) { loopBleTimer = now; loopBleHadClient = _bleClientConn; }
    lastBleState = _bleActive;
    if (_bleClientConn && !loopBleHadClient) { loopBleHadClient = true; loopBleTimer = now; }
    if (!_bleClientConn && loopBleHadClient) { loopBleHadClient = false; loopBleTimer = now; }
    if (now - loopBleTimer >= 5UL * 60UL * 1000UL) stopBLEProvisioning();
  }
#endif

  buttonTick();
  alsTick();
  ledFlushSave();

  // Commandes serie
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.startsWith("t:")) bancCommande(cmd.substring(2));
    else if (cmd.equalsIgnoreCase("startap")) startConfigAP();
    else if (cmd.equalsIgnoreCase("stopap")) stopConfigAP();
#if ENABLE_BLE
    else if (cmd.equalsIgnoreCase("startble")) { if (!_bleActive) startBLEProvisioning(); }
    else if (cmd.equalsIgnoreCase("stopble")) stopBLEProvisioning();
#endif
    else if (cmd.equalsIgnoreCase("showloc")) {
      double lt, ln, ac;
      if (loadStoredLocation(lt, ln, ac)) Serial.printf("Position : %f, %f\n", lt, ln); else Serial.println("Pas de position");
    } else if (cmd.equalsIgnoreCase("showtimes")) {
      if (!timeSet()) Serial.println("Pas d'heure");
      else {
        struct tm lt; localTm(nowLocal(), lt);
        double t[6]; int tz; String src;
        if (computePrayerTimesForDate(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, t, tz, src)) {
          const char *n[6] = { "Fajr", "Lever", "Dhuhr", "Asr", "Maghrib", "Isha" };
          for (int i = 0; i < 6; i++) Serial.printf("%s %s\n", n[i], formatTimeFromMinutes(t[i]).c_str());
        } else Serial.println("Pas de position");
      }
    } else if (cmd.equalsIgnoreCase("halo")) haloStart(99, 1);
    else Serial.printf("Commande inconnue : %s\n", cmd.c_str());
  }

  // Fin du halo, fin du test LED
  if (haloPrayerIndex && (long)(now - haloUntilMs) >= 0) haloStop();
  if (ledTestUntil != 0 && now > ledTestUntil) {
    ledTestUntil = 0;
    if (prevLedScenario >= 0) { ledScenario = prevLedScenario; prevLedScenario = -1; }
  }

  // Rendu LED a 50 Hz
  static unsigned long lastLedTick = 0;
  if (now - lastLedTick >= 20) {
    lastLedTick = now;
    _fxBright = effectiveBrightness();
    if (ledTestUntil != 0) {
      uint8_t offset = (now / 10) & 0xFF;
      for (uint16_t i = 0; i < LED_NUM; i++) {
        uint8_t r, g, b;
        hsv2rgb((uint8_t)((i * 256 / LED_NUM) + offset), 255, 220, r, g, b);
        pixel(i, r, g, b);
      }
      leds.show();
    } else if (_bleActive || apRunning) {
      renderScene(BLINK_INDEX, now);
    } else if (!timeSet() && ledScenario != 0) {
      // « Pas d'heure » : respiration blanche faible, quel que soit le reglage.
      float k = 0.15f + 0.15f * sinf((float)now * (2.0f * 3.14159265f / 3000.0f));
      stripSetAll((uint8_t)(255 * k), (uint8_t)(230 * k), (uint8_t)(200 * k));
    } else if (ledCustomActive) {
      stripSetAll(ledCustomR, ledCustomG, ledCustomB);
    } else {
      renderScene(ledScenario, now);
    }
  }

  // Declenchement de la priere : une fois par seconde, sur l'heure locale.
  static unsigned long lastPrayerCheck = 0;
  if (now - lastPrayerCheck >= 1000) {
    lastPrayerCheck = now;
    if (timeSet()) {
      if (scheduledPrayerIndex == 0) scheduleNextPrayer();
      else if (nowLocal() >= scheduledPrayerLocal) {
        struct tm pt; localTm(scheduledPrayerLocal, pt);
        int idx = scheduledPrayerIndex;
        prefs.begin("adhancfg", true);
        bool dup = (prefs.getInt("last_trig_idx", 0) == idx && prefs.getInt("last_trig_day", 0) == pt.tm_mday
                    && prefs.getInt("last_trig_mon", 0) == pt.tm_mon + 1 && prefs.getInt("last_trig_yr", 0) == pt.tm_year + 1900);
        prefs.end();
        if (dup) Serial.printf("Priere %d deja signalee aujourd'hui\n", idx);
        else {
          prefs.begin("adhancfg", false);
          prefs.putInt("last_trig_idx", idx);
          prefs.putInt("last_trig_day", pt.tm_mday);
          prefs.putInt("last_trig_mon", pt.tm_mon + 1);
          prefs.putInt("last_trig_yr", pt.tm_year + 1900);
          prefs.end();
          if (prayerEnabled(idx)) haloStart(idx, haloDurationMin());
          else Serial.printf("Priere %d desactivee ou lever : pas de halo\n", idx);
        }
        scheduleNextPrayer();
      }
    }
  }

  // Connexion Wi-Fi asynchrone (POST /connect_wifi)
  if (wifiConnectState == WCS_CONNECTING) {
    if (WiFi.status() == WL_CONNECTED) {
      wifiConnectState = WCS_CONNECTED;
      prefs.begin("adhancfg", false);
      prefs.putString("wifi_ssid", wifiConnectSSID);
      prefs.putString("wifi_pass", wifiConnectPass);
      prefs.end();
      startServices();
      if (!timeSet() || timeApprox()) syncTimeFromNtp(15000);
      scheduleNextPrayer();
    } else if (millis() - wifiConnectStart > WIFI_CONNECT_TIMEOUT_MS) {
      wifiConnectState = WCS_FAILED;
      WiFi.disconnect(true);
    }
  }

  server.handleClient();
  if (WiFi.status() == WL_CONNECTED) ArduinoOTA.handle();

  // Wi-Fi tombe : nouvelle tentative toutes les 60 s
  static unsigned long lastWifiRetry = 0;
  if (wifiConnectState != WCS_CONNECTING && !apRunning && !_bleActive && WiFi.status() != WL_CONNECTED && now - lastWifiRetry > 60000) {
    lastWifiRetry = now;
    prefs.begin("adhancfg", true);
    String rSsid = prefs.getString("wifi_ssid", ""), rPass = prefs.getString("wifi_pass", "");
    prefs.end();
    if (rSsid.length() > 0) {
      WiFi.disconnect(true);
      WiFi.mode(WIFI_STA);
      wifiConnectSSID = rSsid; wifiConnectPass = rPass;
      WiFi.begin(rSsid.c_str(), rPass.c_str());
      wifiConnectStart = now;
      wifiConnectState = WCS_CONNECTING;
    }
  }

  // Sauvegarde de l'heure (15 min) ; si l'heure est approximative, on retente le NTP toutes les 5 min
  static unsigned long lastEpochSave = 0;
  if (now - lastEpochSave > 15UL * 60UL * 1000UL) { lastEpochSave = now; saveEpoch(); }
  static unsigned long lastApproxNtp = 0;
  if (timeApprox() && WiFi.status() == WL_CONNECTED && now - lastApproxNtp > 5UL * 60UL * 1000UL) {
    lastApproxNtp = now;
    if (syncTimeFromNtp(5000)) scheduleNextPrayer();
  }

  // Synchro Mawaqit automatique : une fois par minute on regarde, plus de 20 h -> on resynchronise
  static unsigned long lastAutoSyncCheck = 0;
  if (now - lastAutoSyncCheck > 60000) {
    lastAutoSyncCheck = now;
    if (WiFi.status() == WL_CONNECTED && timeSet()) {
      prefs.begin("adhancfg", true);
      unsigned long mq_sync_ts = prefs.getULong("mq_sync_ts", 0);
      String uuid = prefs.getString("mq_uuid", "");
      prefs.end();
      if (uuid.length() > 0) {
        unsigned long nowE = (unsigned long)time(nullptr);
        unsigned long age = (mq_sync_ts > 0 && nowE >= mq_sync_ts) ? (nowE - mq_sync_ts) : 999999UL;
        if (age > 20UL * 3600UL) {
          String err;
          if (performMawaqitSync(err)) scheduleNextPrayer();
          else Serial.printf("Synchro auto Mawaqit : %s\n", err.c_str());
        }
      }
    }
  }

  if (apRunning) dnsServer.processNextRequest();
  delay(5);
}
