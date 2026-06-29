#!/usr/bin/env python3
"""Génère adhanbox_v2/adhanbox_v2.ino à partir du firmware V1 (adhanbox/adhanbox.ino).

Changements V1 -> V2 :
  - Audio : DFPlayer -> I2S (MAX98357A) + SD pilotée par l'ESP (shim de compat)
  - Broches : LED 13->8, bouton 11->6, ajout SD (10-13) + I2S (1,2,3)
  - Serial2 (DFPlayer sur GPIO1/2) désactivé (conflit avec l'I2S)
  - Version 1.4.6 -> 2.0.0 + marqueur matériel "hardware":"v2"
  - dfplayer.loop() ajouté dans loop() pour pomper le décodage audio

NE TOUCHE PAS au firmware V1 ni à firmware_version.json (canal V1 figé).
"""
import os, sys

SRC = "adhanbox/adhanbox.ino"
DST_DIR = "adhanbox_v2"
DST = os.path.join(DST_DIR, "adhanbox_v2.ino")

NEW_INCLUDES = """#include <SPI.h>
#include <SD.h>
#include <AudioOutputI2S.h>
#include <AudioGeneratorMP3.h>
#include <AudioGeneratorWAV.h>
#include <AudioFileSourceSD.h>
#include <AudioFileSourceBuffer.h>"""

SHIM = """// ===== AdhanBox V2 : moteur audio I2S + SD (remplace le DFPlayer) =====
// Broches V2
#define I2S_DIN_PIN   1
#define I2S_LRC_PIN   2
#define I2S_BCLK_PIN  3
#define SD_CS_PIN     10
#define SD_MOSI_PIN   11
#define SD_SCK_PIN    12
#define SD_MISO_PIN   13

// Shim : expose la meme API que DFRobotDFPlayerMini (begin/volume/stop/
// playMp3Folder/available/read/readType) mais joue /mp3/NNNN.mp3 en I2S.
class DFPlayerCompat {
  SPIClass spi{FSPI};
  AudioOutputI2S        *out = nullptr;
  AudioGeneratorMP3     *mp3 = nullptr;
  AudioGeneratorWAV     *wav = nullptr;
  AudioFileSourceSD     *src = nullptr;
  AudioFileSourceBuffer *buf = nullptr;
  float gain = 0.5f;
  bool  sdOk = false;
 public:
  bool begin(Stream &s, bool isACK = true, bool doReset = true) {
    (void)s; (void)isACK; (void)doReset;
    spi.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, SD_CS_PIN);
    sdOk = SD.begin(SD_CS_PIN, spi);
    if (!out) {
      out = new AudioOutputI2S();
      out->SetPinout(I2S_BCLK_PIN, I2S_LRC_PIN, I2S_DIN_PIN);
      out->SetGain(gain);
    }
    return sdOk;          // "DFPlayer dispo" == "SD montee"
  }
  void volume(int v) {                       // 0..30 (echelle DFPlayer) -> gain
    if (v < 0) v = 0; if (v > 30) v = 30;
    gain = (v / 30.0f) * 0.8f;               // 0.8 max pour eviter le clipping
    if (out) out->SetGain(gain);
  }
  void stop() {
    if (mp3) { mp3->stop(); delete mp3; mp3 = nullptr; }
    if (wav) { wav->stop(); delete wav; wav = nullptr; }
    if (buf) { delete buf; buf = nullptr; }
    if (src) { delete src; src = nullptr; }
  }
  bool playPath(const char *path) {
    stop();
    if (!SD.exists(path)) return false;
    src = new AudioFileSourceSD(path);
    buf = new AudioFileSourceBuffer(src, 8192);   // 8KB : sur pour la RAM interne (I2S DMA)
    String p = path; p.toLowerCase();
    if (p.endsWith(".wav")) { wav = new AudioGeneratorWAV(); return wav->begin(buf, out); }
    mp3 = new AudioGeneratorMP3(); return mp3->begin(buf, out);
  }
  void playMp3Folder(int track) {            // compat DFPlayer : /mp3/NNNN.mp3
    char path[24];
    snprintf(path, sizeof(path), "/mp3/%04d.mp3", track);
    if (!playPath(path)) { snprintf(path, sizeof(path), "/MP3/%04d.mp3", track); playPath(path); }
  }
  bool isRunning() { return (mp3 && mp3->isRunning()) || (wav && wav->isRunning()); }
  void pump() {                              // a appeler dans le loop() principal
    if (mp3 && mp3->isRunning()) { if (!mp3->loop()) stop(); }
    if (wav && wav->isRunning()) { if (!wav->loop()) stop(); }
  }
  // API DFPlayer non utilisee en V2 (pas d'evenements serie)
  bool    available() { return false; }
  uint8_t readType()  { return 0; }
  int     read()      { return 0; }
};

DFPlayerCompat dfplayer;

// Constantes d'evenements DFPlayer (compat printDetail ; non utilisees en V2)
enum {
  TimeOut = 1, WrongStack, DFPlayerCardInserted, DFPlayerCardRemoved,
  DFPlayerCardOnline, DFPlayerPlayFinished, DFPlayerError, DFPlayerUSBInserted,
  DFPlayerUSBRemoved, Busy, Sleeping, SerialWrongStack, CheckSumNotMatch,
  FileIndexOut, FileMismatch, Advertise
};"""

