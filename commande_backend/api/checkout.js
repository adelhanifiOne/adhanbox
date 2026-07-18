// POST /api/checkout  { finish, mandala, mandalaColor }
// Crée une session Stripe Checkout avec la configuration choisie sur
// adhanbox.fr/personnaliser.html : le client ne choisit qu'UNE fois (sur le
// site), et la config est visible partout (page de paiement, dashboard,
// reçu, email de confirmation) via le nom de l'article + les métadonnées.
import Stripe from 'stripe';

// Palette alignée sur docs/configurator.js (10 couleurs).
const PALETTE = {
  bois: 'Bois', marbre: 'Marbre', blanc: 'Blanc', gris: 'Gris', noir: 'Noir',
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

function corsHeaders(request) {
  const origin = request.headers.get('origin') || '';
  const h = {
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Vary': 'Origin',
  };
  if (ALLOWED_ORIGINS.includes(origin)) h['Access-Control-Allow-Origin'] = origin;
  return h;
}

export default async function handler(request) {
  const cors = corsHeaders(request);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') {
    return Response.json({ error: 'Méthode non autorisée' }, { status: 405, headers: cors });
  }

  let body;
  try { body = await request.json(); } catch { body = {}; }

  const chassis = PALETTE[body.finish];
  const m = parseInt(body.mandala, 10);
  const motifColor = PALETTE[body.mandalaColor];
  // Validation stricte côté serveur : le prix et les options ne peuvent pas
  // être manipulés depuis le navigateur.
  if (!chassis || !(m >= 0 && m <= 5) || (m > 0 && !motifColor)) {
    return Response.json({ error: 'Configuration invalide' }, { status: 400, headers: cors });
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
            name: 'AdhanBox — Précommande',
            description: configLabel,
            images: [`${SITE}/og-adhanbox.jpg`],
          },
        },
      }],
      shipping_address_collection: { allowed_countries: ['FR', 'BE', 'CH', 'LU', 'MC'] },
      phone_number_collection: { enabled: true },
      metadata,
      // Métadonnées aussi sur le PaymentIntent -> visibles directement sur la
      // page du paiement dans le dashboard Stripe.
      payment_intent_data: { metadata },
      success_url: `${SITE}/merci.html?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE}/personnaliser.html`,
    });

    return Response.json({ url: session.url }, { status: 200, headers: cors });
  } catch (err) {
    console.error('checkout error:', err && err.message);
    return Response.json({ error: 'Erreur serveur — réessayez.' }, { status: 500, headers: cors });
  }
}
