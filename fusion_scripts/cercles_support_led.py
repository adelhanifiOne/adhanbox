"""
Cercles des faces courtes de `support_led` ramenes de D7 a D5,5.

PROBLEME (constate a l'impression, 03/09/2026)
Sur la piece `support_led / AdhanBox_Lid.step`, la bande d'arches porte
4 arches de 14 mm et 3 cercles D7. La face longue les espace au pas de 21 mm,
la face courte au pas de 19 mm seulement : sur la face courte il ne restait que
**0,329 mm** de matiere entre l'arche et le cercle, contre 1,118 mm sur la face
longue. 0,33 mm, c'est moins d'un trait de buse : ca ne s'imprime pas.

ATTENTION, LA PIECE VISIBLE N'EST PAS LA COQUE
Le document contient deux pieces qui portent le meme motif :
  - `AdhanBox_Fusion`, la coque exterieure (corps racine), souvent MASQUE ;
  - `support_led / AdhanBox_Lid.step`, le support interieur, VISIBLE.
Elles s'emboitent : les ouvertures du support sont dessinees ~1 mm plus grandes
que celles de la coque, pour que ce soit la coque qui dessine la forme vue.
Mesurer ou corriger la mauvaise des deux fait perdre beaucoup de temps.

CORRECTIF
La piece vient d'un STEP importe : on ne peut pas y retrecir un trou, il faut
AJOUTER de la matiere. Le script pose une couronne (exterieur D7, interieur
D5,5) dans chacun des 3 cercles des DEUX faces courtes, extrudee en jonction sur
les 1,2 mm d'epaisseur de paroi. Les faces longues ne sont pas touchees.

REJOUABLE : ne fait rien si les fonctions existent deja.
"""

import adsk.core
import adsk.fusion

R_EXT = 0.35    # 3,5 mm : le bord du trou D7 d'origine
R_INT = 0.275   # 2,75 mm : le nouveau D5,5
EP = 0.12       # 1,2 mm d'epaisseur de paroi
MURS_COURTS = (0.0, 99.0)   # Y des deux peaux exterieures, en mm


def _corps_support(root):
    oc = root.occurrences.itemByName('support_led:1')
    if oc is None:
        raise RuntimeError("occurrence 'support_led:1' introuvable")
    comp = oc.component.occurrences.item(0).component
    return comp, comp.bRepBodies.item(0)


def run(_context: str):
    app = adsk.core.Application.get()
    des = adsk.fusion.Design.cast(app.activeProduct)
    root = des.rootComponent
    comp, b = _corps_support(root)

    faits = [comp.features.item(i).name for i in range(comp.features.count)]
    for y in MURS_COURTS:
        nom_f = f'reduction_cercles_mur_Y{int(y)}'
        if nom_f in faits:
            print(f'{nom_f} : deja present, rien a faire')
            continue

        # la peau exterieure de ce mur : plane, normale suivant Y, percee
        face = None
        for i in range(b.faces.count):
            f = b.faces.item(i)
            g = f.geometry
            if (isinstance(g, adsk.core.Plane) and abs(g.normal.y) > .99
                    and f.loops.count >= 5
                    and round(f.boundingBox.minPoint.y * 10, 2) == y):
                face = f
                break
        if face is None:
            raise RuntimeError(f'peau exterieure du mur Y={y} introuvable')

        # centres des D7 traversant ce mur
        y_int = 0.0 if y == 0.0 else y - EP * 10
        centres = []
        for i in range(b.faces.count):
            f = b.faces.item(i)
            g = f.geometry
            if (isinstance(g, adsk.core.Cylinder) and abs(g.axis.y) > .99
                    and abs(g.radius * 20 - 7.0) < .01
                    and abs(f.boundingBox.minPoint.y * 10 - y_int) < .01):
                centres.append((g.origin.x, g.origin.z))
        if len(centres) != 3:
            raise RuntimeError(f'mur Y={y} : {len(centres)} cercles D7 au lieu de 3')

        sk = comp.sketches.add(face)
        sk.name = f'anneaux_mur_Y{int(y)}'
        sk.isComputeDeferred = True
        for cx, cz in centres:
            sp = sk.modelToSketchSpace(adsk.core.Point3D.create(cx, y / 10.0, cz))
            sk.sketchCurves.sketchCircles.addByCenterRadius(sp, R_EXT)
            sk.sketchCurves.sketchCircles.addByCenterRadius(sp, R_INT)
        sk.isComputeDeferred = False

        # une couronne a deux boucles ; le disque interieur n'en a qu'une
        anneaux = adsk.core.ObjectCollection.create()
        for p in sk.profiles:
            if p.profileLoops.count == 2:
                anneaux.add(p)
        if anneaux.count != 3:
            raise RuntimeError(f'mur Y={y} : {anneaux.count} couronnes au lieu de 3')

        ex = comp.features.extrudeFeatures
        inp = ex.createInput(anneaux, adsk.fusion.FeatureOperations.JoinFeatureOperation)
        inp.setDistanceExtent(False, adsk.core.ValueInput.createByReal(-EP))
        inp.participantBodies = [b]
        ex.add(inp).name = nom_f
        print(f'{nom_f} : 3 couronnes posees')

    diam = {}
    for i in range(b.faces.count):
        f = b.faces.item(i)
        g = f.geometry
        if (isinstance(g, adsk.core.Cylinder) and 4 < g.radius * 20 < 8
                and f.boundingBox.minPoint.z * 10 > 20):
            cle = 'faces courtes' if abs(g.axis.y) > .99 else 'faces longues'
            diam.setdefault(cle, set()).add(round(g.radius * 20, 1))
    for cle in sorted(diam):
        print(f'  {cle} : cercles D{sorted(diam[cle])}')
    print('\nPense a ENREGISTRER le document.')