# Module V2 : reglages Azkar/Coran (NVS) + scheduler + sync de contenu.
# RAW string (r'''...''') pour preserver les \\" et \\n du code C.
V2_MODULE = r'''
// ============ AdhanBox V2 : Azkar / Coran + sync de contenu ============
#include <HTTPClient.h>

// Pile de la tache loop() agrandie (decodage MP3 = gourmand en pile)
SET_LOOP_TASK_STACK_SIZE(16384);

// Une automatisation : actif, heure, volume (0-30), jours (bitmask bit0=Dim..bit6=Sam)
struct V2Item { bool en; int h, m, vol, days; };
struct { V2Item sabah, masaa, kahf, mulk; } v2cfg;

void v2LoadOne(const char *p, V2Item &it, int defH, int defM, int defDays) {
  char k[16];
  snprintf(k, sizeof(k), "%sEn", p); it.en   = prefs.getBool(k, false);
  snprintf(k, sizeof(k), "%sH",  p); it.h    = prefs.getInt(k, defH);
  snprintf(k, sizeof(k), "%sM",  p); it.m    = prefs.getInt(k, defM);
  snprintf(k, sizeof(k), "%sV",  p); it.vol  = prefs.getInt(k, 20);
  snprintf(k, sizeof(k), "%sD",  p); it.days = prefs.getInt(k, defDays);
}
void v2SaveOne(const char *p, const V2Item &it) {
  char k[16];
  snprintf(k, sizeof(k), "%sEn", p); prefs.putBool(k, it.en);
  snprintf(k, sizeof(k), "%sH",  p); prefs.putInt(k, it.h);
  snprintf(k, sizeof(k), "%sM",  p); prefs.putInt(k, it.m);
  snprintf(k, sizeof(k), "%sV",  p); prefs.putInt(k, it.vol);
  snprintf(k, sizeof(k), "%sD",  p); prefs.putInt(k, it.days);
}
void v2LoadSettings() {
  prefs.begin("v2cfg", true);
  v2LoadOne("sa", v2cfg.sabah, 7,  0, 0x7F);   // tous les jours
  v2LoadOne("ma", v2cfg.masaa, 18, 0, 0x7F);
  v2LoadOne("ka", v2cfg.kahf,  9,  0, 0x20);   // 0x20 = vendredi (bit5)
  v2LoadOne("mu", v2cfg.mulk,  22, 0, 0x7F);
  prefs.end();
}
void v2SaveSettings() {
  prefs.begin("v2cfg", false);
  v2SaveOne("sa", v2cfg.sabah); v2SaveOne("ma", v2cfg.masaa);
  v2SaveOne("ka", v2cfg.kahf);  v2SaveOne("mu", v2cfg.mulk);
  prefs.end();
}

String v2ItemJson(const char *name, const V2Item &it) {
  char b[160];
  snprintf(b, sizeof(b), "\"%s\":{\"en\":%d,\"h\":%d,\"m\":%d,\"vol\":%d,\"days\":%d}",
           name, it.en, it.h, it.m, it.vol, it.days);
  return String(b);
}
void handleGetAzkarCoran() {
  String j = "{" + v2ItemJson("sabah", v2cfg.sabah) + "," + v2ItemJson("masaa", v2cfg.masaa)
           + "," + v2ItemJson("kahf", v2cfg.kahf) + "," + v2ItemJson("mulk", v2cfg.mulk) + "}";
  server.send(200, "application/json", j);
}

static int v2arg(const String &b, const char *k, int def) {
  double v = parseJsonValue(b, k);
  return isnan(v) ? def : (int)v;            // app envoie en/jours en entiers
}
void v2SetOne(const String &b, const char *pfx, V2Item &it) {
  char k[24];
  snprintf(k, sizeof(k), "%s_en",   pfx); it.en   = v2arg(b, k, it.en);
  snprintf(k, sizeof(k), "%s_h",    pfx); it.h    = v2arg(b, k, it.h);
  snprintf(k, sizeof(k), "%s_m",    pfx); it.m    = v2arg(b, k, it.m);
  snprintf(k, sizeof(k), "%s_vol",  pfx); it.vol  = v2arg(b, k, it.vol);
  snprintf(k, sizeof(k), "%s_days", pfx); it.days = v2arg(b, k, it.days);
}
void handleSetAzkarCoran() {
  String b = getRequestBody();
  v2SetOne(b, "sabah", v2cfg.sabah); v2SetOne(b, "masaa", v2cfg.masaa);
  v2SetOne(b, "kahf",  v2cfg.kahf);  v2SetOne(b, "mulk",  v2cfg.mulk);
  v2SaveSettings();
  server.send(200, "text/plain", "OK");
}

void v2ListDir(File dir, String &out, bool &first) {
  for (File f = dir.openNextFile(); f; f = dir.openNextFile()) {
    String nm = f.name();
    if (f.isDirectory()) { if (!nm.startsWith(".")) v2ListDir(f, out, first); }
    else {
      String low = nm; low.toLowerCase();
      if (low.endsWith(".mp3") || low.endsWith(".wav")) {
        if (!first) out += ",";
        out += "\"" + String(f.path()) + "\"";
        first = false;
      }
    }
    f.close();
  }
}
void handleAudioDelete() {
  String path = server.arg("f");
  if (path.length() && SD.exists(path)) { SD.remove(path); server.send(200, "text/plain", "deleted"); }
  else server.send(404, "text/plain", "not found");
}

void handleAudioList() {
  String out = "[";
  bool first = true;
  File root = SD.open("/");
  if (root) { v2ListDir(root, out, first); root.close(); }
  out += "]";
  server.send(200, "application/json", out);
}

// Sync de contenu : telecharge les fichiers MANQUANTS listes dans un manifeste
// texte (1 ligne = "chemin|url"). Permet d'ajouter des duaas/sons a distance.
String _syncMsg = "(idle)";   // diagnostic visible via /api/content/status
static const char *V2_CONTENT_URL =
  "https://raw.githubusercontent.com/adelhanifiOne/adhanbox/main/audio_content.txt";

int v2SyncContent() {
  if (WiFi.status() != WL_CONNECTED) return -1;
#if ENABLE_BLE
  if (_bleActive) stopBLEProvisioning();   // libere la RAM BLE (~60KB) avant le TLS
#endif
  WiFiClientSecure cli; cli.setInsecure();
  HTTPClient http;
  if (!http.begin(cli, V2_CONTENT_URL)) return -1;
  http.setConnectTimeout(15000);
  http.setTimeout(15000);
  http.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
  int mc = http.GET();
  _syncMsg = "manifest=" + String(mc) + " heap=" + String(ESP.getFreeHeap());
  if (mc != 200) { http.end(); return -1; }
  String man = http.getString();
  http.end();

  int added = 0, start = 0;
  while (start < (int)man.length()) {
    int nl = man.indexOf('\n', start);
    String line = (nl < 0) ? man.substring(start) : man.substring(start, nl);
    start = (nl < 0) ? man.length() : nl + 1;
    line.trim();
    if (line.length() < 3 || line.startsWith("#")) continue;
    int bar = line.indexOf('|');
    if (bar < 0) continue;
    String path = line.substring(0, bar); path.trim();
    String url  = line.substring(bar + 1); url.trim();
    if (SD.exists(path)) continue;                       // deja present -> on saute
    // creer les dossiers parents un par un (/a puis /a/b etc.)
    for (int i = 1; i < (int)path.length(); i++) {
      if (path[i] == '/') {
        String d = path.substring(0, i);
        if (!SD.exists(d)) {
          if (!SD.mkdir(d)) { _syncMsg += "(mkdirFail:" + d + ")"; break; }
        }
      }
    }
    WiFiClientSecure c2; c2.setInsecure();
    HTTPClient h2;
    if (!h2.begin(c2, url)) { _syncMsg += " " + path + "=beginFail"; continue; }
    h2.setConnectTimeout(15000);
    h2.setTimeout(60000);                    // 60s pour les gros fichiers archive.org (26Mo+)
    h2.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
    int gc = h2.GET();
    _syncMsg += " " + path + "=" + String(gc);
    if (gc == 200) {
      File f = SD.open(path, FILE_WRITE);
      if (f) {
        h2.writeToStream(&f);                 // streaming -> pas de gros buffer RAM
        f.close();
        added++; _syncMsg += "(ok)"; Serial.printf("[sync] + %s\n", path.c_str());
      } else { _syncMsg += "(openFail)"; }
    }
    h2.end();
  }
  Serial.printf("[sync] %d fichier(s) ajoute(s)\n", added);
  return added;
}
// Synchro lancee en TACHE DE FOND (sinon le download bloque le serveur HTTP
// + watchdog sur les gros fichiers). L'app interroge /api/content/status.
static volatile bool _syncRunning = false;
static volatile int  _syncAdded   = 0;
void _v2SyncTask(void*) {
  _syncRunning = true;
  _syncAdded = v2SyncContent();
  _syncRunning = false;
  vTaskDelete(nullptr);
}
void handleContentSync() {
  if (!_syncRunning) {
    _syncAdded = 0;
    xTaskCreate(_v2SyncTask, "v2sync", 32768, nullptr, 1, nullptr);  // stack large (TLS)
  }
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"status\":\"%s\"}", _syncRunning ? "running" : "started");
  server.send(200, "application/json", buf);
}
void handleContentStatus() {
  String j = "{\"running\":" + String(_syncRunning ? "true" : "false") +
             ",\"added\":" + String(_syncAdded) +
             ",\"msg\":\"" + _syncMsg + "\"}";
  server.send(200, "application/json", j);
}

// Joue une automatisation si : active, bonne heure, bon jour, pas deja jouee aujourd'hui.
void v2Fire(V2Item &it, int h, int m, int dow, int d, int &fired, const char *path) {
  if (dfplayer.isRunning()) return;             // une lecture est deja en cours
  if (!it.en || h != it.h || m != it.m) return;
  if (!((it.days >> dow) & 1)) return;          // pas programmee ce jour
  if (fired == d) return;                       // deja jouee aujourd'hui
  fired = d;
  dfplayer.volume(it.vol);                       // volume propre a l'automatisation
  dfplayer.playPath(path);
}

// Scheduler appele depuis loop() : joue azkar + coran selon les automatisations
void v2Tick() {
  static bool inited = false, synced = false;
  static unsigned long lastCheck = 0;
  static int fSabah = -1, fMasaa = -1, fKahf = -1, fMulk = -1;
  if (!inited) { v2LoadSettings(); inited = true; }
  if (!synced && WiFi.status() == WL_CONNECTED) {  // sync auto au boot, en tache de fond
    synced = true;
    if (!_syncRunning) xTaskCreate(_v2SyncTask, "v2sync", 32768, nullptr, 1, nullptr);
  }
  if (millis() - lastCheck < 1000) return;              // 1x / s
  lastCheck = millis();
  if (dfplayer.isRunning()) return;                     // ne pas couper une lecture
  DateTime now = rtc.now();
  int h = now.hour(), m = now.minute(), d = now.day(), dow = now.dayOfTheWeek(); // 0=Dim..6=Sam
  v2Fire(v2cfg.sabah, h, m, dow, d, fSabah, "/azkar/sabah.mp3");
  v2Fire(v2cfg.masaa, h, m, dow, d, fMasaa, "/azkar/masaa.mp3");
  v2Fire(v2cfg.kahf,  h, m, dow, d, fKahf,  "/quran/al-kahf.mp3");
  v2Fire(v2cfg.mulk,  h, m, dow, d, fMulk,  "/quran/al-mulk.mp3");
}
// ======================= fin module V2 =======================
'''

