#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Expose les avis clients a Google, et les garde a jour.

    python3 outils_production/maj_avis_seo.py            # met a jour si besoin
    python3 outils_production/maj_avis_seo.py --lire     # ne modifie rien, affiche

POURQUOI. Le site affiche huit avis a cinq etoiles, et Google n'en voyait aucun :
la fiche Product de l'accueil n'avait ni note ni avis. Or un resultat de
recherche qui porte des etoiles se detache au milieu de dix liens bleus. Ce
n'est pas un gain de classement, c'est un gain de CLICS sur le rang deja occupe.

POURQUOI EN DUR DANS LA PAGE. Les avis sont charges par l'application depuis le
backend. Google n'execute pas toujours ce code, et ce qu'il n'execute pas, il ne
le lit pas. La note doit donc etre ecrite dans le HTML servi, pas calculee a
l'affichage — d'ou cet outil, et la tache planifiee qui le rejoue.

CE QU'IL NE FAUT PAS FAIRE. Ne jamais inventer une note ni un nombre d'avis :
Google verifie que le balisage correspond a ce que le visiteur voit sur la page,
et une fiche marquee comme trompeuse perd ses etoiles pour longtemps. Les
chiffres viennent donc TOUJOURS de /api/reviews, jamais d'une saisie.
"""
import argparse
import io
import json
import os
import re
import sys
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = 'https://adhanbox-commande.vercel.app/api/reviews'
ACCUEIL = os.path.join(RACINE, 'docs', 'index.html')
PAGE_AVIS = os.path.join(RACINE, 'docs', 'avis.html')

DEBUT = '<!-- avis:debut -->'
FIN = '<!-- avis:fin -->'


def lire_avis():
    """Les avis publies, tels que le site les montre. Aucune autre source."""
    with urllib.request.urlopen(API, timeout=25) as r:
        d = json.loads(r.read().decode('utf-8'))
    return d.get('count', 0), d.get('average', 0), d.get('reviews', [])


def note_agregee(nombre, moyenne):
    return {
        '@type': 'AggregateRating',
        'ratingValue': str(moyenne),
        'reviewCount': str(nombre),
        'bestRating': '5',
        'worstRating': '1',
    }


def maj_accueil(nombre, moyenne):
    """Ajoute ou corrige aggregateRating dans la fiche Product de l'accueil."""
    s = io.open(ACCUEIL, encoding='utf-8').read()
    avant = s
    bloc = json.dumps(note_agregee(nombre, moyenne), ensure_ascii=False, indent=10)
    bloc = bloc.replace('\n}', '\n        }')

    if '"aggregateRating"' in s:
        # Remplacer la note existante, quelle qu'elle soit.
        s = re.sub(r'"aggregateRating"\s*:\s*\{.*?\n\s*\}',
                   '"aggregateRating": ' + bloc.rstrip(), s, count=1, flags=re.S)
    else:
        # L'inserer juste avant "offers", qui existe deja dans la fiche.
        ancre = '        "offers": {'
        if ancre not in s:
            return s != avant, 'ancre "offers" introuvable dans index.html'
        s = s.replace(ancre, '        "aggregateRating": ' + bloc.rstrip() + ',\n' + ancre, 1)

    io.open(ACCUEIL, 'w', encoding='utf-8').write(s)
    return s != avant, ''


def maj_page_avis(nombre, moyenne, avis):
    """Rebatit le bloc de donnees structurees de la page Avis.

    On y met la note ET les avis un par un : sur une page dont c'est le sujet,
    Google attend le detail, pas seulement la moyenne. Le bloc est delimite par
    deux commentaires pour etre remplace sans toucher au reste de la page."""
    s = io.open(PAGE_AVIS, encoding='utf-8').read()
    avant = s

    donnees = {
        '@context': 'https://schema.org',
        '@type': 'Product',
        '@id': 'https://adhanbox.fr/#product',
        'name': 'AdhanBox',
        'image': 'https://adhanbox.fr/og-adhanbox.jpg',
        'brand': {'@type': 'Brand', 'name': 'AdhanBox'},
        'aggregateRating': note_agregee(nombre, moyenne),
        'review': [
            {
                '@type': 'Review',
                'reviewRating': {'@type': 'Rating', 'ratingValue': str(a.get('note', 5)),
                                 'bestRating': '5', 'worstRating': '1'},
                'author': {'@type': 'Person', 'name': a.get('prenom') or 'Anonyme'},
                'datePublished': (a.get('date') or '')[:10],
                'reviewBody': a.get('texte', ''),
            }
            for a in avis if a.get('texte')
        ],
    }
    bloc = (DEBUT + '\n  <script type="application/ld+json">\n'
            + json.dumps(donnees, ensure_ascii=False, indent=2)
            + '\n  </script>\n  ' + FIN)

    if DEBUT in s and FIN in s:
        s = re.sub(re.escape(DEBUT) + r'.*?' + re.escape(FIN), bloc, s, count=1, flags=re.S)
    else:
        if '</head>' not in s:
            return s != avant, 'pas de </head> dans avis.html'
        s = s.replace('</head>', '  ' + bloc + '\n</head>', 1)

    io.open(PAGE_AVIS, 'w', encoding='utf-8').write(s)
    return s != avant, ''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lire', action='store_true', help='affiche sans modifier')
    args = ap.parse_args()

    try:
        nombre, moyenne, avis = lire_avis()
    except Exception as e:
        print('ECHEC lecture des avis : %s' % e)
        return 2
    if nombre == 0:
        print('Aucun avis publie : on ne touche a rien.')
        return 0

    print('Avis publies : %d, moyenne %s' % (nombre, moyenne))
    if args.lire:
        return 0

    change_a, err_a = maj_accueil(nombre, moyenne)
    if err_a:
        print('index.html : %s' % err_a); return 2
    change_b, err_b = maj_page_avis(nombre, moyenne, avis)
    if err_b:
        print('avis.html : %s' % err_b); return 2

    print('index.html : %s' % ('mis a jour' if change_a else 'deja a jour'))
    print('avis.html  : %s' % ('mis a jour' if change_b else 'deja a jour'))
    return 0 if not (change_a or change_b) else 10   # 10 = il y a de quoi publier


if __name__ == '__main__':
    sys.exit(main())
