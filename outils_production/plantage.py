#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Attrape un plantage de la carte et dit A QUELLE LIGNE il s'est produit.

Quand l'ESP32 plante, il ecrit sur le port serie un bloc de diagnostic qui
contient la cause et une pile d'adresses. Ces adresses ne veulent rien dire
telles quelles ; il faut les traduire avec le fichier .elf de la compilation.
C'est ce que fait cet outil, en direct.

    python3 outils_production/plantage.py

Il ouvre le port, ecrit TOUT ce que dit la carte dans un journal horodate, et
des qu'un plantage passe il le traduit a l'ecran, ligne de code comprise.
Laisse-le tourner, joue un adhan fort, attends que ca tombe.

Deux precautions :
  - FERME le banc avant : deux programmes ne peuvent pas lire le meme port,
    chacun recevrait la moitie des octets.
  - le .elf doit correspondre EXACTEMENT au firmware installe. L'outil compare
    la version qu'il lit dans le .elf a celle que repond la carte, et refuse de
    traduire si elles different : une traduction faite avec le mauvais .elf
    donne des lignes fausses, ce qui est pire que pas de traduction du tout.
"""
import os
import re
import select
import subprocess
import sys
import time
import glob

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELF = os.path.join(RACINE, 'build_banc_v3', 'adhanbox_v3.ino.elf')
JOURNAUX = os.path.join(RACINE, 'outils_production', 'rapports')

# Ce qui annonce un plantage dans le flot du port serie.
DEBUT = re.compile(r'Guru Meditation|abort\(\) was called|assert failed|'
                   r'panic\'ed|StoreProhibited|LoadProhibited|IntegerDivideByZero|'
                   r'InstrFetchProhibited|Stack canary|stack overflow|Brownout', re.I)
PILE = re.compile(r'Backtrace:\s*(.*)')
ADRESSE = re.compile(r'0x[0-9a-fA-F]{8}')


def trouver_addr2line():
    m = glob.glob(os.path.expanduser(
        '~/Library/Arduino15/packages/esp32/tools/esp-x32/*/bin/xtensa-esp32s3-elf-addr2line'))
    return sorted(m)[-1] if m else None


def version_du_elf(chemin):
    """La version compilee dans le .elf, lue dans ses chaines de caracteres."""
    try:
        with open(chemin, 'rb') as f:
            data = f.read()
    except OSError:
        return None
    v = set(re.findall(rb'"version":"(\d+\.\d+\.\d+)"', data))
    return sorted(x.decode() for x in v)[-1] if v else None


def traduire(lignes, addr2line):
    """Traduit toutes les adresses d'un bloc de plantage en lignes de code."""
    adresses = []
    for l in lignes:
        m = PILE.search(l)
        if m:
            adresses += ADRESSE.findall(m.group(1))
    # Certaines versions n'impriment plus de Backtrace : on retombe sur le PC.
    if not adresses:
        for l in lignes:
            if re.search(r'\bPC\s*:|backtrace|abort\(\) was called at PC', l, re.I):
                adresses += ADRESSE.findall(l)
    if not adresses:
        return []
    r = subprocess.run([addr2line, '-pfiaC', '-e', ELF] + adresses,
                       capture_output=True, text=True)
    return [x for x in r.stdout.splitlines() if x.strip()]


def ouvrir(port):
    subprocess.run(['stty', '-f', port, 'raw', '115200', '-echo', '-hupcl'],
                   check=True, capture_output=True, timeout=5)
    return os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else None
    if not port:
        p = sorted(glob.glob('/dev/cu.usbmodem*'))
        if not p:
            sys.exit('Aucune carte branchee. Branche-la en USB et relance.')
        port = p[0]

    addr2line = trouver_addr2line()
    if not addr2line:
        print('! xtensa-esp32s3-elf-addr2line introuvable : je journalise sans traduire.')
    if not os.path.exists(ELF):
        print('! %s absent : compile depuis le banc pour pouvoir traduire.' % ELF)
        addr2line = None

    vlocal = version_du_elf(ELF) if os.path.exists(ELF) else None
    os.makedirs(JOURNAUX, exist_ok=True)
    chemin = os.path.join(JOURNAUX, 'plantage_%s.txt' % time.strftime('%Y-%m-%d_%H%M'))
    journal = open(chemin, 'w', encoding='utf-8')

    print('Port      : %s' % port)
    print('Journal   : %s' % chemin)
    print('Version du .elf : %s' % (vlocal or 'inconnue'))
    print('\nJoue un adhan a volume fort et laisse tourner. Ctrl+C pour arreter.\n')

    fd = ouvrir(port)
    # On demande son identite a la carte : si la version differe du .elf, toute
    # traduction serait fausse, et une ligne fausse envoie chercher au mauvais
    # endroit pendant des heures.
    os.write(fd, b't:info\n')
    vcarte = None
    fin = time.time() + 3
    tampon = ''
    while time.time() < fin:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                tampon += os.read(fd, 4096).decode('utf-8', 'replace')
            except OSError:
                break
    m = re.search(r'"version":"(\d+\.\d+\.\d+)"', tampon)
    if m:
        vcarte = m.group(1)
    print('Version de la carte : %s' % (vcarte or 'pas de reponse'))
    if vlocal and vcarte and vlocal != vcarte:
        print('! ATTENTION : la carte est en %s, le .elf en %s.' % (vcarte, vlocal))
        print('  Je journalise, mais je NE TRADUIRAI PAS : les lignes seraient fausses.')
        print('  Reflashe la carte depuis le banc, ou recompile, pour les faire coincider.\n')
        addr2line = None
    print('-' * 70)

    bloc, dans_bloc, silence = [], False, time.time()
    try:
        while True:
            r, _, _ = select.select([fd], [], [], 0.3)
            if not r:
                # Un bloc de plantage se termine par un blanc : on le traite.
                if dans_bloc and time.time() - silence > 1.5:
                    rendre(bloc, addr2line)
                    bloc, dans_bloc = [], False
                continue
            try:
                morceau = os.read(fd, 4096)
            except OSError:
                continue
            if not morceau:
                continue
            silence = time.time()
            texte = morceau.decode('utf-8', 'replace')
            journal.write(texte)
            journal.flush()
            for ligne in texte.splitlines():
                sys.stdout.write(ligne + '\n')
                if DEBUT.search(ligne):
                    dans_bloc = True
                if dans_bloc:
                    bloc.append(ligne)
            sys.stdout.flush()
    except KeyboardInterrupt:
        if dans_bloc:
            rendre(bloc, addr2line)
        print('\nJournal complet : %s' % chemin)
    finally:
        journal.close()
        os.close(fd)


def rendre(bloc, addr2line):
    print('\n' + '=' * 70)
    print('PLANTAGE ATTRAPE')
    print('=' * 70)
    for l in bloc:
        if re.search(r'Guru Meditation|abort\(\)|assert failed|Brownout|panic', l, re.I):
            print('  ' + l.strip())
    if not addr2line:
        print('  (pas de traduction : voir plus haut pourquoi)')
        print('=' * 70 + '\n')
        return
    lignes = traduire(bloc, addr2line)
    if lignes:
        print('\n  Ou exactement, du plus recent au plus ancien :')
        for l in lignes:
            print('   ', l)
    else:
        print('  Aucune adresse exploitable dans ce bloc.')
    print('=' * 70 + '\n')


if __name__ == '__main__':
    main()
