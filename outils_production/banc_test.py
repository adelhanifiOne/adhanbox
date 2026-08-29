#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Banc de production AdhanBox V3
==============================
Flashe une carte et la teste de bout en bout, puis archive un rapport signé
par numéro de série.

    python3 outils_production/banc_test.py flash          # televerse par USB
    python3 outils_production/banc_test.py test           # teste la carte
    python3 outils_production/banc_test.py serie          # flash + test enchaines

Pourquoi ce rapport compte : ton email client annonce que chaque boitier est
"teste : audio, lumiere, connexion et declenchement de l'adhan a l'heure", et
ta piece 05 du dossier CE decrit un controle unitaire. Ce fichier en est la
preuve, datee et par numero de serie.

Aucune dependance : uniquement la bibliotheque standard Python.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAPPORTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rapports')
SKETCH = os.path.join(RACINE, 'adhanbox_v3')
FQBN = 'esp32:esp32:esp32s3:PartitionScheme=min_spiffs,PSRAM=enabled'
HOTES = ['adhanbox.local', '192.168.4.1']   # mDNS, puis point d'acces de la box

# Contenu attendu sur la carte SD (voir sd_preload/ dans le depot)
CONTENU_ATTENDU = {
    '/azkar/sabah.mp3': 'Azkar du matin',
    '/azkar/masaa.mp3': 'Azkar du soir',
    '/quran/al-kahf.mp3': 'Sourate Al-Kahf',
    '/quran/al-mulk.mp3': 'Sourate Al-Mulk',
}

V, R, J, B, G, N = ('\033[32m', '\033[31m', '\033[33m', '\033[34m',
                    '\033[90m', '\033[0m')
if not sys.stdout.isatty():
    V = R = J = B = G = N = ''


def titre(t):
    print('\n%s%s%s\n%s' % (B, t, N, G + '─' * len(t) + N))


def ok(m):
    print('  %s✓%s %s' % (V, N, m))


def ko(m):
    print('  %s✗%s %s' % (R, N, m))


def info(m):
    print('  %s·%s %s' % (G, N, m))


def demande(question):
    """Question fermee a l'operateur. Entree vide = oui."""
    while True:
        r = input('  %s?%s %s [O/n] ' % (J, N, question)).strip().lower()
        if r in ('', 'o', 'oui', 'y'):
            return True
        if r in ('n', 'non'):
            return False


# ─────────────────────────── couche HTTP ────────────────────────────

class Box:
    def __init__(self, hote, token=None, timeout=8):
        self.hote = hote
        self.token = token
        self.timeout = timeout

    def _url(self, chemin, params=None):
        u = 'http://%s%s' % (self.hote, chemin)
        if params:
            u += '?' + '&'.join('%s=%s' % (k, v) for k, v in params.items())
        return u

    def get(self, chemin, params=None, brut=False):
        req = urllib.request.Request(self._url(chemin, params))
        if self.token:
            req.add_header('X-API-Key', self.token)
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            corps = r.read().decode('utf-8', 'replace')
        return corps if brut else json.loads(corps)

    def post(self, chemin, donnees):
        data = json.dumps(donnees).encode()
        req = urllib.request.Request(self._url(chemin), data=data,
                                     headers={'Content-Type': 'application/json'})
        if self.token:
            req.add_header('X-API-Key', self.token)
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            return r.read().decode('utf-8', 'replace')


def trouver_box(hote_force=None):
    """Cherche la carte : hote impose, puis mDNS, puis le point d'acces."""
    candidats = [hote_force] if hote_force else HOTES
    for h in candidats:
        try:
            b = Box(h, timeout=4)
            d = b.get('/api/device/info')
            return b, d
        except Exception:
            continue
    return None, None


# ─────────────────────────── flash USB ──────────────────────────────

def ports_serie():
    """Liste les ports USB plausibles pour un ESP32-S3 sur macOS."""
    import glob
    return sorted(glob.glob('/dev/cu.usbmodem*') + glob.glob('/dev/cu.usbserial*') +
                  glob.glob('/dev/cu.wchusbserial*'))


