// GET /api/order-amount?id=cs_...  →  { amount, currency }
//
// Renvoie UNIQUEMENT le montant réellement payé pour une session Checkout,
// afin que la page « merci » puisse envoyer au pixel Meta la vraie valeur
// (remise déduite) au lieu du prix catalogue. Aucune donnée personnelle
// n'est exposée : ni email, ni nom, ni adresse.
//
// Signature Node (req, res), helpers désactivés (NODEJS_HELPERS=0).
import Stripe from 'stripe';

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899',
];

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (ALLOWED_ORIGINS.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
}

function send(res, code, body) {
  res.statusCode = code;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(body));
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'GET') return send(res, 405, { error: 'Méthode non autorisée' });

  // NODEJS_HELPERS=0 : pas de req.query, on lit les paramètres depuis l'URL.
  const url = new URL(req.url, 'http://localhost');
  const id = url.searchParams.get('id') || '';
  // Les identifiants de session Stripe sont longs et aléatoires : on refuse
  // tout ce qui n'a pas la bonne forme, sans même appeler l'API.
  if (!/^cs_[A-Za-z0-9_]{20,80}$/.test(id)) {
    return send(res, 400, { error: 'Identifiant de session invalide' });
  }

  if (!process.env.STRIPE_SECRET_KEY) {
    return send(res, 500, { error: 'Configuration serveur incomplète' });
  }

  try {
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
    const session = await stripe.checkout.sessions.retrieve(id);

    // On ne divulgue le montant que si le paiement a bien abouti.
    if (session.payment_status !== 'paid') {
      return send(res, 404, { error: 'Paiement non abouti' });
    }

    // Le montant peut être mis en cache : il ne changera plus.
    res.setHeader('Cache-Control', 'public, max-age=3600');
    return send(res, 200, {
      amount: (session.amount_total ?? 0) / 100,
      currency: (session.currency || 'eur').toUpperCase(),
    });
  } catch (err) {
    console.error('order-amount:', err && err.message);
    return send(res, 404, { error: 'Session introuvable' });
  }
}
