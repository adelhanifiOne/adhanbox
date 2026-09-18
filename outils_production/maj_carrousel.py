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

LES PHOTOS SONT OPTIMISEES AUTOMATIQUEMENT. Une photo de telephone pese 3 a
5 Mo et fait 4000 px de large : telle quelle, elle mettrait plusieurs secondes
a s'afficher sur un mobile en 4G, et c'est la PREMIERE chose que voit un
visiteur. Le script la ramene donc a LARGEUR_MAX px et la recompresse (sips,
fourni avec macOS). Les originaux ne sont pas conserves ici : garder les
siens dans sa photothèque.

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
import subprocess
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, 'docs', 'photos')
PAGE = os.path.join(RACINE, 'docs', 'index.html')
DEBUT = '<!-- carrousel:debut -->'
FIN = '<!-- carrousel:fin -->'
EXTENSIONS = ('.jpg', '.jpeg', '.png', '.webp')
VIDEOS = ('.mp4',)
SUFFIXE_POSTER = '-poster'   # 01-xxx-poster.jpg accompagne 01-xxx.mp4
LARGEUR_MAX = 1400      # px : au-dela, invisible a l'oeil sur le site
POIDS_MAX = 400 * 1024  # octets : au-dela, on recompresse
QUALITE = 78            # compression JPEG appliquee si besoin


def optimiser(noms):
    """Redimensionne et recompresse ce qui est trop lourd. Renvoie le rapport."""
    faits = []
    for n in noms:
        if est_video(n):
            continue                       # deja compressee par ffmpeg, sips n'y peut rien
        chemin = os.path.join(DOSSIER, n)
        avant = os.path.getsize(chemin)
        try:
            larg = int(subprocess.run(['sips', '-g', 'pixelWidth', chemin],
                                      capture_output=True, text=True).stdout.split(':')[-1])
        except Exception:
            continue                       # format illisible par sips : on n'y touche pas
        if larg <= LARGEUR_MAX and avant <= POIDS_MAX:
            continue
        cmd = ['sips']
        if larg > LARGEUR_MAX:
            cmd += ['--resampleWidth', str(LARGEUR_MAX)]
        if n.lower().endswith(('.jpg', '.jpeg')):
            cmd += ['-s', 'formatOptions', str(QUALITE)]
        cmd += [chemin]
        if subprocess.run(cmd, capture_output=True).returncode != 0:
            continue
        apres = os.path.getsize(chemin)
        faits.append((n, larg, avant, apres))
    return faits


def est_video(nom):
    return nom.lower().endswith(VIDEOS)


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
                  if f.lower().endswith(EXTENSIONS + VIDEOS)
                  and not f.startswith('.')
                  # l'image d'attente d'une video n'est pas une vue du carrousel
                  and SUFFIXE_POSTER not in os.path.splitext(f)[0])
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
        if est_video(n):
            # muted + playsinline : sans les deux, iOS refuse la lecture
            # automatique. preload="none" hors premiere vue : on ne telecharge
            # pas une video que le visiteur n'a pas encore fait defiler.
            poster = os.path.splitext(n)[0] + SUFFIXE_POSTER + '.jpg'
            attrs = 'autoplay muted loop playsinline'
            if os.path.exists(os.path.join(DOSSIER, poster)):
                attrs += ' poster="photos/%s"' % echapper(poster)
            if not premiere:
                attrs += ' preload="none"'
            bloc.append('            <video src="photos/%s" %s' % (echapper(n), attrs))
            bloc.append('                   width="548" height="630" aria-label="%s"></video>' % echapper(alt))
        else:
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

    if not args.lire:
        for n, larg, avant, apres in optimiser(noms):
            print('   allege : %-32s %d px, %.1f Mo -> %.0f Ko'
                  % (n, larg, avant / 1048576.0, apres / 1024.0))

    print('%d photo(s) dans docs/photos/ :' % len(noms))
    for n in noms:
        ko = os.path.getsize(os.path.join(DOSSIER, n)) / 1024.0
        print('   %-38s %6.0f Ko  -> %s' % (n, ko, legende(n) or '(sans legende)'))

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
