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
import select
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAPPORTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rapports')
SKETCH = os.path.join(RACINE, 'adhanbox_v3')
FQBN = 'esp32:esp32:esp32s3:PartitionScheme=min_spiffs,PSRAM=enabled,CDCOnBoot=cdc'
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

SANS_JETON = (
    "jeton refuse — la carte ne le publie plus (demarree depuis plus de "
    "10 min). Debranche-la et rebranche-la, puis reclique sur « Chercher la "
    "carte » ; ou colle le jeton a la main."
)


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
        with self._ouvrir(req) as r:
            corps = r.read().decode('utf-8', 'replace')
        return corps if brut else json.loads(corps)

    def post(self, chemin, donnees):
        data = json.dumps(donnees).encode()
        req = urllib.request.Request(self._url(chemin), data=data,
                                     headers={'Content-Type': 'application/json'})
        if self.token:
            req.add_header('X-API-Key', self.token)
        with self._ouvrir(req) as r:
            return r.read().decode('utf-8', 'replace')

    def _ouvrir(self, req):
        try:
            return urllib.request.urlopen(req, timeout=self.timeout)
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise RuntimeError(SANS_JETON)
            raise


def _supprimer_reseau(box, chemin):
    """Equivalent HTTP de BoxSerie.supprimer()."""
    try:
        box.get('/api/audio/delete', {'f': chemin}, brut=True)
        return True
    except Exception:
        return False


def trouver_box(hote_force=None, token=None):
    """Cherche la carte : hote impose, puis mDNS, puis le point d'acces.

    Le jeton n'est publie par /api/device/info que pendant la fenetre
    d'appairage (mode AP, ou 10 min apres le boot). Sur un banc on flashe puis
    on teste : on est dedans. Sur une carte allumee depuis un moment, non — d'ou
    la possibilite de le fournir soi-meme.
    """
    candidats = [hote_force] if hote_force else HOTES
    for h in candidats:
        try:
            b = Box(h, timeout=4)
            d = b.get('/api/device/info')
            b.token = token or d.get('token') or None
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


# Espressif : 0x303A. C'est ce que presente l'USB natif de l'ESP32-S3.
VENDEUR_ESPRESSIF = '12346'


def cartes_usb():
    """Cartes branchees en USB, avec ce que le systeme sait d'elles.

    Le port seul ne suffit pas : un Ozobot, un Arduino ou un cable de debug
    apparaissent tous comme /dev/cu.usbmodem*. Televerser sur le mauvais
    appareil serait au mieux inutile, au pire destructeur — on demande donc a
    ioreg QUI est derriere chaque port, et on le montre a l'operateur.
    """
    connus = {}
    try:
        r = subprocess.run(['ioreg', '-r', '-c', 'IOUSBHostDevice', '-l', '-w0'],
                           capture_output=True, text=True, timeout=10)
        courant = {}
        for ligne in r.stdout.splitlines():
            # ioreg imprime en profondeur d'abord : les attributs d'un
            # peripherique precedent toujours le port de son sous-arbre.
            for cle, champ in (('"USB Vendor Name"', 'fabricant'),
                               ('"USB Product Name"', 'produit'),
                               ('"USB Serial Number"', 'serie'),
                               ('"idVendor"', 'vendeur')):
                if cle in ligne and '=' in ligne:
                    courant[champ] = ligne.split('=', 1)[1].strip().strip('"')
            if '"IOCalloutDevice"' in ligne and '=' in ligne:
                port = ligne.split('=', 1)[1].strip().strip('"')
                connus[port] = dict(courant)
    except Exception:
        pass

    cartes = []
    for port in ports_serie():
        d = connus.get(port, {})
        cartes.append({
            'port': port,
            'fabricant': d.get('fabricant', 'inconnu'),
            'produit': d.get('produit', ''),
            'serie': d.get('serie', ''),
            'espressif': d.get('vendeur') == VENDEUR_ESPRESSIF,
        })
    return cartes


