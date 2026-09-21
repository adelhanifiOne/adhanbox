#!/usr/bin/env python3
"""Genere halo/Halo.kicad_sch (KiCad 10, meme structure que AdhanBoxPCBV3.kicad_sch).

Principe identique a la V3 : symboles places, un label global sur chaque broche
utilisee, aucun fil. Les symboles standard (R, C, SW_Push, USB-C, AMS1117,
TestPoint, Conn_01x02, PWR_FLAG) sont copies verbatim depuis la V3 ; les
symboles propres au Halo (ESP32-C3-MINI-1, WS2812B, USBLC6-2SC6, 74AHCT1G125,
Polyfuse, phototransistor) sont definis ici au format compact.

Usage : python3 halo/gen_kicad_sch.py && python3 halo/gen_kicad_libs.py   (a lancer depuis la racine du repo)
"""
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
V3 = (ROOT / "AdhanBoxPCBV3" / "AdhanBoxPCBV3.kicad_sch").read_text()
OUT = ROOT / "halo" / "Halo.kicad_sch"
PROJECT = "Halo"

# UUID deterministes pour que le fichier soit stable d'une generation a l'autre
NS = uuid.UUID("7a1c5f2e-9b3d-4c8e-a6f1-2d4e6b8c0a1f")
_n = [0]
def uid(tag=None):
    _n[0] += 1
    return str(uuid.uuid5(NS, tag or f"auto-{_n[0]}"))
ROOT_UUID = uid("root")


# --------------------------------------------------------------------------
# Extraction d'un bloc (symbol "X" ...) equilibre depuis la V3
# --------------------------------------------------------------------------
def extract_block(text, start_marker):
    i = text.index(start_marker)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "(":
            depth += 1
        elif text[j] == ")":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    raise ValueError(start_marker)


V3_SYMBOLS = {
    "Device:R": 'Device:R',
    "Device:C": 'Device:C',
    "Switch:SW_Push": 'Switch:SW_Push',
    "Connector:USB_C_Receptacle_USB2.0_16P": 'Connector:USB_C_Receptacle_USB2.0_16P',
    "AdhanBoxV3:AMS1117-3.3": 'AdhanBoxV3:AMS1117-3.3',
    "Connector:TestPoint": 'Connector:TestPoint',
    "Connector_Generic:Conn_01x02": 'Connector_Generic:Conn_01x02',
    "power:PWR_FLAG": 'power:PWR_FLAG',
}
lib_symbols = {}
for name in V3_SYMBOLS:
    blk = extract_block(V3, f'(symbol "{name}"')
    if name == "AdhanBoxV3:AMS1117-3.3":
        blk = blk.replace('(symbol "AdhanBoxV3:AMS1117-3.3"', '(symbol "Halo:AMS1117-3.3"', 1)
        name = "Halo:AMS1117-3.3"
    lib_symbols[name] = blk


# --------------------------------------------------------------------------
# Symboles propres au Halo, format compact (comme AdhanBoxV3:RX8025T)
# --------------------------------------------------------------------------
FX = "(effects (font (size 1.27 1.27)))"
FXH = "(effects (font (size 1.27 1.27)) (hide yes))"

def pin(ptype, x, y, ang, name, num, hide=False):
    h = " (hide yes)" if hide else ""
    return (f'\t\t\t\t(pin {ptype} line (at {x} {y} {ang}) (length 2.54){h} '
            f'(name "{name}" {FX}) (number "{num}" {FX}))')

def compact_symbol(name, ref, value, desc, w, h, pins, extra_gfx=""):
    body = (f'(rectangle (start {-w} {h}) (end {w} {-h}) '
            f'(stroke (width 0.254) (type default)) (fill (type background)))')
    short = name.split(":")[1]
    return "\n".join([
        f'\t\t(symbol "{name}" (pin_names (offset 1.016)) (exclude_from_sim no) (in_bom yes) (on_board yes)',
        f'\t\t\t(property "Reference" "{ref}" (at 0 {h + 3.81} 0) {FX})',
        f'\t\t\t(property "Value" "{value}" (at 0 {-(h + 3.81)} 0) {FX})',
        f'\t\t\t(property "Footprint" "" (at 0 0 0) {FXH})',
        f'\t\t\t(property "Datasheet" "~" (at 0 0 0) {FXH})',
        f'\t\t\t(property "Description" "{desc}" (at 0 0 0) {FXH})',
        f'\t\t\t(symbol "{short}_0_1" {body}{extra_gfx})',
        f'\t\t\t(symbol "{short}_1_1"',
        *pins,
        "\t\t\t)",
        "\t\t)",
    ])


