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
            '<h4>Suivez-nous</h4>' +
            '<div class="fs-links">' +
              '<a class="fs-link" href="https://www.instagram.com/adhanbox" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2.2c3.2 0 3.6 0 4.9.07 1.2.05 1.8.25 2.2.42.6.22 1 .48 1.4.9.44.42.7.82.92 1.4.17.42.37 1.04.42 2.24.06 1.28.07 1.66.07 4.88s0 3.6-.07 4.88c-.05 1.2-.25 1.82-.42 2.24a3.8 3.8 0 0 1-.92 1.4c-.4.42-.8.68-1.4.9-.4.17-1 .37-2.2.42-1.3.06-1.7.07-4.9.07s-3.6 0-4.9-.07c-1.2-.05-1.8-.25-2.2-.42a3.8 3.8 0 0 1-1.4-.9 3.8 3.8 0 0 1-.92-1.4c-.17-.42-.37-1.04-.42-2.24C2.2 15.6 2.2 15.2 2.2 12s0-3.6.07-4.88c.05-1.2.25-1.82.42-2.24.22-.58.48-.98.92-1.4.4-.42.8-.68 1.4-.9.4-.17 1-.37 2.2-.42C8.4 2.2 8.8 2.2 12 2.2zm0 1.8c-3.15 0-3.5 0-4.75.07-.9.04-1.4.2-1.72.32-.44.17-.75.37-1.08.7-.33.32-.53.63-.7 1.07-.13.33-.28.83-.32 1.73C3.36 9.14 3.35 9.5 3.35 12s0 2.86.08 4.11c.04.9.19 1.4.32 1.73.17.44.37.75.7 1.07.33.33.64.53 1.08.7.32.13.82.28 1.72.32 1.25.07 1.6.07 4.75.07s3.5 0 4.75-.07c.9-.04 1.4-.19 1.72-.32.44-.17.75-.37 1.08-.7.33-.32.53-.63.7-1.07.13-.33.28-.83.32-1.73.07-1.25.08-1.6.08-4.11s0-2.86-.08-4.11c-.04-.9-.19-1.4-.32-1.73a2.9 2.9 0 0 0-.7-1.07 2.9 2.9 0 0 0-1.08-.7c-.32-.13-.82-.28-1.72-.32C15.5 4 15.15 4 12 4zm0 3.06a4.94 4.94 0 1 1 0 9.88 4.94 4.94 0 0 1 0-9.88zm0 1.8a3.14 3.14 0 1 0 0 6.28 3.14 3.14 0 0 0 0-6.28zm5.15-2.05a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z"/></svg><span>@adhanbox</span></a>' +
              '<a class="fs-link" href="https://www.tiktok.com/@adhanbox_officiel" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M13.3 2h2.9c.16 1.3.62 2.35 1.4 3.14.77.78 1.8 1.24 3.1 1.4v2.93c-1.6-.05-3-.5-4.2-1.35v6.44c0 1.2-.27 2.3-.82 3.27a5.9 5.9 0 0 1-2.28 2.28 6.3 6.3 0 0 1-3.2.83 6.2 6.2 0 0 1-3.14-.84 6.1 6.1 0 0 1-2.28-2.29A6.2 6.2 0 0 1 4 14.6c0-1.14.28-2.2.84-3.16a6.1 6.1 0 0 1 2.3-2.3 6.1 6.1 0 0 1 3.13-.85c.28 0 .55.02.83.06v3a3.2 3.2 0 0 0-4.3 3.03 3.2 3.2 0 0 0 3.2 3.22c.9 0 1.65-.32 2.27-.96.6-.63.9-1.4.9-2.3L13.3 2z"/></svg><span>@adhanbox_officiel</span></a>' +
              '<a class="fs-link" href="https://www.facebook.com/people/Adhanbox/61591952944804/" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M22 12.06C22 6.5 17.52 2 12 2S2 6.5 2 12.06c0 5.02 3.66 9.18 8.44 9.94v-7.03H7.9v-2.9h2.54V9.85c0-2.52 1.5-3.9 3.77-3.9 1.1 0 2.24.19 2.24.19v2.46H15.2c-1.24 0-1.63.78-1.63 1.57v1.89h2.78l-.44 2.9h-2.34v7.03C18.34 21.24 22 17.08 22 12.06z"/></svg><span>@adhanbox</span></a>' +
            '</div>' +
          '</div>' +
          '<div class="footer-col">' +
            '<h4>Ressources</h4>' +
            '<ul>' +
              '<li><a href="privacy.html">Politique de confidentialité</a></li>' +
              '<li><a href="cgv.html">Conditions générales de vente</a></li>' +
              '<li><a href="mentions-legales.html">Mentions légales</a></li>' +
              '<li><a href="conformite.html">Déclaration UE de conformité</a></li>' +
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
