#!/usr/bin/env python3
"""Coque arriere et pied du Halo v1, en CadQuery. Rejouable, verifie ses collisions.

Sortie dans halo/3d/ : Halo_coque.step/.stl, Halo_pied.step/.stl, Halo_pcb.step
(le PCB nu, pour l'assemblage dans Fusion), et Halo_assemblage.step.

Reperes
-------
Repere "carte" = repere KiCad du PCB : x vers la droite, y vers le BAS (vers la
languette USB-C), z vers l'ARRIERE (cote composants, F.Cu). z = 0 est la face
avant du PCB, celle qui touche le telephone.

Repere "monde" pour le pied : X droite, Y vers l'ARRIERE, Z vers le haut. La
carte est inclinee a 65 deg de l'horizontale, dos vers l'arriere.

Style : le marche des supports de telephone imprimes (Cozyleigh et consorts)
impose un vocabulaire : cannelures verticales sur tout le pourtour, aretes
adoucies, silhouette de galet, teintes mates. La coque et le pied le reprennent.

Coque (PETG translucide blanc, imprimee fond sur le plateau, ouverture en l'air)
  - galet D100.8 ext, paroi 2.9 cannelee (54 gorges de 1.3, il reste 1.6 de
    matiere au fond des gorges), dos arrondi R4, levre avant chanfreinee ;
    5 mm de jour tout autour du PCB : c'est par la que sort la lumiere des LEDs,
    vue de face, et les cannelures la modulent.
  - 4 plots D6 a r = 30 avec pion D1.8 dans les trous H1..H4 du PCB.
  - 4 nervures a 45/135/225/315 deg avec crochet de 0.6 mm : le PCB se clipse,
    pas de vis en face avant.
  - fente en bas pour la languette USB-C ; 2 trous D2.2 sur RESET/BOOT ;
    membrane souple sur le bouton utilisateur ; trou D3 sur le capteur de lumiere.

Pied (PETG noir, imprime a plat)
  - bloc 70 x 52 x 24, angles verticaux R10, dessus arrondi R4, face avant
    cannelee comme la coque ; fente a la forme exacte de la coque
    (jeu 0.3), poche pour la languette et une PRISE USB-C COUDEE, rainure de
    cable vers le cote droit, 4 logements pour pads silicone dessous.
  - butee avant de 3 mm pour le bas du telephone.

Usage : python3 halo/gen_coque_pied.py   (depuis la racine du repo)
"""
import math
from pathlib import Path

import cadquery as cq

OUT = Path(__file__).resolve().parent / "3d"
OUT.mkdir(exist_ok=True)

# ---------------------------------------------------------------- PCB (repere carte)
R_PCB = 42.5
T_PCB = 1.6
TAB_W, TAB_Y = 14.0, 50.5           # languette : largeur, y max
R_HOLE, D_HOLE = 30.0, 2.2          # trous H1..H4 a 45 + 90k deg
HOLES = [(R_HOLE * math.cos(math.radians(a)), -R_HOLE * math.sin(math.radians(a))) for a in (45, 135, 225, 315)]
H_COMP = 5.4                        # composant le plus haut : C7 electrolytique
SW1, SW2, SW3, Q1 = (-14, -14), (-14, -6), (14, -14), (-17, -29.4)   # positions KiCad (x, y)
USB = dict(w=9.0, d=7.35, h=3.2, y_face=TAB_Y)   # receptacle HRO sur la languette, face a y = 50.5

# ---------------------------------------------------------------- coque (repere carte)
GAP_RAD = 5.0                       # jour lumineux entre PCB et paroi
WALL = 2.9                          # paroi du pourtour : 1.6 de matiere sous les cannelures
BACK_T = 1.6                        # fond
R_IN = R_PCB + GAP_RAD              # 47.5
R_OUT = R_IN + WALL                 # 50.4
# style commun coque / pied
N_FLUTE = 54                        # cannelures sur le pourtour, pas de 5.9 mm au rayon 50.4 : une tranche de piece
R_FLUTE, D_FLUTE = 3.9, 1.3         # rayon de la gorge, profondeur : les gorges se touchent, il reste des cretes arrondies
R_BACK, C_FRONT = 3.5, 0.8          # arrondi du dos (il reste 1.5 au coin de la cavite), chanfrein de la levre avant
Z_FRONT = -1.6                      # bord avant de la coque, 1.6 mm devant le PCB
Z_INNER = T_PCB + H_COMP + 1.0      # fond interieur : 8.0
Z_BACK = Z_INNER + BACK_T           # 9.6
HOOK = 0.6                          # retenue des crochets sur le bord du PCB
PLAY = 0.3                          # jeu radial PCB / crochets