# ESP32-C3-MINI-1 : brochage datasheet Espressif (table "Pin Definitions").
# A VERIFIER contre la datasheet avant de router : les numeros ci-dessous sont
# ceux du module MINI-1 (53 broches), pas du WROOM-02.
ESP_PINS = []
ESP_PINS.append(pin("power_in", 0, 40.64, 270, "3V3", "3"))
gnd_pins = [1, 2, 11, 14] + list(range(36, 54))
for k, n in enumerate(gnd_pins):
    ESP_PINS.append(pin("power_in", 0, -40.64, 90, "GND", str(n), hide=(k > 0)))
left = [("EN", 8, 30.48), ("IO2", 5, 25.4), ("IO8", 22, 20.32), ("IO9", 23, 15.24),
        ("IO3", 6, 10.16), ("IO4", 18, 5.08), ("IO0", 12, 0), ("IO1", 13, -5.08),
        ("IO5", 19, -10.16), ("IO6", 20, -15.24), ("IO7", 21, -20.32)]
for nm, num, y in left:
    ESP_PINS.append(pin("input" if nm == "EN" else "bidirectional", -20.32, y, 0, nm, str(num)))
right = [("IO10", 16, 30.48), ("IO18", 26, 25.4), ("IO19", 27, 20.32),
         ("IO20/RXD0", 30, 10.16), ("IO21/TXD0", 31, 5.08)]
for nm, num, y in right:
    ESP_PINS.append(pin("bidirectional", 20.32, y, 180, nm, str(num)))
nc_pins = [4, 7, 9, 10, 15, 17, 24, 25, 28, 29, 32, 33, 34, 35]
for k, num in enumerate(nc_pins):
    ESP_PINS.append(pin("no_connect", 20.32, -2.54 - 2.54 * k, 180, "NC", str(num)))

lib_symbols["Halo:ESP32-C3-MINI-1"] = compact_symbol(
    "Halo:ESP32-C3-MINI-1", "U", "ESP32-C3-MINI-1",
    "Module Wi-Fi + BLE ESP32-C3, antenne PCB, 4 MB flash, pre-certifie RED",
    17.78, 38.1, ESP_PINS)

lib_symbols["Halo:WS2812B"] = compact_symbol(
    "Halo:WS2812B", "LED", "WS2812B",
    "LED RGB adressable 2 x 2 Worldsemi, 4 broches : 1 DO, 2 GND, 3 DI, 4 VDD. WS2812C-2020-V1 (le WS2812B-2020 est arrete) : meme boitier, meme brochage",
    5.08, 5.08, [
        pin("output", 7.62, 0, 180, "DO", "1"),
        pin("power_in", 0, -7.62, 90, "GND", "2"),
        pin("input", -7.62, 0, 0, "DI", "3"),
        pin("power_in", 0, 7.62, 270, "VDD", "4"),
    ])

lib_symbols["Halo:USBLC6-2SC6"] = compact_symbol(
    "Halo:USBLC6-2SC6", "D", "USBLC6-2SC6",
    "Protection ESD USB 2 lignes, SOT-23-6",
    7.62, 5.08, [
        pin("passive", -10.16, 2.54, 0, "I/O1", "1"),
        pin("passive", 0, -7.62, 90, "GND", "2"),
        pin("passive", -10.16, -2.54, 0, "I/O2", "3"),
        pin("passive", 10.16, -2.54, 180, "I/O2", "4"),
        pin("passive", 0, 7.62, 270, "VBUS", "5"),
        pin("passive", 10.16, 2.54, 180, "I/O1", "6"),
    ])

lib_symbols["Halo:74AHCT1G125"] = compact_symbol(
    "Halo:74AHCT1G125", "U", "74AHCT1G125",
    "Buffer 3 etats 1 porte, entree TTL : translateur 3V3 vers 5V, SOT-23-5",
    7.62, 5.08, [
        pin("input", -10.16, -2.54, 0, "~{OE}", "1"),
        pin("input", -10.16, 2.54, 0, "A", "2"),
        pin("power_in", 0, -7.62, 90, "GND", "3"),
        pin("tri_state", 10.16, 0, 180, "Y", "4"),
        pin("power_in", 0, 7.62, 270, "VCC", "5"),
    ])

