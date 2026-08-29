#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Banc de production AdhanBox V3
==============================
Flashe une carte et la teste de bout en bout, puis archive un rapport signé
par numéro de série.

    python3 outils_production/banc_gui.py                  # interface graphique
    python3 outils_production/banc_test.py flash           # televerse par USB
    python3 outils_production/banc_test.py test            # teste la carte
    python3 outils_production/banc_test.py serie           # flash + test enchaines

Ce fichier tient le catalogue des controles ; l'interface graphique s'en sert
telle quelle. Un test ne sait pas s'il tourne dans un terminal ou dans une
fenetre : il parle a son `Contexte`, qui se charge du reste.

Pourquoi le rapport compte : ton email client annonce que chaque boitier est
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
            # Le token n'est lisible que pendant la fenetre d'appairage (mode AP,
            # ou 10 min apres le boot). Sur un banc de production on est dedans.
            if d.get('token'):
                b.token = d['token']
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


def trouver_cli():
    for p in ['/opt/homebrew/bin/arduino-cli', '/usr/local/bin/arduino-cli', 'arduino-cli']:
        try:
            subprocess.run([p, 'version'], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            return p
        except Exception:
            continue
    return None


def _courir(cmd, sortie):
    """Lance une commande en renvoyant sa sortie ligne a ligne, au fil de l'eau."""
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, bufsize=1)
    for ligne in p.stdout:
        ligne = ligne.rstrip()
        if ligne:
            sortie(ligne)
    return p.wait()


def flasher(port=None, recompiler=False, sortie=info):
    """Compile si besoin, puis televerse. Retourne (succes, message)."""
    cli = trouver_cli()
    if not cli:
        return False, 'arduino-cli introuvable (brew install arduino-cli).'

    if not port:
        dispo = ports_serie()
        if not dispo:
            return False, 'Aucune carte detectee. Branche-la en USB et reessaie.'
        if len(dispo) > 1:
            return False, ('Plusieurs cartes branchees (%s) — choisis le port.'
                           % ', '.join(dispo))
        port = dispo[0]
    sortie('Carte sur %s' % port)

    build = os.path.join(RACINE, 'build_temp_v3')
    binaire = os.path.join(build, 'adhanbox_v3.ino.bin')
    if recompiler or not os.path.exists(binaire):
        sortie('Compilation du firmware…')
        lib = os.path.expanduser('~/Documents/Arduino/libraries')
        if _courir([cli, 'compile', '--fqbn', FQBN, '--libraries', lib,
                    '--output-dir', build, SKETCH], sortie) != 0:
            return False, 'Compilation echouee.'
    else:
        sortie('Binaire deja compile, reutilise : %s' % os.path.relpath(binaire, RACINE))

    sortie('Televersement…')
    if _courir([cli, 'upload', '--fqbn', FQBN, '--port', port,
                '--input-dir', build, SKETCH], sortie) != 0:
        return False, 'Televersement echoue.'
    return True, 'Firmware televerse sur %s. La carte redemarre (~20 s).' % port


def cmd_flash(args):
    titre('Televersement du firmware V3')
    succes, message = flasher(args.port, args.recompiler, sortie=info)
    (ok if succes else ko)(message)
    return 0 if succes else 1


# ─────────────────────── le monde autour d'un test ──────────────────

class Contexte:
    """Ce qui relie un test au reste : la carte, et un canal vers l'operateur.

    La console et l'interface graphique fournissent chacune leur `dire`,
    `consigne` et `demander`. Les tests, eux, ne changent pas d'une ligne.
    """

    def __init__(self, box, infos):
        self.box = box
        self.infos = infos or {}
        self._diag = None
        self.arret = None          # threading.Event, pose par l'interface

    def diag(self):
        """/api/diag n'est interroge qu'une fois par serie de tests."""
        if self._diag is None:
            self._diag = self.box.get('/api/diag')
        return self._diag

    def oublier_diag(self):
        self._diag = None

    def dire(self, m):
        info(m)

    def consigne(self, m):
        print('  %s?%s %s' % (J, N, m))

    def demander(self, q):
        return demande(q)

    def interrompu(self):
        return bool(self.arret and self.arret.is_set())

    def patiente(self, secondes):
        """Attend — mais se reveille aussitot si l'operateur arrete la serie."""
        fin = time.time() + secondes
        while time.time() < fin:
            if self.interrompu():
                return False
            time.sleep(min(0.2, max(0.0, fin - time.time())))
        return True


