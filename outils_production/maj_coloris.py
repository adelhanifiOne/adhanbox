#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Photos des coloris, en haut de la page Personnaliser (docs/personnaliser.html).

    python3 outils_production/maj_coloris.py IMG_3360.jpeg vert-foret or
    python3 outils_production/maj_coloris.py            # regenere seulement la liste

UNE PHOTO PAR COULEUR DE CHASSIS. Les deux derniers arguments sont les cles du
chassis et de la couleur du motif, celles de FINISHES et MANDALA_COLORS dans
docs/configurator.js (vert-foret, cacahuete, or...). Une nouvelle photo d'une
couleur remplace l'ancienne.

LA PHOTO PERD SES METADONNEES. Une photo de telephone porte les coordonnees GPS
de l'endroit ou elle a ete prise, c'est-a-dire la maison, et le site comme le
depot sont publics. Elle est aussi ramenee a LARGEUR x HAUTEUR (3:4, recadree
au centre si besoin) et passee en sRGB. Le resultat va dans docs/coloris/,
nomme <chassis>--<motif>.jpg. L'original n'est pas copie : le ranger dans
store_assets/photos_originales/ (ignore par git), PAS dans docs/photos/, que
maj_carrousel.py verse tout entier dans le carrousel de l'accueil.

LA LISTE DU CARROUSEL, entre <!-- coloris:debut --> et <!-- coloris:fin -->,
est reecrite d'apres les fichiers presents : du chassis le plus sombre au plus
clair (lu comme un nuancier), les noms repris de configurator.js. Les couleurs
du site qui n'ont pas de photo sont nommees sous le carrousel par
configurator.js lui-meme : rien a faire ici quand on en ajoute une.

Dependance : pillow.
"""
import io
import os
import re
import sys

from PIL import Image, ImageCms, ImageOps

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, 'docs', 'coloris')
PAGE = os.path.join(RACINE, 'docs', 'personnaliser.html')
CONFIG = os.path.join(RACINE, 'docs', 'configurator.js')
DEBUT = '<!-- coloris:debut -->'
FIN = '<!-- coloris:fin -->'
LARGEUR, HAUTEUR = 720, 960   # px : deux fois la plus grande carte a l'ecran
QUALITE = 80


def palettes():
    """(chassis, motifs), chacun {cle: (libelle, teinte)}, lus dans configurator.js."""
    src = io.open(CONFIG, encoding='utf-8').read()
    chassis = src.split('const FINISHES', 1)[1].split('};', 1)[0]
    motifs = src.split('const MANDALA_COLORS', 1)[1].split('};', 1)[0]
    entree = r"'([a-z-]+)':\s*\{\s*label:\s*'([^']+)',\s*hex:\s*'(#[0-9A-Fa-f]{6})'"
    lire = lambda s: {k: (nom, teinte) for k, nom, teinte in re.findall(entree, s)}
    return lire(chassis), lire(motifs)


def luminance(teinte):
    r, g, b = (int(teinte[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    lin = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def importer(source, chassis, motif):
    im = Image.open(source)
    icc = im.info.get('icc_profile')
    im = ImageOps.exif_transpose(im).convert('RGB')     # droite, comme a l'ecran
    if icc:
        try:
            im = ImageCms.profileToProfile(im, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                                           ImageCms.createProfile('sRGB'))
        except Exception:
            pass                                         # profil illisible : tel quel
    im = ImageOps.fit(im, (LARGEUR, HAUTEUR), Image.LANCZOS)
    os.makedirs(DOSSIER, exist_ok=True)
    for f in os.listdir(DOSSIER):
        if f.startswith(chassis + '--'):
            os.remove(os.path.join(DOSSIER, f))
    dest = os.path.join(DOSSIER, '%s--%s.jpg' % (chassis, motif))
    # Sans exif= ni icc_profile= : aucune metadonnee ne suit, GPS compris.
    im.save(dest, 'JPEG', quality=QUALITE, optimize=True, progressive=True)
    print('   %s  %d Ko' % (os.path.relpath(dest, RACINE), os.path.getsize(dest) // 1024))


def echapper(t):
    return (t.replace('&', '&amp;').replace('<', '&lt;')
             .replace('>', '&gt;').replace('"', '&quot;'))


def figures(chassis, motifs):
    presentes = []
    for f in os.listdir(DOSSIER) if os.path.isdir(DOSSIER) else []:
        m = re.match(r'^([a-z-]+?)--([a-z-]+)\.jpg$', f)
        if m and m.group(1) in chassis and m.group(2) in motifs:
            presentes.append((m.group(1), m.group(2), f))
    presentes.sort(key=lambda p: luminance(chassis[p[0]][1]))
    blocs = []
    for rang, (c, m, f) in enumerate(presentes):
        nom, motif = chassis[c][0], motifs[m][0].lower()
        # Les premieres cartes sont a l'ecran des l'arrivee : pas de chargement differe.
        charge = '' if rang < 2 else ' loading="lazy"'
        blocs.append('\n'.join([
            '          <figure data-finish="%s">' % c,
            '            <img src="coloris/%s" width="%d" height="%d"' % (f, LARGEUR, HAUTEUR),
            '                 alt="AdhanBox, châssis %s, motif %s"%s decoding="async">'
            % (echapper(nom), echapper(motif), charge),
            '            <figcaption><span class="coloris-nom">%s</span>'
            '<span class="coloris-motif">motif %s</span></figcaption>' % (echapper(nom), echapper(motif)),
            '          </figure>']))
    return presentes, '\n'.join(blocs)


def main():
    chassis, motifs = palettes()
    if len(sys.argv) == 4:
        source, c, m = sys.argv[1:]
        if c not in chassis:
            sys.exit('chassis inconnu : %s (connus : %s)' % (c, ', '.join(chassis)))
        if m not in motifs:
            sys.exit('motif inconnu : %s (connus : %s)' % (m, ', '.join(motifs)))
        importer(source, c, m)
    elif len(sys.argv) != 1:
        sys.exit(__doc__)

    presentes, bloc = figures(chassis, motifs)
    s = io.open(PAGE, encoding='utf-8').read()
    if DEBUT not in s or FIN not in s:
        sys.exit('reperes %s / %s absents de docs/personnaliser.html' % (DEBUT, FIN))
    neuf = DEBUT + ('\n' + bloc if bloc else '') + '\n' + FIN
    s = re.sub(re.escape(DEBUT) + r'.*?' + re.escape(FIN), lambda _: neuf, s, count=1, flags=re.S)
    io.open(PAGE, 'w', encoding='utf-8').write(s)
    photographies = set(p[0] for p in presentes)
    print('%d coloris en photo : %s' % (len(presentes), ', '.join(chassis[p[0]][0] for p in presentes)))
    print('sans photo : %s' % (', '.join(v[0] for k, v in chassis.items() if k not in photographies) or 'aucun'))


if __name__ == '__main__':
    main()
