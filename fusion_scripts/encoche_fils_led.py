# -*- coding: utf-8 -*-
"""
Encoche de passage des fils LED — support_led
=============================================
Le trou carre de la dalle du support (35 x 35 mm, lamage 39,4 mm ou la carte
LED se pose) n'a aucun passage pour les fils : ils devaient etre pinces entre
la carte et la dalle. Ce script ouvre une encoche sur UN cote du carre, celui
qui regarde le port USB-C de la coque — la carte principale et ses
connecteurs sont dessous, les fils descendent tout droit.

Comme fermeture_aimantee.py, rien n'est code en dur : le carre est mesure sur
la boucle interieure de la face du dessous, le cote est choisi en lisant la
coque (ou est le percage rond D13 du port USB-C), et l'encoche est posee
depuis le bord du carre. Rejouable : si `Encoche_fils_LED` existe deja, le
script ne fait rien.

Resultat attendu (valide le 05/09/2026, en local support) :
  - cote +X du carre (X = 61,50), encoche X 61,50 -> 67,50 (6 mm de fond),
    Y 39,50 -> 59,50 (20 mm, centree sur le carre), traversante Z 0 -> 5.
  - elle franchit le lamage (bord de carte a X = 63,70) avec 3,8 mm de marge :
    les fils passent SOUS la carte, pas contre son bord.
  - rien d'autre a cet endroit : plots d'aimant a X ~ 78,5, vis a X = 83.

Cotes : LARGEUR 20 mm (demande d'Adel), FOND 6 mm (assez pour trois fils
en nappe, sans entamer la zone des plots).
"""

import adsk.core, adsk.fusion

LARGEUR = 20.0    # le long du cote du carre
FOND    = 6.0     # de l'arete du carre vers l'exterieur
NOM     = 'Encoche_fils_LED'
CUT = adsk.fusion.FeatureOperations.CutFeatureOperation


def find(o):
    if o.bRepBodies.count:
        return o
    for c in o.childOccurrences:
        r = find(c)
        if r:
            return r