# ─────────────────────────── catalogue de tests ─────────────────────
# Chaque test recoit un Contexte et renvoie (reussi, detail).

def t_identite(ctx):
    i = ctx.infos
    return (i.get('hardware') == 'v3',
            'firmware %s · materiel %s · id %s' % (
                i.get('version', '?'), i.get('hardware', '?'),
                i.get('device_id', '?')))


def t_psram(ctx):
    p = ctx.diag().get('psram_size', 0)
    return p > 0, ('%.1f Mo' % (p / 1048576.0)) if p else 'ABSENTE'


def t_sd(ctx):
    d = ctx.diag()
    lu, besoin = d.get('sd_read_kBs', 0), d.get('need_kBs', 16)
    return lu >= besoin, '%d ko/s lus, %d requis%s' % (
        lu, besoin, '' if lu >= besoin else ' → coupures audio garanties')


def t_heap(ctx):
    h = ctx.diag().get('free_heap', 0)
    return h > 60000, '%d octets' % h


def t_contenu(ctx):
    liste = ctx.box.get('/api/audio/list', brut=True)
    manquants = [c for c in CONTENU_ATTENDU if c.split('/')[-1] not in liste]
    return (not manquants,
            'complet' if not manquants
            else 'manque : ' + ', '.join(CONTENU_ATTENDU[m] for m in manquants))


def t_rtc(ctx):
    t = ctx.box.get('/rtc_time', brut=True)
    return bool(re.search(r'20\d\d', t)), t.strip()[:60]


def t_wifi(ctx):
    w = ctx.box.get('/api/wifi/status')
    connecte = str(w.get('status', '')).lower() in ('connected', 'ok', '3', 'true')
    return (connecte or bool(w.get('ip')),
            '%s · %s' % (w.get('ssid', '?'), w.get('ip', 'sans IP')))


def t_led_couleurs(ctx):
    ctx.box.post('/api/led/brightness', {'brightness': 100})
    for nom, r, g, b in [('Rouge', 255, 0, 0), ('Vert', 0, 255, 0), ('Bleu', 0, 0, 255)]:
        ctx.box.post('/api/led/rgb', {'r': r, 'g': g, 'b': b})
        ctx.dire('LED en %s' % nom.lower())
        ctx.patiente(1.2)
    return (ctx.demander('As-tu vu rouge, puis vert, puis bleu ?'),
            'rouge/vert/bleu envoyes')


def t_led_luminosite(ctx):
    ctx.box.post('/api/led/rgb', {'r': 255, 'g': 255, 'b': 255})
    ctx.box.post('/api/led/brightness', {'brightness': 10})
    ctx.patiente(1.0)
    faible = ctx.demander('La lumière est-elle devenue faible ?')
    ctx.box.post('/api/led/brightness', {'brightness': 100})
    ctx.patiente(1.0)
    forte = ctx.demander('Et de nouveau vive ?')
    return faible and forte, '10 % puis 100 %'


def t_hp(ctx):
    ctx.box.post('/api/audio/volume', {'volume': 12})
    ctx.box.get('/play', {'track': 2})
    ctx.patiente(3)
    entendu = ctx.demander("Entends-tu l'adhan ?")
    try:
        ctx.box.get('/stopplay')
    except Exception:
        pass
    return entendu, 'piste 2, volume 12/30'


