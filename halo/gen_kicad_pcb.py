#!/usr/bin/env python3
"""Genere halo/Halo.kicad_pcb (KiCad 10, meme format que AdhanBoxPCBV3.kicad_pcb).

Carte ronde D85 mm avec une languette 14 x 8 mm en bas (dans le pied) qui
porte l'USB-C. Tous les composants sur F.Cu ; F.Cu = face arriere du produit
(composants, LEDs), B.Cu = face avant visible derriere le telephone (plan de
masse plein + logo en serigraphie).

Ce qui est route ici : l'anneau 5V, les 24 arcs de data DOUT -> DIN, les
stubs VDD de chaque LED, l'alimentation de l'anneau depuis F1, R7 -> LED1.
Le centre (module, USB, LDO, boutons) est place ici et route ensuite par
route_center.py ; drc.py verifie le tout. Enchainement complet : build.sh.

Empreintes copiees depuis la V3 : R/C 0805, CP 6.3x5.4, SOT-223, TL3342,
USB-C HRO, test point, pin header, trou de fixation. Empreintes dessinees ici :
ESP32-C3-MINI-1 (land pattern datasheet Espressif fig. 11-1, verifie contre
espressif/kicad-libraries), WS2812B-2020 (datasheet Worldsemi : 1 DO, 2 GND,
3 DI, 4 VDD, pastilles 0.7 x 0.7), SOT-23-5/6, 1206, 0603, LED 0805 aux cotes
des bibliotheques KiCad 10, trou 2.2.

Usage : python3 halo/gen_kicad_pcb.py && python3 halo/route_center.py && python3 halo/drc.py && python3 halo/gen_kicad_libs.py
"""
import math
import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "halo"))
from gen_kicad_sch import parts  # noqa: E402  (ref, lib, value, fp, nets par broche)

V3 = (ROOT / "AdhanBoxPCBV3" / "AdhanBoxPCBV3.kicad_pcb").read_text()
OUT = ROOT / "halo" / "Halo.kicad_pcb"

NS = uuid.UUID("3c9e7d21-5a4b-4f0e-8b6d-1f2a3c4d5e6f")
_n = [0]
def uid(tag=None):
    _n[0] += 1
    return str(uuid.uuid5(NS, tag or f"auto-{_n[0]}"))

def fmt(v):
    v = round(v, 4)
    return str(int(v)) if v == int(v) else repr(v)

# --------------------------------------------------------------------------
# Geometrie de la carte
# --------------------------------------------------------------------------
CX, CY = 150.0, 105.0        # centre du disque sur la feuille A4
R_EDGE = 42.5                # rayon du disque
TAB_W, TAB_BOTTOM = 14.0, 50.5   # languette USB-C : largeur, y max (depuis le centre)
R_LED = 38.0                 # rayon des centres de LED
R_5V = 40.6                  # anneau 5V, largeur 0.8
W_5V = 0.8
R_CAP = 40.0                 # centres des 100nF (radiales, a +/-5 deg de leur LED) ; pad 2 a 0.4 mm de la piste de data
R_HOLE = 30.0                # trous de fixation D2.2
LED_ANGLE0 = 277.5           # LED1 en bas a droite ; LED i a 277.5 + 15 (i-1), sens trigonometrique vu cote composants
                             # (impose par le WS2812B-2020 : VDD et DI du meme cote) ; haut = entre LED12 et LED13
GAP_5V = (266.0, 274.0)      # ouverture de l'anneau 5V en bas, passage des pistes USB
ANT_NOTCH = (-8.0, -35.0, 8.0, -26.9)   # zone sans cuivre sous l'antenne (x1, y1, x2, y2) : zone antenne du module y < -2.9 (datasheet),
                                        # la rangee 36-48 (GND) est a y = -2.2

def led_angle(i):            # degres, sens trigonometrique, 0 = droite, 90 = haut
    return LED_ANGLE0 + 15.0 * (i - 1)

def polar(r, a_deg):         # coordonnees absolues sur la feuille (y vers le bas)
    a = math.radians(a_deg)
    return CX + r * math.cos(a), CY - r * math.sin(a)

def rot_local(x, y, R):      # vecteur local d'une empreinte tournee de R (convention KiCad) -> feuille
    a = math.radians(R)
    return x * math.cos(a) + y * math.sin(a), -x * math.sin(a) + y * math.cos(a)


