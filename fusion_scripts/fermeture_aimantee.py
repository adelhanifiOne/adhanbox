# -*- coding: utf-8 -*-
"""
Fermeture aimantee AdhanBox — support_led <-> diffusion_lum
============================================================
Rejoue integralement la conception validee le 24/08/2026. A executer dans
Fusion (Utilitaires > Scripts et modules complementaires) sur le document
AdhanBox_Fusion, avec les deux pieces a l'etat vierge.

Le script ne code AUCUNE cote en dur : il mesure le modele (bbox du support,
dessus de dalle, bas de jupe, rayon et centres des conges, faces de paroi)
puis en deduit tout. Il est donc rejouable meme si les pieces ont bouge.

Resultat attendu :
  - 4 plots D10 sur le support, du dessus de dalle a 0,30 mm SOUS la jupe
  - 4 logements D6,2 x 2,2 dans les plots
  - 4 goussets a 45 deg dans les angles du diffuseur
  - 4 logements D6,2 x 2,2 dans les goussets
  -> 8 aimants D6 x 2 par boitier, soit 200 pour une serie de 25.

TROIS PIEGES, tous decouverts a la dure :

1. Les plots s'arretent 0,30 mm SOUS la jupe. Sinon l'appui est en serie avec
   la bride qui repose sur le rebord a Z=94 : au moindre ecart d'impression,
   le couvercle decolle et un jour apparait tout autour.

2. Le coin du gousset doit rester sous le conge R5 de la jupe, sinon il
   ressort de l'arrondi (0,63 mm de depassement visible constate). D'ou le
   calcul x_start = cx -/+ sqrt((R - MARGE)^2 - dy^2).

3. Les normales de faces sont INVERSEES sur ces STEP importes : toujours
   passer par face.isParamReversed, sinon on prend le dessus d'une plaque
   pour son dessous.

Les vis de fixation (D3,5 en 7,7 / 7,99 / 88,7 / 88,99) ne traversent que la
dalle pleine Z 45->50 ; au-dessus les angles sont vides. Les aimants sont a
8,5 mm de ces axes : aucun conflit.
"""

import adsk.core, adsk.fusion, math

# ---- parametres valides le 24/08/2026 -------------------------------------
D_MAG, H_MAG = 6.2, 2.2   # logement d'aimant (pour aimant D6 x 2)
D_PLOT       = 10.0       # plot cote support
GAP          = 0.30       # dessus de plot SOUS la jupe : la bride porte sur le rebord
RETRAIT      = 9.5        # centre d'aimant, en retrait du bord exterieur du support
EMB          = 0.5        # ancrage du gousset dans la paroi Y
PROJ         = 13.0       # porte-a-faux -> pente 45 deg
WID          = 15.0       # largeur du gousset
MARGE        = 0.20       # retrait du coin sous la peau du conge

JOIN = adsk.fusion.FeatureOperations.JoinFeatureOperation
CUT  = adsk.fusion.FeatureOperations.CutFeatureOperation


def find(o):
    if o.bRepBodies.count:
        return o
    for c in o.childOccurrences:
        r = find(c)
        if r:
            return r


def nz(f):
    """normale SORTANTE en Z (les STEP importes ont des faces inversees)"""
    n = f.geometry.normal.copy()
    if f.isParamReversed:
        n.scaleBy(-1)
    return n.z


def offset(host):
    a = host.bRepBodies.item(0).boundingBox.minPoint
    b = host.component.bRepBodies.item(0).boundingBox.minPoint
    return (a.x - b.x) * 10, (a.y - b.y) * 10, (a.z - b.z) * 10


def cercles(comp, z_loc, pos_loc, diam, prof, op, nom):
    pi = comp.constructionPlanes.createInput()
    pi.setByOffset(comp.xYConstructionPlane, adsk.core.ValueInput.createByReal(z_loc / 10.0))
    pl = comp.constructionPlanes.add(pi)
    pl.name = 'PL_' + nom
    sk = comp.sketches.add(pl)
    sk.name = 'ESQ_' + nom
    for x, y in pos_loc:
        c = sk.modelToSketchSpace(adsk.core.Point3D.create(x / 10.0, y / 10.0, z_loc / 10.0))
        sk.sketchCurves.sketchCircles.addByCenterRadius(c, diam / 20.0)
    col = adsk.core.ObjectCollection.create()
    for p in sk.profiles:
        col.add(p)
    ei = comp.features.extrudeFeatures.createInput(col, op)
    ei.setDistanceExtent(False, adsk.core.ValueInput.createByReal(float(prof) / 10.0))
    f = comp.features.extrudeFeatures.add(ei)
    f.name = nom
    return f


