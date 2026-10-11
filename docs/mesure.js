/* ════════════════════════════════════════════════════════════
   AdhanBox — mesure d'audience, sans cookie ni donnee personnelle.

   Cloudflare Web Analytics : un script, aucun cookie, aucun identifiant,
   donc pas de bandeau de consentement. Il compte les pages vues, d'ou
   viennent les visiteurs (instagram.com, google…) et la vitesse reelle
   d'affichage sur leurs telephones.

   Le jeton se cree sur dash.cloudflare.com → Web Analytics → Add a site
   (adhanbox.fr). Tant qu'il est vide, ce fichier ne fait rien : aucune
   requete ne part.

   Charge par index.html (balise script) et par site.js (toutes les
   autres pages). Le pixel Meta, lui, reste interdit sur ce site
   (categorie « Religion ») : voir commande_backend/README.md.
   ════════════════════════════════════════════════════════════ */
(function () {
  var JETON = '7c75268acad44f42a0f69ab98a2640b4';   // site « adhanbox.fr » cree le 07/10/2026 sur le compte Cloudflare d'Adel
  if (!JETON) return;
  // Seulement le vrai site : les essais en local (localhost) faussaient les chiffres.
  if (!/(^|\.)adhanbox\.fr$/.test(location.hostname)) return;
  var s = document.createElement('script');
  s.defer = true;
  s.src = 'https://static.cloudflareinsights.com/beacon.min.js';
  s.setAttribute('data-cf-beacon', JSON.stringify({ token: JETON }));
  document.head.appendChild(s);
})();

/* ── Parcours : jusqu'ou on descend, ce qu'on clique (11/10/2026) ──────────
   Cloudflare ne compte que les pages vues. Ces petits signaux vont au
   compteur cloudflare_mesure/worker.js, qui n'incremente que des TOTAUX PAR
   JOUR (page, signal, provenance) : ni identifiant, ni cookie, ni stockage
   dans le navigateur, rien qui suive une personne.
     vue                      la page s'affiche
     defile-25 … defile-100   part de la page atteinte
     section:<nom>            une section de la page arrive a l'ecran
     reste-10s / 30s / 60s    page encore ouverte et visible
     clic:<section>:<cible>   lien touche (cible = page, ancre ou « externe »)
   ─────────────────────────────────────────────────────────────────────── */
(function () {
  var URL_MESURE = 'https://adhanbox-mesure.adhanbox.workers.dev/';
  if (!/(^|\.)adhanbox\.fr$/.test(location.hostname) || navigator.webdriver) return;

  var page = location.pathname.replace(/\/index\.html$/, '/').toLowerCase().slice(0, 41);
  var source = (function () {
    var utm = (new URLSearchParams(location.search).get('utm_source') || '').toLowerCase();
    var ref = '';
    try { ref = document.referrer ? new URL(document.referrer).hostname : ''; } catch (e) {}
    var s = utm || ref;
    if (/adhanbox\.fr$/.test(ref) && !utm) return 'interne';
    if (/instagram|^ig$/.test(s)) return 'instagram';
    if (/facebook|^fb$/.test(s)) return 'facebook';
    if (/google/.test(s)) return 'google';
    if (/tiktok/.test(s)) return 'tiktok';
    return s ? 'autre' : 'direct';
  })();
  var envoyes = {};
  function signal(quoi) {
    quoi = String(quoi).toLowerCase().replace(/[^a-z0-9\-:.\/]/g, '-').slice(0, 60);
    if (envoyes[quoi]) return;
    envoyes[quoi] = 1;
    var corps = JSON.stringify({ page: page, quoi: quoi, source: source });
    try {
      if (navigator.sendBeacon && navigator.sendBeacon(URL_MESURE, corps)) return;
    } catch (e) {}
    try { fetch(URL_MESURE, { method: 'POST', body: corps, mode: 'no-cors', keepalive: true }); } catch (e) {}
  }

  function nomSection(el) {
    var s = el && el.closest ? el.closest('section, header, footer') : null;
    if (!s) return 'page';
    if (s.id) return s.id;
    var c = (s.className || '').split(/\s+/).filter(function (x) { return x && x !== 'block' && x !== 'alt'; })[0];
    return c || s.tagName.toLowerCase();
  }

  function demarrer() {
    signal('vue');

    // Part de la page atteinte (bas de l'ecran / hauteur totale).
    var paliers = [25, 50, 75, 100];
    function defile() {
      var h = document.documentElement.scrollHeight;
      var bas = (window.scrollY || window.pageYOffset) + window.innerHeight;
      paliers.forEach(function (p) { if (h && bas >= h * p / 100 - 2) signal('defile-' + p); });
    }
    window.addEventListener('scroll', defile, { passive: true });

    // Sections vues : au moins 30 % de la section a l'ecran.
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entrees) {
        entrees.forEach(function (e) {
          if (e.isIntersecting) { signal('section:' + nomSection(e.target)); io.unobserve(e.target); }
        });
      }, { threshold: 0.3 });
      document.querySelectorAll('main section, body > section').forEach(function (s) {
        if (!s.hidden) io.observe(s);
      });
    }

    // Temps passe, seulement page visible.
    var visible = 0;
    setInterval(function () {
      if (document.visibilityState !== 'visible') return;
      visible += 5;
      if (visible === 10 || visible === 30 || visible === 60) signal('reste-' + visible + 's');
    }, 5000);

    // Liens touches.
    document.addEventListener('click', function (ev) {
      var a = ev.target && ev.target.closest ? ev.target.closest('a[href]') : null;
      if (!a) return;
      var cible;
      try {
        var u = new URL(a.getAttribute('href'), location.href);
        if (u.hostname !== location.hostname) cible = 'externe';
        else if (u.pathname === location.pathname && u.hash) cible = 'ancre-' + u.hash.slice(1);
        else cible = u.pathname.replace(/^\//, '').replace(/\.html$/, '') || 'accueil';
      } catch (e) { cible = 'autre'; }
      envoyes['clic:' + nomSection(a) + ':' + cible] = 0;   // chaque clic compte
      signal('clic:' + nomSection(a) + ':' + cible);
    }, true);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', demarrer);
  else demarrer();
})();