# --------------------------------------------------------------------------
# Empreintes copiees depuis la V3
# --------------------------------------------------------------------------
def extract_block(text, marker):
    i = text.index(marker)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "(":
            depth += 1
        elif text[j] == ")":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    raise ValueError(marker)

V3_FP = {
    "R_0805": 'R_0805_2012Metric',
    "C_0805": 'C_0805_2012Metric',
    "CP_6.3x5.4": 'CP_Elec_6.3x5.4',
    "SOT-223": 'SOT-223-3_TabPin2',
    "TL3342": 'SW_SPST_TL3342',
    "USB-C": 'USB_C_Receptacle_HRO_TYPE-C-31-M-12',
    "TP": 'TestPoint_Pad_D1.5mm',
    "PH1x02": 'PinHeader_1x02_P2.54mm_Vertical',
    "HOLE3.2": 'MountingHole_3.2mm_M3',
}
TEMPLATES = {k: extract_block(V3, f'(footprint "{v}"') for k, v in V3_FP.items()}

AT_RE = re.compile(r'\(at (-?[\d.]+) (-?[\d.]+)(?: (-?[\d.]+))?\)')

def instantiate(tpl, ref, value, x, y, R, nets, fp_name=None):
    """Place une copie d'une empreinte V3 : position, rotation, reference, nets."""
    m = AT_RE.search(tpl)                      # (at ...) de l'empreinte elle-meme
    Rt = float(m.group(3) or 0)
    head, rest = tpl[:m.start()], tpl[m.end():]
    head = re.sub(r'\(layer "F.Cu"\)\s*\(uuid "[^"]*"\)', '(layer "F.Cu")\n\t\t(uuid "%s")' % uid("fp-" + ref), head, count=1)
    if fp_name:
        head = re.sub(r'^\(footprint "[^"]*"', f'(footprint "{fp_name}"', head)

    def fix_at(mm):                             # angles des pads / textes : retire Rt, ajoute R
        a = (float(mm.group(3) or 0) - Rt + R) % 360
        return f"(at {mm.group(1)} {mm.group(2)}{'' if a == 0 else ' ' + fmt(a)})"
    rest = AT_RE.sub(fix_at, rest)
    rest = re.sub(r'\(property "Reference" "[^"]*"', f'(property "Reference" "{ref}"', rest, count=1)
    rest = re.sub(r'\(property "Value" "[^"]*"', f'(property "Value" "{value}"', rest, count=1)

    def fix_pad(pm):                            # net de chaque pad d'apres le schema
        num, body = pm.group(1), pm.group(2)
        body = re.sub(r'\s*\(net "[^"]*"\)', '', body)
        net = nets.get(num)
        if num == "SH":
            net = nets.get("SH", "GND")
        if net and net != "NC":
            body = body.replace("\n\t\t\t(uuid", f'\n\t\t\t(net "{net}")\n\t\t\t(uuid', 1)
        return f'(pad "{num}"{body}\n\t\t)'
    rest = re.sub(r'\(pad "([^"]*)"(.*?)\n\t\t\)', fix_pad, rest, flags=re.S)
    rest = re.sub(r'\(uuid "[^"]*"\)', lambda _: f'(uuid "{uid()}")', rest)
    at = f"(at {fmt(x)} {fmt(y)}{'' if R % 360 == 0 else ' ' + fmt(R % 360)})"
    return head + at + rest


# --------------------------------------------------------------------------
# Empreintes dessinees ici (format KiCad 10, cotes nominales)
# --------------------------------------------------------------------------
def prop(name, val, x, y, layer, hide=False, size=1.0):
    h = "\n\t\t\t(hide yes)" if hide else ""
    return (f'\t\t(property "{name}" "{val}"\n\t\t\t(at {fmt(x)} {fmt(y)} 0)\n\t\t\t(layer "{layer}"){h}'
            f'\n\t\t\t(uuid "{uid()}")\n\t\t\t(effects\n\t\t\t\t(font\n\t\t\t\t\t(size {size} {size})\n\t\t\t\t\t(thickness 0.15)\n\t\t\t\t)\n\t\t\t)\n\t\t)')

def fp_rect(x1, y1, x2, y2, layer, w):
    return (f'\t\t(fp_rect\n\t\t\t(start {fmt(x1)} {fmt(y1)})\n\t\t\t(end {fmt(x2)} {fmt(y2)})\n\t\t\t(stroke\n\t\t\t\t(width {w})\n\t\t\t\t(type solid)\n\t\t\t)'
            f'\n\t\t\t(fill no)\n\t\t\t(layer "{layer}")\n\t\t\t(uuid "{uid()}")\n\t\t)')

