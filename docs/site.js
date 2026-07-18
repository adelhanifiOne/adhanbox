/* ════════════════════════════════════════════════════════════
   AdhanBox — éléments partagés (header, menu burger, footer)
   injectés sur toutes les pages + comportements communs.
   ════════════════════════════════════════════════════════════ */
(function () {
  var page = document.body.getAttribute('data-page') || '';

  var LOGO_SVG =
    '<img class="logo-mark" src="logo-app.png" alt="" aria-hidden="true" width="38" height="38">';

  var HEADER =
    '<header id="header">' +
      '<div class="container nav-bar">' +
        '<a href="index.html" class="logo" aria-label="AdhanBox — Accueil">' + LOGO_SVG + 'Adhan<span>Box</span></a>' +
      '</div>' +
    '</header>' +
    '<button class="burger" id="burger" aria-label="Ouvrir le menu" aria-expanded="false" aria-controls="menu-overlay">' +
      '<span></span><span></span><span></span>' +
    '</button>' +
    '<div class="menu-overlay" id="menu-overlay" aria-hidden="true">' +
      '<nav class="menu-nav" aria-label="Navigation principale">' +
        '<a href="index.html" data-nav="accueil">Accueil</a>' +
        '<a href="personnaliser.html" data-nav="personnaliser">Personnaliser</a>' +
        '<a href="produit.html" data-nav="produit">Le produit</a>' +
        '<a href="avis.html" data-nav="avis">Avis</a>' +
        '<a href="faq.html" data-nav="faq">FAQ</a>' +
        '<a href="contact.html" data-nav="contact">Contact</a>' +
      '</nav>' +
    '</div>';

  var FOOTER =
    '<footer>' +
      '<div class="container">' +
        '<div class="footer-grid">' +
          '<div class="footer-brand">' +
            '<a href="index.html" class="logo" aria-label="AdhanBox — Accueil">' + LOGO_SVG + 'Adhan<span>Box</span></a>' +
            '<p>Boîtier d\'appel à la prière artisanal et connecté, conçu et fabriqué avec minutie pour soutenir la communauté musulmane.</p>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Naviguer</h4>' +
            '<ul>' +
              '<li><a href="personnaliser.html">Personnaliser</a></li>' +
              '<li><a href="produit.html">Le produit</a></li>' +
              '<li><a href="avis.html">Avis</a></li>' +
              '<li><a href="faq.html">FAQ</a></li>' +
              '<li><a href="contact.html">Contact</a></li>' +
            '</ul>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Ressources</h4>' +
            '<ul>' +
              '<li><a href="privacy.html">Politique de confidentialité</a></li>' +
              '<li><a href="cgv.html">Conditions générales de vente</a></li>' +
              '<li><a href="mentions-legales.html">Mentions légales</a></li>' +
              '<li><a href="mailto:contact@adhanbox.fr">contact@adhanbox.fr</a></li>' +
            '</ul>' +
          '</div>' +
        '</div>' +
        '<div class="footer-bottom">' +
          '<span>© 2026 AdhanBox · Adel Hanifi</span>' +
          '<span class="arabic">بِسْمِ ٱللَّٰهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ</span>' +
        '</div>' +
      '</div>' +
    '</footer>';

  document.body.insertAdjacentHTML('afterbegin', HEADER);
  document.body.insertAdjacentHTML('beforeend', FOOTER);

  // Lien actif
  if (page) {
    var active = document.querySelector('.menu-nav a[data-nav="' + page + '"]');
    if (active) active.classList.add('active');
  }

  // Ombre du header au défilement
  var header = document.getElementById('header');
  window.addEventListener('scroll', function () {
    header.classList.toggle('scrolled', window.scrollY > 20);
  }, { passive: true });

  // Ouverture / fermeture du menu burger
  var burger = document.getElementById('burger');
  var overlay = document.getElementById('menu-overlay');
  function setMenu(open) {
    document.body.classList.toggle('menu-open', open);
    burger.setAttribute('aria-expanded', open ? 'true' : 'false');
    overlay.setAttribute('aria-hidden', open ? 'false' : 'true');
    burger.setAttribute('aria-label', open ? 'Fermer le menu' : 'Ouvrir le menu');
  }
  burger.addEventListener('click', function () {
    setMenu(!document.body.classList.contains('menu-open'));
  });
  overlay.addEventListener('click', function (e) {
    if (e.target.tagName === 'A') setMenu(false);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && document.body.classList.contains('menu-open')) setMenu(false);
  });

  // Apparition au défilement
  var revealObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });
  document.querySelectorAll('.reveal').forEach(function (el) { revealObserver.observe(el); });

  // Accordéon FAQ
  document.querySelectorAll('.faq-q').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var item = btn.parentElement;
      var answer = item.querySelector('.faq-a');
      var isOpen = item.classList.contains('open');
      document.querySelectorAll('.faq-item.open').forEach(function (other) {
        other.classList.remove('open');
        other.querySelector('.faq-a').style.maxHeight = null;
        other.querySelector('.faq-q').setAttribute('aria-expanded', 'false');
      });
      if (!isOpen) {
        item.classList.add('open');
        answer.style.maxHeight = answer.scrollHeight + 'px';
        btn.setAttribute('aria-expanded', 'true');
      }
    });
  });

  // Liste d'attente : envoi AJAX (Formspree) sans quitter la page
  var wlForm = document.getElementById('waitlist-form');
  if (wlForm) {
    wlForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var btn = wlForm.querySelector('button[type="submit"]');
      var original = btn.innerHTML;
      btn.disabled = true;
      btn.textContent = 'Envoi…';
      fetch(wlForm.action, {
        method: 'POST',
        body: new FormData(wlForm),
        headers: { 'Accept': 'application/json' }
      }).then(function (res) {
        if (res.ok) {
          wlForm.hidden = true;
          var ok = document.getElementById('waitlist-success');
          if (ok) ok.hidden = false;
        } else {
          throw new Error('rejet serveur');
        }
      }).catch(function () {
        btn.disabled = false;
        btn.innerHTML = original;
        alert('Une erreur est survenue. Réessayez ou écrivez à contact@adhanbox.fr');
      });
    });
  }
})();
