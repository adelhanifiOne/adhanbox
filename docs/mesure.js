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
