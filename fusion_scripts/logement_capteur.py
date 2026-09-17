"""Logement du capteur tactile : 10 mm plus bas, en glissiere, sans colle, sans support.

Document : AdhanBox_Fusion, corps « AdhanBox_Fusion » (la coque), face -X.

ETAT DE DEPART. Une poche de 11,70 x 14,70, profonde de 1,2 mm dans la paroi
de 3, fond a X = 1,80 : le module TTP223 (HW-763, 14 x 11 x 1 mm) s'y pose,
pastille contre le fond, et le doigt est detecte a travers 1,8 mm de plastique.
Deux defauts : la poche monte jusqu'a Z = 49 alors que support_led commence a
Z = 45 (4 mm d'empietement), et rien ne retient le module sur une paroi
verticale — d'ou la colle chaude. Or un module qui flotte dans de la colle
molle bouge quand le haut-parleur fait vibrer la paroi, sa capacite change au
rythme du son, et le bouton part tout seul : c'est la coupure d'adhan.

CE QUE FAIT LE SCRIPT.
  1. rebouche la poche actuelle ;
  2. la recreuse 10 mm plus bas, meme membrane de 1,8 mm, en RAIL ouvert vers
     le haut, plafond a 45° ; une encoche en bas laisse sortir les fils ;
  3. ajoute deux LEVRES le long des bords verticaux du rail : entre le fond et
     les levres, une fente de l'epaisseur du circuit + JEU_EP. Le module se
     glisse par le dessus, vient reposer en bas, et ne bouge plus — ni en
     epaisseur, ni en largeur, ni en hauteur. Aucune colle.

SANS SUPPORT. Boite imprimee debout. Toute face tournee vers le bas est a 45° :
plafond du rail, dessous des levres (elles naissent en pointe sur la paroi).

REJOUABLE. La poche est retrouvee par sa geometrie (face plane de 11,7 x 14,7
au fond d'une paroi normale a X), pas par des cotes codees en dur. Le script
mesure, agit, puis imprime ses valeurs de controle. Il n'enregistre PAS.

EPROUVETTE. `prototype_logement_capteur.py` construit la meme glissiere sur un
petit L a imprimer en quelques minutes, en important CE fichier : les cotes ne
vivent qu'ici. Tester la avant d'imprimer une boite.

REGLAGE. Si le module force ou ne rentre pas apres impression, augmenter
JEU_EP (0,15 -> 0,20) et/ou JEU_LAT (0,20 -> 0,30), annuler, rejouer.

MONTAGE. Module glisse par le haut, composants vers l'interieur, pastille
contre la membrane, broches en bas coupees a ras cote pastille, fils par
l'encoche. A faire AVANT de poser support_led. Puis BAISSER la sensibilite du
TTP223 : plaque franchement contre 1,8 mm de plastique, il lui en faut moins
qu'a travers un bouchon de colle.
"""
import adsk.core, adsk.fusion, traceback

# ── Cotes de conception (mm) — seule source, l'eprouvette les importe ───────
POCHE_A   = 11.7    # emprise attendue de la poche actuelle, pour la retrouver
POCHE_B   = 14.7
TOL       = 0.1
MODULE_l  = 11.0    # module HW-763 : largeur (axe Y)
MODULE_L  = 14.0    # hauteur (axe Z), les broches en bas
EP_PCB    = 1.0     # epaisseur du circuit
JEU_EP    = 0.15    # jeu dans la fente, en epaisseur
JEU_LAT   = 0.20    # jeu par cote, en largeur
DESCENTE  = 10.0    # le siege descend de 10 mm
ENGAGE    = 6.0     # rail au-dessus du module, pour l'engager par le haut
ENCOCHE_l = 6.0     # encoche de sortie des fils : largeur
ENCOCHE_H = 3.0     # ... et hauteur, sous le bas du rail
LEVRE_EP  = 1.2     # epaisseur des levres (axe X)
LEVRE_REC = 0.8     # recouvrement des levres sur le circuit (axe Y)
LEVRE_ANC = 1.0     # ancrage des levres sur la paroi, hors rail (axe Y)
LEVRE_RET = 1.0     # retrait des levres sous le haut du module : le rail reste ouvert
CORPS     = 'AdhanBox_Fusion'

CM = 0.1  # l'API Fusion travaille en cm

JOIN = adsk.fusion.FeatureOperations.JoinFeatureOperation
CUT  = adsk.fusion.FeatureOperations.CutFeatureOperation
NEW  = adsk.fusion.FeatureOperations.NewBodyFeatureOperation