lib_symbols["Halo:Polyfuse"] = compact_symbol(
    "Halo:Polyfuse", "F", "Polyfuse",
    "Fusible rearmable PTC",
    1.016, 2.54, [
        pin("passive", 0, 3.81, 270, "", "1"),
        pin("passive", 0, -3.81, 90, "", "2"),
    ],
    extra_gfx=' (polyline (pts (xy -1.016 -2.54) (xy 1.016 2.54)) (stroke (width 0) (type default)) (fill (type none)))')

# ---- v2 : negociation 9 V, buck 5 V, LDO 3V3, self (datasheets WCH CH224 V2.0, Aerosemi MT2492, Diodes AP2112K)
lib_symbols["Halo:CH224A"] = compact_symbol(
    "Halo:CH224A", "U", "CH224A",
    "Recepteur USB PD : demande 9 V au chargeur par CC1/CC2 (Rset 6.8k sur CFG1), ESSOP-10 a pad thermique",
    12.7, 15.24, [
        pin("power_in", 0, -17.78, 90, "GND", "0"),
        pin("power_in", 0, 17.78, 270, "VHV", "1"),
        pin("input", -15.24, 10.16, 0, "CFG2/SCL", "2"),
        pin("input", -15.24, 5.08, 0, "CFG3/SDA", "3"),
        pin("bidirectional", -15.24, 0, 0, "DP", "4"),
        pin("bidirectional", -15.24, -5.08, 0, "DM", "5"),
        pin("bidirectional", 15.24, -5.08, 180, "CC2", "6"),
        pin("bidirectional", 15.24, 0, 180, "CC1", "7"),
        pin("input", 15.24, 10.16, 180, "VBUS", "8"),
        pin("input", -15.24, -10.16, 0, "CFG1", "9"),
        pin("open_collector", 15.24, 5.08, 180, "~{PG}", "10"),
    ])

lib_symbols["Halo:MT2492"] = compact_symbol(
    "Halo:MT2492", "U", "MT2492",
    "Buck synchrone 2 A, 4.5 a 16 V, 600 kHz, reference 0.6 V, SOT-23-6",
    10.16, 10.16, [
        pin("passive", 12.7, 5.08, 180, "BS", "1"),
        pin("power_in", 0, -12.7, 90, "GND", "2"),
        pin("input", -12.7, -5.08, 0, "FB", "3"),
        pin("input", -12.7, 0, 0, "EN", "4"),
        pin("power_in", -12.7, 5.08, 0, "IN", "5"),
        pin("output", 12.7, -5.08, 180, "SW", "6"),
    ])

lib_symbols["Halo:AP2112K"] = compact_symbol(
    "Halo:AP2112K", "U", "AP2112K-3.3",
    "LDO 3.3 V 600 mA a faible chute (250 mV), SOT-23-5 : tient le 3V3 quand le buck ne sort que 4.6 V",
    7.62, 5.08, [
        pin("power_in", -10.16, 2.54, 0, "VIN", "1"),
        pin("power_in", 0, -7.62, 90, "GND", "2"),
        pin("input", -10.16, -2.54, 0, "EN", "3"),
        pin("no_connect", 10.16, -2.54, 180, "NC", "4"),
        pin("power_out", 10.16, 2.54, 180, "VOUT", "5"),
    ])

lib_symbols["Halo:L"] = compact_symbol(
    "Halo:L", "L", "L",
    "Self de puissance",
    1.016, 2.54, [
        pin("passive", 0, 3.81, 270, "", "1"),
        pin("passive", 0, -3.81, 90, "", "2"),
    ])

lib_symbols["Halo:Q_Photo_NPN"] = compact_symbol(
    "Halo:Q_Photo_NPN", "Q", "Q_Photo_NPN",
    "Phototransistor NPN, capteur de lumiere ambiante",
    3.81, 3.81, [
        pin("passive", 0, 6.35, 270, "C", "1"),
        pin("passive", 0, -6.35, 90, "E", "2"),
    ])


# --------------------------------------------------------------------------
# Lecture des broches d'un symbole (coordonnees lib, y vers le haut)
# --------------------------------------------------------------------------
PIN_RE = re.compile(
    r'\(pin\s+\w+\s+\w+\s*\(at\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)\)'
    r'.*?\(number\s+"([^"]+)"', re.S)

