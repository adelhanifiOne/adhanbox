// Driver Epson RX-8025T (I2C RTC, DTCXO ±3.8ppm integre, SOP-14) — AdhanBox V3.
// Remplace le DS3231 de la V2. Expose le sous-ensemble RTClib utilise par le
// firmware (begin/now/adjust/lostPower) — DateTime vient toujours de RTClib.h.
//
// Registres (ETM25E-01) :
//   0x00 SEC  0x01 MIN  0x02 HOUR(24h)  0x03 WEEK(one-hot)  0x04 DAY
//   0x05 MONTH  0x06 YEAR(00-99)  0x07 RAM
//   0x08 MIN Alarm  0x09 HOUR Alarm  0x0A WEEK/DAY Alarm   (bit7 = AE "ignore")
//   0x0B/0x0C Timer   0x0D Extension(TEST,WADA,USEL,TE,FSEL,TSEL)
//   0x0E Flag(UF5,TF4,AF3,VLF1,VDET0)   0x0F Control(CSEL,UIE,TIE,AIE3,RESET0)
// /INT (pin 10, open drain) passe bas quand AF=1 -> GPIO7 (pullup R7 sur PCB V3).
#pragma once
#include <Wire.h>
#include <RTClib.h>   // pour la classe DateTime uniquement

#define RX8025T_ADDR 0x32

// Regs
#define RX_REG_SEC   0x00
#define RX_REG_ALMIN 0x08
#define RX_REG_ALHR  0x09
#define RX_REG_ALWD  0x0A
#define RX_REG_EXT   0x0D
#define RX_REG_FLAG  0x0E
#define RX_REG_CTRL  0x0F
// Bits
#define RX_EXT_WADA  0x40  // 1 = alarme sur jour du mois (pas jour de semaine)
#define RX_FLAG_AF   0x08
#define RX_FLAG_VLF  0x02
#define RX_FLAG_VDET 0x01
#define RX_CTRL_AIE  0x08
#define RX_ALARM_AE  0x80  // bit "ignore ce champ"

static inline uint8_t rxDecToBcd(uint8_t v) { return (uint8_t)((v / 10 * 16) + (v % 10)); }
static inline uint8_t rxBcdToDec(uint8_t v) { return (uint8_t)((v / 16 * 10) + (v % 16)); }

class RX8025T {
 public:
  bool begin() {
    Wire.beginTransmission(RX8025T_ADDR);
    if (Wire.endTransmission() != 0) return false;
    // memorise l'etat "perte d'alim" (VLF) AVANT tout clear pour lostPower()
    _lostPower = (readReg(RX_REG_FLAG) & RX_FLAG_VLF) != 0;
    return true;
  }

  // VLF = oscillateur arrete / donnees perdues (equivalent DS3231 OSF)
  bool lostPower() { return _lostPower; }

  DateTime now() {
    Wire.beginTransmission(RX8025T_ADDR);
    Wire.write((uint8_t)RX_REG_SEC);
    if (Wire.endTransmission(false) != 0) return DateTime((uint32_t)0);
    if (Wire.requestFrom((uint8_t)RX8025T_ADDR, (uint8_t)7) != 7) return DateTime((uint32_t)0);
    uint8_t ss = rxBcdToDec(Wire.read() & 0x7F);
    uint8_t mm = rxBcdToDec(Wire.read() & 0x7F);
    uint8_t hh = rxBcdToDec(Wire.read() & 0x3F);
    Wire.read();                                   // WEEK (one-hot) ignore
    uint8_t d  = rxBcdToDec(Wire.read() & 0x3F);
    uint8_t mo = rxBcdToDec(Wire.read() & 0x1F);
    uint16_t y = 2000 + rxBcdToDec(Wire.read());
    return DateTime(y, mo, d, hh, mm, ss);
  }

  void adjust(const DateTime &dt) {
    Wire.beginTransmission(RX8025T_ADDR);
    Wire.write((uint8_t)RX_REG_SEC);               // l'ecriture des secondes
    Wire.write(rxDecToBcd(dt.second()));           // resynchronise le diviseur
    Wire.write(rxDecToBcd(dt.minute()));
    Wire.write(rxDecToBcd(dt.hour()));
    Wire.write((uint8_t)(1 << dt.dayOfTheWeek())); // WEEK one-hot (0=dimanche)
    Wire.write(rxDecToBcd(dt.day()));
    Wire.write(rxDecToBcd(dt.month()));
    Wire.write(rxDecToBcd((uint8_t)(dt.year() % 100)));
    Wire.endTransmission();
    // heure valide -> effacer les flags de perte d'alim
    uint8_t f = readReg(RX_REG_FLAG);
    writeReg(RX_REG_FLAG, f & ~(RX_FLAG_VLF | RX_FLAG_VDET));
    _lostPower = false;
  }

  // ── acces registres (utilises par les fonctions alarme du .ino) ──────────
  static uint8_t readReg(uint8_t reg) {
    Wire.beginTransmission(RX8025T_ADDR);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return 0;
    if (Wire.requestFrom((uint8_t)RX8025T_ADDR, (uint8_t)1) != 1) return 0;
    return Wire.read();
  }
  static void writeReg(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(RX8025T_ADDR);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
  }

 private:
  bool _lostPower = false;
};
