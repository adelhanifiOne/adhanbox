# -*- coding: utf-8 -*-
"""
Encoche de passage des fils LED — support_led
=============================================
Le trou carre de la dalle du support (35 x 35 mm, lamage 39,4 mm ou la carte
LED se pose) n'a aucun passage pour les fils : ils devaient etre pinces entre
la carte et la dalle. Ce script ouvre une saignee sur UN cote du carre, celui
qui regarde le port USB-C de la coque — la carte principale et ses
connecteurs sont dessous, les fils descendent tout droit.

LARGEUR REDUITE, MAIS TRAVERSANTE (corrige le 18/09/2026, demande d'Adel)
La premiere version etait trop large : elle mordait jusqu'a X 67,5, bien
au-dela du lamage, et enlevait de la matiere la ou la dalle est pleine sur
5 mm. Desormais la saignee part de l'EPAULEMENT du lamage (Z = 3 en local) et
descend jusqu'au DESSOUS de la dalle : elle debouche, les fils montent du
dessous jusque sous la carte sans etre pinces.

ELLE S'ARRETE AU BORD DU LAMAGE (X 63,70). C'est la que se termine la zone
ouverte au-dessus, donc la que les fils cessent d'etre pinces par la carte.
Aller au-dela n'apporterait rien et entamerait la dalle pleine. La borne est
mesuree sur le lamage, pas choisie.

Comme fermeture_aimantee.py, rien n'est code en dur : le carre est mesure sur
la boucle interieure de la face du dessous, l'epaulement sur la face de
39,4 x 39,4, le cote est choisi en lisant la coque (ou est le percage rond D13
du port USB-C). Rejouable : si `Encoche_fils_LED` existe deja, rien n'est fait.

TOUT EN COORDONNEES LOCALES. L'occurrence support_led est translatee de
(3,50 / 3,50 / 45,00) : mesurer en monde et construire en local fait couper
45 mm au-dessus de la piece, dans le vide (erreur commise le 18/09/2026, la
coupe ne creait aucune face). Utiliser comp.bRepBodies, jamais occ.bRepBodies.

Resultat attendu (valide le 18/09/2026, en local support) :
  - cote +X du carre, saignee X 61,00 -> 63,70 (bord du lamage),
    Y 39,50 -> 59,50 (20 mm, centree), Z 3,00 -> 0,00 : TRAVERSANTE.
  - epaulement ramene de 327,4 a 283,4 mm2.
  - dessous de dalle : son ouverture s'elargit de 2,2 x 20 mm (preuve que la
    saignee debouche bien). Si elle reste a 7427,1 mm2, la coupe n'a pas
    traverse.
"""

import adsk.core, adsk.fusion