def qui_occupe_port(port):
    """Quel programme tient ce port ? Rend une phrase, ou None.

    Sur macOS un port serie s'ouvre en exclusivite. Le moniteur serie de
    l'Arduino IDE le reprend des qu'une carte reapparait — et il le reprend
    APRES chaque televersement, donc le probleme revient a chaque carte.
    esptool ne dit alors que « Resource busy », ce qui envoie chercher au
    mauvais endroit : le cable, la carte, le firmware.

    On n'appelle CECI QU'APRES un echec, jamais en prevention : le
    serial-discovery d'Arduino ouvre les ports au vol pour les detecter, et
    refuser un televersement sur cette base bloquerait des cartes saines.
    """
    try:
        # Surtout pas de -t : il annule -F et ne rend que des numeros de
        # processus, jamais leur nom — donc jamais de diagnostic lisible.
        r = subprocess.run(['lsof', '-F', 'cn', port],
                           capture_output=True, text=True, timeout=6)
    except Exception:
        return None
    noms = [l[1:] for l in r.stdout.splitlines() if l.startswith('c')]
    noms = [n for n in noms if n]
    if not noms:
        return None
    if any('serial-mo' in n or 'arduino' in n.lower() for n in noms):
        return ("le moniteur serie de l'Arduino IDE occupe ce port. "
                "Ferme-le dans l'IDE (icone loupe, ou Ctrl+Maj+M) et reessaie.")
    return ('le port est occupe par « %s ». Ferme ce programme et reessaie.'
            % noms[0])


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
    trace = []

    def tracer(ligne):
        trace.append(ligne)
        sortie(ligne)

    if _courir([cli, 'upload', '--fqbn', FQBN, '--port', port,
                '--input-dir', build, SKETCH], tracer) != 0:
        texte = '\n'.join(trace).lower()
        if 'busy' in texte or 'resource busy' in texte or 'could not open' in texte:
            occupant = qui_occupe_port(port)
            if occupant:
                return False, 'Televersement impossible : %s' % occupant
            return False, ('Televersement impossible : le port est pris par un '
                           'autre programme. Le moniteur serie de l\'Arduino IDE '
                           'en est la cause la plus frequente — ferme-le.')
        return False, 'Televersement echoue.'
    return True, 'Firmware televerse sur %s. La carte redemarre (~20 s).' % port


def cmd_flash(args):
    titre('Televersement du firmware V3')
    succes, message = flasher(args.port, args.recompiler, sortie=info)
    (ok if succes else ko)(message)
    return 0 if succes else 1


# ───────────────────── preparation de la carte SD ───────────────────

# Contenu de reference a copier sur chaque carte. ADHANBOX_SD_SOURCE permet
# de le deplacer (disque externe, autre machine) sans toucher au code.
SD_SOURCE = os.environ.get('ADHANBOX_SD_SOURCE') or os.path.join(RACINE, 'sd_preload')

# Residus que macOS seme sur toute carte qu'il monte.
DOSSIERS_INDESIRABLES = ('.Spotlight-V100', '.fseventsd', '.Trashes',
                         '.TemporaryItems', '.DocumentRevisions-V100')


def _diskutil(chemin):
    """Infos diskutil d'un volume, en dictionnaire."""
    try:
        r = subprocess.run(['diskutil', 'info', chemin],
                           capture_output=True, text=True, timeout=8)
    except Exception:
        return {}
    d = {}
    for ligne in r.stdout.splitlines():
        if ':' in ligne:
            cle, _, val = ligne.partition(':')
            d[cle.strip()] = val.strip()
    return d


def est_amovible(chemin):
    """Ce volume est-il une carte, et non le disque de demarrage ?

    Garde-fou central : on va ecrire 4,7 Go. Se tromper de cible n'est pas
    une option, donc on exige que diskutil confirme « External » ou
    « Removable » — sans quoi on refuse.
    """
    d = _diskutil(chemin)
    if not d:
        return False, 'volume inconnu de diskutil'
    if d.get('Read-Only Volume') == 'Yes':
        return False, 'volume en lecture seule'
    if d.get('Device Location') == 'External' or d.get('Removable Media') == 'Removable':
        return True, d.get('File System Personality', '?')
    return False, 'volume interne (%s) — refuse' % d.get('Device Location', '?')


def cartes_sd():
    """Cartes montees, prêtes a recevoir le contenu."""
    trouvees = []
    try:
        noms = sorted(os.listdir('/Volumes'))
    except OSError:
        return trouvees
    for nom in noms:
        chemin = os.path.join('/Volumes', nom)
        if not os.path.isdir(chemin):
            continue
        amovible, detail = est_amovible(chemin)
        if not amovible:
            continue
        try:
            st = os.statvfs(chemin)
        except OSError:
            continue
        trouvees.append({
            'chemin': chemin,
            'nom': nom,
            'systeme': detail,
            'libre': st.f_bavail * st.f_frsize,
            'total': st.f_blocks * st.f_frsize,
        })
    return trouvees


def contenu_source(source=None):
    """Fichiers de reference a copier : (chemin relatif, absolu, taille)."""
    source = source or SD_SOURCE
    fichiers = []
    for dossier, sous, noms in os.walk(source):
        sous[:] = [d for d in sous if not d.startswith('.')]
        for n in noms:
            if n.startswith('.'):
                continue
            absolu = os.path.join(dossier, n)
            try:
                taille = os.path.getsize(absolu)
            except OSError:
                continue
            fichiers.append((os.path.relpath(absolu, source), absolu, taille))
    return sorted(fichiers)


def nettoyer_volume(volume):
    """Supprime les residus macOS. Retourne le nombre d'entrees enlevees."""
    import shutil
    n = 0
    for dossier, sous, noms in os.walk(volume, topdown=True):
        for d in list(sous):
            if d in DOSSIERS_INDESIRABLES:
                shutil.rmtree(os.path.join(dossier, d), ignore_errors=True)
                sous.remove(d)
                n += 1
        for f in noms:
            if f.startswith('._') or f == '.DS_Store':
                try:
                    os.remove(os.path.join(dossier, f))
                    n += 1
                except OSError:
                    pass
    return n


