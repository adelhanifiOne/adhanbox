#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bascule la page Android du site le jour ou l'application est sur Google Play.

    python3 outils_production/bascule_android.py            # bascule si la fiche est en ligne
    python3 outils_production/bascule_android.py --lire     # ne modifie rien, dit ou on en est

POURQUOI. L'application a ete envoyee en production le 17/09/2026, et Google
l'examine sous sept jours. Tant qu'elle n'est pas publiee, la fiche Play Store
repond 404 : un lien direct sur le site enverrait les clients dans le vide. La
page docs/android.html decrit donc encore le programme de test — et c'est sur
elle que pointe le QR des notices imprimees. Le jour ou la fiche repond, il
faut remplacer la page par le lien direct, sans rien reimprimer.

CE QU'IL FAIT. Interroge la fiche. Si elle repond 200, remplace docs/android.html
par le gabarit outils_production/android_fiche_play.html. Rien d'autre.

CODES DE SORTIE. 0 = rien a faire (pas encore en ligne, ou deja basculee) ;
10 = la page a ete remplacee, il y a de quoi publier ; 2 = impossible de savoir
(reseau, reponse inattendue) : ne rien publier.
"""
import argparse
import io
import os
import sys
import urllib.error
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FICHE = 'https://play.google.com/store/apps/details?id=com.adhanbox.app'
GABARIT = os.path.join(RACINE, 'outils_production', 'android_fiche_play.html')
CIBLE = os.path.join(RACINE, 'docs', 'android.html')


def fiche_en_ligne():
    """True si la fiche est publiee, False si Google repond 404, None si on ne sait pas."""
    req = urllib.request.Request(FICHE + '&hl=fr&gl=FR', headers={
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
        'Accept-Language': 'fr-FR,fr;q=0.9',
    })
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            corps = r.read().decode('utf-8', 'ignore')
            # Une vraie fiche cite l'identifiant du paquet ; une page d'erreur deguisee, non.
            return r.status == 200 and 'com.adhanbox.app' in corps
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        print('Reponse inattendue de Google Play : HTTP %d' % e.code)
        return None
    except Exception as e:
        print('Impossible de joindre Google Play : %s' % e)
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lire', action='store_true', help='ne modifie rien')
    args = ap.parse_args()

    etat = fiche_en_ligne()
    if etat is None:
        return 2
    if not etat:
        print('Fiche Google Play : pas encore en ligne (404). Rien a faire.')
        return 0

    actuel = io.open(CIBLE, encoding='utf-8').read()
    if FICHE in actuel:
        print('Fiche en ligne, et docs/android.html pointe deja dessus. Rien a faire.')
        return 0

    print('Fiche Google Play EN LIGNE : %s' % FICHE)
    if args.lire:
        print('(--lire) docs/android.html serait remplacee par le gabarit.')
        return 0

    gabarit = io.open(GABARIT, encoding='utf-8').read()
    if FICHE not in gabarit or '<!-- plan:debut -->' not in gabarit:
        print('Gabarit incomplet (lien Play ou plan du site absent) : je ne remplace rien.')
        return 2
    io.open(CIBLE, 'w', encoding='utf-8').write(gabarit)
    print('docs/android.html remplacee : lien direct vers la fiche. A publier.')
    return 10


if __name__ == '__main__':
    sys.exit(main())
