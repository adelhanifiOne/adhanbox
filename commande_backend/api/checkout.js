// POST /api/checkout  { finish, mandala, mandalaColor }
// Crée une session Stripe Checkout avec la configuration choisie sur
// adhanbox.fr/personnaliser.html : le client ne choisit qu'UNE fois (sur le
// site), et la config est visible partout (page de paiement, dashboard,
// reçu, email de confirmation) via le nom de l'article + les métadonnées.
//
// Signature Node (req, res) — les fonctions Vercel de ce projet tournent
// SANS les helpers (@vercel/node, NODEJS_HELPERS=0) : lecture du flux et
// réponses en Node pur, comportement identique en local et en prod.
import Stripe from 'stripe';

// Palette alignée sur docs/configurator.js (10 couleurs).
const PALETTE = {
  marbre: 'Marbre', blanc: 'Blanc', gris: 'Gris', noir: 'Noir',
  dore: 'Doré', rouge: 'Rouge', vert: 'Vert', bleu: 'Bleu', violet: 'Violet',
};

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899', // tests locaux (python -m http.server)
];

const SITE = process.env.SITE_URL || 'https://adhanbox.fr';
// Prix en centimes — offre de lancement 95 €. Modifiable sans toucher au code
// via la variable d'environnement AMOUNT_CENTS (puis redéployer).
const AMOUNT_CENTS = parseInt(process.env.AMOUNT_CENTS || '9500', 10);

async function readJson(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return {}; }
}

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (ALLOWED_ORIGINS.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj));
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'Méthode non autorisée' });

  const body = await readJson(req);
  const chassis = PALETTE[body.finish];
  const m = parseInt(body.mandala, 10);
  const motifColor = PALETTE[body.mandalaColor];
  // Validation stricte côté serveur : le prix et les options ne peuvent pas
  // être manipulés depuis le navigateur.
  if (!chassis || !(m >= 0 && m <= 5) || (m > 0 && !motifColor)) {
    return sendJson(res, 400, { error: 'Configuration invalide' });
  }

  const configLabel = m === 0
    ? `Châssis ${chassis} · Sans motif`
    : `Châssis ${chassis} · Motif ${m} (${motifColor})`;

  const metadata = {
    couleur_boitier: chassis,
    motif: m === 0 ? 'Sans motif' : `Motif ${m}`,
    couleur_motif: m === 0 ? '-' : motifColor,
    config: configLabel,
    source: 'adhanbox.fr/personnaliser',
  };

  try {
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      locale: 'fr',
      customer_creation: 'always',
      line_items: [{
        quantity: 1,
        price_data: {
          currency: 'eur',
          unit_amount: AMOUNT_CENTS,
          product_data: {
            name: 'AdhanBox — Commande',
            description: configLabel,
            images: [`${SITE}/og-adhanbox.jpg`],
          },
        },
      }],
      shipping_address_collection: { allowed_countries: ['FR', 'BE', 'CH', 'LU', 'MC'] },
      phone_number_collection: { enabled: true },
      // Champ « code promo » sur la page de paiement. Les codes eux-memes
      // (FAMILLE, ADHAN5...) se creent dans le dashboard Stripe : on peut
      // les creer, suspendre ou limiter sans retoucher au code.
      allow_promotion_codes: true,
      metadata,
      // Métadonnées aussi sur le PaymentIntent -> visibles directement sur la
      // page du paiement dans le dashboard Stripe.
      payment_intent_data: { metadata },
      success_url: `${SITE}/merci.html?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE}/personnaliser.html`,
    });

    return sendJson(res, 200, { url: session.url });
  } catch (err) {
    console.error('checkout error:', err && err.message);
    return sendJson(res, 500, { error: 'Erreur serveur — réessayez.' });
  }
}