def fp_line(x1, y1, x2, y2, layer, w):
    return (f'\t\t(fp_line\n\t\t\t(start {fmt(x1)} {fmt(y1)})\n\t\t\t(end {fmt(x2)} {fmt(y2)})\n\t\t\t(stroke\n\t\t\t\t(width {w})\n\t\t\t\t(type solid)\n\t\t\t)'
            f'\n\t\t\t(layer "{layer}")\n\t\t\t(uuid "{uid()}")\n\t\t)')

def fp_circle(cx, cy, r, layer, w):
    return (f'\t\t(fp_circle\n\t\t\t(center {fmt(cx)} {fmt(cy)})\n\t\t\t(end {fmt(cx + r)} {fmt(cy)})\n\t\t\t(stroke\n\t\t\t\t(width {w})\n\t\t\t\t(type solid)\n\t\t\t)'
            f'\n\t\t\t(fill no)\n\t\t\t(layer "{layer}")\n\t\t\t(uuid "{uid()}")\n\t\t)')

def smd_pad(num, x, y, sx, sy, R, net, shape="roundrect"):
    rr = "\n\t\t\t(roundrect_rratio 0.25)" if shape == "roundrect" else ""
    n = f'\n\t\t\t(net "{net}")' if net and net != "NC" else ""
    a = "" if R % 360 == 0 else " " + fmt(R % 360)
    return (f'\t\t(pad "{num}" smd {shape}\n\t\t\t(at {fmt(x)} {fmt(y)}{a})\n\t\t\t(size {fmt(sx)} {fmt(sy)})'
            f'\n\t\t\t(layers "F.Cu" "F.Mask" "F.Paste"){rr}{n}\n\t\t\t(uuid "{uid()}")\n\t\t)')

def custom_fp(name, descr, ref, value, x, y, R, pads, gfx, attr="smd", ref_y=-2.0):
    lines = [f'\t(footprint "{name}"', '\t\t(layer "F.Cu")', f'\t\t(uuid "{uid("fp-" + ref)}")',
             f"\t\t(at {fmt(x)} {fmt(y)}{'' if R % 360 == 0 else ' ' + fmt(R % 360)})",
             f'\t\t(descr "{descr}")', '\t\t(tags "halo")',
             prop("Reference", ref, 0, ref_y, "F.SilkS"), prop("Value", value, 0, -ref_y, "F.Fab"),
             prop("Datasheet", "", 0, 0, "F.Fab", hide=True, size=1.27),
             prop("Description", "", 0, 0, "F.Fab", hide=True, size=1.27),
             f"\t\t(attr {attr})", "\t\t(duplicate_pad_numbers_are_jumpers no)", *gfx, *pads,
             "\t\t(embedded_fonts no)", "\t)"]
    return "\n".join(lines)

def fp_two_pad(name, descr, ref, value, x, y, R, nets, pitch, psx, psy, body, court):
    pads = [smd_pad("1", -pitch / 2, 0, psx, psy, R, nets.get("1")),
            smd_pad("2", pitch / 2, 0, psx, psy, R, nets.get("2"))]
    gfx = [fp_rect(-body[0] / 2, -body[1] / 2, body[0] / 2, body[1] / 2, "F.Fab", 0.1),
           fp_rect(-court[0] / 2, -court[1] / 2, court[0] / 2, court[1] / 2, "F.CrtYd", 0.05)]
    return custom_fp(name, descr, ref, value, x, y, R, pads, gfx, ref_y=-(court[1] / 2 + 0.8))