def run(_context: str):
    app = adsk.core.Application.get()
    des = adsk.fusion.Design.cast(app.activeProduct)
    root = des.rootComponent
    hs = find([o for o in root.occurrences if o.name.startswith('support_led')][0])
    comp = hs.component
    for i in range(comp.features.count):
        if comp.features.item(i).name == NOM:
            print(NOM, ': deja presente, rien a faire')
            return
    b = comp.bRepBodies.item(0)

    # ---------- 1) le trou carre : boucle interieure ~35 mm de la face du dessous ----------
    zmin = b.boundingBox.minPoint.z * 10
    carre = None
    for f in b.faces:
        g = f.geometry
        if not isinstance(g, adsk.core.Plane) or abs(g.normal.z) < .99:
            continue
        if abs(g.origin.z * 10 - zmin) > 0.05:
            continue
        for li in range(f.loops.count):
            lp = f.loops.item(li)
            if lp.isOuter:
                continue
            lb = lp.boundingBox
            w = (lb.maxPoint.x - lb.minPoint.x) * 10
            h = (lb.maxPoint.y - lb.minPoint.y) * 10
            if 30 < w < 40 and 30 < h < 40 and lp.edges.count == 4:
                carre = (lb.minPoint.x * 10, lb.maxPoint.x * 10, lb.minPoint.y * 10, lb.maxPoint.y * 10)
    if carre is None:
        raise RuntimeError('trou carre 35 x 35 introuvable sur la face du dessous')
    x0, x1, y0, y1 = carre
    # epaisseur de la dalle : la plus haute face horizontale sous 10 mm
    ztop = max(f.geometry.origin.z * 10 for f in b.faces
               if isinstance(f.geometry, adsk.core.Plane) and abs(f.geometry.normal.z) > .99
               and f.geometry.origin.z * 10 < zmin + 10)
    print('CARRE : X %.2f..%.2f  Y %.2f..%.2f | dalle Z %.2f -> %.2f' % (x0, x1, y0, y1, zmin, ztop))

    # ---------- 2) le cote : celui qui regarde le port USB-C de la coque ----------
    coque = root.bRepBodies.itemByName('AdhanBox_Fusion')
    usb = None
    for f in coque.faces:
        g = f.geometry
        if isinstance(g, adsk.core.Cylinder) and abs(g.axis.z) < .01 and 12 < g.radius * 20 < 14:
            usb = (g.origin.x * 10, g.origin.y * 10, 'X' if abs(g.axis.x) > .99 else 'Y')
    if usb is None:
        raise RuntimeError('port USB-C D13 introuvable sur la coque')
    # offset local -> monde du support
    off = hs.bRepBodies.item(0).boundingBox.minPoint
    loc = comp.bRepBodies.item(0).boundingBox.minPoint
    ox, oy = (off.x - loc.x) * 10, (off.y - loc.y) * 10
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    ux, uy = usb[0] - ox, usb[1] - oy            # port USB en coordonnees support
    if usb[2] == 'X':
        cote = '+X' if ux > cx else '-X'
    else:
        cote = '+Y' if uy > cy else '-Y'
    print('USB-C coque a (%.1f, %.1f) monde -> cote %s du carre' % (usb[0], usb[1], cote))

    # ---------- 3) rectangle de l'encoche, a cheval sur l'arete du carre ----------
    if cote == '+X':
        rx0, rx1, ry0, ry1 = x1 - 0.5, x1 + FOND, cy - LARGEUR / 2, cy + LARGEUR / 2
    elif cote == '-X':
        rx0, rx1, ry0, ry1 = x0 - FOND, x0 + 0.5, cy - LARGEUR / 2, cy + LARGEUR / 2
    elif cote == '+Y':
        rx0, rx1, ry0, ry1 = cx - LARGEUR / 2, cx + LARGEUR / 2, y1 - 0.5, y1 + FOND
    else:
        rx0, rx1, ry0, ry1 = cx - LARGEUR / 2, cx + LARGEUR / 2, y0 - FOND, y0 + 0.5
    # (0,5 mm de recouvrement dans le vide du carre : pas d'arete coincidente)

    pi = comp.constructionPlanes.createInput()
    pi.setByOffset(comp.xYConstructionPlane, adsk.core.ValueInput.createByReal((zmin - 1.0) / 10.0))
    pl = comp.constructionPlanes.add(pi); pl.name = 'PL_' + NOM
    sk = comp.sketches.add(pl); sk.name = 'ESQ_' + NOM
    P = lambda x, y: sk.modelToSketchSpace(adsk.core.Point3D.create(x / 10.0, y / 10.0, (zmin - 1.0) / 10.0))
    sk.sketchCurves.sketchLines.addTwoPointRectangle(P(rx0, ry0), P(rx1, ry1))
    if sk.profiles.count != 1:
        raise RuntimeError('encoche : %d profils' % sk.profiles.count)
    ei = comp.features.extrudeFeatures.createInput(sk.profiles.item(0), CUT)
    ei.setDistanceExtent(False, adsk.core.ValueInput.createByReal((ztop - zmin + 2.0) / 10.0))
    ei.participantBodies = [b]
    f = comp.features.extrudeFeatures.add(ei); f.name = NOM
    print('  + %s : cote %s, X %.2f..%.2f  Y %.2f..%.2f, traversante Z %.2f -> %.2f'
          % (NOM, cote, max(rx0, x0), min(rx1, x1) if cote.startswith('-') else rx1, ry0, ry1, zmin, ztop))

    # ---------- 4) preuve : la boucle du dessous a pris la forme du carre + encoche ----------
    for ff in b.faces:
        g = ff.geometry
        if isinstance(g, adsk.core.Plane) and abs(g.normal.z) > .99 and abs(g.origin.z * 10 - zmin) < .05:
            for li in range(ff.loops.count):
                lp = ff.loops.item(li)
                lb = lp.boundingBox
                if not lp.isOuter and (lb.maxPoint.x - lb.minPoint.x) * 10 > 30 and (lb.maxPoint.y - lb.minPoint.y) * 10 > 30:
                    print('  ouverture du dessous apres coupe : X %.2f..%.2f  Y %.2f..%.2f  (%d aretes)'
                          % (lb.minPoint.x * 10, lb.maxPoint.x * 10, lb.minPoint.y * 10, lb.maxPoint.y * 10, lp.edges.count))
    print('\nPense a ENREGISTRER le document.')