def lib_pins(lib_id):
    """-> dict numero -> (x, y, angle) en coordonnees lib."""
    out = {}
    for m in PIN_RE.finditer(lib_symbols[lib_id]):
        out.setdefault(m.group(4), (float(m.group(1)), float(m.group(2)), int(m.group(3))))
    return out


# --------------------------------------------------------------------------
# Placement : (ref, lib_id, value, footprint, x, y, {numero_broche: net})
# net "NC" -> croix de non-connexion ; net absent -> broche laissee libre
# --------------------------------------------------------------------------
FP = {
    "R": "Resistor_SMD:R_0805_2012Metric",
    "C": "Capacitor_SMD:C_0805_2012Metric",
    "C0603": "Capacitor_SMD:C_0603_1608Metric",
    "CP": "Capacitor_SMD:CP_Elec_6.3x5.4",
    "SW": "Button_Switch_SMD:SW_SPST_TL3342",
    "TP": "TestPoint:TestPoint_Pad_D1.5mm",
    "J2": "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical",
}
USBC = "Connector:USB_C_Receptacle_USB2.0_16P"

parts = []
def P(ref, lib, value, fp, x, y, nets, dnp=False, in_bom=True):
    parts.append(dict(ref=ref, lib=lib, value=value, fp=fp, x=x, y=y, nets=nets, dnp=dnp, in_bom=in_bom))

# ---- Feuille 1 : USB-C, protection, 5V, 3V3 (zone haut gauche) ----
P("J1", USBC, "USB-C 16P", "Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12",
  38.1, 66.04, {"A4": "VBUS", "A9": "VBUS", "B4": "VBUS", "B9": "VBUS",
                "A5": "CC1", "B5": "CC2", "A6": "USB_DP", "B6": "USB_DP",
                "A7": "USB_DM", "B7": "USB_DM", "A8": "NC", "B8": "NC",
                "A1": "GND", "A12": "GND", "B1": "GND", "B12": "GND", "SH": "GND"})
# v2 (16/09/2026, HALO_V2.md) : le bus apres fusible est a 9 V (VBUS_F), negocie par U4 ; un buck U5 en tire le 5 V des
# LEDs ; le 3V3 vient d'un LDO a faible chute. La prise USB-C reste la seule entree, le module Qi est alimente en 9 V par J3.
P("F1", "Halo:Polyfuse", "2.5A 16V", "Fuse:Fuse_1812_4532Metric", 76.2, 45.72, {"1": "VBUS", "2": "VBUS_F"})
P("D1", "Halo:USBLC6-2SC6", "USBLC6-2SC6", "Package_TO_SOT_SMD:SOT-23-6", 127, 66.04,
  {"1": "USB_DP", "3": "USB_DM", "2": "GND", "5": "5V", "6": "USB_DP", "4": "USB_DM"})   # VBUS de la diode : 5.25 V max, donc sur le 5 V
P("C7", "Device:C", "100uF", FP["CP"], 152.4, 66.04, {"1": "5V", "2": "GND"})
P("U2", "Halo:AP2112K", "AP2112K-3.3", "Package_TO_SOT_SMD:SOT-23-5", 190.5, 66.04,
  {"1": "5V", "2": "GND", "3": "5V", "4": "NC", "5": "3V3"})
# negociation PD : Rset 6.8k sur CFG1 = 9 V (table 5-1), CFG2/CFG3 en l'air, DP/DM non relies (ils restent a l'ESP32 pour
# le flashage : le CH224 ne s'en sert que pour QC, dont on se passe), PG non utilise
P("U4", "Halo:CH224A", "CH224A", "Package_SO:SSOP-10_3.9x4.9mm_P1.00mm", 88.9, 106.68,
  {"0": "GND", "1": "VBUS_F", "8": "VBUS_F", "7": "CC1", "6": "CC2", "9": "CFG1",
   "2": "NC", "3": "NC", "4": "NC", "5": "NC", "10": "NC"})
