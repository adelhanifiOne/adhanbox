#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Banc de production AdhanBox V3 — interface graphique
====================================================

    python3 outils_production/banc_gui.py

Ouvre une fenetre dans le navigateur. Chaque controle a son bouton : tu lances
celui que tu veux, quand tu veux, autant de fois que tu veux. Le bouton « Tout
tester » enchaine simplement toute la liste.

Rien a installer : un petit serveur local en bibliotheque standard, et une page
qui l'interroge. Les tests eux-memes vivent dans banc_test.py — cette interface
ne fait que les declencher et montrer ce qu'ils repondent.
"""

import errno
import json
import os
import subprocess
import sys
import threading
import time
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import banc_test as bt   # noqa: E402

PORT_WEB = 8765


# ─────────────────────────── la session ─────────────────────────────

class Session:
    """L'etat du banc : une carte, des resultats, un test en cours.

    Un seul thread de travail a la fois — on ne teste qu'une carte, et les
    controles se marchent dessus s'ils tournent en parallele (le haut-parleur
    ne peut pas jouer deux pistes).
    """

    def __init__(self):
        self.verrou = threading.RLock()
        self.box = None
        self.infos = {}
        self.resultats = {}          # clef -> {ok, detail, horo}
        self.en_cours = None
        self.consigne = None         # instruction affichee en grand
        self.question = None         # question fermee posee a l'operateur
        self.reponse = None
        self.repondu = threading.Event()
        self.arret = threading.Event()
        self.travail = None
        self.journal = []
        self.flash_actif = False
        self.copie = None            # avancement de la preparation de carte SD
        self.dernier_rapport = None

    # — journal —
    def noter(self, ligne):
        with self.verrou:
            self.journal.append('%s  %s' % (datetime.now().strftime('%H:%M:%S'), ligne))
            del self.journal[:-400]

    def occupe(self):
        return bool(self.travail and self.travail.is_alive())

    def vider(self):
        """Efface les resultats : on repart d'une carte vierge.

        Indispensable — un rapport ne doit jamais melanger des mesures prises
        sur deux cartes differentes, ni d'avant et d'apres un flash.
        """
        with self.verrou:
            self.resultats = {}
            self.dernier_rapport = None

    # — connexion —
    def connecter_usb(self, port):
        """Se relie a la carte par le cable, sans reseau.

        C'est la voie normale pour une carte neuve : elle n'a pas
        d'identifiants Wi-Fi et reste injoignable par HTTP.
        """
        if self.occupe():
            return False, 'Une autre operation est en cours.'
        ports = {c['port'] for c in bt.cartes_usb()}
        if port not in ports:
            return False, 'Carte introuvable — reclique sur « Chercher une carte ».'
        ancien = (self.infos or {}).get('device_id')
        if isinstance(self.box, bt.BoxSerie):
            self.box.fermer()
        self.noter('Ouverture du cable %s…' % port)
        box, infos = bt.trouver_box_serie(port)
        if not box:
            self.noter('Pas de reponse sur %s' % port)
            return False, ("Pas de reponse sur ce port. La carte porte-t-elle bien "
                           "le firmware ? Le televersement est peut-etre a refaire.")
        with self.verrou:
            self.box, self.infos = box, infos or {}
        if self.infos.get('device_id') != ancien:
            self.vider()
        self.noter('Carte reliee par le cable %s (firmware %s)'
                   % (port, self.infos.get('version', '?')))
        return True, 'Carte reliee par le cable — aucun reseau necessaire.'

    def connecter(self, hote=None, jeton=None):
        ancien = (self.infos or {}).get('device_id')
        box, infos = bt.trouver_box(hote or None, jeton or None)
        with self.verrou:
            self.box, self.infos = box, infos or {}
        if box and self.infos.get('device_id') != ancien:
            self.vider()
            if ancien:
                self.noter('Nouvelle carte : les resultats precedents sont effaces.')
        if not box:
            self.noter('Carte introuvable sur %s' % (hote or ' / '.join(bt.HOTES)))
            return False, 'Carte introuvable. Allumee ? Sur le meme reseau ?'
        self.noter('Carte trouvee sur %s (firmware %s)'
                   % (box.hote, self.infos.get('version', '?')))
        if not box.token:
            self.noter('Jeton non publie : les controles LED et audio seront refuses.')
        return True, 'Carte trouvee sur %s' % box.hote

    # — etat pour la page —
    def etat(self):
        with self.verrou:
            carte = None
            if self.box:
                carte = {
                    'hote': self.box.hote,
                    'version': self.infos.get('version'),
                    'materiel': self.infos.get('hardware'),
                    'device_id': self.infos.get('device_id'),
                    'jeton': bool(self.box.token),
                    'usb': isinstance(self.box, bt.BoxSerie),
                }
            return {
                'carte': carte,
                'resultats': dict(self.resultats),
                'en_cours': self.en_cours,
                'consigne': self.consigne,
                'question': self.question,
                'occupe': self.occupe(),
                'flash': self.flash_actif,
                'copie': dict(self.copie) if self.copie else None,
                'journal': self.journal[-120:],
                'rapport': self.dernier_rapport,
            }

    # — lancement —
    def lancer(self, clefs):
        if self.occupe():
            return False, 'Un controle est deja en cours.'
        if not self.box:
            return False, "Aucune carte connectee : clique d'abord sur « Chercher la carte »."
        clefs = [c for c in clefs if c in bt.PAR_CLEF]
        if not clefs:
            return False, 'Rien a lancer.'
        self.arret.clear()
        self.travail = threading.Thread(target=self._derouler, args=(clefs,), daemon=True)
        self.travail.start()
        return True, ''

    def _derouler(self, clefs):
        ctx = ContexteGUI(self)
        for clef in clefs:
            if self.arret.is_set():
                self.noter('Serie interrompue.')
                break
            test = bt.PAR_CLEF[clef]
            with self.verrou:
                self.en_cours = clef
                self.consigne = None
                self.resultats.pop(clef, None)
            reussi, detail = bt.executer(test, ctx)
            if self.arret.is_set():
                # Un arret n'est pas un echec : on ne retient rien, le controle
                # reste simplement a refaire.
                self.noter('%s : interrompu, aucun resultat retenu.' % test.nom)
                break
            with self.verrou:
                self.resultats[clef] = {
                    'ok': reussi, 'detail': detail,
                    'horo': datetime.now().strftime('%H:%M:%S'),
                }
                self.en_cours = None
                self.consigne = None
            self.noter('%s %s%s' % ('OK  ' if reussi else 'ECHEC', test.nom,
                                    (' — ' + detail) if detail else ''))
        with self.verrou:
            self.en_cours = self.consigne = self.question = None
        self.arret.clear()

    def repondre(self, oui):
        with self.verrou:
            self.reponse = bool(oui)
        self.repondu.set()

    def stopper(self):
        self.arret.set()
        self.repondu.set()          # debloque une question en attente
        try:
            if self.box:
                self.box.get('/stopplay')
        except Exception:
            pass

    # — flash —
    def flasher(self, port=None, recompiler=False):
        if self.occupe():
            return False, 'Un controle est en cours.'

        def travail():
            with self.verrou:
                self.flash_actif = True
            try:
                succes, message = bt.flasher(port or None, recompiler, sortie=self.noter)
                self.noter(('OK  ' if succes else 'ECHEC ') + message)
                if succes:
                    # Le firmware a change : tout ce qui a ete mesure avant ne
                    # vaut plus rien.
                    self.vider()
            finally:
                with self.verrou:
                    self.flash_actif = False

        self.travail = threading.Thread(target=travail, daemon=True)
        self.travail.start()
        return True, 'Televersement lance — suis le journal.'

    # — carte SD —
    def preparer(self, volume):
        if self.occupe():
            return False, 'Une autre operation est en cours.'
        connues = {c['chemin'] for c in bt.cartes_sd()}
        if volume not in connues:
            # On ne copie JAMAIS vers un chemin fourni tel quel : il doit
            # figurer dans la liste des volumes amovibles detectes.
            return False, 'Carte introuvable ou non amovible — reclique sur « Chercher une carte ».'

        def travail():
            with self.verrou:
                self.copie = {'actif': True, 'volume': volume, 'fait': 0, 'total': 0,
                              'octets': 0, 'total_octets': 0, 'fichier': '',
                              'message': '', 'succes': None}
            message, succes = 'interrompu', False
            try:
                def avancement(i, n, o, tot, rel):
                    with self.verrou:
                        if self.copie:
                            self.copie.update(fait=i, total=n, octets=o,
                                              total_octets=tot, fichier=rel)
                succes, message = bt.preparer_carte(
                    volume, sortie=self.noter, avancement=avancement, arret=self.arret)
                self.noter(('OK  ' if succes else 'ECHEC ') + message)
            except Exception as e:
                message = str(e)
                self.noter('ECHEC preparation : ' + message)
            finally:
                with self.verrou:
                    if self.copie:
                        self.copie.update(actif=False, message=message, succes=succes)
                self.arret.clear()

        self.arret.clear()
        self.travail = threading.Thread(target=travail, daemon=True)
        self.travail.start()
        return True, 'Copie lancee — suis la progression ci-dessous.'

    # — rapport —
    def rapport(self, serie):
        with self.verrou:
            if not self.resultats:
                return None, 'Aucun controle joue : rien a archiver.'
            lignes, non_faits = [], []
            for t in bt.TESTS:
                r = self.resultats.get(t.clef)
                if r:
                    lignes.append({'test': t.nom, 'ok': r['ok'], 'detail': r['detail']})
                else:
                    non_faits.append(t.nom)
            chemin, verdict = bt.ecrire_rapport(serie.strip(), self.infos, lignes,
                                                self.box.hote if self.box else None,
                                                non_faits)
            self.dernier_rapport = {
                'chemin': os.path.relpath(chemin, bt.RACINE),
                'verdict': verdict,
                'non_executes': len(non_faits),
            }
        self.noter('Rapport ecrit : %s (%s)' % (self.dernier_rapport['chemin'], verdict))
        return self.dernier_rapport, ''


class ContexteGUI(bt.Contexte):
    """Le meme Contexte que la console — mais qui parle a la page web."""

    def __init__(self, session):
        super().__init__(session.box, session.infos)
        self.s = session
        self.arret = session.arret

    def dire(self, m):
        self.s.noter(m)

    def consigne(self, m):
        with self.s.verrou:
            self.s.consigne = m
        self.s.noter(m)

    def demander(self, q):
        with self.s.verrou:
            self.s.question = q
            self.s.reponse = None
        self.s.repondu.clear()
        while not self.s.repondu.wait(0.2):
            if self.arret.is_set():
                with self.s.verrou:
                    self.s.question = None
                return False
        with self.s.verrou:
            r = bool(self.s.reponse)
            self.s.question = None
        return r


SESSION = Session()


# ─────────────────────────── serveur ────────────────────────────────

class Poignee(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass                                    # le journal du banc suffit

    def _envoyer(self, corps, type_mime='application/json; charset=utf-8', code=200):
        if isinstance(corps, (dict, list)):
            corps = json.dumps(corps, ensure_ascii=False)
        data = corps.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', type_mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def _corps(self):
        n = int(self.headers.get('Content-Length') or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode('utf-8'))
        except Exception:
            return {}

    def do_GET(self):
        if self.path in ('/', '/index.html'):
            return self._envoyer(PAGE, 'text/html; charset=utf-8')
        if self.path == '/api/catalogue':
            return self._envoyer({
                'groupes': [{'clef': g, 'nom': n, 'sous_titre': s} for g, n, s in bt.GROUPES],
                'tests': [{'clef': t.clef, 'nom': t.nom, 'groupe': t.groupe,
                           'pourquoi': t.pourquoi} for t in bt.TESTS],
            })
        if self.path == '/api/etat':
            return self._envoyer(SESSION.etat())
        if self.path == '/api/usb':
            return self._envoyer({'cartes': bt.cartes_usb()})
        if self.path == '/api/cartes':
            return self._envoyer({'cartes': bt.cartes_sd()})
        if self.path == '/api/ports':
            return self._envoyer({'ports': bt.ports_serie()})
        return self._envoyer({'erreur': 'inconnu'}, code=404)

    def do_POST(self):
        c = self._corps()
        if self.path == '/api/connecter':
            trouve, message = SESSION.connecter(c.get('hote', '').strip(),
                                                c.get('jeton', '').strip())
            return self._envoyer({'ok': trouve, 'message': message})
        if self.path == '/api/lancer':
            lance, message = SESSION.lancer(c.get('clefs') or [])
            return self._envoyer({'ok': lance, 'message': message})
        if self.path == '/api/repondre':
            SESSION.repondre(c.get('oui'))
            return self._envoyer({'ok': True})
        if self.path == '/api/vider':
            SESSION.vider()
            SESSION.noter('Resultats effaces — carte suivante.')
            return self._envoyer({'ok': True})
        if self.path == '/api/arreter':
            SESSION.stopper()
            return self._envoyer({'ok': True})
        if self.path == '/api/flash':
            lance, message = SESSION.flasher(c.get('port', '').strip(),
                                             bool(c.get('recompiler')))
            return self._envoyer({'ok': lance, 'message': message})
        if self.path == '/api/connecter_usb':
            relie, message = SESSION.connecter_usb(c.get('port', ''))
            return self._envoyer({'ok': relie, 'message': message})
        if self.path == '/api/preparer':
            lance, message = SESSION.preparer(c.get('volume', ''))
            return self._envoyer({'ok': lance, 'message': message})
        if self.path == '/api/rapport':
            rap, message = SESSION.rapport(c.get('serie', ''))
            return self._envoyer({'ok': bool(rap), 'rapport': rap, 'message': message})
        return self._envoyer({'erreur': 'inconnu'}, code=404)


# ─────────────────────────── la page ────────────────────────────────

PAGE = r"""<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Banc de production — AdhanBox V3</title>
<style>
:root{
  --fond:#f6f6f4; --carte:#fff; --trait:#e2e0da; --texte:#1c1b19; --doux:#6f6c64;
  --accent:#1f6f4a; --accent-fort:#18583b; --vert:#1f7a4d; --rouge:#b3271e;
  --ambre:#a8620a; --ombre:0 1px 2px rgba(0,0,0,.05), 0 4px 14px rgba(0,0,0,.04);
}
@media (prefers-color-scheme:dark){:root{
  --fond:#141514; --carte:#1c1e1d; --trait:#2e312f; --texte:#eceae4; --doux:#9a978e;
  --accent:#3f9f70; --accent-fort:#55b585; --vert:#4caf7d; --rouge:#e4645a;
  --ambre:#d99a3e; --ombre:0 1px 2px rgba(0,0,0,.4);
}}
*{box-sizing:border-box}
body{margin:0;background:var(--fond);color:var(--texte);
  font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;}