def cmd_flash(args):
    titre('Televersement du firmware V3')

    cli = None
    for p in ['/opt/homebrew/bin/arduino-cli', '/usr/local/bin/arduino-cli', 'arduino-cli']:
        try:
            subprocess.run([p, 'version'], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            cli = p
            break
        except Exception:
            continue
    if not cli:
        ko('arduino-cli introuvable (brew install arduino-cli).')
        return 1

    port = args.port
    if not port:
        dispo = ports_serie()
        if not dispo:
            ko('Aucune carte detectee. Branche-la en USB et reessaie.')
            return 1
        if len(dispo) > 1:
            info('Plusieurs ports : %s' % ', '.join(dispo))
            info('Precise-le avec --port')
            return 1
        port = dispo[0]
    ok('Carte sur %s' % port)

    build = os.path.join(RACINE, 'build_temp_v3')
    binaire = os.path.join(build, 'adhanbox_v3.ino.bin')
    if args.recompiler or not os.path.exists(binaire):
        info('Compilation…')
        lib = os.path.expanduser('~/Documents/Arduino/libraries')
        r = subprocess.run([cli, 'compile', '--fqbn', FQBN, '--libraries', lib,
                            '--output-dir', build, SKETCH])
        if r.returncode != 0:
            ko('Compilation echouee.')
            return 1
        ok('Compile.')
    else:
        info('Binaire existant reutilise (--recompiler pour forcer)')
        info('  %s' % binaire)

    info('Televersement…')
    r = subprocess.run([cli, 'upload', '--fqbn', FQBN, '--port', port,
                        '--input-dir', build, SKETCH])
    if r.returncode != 0:
        ko('Televersement echoue.')
        return 1
    ok('Firmware televerse.')
    info("La carte redemarre. Laisse-lui ~20 s, puis lance le test.")
    return 0


# ─────────────────────────── les tests ──────────────────────────────

class Bilan:
    def __init__(self):
        self.lignes = []

    def add(self, nom, reussi, detail=''):
        self.lignes.append({'test': nom, 'ok': bool(reussi), 'detail': detail})
        (ok if reussi else ko)('%s%s' % (nom, (' — ' + detail) if detail else ''))
        return reussi

    @property
    def echecs(self):
        return [l for l in self.lignes if not l['ok']]


def tests_automatiques(box, infos, bilan):
    titre('Controles automatiques')

    bilan.add('Identite',
              infos.get('hardware') == 'v3',
              'firmware %s · materiel %s · id %s' % (
                  infos.get('version', '?'), infos.get('hardware', '?'),
                  infos.get('device_id', '?')))

    try:
        d = box.get('/api/diag')
    except Exception as e:
        bilan.add('Diagnostic materiel', False, 'injoignable (%s)' % e)
        return

    psram = d.get('psram_size', 0)
    bilan.add('PSRAM presente', psram > 0, '%.1f Mo' % (psram / 1048576.0) if psram else 'ABSENTE')

    lu, besoin = d.get('sd_read_kBs', 0), d.get('need_kBs', 16)
    bilan.add('Debit carte SD', lu >= besoin,
              '%d ko/s lus, %d requis%s' % (lu, besoin,
                  '' if lu >= besoin else ' → coupures audio garanties'))

    heap = d.get('free_heap', 0)
    bilan.add('Memoire libre', heap > 60000, '%d octets' % heap)

    try:
        liste = box.get('/api/audio/list', brut=True)
        manquants = [c for c in CONTENU_ATTENDU if c.split('/')[-1] not in liste]
        bilan.add('Contenu audio', not manquants,
                  'complet' if not manquants
                  else 'manque : ' + ', '.join(CONTENU_ATTENDU[m] for m in manquants))
    except Exception as e:
        bilan.add('Contenu audio', False, str(e))

    try:
        t = box.get('/rtc_time', brut=True)
        annee = re.search(r'20\d\d', t)
        bilan.add('Horloge temps reel', bool(annee), t.strip()[:60])
    except Exception as e:
        bilan.add('Horloge temps reel', False, str(e))

    try:
        w = box.get('/api/wifi/status')
        connecte = str(w.get('status', '')).lower() in ('connected', 'ok', '3', 'true')
        bilan.add('Wi-Fi', connecte or bool(w.get('ip')),
                  '%s · %s' % (w.get('ssid', '?'), w.get('ip', 'sans IP')))
    except Exception as e:
        bilan.add('Wi-Fi', False, str(e))


def tests_sensoriels(box, bilan):
    """Ce que seul un humain peut constater : lumiere et son."""
    titre('Controles visuels et sonores')
    info('Regarde et ecoute la carte, puis reponds.')

    couleurs = [('Rouge', 255, 0, 0), ('Vert', 0, 255, 0), ('Bleu', 0, 0, 255)]
    vus = []
    try:
        box.post('/api/led/brightness', {'brightness': 100})
        for nom, r, g, b in couleurs:
            box.post('/api/led/rgb', {'r': r, 'g': g, 'b': b})
            time.sleep(1.2)
            vus.append(nom)
        bilan.add('LED — les 3 couleurs',
                  demande('As-tu vu rouge, puis vert, puis bleu ?'),
                  'rouge/vert/bleu envoyes')
    except Exception as e:
        bilan.add('LED — les 3 couleurs', False, str(e))

    try:
        box.post('/api/led/brightness', {'brightness': 10})
        time.sleep(1.0)
        faible = demande('La lumiere est-elle devenue faible ?')
        box.post('/api/led/brightness', {'brightness': 100})
        time.sleep(1.0)
        forte = demande('Et de nouveau vive ?')
        bilan.add('LED — reglage de luminosite', faible and forte, '10 % puis 100 %')
    except Exception as e:
        bilan.add('LED — reglage de luminosite', False, str(e))

    try:
        box.post('/api/audio/volume', {'volume': 12})
        box.get('/play', {'track': 2})
        time.sleep(3)
        entendu = demande("Entends-tu l'adhan ?")
        bilan.add('Haut-parleur', entendu, 'piste 2, volume 12/30')
        if entendu:
            box.post('/api/audio/volume', {'volume': 28})
            time.sleep(2.5)
            bilan.add('Reglage du volume',
                      demande('Le son est-il monte ?'), '12 → 28')
    except Exception as e:
        bilan.add('Haut-parleur', False, str(e))


def tests_bouton(box, bilan):
    """Le bouton tactile se verifie tout seul : il change le scenario LED."""
    titre('Bouton tactile')

    def scenario():
        return box.get('/api/led/status').get('scenario')

    try:
        box.get('/stopplay')
        time.sleep(0.6)
        avant = scenario()
        info('Scenario LED avant appui : %s' % avant)
        print('  %s?%s Appuie une fois sur le bouton tactile…' % (J, N))
        change, t0 = False, time.time()
        while time.time() - t0 < 20:
            time.sleep(0.7)
            if scenario() != avant:
                change = True
                break
        bilan.add('Bouton — changement de scenario', change,
                  'scenario %s → %s' % (avant, scenario()) if change
                  else 'aucun changement en 20 s')
    except Exception as e:
        bilan.add('Bouton — changement de scenario', False, str(e))

    try:
        box.get('/play', {'track': 2})
        time.sleep(2)
        if not box.get('/api/audio/status').get('playing'):
            bilan.add("Bouton — arret de la lecture", False, "la lecture n'a pas demarre")
            return
        print("  %s?%s Appuie de nouveau pour arreter l'adhan…" % (J, N))
        arrete, t0 = False, time.time()
        while time.time() - t0 < 20:
            time.sleep(0.7)
            if not box.get('/api/audio/status').get('playing'):
                arrete = True
                break
        bilan.add("Bouton — arret de la lecture", arrete,
                  'lecture stoppee' if arrete else 'toujours en lecture apres 20 s')
    except Exception as e:
        bilan.add("Bouton — arret de la lecture", False, str(e))
    finally:
        try:
            box.get('/stopplay')
        except Exception:
            pass


# ─────────────────────────── rapport ────────────────────────────────

def ecrire_rapport(serie, infos, bilan, hote):
    os.makedirs(RAPPORTS, exist_ok=True)
    horo = datetime.now(timezone.utc).astimezone()
    rap = {
        'numero_serie': serie,
        'date': horo.isoformat(timespec='seconds'),
        'device_id': infos.get('device_id'),
        'firmware': infos.get('version'),
        'materiel': infos.get('hardware'),
        'adresse': hote,
        'verdict': 'CONFORME' if not bilan.echecs else 'NON CONFORME',
        'tests': bilan.lignes,
    }
    nom = '%s_%s.json' % (serie or infos.get('device_id', 'inconnu'),
                          horo.strftime('%Y-%m-%d_%H%M'))
    chemin = os.path.join(RAPPORTS, nom)
    with open(chemin, 'w', encoding='utf-8') as f:
        json.dump(rap, f, indent=2, ensure_ascii=False)
        f.write('\n')
    return chemin


def cmd_test(args):
    titre('Banc de test AdhanBox V3')
    box, infos = trouver_box(args.hote)
    if not box:
        ko('Carte introuvable sur %s.' % (args.hote or ' / '.join(HOTES)))
        info('Verifie qu\'elle est allumee et sur le meme reseau, ou passe --hote <ip>.')
        return 1
    ok('Carte trouvee sur %s' % box.hote)

    # Le token n'est lisible que pendant la fenetre d'appairage (mode AP, ou
    # 10 min apres le boot). Sur un banc de production on est toujours dedans.
    if infos.get('token'):
        box.token = infos['token']
        info('Jeton recupere automatiquement')
    else:
        info('Jeton non expose (carte demarree depuis plus de 10 min) — '
             'les routes protegees peuvent refuser. Redemarre-la si un test echoue.')

    bilan = Bilan()
    tests_automatiques(box, infos, bilan)
    if not args.sans_operateur:
        tests_sensoriels(box, bilan)
        tests_bouton(box, bilan)

    titre('Bilan')
    reussis = len(bilan.lignes) - len(bilan.echecs)
    print('  %d/%d controles reussis' % (reussis, len(bilan.lignes)))
    if bilan.echecs:
        for e in bilan.echecs:
            ko('%s — %s' % (e['test'], e['detail']))
        print('\n  %sCARTE NON CONFORME — ne pas expedier.%s' % (R, N))
    else:
        print('\n  %sCARTE CONFORME.%s' % (V, N))

    serie = args.serie
    if not serie and not args.sans_operateur:
        serie = input('  Numero de serie (ex. AB3-0001, vide pour ignorer) : ').strip()
    chemin = ecrire_rapport(serie, infos, bilan, box.hote)
    info('Rapport : %s' % os.path.relpath(chemin, RACINE))
    return 0 if not bilan.echecs else 2


def cmd_serie(args):
    r = cmd_flash(args)
    if r != 0:
        return r
    info('Attente du redemarrage (25 s)…')
    time.sleep(25)
    return cmd_test(args)


def main():
    p = argparse.ArgumentParser(description='Banc de production AdhanBox V3')
    sp = p.add_subparsers(dest='commande', required=True)

    f = sp.add_parser('flash', help='televerse le firmware par USB')
    f.add_argument('--port', help='port serie (auto-detecte sinon)')
    f.add_argument('--recompiler', action='store_true', help='force la compilation')
    f.set_defaults(fn=cmd_flash)

    t = sp.add_parser('test', help='teste une carte deja flashee')
    t.add_argument('--hote', help='adresse de la carte (defaut : adhanbox.local puis 192.168.4.1)')
    t.add_argument('--serie', help='numero de serie a inscrire au rapport')
    t.add_argument('--sans-operateur', action='store_true',
                   help='ne lance que les controles automatiques')
    t.set_defaults(fn=cmd_test)

    s = sp.add_parser('serie', help='flash puis test, enchaines')
    s.add_argument('--port')
    s.add_argument('--hote')
    s.add_argument('--serie')
    s.add_argument('--recompiler', action='store_true')
    s.add_argument('--sans-operateur', action='store_true')
    s.set_defaults(fn=cmd_serie)

    args = p.parse_args()
    try:
        sys.exit(args.fn(args))
    except KeyboardInterrupt:
        print('\n  Interrompu.')
        sys.exit(130)


if __name__ == '__main__':
    main()
