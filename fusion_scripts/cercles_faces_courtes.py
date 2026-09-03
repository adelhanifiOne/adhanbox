"""
Ecart arche / cercle sur les faces courtes du boitier AdhanBox.

PROBLEME (constate a l'impression, 03/09/2026)
Les 4 arches (12 mm de large) et les 3 cercles (D5) sont identiques sur les
quatre faces. Mais la face courte n'a que 95,2 mm de large contre 106 mm pour
la face longue : le motif y est serre a un pas de 19 mm au lieu de 21 mm.
L'ecart arche/cercle tombait a 2,03 mm au lieu de 2,94 mm, et cette paroi
mince s'imprimait mal.

POURQUOI ON NE PEUT PAS SIMPLEMENT ECARTER LE MOTIF
Les angles portent un conge R8 sur toute la hauteur (centres en 8,8 / 87,8 /
87,98 / 8,98). La partie PLATE de la face courte ne fait donc que 79 mm
(X = 8 a 87). Le motif espace comme sur les faces longues occuperait 75 mm :
il ne resterait que 2 mm jusqu'au conge de chaque cote. Impossible.

CORRECTIF
Les 3 cercles des faces courtes passent de D5 a D3. L'ecart remonte a 3,01 mm,
soit un peu plus que les faces longues (2,94 mm) qui s'impriment bien. Les
arches, motif signature, ne bougent pas. Les cercles des faces longues restent
en D5.

Esquisse4 pilote les deux faces courtes (plan XZ), Esquisse6 les deux faces
longues (plan YZ). Les deux esquisses sont libres : ni cote ni contrainte, le
rayon se regle donc directement.

REJOUABLE : ne fait rien si les cercles sont deja au bon rayon.
"""

import adsk.core
import adsk.fusion

RAYON_COURT_MM = 1.5   # D3 sur les faces courtes
RAYON_LONG_MM = 2.5    # D5 sur les faces longues, inchange


def _esquisse_faces_courtes(root):
    """L'esquisse des faces courtes : celle du plan XZ qui porte des cercles."""
    for s in root.sketches:
        if s.sketchCurves.sketchCircles.count == 0:
            continue
        if s.referencePlane == root.xZConstructionPlane:
            return s
    raise RuntimeError("esquisse des faces courtes introuvable (plan XZ avec cercles)")


def _paroi_la_plus_fine(app, body, mur):
    """Matiere minimale entre un petit trou et l'ouverture voisine, en mm.

    On ne retient que les flancs d'ouverture : surfaces prismatiques dans
    l'epaisseur du mur. Les deux peaux du mur toucheraient les trous (0 mm) et
    fausseraient la mesure.
    """
    axe, rayon = ('y', RAYON_COURT_MM) if mur == 'Y0' else ('x', RAYON_LONG_MM)
    flancs = []
    for i in range(body.faces.count):
        f = body.faces.item(i)
        bb, g = f.boundingBox, f.geometry
        if bb.maxPoint.z * 10 < 60 or bb.minPoint.z * 10 > 90:
            continue                                    # hors de la bande haute
        lo = (bb.minPoint.y if axe == 'y' else bb.minPoint.x) * 10
        hi = (bb.maxPoint.y if axe == 'y' else bb.maxPoint.x) * 10
        if lo > 0.05 or hi > 3.05:
            continue                                    # pas dans ce mur
        composante = (lambda v: v.y) if axe == 'y' else (lambda v: v.x)
        prisme = ((isinstance(g, adsk.core.Cylinder) and abs(composante(g.axis)) > .99)
                  or (isinstance(g, adsk.core.Plane) and abs(composante(g.normal)) < .01))
        if prisme:
            flancs.append(f)
    trous = [f for f in flancs if isinstance(f.geometry, adsk.core.Cylinder)
             and abs(f.geometry.radius * 10 - rayon) < 0.01]
    mm = app.measureManager
    return min(mm.measureMinimumDistance(t, a).value * 10
               for t in trous for a in flancs if a != t)


def run(_context: str):
    app = adsk.core.Application.get()
    des = adsk.fusion.Design.cast(app.activeProduct)
    root = des.rootComponent

    sk = _esquisse_faces_courtes(root)
    cible = RAYON_COURT_MM / 10.0                       # l'API travaille en cm
    change = 0
    for c in sk.sketchCurves.sketchCircles:
        if abs(c.radius - cible) > 1e-6:
            c.radius = cible
            change += 1
    print(f"{sk.name} : {change} cercle(s) ramene(s) a D{RAYON_COURT_MM * 2:.0f} "
          f"({sk.sketchCurves.sketchCircles.count} au total)")

    body = root.bRepBodies.itemByName('AdhanBox_Fusion')
    court = _paroi_la_plus_fine(app, body, 'Y0')
    long_ = _paroi_la_plus_fine(app, body, 'X0')
    print(f"  face courte (95,2 mm) : paroi la plus fine {court:.3f} mm   attendu 3,013")
    print(f"  face longue (106 mm)  : paroi la plus fine {long_:.3f} mm   attendu 2,940")
    if court < long_:
        print("  ATTENTION : la face courte est encore plus fine que la face longue")
    else:
        print("  OK : la face courte n'est plus le point faible")
    print("\nPense a ENREGISTRER le document.")