def preparer_carte(volume, source=None, sortie=info, avancement=None, arret=None):
    """Copie le contenu de reference sur la carte. Retourne (succes, message).

    shutil.copyfile ne copie QUE les octets : ni attributs etendus, ni fork de
    ressource. macOS n'a donc rien a deporter dans un jumeau « ._ » — les
    doublons invisibles sont ecartes PAR CONSTRUCTION, pas nettoyes apres coup.
    C'est la difference avec un glisser-deposer dans le Finder.
    """
    import shutil
    source = source or SD_SOURCE

    if not os.path.isdir(source):
        return False, 'Contenu de reference introuvable : %s' % source
    fichiers = contenu_source(source)
    if not fichiers:
        return False, 'Aucun fichier dans %s' % source

    amovible, detail = est_amovible(volume)
    if not amovible:
        return False, 'Cible refusee : %s' % detail

    total_octets = sum(t for _, _, t in fichiers)
    try:
        st = os.statvfs(volume)
        libre = st.f_bavail * st.f_frsize
    except OSError as e:
        return False, 'Volume illisible (%s)' % e

    deja = 0
    for rel, _, taille in fichiers:
        cible = os.path.join(volume, rel)
        if os.path.exists(cible) and os.path.getsize(cible) == taille:
            deja += taille
    besoin = total_octets - deja
    if besoin > libre:
        return False, ('Place insuffisante : %.1f Go a ecrire, %.1f Go libres.'
                       % (besoin / 1e9, libre / 1e9))

    sortie('%d fichiers · %.1f Go · destination %s (%s)'
           % (len(fichiers), total_octets / 1e9, volume, detail))

    copies = ignores = 0
    ecrits = 0
    for i, (rel, absolu, taille) in enumerate(fichiers, 1):
        if arret and arret.is_set():
            return False, 'Interrompu apres %d fichiers.' % copies
        cible = os.path.join(volume, rel)
        try:
            if os.path.exists(cible) and os.path.getsize(cible) == taille:
                ignores += 1
            else:
                os.makedirs(os.path.dirname(cible), exist_ok=True)
                shutil.copyfile(absolu, cible)   # octets seuls : aucun jumeau ._
                copies += 1
            ecrits += taille
        except Exception as e:
            return False, 'Echec sur %s : %s' % (rel, e)
        if avancement:
            avancement(i, len(fichiers), ecrits, total_octets, rel)
        if i % 25 == 0 or i == len(fichiers):
            sortie('  %d/%d fichiers — %.1f Go' % (i, len(fichiers), ecrits / 1e9))

    sortie('Nettoyage des residus macOS…')
    enleves = nettoyer_volume(volume)

    # Verification : ce qui est sur la carte correspond-il a la reference ?
    manquants = [rel for rel, _, taille in fichiers
                 if not os.path.exists(os.path.join(volume, rel))
                 or os.path.getsize(os.path.join(volume, rel)) != taille]
    fantomes = sum(1 for d, _, ns in os.walk(volume) for n in ns if n.startswith('._'))
    if manquants:
        return False, '%d fichiers manquants ou incomplets apres copie.' % len(manquants)

    return True, ('Carte prête : %d fichiers copies, %d deja a jour, '
                  '%d residus enleves, %d fantomes.'
                  % (copies, ignores, enleves, fantomes))


# ───────────────────── liaison serie (carte neuve) ──────────────────

