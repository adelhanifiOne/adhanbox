"""Eprouvette de la glissiere du capteur tactile : un petit L a imprimer.

POURQUOI. Une boite complete, c'est des heures d'impression ; la glissiere se
joue au dixieme de millimetre (fente de 1,15 pour un circuit de 1,00). On
imprime donc d'abord ce L de quelques minutes : une paroi de 3 mm avec
EXACTEMENT le rail, l'encoche, le plafond a 45° et les deux levres de la
boite, et un pied pour qu'il tienne debout sur le plateau — meme orientation
d'impression que la paroi de la boite, donc memes surplombs, memes tolerances.

La membrane de 1,8 mm est la aussi : on peut glisser le module, le brancher,
et verifier la detection a travers le plastique avant d'imprimer une boite.

LES COTES NE VIVENT PAS ICI. Ce script importe logement_capteur.py et appelle
la meme fonction glissiere() : ce qu'on valide sur l'eprouvette est ce qui
partira dans la boite. Pour ajuster un jeu, modifier logement_capteur.py.

CE QUE FAIT LE SCRIPT. Ouvre un nouveau document Fusion, construit le L,
creuse la glissiere, controle, et exporte
    IMPRESSION 3D/proto_logement_capteur.3mf   (unites sures)
    IMPRESSION 3D/proto_logement_capteur.stl
Le nouveau document n'est pas enregistre : l'eprouvette est un fichier a
trancher, pas un modele a garder.

IMPRESSION. Debout, le pied sur le plateau, sans support.
"""
import os, sys, importlib
import adsk.core, adsk.fusion, traceback

DOSSIER_SCRIPTS = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() \
    else '/Users/adelhanifi/Projects/adhanbox/fusion_scripts'
if DOSSIER_SCRIPTS not in sys.path:
    sys.path.insert(0, DOSSIER_SCRIPTS)
import logement_capteur as lc
importlib.reload(lc)   # Fusion garde les modules en cache entre deux executions

DOSSIER_SORTIE = os.path.join(os.path.dirname(DOSSIER_SCRIPTS), 'IMPRESSION 3D')

# ── L'eprouvette (mm) ───────────────────────────────────────────────────────
PAROI   = 3.0      # comme la boite
MEMBR   = 1.8      # comme la boite : fond du rail a 1,8 de la face exterieure
LARG    = 24.0     # largeur du L (axe Y) : la glissiere fait 13,4 avec ses levres
HAUT    = 32.0     # hauteur de la paroi : le rail monte jusqu'a 29,35
PIED    = 15.0     # profondeur du pied (axe X), cote interieur
PIED_EP = 3.0      # epaisseur du pied
Z_BAS   = 8.0      # le module repose ici : encoche de 3 au-dessus du pied, avec 2 mm de marge


def run(context):
    ui = None
    try:
        app = adsk.core.Application.get()
        ui = app.userInterface
        doc = app.documents.add(adsk.core.DocumentTypes.FusionDesignDocumentType)
        des = adsk.fusion.Design.cast(app.activeProduct)
        des.designType = adsk.fusion.DesignTypes.ParametricDesignType
        root = des.rootComponent
        at = lc.Atelier(root)

        # Le pied : X 0..PIED, Y 0..LARG, Z 0..PIED_EP — nouveau corps
        p = at.plan('z', 0.0)
        sk = at.esquisse(p)
        at.rect(sk, (0.0, 0.0, 0.0), (PIED, LARG, 0.0))
        f = at.extruder(sk, p, 'z', 0.0, PIED_EP, lc.NEW, 'Eprouvette - pied')
        corps = f.bodies.item(0)
        corps.name = 'Eprouvette'
        at.corps = corps

        # La paroi : X 0..PAROI, Y 0..LARG, Z 0..HAUT — jointe au pied
        p = at.plan('z', 0.0)
        sk = at.esquisse(p)
        at.rect(sk, (0.0, 0.0, 0.0), (PAROI, LARG, 0.0))
        at.extruder(sk, p, 'z', 0.0, HAUT, lc.JOIN, 'Eprouvette - paroi')

        # La glissiere, exactement celle de la boite
        g = lc.glissiere(at, x_ext=0.0, x_int=PAROI, x_fond=MEMBR, cy=LARG / 2, z_bas=Z_BAS)
        lignes, ok = lc.controler(corps, g)

        # Export
        os.makedirs(DOSSIER_SORTIE, exist_ok=True)
        em = des.exportManager
        chemins = []
        for ext in ('3mf', 'stl'):
            chemin = os.path.join(DOSSIER_SORTIE, 'proto_logement_capteur.' + ext)
            if ext == '3mf':
                opts = em.createC3MFExportOptions(corps, chemin)   # oui, « C3MF » : c'est le nom Fusion
            else:
                opts = em.createSTLExportOptions(corps, chemin)
                opts.meshRefinement = adsk.fusion.MeshRefinementSettings.MeshRefinementHigh
            em.execute(opts)
            chemins.append(chemin)

        b = corps.boundingBox
        L = ['Eprouvette      : %.1f x %.1f x %.1f mm, %d faces, corps a la racine : %d' % (
                (b.maxPoint.x - b.minPoint.x) / lc.CM, (b.maxPoint.y - b.minPoint.y) / lc.CM,
                (b.maxPoint.z - b.minPoint.z) / lc.CM, corps.faces.count, root.bRepBodies.count)]
        L += lignes
        L.append('Marge au-dessus du rail : %.2f mm ; marge entre pied et encoche : %.2f mm' % (
            HAUT - (g['z_haut'] + g['profondeur']), (Z_BAS - lc.ENCOCHE_H) - PIED_EP))
        L.append('Controle        : %s' % ('OK' if ok else 'A REVOIR'))
        L.append('Exporte         : ' + ' ; '.join(chemins))
        L.append('Document        : nouveau, NON enregistre')
        print('\n'.join(L))
        if ui and context is not None and not isinstance(context, dict):
            ui.messageBox('\n'.join(L), 'Eprouvette glissiere')
    except Exception:
        msg = traceback.format_exc()
        print(msg)
        if ui:
            ui.messageBox(msg, 'Eprouvette - ECHEC')