class Atelier:
    """Esquisses et extrusions cotees en mm, dans le repere du modele."""

    def __init__(self, root, corps=None):
        self.root = root
        self.corps = corps

    def plan(self, axe, valeur_mm):
        # Plan normal a `axe` ('x','y','z') a la cote voulue. Le sens de l'offset
        # depend de la normale du plan de base : on essaie, on mesure, on refait.
        base = {'x': self.root.yZConstructionPlane, 'y': self.root.xZConstructionPlane,
                'z': self.root.xYConstructionPlane}[axe]
        for signe in (1.0, -1.0):
            inp = self.root.constructionPlanes.createInput()
            inp.setByOffset(base, adsk.core.ValueInput.createByReal(signe * valeur_mm * CM))
            p = self.root.constructionPlanes.add(inp)
            p.isLightBulbOn = False
            o = p.geometry.origin
            obtenu = {'x': o.x, 'y': o.y, 'z': o.z}[axe] / CM
            if abs(obtenu - valeur_mm) < 0.01:
                return p
            p.deleteMe()
        raise RuntimeError('impossible de placer un plan a %s = %.2f' % (axe, valeur_mm))

    def esquisse(self, plan):
        sk = self.root.sketches.add(plan)
        sk.isVisible = False
        return sk

    def pt(self, sk, x, y, z):
        return sk.modelToSketchSpace(adsk.core.Point3D.create(x * CM, y * CM, z * CM))

    def rect(self, sk, a, b):
        # a, b : deux coins opposes (x, y, z) en mm, dans le plan de l'esquisse
        sk.sketchCurves.sketchLines.addTwoPointRectangle(self.pt(sk, *a), self.pt(sk, *b))

    def polygone(self, sk, points):
        L = sk.sketchCurves.sketchLines
        n = len(points)
        for i in range(n):
            L.addByTwoPoints(self.pt(sk, *points[i]), self.pt(sk, *points[(i + 1) % n]))

    def extruder(self, sk, plan, axe, de, a, operation, nom):
        profils = adsk.core.ObjectCollection.create()
        for i in range(sk.profiles.count):
            profils.add(sk.profiles.item(i))
        n = plan.geometry.normal
        sens = 1.0 if {'x': n.x, 'y': n.y, 'z': n.z}[axe] > 0 else -1.0
        inp = self.root.features.extrudeFeatures.createInput(profils, operation)
        inp.setDistanceExtent(False, adsk.core.ValueInput.createByReal((a - de) * sens * CM))
        if self.corps is not None and operation != NEW:
            inp.participantBodies = [self.corps]
        f = self.root.features.extrudeFeatures.add(inp)
        f.name = nom
        return f


def glissiere(at, x_ext, x_int, x_fond, cy, z_bas):
    """Creuse le rail et l'encoche, pose le plafond a 45° et les deux levres.

    Paroi normale a X : face exterieure x_ext (cote doigt), interieure x_int,
    fond du rail x_fond. Le module est centre en Y sur cy et repose en z_bas.
    Retourne les cotes obtenues, pour le controle."""
    profondeur = x_int - x_fond
    if profondeur < EP_PCB + JEU_EP - 1e-6:
        raise RuntimeError('rail trop peu profond (%.2f) pour un circuit de %.2f + %.2f' % (profondeur, EP_PCB, JEU_EP))
    y0 = cy - MODULE_l / 2 - JEU_LAT
    y1 = cy + MODULE_l / 2 + JEU_LAT
    z_mod  = z_bas + MODULE_L + JEU_EP         # haut du module en place
    z_haut = z_mod + ENGAGE                    # debut du plafond a 45°

    # Le rail, ouvert vers le haut, et l'encoche des fils en bas
    p = at.plan('x', x_int)
    sk = at.esquisse(p)
    at.rect(sk, (x_int, y0, z_bas), (x_int, y1, z_haut))
    at.rect(sk, (x_int, cy - ENCOCHE_l / 2, z_bas - ENCOCHE_H), (x_int, cy + ENCOCHE_l / 2, z_bas + 0.5))
    at.extruder(sk, p, 'x', x_int, x_fond, CUT, 'Capteur - rail et encoche')

    # Plafond a 45° : un coin retire au-dessus du rail. Rien de plat au-dessus du vide.
    p = at.plan('y', y0)
    sk = at.esquisse(p)
    at.polygone(sk, [(x_int, y0, z_haut), (x_fond, y0, z_haut), (x_int, y0, z_haut + profondeur)])
    at.extruder(sk, p, 'y', y0, y1, CUT, 'Capteur - plafond du rail a 45')

    # Les levres : la fente fait EP_PCB + JEU_EP depuis le fond. Profil XZ :
    # la levre nait en pointe sur la paroi et grossit a 45°, puis monte droit.
    x_levre_a = x_fond + EP_PCB + JEU_EP       # dessous des levres
    x_levre_b = x_levre_a + LEVRE_EP           # face avant, dans la boite
    z_levre   = z_mod - LEVRE_RET
    for ya, yb, nom in ((y0 - LEVRE_ANC, y0 + LEVRE_REC, 'Capteur - levre 1'),
                        (y1 - LEVRE_REC, y1 + LEVRE_ANC, 'Capteur - levre 2')):
        p = at.plan('y', ya)
        sk = at.esquisse(p)
        at.polygone(sk, [(x_levre_a, ya, z_bas - (x_levre_b - x_levre_a)), (x_levre_a, ya, z_levre),
                         (x_levre_b, ya, z_levre), (x_levre_b, ya, z_bas)])
        at.extruder(sk, p, 'y', ya, yb, JOIN, nom)

    return dict(x_ext=x_ext, x_int=x_int, x_fond=x_fond, profondeur=profondeur, membrane=x_fond - x_ext,
                cy=cy, y0=y0, y1=y1, z_bas=z_bas, z_mod=z_mod, z_haut=z_haut,
                x_levre_a=x_levre_a, x_levre_b=x_levre_b, z_levre=z_levre)