class BoxSerie:
    """La meme carte, vue par le cable USB au lieu du reseau.

    Une carte neuve n'a pas d'identifiants Wi-Fi : elle part en appairage BLE
    au demarrage et reste injoignable par HTTP. Mais elle est deja au bout du
    cable qui vient de servir a la flasher.

    Cette classe presente EXACTEMENT la surface de `Box` — `get`, `post`,
    `hote`, `token`. Les 14 controles passent par leur `Contexte` et ne savent
    donc pas par ou ils parlent : aucun n'a eu besoin d'etre retouche.

    Sans pyserial : `stty` configure le port, `select` borne les attentes. Le
    banc garde ainsi sa propriete la plus utile — rien a installer, sur
    n'importe quel Mac.
    """

    def __init__(self, port, timeout=12):
        self.hote = port
        self.token = 'usb'                  # le cable vaut authentification
        self.timeout = timeout
        subprocess.run(['stty', '-f', port, '115200', 'cs8', '-cstopb',
                        '-parenb', 'raw', '-echo'],
                       check=True, capture_output=True, timeout=5)
        self._fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)

    def fermer(self):
        fd, self._fd = getattr(self, '_fd', None), None
        if fd is None:
            return
        try:
            os.close(fd)
        except Exception:
            pass

    def __del__(self):
        # Dernier filet : un descripteur oublie garderait le port pris, et
        # ferait echouer le televersement suivant sur « Resource busy ».
        self.fermer()

    def _lignes(self, fin_attente):
        """Rend les lignes recues jusqu'a l'echeance."""
        tampon = b''
        while time.time() < fin_attente:
            pret, _, _ = select.select([self._fd], [], [],
                                       max(0.05, fin_attente - time.time()))
            if not pret:
                continue
            try:
                morceau = os.read(self._fd, 4096)
            except BlockingIOError:
                continue
            if not morceau:
                continue
            tampon += morceau
            while b'\n' in tampon:
                ligne, tampon = tampon.split(b'\n', 1)
                yield ligne.decode('utf-8', 'replace').strip()

    def _commande(self, texte, attente=None):
        """Envoie une commande et rend la ligne <BANC> correspondante.

        La carte parle beaucoup au demarrage : on ne retient que les lignes
        prefixees, et on ignore tout le reste.
        """
        try:
            while select.select([self._fd], [], [], 0)[0]:
                if not os.read(self._fd, 4096):
                    break
        except (BlockingIOError, OSError):
            pass
        os.write(self._fd, ('t:%s\n' % texte).encode())
        for ligne in self._lignes(time.time() + (attente or self.timeout)):
            if ligne.startswith('<BANC>'):
                return ligne[6:]
        raise RuntimeError('pas de reponse de la carte sur %s (commande « %s »)'
                           % (self.hote, texte))

    def get(self, chemin, params=None, brut=False):
        if chemin == '/api/audio/list':
            # Pas d'equivalent direct : `ls` travaille dossier par dossier, ce
            # qui evite de construire 456 entrees dans la RAM de l'ESP32. On
            # recompose la meme liste de chemins complets que la route HTTP —
            # /quran exclu, exactement comme v2ListDir.
            fichiers = []
            for dossier in ('/azkar', '/mp3'):
                try:
                    fichiers += ['%s/%s' % (dossier, n) for n in self.lister(dossier)]
                except Exception:
                    pass
            return fichiers

        cmd = self._traduire(chemin, params or {})
        # Le banc de debit SD lit 256 ko a 1 MHz : il lui faut sa minute.
        corps = self._commande(cmd, attente=30 if chemin == '/api/diag' else None)
        if brut:
            # Certaines routes repondent en text/plain cote HTTP. On rend la
            # MEME chose ici, sinon les controles lisent autre chose selon le
            # transport — c'est ce qui a fait dire « Stopped » a l'horloge.
            if chemin == '/play':
                return 'Playing'
            if chemin == '/stopplay':
                return 'Stopped'
            if chemin == '/rtc_time':
                return 'RTC: %s' % json.loads(corps).get('time', '')
            return corps
        d = json.loads(corps)
        if chemin == '/api/audio/play' and d.get('exists') is False:
            raise urllib.error.HTTPError(chemin, 404, 'absent', None, None)
        if chemin == '/api/audio/play' and 'started' not in d:
            d['started'] = d.get('exists', False)
        return d

    def post(self, chemin, donnees):
        return self._commande(self._traduire(chemin, donnees))

    def _traduire(self, chemin, d):
        """Le seul endroit qui connaisse les deux transports."""
        table = {
            '/api/device/info': lambda: 'info',
            '/api/diag': lambda: 'diag',
            '/rtc_time': lambda: 'rtc',
            '/api/wifi/status': lambda: 'wifi',
            '/api/led/status': lambda: 'ledstatus',
            '/api/audio/status': lambda: 'audiostatus',
            '/stopplay': lambda: 'stop',
            '/play': lambda: 'track %s' % d.get('track', 1),
            '/api/audio/play': lambda: 'play %s' % d.get('f', ''),
            '/api/audio/volume': lambda: 'vol %s' % d.get('vol', d.get('volume', 15)),
            '/api/led/brightness': lambda: 'bright %s' % d.get('bright', d.get('brightness', 100)),
            '/api/led/rgb': lambda: 'rgb %s %s %s' % (d.get('r', 0), d.get('g', 0), d.get('b', 0)),
            '/api/led/scenario': lambda: 'led %s' % d.get('scenario', 0),
        }
        if chemin not in table:
            raise RuntimeError('chemin sans equivalent serie : %s' % chemin)
        return table[chemin]()

    def lister(self, dossier):
        """Contenu d'un dossier de la carte SD (non recursif)."""
        return json.loads(self._commande('ls %s' % dossier))

    def supprimer(self, chemin):
        """Supprime un fichier. Le firmware refuse tout ce qui n'est pas « ._ »."""
        return json.loads(self._commande('rm %s' % chemin)).get('supprime', False)

    def scan_wifi(self):
        """Nombre de reseaux visibles. Eprouve la radio, pas la connexion."""
        return int(json.loads(self._commande('wifiscan', attente=30))
                   .get('reseaux', 0))

    def etat_usine(self):
        """Ce qui distingue une carte configuree d'une carte neuve :
        Wi-Fi memorise, mosquee, position. Lu avant ET apres la remise a zero."""
        return json.loads(self._commande('usinestatus'))

    def usine(self):
        """Demande la remise a zero. La carte repond puis REDEMARRE : le port
        tombe, il faut le rouvrir (voir remise_a_zero)."""
        return json.loads(self._commande('usine', attente=20))