def fp_sot23(n, ref, value, x, y, R, nets):
    """SOT-23-5 / SOT-23-6 : pas 0.95, rangees a +/-1.1375, pastilles 1.325 x 0.6 (= Package_TO_SOT_SMD de KiCad 10)."""
    pos = {1: (-1.1375, -0.95), 2: (-1.1375, 0), 3: (-1.1375, 0.95), 4: (1.1375, 0.95), 5: (1.1375, 0), 6: (1.1375, -0.95)}
    if n == 5:
        del pos[5]; pos[5] = (1.1375, -0.95)
        pos = {1: pos[1], 2: pos[2], 3: pos[3], 4: pos[4], 5: pos[5]}
    pads = [smd_pad(str(k), px, py, 1.325, 0.6, R, nets.get(str(k))) for k, (px, py) in pos.items()]
    gfx = [fp_rect(-0.8, -1.45, 0.8, 1.45, "F.Fab", 0.1), fp_rect(-1.9, -1.75, 1.9, 1.75, "F.CrtYd", 0.05),
           fp_line(-0.8, -1.45, -1.9, -1.45, "F.SilkS", 0.12)]
    return custom_fp(f"Package_TO_SOT_SMD:SOT-23-{n}", f"SOT-23-{n}, cotes KiCad", ref, value, x, y, R, pads, gfx, ref_y=-2.6)

def fp_ws2812b_2020(ref, value, x, y, R, nets):
    """WS2812B-2020 Worldsemi (LCSC C965555), datasheet p.2 : corps 2.2 x 2.0, 4 pastilles 0.7 x 0.7,
    ecart 1.13 entre les deux colonnes, 0.40 entre les deux rangees. Vue de dessus :
    3 DI (-x, -y)  2 GND (+x, -y)
    4 VDD (-x, +y) 1 DO (+x, +y)
    Sur l'anneau : +y local = radial exterieur (VDD et DO dehors), +x local = vers la LED suivante (DO, GND)."""
    pos = {"1": (0.915, 0.55), "2": (0.915, -0.55), "3": (-0.915, -0.55), "4": (-0.915, 0.55)}
    pads = [smd_pad(k, px, py, 0.7, 0.7, R, nets.get(k)) for k, (px, py) in pos.items()]
    gfx = [fp_rect(-1.1, -1.0, 1.1, 1.0, "F.Fab", 0.1), fp_rect(-1.5, -1.4, 1.5, 1.4, "F.CrtYd", 0.05),
           fp_line(1.5, 0.3, 1.5, 1.4, "F.SilkS", 0.12), fp_line(1.5, 1.4, 0.4, 1.4, "F.SilkS", 0.12),   # coin broche 1 (DO)
           fp_line(-1.5, -1.4, -1.5, -0.3, "F.SilkS", 0.12), fp_line(-1.5, -1.4, -0.4, -1.4, "F.SilkS", 0.12)]
    return custom_fp("Halo:LED_WS2812B-2020_PLCC4_2.0x2.0mm", "WS2812B-2020 Worldsemi, datasheet V1.4", ref, value, x, y, R, pads, gfx, ref_y=-2.1)

def fp_esp32c3_mini1(ref, value, x, y, R, nets):
    """ESP32-C3-MINI-1 : corps 13.2 x 16.6, antenne en -y (zone y < -2.9, sans cuivre sous le module ni autour).
    Land pattern de la datasheet Espressif v2.2 fig. 11-1, identique a espressif/kicad-libraries :
    48 broches 0.4 x 0.8 en retrait sous le module (colonnes x = +/-5.9, rangees y = -2.2 et 7.6, pas 0.8),
    masse centrale 3 x 3 pastilles 1.45 (pad 49, un via thermique par pastille), 4 pastilles d'angle 0.7 (50-53)."""
    pads = []
    for k in range(11):                                   # 1..11 colonne gauche, de haut en bas
        pads.append(smd_pad(str(1 + k), -5.9, -1.3 + 0.8 * k, 0.8, 0.4, R, nets.get(str(1 + k)), "rect"))
    for k in range(13):                                   # 12..24 rangee basse, de gauche a droite
        pads.append(smd_pad(str(12 + k), -4.8 + 0.8 * k, 7.6, 0.4, 0.8, R, nets.get(str(12 + k)), "rect"))
    for k in range(11):                                   # 25..35 colonne droite, de bas en haut
        pads.append(smd_pad(str(25 + k), 5.9, 6.7 - 0.8 * k, 0.8, 0.4, R, nets.get(str(25 + k)), "rect"))
    for k in range(13):                                   # 36..48 rangee haute sous la zone antenne, de droite a gauche (GND)
        pads.append(smd_pad(str(36 + k), 4.8 - 0.8 * k, -2.2, 0.4, 0.8, R, nets.get(str(36 + k), "GND"), "rect"))
    for py in (0.725, 2.7, 4.675):                        # 49 : grille 3 x 3 de la masse centrale
        for px in (-1.975, 0, 1.975):
            pads.append(smd_pad("49", px, py, 1.45, 1.45, R, nets.get("49", "GND"), "rect"))
    for n, (px, py) in zip(("50", "51", "52", "53"), ((5.95, -2.25), (5.95, 7.65), (-5.95, 7.65), (-5.95, -2.25))):
        pads.append(smd_pad(n, px, py, 0.7, 0.7, R, nets.get(n, "GND"), "rect"))
    gfx = [fp_rect(-6.6, -8.3, 6.6, 8.3, "F.Fab", 0.1), fp_rect(-6.8, -8.5, 6.8, 8.5, "F.CrtYd", 0.05),
           fp_line(-6.6, -2.9, 6.6, -2.9, "F.Fab", 0.1),       # limite de la zone antenne
           fp_line(-6.8, -8.5, 6.8, -8.5, "F.SilkS", 0.12), fp_line(-6.8, -8.5, -6.8, -2.9, "F.SilkS", 0.12),
           fp_line(6.8, -8.5, 6.8, -2.9, "F.SilkS", 0.12),
           fp_line(-6.8, 8.5, -6.8, 7.7, "F.SilkS", 0.12), fp_line(-6.8, 8.5, -6.0, 8.5, "F.SilkS", 0.12),
           fp_line(6.8, 8.5, 6.8, 7.7, "F.SilkS", 0.12), fp_line(6.8, 8.5, 6.0, 8.5, "F.SilkS", 0.12),
           fp_line(-7.2, -1.3, -6.8, -1.3, "F.SilkS", 0.12)]   # repere broche 1
    return custom_fp("Halo:ESP32-C3-MINI-1", "ESP32-C3-MINI-1, land pattern datasheet Espressif fig. 11-1", ref, value, x, y, R, pads, gfx, ref_y=-9.5)