P("C34", "Device:C", "1uF", FP["C"], 63.5, 106.68, {"1": "VBUS_F", "2": "GND"})
P("R9", "Device:R", "6.8k", FP["R"], 116.84, 106.68, {"1": "CFG1", "2": "GND"})
# buck 5 V : Vout = 0.6 x (1 + R10/R11) = 4.98 V ; EN par pont 100k/100k (EN limite a 6 V, VBUS_F vaut 9 V) ;
# self 4.7 uH 3.9 A, ondulation ~0.8 A a 9 V ; sortie filtree par C1 10 uF + C7 100 uF
P("U5", "Halo:MT2492", "MT2492", "Package_TO_SOT_SMD:SOT-23-6", 162.56, 106.68,
  {"5": "VBUS_F", "4": "EN_BUCK", "1": "BS", "6": "SW", "3": "FB", "2": "GND"})
P("C36", "Device:C", "10uF", FP["C"], 137.16, 106.68, {"1": "VBUS_F", "2": "GND"})
P("C35", "Device:C", "100nF", FP["C"], 187.96, 96.52, {"1": "BS", "2": "SW"})
P("L1", "Halo:L", "4.7uH", "Inductor_SMD:L_Taiyo-Yuden_NR-50xx", 200.66, 106.68, {"1": "SW", "2": "5V"})
P("R10", "Device:R", "100k", FP["R"], 213.36, 106.68, {"1": "5V", "2": "FB"})
P("R11", "Device:R", "13.7k", FP["R"], 223.52, 106.68, {"1": "FB", "2": "GND"})
P("R12", "Device:R", "100k", FP["R"], 137.16, 91.44, {"1": "VBUS_F", "2": "EN_BUCK"})
P("R13", "Device:R", "100k", FP["R"], 147.32, 91.44, {"1": "EN_BUCK", "2": "GND"})
# module Qi certifie : deux trous pour ses fils, 9 V et masse (HALO_V2.md, chapitre 3)
P("J3", "Connector_Generic:Conn_01x02", "Module Qi VIN / GND", FP["J2"], 243.84, 106.68, {"1": "VBUS_F", "2": "GND"}, dnp=True, in_bom=False)
P("C1", "Device:C", "10uF", FP["C"], 170.18, 86.36, {"1": "5V", "2": "GND"})
P("C3", "Device:C", "100nF", FP["C"], 180.34, 86.36, {"1": "5V", "2": "GND"})
P("C2", "Device:C", "10uF", FP["C"], 208.28, 86.36, {"1": "3V3", "2": "GND"})
P("J2", "Connector_Generic:Conn_01x02", "5V / GND alt", FP["J2"], 236.22, 66.04, {"1": "5V", "2": "GND"}, dnp=True, in_bom=False)
P("TP1", "Connector:TestPoint", "5V", FP["TP"], 256.54, 66.04, {"1": "5V"}, dnp=True, in_bom=False)
P("TP2", "Connector:TestPoint", "3V3", FP["TP"], 266.7, 66.04, {"1": "3V3"}, dnp=True, in_bom=False)
P("TP3", "Connector:TestPoint", "GND", FP["TP"], 276.86, 66.04, {"1": "GND"}, dnp=True, in_bom=False)
P("TP4", "Connector:TestPoint", "EN", FP["TP"], 287.02, 66.04, {"1": "EN"}, dnp=True, in_bom=False)
P("#FLG1", "power:PWR_FLAG", "PWR_FLAG", "", 25.4, 30.48, {"1": "5V"}, in_bom=False)
P("#FLG2", "power:PWR_FLAG", "PWR_FLAG", "", 40.64, 30.48, {"1": "GND"}, in_bom=False)
P("#FLG3", "power:PWR_FLAG", "PWR_FLAG", "", 55.88, 30.48, {"1": "VBUS_F"}, in_bom=False)

# ---- Feuille 2 : module, strapping, boutons, capteur (zone milieu) ----
P("U1", "Halo:ESP32-C3-MINI-1", "ESP32-C3-MINI-1-N4", "Halo:ESP32-C3-MINI-1", 68.58, 157.48,
  {"3": "3V3", "1": "GND", "2": "GND", "11": "GND", "14": "GND", "8": "EN", "5": "STRAP_IO2", "22": "STRAP_IO8", "23": "BOOT",
   "6": "BTN_USER", "18": "ALS", "16": "LED_DATA_3V3", "26": "USB_DM", "27": "USB_DP",
   "12": "NC", "13": "NC", "19": "NC", "20": "NC", "21": "NC", "30": "NC", "31": "NC"})