def trouver_box_serie(port=None):
    """Ouvre la liaison serie avec une carte, et lit son identite.

    Retourne (box, infos) comme trouver_box(), pour que la suite ne voie pas
    la difference.
    """
    if not port:
        candidates = [c for c in cartes_usb() if c['espressif']]
        if not candidates:
            return None, None
        port = candidates[0]['port']
    try:
        b = BoxSerie(port)
    except Exception as e:
        occupant = qui_occupe_port(port)
        raise RuntimeError(occupant or
                           'ouverture de %s impossible (%s)' % (port, e))
    # Ouvrir le port peut faire redemarrer la carte, et elle passe alors par
    # ~15 s de demarrage avant de repondre. On insiste plutot que d'abandonner.
    fin = time.time() + 40
    derniere = None
    try:
        while time.time() < fin:
            try:
                return b, b.get('/api/device/info')
            except Exception as e:
                derniere = e
                time.sleep(1.5)
    except BaseException:
        b.fermer()
        raise
    b.fermer()      # sans ca, le port resterait pris pour le flash suivant
    raise RuntimeError(
        'la carte ne repond pas sur %s. Porte-t-elle bien un firmware V3 '
        'recent ? Televerse-le, puis reessaie. (%s)' % (port, derniere))


def _configuree(etat):
    """Vrai si la carte porte encore quelque chose d'un atelier ou d'un client."""
    return bool(etat.get('saved_ssid') or etat.get('mq_uuid') or etat.get('lat'))


def remise_a_zero(box, sortie=info):
    """Remet la carte comme au premier allumage, et le PROUVE.

    Au banc, chaque carte est appairee sur le Wi-Fi de l'atelier pour etre
    testee. Sans ce nettoyage, le client recevrait une carte qui cherche un
    reseau qui n'existe pas chez lui, avec une mosquee et un jeton deja
    poses. Le firmware efface la NVS entiere et redemarre ; ici on rouvre le
    cable et on relit l'etat : le verdict vient de cette relecture, jamais de
    la reponse a l'ordre d'effacement.

    Reserve au cable. Par le reseau, une remise a zero pourrait atteindre la
    carte d'un client — le banc ne l'offre donc tout simplement pas.

    Rend (reussi, message, box, infos) : la carte a redemarre, l'appelant doit
    reprendre le NOUVEAU couple box/infos, l'ancien descripteur est mort.
    """
    if not isinstance(box, BoxSerie):
        return False, 'remise a zero possible par le cable uniquement', box, None
    port = box.hote
    avant = box.etat_usine()
    sortie('Avant : Wi-Fi « %s », mosquee %s, position %s.'
           % (avant.get('saved_ssid') or '—',
              'posee' if avant.get('mq_uuid') else '—',
              'posee' if avant.get('lat') else '—'))
    try:
        rep = box.usine()
    except RuntimeError as e:
        # La carte peut rebooter avant que sa reponse ne traverse : on ne
        # conclut rien ici, la relecture tranchera.
        sortie('Pas de reponse a l\'ordre (%s) — on juge sur la relecture.' % e)
        rep = {}
    else:
        nvs = rep.get('nvs', {})
        sortie('Ordre recu : ok=%s, nvs deinit/erase/init = %s/%s/%s.'
               % (rep.get('ok'), nvs.get('deinit'), nvs.get('erase'), nvs.get('init')))
    box.fermer()
    sortie('Redemarrage de la carte, reouverture du cable %s…' % port)
    time.sleep(3)                     # le port USB tombe et revient
    box2, infos2 = trouver_box_serie(port)     # insiste 40 s, comme au flash
    apres = box2.etat_usine()
    if not apres.get('wifi_init'):
        # Sans pilote Wi-Fi demarre, on ne peut PAS lire les identifiants :
        # dire « efface » serait une promesse, pas une mesure.
        return (False, 'pilote Wi-Fi non demarre apres reboot : identifiants '
                'invérifiables — relance le controle', box2, infos2)
    if _configuree(apres):
        return (False, 'la carte garde encore : Wi-Fi « %s », mosquee %s, '
                'position %s' % (apres.get('saved_ssid') or '—',
                                 apres.get('mq_uuid') or '—',
                                 apres.get('lat') or '—'), box2, infos2)
    if not apres.get('api_token'):
        return (False, 'jeton d\'API non regenere au redemarrage', box2, infos2)
    return (True, 'carte vierge — aucun Wi-Fi, aucune mosquee, aucune position ; '
            'jeton regenere (firmware %s)' % (infos2 or {}).get('version', '?'),
            box2, infos2)


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

    def stop_lecture(self):
        """/stopplay repond en text/plain : ne jamais le lire comme du JSON."""
        try:
            self.box.get('/stopplay', brut=True)
        except Exception:
            pass

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


def taille_reference(chemin):
    """Taille attendue d'apres sd_preload, ou None si la reference manque."""
    p = os.path.join(SD_SOURCE, chemin.lstrip('/'))
    try:
        return os.path.getsize(p)
    except OSError:
        return None