def controler(corps, g):
    """Relit la geometrie obtenue. Retourne (lignes de rapport, tout_va_bien)."""
    def face_x(x_mm, ya, yb, za, zb):
        for f in corps.faces:
            geo = f.geometry
            if isinstance(geo, adsk.core.Plane) and abs(abs(geo.normal.x) - 1.0) < 1e-3:
                b = f.boundingBox
                if (abs(b.minPoint.x / CM - x_mm) < 0.02
                        and abs(b.minPoint.y / CM - ya) < 0.05 and abs(b.maxPoint.y / CM - yb) < 0.05
                        and abs(b.minPoint.z / CM - za) < 0.05 and abs(b.maxPoint.z / CM - zb) < 0.05):
                    return f
        return None

    rail = face_x(g['x_fond'], g['y0'], g['y1'], g['z_bas'] - ENCOCHE_H, g['z_haut'])
    dessous = 0
    for f in corps.faces:
        geo = f.geometry
        if isinstance(geo, adsk.core.Plane) and abs(abs(geo.normal.x) - 1.0) < 1e-3:
            b = f.boundingBox
            if (abs(b.minPoint.x / CM - g['x_levre_a']) < 0.02
                    and b.minPoint.z / CM >= g['z_bas'] - 0.05 and b.maxPoint.z / CM <= g['z_levre'] + 0.05):
                dessous += 1
    # Surplombs : aucune face plane horizontale tournee vers le bas dans la zone.
    plats = []
    for f in corps.faces:
        geo = f.geometry
        if not isinstance(geo, adsk.core.Plane):
            continue
        n = geo.normal
        nz = -n.z if f.isParamReversed else n.z
        if nz < -0.99:
            b = f.boundingBox
            if (b.minPoint.x / CM > g['x_ext'] + 0.5 and b.maxPoint.x / CM < g['x_levre_b'] + 1.0
                    and b.minPoint.y / CM > g['y0'] - LEVRE_ANC - 1.0 and b.maxPoint.y / CM < g['y1'] + LEVRE_ANC + 1.0
                    and b.minPoint.z / CM > g['z_bas'] - LEVRE_EP - 1.0 and b.maxPoint.z / CM < g['z_haut'] + g['profondeur'] + 1.0):
                plats.append('X %.1f..%.1f Y %.1f..%.1f Z %.1f' % (b.minPoint.x / CM, b.maxPoint.x / CM,
                             b.minPoint.y / CM, b.maxPoint.y / CM, b.minPoint.z / CM))
    fente = g['x_levre_a'] - g['x_fond']
    L = []
    L.append('Paroi           : X %.2f (ext) -> %.2f (int) = %.2f mm ; rail %.2f, membrane %.2f' % (
        g['x_ext'], g['x_int'], g['x_int'] - g['x_ext'], g['profondeur'], g['membrane']))
    L.append('Rail            : Y %.2f..%.2f (%.2f large), Z %.2f..%.2f puis plafond a 45 jusqu a %.2f -> %s' % (
        g['y0'], g['y1'], g['y1'] - g['y0'], g['z_bas'], g['z_haut'], g['z_haut'] + g['profondeur'], 'OK' if rail else 'INTROUVABLE'))
    L.append('Module          : repose a Z %.2f, haut a %.2f' % (g['z_bas'], g['z_mod']))
    L.append('Fente           : %.2f mm entre fond (X %.2f) et levres (X %.2f) pour un circuit de %.2f -> jeu %.2f ; dessous de levre %d/2' % (
        fente, g['x_fond'], g['x_levre_a'], EP_PCB, fente - EP_PCB, dessous))
    L.append('Levres          : Z %.2f..%.2f, recouvrement %.1f, ancrage %.1f, avant a X %.2f' % (
        g['z_bas'], g['z_levre'], LEVRE_REC, LEVRE_ANC, g['x_levre_b']))
    L.append('Encoche fils    : %.0f x %.0f sous le rail' % (ENCOCHE_l, ENCOCHE_H))
    L.append('Faces horizontales tournees vers le bas dans la zone : %d%s' % (len(plats), '' if not plats else ' -> ' + ' | '.join(plats)))
    ok = (rail is not None) and dessous == 2 and not plats
    return L, ok