def run(_context: str):
    app = adsk.core.Application.get()
    des = adsk.fusion.Design.cast(app.activeProduct)
    root = des.rootComponent
    hs = find([o for o in root.occurrences if o.name.startswith('support_led')][0])
    hd = find([o for o in root.occurrences if o.name.startswith('diffusion')][0])
    sox, soy, soz = offset(hs)
    dox, doy, doz = offset(hd)

    # ---------- 1) mesures sur le support ----------
    bs = hs.bRepBodies.item(0)
    sb = bs.boundingBox
    x0, x1 = sb.minPoint.x * 10, sb.maxPoint.x * 10
    y0, y1 = sb.minPoint.y * 10, sb.maxPoint.y * 10
    # dessus de dalle : plus grande face horizontale tournee vers le haut, en bas de piece
    dalle, aire = None, 0
    for f in bs.faces:
        g = f.geometry
        if not isinstance(g, adsk.core.Plane) or nz(f) < 0.99:
            continue
        z = g.origin.z * 10
        if z > sb.minPoint.z * 10 + 20:
            continue
        if f.area * 100 > aire:
            aire, dalle = f.area * 100, z
    print('SUPPORT : bbox X %.2f..%.2f  Y %.2f..%.2f | dessus de dalle Z=%.2f (%.0f mm2)'
          % (x0, x1, y0, y1, dalle, aire))

    # ---------- 2) mesures sur le diffuseur, en LOCAL ----------
    loc = hd.component.bRepBodies.item(0)
    zb_loc = loc.boundingBox.minPoint.z * 10          # bas de jupe, local
    zb_monde = zb_loc + doz
    arcs, R = [], None
    for f in loc.faces:
        g = f.geometry
        if not isinstance(g, adsk.core.Cylinder) or abs(g.axis.z) < 0.99:
            continue
        fb = f.boundingBox
        if (fb.maxPoint.z - fb.minPoint.z) * 10 < 20:
            continue
        r = g.radius * 10
        if not 3.0 < r < 7.0:
            continue
        R = r
        p = (round(g.origin.x * 10, 3), round(g.origin.y * 10, 3))
        if p not in arcs:
            arcs.append(p)
    if len(arcs) != 4:
        raise RuntimeError('%d conges d angle au lieu de 4' % len(arcs))
    fx, fy = [], []
    for f in loc.faces:
        g = f.geometry
        if not isinstance(g, adsk.core.Plane) or abs(g.normal.z) > 0.01:
            continue
        fb = f.boundingBox
        if fb.minPoint.z * 10 > zb_loc + 30 or fb.maxPoint.z * 10 < zb_loc + 2 or f.area * 100 < 1000:
            continue
        if abs(g.normal.x) > 0.99:
            fx.append((round(g.origin.x * 10, 3), 1 if g.normal.x > 0 else -1))
        elif abs(g.normal.y) > 0.99:
            fy.append((round(g.origin.y * 10, 3), 1 if g.normal.y > 0 else -1))
    xo0 = min(v for v, s in fx if s < 0); xo1 = max(v for v, s in fx if s > 0)
    xi0 = min(v for v, s in fx if s > 0); xi1 = max(v for v, s in fx if s < 0)
    yi0 = min(v for v, s in fy if s > 0); yi1 = max(v for v, s in fy if s < 0)
    mx, my = (xo0 + xo1) / 2, (min(v for v, s in fy if s < 0) + max(v for v, s in fy if s > 0)) / 2
    print('DIFFUSEUR (local) : bas de jupe Z=%.2f (monde %.2f) | R conge=%.2f | X int %.2f/%.2f | Y int %.2f/%.2f'
          % (zb_loc, zb_monde, R, xi0, xi1, yi0, yi1))

    z_plot = zb_monde - GAP
    print('ENTREFER : plots jusqu a Z=%.2f, jupe a Z=%.2f -> %.2f mm' % (z_plot, zb_monde, GAP))

    # ---------- 3) positions d aimants : en retrait des coins du support ----------
    pos_monde = [(x0 + RETRAIT, y0 + RETRAIT), (x1 - RETRAIT, y0 + RETRAIT),
                 (x0 + RETRAIT, y1 - RETRAIT), (x1 - RETRAIT, y1 - RETRAIT)]
    print('AIMANTS (monde) : %s' % ['(%.1f, %.1f)' % p for p in pos_monde])

    # ---------- 4) support : plots + logements ----------
    cs = hs.component
    pos_s = [((x - sox), (y - soy)) for x, y in pos_monde]
    cercles(cs, dalle - soz, pos_s, D_PLOT, z_plot - dalle, JOIN, 'Plots_aimants_support')
    print('  + 4 plots D%.0f  Z %.2f -> %.2f' % (D_PLOT, dalle, z_plot))
    cercles(cs, z_plot - soz, pos_s, D_MAG, -H_MAG, CUT, 'Logements_aimants_support')
    print('  + 4 logements D%.1f x %.1f  Z %.2f -> %.2f' % (D_MAG, H_MAG, z_plot - H_MAG, z_plot))

    # ---------- 5) diffuseur : goussets 45 deg + logements ----------
    cd = hd.component
    pos_d = [((x - dox), (y - doy)) for x, y in pos_monde]
    for i, (px, py) in enumerate(sorted(pos_d), 1):
        cx, cy = min(arcs, key=lambda a: (a[0] - px) ** 2 + (a[1] - py) ** 2)
        sy = 1 if cy < my else -1
        yin = yi0 if sy > 0 else yi1
        y_anc = yin - sy * EMB
        y_tip = yin + sy * PROJ
        dy = abs(cy - y_anc)
        dxmax = math.sqrt((R - MARGE) ** 2 - dy ** 2)
        sx = 1 if cx < mx else -1
        x_start = cx - sx * dxmax
        z_top = zb_loc + PROJ + EMB

        pi = cd.constructionPlanes.createInput()
        pi.setByOffset(cd.yZConstructionPlane, adsk.core.ValueInput.createByReal(x_start / 10.0))
        pl = cd.constructionPlanes.add(pi); pl.name = 'PL_Gousset_aimant_%d' % i
        sk = cd.sketches.add(pl); sk.name = 'ESQ_Gousset_aimant_%d' % i

        def P(y, z):
            return sk.modelToSketchSpace(adsk.core.Point3D.create(x_start / 10.0, y / 10.0, z / 10.0))

        L = sk.sketchCurves.sketchLines
        p1, p2, p3 = P(y_anc, zb_loc), P(y_tip, zb_loc), P(y_anc, z_top)
        L.addByTwoPoints(p1, p2); L.addByTwoPoints(p2, p3); L.addByTwoPoints(p3, p1)
        if sk.profiles.count != 1:
            raise RuntimeError('gousset %d : %d profils' % (i, sk.profiles.count))
        ei = cd.features.extrudeFeatures.createInput(sk.profiles.item(0), JOIN)
        ei.setDistanceExtent(False, adsk.core.ValueInput.createByReal(sx * WID / 10.0))
        f = cd.features.extrudeFeatures.add(ei); f.name = 'Gousset_aimant_%d' % i
        print('  + gousset %d : ancrage %.2f mm dans la paroi, coin a %.2f mm du centre de conge (max %.2f)'
              % (i, abs((xi0 if sx > 0 else xi1) - x_start), math.hypot(cx - x_start, dy), R - MARGE))

    cercles(cd, zb_loc, pos_d, D_MAG, H_MAG, CUT, 'Logements_aimants_diffuseur')
    print('  + 4 logements D%.1f x %.1f  Z %.2f -> %.2f (monde)' % (D_MAG, H_MAG, zb_monde, zb_monde + H_MAG))