P("R1", "Device:R", "10k", FP["R"], 121.92, 129.54, {"1": "3V3", "2": "EN"})
P("C6", "Device:C", "1uF", FP["C"], 132.08, 129.54, {"1": "EN", "2": "GND"})
P("SW1", "Switch:SW_Push", "RESET", FP["SW"], 149.86, 129.54, {"1": "EN", "2": "GND"})
P("R4", "Device:R", "10k", FP["R"], 172.72, 129.54, {"1": "3V3", "2": "STRAP_IO2"})
P("R3", "Device:R", "10k", FP["R"], 185.42, 129.54, {"1": "3V3", "2": "STRAP_IO8"})
P("R2", "Device:R", "10k", FP["R"], 208.28, 129.54, {"1": "3V3", "2": "BOOT"})
P("SW2", "Switch:SW_Push", "BOOT", FP["SW"], 226.06, 129.54, {"1": "BOOT", "2": "GND"})
P("SW3", "Switch:SW_Push", "USER", FP["SW"], 254, 129.54, {"1": "BTN_USER", "2": "GND"})
P("C5", "Device:C", "10uF", FP["C"], 121.92, 160.02, {"1": "3V3", "2": "GND"})
P("C4", "Device:C", "100nF", FP["C"], 132.08, 160.02, {"1": "3V3", "2": "GND"})
P("Q1", "Halo:Q_Photo_NPN", "ALS-PT19-315C", "LED_SMD:LED_0805_2012Metric", 172.72, 160.02, {"1": "3V3", "2": "ALS"}, dnp=True)
P("R8", "Device:R", "10k", FP["R"], 185.42, 160.02, {"1": "ALS", "2": "GND"})

# ---- Feuille 3 : translateur + anneau de 24 LEDs (zone basse) ----
P("U3", "Halo:74AHCT1G125", "74AHCT1G125", "Package_TO_SOT_SMD:SOT-23-5", 40.64, 226.06,
  {"2": "LED_DATA_3V3", "1": "GND", "3": "GND", "4": "LED_DATA_5V", "5": "5V"})
P("C8", "Device:C", "100nF", FP["C"], 63.5, 226.06, {"1": "5V", "2": "GND"})
P("R7", "Device:R", "330R", FP["R"], 76.2, 226.06, {"1": "LED_DATA_5V", "2": "LED_DIN1"})
for i in range(1, 25):
    row, col = divmod(i - 1, 12)
    x, y = 106.68 + col * 25.4, 226.06 + row * 27.94
    P(f"LED{i}", "Halo:WS2812B", "WS2812C-2020-V1", "Halo:LED_WS2812B-2020_PLCC4_2.0x2.0mm",
      x, y, {"4": "5V", "3": f"LED_DIN{i}", "1": (f"LED_DIN{i + 1}" if i < 24 else "NC"), "2": "GND"})
for i in range(1, 25):
    P(f"C{9 + i}", "Device:C", "100nF", FP["C0603"], 40.64 + (i - 1) * 12.7, 283.21, {"1": "5V", "2": "GND"})