def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        des = adsk.fusion.Design.cast(app.activeProduct)
        root = des.rootComponent
        corps = None
        for b in root.bRepBodies:
            if b.name == CORPS:
                corps = b
        if corps is None:
            raise RuntimeError('corps %s introuvable a la racine' % CORPS)

        # ── 1. Retrouver la poche : face plane normale a X, emprise 11,7 x 14,7 ─
        fond = None
        for f in corps.faces:
            geo = f.geometry
            if not (isinstance(geo, adsk.core.Plane) and abs(abs(geo.normal.x) - 1.0) < 1e-3):
                continue
            b = f.boundingBox
            dy = (b.maxPoint.y - b.minPoint.y) / CM
            dz = (b.maxPoint.z - b.minPoint.z) / CM
            if abs(dy - POCHE_A) < TOL and abs(dz - POCHE_B) < TOL:
                fond = f
        if fond is None:
            raise RuntimeError('aucune face plane de %.1f x %.1f normale a X : la poche a deja ete deplacee ?' % (POCHE_A, POCHE_B))
        fb = fond.boundingBox
        x_fond = fb.minPoint.x / CM
        y0a, y1a = fb.minPoint.y / CM, fb.maxPoint.y / CM
        z0a, z1a = fb.minPoint.z / CM, fb.maxPoint.z / CM
        cy = (y0a + y1a) / 2

        # La paroi qui porte la poche : ses deux grandes faces normales a X, de
        # part et d'autre du fond. On les mesure, on ne les suppose pas.
        x_int = x_ext = None
        for f in corps.faces:
            geo = f.geometry
            if isinstance(geo, adsk.core.Plane) and abs(abs(geo.normal.x) - 1.0) < 1e-3 and f.area / (CM * CM) > 3000:
                x = f.boundingBox.minPoint.x / CM
                if abs(x - x_fond) < 4.0:
                    if x > x_fond: x_int = x        # face interieure (cote module)
                    else:          x_ext = x        # face exterieure (cote doigt)
        if x_int is None or x_ext is None:
            raise RuntimeError('faces de paroi introuvables autour de la poche')

        at = Atelier(root, corps)

        # ── 2. Reboucher la poche actuelle ──────────────────────────────────
        p = at.plan('x', x_fond)
        sk = at.esquisse(p)
        at.rect(sk, (x_fond, y0a, z0a), (x_fond, y1a, z1a))
        at.extruder(sk, p, 'x', x_fond, x_int, JOIN, 'Capteur - bouchon ancienne poche')

        # ── 3. La glissiere, 10 mm plus bas ─────────────────────────────────
        g = glissiere(at, x_ext, x_int, x_fond, cy, z0a - DESCENTE)

        # ── Controle ────────────────────────────────────────────────────────
        def face_x(x_mm, ya, yb, za, zb):
            for f in corps.faces:
                geo = f.geometry
                if isinstance(geo, adsk.core.Plane) and abs(abs(geo.normal.x) - 1.0) < 1e-3:
                    b = f.boundingBox
                    if (abs(b.minPoint.x / CM - x_mm) < 0.02
                            and abs(b.minPoint.y / CM - ya) < 0.05 and abs(b.maxPoint.y / CM - yb) < 0.05
                            and abs(b.minPoint.z / CM - za) < 0.05 and abs(b.maxPoint.z / CM - zb) < 0.05):
                        return f
            return None
        ancien = face_x(x_fond, y0a, y1a, z0a, z1a)
        L = ['Poche d origine : Y %.2f..%.2f  Z %.2f..%.2f, fond X %.2f' % (y0a, y1a, z0a, z1a, x_fond),
             'Ancienne poche  : %s' % ('rebouchee' if ancien is None else 'ENCORE PRESENTE')]
        lignes, ok = controler(corps, g)
        L += lignes
        L.append('support_led commence a Z 45 ; haut du module a %.2f' % g['z_mod'])
        L.append('Corps a la racine : %d (1 attendu)' % root.bRepBodies.count)
        L.append('Document        : NON enregistre')
        print('\n'.join(L))
        if ui and context is not None and not isinstance(context, dict):
            ui.messageBox('\n'.join(L), 'Logement capteur')
    except Exception:
        msg = traceback.format_exc()
        print(msg)
        if ui:
            ui.messageBox(msg, 'Logement capteur - ECHEC')
