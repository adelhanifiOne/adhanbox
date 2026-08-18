/* ════════════════════════════════════════════════════════════
   AdhanBox — Pixel Meta (publicité) + bandeau de consentement.
   Conformité CNIL : le pixel n'est chargé qu'après « Accepter ».
   Le choix est mémorisé (localStorage) et ne réapparaît plus.
   Inclus sur TOUTES les pages (y compris index.html qui ne
   charge pas site.js).
   ════════════════════════════════════════════════════════════ */
(function () {
  // Doit rester identique au pixel utilisé côté serveur (commande_backend/
  // api/stripe-webhook.js) : sinon Meta ne déduplique plus les Purchase.
  var PIXEL_ID = '1510675917787927';
  var CONSENT_KEY = 'ab_consent_ads';
  var BACKEND = 'https://adhanbox-commande.vercel.app';
  var page = document.body.getAttribute('data-page') || '';

  function loadMetaPixel() {
    if (window.fbq) return;
    !function (f, b, e, v, n, t, s) {
      if (f.fbq) return; n = f.fbq = function () {
        n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
      };
      if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = '2.0';
      n.queue = []; t = b.createElement(e); t.async = !0; t.src = v;
      s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s);
    }(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');
    fbq('init', PIXEL_ID);
    fbq('track', 'PageView');
    // Événements standard selon la page (pour l'optimisation des pubs)
    if (page === 'personnaliser') {
      fbq('track', 'ViewContent', { content_name: 'Configurateur AdhanBox', value: 95, currency: 'EUR' });
    }
    // Purchase déclenché uniquement après un vrai paiement (session_id présent).
    // eventID = id de session Stripe : le backend envoie le même Purchase via
    // l'API Conversions avec cet id -> Meta déduplique, pas de double comptage.
    // On demande au backend le montant réellement payé (codes promo déduits)
    // pour que le ROAS soit juste ; si l'appel échoue, on retombe sur le prix
    // catalogue plutôt que de perdre la conversion.
    var sid = window.location.search.match(/[?&]session_id=([^&]+)/);
    if (page === 'merci' && sid) {
      var sessionId = decodeURIComponent(sid[1]);
      var sendPurchase = function (value) {
        fbq('track', 'Purchase',
          { content_name: 'AdhanBox — Précommande', value: value, currency: 'EUR' },
          { eventID: sessionId });
      };
      fetch(BACKEND + '/api/order-amount?id=' + encodeURIComponent(sessionId))
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d) {
          sendPurchase(d && typeof d.amount === 'number' ? d.amount : 95);
        })
        .catch(function () { sendPurchase(95); });
    }
  }

  /* Bandeau de consentement.
     Règle CNIL : refuser doit être aussi simple qu'accepter — les deux boutons
     ont donc la même taille, la même typo et le même niveau de lisibilité.
     Seule la couleur distingue l'action principale, ce qui reste autorisé. */
  function showConsentBanner() {
    var style = document.createElement('style');
    style.textContent =
      '#ab-cookies{position:fixed;left:18px;right:18px;bottom:18px;z-index:9999;max-width:520px;margin:0 auto;' +
      'background:#FFFDF8;border:1px solid rgba(12,91,69,.16);border-radius:18px;padding:20px 22px;' +
      'box-shadow:0 18px 50px rgba(21,37,31,.20);font-size:.9rem;line-height:1.55;color:#15251F;' +
      'font-family:"Inter",system-ui,sans-serif;animation:ab-cb-up .45s cubic-bezier(.2,.7,.3,1) both;}' +
      '@keyframes ab-cb-up{from{opacity:0;transform:translateY(14px);}to{opacity:1;transform:none;}}' +
      '@media (prefers-reduced-motion:reduce){#ab-cookies{animation:none;}}' +
      '#ab-cookies .cb-head{display:flex;align-items:center;gap:.6rem;font-family:"Fraunces",Georgia,serif;' +
      'font-weight:600;font-size:1.02rem;color:#0C5B45;margin-bottom:.5rem;}' +
      '#ab-cookies .cb-head img{width:26px;height:26px;border-radius:7px;flex-shrink:0;}' +
      '#ab-cookies p{margin:0 0 .9rem;color:#3E4C45;}' +
      '#ab-cookies a{color:#0C5B45;text-decoration:underline;text-underline-offset:2px;}' +
      '#ab-cookies .cb-row{display:flex;gap:10px;}' +
      '#ab-cookies button{flex:1;cursor:pointer;border-radius:999px;padding:.72rem 1rem;' +
      'font-family:inherit;font-size:.9rem;font-weight:600;line-height:1.2;' +
      'border:1.5px solid #0C5B45;transition:background .15s,transform .15s;}' +
      '#ab-cookies button:hover{transform:translateY(-1px);}' +
      '#ab-cookies .cb-no{background:transparent;color:#0C5B45;}' +
      '#ab-cookies .cb-no:hover{background:#E5F0EB;}' +
      '#ab-cookies .cb-yes{background:#0C5B45;border-color:#0C5B45;color:#fff;}' +
      '#ab-cookies .cb-yes:hover{background:#08402F;}' +
      '@media (max-width:420px){#ab-cookies .cb-row{flex-direction:column-reverse;}}';
    document.head.appendChild(style);
    var b = document.createElement('div');
    b.id = 'ab-cookies';
    b.setAttribute('role', 'dialog');
    b.setAttribute('aria-label', 'Votre choix sur la mesure d\'audience');
    b.innerHTML =
      '<div class="cb-head"><img src="logo-app.png" alt="">Un coup de main ?</div>' +
      '<p>AdhanBox est un projet artisanal, lancé sans budget marketing. ' +
      'Accepter la mesure d\'audience nous permet simplement de savoir quelles annonces ' +
      'font découvrir le boîtier — et de ne pas dépenser dans le vide. ' +
      'Aucune donnée n\'est vendue. <a href="privacy.html">En savoir plus</a></p>' +
      '<div class="cb-row"><button class="cb-no" id="ab-cb-no">Continuer sans</button>' +
      '<button class="cb-yes" id="ab-cb-yes">J\'accepte, avec plaisir</button></div>';
    document.body.appendChild(b);
    document.getElementById('ab-cb-yes').addEventListener('click', function () {
      try { localStorage.setItem(CONSENT_KEY, 'yes'); } catch (e) {}
      b.remove();
      loadMetaPixel();
    });
    document.getElementById('ab-cb-no').addEventListener('click', function () {
      try { localStorage.setItem(CONSENT_KEY, 'no'); } catch (e) {}
      b.remove();
    });
  }

  var adsConsent = null;
  try { adsConsent = localStorage.getItem(CONSENT_KEY); } catch (e) {}
  if (adsConsent === 'yes') loadMetaPixel();
  else if (adsConsent === null) showConsentBanner();
})();