def fp_hole(ref, x, y, d):
    pad = (f'\t\t(pad "" np_thru_hole circle\n\t\t\t(at 0 0)\n\t\t\t(size {fmt(d)} {fmt(d)})\n\t\t\t(drill {fmt(d)})'
           f'\n\t\t\t(layers "*.Cu" "*.Mask")\n\t\t\t(uuid "{uid()}")\n\t\t)')
    gfx = [fp_circle(0, 0, d / 2 + 0.25, "F.CrtYd", 0.05), fp_circle(0, 0, d / 2, "Cmts.User", 0.15)]
    return custom_fp(f"MountingHole:MountingHole_{d}mm_M2", f"Trou de fixation {d} mm, vis autotaraudeuse M2", ref, f"MountingHole_{d}mm_M2",
                     x, y, 0, [pad], gfx, attr="exclude_from_pos_files exclude_from_bom", ref_y=-(d / 2 + 1.2))


# --------------------------------------------------------------------------
# Placement (coordonnees relatives au centre, y vers le bas, rotation KiCad)
# --------------------------------------------------------------------------
NETS = {p["ref"]: p["nets"] for p in parts}
VALUE = {p["ref"]: p["value"] for p in parts}

PLACE = {   # ref: (x, y, rot)
    "U1": (0, -24, 0),
    "C5": (-10.5, -30, 90), "C4": (-10.5, -26.4, 90), "R1": (-10.5, -22.8, 90), "C6": (-10.5, -19.2, 90),   # le long des broches 3 (3V3) et 8 (EN)
    "R4": (-14, -21, 90),                                                                                  # IO2 (broche 5, colonne gauche)
    "R3": (10.5, -22.8, 90), "R2": (10.5, -19.2, 90),                                                      # IO8, IO9 (rangee basse, a droite)
    "SW1": (-14, -14, 0), "SW2": (-14, -6, 0), "SW3": (14, -14, 0),                                        # positions reprises par gen_coque_pied.py
    "Q1": (-17, -29.4, 0), "R8": (-17, -25.5, 0), "TP4": (-20, -8, 0),
    "J1": (0, 46.6, 0),
    "F1": (-8, 30, 0), "C7": (7, 28, 0), "D1": (0, 27, 0),
    "U2": (-12, 20, 0), "C1": (-18, 14, 90), "C3": (-15, 14, 90), "C2": (-9, 14, 90),
    "R5": (14, 20, 0), "R6": (14, 23.5, 0),
    "TP1": (20, 8, 0), "TP2": (20, 11, 0), "TP3": (20, 14, 0), "J2": (25, 14, 0),
    "U3": (9.5, 33.5, 0), "R7": (3, 33.5, 0), "C8": (14, 30, 90),   # a droite, sous LED1 (en bas a droite)
}
for i in range(1, 25):
    a = led_angle(i)
    x, y = polar(R_LED, a)
    PLACE[f"LED{i}"] = (x - CX, y - CY, (a + 90) % 360)     # +y local = radial vers l'exterieur, +x local = vers la LED suivante (DO)
    ac = a + 5 if i <= 12 else a - 5                          # 100nF a 5 deg de sa LED, jamais dans l'ouverture du bas
    xc, yc = polar(R_CAP, ac)
    PLACE[f"C{9 + i}"] = (xc - CX, yc - CY, (ac + 180) % 360)  # pad 1 (5V) vers l'exterieur, sur l'anneau 5V

