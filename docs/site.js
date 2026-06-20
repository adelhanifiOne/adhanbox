/* ════════════════════════════════════════════════════════════
   AdhanBox — éléments partagés (header, menu burger, footer)
   injectés sur toutes les pages + comportements communs.
   ════════════════════════════════════════════════════════════ */
(function () {
  var page = document.body.getAttribute('data-page') || '';

  var LOGO_SVG =
    '<span class="logo-mark" aria-hidden="true">' +
      '<svg width="20" height="20" viewBox="0 0 64 64" fill="none">' +
        '<path d="M32 10c2.4 8 8 12.6 16 15v24a3 3 0 0 1-3 3H19a3 3 0 0 1-3-3V25c8-2.4 13.6-7 16-15z" fill="#F7EEDC"/>' +
        '<circle cx="32" cy="34" r="7" fill="#0C5B45"/>' +
      '</svg>' +
    '</span>';

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
        '<a href="index.html#configurateur" data-nav="configurateur">Personnaliser</a>' +
        '<div class="menu-group" id="menu-group-produit">' +
          '<button class="menu-group-toggle" aria-expanded="false">Le produit' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>' +
          '</button>' +
          '<div class="menu-sub">' +
            '<a href="produit.html#horaires">Horaires</a>' +
            '<a href="produit.html#lumiere">Lumière</a>' +
            '<a href="produit.html#adhan">Adhan</a>' +
            '<a href="produit.html#application">Application</a>' +
          '</div>' +
        '</div>' +
        '<a href="faq.html" data-nav="faq">FAQ</a>' +
        '<a href="contact.html" data-nav="contact">Contact</a>' +
        '<a href="offres.html" class="btn btn-primary menu-cta" data-nav="offres">Commander</a>' +
        '<div class="menu-arabic">صدقة جارية</div>' +
      '</nav>' +
    '</div>' +
    '<a href="offres.html" class="order-fab" aria-label="Commander l\'AdhanBox">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.7 13.4a2 2 0 0 0 2 1.6h9.7a2 2 0 0 0 2-1.6L23 6H6"/></svg>' +
      'Commander' +
    '</a>';

  var FOOTER =
    '<footer>' +
      '<div class="container">' +
        '<div class="footer-grid">' +
          '<div class="footer-brand">' +
            '<a href="index.html" class="logo" aria-label="AdhanBox — Accueil">' + LOGO_SVG + 'Adhan<span>Box</span></a>' +
            '<p>Boîtier d\'appel à la prière artisanal et connecté, conçu et fabriqué avec minutie pour soutenir la communauté musulmane.</p>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Le produit</h4>' +
            '<ul>' +
              '<li><a href="produit.html#horaires">Horaires de prière</a></li>' +
              '<li><a href="produit.html#lumiere">Lumière d\'ambiance</a></li>' +
              '<li><a href="produit.html#adhan">Adhan &amp; doua</a></li>' +
              '<li><a href="produit.html#application">Application</a></li>' +
            '</ul>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Naviguer</h4>' +
            '<ul>' +
              '<li><a href="index.html#configurateur">Personnaliser</a></li>' +
              '<li><a href="offres.html">Offres</a></li>' +
              '<li><a href="faq.html">FAQ</a></li>' +
              '<li><a href="contact.html">Contact</a></li>' +
            '</ul>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Ressources</h4>' +
            '<ul>' +
              '<li><a href="privacy.html">Politique de confidentialité</a></li>' +
              '<li><a href="mailto:adel.hanifi@yahoo.fr">adel.hanifi@yahoo.fr</a></li>' +
            '</ul>' +
          '</div>' +
        '</div>' +
        '<div class="footer-bottom">' +
          '<span>© 2026 AdhanBox · Adel Hanifi</span>' +
          '<span class="arabic">بِسْمِ ٱللَّٰهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ · صدقة جارية</span>' +
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

  // Sous-menu « Le produit »
  var group = document.getElementById('menu-group-produit');
  var toggle = group.querySelector('.menu-group-toggle');
  toggle.addEventListener('click', function () {
    var open = group.classList.toggle('open');
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
  });
  if (page === 'produit') {
    group.classList.add('open');
    toggle.setAttribute('aria-expanded', 'true');
  }

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
})();