def t_contenu(ctx):
    """Les 4 automatismes doivent pouvoir demarrer.

    Surtout PAS via /api/audio/list : v2ListDir exclut volontairement /quran de
    cette liste (les 456 recitations feraient expirer l'app). Al-Kahf et Al-Mulk
    n'y figurent donc jamais, meme presentes. On les ouvre une par une, comme le
    fait v2Fire() a l'heure dite — ce qui prouve davantage qu'une existence :
    que le decodeur demarre vraiment.
    """
    presents, manquants = [], []
    for chemin, nom in CONTENU_ATTENDU.items():
        try:
            r = ctx.box.get('/api/audio/play', {'f': chemin})
            taille = r.get('size', 0)
            attendu = taille_reference(chemin)
            if attendu is not None and taille != attendu:
                # « Present » ne veut pas dire « utilisable » : une copie
                # interrompue laisse un fichier de la bonne taille zero.
                manquants.append('%s (%d octets au lieu de %d — copie incomplete)'
                                 % (nom, taille, attendu))
            elif r.get('started'):
                presents.append('%s %.1f Mo' % (nom, taille / 1048576.0))
            else:
                manquants.append('%s (presente mais ne demarre pas)' % nom)
        except urllib.error.HTTPError as e:
            manquants.append('%s (%s)' % (nom, 'absente' if e.code == 404 else e))
        except Exception as e:
            manquants.append('%s (%s)' % (nom, e))
        finally:
            try:
                ctx.box.get('/stopplay', brut=True)
            except Exception:
                pass
    return (not manquants,
            'les 4 demarrent — ' + ', '.join(presents) if not manquants
            else 'manque : ' + ', '.join(manquants))


def t_adhans(ctx):
    """Les pistes d'adhan, celles que /play joue par numero.

    Aucun controle ne les regardait : le boitier d'atelier fonctionnait, donc
    on n'a jamais vu qu'une carte neuve pouvait porter un /mp3/0002.mp3 de
    zero octet. La lecture « demarre » et se termine aussitot : silence, sans
    la moindre erreur.
    """
    pistes = sorted(f for f in os.listdir(os.path.join(SD_SOURCE, 'mp3'))
                    if f.endswith('.mp3')) if os.path.isdir(
                        os.path.join(SD_SOURCE, 'mp3')) else []
    if not pistes:
        return False, 'contenu de reference introuvable (%s)' % SD_SOURCE

    bons, mauvais = 0, []
    for nom in pistes:
        chemin = '/mp3/' + nom
        attendu = taille_reference(chemin)
        try:
            r = ctx.box.get('/api/audio/play', {'f': chemin})
            taille = r.get('size', 0)
        except urllib.error.HTTPError as e:
            mauvais.append('%s (%s)' % (nom, 'absent' if e.code == 404 else e))
            continue
        except Exception as e:
            mauvais.append('%s (%s)' % (nom, e))
            continue
        finally:
            ctx.stop_lecture()
        if taille != attendu:
            mauvais.append('%s : %d octets au lieu de %d' % (nom, taille, attendu))
        else:
            bons += 1

    if mauvais:
        return False, 'copie incomplete — ' + ' ; '.join(mauvais)
    return True, '%d pistes conformes a la reference' % bons


def _jumeau_fantome(chemin):
    """/azkar/masaa.mp3 -> /azkar/._masaa.mp3"""
    dossier, _, nom = chemin.rpartition('/')
    return '%s/._%s' % (dossier, nom)


def t_fantomes(ctx):
    """Les ._X.mp3 que macOS depose a chaque copie sur la carte SD.

    v2ListDir ne filtre que les DOSSIERS caches, pas les fichiers : ces jumeaux
    portent l'extension .mp3, l'app les affiche donc dans sa liste, et un client
    peut en choisir un — qui ne jouera rien.
    """
    trouves = []
    for chemin in ctx.box.get('/api/audio/list'):
        n = chemin.rpartition('/')[2]
        if n.startswith('._') or n == '.DS_Store':
            trouves.append(chemin)

    # Par le cable on peut lister /quran directement — et y trouver les
    # jumeaux des DOSSIERS (._afs, ._dosari…), que l'interrogation fichier par
    # fichier ne pouvait pas voir.
    lister = getattr(ctx.box, 'lister', None)
    if lister is not None:
        for dossier in ('/quran', '/quran/afs', '/quran/dosari',
                        '/quran/ghamdi', '/quran/maher'):
            try:
                for n in lister(dossier):
                    if n.startswith('._') or n == '.DS_Store':
                        trouves.append('%s/%s' % (dossier, n))
            except Exception:
                pass
        reserve = ''
        if not trouves:
            return True, 'aucun' + reserve
        apercu = ', '.join(trouves[:3])
        reste = len(trouves) - 3
        return False, '%d trouves : %s%s' % (
            len(trouves), apercu, ' … +%d autres' % reste if reste > 0 else '')

    # Par le reseau, /quran est invisible (v2ListDir l'exclut) : on ne peut
    # interroger que les jumeaux des deux sourates automatisees.
    quran_vu = True
    for chemin in CONTENU_ATTENDU:
        if not chemin.startswith('/quran'):
            continue
        jumeau = _jumeau_fantome(chemin)
        try:
            ctx.box.get('/api/audio/play', {'f': jumeau})
            trouves.append(jumeau)
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
        except RuntimeError:
            quran_vu = False        # jeton absent : on ne peut pas regarder
            break
        finally:
            ctx.stop_lecture()

    reserve = '' if quran_vu else ' (/quran non verifie : jeton absent)'
    if not trouves:
        return True, 'aucun' + reserve
    apercu = ', '.join(trouves[:3])
    reste = len(trouves) - 3
    return False, '%d trouves : %s%s%s' % (
        len(trouves), apercu, ' … +%d autres' % reste if reste > 0 else '', reserve)