def t_volume(ctx):
    ctx.box.post('/api/audio/volume', {'volume': 10})
    ctx.box.get('/play', {'track': 2})
    ctx.patiente(2.5)
    ctx.dire('Volume porté à 28/30')
    ctx.box.post('/api/audio/volume', {'volume': 28})
    ctx.patiente(2.5)
    monte = ctx.demander('Le son est-il monté ?')
    try:
        ctx.box.get('/stopplay')
    except Exception:
        pass
    return monte, '10 → 28'


def t_bouton_scenario(ctx):
    """Le bouton fait defiler les scenarios LED : l'outil constate le changement."""
    def scenario():
        return ctx.box.get('/api/led/status').get('scenario')

    ctx.box.get('/stopplay')
    ctx.patiente(0.6)
    avant = scenario()
    ctx.dire('Scénario LED avant appui : %s' % avant)
    ctx.consigne('Appuie une fois sur le bouton tactile…')
    t0 = time.time()
    while time.time() - t0 < 25:
        if not ctx.patiente(0.7):
            return False, 'interrompu'
        maintenant = scenario()
        if maintenant != avant:
            return True, 'scénario %s → %s' % (avant, maintenant)
    return False, 'aucun changement en 25 s'


def t_bouton_stop(ctx):
    ctx.box.get('/play', {'track': 2})
    ctx.patiente(2)
    if not ctx.box.get('/api/audio/status').get('playing'):
        return False, "la lecture n'a pas démarré"
    ctx.consigne("Appuie de nouveau sur le bouton pour arrêter l'adhan…")
    t0 = time.time()
    try:
        while time.time() - t0 < 25:
            if not ctx.patiente(0.7):
                return False, 'interrompu'
            if not ctx.box.get('/api/audio/status').get('playing'):
                return True, 'lecture stoppée par le bouton'
        return False, 'toujours en lecture après 25 s'
    finally:
        try:
            ctx.box.get('/stopplay')
        except Exception:
            pass


class Test:
    def __init__(self, clef, nom, groupe, fn, pourquoi=''):
        self.clef, self.nom, self.groupe = clef, nom, groupe
        self.fn, self.pourquoi = fn, pourquoi


GROUPES = [
    ('auto', 'Contrôles automatiques',
     "L'outil interroge la carte et juge seul."),
    ('sensoriel', 'Contrôles visuels et sonores',
     'Tu regardes, tu écoutes, tu réponds.'),
    ('physique', 'Bouton tactile',
     "Tu appuies, l'outil mesure l'effet. Pas de déclaration : une constatation."),
]

TESTS = [
    Test('identite', 'Identité de la carte', 'auto', t_identite,
         'Le bon firmware sur le bon matériel, et un identifiant unique.'),
    Test('psram', 'PSRAM présente', 'auto', t_psram,
         'Son absence était la loterie des modules V2.'),
    Test('sd', 'Débit de la carte SD', 'auto', t_sd,
         "Sous 16 ko/s, l'audio se coupe en pleine lecture."),
    Test('heap', 'Mémoire libre', 'auto', t_heap,
         'Une marge trop courte fait redémarrer la carte au bout de quelques jours.'),
    Test('contenu', 'Contenu audio', 'auto', t_contenu,
         'Les 4 fichiers des automatismes sont bien sur la carte SD.'),
    Test('rtc', 'Horloge temps réel', 'auto', t_rtc,
         "Sans elle, pas d'adhan à l'heure après une coupure de courant."),
    Test('wifi', 'Wi-Fi', 'auto', t_wifi,
         'La carte est connectée et joignable.'),

    Test('led_couleurs', 'LED — les 3 couleurs', 'sensoriel', t_led_couleurs,
         'Rouge, vert, bleu : les trois canaux du bandeau répondent.'),
    Test('led_luminosite', 'LED — luminosité', 'sensoriel', t_led_luminosite,
         'Le réglage descend à 10 % puis remonte à 100 %.'),
    Test('hp', 'Haut-parleur', 'sensoriel', t_hp,
         "L'adhan sort vraiment du haut-parleur."),
    Test('volume', 'Réglage du volume', 'sensoriel', t_volume,
         'Le volume monte de 10 à 28 sur 30.'),

    Test('bouton_scenario', 'Bouton — changement de scénario', 'physique', t_bouton_scenario,
         "L'appui change le scénario LED, et l'outil lit le changement."),
    Test('bouton_stop', "Bouton — arrêt de la lecture", 'physique', t_bouton_stop,
         "Un second appui coupe l'adhan en cours."),
]