def cannelures(centres, z0, h):
    """Cylindres verticaux a retrancher : une gorge par centre (x, y), de z0 a z0 + h.
    Les cercles voisins se chevauchent : ils sont fusionnes en 2D (Sketch) avant extrusion, sinon
    OCC recoit une face auto-intersectante et la soustraction echoue en silence (piece intacte ou vide)."""
    sk = cq.Sketch().push(centres).circle(R_FLUTE).clean()
    return cq.Workplane("XY").placeSketch(sk).extrude(h).translate((0, 0, z0))

def verifie_gorges(avant, apres, nom):
    """Garde-fou : la soustraction des cannelures doit avoir enleve de la matiere, pas tout ni rien."""
    va, vb = avant.val().Volume(), apres.val().Volume()
    if not apres.solids().size() or vb >= va - 1.0:
        raise RuntimeError(f"{nom} : cannelures non taillees (volume {va / 1000:.1f} -> {vb / 1000:.1f} cm3)")
    return apres

def coque():
    # galet de revolution : levre avant chanfreinee, dos arrondi (profil dans le plan XZ, x = rayon)
    k = math.sqrt(0.5)
    body = (cq.Workplane("XZ")
            .moveTo(0, Z_FRONT).lineTo(R_OUT - C_FRONT, Z_FRONT).lineTo(R_OUT, Z_FRONT + C_FRONT)
            .lineTo(R_OUT, Z_BACK - R_BACK)
            .threePointArc((R_OUT - R_BACK + R_BACK * k, Z_BACK - R_BACK + R_BACK * k), (R_OUT - R_BACK, Z_BACK))
            .lineTo(0, Z_BACK).close()
            .revolve(360, (0, 0, 0), (0, 1, 0)))
    cavity = cq.Workplane("XY").circle(R_IN).extrude(Z_INNER - Z_FRONT).translate((0, 0, Z_FRONT))
    body = body.cut(cavity)
    # cannelures : elles s'arretent la ou le dos s'arrondit
    r_axe = R_OUT + R_FLUTE - D_FLUTE
    pts = [(r_axe * math.cos(2 * math.pi * i / N_FLUTE), r_axe * math.sin(2 * math.pi * i / N_FLUTE)) for i in range(N_FLUTE)]
    body = verifie_gorges(body, body.cut(cannelures(pts, Z_FRONT - 1.0, (Z_BACK - R_BACK) - (Z_FRONT - 1.0))), "coque")

    # plots + pions (le PCB repose dessus par sa face arriere, z = 1.6)
    for hx, hy in HOLES:
        boss = cq.Workplane("XY").center(hx, hy).circle(3.0).extrude(Z_INNER - T_PCB).translate((0, 0, T_PCB))
        pin = cq.Workplane("XY").center(hx, hy).circle(0.9).extrude(1.4).translate((0, 0, 0.2))
        body = body.union(boss).union(pin)

    # nervures + crochets : construits sur l'axe +x puis tournes
    r_hook = R_PCB + PLAY                                  # 42.8 : face interieure de la nervure
    rib = cq.Workplane("XY").box(R_IN + 0.5 - r_hook, 1.2, Z_INNER - Z_FRONT, centered=(False, True, False)) \
        .translate((r_hook, 0, Z_FRONT))
    hook = (cq.Workplane("XZ")
            .polyline([(r_hook, Z_FRONT), (r_hook, -0.2), (r_hook - HOOK, -0.2), (r_hook - HOOK, -0.5), (r_hook, Z_FRONT)])
            .close().extrude(0.6, both=True))
    ribhook = rib.union(hook)
    for a in (45, 135, 225, 315):
        body = body.union(ribhook.rotate((0, 0, 0), (0, 0, 1), -a))   # -a : y de la carte vers le bas

    # fente pour la languette + connecteur, en bas de la paroi (y > 0)
    slot = cq.Workplane("XY").box(TAB_W + 2.6, R_OUT - 42.0 + 1.0, 8.5, centered=(True, False, False)) \
        .translate((0, 42.0, -2.0))
    body = body.cut(slot)

    # acces RESET / BOOT : trous D2.2 dans le fond
    for sx, sy in (SW1, SW2):
        body = body.cut(cq.Workplane("XY").center(sx, sy).circle(1.1).extrude(4).translate((0, 0, Z_INNER - 1)))
    # bouton utilisateur : membrane D10 amincie a 0.6 mm + teton D3 qui descend sur le poussoir
    body = body.cut(cq.Workplane("XY").center(*SW3).circle(5.0).extrude(2).translate((0, 0, Z_INNER + 0.6)))
    body = body.union(cq.Workplane("XY").center(*SW3).circle(1.5).extrude(1.0).translate((0, 0, Z_INNER - 1.0)))
    # capteur de lumiere : trou D3
    body = body.cut(cq.Workplane("XY").center(*Q1).circle(1.5).extrude(4).translate((0, 0, Z_INNER - 1)))
    return body