def t_rtc(ctx):
    t = ctx.box.get('/rtc_time', brut=True)
    return bool(re.search(r'20\d\d', t)), t.strip()[:60]


def t_wifi(ctx):
    """Au banc, une carte neuve n'a aucun identifiant Wi-Fi.

    La juger sur « est-elle connectee ? » n'aurait aucun sens — et la faire
    passer parce que l'IP vaut « 0.0.0.0 » serait pire : le rapport
    affirmerait un Wi-Fi fonctionnel sans l'avoir constate. On verifie donc ce
    qui EST verifiable a ce stade : que la radio voit des reseaux. C'est ce
    qui attrape une antenne mal soudee.
    """
    w = ctx.box.get('/api/wifi/status')
    ip = str(w.get('ip', '') or '')
    connecte = (str(w.get('status', '')).lower() in ('connected', 'ok', '3', 'true')
                and ip not in ('', '0.0.0.0'))
    if connecte:
        return True, '%s · %s' % (w.get('ssid', '?'), ip)

    scan = getattr(ctx.box, 'scan_wifi', None)
    if scan is None:
        return False, 'non connectee (%s)' % (ip or 'sans IP')
    vus = scan()
    return vus > 0, ('radio active — %d reseaux vus (carte non connectee, '
                     'normal au banc)' % vus if vus > 0
                     else 'radio muette : aucun reseau vu — antenne ?')


def t_led_couleurs(ctx):
    ctx.box.post('/api/led/brightness', {'bright': 100})
    for nom, r, g, b in [('Rouge', 255, 0, 0), ('Vert', 0, 255, 0), ('Bleu', 0, 0, 255)]:
        ctx.box.post('/api/led/rgb', {'r': r, 'g': g, 'b': b})
        ctx.dire('LED en %s' % nom.lower())
        ctx.patiente(1.2)
    return (ctx.demander('As-tu vu rouge, puis vert, puis bleu ?'),
            'rouge/vert/bleu envoyes')


def t_led_luminosite(ctx):
    ctx.box.post('/api/led/rgb', {'r': 255, 'g': 255, 'b': 255})
    ctx.box.post('/api/led/brightness', {'bright': 10})
    ctx.patiente(1.0)
    faible = ctx.demander('La lumière est-elle devenue faible ?')
    ctx.box.post('/api/led/brightness', {'bright': 100})
    ctx.patiente(1.0)
    forte = ctx.demander('Et de nouveau vive ?')
    return faible and forte, '10 % puis 100 %'


def t_hp(ctx):
    ctx.box.post('/api/audio/volume', {'vol': 12})
    ctx.box.get('/play', {'track': 2}, brut=True)
    ctx.patiente(3)
    entendu = ctx.demander("Entends-tu l'adhan ?")
    ctx.stop_lecture()
    return entendu, 'piste 2, volume 12/30'


def t_volume(ctx):
    ctx.box.post('/api/audio/volume', {'vol': 10})
    ctx.box.get('/play', {'track': 2}, brut=True)
    ctx.patiente(2.5)
    ctx.dire('Volume porté à 28/30')
    ctx.box.post('/api/audio/volume', {'vol': 28})
    ctx.patiente(2.5)
    monte = ctx.demander('Le son est-il monté ?')
    ctx.stop_lecture()
    return monte, '10 → 28'


def t_bouton_scenario(ctx):
    """Le bouton fait defiler les scenarios LED : l'outil constate le changement."""
    def scenario():
        return ctx.box.get('/api/led/status').get('scenario')

    ctx.stop_lecture()
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
    ctx.box.get('/play', {'track': 2}, brut=True)
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
        ctx.stop_lecture()