V2_ROUTES = '''server.on("/api/firmware/version", HTTP_GET, handleFirmwareVersion);
  server.on("/api/azkarcoran", HTTP_GET, handleGetAzkarCoran);
  server.on("/api/azkarcoran", HTTP_POST, handleSetAzkarCoran);
  server.on("/api/content/sync", HTTP_POST, handleContentSync);
  server.on("/api/content/status", HTTP_GET, handleContentStatus);
  server.on("/api/audio/list", HTTP_GET, handleAudioList);
  server.on("/api/audio/delete", HTTP_GET, handleAudioDelete);'''


def apply(text, old, new, expect=1):
    n = text.count(old)
    if n != expect:
        sys.exit(f"ABORT: motif trouvé {n}x (attendu {expect}) : {old[:60]!r}")
    return text.replace(old, new)


def main():
    if not os.path.exists(SRC):
        sys.exit("ABORT: " + SRC + " introuvable")
    t = open(SRC, encoding="utf-8").read()

    # 1) version : 1.4.6 -> 2.0.0 partout, puis marquer le commentaire d'entête
    t = t.replace("1.4.6", "2.0.0")
    t = apply(t, "//Version: 2.0.0", "//Version: 2.0.0 (AdhanBox V2 / HW v2)")

    # 2) marqueur materiel dans les 2 reponses JSON de version
    t = apply(t, '\\"version\\":\\"2.0.0\\",\\"build\\":\\"',
                 '\\"version\\":\\"2.0.0\\",\\"hardware\\":\\"v2\\",\\"build\\":\\"')
    t = apply(t, '\\"version\\":\\"2.0.0\\",\\"hostname\\":',
                 '\\"version\\":\\"2.0.0\\",\\"hardware\\":\\"v2\\",\\"hostname\\":')

    # 3) includes : remplacer le DFPlayer par le bloc audio I2S/SD
    t = apply(t, "#include <DFRobotDFPlayerMini.h>", NEW_INCLUDES)

    # 4) objet dfplayer -> shim I2S
    t = apply(t, "DFRobotDFPlayerMini dfplayer;", SHIM)

    # 5) broches LED + bouton (conflit avec le bus SD en V2)
    t = apply(t, "#define LED_DATA_PIN 13", "#define LED_DATA_PIN 8")
    t = apply(t, "#define CONFIG_BUTTON_PIN 11", "#define CONFIG_BUTTON_PIN 6")

    # 6) desactiver Serial2 (GPIO1/2 = I2S en V2)
    t = apply(t,
        "Serial2.begin(9600, SERIAL_8N1, DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);",
        "// [V2] Serial2 desactive : GPIO1/2 utilises par l'I2S\n  // Serial2.begin(9600, SERIAL_8N1, DFPLAYER_RX_PIN, DFPLAYER_TX_PIN);")

    # 7) pomper le decodage audio + scheduler azkar/coran dans loop()
    t = apply(t, "void loop() {",
                 "void loop() {\n  dfplayer.pump();   // [V2] pompe le decodage audio I2S"
                 "\n  v2Tick();          // [V2] azkar/coran + sync contenu")

    # 8) injecter le module V2 (azkar/coran/sync) juste avant setup()
    t = apply(t, "void setup() {", V2_MODULE + "\nvoid setup() {")

    # 9) enregistrer les routes HTTP V2
    t = apply(t, 'server.on("/api/firmware/version", HTTP_GET, handleFirmwareVersion);',
                 V2_ROUTES)

    # 10z) la tache BLE wifi-scan deborde sa pile (8KB) -> crash pendant la
    #      provisioning (scanNetworks + JSON + notify). On l'agrandit.
    t = apply(t, '"ble_wifi_scan", 8192, nullptr, 1, nullptr',
                 '"ble_wifi_scan", 16384, nullptr, 1, nullptr')

    # 10a) le "wait for errors" post-lecture (800ms) coupait le debut de l'adhan
    #      en I2S -> on pompe le decodeur pendant cette fenetre.
    t = apply(t,
        "  while (millis() - start < 800) {\n"
        "    if (dfLastError != DFERR_NONE) {\n"
        "      // If an error occurs even after recovery, log and stop trying\n"
        "      Serial.printf(\"DFPlayer error after play request: %d\\n\", dfLastError);\n"
        "      break;\n"
        "    }\n"
        "    delay(50);\n"
        "  }",
        "  while (millis() - start < 800) {\n"
        "    dfplayer.pump();   // [V2] decode pendant l'attente -> debut de l'adhan non coupe\n"
        "    delay(2);\n"
        "  }")

    # 10b) stopBLEProvisioning libere AUSSI la RAM du BLE (~60KB) -> dispo pour le TLS
    t = apply(t,
        "  BLEDevice::stopAdvertising();\n  _bleCredsReady = false;",
        "  BLEDevice::stopAdvertising();\n  BLEDevice::deinit(true);   // [V2] libere la RAM BLE\n  _bleCredsReady = false;")

    # 10) declarations anticipees (les routes sont enregistrees AVANT le module V2)
    t = apply(t, "void handlePlayTrack();",
                 "void handlePlayTrack();\n"
                 "void handleGetAzkarCoran();\nvoid handleSetAzkarCoran();\n"
                 "void handleContentSync();\nvoid handleContentStatus();\nvoid handleAudioDelete();\nvoid handleAudioList();")

    os.makedirs(DST_DIR, exist_ok=True)
    open(DST, "w", encoding="utf-8").write(t)
    print("OK ->", DST, f"({len(t)} octets)")


if __name__ == "__main__":
    main()
