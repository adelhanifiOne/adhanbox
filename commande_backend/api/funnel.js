// GET /api/funnel?token=…&jours=14
//
// Le bas du tunnel de vente, lu chez Stripe : par jour, combien de pages de
// paiement ont ete ouvertes (sessions Checkout creees), combien ont ete
// payees, pour quel montant, en relais ou a domicile, avec ou sans code
// promo. Repond en page HTML, a ouvrir dans un navigateur.
//
// Le haut du tunnel (clics sur la pub, pages vues) n'est pas ici : il se lit
// dans Ads Manager et dans Cloudflare Web Analytics (docs/mesure.js).
//
// Meme protection que order-step.js : jeton partage dans l'URL. Aucune
// donnee personnelle n'est affichee : ni nom, ni email, ni adresse.
import Stripe from 'stripe';
import { esc } from '../lib/email.js';

const JOURS_DEFAUT = 14;
const JOURS_MAX = 90;

function jourParis(ts) {
  return new Date(ts * 1000).toLocaleDateString('fr-FR', {
    timeZone: 'Europe/Paris', year: 'numeric', month: '2-digit', day: '2-digit',
  });
}

function euros(cents) {
  return (cents / 100).toLocaleString('fr-FR', { style: 'currency', currency: 'EUR' });
}

function pct(n, d) {
  return d ? Math.round((n / d) * 1000) / 10 + ' %' : '–';
}

function page(res, status, title, body) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(`<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>
<style>
  body{font-family:-apple-system,Segoe UI,Arial,sans-serif;background:#F6F4EF;margin:0;padding:32px 16px;color:#232323}
  .card{max-width:860px;margin:0 auto;background:#fff;border-radius:16px;padding:28px;box-shadow:0 8px 30px rgba(0,0,0,.06)}
  h1{color:#0C5B45;font-size:22px;margin:0 0 6px}
  p{color:#555;font-size:14px;line-height:1.6;margin:8px 0}
  table{border-collapse:collapse;width:100%;margin-top:18px;font-size:14px;font-variant-numeric:tabular-nums}
  th,td{padding:8px 10px;border-bottom:1px solid #EEE;text-align:right}
  th:first-child,td:first-child{text-align:left}
  th{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:#777;background:#FAF8F3}
  tr.total td{font-weight:700;border-top:2px solid #0C5B45}
  .ok{color:#0C5B45;font-weight:600}
  .aide{margin-top:22px;padding:14px 16px;background:#FBF3E3;border-left:3px solid #B4791A;border-radius:0 8px 8px 0;font-size:13px;line-height:1.6}
</style></head><body><div class="card">${body}</div></body></html>`);
}

