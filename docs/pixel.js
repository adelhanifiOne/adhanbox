/* ════════════════════════════════════════════════════════════
   AdhanBox — Pixel Meta (publicité) + bandeau de consentement.
   Conformité CNIL : le pixel n'est chargé qu'après « Accepter ».
   Le choix est mémorisé (localStorage) et ne réapparaît plus.
   Inclus sur TOUTES les pages (y compris index.html qui ne
   charge pas site.js).
   ════════════════════════════════════════════════════════════ */
(function () {
  var PIXEL_ID = '1510675917787927';
  var CONSENT_KEY = 'ab_consent_ads';
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
    var sid = window.location.search.match(/[?&]session_id=([^&]+)/);
    if (page === 'merci' && sid) {
      fbq('track', 'Purchase',
        { content_name: 'AdhanBox — Précommande', value: 95, currency: 'EUR' },
        { eventID: decodeURIComponent(sid[1]) });
    }
  }

  function showConsentBanner() {
    var style = document.createElement('style');
    style.textContent =
      '#ab-cookies{position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;max-width:440px;margin:0 auto;' +
      'background:#FFFDF8;border:1px solid rgba(12,91,69,.18);border-radius:14px;padding:16px 18px;' +
      'box-shadow:0 12px 40px rgba(0,0,0,.16);font-size:.86rem;line-height:1.5;color:#333;font-family:"Inter",system-ui,sans-serif;}' +
      '#ab-cookies p{margin:0 0 10px;}' +
      '#ab-cookies a{color:#0C5B45;text-decoration:underline;}' +
      '#ab-cookies .cb-row{display:flex;gap:10px;justify-content:flex-end;}' +
      '#ab-cookies button{cursor:pointer;border-radius:999px;padding:8px 18px;font-size:.86rem;font-weight:600;border:1px solid rgba(12,91,69,.35);}' +
      '#ab-cookies .cb-no{background:transparent;color:#0C5B45;}' +
      '#ab-cookies .cb-yes{background:#C9A227;border-color:#C9A227;color:#fff;}';
    document.head.appendChild(style);
    var b = document.createElement('div');
    b.id = 'ab-cookies';
    b.setAttribute('role', 'dialog');
    b.setAttribute('aria-label', 'Consentement cookies');
    b.innerHTML =
      '<p>🍪 Avec votre accord, nous utilisons un traceur publicitaire (Meta) pour mesurer nos campagnes. ' +
      '<a href="privacy.html">En savoir plus</a></p>' +
      '<div class="cb-row"><button class="cb-no" id="ab-cb-no">Refuser</button>' +
      '<button class="cb-yes" id="ab-cb-yes">Accepter</button></div>';
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