LARGEUR = 20.0      # le long du cote du carre (demande d'Adel)
# La profondeur n'est pas figee : la saignee descend de l'epaulement jusqu'au
# dessous de la dalle, mesure sur la piece. Elle DOIT deboucher.
NOM = 'Encoche_fils_LED'
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
    b = comp.bRepBodies.item(0)          # LOCAL — voir l'avertissement du docstring

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

    # ---------- 2) l'epaulement du lamage : ou la carte se pose, et ou la rainure s'arrete ----------
    lam = None
    for f in b.faces:
        g = f.geometry
        if not isinstance(g, adsk.core.Plane) or abs(g.normal.z) < .99:
            continue
        fb = f.boundingBox
        dx = (fb.maxPoint.x - fb.minPoint.x) * 10
        dy = (fb.maxPoint.y - fb.minPoint.y) * 10
        if 38 < dx < 41 and 38 < dy < 41:
            lam = (fb.minPoint.z * 10, fb.minPoint.x * 10, fb.maxPoint.x * 10,
                   fb.minPoint.y * 10, fb.maxPoint.y * 10)
    if lam is None:
        raise RuntimeError('epaulement du lamage (39,4 x 39,4) introuvable')
    z_ep, lx0, lx1, ly0, ly1 = lam
    print('CARRE : X %.2f..%.2f  Y %.2f..%.2f | dalle Z %.2f -> %.2f | epaulement Z %.2f'
          % (x0, x1, y0, y1, zmin, b.boundingBox.maxPoint.z * 10, z_ep))

    # ---------- 3) le cote : celui qui regarde le port USB-C de la coque ----------
    coque = root.bRepBodies.itemByName('AdhanBox_Fusion')
    usb = None
    for f in coque.faces:
        g = f.geometry
        if isinstance(g, adsk.core.Cylinder) and abs(g.axis.z) < .01 and 12 < g.radius * 20 < 14:
            usb = (g.origin.x * 10, g.origin.y * 10, 'X' if abs(g.axis.x) > .99 else 'Y')
    if usb is None:
        raise RuntimeError('port USB-C D13 introuvable sur la coque')
    off = hs.bRepBodies.item(0).boundingBox.minPoint      # monde
    loc = b.boundingBox.minPoint                          # local
    ox, oy = (off.x - loc.x) * 10, (off.y - loc.y) * 10
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    ux, uy = usb[0] - ox, usb[1] - oy
    if usb[2] == 'X':
        cote = '+X' if ux > cx else '-X'
    else:
        cote = '+Y' if uy > cy else '-Y'
    print('USB-C coque a (%.1f, %.1f) monde -> cote %s du carre' % (usb[0], usb[1], cote))

    # ---------- 4) le rectangle : du bord du carre jusqu'au bord du lamage ----------
    # 0,5 mm de recouvrement dans le vide du carre : pas d'arete coincidente.
    if cote == '+X':
        rx0, rx1, ry0, ry1 = x1 - 0.5, lx1, cy - LARGEUR / 2, cy + LARGEUR / 2
    elif cote == '-X':
        rx0, rx1, ry0, ry1 = lx0, x0 + 0.5, cy - LARGEUR / 2, cy + LARGEUR / 2
    elif cote == '+Y':
        rx0, rx1, ry0, ry1 = cx - LARGEUR / 2, cx + LARGEUR / 2, y1 - 0.5, ly1
    else:
        rx0, rx1, ry0, ry1 = cx - LARGEUR / 2, cx + LARGEUR / 2, ly0, y0 + 0.5

    pi = comp.constructionPlanes.createInput()
    pi.setByOffset(comp.xYConstructionPlane, adsk.core.ValueInput.createByReal(z_ep / 10.0))
    pl = comp.constructionPlanes.add(pi); pl.name = 'PL_' + NOM; pl.isLightBulbOn = False
    sk = comp.sketches.add(pl); sk.name = 'ESQ_' + NOM; sk.isVisible = False
    P = lambda x, y: sk.modelToSketchSpace(adsk.core.Point3D.create(x / 10.0, y / 10.0, z_ep / 10.0))
    sk.sketchCurves.sketchLines.addTwoPointRectangle(P(rx0, ry0), P(rx1, ry1))
    if sk.profiles.count != 1:
        raise RuntimeError('encoche : %d profils' % sk.profiles.count)

    profondeur = z_ep - zmin          # de l'epaulement au dessous : traversante
    ei = comp.features.extrudeFeatures.createInput(sk.profiles.item(0), CUT)
    sens = -1.0 if pl.geometry.normal.z > 0 else 1.0     # toujours vers le bas
    ei.setDistanceExtent(False, adsk.core.ValueInput.createByReal(sens * profondeur / 10.0))
    ei.participantBodies = [b]
    f = comp.features.extrudeFeatures.add(ei); f.name = NOM
    print('  + %s : cote %s, X %.2f..%.2f  Y %.2f..%.2f, Z %.2f -> %.2f TRAVERSANTE (%d faces coupees)'
          % (NOM, cote, rx0, rx1, ry0, ry1, z_ep, z_ep - profondeur, f.faces.count))
    if f.faces.count == 0:
        raise RuntimeError('la coupe n a rien enleve : repere local/monde melange ?')

    # ---------- 5) preuve : l'ouverture du dessous a pris la forme du carre + saignee ----------
    for ff in b.faces:
        g = ff.geometry
        if not isinstance(g, adsk.core.Plane) or abs(g.normal.z) < .99:
            continue
        if abs(ff.boundingBox.minPoint.z * 10 - zmin) > .05:
            continue
        for li in range(ff.loops.count):
            lp = ff.loops.item(li)
            lb = lp.boundingBox
            if not lp.isOuter and (lb.maxPoint.x - lb.minPoint.x) * 10 > 30 \
               and (lb.maxPoint.y - lb.minPoint.y) * 10 > 30:
                print('  ouverture du dessous : X %.2f..%.2f  Y %.2f..%.2f  (%d aretes)'
                      % (lb.minPoint.x * 10, lb.maxPoint.x * 10,
                         lb.minPoint.y * 10, lb.maxPoint.y * 10, lp.edges.count))
                if lp.edges.count <= 4:
                    raise RuntimeError('la saignee n a pas traverse : le dessous est encore un simple carre')
    print('\nPense a ENREGISTRER : support_led, puis diffusion_lum, puis AdhanBox_Fusion.')