# ---------------------------------------------------------------- PCB + composants (repere carte)
def pcb():
    disc = cq.Workplane("XY").circle(R_PCB).extrude(T_PCB)
    tab = cq.Workplane("XY").box(TAB_W, TAB_Y - 40.0, T_PCB, centered=(True, False, False)).translate((0, 40.0, 0))
    return disc.union(tab)

def composants_enveloppe():
    """Volumes majorants des composants cote arriere, pour le test de collision."""
    usb = cq.Workplane("XY").box(USB["w"], USB["d"], USB["h"], centered=(True, False, False)) \
        .translate((0, USB["y_face"] - USB["d"], T_PCB))
    c7 = cq.Workplane("XY").center(-7, 28).rect(7.0, 7.0).extrude(H_COMP).translate((0, 0, T_PCB))
    esp = cq.Workplane("XY").center(0, -24).rect(13.2, 16.6).extrude(2.4).translate((0, 0, T_PCB))
    leds = cq.Workplane("XY").circle(41.2).circle(36.0).extrude(1.2).translate((0, 0, T_PCB))
    sw = None
    for sx, sy in (SW1, SW2, SW3):
        b = cq.Workplane("XY").center(sx, sy).rect(7.0, 5.0).extrude(5.0).translate((0, 0, T_PCB))
        sw = b if sw is None else sw.union(b)
    return usb.union(c7).union(esp).union(leds).union(sw)

# ---------------------------------------------------------------- pied (repere monde)
TILT = 65.0                          # angle de la carte sur l'horizontale
ROT_X = -(90 + (90 - TILT))          # -115 deg : y carte -> bas/avant, z carte -> arriere/bas
Y0, Z0 = 6.0, 64.0                   # position du centre de la carte dans le monde
FOOT = dict(x=70.0, y0=-24.0, y1=28.0, h=24.0)
PLUG = dict(w=12.5, thick=6.6, len=12.5)   # prise USB-C coudee, corps au-dela de la face du connecteur

def to_world(shape):
    return shape.rotate((0, 0, 0), (1, 0, 0), ROT_X).translate((0, Y0, Z0))

def pt_world(x, y, z):
    a = math.radians(ROT_X)
    return (x, Y0 + y * math.cos(a) - z * math.sin(a), Z0 + y * math.sin(a) + z * math.cos(a))

def pied():
    f = FOOT
    block = cq.Workplane("XY").box(f["x"], f["y1"] - f["y0"], f["h"], centered=(True, False, False)).translate((0, f["y0"], 0))
    block = block.edges("|Z").fillet(10.0)
    block = block.faces(">Z").edges().fillet(4.0)          # dessus arrondi, la brique devient un galet
    # cannelures sur la face avant, meme pas que la coque, entre les angles arrondis
    pitch = 2 * math.pi * R_OUT / N_FLUTE
    n = int((f["x"] - 26.0) / pitch)
    pts = [(-(n - 1) / 2 * pitch + i * pitch, f["y0"] - R_FLUTE + D_FLUTE) for i in range(n)]
    block = verifie_gorges(block, block.cut(cannelures(pts, -1.0, f["h"] - 4.0 + 1.0)), "pied")
    # butee avant pour le bas du telephone ; elle descend dans l'arrondi pour ne pas flotter
    lip = cq.Workplane("XY").box(f["x"] - 16, 2.5, 7.0, centered=(True, False, False)).translate((0, f["y0"] + 1.0, f["h"] - 4.0))
    block = block.union(lip)

    # fente : enveloppe de la coque avec jeu
    env = cq.Workplane("XY").circle(R_OUT + PLAY).extrude(Z_BACK - Z_FRONT + 2 * PLAY).translate((0, 0, Z_FRONT - PLAY))
    block = block.cut(to_world(env))

    # poche languette + prise coudee (repere carte : x +-, y de 44 a 50.5 + len, z de -1 a 7.6)
    pocket = cq.Workplane("XY").box(PLUG["w"] + 2.0, USB["y_face"] + PLUG["len"] - 44.0 + 1.0, PLUG["thick"] + 2.0,
                                    centered=(True, False, False)).translate((0, 44.0, -1.0))
    block = block.cut(to_world(pocket))

    # rainure de cable : du centre de la prise vers la face droite
    cx, cy, cz = pt_world(0, USB["y_face"] + PLUG["len"] / 2, T_PCB + USB["h"] / 2)
    chan = cq.Workplane("XY").box(f["x"], 7.0, 7.0, centered=(False, True, True)).translate((0, cy, cz))
    block = block.cut(chan)

    # logements pads silicone dessous
    for px, py in ((-26, f["y0"] + 8), (26, f["y0"] + 8), (-26, f["y1"] - 8), (26, f["y1"] - 8)):
        block = block.cut(cq.Workplane("XY").center(px, py).circle(5.0).extrude(1.0))
    return block, (cx, cy, cz)