KIND = {"R": "R_0805", "C": "C_0805"}
def footprint_of(ref):
    x, y, R = PLACE[ref]
    x, y = CX + x, CY + y
    nets, val = NETS[ref], VALUE[ref]
    if ref == "U1":
        return fp_esp32c3_mini1(ref, val, x, y, R, nets)
    if ref.startswith("LED"):
        return fp_ws2812b_2020(ref, val, x, y, R, nets)
    if ref == "J1":
        return instantiate(TEMPLATES["USB-C"], ref, val, x, y, R, nets)
    if ref == "F1":
        return fp_two_pad("Fuse:Fuse_1206_3216Metric", "Fusible 1206, cotes KiCad", ref, val, x, y, R, nets, 2.8, 1.25, 1.75, (3.2, 1.6), (4.5, 2.3))
    if ref == "D1":
        return fp_sot23(6, ref, val, x, y, R, nets)
    if ref == "U3":
        return fp_sot23(5, ref, val, x, y, R, nets)
    if ref == "U2":
        return instantiate(TEMPLATES["SOT-223"], ref, val, x, y, R, nets)
    if ref == "C7":
        return instantiate(TEMPLATES["CP_6.3x5.4"], ref, val, x, y, R, nets)
    if ref == "Q1":
        return fp_two_pad("LED_SMD:LED_0805_2012Metric", "Phototransistor 0805", ref, val, x, y, R, nets, 1.9, 1.0, 1.45, (2.0, 1.25), (3.4, 1.9))
    if ref.startswith("SW"):
        return instantiate(TEMPLATES["TL3342"], ref, val, x, y, R, nets)
    if ref.startswith("TP"):
        return instantiate(TEMPLATES["TP"], ref, val, x, y, R, nets)
    if ref == "J2":
        return instantiate(TEMPLATES["PH1x02"], ref, val, x, y, R, nets)
    if ref.startswith("C") and int(ref[1:]) >= 10:
        return fp_two_pad("Capacitor_SMD:C_0603_1608Metric", "Condensateur 0603, cotes nominales", ref, val, x, y, R, nets, 1.55, 0.9, 0.95, (1.6, 0.8), (2.9, 1.7))
    if ref.startswith("R"):
        return instantiate(TEMPLATES["R_0805"], ref, val, x, y, R, nets)
    if ref.startswith("C"):
        return instantiate(TEMPLATES["C_0805"], ref, val, x, y, R, nets)
    raise KeyError(ref)

footprints = [footprint_of(p["ref"]) for p in parts if not p["ref"].startswith("#")]
for k, a in enumerate((45, 135, 225, 315), start=1):
    x, y = polar(R_HOLE, a)
    footprints.append(fp_hole(f"H{k}", x, y, 2.2))


# --------------------------------------------------------------------------
# Contour, zones, pistes, textes
# --------------------------------------------------------------------------
def gr_arc(p1, pm, p2, layer, w):
    return (f'\t(gr_arc\n\t\t(start {fmt(p1[0])} {fmt(p1[1])})\n\t\t(mid {fmt(pm[0])} {fmt(pm[1])})\n\t\t(end {fmt(p2[0])} {fmt(p2[1])})'
            f'\n\t\t(stroke\n\t\t\t(width {w})\n\t\t\t(type default)\n\t\t)\n\t\t(layer "{layer}")\n\t\t(uuid "{uid()}")\n\t)')

def gr_line(p1, p2, layer, w):
    return (f'\t(gr_line\n\t\t(start {fmt(p1[0])} {fmt(p1[1])})\n\t\t(end {fmt(p2[0])} {fmt(p2[1])})'
            f'\n\t\t(stroke\n\t\t\t(width {w})\n\t\t\t(type default)\n\t\t)\n\t\t(layer "{layer}")\n\t\t(uuid "{uid()}")\n\t)')