/** Toutes les sessions Checkout creees depuis `depuis` (timestamp Unix). */
async function sessionsDepuis(stripe, depuis) {
  const toutes = [];
  let starting_after;
  for (let i = 0; i < 20; i++) {
    const r = await stripe.checkout.sessions.list({
      created: { gte: depuis }, limit: 100,
      ...(starting_after ? { starting_after } : {}),
    });
    toutes.push(...r.data);
    if (!r.has_more || !r.data.length) break;
    starting_after = r.data[r.data.length - 1].id;
  }
  return toutes;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.statusCode = 405; return res.end('Méthode non autorisée'); }

  const url = new URL(req.url, 'http://localhost');
  const token = url.searchParams.get('token') || '';
  const ADMIN_TOKEN = process.env.ORDER_ADMIN_TOKEN || process.env.REVIEW_ADMIN_TOKEN || '';
  if (!ADMIN_TOKEN || token !== ADMIN_TOKEN) {
    return page(res, 403, 'Accès refusé', '<h1>Accès refusé</h1><p>Lien invalide.</p>');
  }
  if (!process.env.STRIPE_SECRET_KEY) {
    return page(res, 500, 'Configuration incomplète', '<h1>Configuration incomplète</h1><p>Clé Stripe absente.</p>');
  }

  let jours = parseInt(url.searchParams.get('jours') || String(JOURS_DEFAUT), 10);
  if (!(jours >= 1)) jours = JOURS_DEFAUT;
  if (jours > JOURS_MAX) jours = JOURS_MAX;
  const depuis = Math.floor(Date.now() / 1000) - jours * 86400;

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  let sessions;
  try {
    sessions = await sessionsDepuis(stripe, depuis);
  } catch (e) {
    return page(res, 502, 'Stripe injoignable', `<h1>Stripe injoignable</h1><p>${esc(e.message)}</p>`);
  }

  // Agregation par jour (heure de Paris), du plus recent au plus ancien.
  const parJour = new Map();
  const vide = () => ({ ouvertes: 0, payees: 0, montant: 0, relais: 0, domicile: 0, promo: 0, lienDirect: 0 });
  const total = vide();
  for (const s of sessions) {
    const j = jourParis(s.created);
    if (!parJour.has(j)) parJour.set(j, vide());
    const d = parJour.get(j);
    const paye = s.status === 'complete' && s.payment_status === 'paid';
    const m = s.metadata || {};
    const cumul = (c) => {
      c.ouvertes += 1;
      if (!m.source) c.lienDirect += 1;           // Payment Link de secours, sans metadonnees
      if (paye) {
        c.payees += 1;
        c.montant += s.amount_total || 0;
        if (m.livraison === 'Point relais') c.relais += 1; else c.domicile += 1;
        if ((s.total_details && s.total_details.amount_discount) > 0) c.promo += 1;
      }
    };
    cumul(d); cumul(total);
  }
  const lignes = [...parJour.entries()]
    .sort((a, b) => b[0].split('/').reverse().join('').localeCompare(a[0].split('/').reverse().join('')))
    .map(([j, c]) => `<tr><td>${esc(j)}</td><td>${c.ouvertes}</td><td class="ok">${c.payees}</td><td>${pct(c.payees, c.ouvertes)}</td><td>${euros(c.montant)}</td><td>${c.relais} / ${c.domicile}</td><td>${c.promo}</td></tr>`)
    .join('');

  const body = `
    <h1>Tunnel de vente — ${jours} derniers jours</h1>
    <p>Lu chez Stripe à l'instant. « Paiement ouvert » = une page de paiement créée depuis le site
       (un visiteur a cliqué « Commander cette configuration »). « Payé » = commande encaissée.</p>
    <table>
      <thead><tr><th>Jour</th><th>Paiement ouvert</th><th>Payé</th><th>Taux</th><th>Encaissé</th><th>Relais / domicile</th><th>Avec code promo</th></tr></thead>
      <tbody>${lignes || '<tr><td colspan="7" style="text-align:center;color:#777">Aucune page de paiement ouverte sur la période.</td></tr>'}
      <tr class="total"><td>Total</td><td>${total.ouvertes}</td><td class="ok">${total.payees}</td><td>${pct(total.payees, total.ouvertes)}</td><td>${euros(total.montant)}</td><td>${total.relais} / ${total.domicile}</td><td>${total.promo}</td></tr>
      </tbody>
    </table>
    ${total.lienDirect ? `<p>Dont ${total.lienDirect} page(s) ouverte(s) par le lien de paiement de secours (backend indisponible à ce moment-là).</p>` : ''}
    <div class="aide">
      <b>Pour lire tout le tunnel</b>, mettez ces chiffres en face de ceux du haut :<br>
      1. Ads Manager → « Clics sur un lien » de la campagne.<br>
      2. Cloudflare Web Analytics → pages vues de <code>/</code> et de <code>/personnaliser.html</code>, et le référent <code>instagram.com</code>.<br>
      3. Ce tableau → paiements ouverts, puis payés.<br>
      La plus grosse marche entre deux lignes, c'est là qu'on travaille en premier.
      Changer la période : <code>&amp;jours=30</code> (90 au plus).
    </div>`;
  return page(res, 200, 'Tunnel de vente', body);
}
