#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Met le carrousel de l'accueil a jour depuis le dossier docs/photos/.

    python3 outils_production/maj_carrousel.py            # regenere la liste
    python3 outils_production/maj_carrousel.py --lire     # ne modifie rien, affiche

POURQUOI. Le carrousel de adhanbox.fr liste ses photos en dur dans le HTML :
c'est un site statique, il n'y a pas de serveur pour lire un dossier. Editer
cette liste a la main a chaque photo ajoutee, c'est la garantie d'un jour
oublier une balise et casser la page. Ce script le fait a la place.

COMMENT AJOUTER UNE PHOTO. La deposer dans docs/photos/, puis relancer ce
script. Rien d'autre.

LE NOM DU FICHIER DEVIENT LA LEGENDE. `03-couvercle-ajoure.jpg` donne
« Couvercle ajoure ». Le numero sert a ordonner, il n'apparait pas. Une photo
sans texte apres le numero n'aura pas de legende, ce qui est permis.

L'ALTERNATIVE TEXTUELLE. Elle est obligatoire (accessibilite, et Google la
lit). Par defaut le script reprend la legende. Pour un texte plus riche,
creer un fichier .txt du meme nom a cote : `03-couvercle-ajoure.txt`.

CODES DE SORTIE. 0 = rien a changer ; 10 = le HTML a ete modifie, il y a de
quoi publier ; 2 = probleme (dossier absent, aucune photo, balises manquantes).
"""
import argparse
import io
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, 'docs', 'photos')
PAGE = os.path.join(RACINE, 'docs', 'index.html')
DEBUT = '<!-- carrousel:debut -->'
FIN = '<!-- carrousel:fin -->'
EXTENSIONS = ('.jpg', '.jpeg', '.png', '.webp')


def legende(nom):
    """« 03-couvercle-ajoure.jpg » -> « Couvercle ajoure »."""
    base = os.path.splitext(nom)[0]
    base = re.sub(r'^\d+[-_ ]*', '', base)          # le numero ne sert qu'a trier
    base = base.replace('-', ' ').replace('_', ' ').strip()
    return base[:1].upper() + base[1:] if base else ''


def echapper(t):
    return (t.replace('&', '&amp;').replace('<', '&lt;')
             .replace('>', '&gt;').replace('"', '&quot;'))


def photos():
    if not os.path.isdir(DOSSIER):
        return None, 'dossier introuvable : docs/photos/'
    noms = sorted(f for f in os.listdir(DOSSIER)
                  if f.lower().endswith(EXTENSIONS) and not f.startswith('.'))
    if not noms:
        return None, 'aucune photo dans docs/photos/'
    return noms, ''


def figures(noms):
    out = []
    for rang, n in enumerate(noms):
        leg = legende(n)
        # Texte alternatif : le .txt voisin s'il existe, la legende sinon.
        alt = leg
        txt = os.path.join(DOSSIER, os.path.splitext(n)[0] + '.txt')
        if os.path.exists(txt):
            alt = io.open(txt, encoding='utf-8').read().strip() or leg
        if not alt:
            alt = 'Photo de l\'AdhanBox'
        # La premiere photo est celle que le visiteur voit tout de suite : c'est
        # elle qui decide du temps d'affichage percu (LCP). Elle se charge donc en
        # priorite, jamais en differe. Les suivantes, invisibles tant qu'on n'a pas
        # fait defiler, attendent.
        premiere = (rang == 0)
        bloc = ['          <figure>']
        bloc.append('            <img src="photos/%s" width="548" height="630"' % echapper(n))
        bloc.append('                 alt="%s"' % echapper(alt))
        bloc.append('                 %s decoding="async">'
                    % ('fetchpriority="high"' if premiere else 'loading="lazy"'))
        if leg:
            bloc.append('            <figcaption>%s</figcaption>' % echapper(leg))
        bloc.append('          </figure>')
        out.append('\n'.join(bloc))
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lire', action='store_true', help='affiche sans modifier')
    args = ap.parse_args()

    noms, err = photos()
    if err:
        print('ECHEC : %s' % err)
        return 2

    print('%d photo(s) dans docs/photos/ :' % len(noms))
    for n in noms:
        print('   %-38s -> %s' % (n, legende(n) or '(sans legende)'))

    s = io.open(PAGE, encoding='utf-8').read()
    if DEBUT not in s or FIN not in s:
        print('ECHEC : reperes %s / %s absents de docs/index.html' % (DEBUT, FIN))
        return 2

    neuf = DEBUT + '\n' + figures(noms) + '\n' + FIN
    ancien = re.search(re.escape(DEBUT) + r'.*?' + re.escape(FIN), s, re.S).group(0)
    if ancien == neuf:
        print('\nLe carrousel est deja a jour.')
        return 0
    if args.lire:
        print('\n(--lire) le carrousel serait mis a jour.')
        return 0

    io.open(PAGE, 'w', encoding='utf-8').write(s.replace(ancien, neuf, 1))
    print('\ndocs/index.html mis a jour. A publier.')
    return 10


if __name__ == '__main__':
    sys.exit(main())