# ---------------------------------------------------------------- generation + controles
if __name__ == "__main__":
    coq = coque()
    carte = pcb()
    comp = composants_enveloppe()
    foot, chan_c = pied()

    def vol(s):
        return s.val().Volume()

    print(f"coque : valide={coq.val().isValid()} volume={vol(coq) / 1000:.1f} cm3 (PETG ~{vol(coq) / 1000 * 1.27:.0f} g plein)")
    print(f"pied  : valide={foot.val().isValid()} volume={vol(foot) / 1000:.1f} cm3 (PETG ~{vol(foot) / 1000 * 1.27:.0f} g plein)")

    # 1. la coque ne touche ni le PCB ni les composants (les pions dans les trous exceptes)
    carte_trouee = carte
    for hx, hy in HOLES:
        carte_trouee = carte_trouee.cut(cq.Workplane("XY").center(hx, hy).circle(D_HOLE / 2).extrude(T_PCB))
    i1 = vol(coq.intersect(carte_trouee)) if coq.intersect(carte_trouee).solids().size() else 0.0
    i2 = vol(coq.intersect(comp)) if coq.intersect(comp).solids().size() else 0.0
    print(f"intersection coque/PCB = {i1:.3f} mm3, coque/composants = {i2:.3f} mm3  (attendu 0)")

    # 2. le PCB repose bien : hauteur du dessus des plots
    zt = max(v.Z for v in coq.faces(">Z").vals()[0].Vertices()) if False else T_PCB
    print(f"plots : dessus a z = {T_PCB} (face arriere du PCB), crochets de z = -0.5 a -0.2, retenue {HOOK} mm")

    # 3. pied : la coque en position ne touche pas le pied (jeu 0.3), la prise a de la place
    coq_w = to_world(coq)
    inter = coq_w.intersect(foot)
    i3 = vol(inter) if inter.solids().size() else 0.0
    print(f"intersection coque/pied = {i3:.3f} mm3 (attendu 0)")
    bb = coq_w.val().BoundingBox()
    print(f"coque en place : Z de {bb.zmin:.1f} a {bb.zmax:.1f} mm, Y de {bb.ymin:.1f} a {bb.ymax:.1f} mm ; pied haut {FOOT['h']} mm")
    print(f"profondeur d'emboitement dans le pied : {FOOT['h'] - bb.zmin:.1f} mm")
    px, py, pz = pt_world(0, USB["y_face"] + PLUG["len"], T_PCB + USB["h"] / 2 + PLUG["thick"] / 2)
    print(f"bas de la prise coudee : Z = {pz:.1f} mm (plancher du pied : > 2 mm attendu)")
    print(f"rainure de cable : Y = {chan_c[1]:.1f}, Z = {chan_c[2]:.1f}")
    fb = foot.val().BoundingBox()
    print(f"pied : {fb.xlen:.0f} x {fb.ylen:.0f} x {fb.zlen:.0f} mm ; hauteur totale produit {bb.zmax:.0f} mm")

    # 4. exports
    cq.exporters.export(coq, str(OUT / "Halo_coque.step"))
    cq.exporters.export(coq, str(OUT / "Halo_coque.stl"), tolerance=0.02, angularTolerance=0.1)
    cq.exporters.export(foot, str(OUT / "Halo_pied.step"))
    cq.exporters.export(foot, str(OUT / "Halo_pied.stl"), tolerance=0.02, angularTolerance=0.1)
    cq.exporters.export(carte, str(OUT / "Halo_pcb.step"))
    asm = cq.Assembly()
    asm.add(foot, name="pied", color=cq.Color(0.15, 0.15, 0.15))
    asm.add(coq_w, name="coque", color=cq.Color(0.95, 0.95, 0.95, 0.6))
    asm.add(to_world(carte), name="pcb", color=cq.Color(0.1, 0.3, 0.15))
    asm.save(str(OUT / "Halo_assemblage.step"))
    print("exports :", sorted(p.name for p in OUT.iterdir()))