def gr_text(text, x, y, layer, size, thick, mirror=False):
    j = "\n\t\t\t(justify mirror)" if mirror else ""
    return (f'\t(gr_text "{text}"\n\t\t(at {fmt(x)} {fmt(y)} 0)\n\t\t(layer "{layer}")\n\t\t(uuid "{uid()}")'
            f'\n\t\t(effects\n\t\t\t(font\n\t\t\t\t(size {size} {size})\n\t\t\t\t(thickness {thick})\n\t\t\t\tbold\n\t\t\t){j}\n\t\t)\n\t)')

def segment(p1, p2, w, net, layer="F.Cu"):
    return (f'\t(segment\n\t\t(start {fmt(p1[0])} {fmt(p1[1])})\n\t\t(end {fmt(p2[0])} {fmt(p2[1])})\n\t\t(width {w})'
            f'\n\t\t(layer "{layer}")\n\t\t(net "{net}")\n\t\t(uuid "{uid()}")\n\t)')

def arc_track(r, a1, a2, w, net, layer="F.Cu"):
    p1, pm, p2 = polar(r, a1), polar(r, (a1 + a2) / 2), polar(r, a2)
    return (f'\t(arc\n\t\t(start {fmt(p1[0])} {fmt(p1[1])})\n\t\t(mid {fmt(pm[0])} {fmt(pm[1])})\n\t\t(end {fmt(p2[0])} {fmt(p2[1])})\n\t\t(width {w})'
            f'\n\t\t(layer "{layer}")\n\t\t(net "{net}")\n\t\t(uuid "{uid()}")\n\t)')

def zone(net, layer, pts):
    xy = " ".join(f"(xy {fmt(x)} {fmt(y)})" for x, y in pts)
    return (f'\t(zone\n\t\t(net "{net}")\n\t\t(layer "{layer}")\n\t\t(uuid "{uid()}")\n\t\t(hatch edge 0.5)'
            f'\n\t\t(connect_pads yes\n\t\t\t(clearance 0.25)\n\t\t)\n\t\t(min_thickness 0.2)'
            f'\n\t\t(fill yes\n\t\t\t(thermal_gap 0.5)\n\t\t\t(thermal_bridge_width 0.5)\n\t\t\t(island_removal_mode 0)\n\t\t)'
            f'\n\t\t(polygon\n\t\t\t(pts\n\t\t\t\t{xy}\n\t\t\t)\n\t\t)\n\t)')

graphics, tracks, zones = [], [], []

# Contour : arc principal + languette
half = math.degrees(math.asin((TAB_W / 2) / R_EDGE))
a_right, a_left = 270 + half, 270 - half
p_right, p_left = polar(R_EDGE, a_right), polar(R_EDGE, a_left)
graphics.append(gr_arc(p_right, polar(R_EDGE, 90), p_left, "Edge.Cuts", 0.1))
graphics.append(gr_line(p_right, (CX + TAB_W / 2, CY + TAB_BOTTOM), "Edge.Cuts", 0.1))
graphics.append(gr_line((CX + TAB_W / 2, CY + TAB_BOTTOM), (CX - TAB_W / 2, CY + TAB_BOTTOM), "Edge.Cuts", 0.1))
graphics.append(gr_line((CX - TAB_W / 2, CY + TAB_BOTTOM), p_left, "Edge.Cuts", 0.1))

# Serigraphie
graphics.append(gr_text("HALO", CX, CY, "B.SilkS", 6, 0.8, mirror=True))
graphics.append(gr_text("HALO-V1", CX, CY + 4, "F.SilkS", 1.5, 0.25))
graphics.append(gr_text("ANTENNE : pas de cuivre", CX, CY - 38.5, "Cmts.User", 1.0, 0.15))