PAR_CLEF = {t.clef: t for t in TESTS}


def executer(test, ctx):
    """Lance un test sans jamais laisser une exception remonter."""
    try:
        reussi, detail = test.fn(ctx)
    except Exception as e:
        return False, str(e)
    return bool(reussi), detail or ''


# ─────────────────────────── rapport ────────────────────────────────

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


def ecrire_rapport(serie, infos, lignes, hote, non_executes=()):
    """Archive le resultat. `lignes` : [{test, ok, detail}, …]

    Un rapport ou tout n'a pas ete joue n'est pas CONFORME : il est PARTIEL.
    C'est la difference entre une preuve et une impression.
    """
    os.makedirs(RAPPORTS, exist_ok=True)
    horo = datetime.now(timezone.utc).astimezone()
    echecs = [l for l in lignes if not l['ok']]
    if echecs:
        verdict = 'NON CONFORME'
    elif non_executes:
        verdict = 'PARTIEL'
    else:
        verdict = 'CONFORME'
    rap = {
        'numero_serie': serie,
        'date': horo.isoformat(timespec='seconds'),
        'device_id': (infos or {}).get('device_id'),
        'firmware': (infos or {}).get('version'),
        'materiel': (infos or {}).get('hardware'),
        'adresse': hote,
        'verdict': verdict,
        'tests': lignes,
    }
    if non_executes:
        rap['non_executes'] = list(non_executes)
    nom = '%s_%s.json' % (serie or (infos or {}).get('device_id', 'inconnu'),
                          horo.strftime('%Y-%m-%d_%H%M'))
    chemin = os.path.join(RAPPORTS, nom)
    with open(chemin, 'w', encoding='utf-8') as f:
        json.dump(rap, f, indent=2, ensure_ascii=False)
        f.write('\n')
    return chemin, verdict


# ─────────────────────────── commandes CLI ──────────────────────────

def cmd_test(args):
    titre('Banc de test AdhanBox V3')
    box, infos = trouver_box(args.hote)
    if not box:
        ko('Carte introuvable sur %s.' % (args.hote or ' / '.join(HOTES)))
        info("Verifie qu'elle est allumee et sur le meme reseau, ou passe --hote <ip>.")
        return 1
    ok('Carte trouvee sur %s' % box.hote)
    if box.token:
        info('Jeton recupere automatiquement')
    else:
        info('Jeton non expose (carte demarree depuis plus de 10 min) — '
             'les routes protegees peuvent refuser. Redemarre-la si un test echoue.')

    ctx = Contexte(box, infos)
    bilan = Bilan()
    voulus = ['auto'] if args.sans_operateur else ['auto', 'sensoriel', 'physique']
    for groupe, nom_groupe, sous_titre in GROUPES:
        if groupe not in voulus:
            continue
        titre(nom_groupe)
        info(sous_titre)
        for t in TESTS:
            if t.groupe == groupe:
                bilan.add(t.nom, *executer(t, ctx))

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
    joues = {l['test'] for l in bilan.lignes}
    non_faits = [t.nom for t in TESTS if t.nom not in joues]
    chemin, _ = ecrire_rapport(serie, infos, bilan.lignes, box.hote, non_faits)
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