# --------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------
def main():
    def fmt(v):
        v = round(v, 4)
        return str(int(v)) if v == int(v) else repr(v)

    JUSTIFY = {0: "left", 90: "left", 180: "right", 270: "right"}
    sym_out, lbl_out, nc_out = [], [], []

    for p in parts:
        pins = lib_pins(p["lib"])
        X, Y = p["x"], p["y"]
        lines = [
            "\t(symbol",
            f'\t\t(lib_id "{p["lib"]}")',
            f"\t\t(at {fmt(X)} {fmt(Y)} 0)",
            "\t\t(unit 1)",
            "\t\t(exclude_from_sim no)",
            f'\t\t(in_bom {"yes" if p["in_bom"] else "no"})',
            "\t\t(on_board yes)",
            f'\t\t(dnp {"yes" if p["dnp"] else "no"})',
            "\t\t(fields_autoplaced yes)",
            f'\t\t(uuid "{uid("sym-" + p["ref"])}")',
            f'\t\t(property "Reference" "{p["ref"]}"',
            f"\t\t\t(at {fmt(X)} {fmt(Y - 12)} 0)",
            f"\t\t\t{FX}",
            "\t\t)",
            f'\t\t(property "Value" "{p["value"]}"',
            f"\t\t\t(at {fmt(X)} {fmt(Y + 12)} 0)",
            f"\t\t\t{FX}",
            "\t\t)",
            f'\t\t(property "Footprint" "{p["fp"]}"',
            f"\t\t\t(at {fmt(X)} {fmt(Y)} 0)",
            f"\t\t\t{FXH}",
            "\t\t)",
            '\t\t(property "Datasheet" "~"',
            f"\t\t\t(at {fmt(X)} {fmt(Y)} 0)",
            f"\t\t\t{FXH}",
            "\t\t)",
            '\t\t(property "Description" ""',
            f"\t\t\t(at {fmt(X)} {fmt(Y)} 0)",
            f"\t\t\t{FXH}",
            "\t\t)",
        ]
        for num in pins:
            lines += [f'\t\t(pin "{num}"', f'\t\t\t(uuid "{uid("pin-" + p["ref"] + "-" + num)}")', "\t\t)"]
        lines += [
            "\t\t(instances",
            f'\t\t\t(project "{PROJECT}"',
            f'\t\t\t\t(path "/{ROOT_UUID}"',
            f'\t\t\t\t\t(reference "{p["ref"]}")',
            "\t\t\t\t\t(unit 1)",
            "\t\t\t\t)",
            "\t\t\t)",
            "\t\t)",
            "\t)",
        ]
        sym_out.append("\n".join(lines))

        done_pos = set()
        for num, net in p["nets"].items():
            if num not in pins:
                raise KeyError(f"{p['ref']} : broche {num} absente du symbole {p['lib']}")
            px, py, ang = pins[num]
            sx, sy = X + px, Y - py          # y du symbole vers le haut, y de la feuille vers le bas
            if (sx, sy) in done_pos:
                continue                     # broches empilees (VBUS x4, GND...) : un seul label
            done_pos.add((sx, sy))
            if net == "NC":
                nc_out.append("\n".join([
                    "\t(no_connect",
                    f"\t\t(at {fmt(sx)} {fmt(sy)})",
                    f'\t\t(uuid "{uid("nc-" + p["ref"] + "-" + num)}")',
                    "\t)"]))
                continue
            la = (ang + 180) % 360
            lbl_out.append("\n".join([
                f'\t(global_label "{net}"',
                "\t\t(shape bidirectional)",
                f"\t\t(at {fmt(sx)} {fmt(sy)} {la})",
                f"\t\t(effects (font (size 1.27 1.27)) (justify {JUSTIFY[la]}))",
                f'\t\t(uuid "{uid("lbl-" + p["ref"] + "-" + num)}")',
                "\t)"]))

    texts = [
        (25.4, 15.24, "Halo v1 : support telephone a anneau lumineux (derive AdhanBox V3)"),
        (25.4, 38.1, "1. Entree USB-C, protection ESD, fusible, rail 5V et 3V3"),
        (25.4, 110.49, "2. Module ESP32-C3-MINI-1, strapping (IO2/IO8/IO9), boutons RESET/BOOT/USER, capteur de lumiere"),
        (25.4, 208.28, "3. Translateur 3V3->5V et anneau de 24 LED WS2812B-2020 en face arriere (chaine LED1..LED24), C10..C33 = une 100nF par LED"),
    ]
    txt_out = []
    for x, y, t in texts:
        txt_out.append("\n".join([
            f'\t(text "{t}"',
            "\t\t(exclude_from_sim no)",
            f"\t\t(at {fmt(x)} {fmt(y)} 0)",
            "\t\t(effects (font (size 2.54 2.54) bold) (justify left bottom))",
            f'\t\t(uuid "{uid("txt-" + t)}")',
            "\t)"]))

    doc = "\n".join([
        "(kicad_sch",
        "\t(version 20260306)",
        '\t(generator "eeschema")',
        '\t(generator_version "10.0")',
        f'\t(uuid "{ROOT_UUID}")',
        '\t(paper "A3")',
        "\t(lib_symbols",
        *lib_symbols.values(),
        "\t)",
        *txt_out,
        *nc_out,
        *sym_out,
        *lbl_out,
        "\t(sheet_instances",
        '\t\t(path "/"',
        '\t\t\t(page "1")',
        "\t\t)",
        "\t)",
        ")",
        "",
    ])
    OUT.write_text(doc)
    print(f"{OUT.relative_to(ROOT)} : {len(parts)} symboles, {len(lbl_out)} labels, {len(nc_out)} NC, {len(doc)} octets")


if __name__ == "__main__":
    main()