# Zones GND : disque r = 41.5 + languette, avec une encoche sous l'antenne (fente de 0.6 mm vers le bord)
def gnd_polygon():
    pts = []
    x1, y1, x2, y2 = ANT_NOTCH
    r = R_EDGE - 1.0
    a = 270 + half + 2
    while a < 270 - half + 358:
        if 91 < a % 360 <= 96:                         # detour par l'encoche antenne (a croissant = x decroissant)
            top = CY - r - 1.0                          # depart hors carte : KiCad rogne la zone au contour
            pts += [(CX + 0.3, top), (CX + 0.3, CY + y1), (CX + x2, CY + y1), (CX + x2, CY + y2),
                    (CX + x1, CY + y2), (CX + x1, CY + y1), (CX - 0.3, CY + y1), (CX - 0.3, top)]
        else:
            pts.append(polar(r, a))
        a += 5
    pts += [(CX - TAB_W / 2 + 0.8, CY + TAB_BOTTOM - 0.8), (CX + TAB_W / 2 - 0.8, CY + TAB_BOTTOM - 0.8)]
    return pts
zones.append(zone("GND", "F.Cu", gnd_polygon()))
zones.append(zone("GND", "B.Cu", gnd_polygon()))

# Anneau 5V ouvert en bas, alimente par F1 (pad 2) a son extremite gauche (266 deg)
tracks.append(arc_track(R_5V, GAP_5V[1], GAP_5V[1] + 120, W_5V, "5V"))
tracks.append(arc_track(R_5V, GAP_5V[1] + 120, GAP_5V[1] + 240, W_5V, "5V"))
tracks.append(arc_track(R_5V, GAP_5V[1] + 240, GAP_5V[0] + 360, W_5V, "5V"))
f1x, f1y = CX + PLACE["F1"][0] + 1.4, CY + PLACE["F1"][1]
tracks.append(segment((f1x, f1y), (CX - 2.5, CY + 36), 0.6, "5V"))
tracks.append(segment((CX - 2.5, CY + 36), polar(R_5V, GAP_5V[0]), 0.6, "5V"))

# LEDs : stub VDD vers l'anneau, piste DO -> DI de la suivante
LED_PAD = {"DO": (0.915, 0.55), "GND": (0.915, -0.55), "DI": (-0.915, -0.55), "VDD": (-0.915, 0.55)}
def led_pad(i, name):
    x, y, R = PLACE[f"LED{i}"]
    dx, dy = rot_local(*LED_PAD[name], R)
    return CX + x + dx, CY + y + dy
for i in range(1, 25):
    vdd = led_pad(i, "VDD")
    a_vdd = math.degrees(math.atan2(CY - vdd[1], vdd[0] - CX))
    tracks.append(segment(vdd, polar(R_5V, a_vdd), 0.4, "5V"))
    if i < 24:
        # DO (rangee exterieure, cote suivante) -> DI (rangee interieure, cote precedente) : segment droit,
        # 8 mm de long, pente 1.1 mm, qui passe a 0.4 mm du pad 2 du 100nF intercale
        tracks.append(segment(led_pad(i, "DO"), led_pad(i + 1, "DI"), 0.3, f"LED_DIN{i + 1}"))

# Pastilles d'angle GND du module (50-53) : coincees entre deux broches, la zone ne les atteint pas ;
# petit segment vers la pastille GND voisine, ou vers l'exterieur pour 51 (entre deux NC)
u1x, u1y = CX + PLACE["U1"][0], CY + PLACE["U1"][1]
for (x1, y1), (x2, y2) in (((5.95, -2.25), (4.8, -2.2)), ((-5.95, -2.25), (-4.8, -2.2)),
                           ((-5.95, 7.65), (-5.9, 6.7)), ((5.95, 7.65), (7.05, 8.75))):
    tracks.append(segment((u1x + x1, u1y + y1), (u1x + x2, u1y + y2), 0.3, "GND"))

# R7 -> DI de LED1
tracks.append(segment((CX + PLACE["R7"][0] + 0.9125, CY + PLACE["R7"][1]), led_pad(1, "DI"), 0.3, "LED_DIN1"))


# --------------------------------------------------------------------------
# Assemblage du fichier
# --------------------------------------------------------------------------
header = extract_block(V3, "(general")
layers = extract_block(V3, "(layers")
setup = extract_block(V3, "(setup")
doc = "\n".join([
    "(kicad_pcb",
    "\t(version 20260206)",
    '\t(generator "pcbnew")',
    '\t(generator_version "10.0")',
    "\t" + header, '\t(paper "A4")', "\t" + layers, "\t" + setup,
    *footprints, *graphics, *tracks, *zones,
    ")", "",
])
OUT.write_text(doc)
print(f"{OUT.relative_to(ROOT)} : {len(footprints)} empreintes, {len(tracks)} pistes, {len(zones)} zones, {len(doc)} octets")