def reparer_fantomes(ctx, sortie=info):
    """Supprime les jumeaux « ._ » trouves par le controle.

    On relit la carte plutot que de se fier a un resultat affiche : entre le
    controle et le clic, l'operateur a pu changer de carte SD.
    """
    trouves = []
    for chemin in ctx.box.get('/api/audio/list'):
        if chemin.rpartition('/')[2].startswith('._'):
            trouves.append(chemin)
    for chemin in CONTENU_ATTENDU:
        if not chemin.startswith('/quran'):
            continue
        jumeau = _jumeau_fantome(chemin)
        try:
            ctx.box.get('/api/audio/play', {'f': jumeau})
            trouves.append(jumeau)
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
        except RuntimeError:
            pass                       # jeton absent : on ne peut pas regarder
        finally:
            ctx.stop_lecture()

    if not trouves:
        return True, 'aucun fantome a supprimer'

    supprimer = getattr(ctx.box, 'supprimer', None)
    if supprimer is None:
        supprimer = lambda c: _supprimer_reseau(ctx.box, c)

    faits, rates = 0, []
    for chemin in trouves:
        # Ceinture et bretelles : le firmware refuse deja tout ce qui n'est
        # pas un jumeau, mais on ne lui envoie que ca.
        if not chemin.rpartition('/')[2].startswith('._'):
            continue
        if supprimer(chemin):
            faits += 1
            sortie('supprime %s' % chemin)
        else:
            rates.append(chemin)
    if rates:
        return False, '%d supprimes, %d resistants : %s' % (
            faits, len(rates), ', '.join(rates[:3]))
    return True, '%d fichiers fantomes supprimes' % faits


class Test:
    def __init__(self, clef, nom, groupe, fn, pourquoi='', reparation=None):
        self.clef, self.nom, self.groupe = clef, nom, groupe
        self.fn, self.pourquoi = fn, pourquoi
        # (libelle, fonction) : un controle qui sait se reparer propose son
        # bouton. L'interface n'a rien de particulier a savoir.
        self.reparation = reparation


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
    Test('adhans', 'Pistes d\'adhan', 'auto', t_adhans,
         'Les 6 pistes jouees par numero, comparees a la reference — '
         'un fichier vide ne fait aucun bruit et aucune erreur.'),
    Test('contenu', 'Contenu audio', 'auto', t_contenu,
         'Les 4 fichiers des automatismes s\'ouvrent et démarrent vraiment.'),
    Test('fantomes', 'Fichiers fantômes macOS', 'auto', t_fantomes,
         "macOS depose un ._X.mp3 par fichier copie : l'app les affiche, "
         "et ils ne jouent rien.",
         reparation=('Supprimer ces fichiers', reparer_fantomes)),
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


def ecrire_rapport(serie, infos, lignes, hote, non_executes=(), remise_a_zero=None):
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
    # Preuve que la carte est partie vierge — ou constat qu'elle ne l'est pas.
    # Ce n'est pas un test : le verdict n'en depend pas, mais l'archive le dit.
    rap['remise_a_zero'] = remise_a_zero or {'faite': False}
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
    box, infos = trouver_box(args.hote, getattr(args, 'jeton', None))
    if not box:
        ko('Carte introuvable sur %s.' % (args.hote or ' / '.join(HOTES)))
        info("Verifie qu'elle est allumee et sur le meme reseau, ou passe --hote <ip>.")
        return 1
    ok('Carte trouvee sur %s' % box.hote)
    if box.token:
        info('Jeton en main')
    else:
        ko('Jeton non publie : les controles LED et audio seront refuses.')
        info('Debranche/rebranche la carte et relance, ou passe --jeton <valeur>.')

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


def cmd_usine(args):
    titre('Remise a zero usine')
    try:
        box, infos = trouver_box_serie(args.port)
    except Exception as e:
        ko(str(e))
        return 1
    if not box:
        ko('Aucune carte Espressif sur USB.')
        return 1
    ok('Carte %s (firmware %s)' % (box.hote, (infos or {}).get('version', '?')))
    if not args.oui and not demande('Effacer Wi-Fi, mosquee, position et jeton de cette carte'):
        info('Rien fait.')
        return 0
    reussi, message, box, _ = remise_a_zero(box)
    (ok if reussi else ko)(message)
    if box:
        box.fermer()
    return 0 if reussi else 2


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
    t.add_argument('--jeton', help="jeton d'API, si la carte ne le publie plus")
    t.add_argument('--sans-operateur', action='store_true',
                   help='ne lance que les controles automatiques')
    t.set_defaults(fn=cmd_test)

    s = sp.add_parser('serie', help='flash puis test, enchaines')
    s.add_argument('--port')
    s.add_argument('--hote')
    s.add_argument('--serie')
    s.add_argument('--jeton')
    s.add_argument('--recompiler', action='store_true')
    s.add_argument('--sans-operateur', action='store_true')
    s.set_defaults(fn=cmd_serie)

    u = sp.add_parser('usine', help='remet une carte comme au premier allumage (cable USB)')
    u.add_argument('--port', help='port serie (auto-detecte sinon)')
    u.add_argument('--oui', action='store_true', help='ne demande pas confirmation')
    u.set_defaults(fn=cmd_usine)

    args = p.parse_args()
    try:
        sys.exit(args.fn(args))
    except KeyboardInterrupt:
        print('\n  Interrompu.')
        sys.exit(130)


if __name__ == '__main__':
    main()