.enveloppe{max-width:1000px;margin:0 auto;padding:28px 20px 80px}
header{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;margin-bottom:6px}
h1{font-size:22px;margin:0;letter-spacing:-.01em}
h1 span{color:var(--doux);font-weight:400}
.pastille{margin-left:auto;font-size:13px;padding:4px 12px;border-radius:999px;
  border:1px solid var(--trait);background:var(--carte);color:var(--doux);white-space:nowrap}
.pastille.vivante{color:var(--vert);border-color:color-mix(in srgb,var(--vert) 40%,transparent)}
.bloc{background:var(--carte);border:1px solid var(--trait);border-radius:12px;
  padding:16px;margin-top:16px;box-shadow:var(--ombre)}
.rangee{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
label{font-size:13px;color:var(--doux)}
input[type=text]{font:inherit;padding:8px 11px;border:1px solid var(--trait);
  border-radius:8px;background:var(--fond);color:var(--texte);min-width:190px}
input[type=text]:focus{outline:2px solid var(--accent);outline-offset:-1px}
button{font:inherit;padding:8px 15px;border-radius:8px;border:1px solid var(--trait);
  background:var(--carte);color:var(--texte);cursor:pointer}
button:hover:not(:disabled){border-color:var(--doux)}
button:disabled{opacity:.4;cursor:default}
button.fort{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
button.fort:hover:not(:disabled){background:var(--accent-fort);border-color:var(--accent-fort)}
button.danger{color:var(--rouge);border-color:color-mix(in srgb,var(--rouge) 40%,transparent)}
.aparte{font-size:13px;color:var(--doux);margin:6px 0 0}
h2{font-size:15px;margin:26px 0 2px;letter-spacing:-.005em}
h2 + .aparte{margin:0 0 10px}
.test{display:flex;align-items:flex-start;gap:12px;padding:11px 14px;
  border:1px solid var(--trait);border-radius:10px;background:var(--carte);margin-bottom:8px}
.test .jouer{flex:none;width:34px;height:34px;padding:0;border-radius:50%;
  display:grid;place-items:center;font-size:12px;line-height:1}
.test .corps{flex:1;min-width:0}
.test .nom{font-weight:600;font-size:14px}
.test .pourquoi{font-size:12.5px;color:var(--doux);margin-top:1px}
.test .detail{font-size:13px;margin-top:5px;font-variant-numeric:tabular-nums;
  word-break:break-word}
.test .marque{flex:none;font-size:13px;font-weight:600;padding-top:8px;min-width:74px;
  text-align:right;color:var(--doux)}
.test.ok{border-color:color-mix(in srgb,var(--vert) 35%,var(--trait))}
.test.ok .marque,.test.ok .detail{color:var(--vert)}
.test.ko{border-color:color-mix(in srgb,var(--rouge) 45%,var(--trait))}
.test.ko .marque,.test.ko .detail{color:var(--rouge)}
.test.actif{border-color:var(--accent);box-shadow:0 0 0 3px color-mix(in srgb,var(--accent) 14%,transparent)}
.test.actif .marque{color:var(--accent)}
.appel{position:sticky;top:12px;z-index:5;margin-top:16px;padding:16px 18px;border-radius:12px;
  background:var(--carte);border:2px solid var(--accent);box-shadow:var(--ombre)}
.appel.consigne{border-color:var(--ambre)}
.alerte{border-color:var(--ambre);border-left-width:4px}
.sd{display:flex;align-items:center;gap:12px;padding:10px 14px;border:1px solid var(--trait);
  border-radius:10px;margin-top:8px}
.sd .ident{flex:1;min-width:0}
.sd .ident b{font-size:14px} .sd .ident span{color:var(--doux);font-size:12.5px}
.jauge{height:8px;border-radius:999px;background:var(--fond);overflow:hidden;margin-top:10px}
.jauge i{display:block;height:100%;background:var(--accent);width:0;transition:width .3s}
.alerte b{color:var(--ambre)}
.appel p{margin:0 0 12px;font-size:17px;font-weight:600}
.appel .rangee button{padding:9px 22px}
.verdict{font-size:17px;font-weight:700;margin:0}
.verdict.ok{color:var(--vert)} .verdict.ko{color:var(--rouge)} .verdict.partiel{color:var(--ambre)}
details{margin-top:20px}
summary{cursor:pointer;font-size:13px;color:var(--doux)}
pre{background:var(--carte);border:1px solid var(--trait);border-radius:10px;padding:12px;
  font-size:12px;line-height:1.6;max-height:300px;overflow:auto;margin-top:8px;
  white-space:pre-wrap;word-break:break-word}
.cache{display:none}
</style></head><body>
<div class="enveloppe">

<header>
  <h1>Banc de production <span>· AdhanBox V3</span></h1>
  <div class="pastille" id="pastille">Aucune carte</div>
</header>
<p class="aparte">Chaque contrôle a son bouton. Lance ce que tu veux, quand tu veux.</p>

<div class="bloc">
  <div class="rangee">
    <label for="hote">Adresse</label>
    <input type="text" id="hote" placeholder="auto : adhanbox.local, 192.168.4.1">
    <label for="jeton">Jeton</label>
    <input type="text" id="jeton" placeholder="seulement si la carte le refuse">
    <button id="b-chercher" class="fort">Chercher la carte</button>
    <button id="b-vider" title="Efface les résultats pour passer au boîtier suivant">Carte suivante</button>
    <button id="b-flash">Flasher le firmware</button>
    <span style="flex:1"></span>
    <button id="b-tout" class="fort">Tout tester</button>
    <button id="b-auto">Contrôles automatiques</button>
    <button id="b-stop" class="danger cache">Arrêter</button>
  </div>
  <p class="aparte" id="message"></p>
</div>

<div id="alerte" class="bloc alerte cache"></div>

<div class="bloc">
  <div class="rangee">
    <b style="font-size:15px">Carte branchée en USB</b>
    <span class="aparte" style="margin:0">Pour téléverser le firmware.</span>
    <span style="flex:1"></span>
    <button id="b-usb">Chercher une carte</button>
  </div>
  <div id="usb"></div>
</div>

<div class="bloc">
  <div class="rangee">
    <b style="font-size:15px">Carte SD</b>
    <span class="aparte" style="margin:0">Copie le contenu de référence, sans doublon invisible.</span>
    <span style="flex:1"></span>
    <button id="b-cartes">Chercher une carte</button>
  </div>
  <div id="cartes"></div>
  <div id="copie" class="cache"></div>
</div>

<div id="appel" class="appel cache"></div>

<main id="groupes"></main>

<div class="bloc">
  <div class="rangee">
    <p class="verdict" id="verdict">Aucun contrôle joué</p>
    <span style="flex:1"></span>
    <label for="serie">N° de série</label>
    <input type="text" id="serie" placeholder="AB3-0001">
    <button id="b-rapport" class="fort">Enregistrer le rapport</button>
  </div>
  <p class="aparte" id="rapport-msg"></p>
</div>

<details>
  <summary>Journal</summary>
  <pre id="journal"></pre>
</details>

</div>
<script>
const $ = s => document.querySelector(s);
let CAT = null, ETAT = null;

const poste = (url, corps) => fetch(url, {method:'POST',
  headers:{'Content-Type':'application/json'}, body:JSON.stringify(corps||{})})
  .then(r => r.json());

function dessinerCatalogue(){
  const hote = $('#groupes');
  hote.innerHTML = '';
  for (const g of CAT.groupes){
    const h = document.createElement('h2'); h.textContent = g.nom;
    const p = document.createElement('p'); p.className='aparte'; p.textContent=g.sous_titre;
    hote.append(h, p);
    for (const t of CAT.tests.filter(t => t.groupe === g.clef)){
      const a = document.createElement('article');
      a.className = 'test'; a.id = 'test-' + t.clef;
      a.innerHTML = '<button class="jouer" title="Lancer ce contrôle">▶</button>'
        + '<div class="corps"><div class="nom"></div>'
        + '<div class="pourquoi"></div><div class="detail"></div></div>'
        + '<div class="marque">—</div>';
      a.querySelector('.nom').textContent = t.nom;
      a.querySelector('.pourquoi').textContent = t.pourquoi;
      a.querySelector('.jouer').onclick = () => lancer([t.clef]);
      hote.append(a);
    }
    const barre = document.createElement('div');
    barre.className = 'rangee'; barre.style.margin = '4px 0 6px';
    const b = document.createElement('button');
    b.textContent = 'Lancer les ' + CAT.tests.filter(t=>t.groupe===g.clef).length
                  + ' contrôles de cette section';
    b.onclick = () => lancer(CAT.tests.filter(t=>t.groupe===g.clef).map(t=>t.clef));
    barre.append(b); hote.append(barre);
  }
}

function lancer(clefs){
  poste('/api/lancer', {clefs}).then(r => { if(!r.ok) $('#message').textContent = r.message; });
  rafraichir();
}

function peindre(e){
  ETAT = e;
  const p = $('#pastille');
  if (e.carte){
    p.className = 'pastille vivante';
    p.textContent = (e.carte.usb ? '⎯ câble · ' : '')
      + e.carte.hote + ' · ' + (e.carte.version||'?') + ' · ' + (e.carte.device_id||'');
  } else { p.className = 'pastille'; p.textContent = 'Aucune carte'; }

  for (const t of CAT.tests){
    const a = document.getElementById('test-' + t.clef);
    const r = e.resultats[t.clef];
    const actif = e.en_cours === t.clef;
    a.className = 'test' + (actif ? ' actif' : r ? (r.ok ? ' ok' : ' ko') : '');
    a.querySelector('.marque').textContent = actif ? '…' : r ? (r.ok ? '✓ OK' : '✗ Échec') : '—';
    a.querySelector('.detail').textContent = actif ? '' : (r ? r.detail : '');
    a.querySelector('.jouer').disabled = e.occupe || e.flash || !e.carte;
  }

  const al = $('#alerte');
  if (e.carte && !e.carte.jeton && !e.carte.usb){
    al.className = 'bloc alerte';
    al.innerHTML = '<p style="margin:0 0 6px"><b>La carte ne publie plus son jeton.</b></p>'
      + '<p class="aparte" style="margin:0">Le firmware ne le donne que pendant les 10 minutes '
      + 'qui suivent le démarrage. Sans lui, les contrôles LED et audio seront refusés '
      + '(erreur 401), ainsi que le contrôle du contenu audio qui ouvre les fichiers. '
      + 'Les six autres contrôles automatiques passent.<br>'
      + '<b>Débranche puis rebranche la carte</b>, et reclique sur « Chercher la carte ». '
      + 'Ou colle le jeton dans le champ ci-dessus, si tu l\'as.</p>';
  } else al.className = 'bloc alerte cache';

  const cp = e.copie, zc = $('#copie');
  if (cp){
    const pct = cp.total ? Math.round(100 * cp.fait / cp.total) : 0;
    zc.className = '';
    zc.innerHTML = '<p class="aparte" style="margin:14px 0 0"></p>'
      + '<div class="jauge"><i style="width:' + pct + '%"></i></div>';
    zc.querySelector('p').textContent = cp.actif
      ? (cp.fait + '/' + cp.total + ' fichiers · ' + go(cp.octets) + ' sur ' + go(cp.total_octets)
         + ' · ' + cp.fichier)
      : (cp.succes ? '✓ ' : '✗ ') + cp.message;
    if (!cp.actif) zc.querySelector('.jauge').style.display = 'none';
  } else zc.className = 'cache';

  const appel = $('#appel');
  if (e.question){
    appel.className = 'appel';
    appel.innerHTML = '<p></p><div class="rangee">'
      + '<button class="fort" id="b-oui">Oui</button>'
      + '<button class="danger" id="b-non">Non</button></div>';
    appel.querySelector('p').textContent = e.question;
    $('#b-oui').onclick = () => poste('/api/repondre',{oui:true}).then(rafraichir);
    $('#b-non').onclick = () => poste('/api/repondre',{oui:false}).then(rafraichir);
  } else if (e.consigne){
    appel.className = 'appel consigne';
    appel.innerHTML = '<p></p><p class="aparte">L\'outil surveille la carte et notera le changement tout seul.</p>';
    appel.querySelector('p').textContent = e.consigne;
  } else { appel.className = 'appel cache'; }

  const pris = e.occupe || e.flash;
  $('#b-cartes').disabled = e.occupe || e.flash;
  $('#b-usb').disabled = e.occupe || e.flash;
  for (const el of document.querySelectorAll('#cartes button, #usb button'))
    el.disabled = e.occupe || e.flash;
  for (const id of ['#b-tout','#b-auto','#b-flash','#b-chercher'])
    $(id).disabled = pris || (id !== '#b-chercher' && id !== '#b-flash' && !e.carte);
  $('#b-stop').className = e.occupe && !e.flash ? 'danger' : 'danger cache';

  const joues = CAT.tests.filter(t => e.resultats[t.clef]);
  const rates = joues.filter(t => !e.resultats[t.clef].ok);
  const v = $('#verdict');
  if (!joues.length){ v.className='verdict'; v.textContent='Aucun contrôle joué'; }
  else if (rates.length){ v.className='verdict ko';
    v.textContent = 'NON CONFORME — ' + rates.length + ' contrôle(s) en échec, ne pas expédier'; }
  else if (joues.length < CAT.tests.length){ v.className='verdict partiel';
    v.textContent = 'Partiel — ' + joues.length + '/' + CAT.tests.length + ' contrôles réussis'; }
  else { v.className='verdict ok'; v.textContent = 'CONFORME — les '+CAT.tests.length+' contrôles sont passés'; }

  const j = $('#journal');
  const enBas = j.scrollTop + j.clientHeight >= j.scrollHeight - 20;
  j.textContent = e.journal.join('\n');
  if (enBas) j.scrollTop = j.scrollHeight;

  if (e.rapport) $('#rapport-msg').textContent =
    'Dernier rapport : ' + e.rapport.chemin + ' — ' + e.rapport.verdict
    + (e.rapport.non_executes ? ' (' + e.rapport.non_executes + ' contrôles non exécutés)' : '');
}

const go = o => o >= 1e9 ? (o/1e9).toFixed(1) + ' Go'
                         : Math.round(o/1e6) + ' Mo';

function chercherUsb(){
  $('#usb').innerHTML = '<p class="aparte">Recherche…</p>';
  fetch('/api/usb').then(r=>r.json()).then(d => {
    const h = $('#usb'); h.innerHTML = '';
    if (!d.cartes.length){
      h.innerHTML = '<p class="aparte">Aucune carte détectée. Branche-la en USB, '
        + 'puis reclique. Si rien n\'apparaît, essaie un autre câble : '
        + 'beaucoup ne portent que l\'alimentation.</p>';
      return;
    }
    for (const c of d.cartes){
      const el = document.createElement('div');
      el.className = 'sd';
      el.innerHTML = '<div class="ident"><b></b><br><span></span></div>'
        + '<button></button>';
      el.querySelector('b').textContent = c.espressif
        ? 'AdhanBox (ESP32-S3)' : (c.produit || 'Appareil inconnu');
      el.querySelector('span').textContent =
        c.port + ' · ' + c.fabricant + (c.produit ? ' · ' + c.produit : '');
      el.querySelector('.ident').insertAdjacentHTML('afterend',
        '<button class="relier">Tester par le câble</button>');
      el.querySelector('.relier').onclick = () => {
        $('#message').textContent = 'Ouverture du câble…';
        poste('/api/connecter_usb', {port: c.port})
          .then(r => { $('#message').textContent = r.message; rafraichir(); });
      };
      const b = el.querySelector('button:last-of-type');
      b.textContent = 'Flasher cette carte';
      b.className = c.espressif ? 'fort' : '';
      b.onclick = () => {
        if (!c.espressif && !confirm('« ' + (c.produit || c.port) + ' » n\'est pas '
          + 'un appareil Espressif.\n\nTéléverser dessus n\'aura aucun effet utile, '
          + 'et pourrait perturber cet appareil. Continuer quand même ?')) return;
        $('#message').textContent = 'Compilation et téléversement — ouvre le journal pour suivre.';
        poste('/api/flash', {port: c.port})
          .then(r => { $('#message').textContent = r.message; rafraichir(); });
      };
      h.append(el);
    }
  });
}
$('#b-usb').onclick = chercherUsb;

function chercherCartes(){
  $('#cartes').innerHTML = '<p class="aparte">Recherche…</p>';
  fetch('/api/cartes').then(r=>r.json()).then(d => {
    const h = $('#cartes'); h.innerHTML = '';
    if (!d.cartes.length){
      h.innerHTML = '<p class="aparte">Aucune carte détectée. Branche-la, puis reclique. '
        + 'Les volumes internes sont volontairement ignorés.</p>';
      return;
    }
    for (const c of d.cartes){
      const el = document.createElement('div');
      el.className = 'sd';
      el.innerHTML = '<div class="ident"><b></b><br><span></span></div>'
        + '<button class="fort">Préparer cette carte</button>';
      el.querySelector('b').textContent = c.nom;
      el.querySelector('span').textContent =
        c.systeme + ' · ' + go(c.libre) + ' libres sur ' + go(c.total) + ' · ' + c.chemin;
      el.querySelector('button').onclick = () => {
        if (!confirm('Copier le contenu de référence sur « ' + c.nom + ' » ?\n\n'
          + 'Les fichiers déjà identiques seront ignorés. Rien n\'est effacé, '
          + 'sauf les résidus macOS.')) return;
        poste('/api/preparer', {volume: c.chemin})
          .then(r => { $('#message').textContent = r.message; rafraichir(); });
      };
      h.append(el);
    }
  });
}
$('#b-cartes').onclick = chercherCartes;

const rafraichir = () => fetch('/api/etat').then(r=>r.json()).then(peindre).catch(()=>{});

$('#b-chercher').onclick = () => {
  $('#message').textContent = 'Recherche…';
  poste('/api/connecter', {hote: $('#hote').value, jeton: $('#jeton').value})
    .then(r => { $('#message').textContent = r.message; rafraichir(); });
};
$('#b-flash').onclick = () => {
  $('#message').textContent = 'Compilation et téléversement — ouvre le journal pour suivre.';
  poste('/api/flash', {}).then(r => { $('#message').textContent = r.message; rafraichir(); });
};
$('#b-tout').onclick = () => lancer(CAT.tests.map(t => t.clef));
$('#b-auto').onclick = () => lancer(CAT.tests.filter(t=>t.groupe==='auto').map(t=>t.clef));
$('#b-stop').onclick = () => poste('/api/arreter').then(rafraichir);
$('#b-rapport').onclick = () => poste('/api/rapport', {serie: $('#serie').value})
  .then(r => { if(!r.ok) $('#rapport-msg').textContent = r.message; rafraichir(); });
$('#b-vider').onclick = () => {
  if (!confirm('Effacer les résultats et repartir sur une carte vierge ?')) return;
  poste('/api/vider').then(() => { $('#serie').value=''; $('#rapport-msg').textContent=''; rafraichir(); });
};

fetch('/api/catalogue').then(r=>r.json()).then(c => {
  CAT = c; dessinerCatalogue(); rafraichir(); setInterval(rafraichir, 500);
});
</script></body></html>
"""


def occupant(port):
    """Qui tient deja ce port ? Retourne (pid, est-ce un banc de production)."""
    pid = None
    try:
        r = subprocess.run(['lsof', '-nP', '-tiTCP:%d' % port, '-sTCP:LISTEN'],
                           capture_output=True, text=True, timeout=4)
        pid = (r.stdout.strip().split('\n') or [''])[0] or None
    except Exception:
        pass
    banc = False
    try:
        import urllib.request
        with urllib.request.urlopen('http://127.0.0.1:%d/api/catalogue' % port,
                                    timeout=2) as f:
            banc = b'groupes' in f.read(400)
    except Exception:
        pass
    return pid, banc


def main():
    port = PORT_WEB
    if '--port' in sys.argv:
        port = int(sys.argv[sys.argv.index('--port') + 1])
    moi = os.path.relpath(os.path.abspath(__file__))
    try:
        serveur = ThreadingHTTPServer(('127.0.0.1', port), Poignee)
    except OSError as e:
        # « Address already in use » sans plus d'explication laisse l'operateur
        # devant une trace Python. On dit qui occupe le port et quoi taper.
        if e.errno != errno.EADDRINUSE:
            raise
        pid, banc = occupant(port)
        print('Le port %d est deja pris.\n' % port)
        if banc:
            print("  Un banc de production y tourne deja — probablement une")
            print("  version anterieure, qui n'a donc pas les derniers correctifs.")
        elif pid:
            print('  Un autre programme y tourne (PID %s).' % pid)
        if pid:
            print('\n  Ferme-le :   kill %s' % pid)
            print('  puis :       python3 %s' % moi)
        print('\n  Ou lance celui-ci a cote :')
        print('               python3 %s --port %d' % (moi, port + 1))
        sys.exit(1)
    url = 'http://127.0.0.1:%d/' % port
    print('Banc de production AdhanBox V3')
    print('  %s' % url)
    print('  Ctrl+C pour fermer.')
    if '--sans-navigateur' not in sys.argv:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        print('\nFerme.')
        SESSION.stopper()


if __name__ == '__main__':
    main()
