// POST /api/checkout  { finish, mandala, mandalaColor, livraison, relais }
// Crée une session Stripe Checkout avec la configuration choisie sur
// adhanbox.fr/personnaliser.html : le client ne choisit qu'UNE fois (sur le
// site), et la config est visible partout (page de paiement, dashboard,
// reçu, email de confirmation) via le nom de l'article + les métadonnées.
//
// Livraison (choisie sur le site, voir docs/configurator.js) :
//   livraison: 'relais'   -> point relais Mondial Relay, offert ;
//                            relais = { code, network, name, street, zipCode, city }
//                            tel que renvoye par la carte Boxtal.
//   livraison: 'domicile' -> Colissimo suivi a domicile, +5 € (DOMICILE_CENTS).
// Le mode et le point relais partent en metadonnees : le webhook les met dans
// les emails, et le vendeur cree l'expedition Boxtal avec le code du relais.
//
// Signature Node (req, res) — les fonctions Vercel de ce projet tournent
// SANS les helpers (@vercel/node, NODEJS_HELPERS=0) : lecture du flux et
// réponses en Node pur, comportement identique en local et en prod.
import Stripe from 'stripe';

// Deux palettes DISTINCTES, alignées sur docs/configurator.js : le châssis et
// le motif ne se font pas dans les mêmes bobines. Ce qui n'est pas dans ces
// listes est refusé plus bas — donc toute couleur ajoutée au configurateur
// doit l'être ici AVANT la mise en ligne, sinon la commande échoue sur
// « Configuration invalide ».
const CHASSIS = {
  beige: 'Beige', noir: 'Noir', blanc: 'Blanc', marbre: 'Marbre',
  marron: 'Marron', creme: 'Crème', gris: 'Gris',
  cacahuete: 'Marron cacahuète', 'vert-foret': 'Vert forêt',
  'gris-texture': 'Gris texturé',
};
// Noms des trois motifs de facade (06/10/2026), alignes sur docs/configurator.js.
// Le numero reste la reference de l'atelier : les deux figurent dans la commande.
const MOTIF_NOMS = { 1: 'Arabesque', 2: 'Lotus', 3: 'Rosace' };
const MOTIFS = {
  noir: 'Noir', blanc: 'Blanc', rouge: 'Rouge', rose: 'Rose',
  bleu: 'Bleu', 'vert-foret': 'Vert forêt', or: 'Or', marron: 'Marron',
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
// Participation demandee pour la livraison a domicile (le relais est offert).
const DOMICILE_CENTS = parseInt(process.env.DOMICILE_CENTS || '500', 10);

// Point relais renvoye par la carte Boxtal : on ne garde que ce qui sert a
// expedier, borne en longueur (les metadonnees Stripe sont limitees a 500 car.).
function cleanRelais(r) {
  if (!r || typeof r !== 'object') return null;
  const s = (v, n) => String(v || '').replace(/\s+/g, ' ').trim().slice(0, n);
  const code = s(r.code, 40), network = s(r.network, 40), name = s(r.name, 80);
  const street = s(r.street, 120), zipCode = s(r.zipCode, 10), city = s(r.city, 60);
  if (!code || !network || !name || !zipCode || !city) return null;
  return { code, network, name, street, zipCode, city };
}

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
  const chassis = CHASSIS[body.finish];
  const m = parseInt(body.mandala, 10);
  const motifColor = MOTIFS[body.mandalaColor];
  // Validation stricte côté serveur : le prix et les options ne peuvent pas
  // être manipulés depuis le navigateur.
  if (!chassis || !(m >= 0 && m <= 5) || (m > 0 && !motifColor)) {
    return sendJson(res, 400, { error: 'Configuration invalide' });
  }

  const nomMotif = MOTIF_NOMS[m] ? ` « ${MOTIF_NOMS[m]} »` : '';
  const configLabel = m === 0
    ? `Châssis ${chassis} · Sans motif`
    : `Châssis ${chassis} · Motif ${m}${nomMotif} (${motifColor})`;

  // Livraison : 'relais' = Mondial Relay offert. Depuis le 06/10/2026 le point
  // n'est plus choisi AVANT le paiement (le bouton de commande restait grise
  // tant que la carte n'avait pas ete utilisee, et c'etait le principal point
  // de fuite du tunnel) : le client paie, puis la page merci.html lui propose
  // le point le plus proche de son adresse (api/relais.js), modifiable jusqu'a
  // l'expedition. Un point deja choisi reste accepte, pour compatibilite.
  const modeRelais = body.livraison === 'relais';
  const relais = modeRelais ? cleanRelais(body.relais) : null;
  const livraison = modeRelais ? 'relais' : 'domicile';
  const shippingOption = modeRelais
    ? {
        shipping_rate_data: {
          type: 'fixed_amount',
          fixed_amount: { amount: 0, currency: 'eur' },
          display_name: relais
            ? `Point relais — ${relais.name}`
            : 'Point relais Mondial Relay — offert (choix du point après paiement)',
          delivery_estimate: {
            minimum: { unit: 'business_day', value: 2 },
            maximum: { unit: 'business_day', value: 4 },
          },
        },
      }
    : {
        shipping_rate_data: {
          type: 'fixed_amount',
          fixed_amount: { amount: DOMICILE_CENTS, currency: 'eur' },
          display_name: 'Livraison à domicile — Colissimo suivi',
          delivery_estimate: {
            minimum: { unit: 'business_day', value: 2 },
            maximum: { unit: 'business_day', value: 3 },
          },
        },
      };

  const metadata = {
    couleur_boitier: chassis,
    motif: m === 0 ? 'Sans motif' : `Motif ${m}${nomMotif}`,
    couleur_motif: m === 0 ? '-' : motifColor,
    config: configLabel,
    livraison: modeRelais ? 'Point relais' : 'Domicile',
    ...(relais ? {
      relais_code: relais.code,
      relais_reseau: relais.network,
      relais_nom: relais.name,
      relais_adresse: `${relais.street} ${relais.zipCode} ${relais.city}`.trim(),
    } : (modeRelais ? { relais_a_choisir: '1' } : {})),
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
      // France metropolitaine + Monaco uniquement : c'est ce que promettent les
      // CGV (art. 7, Colissimo suivi, livraison offerte). Ne pas rouvrir la
      // Suisse sans ajouter des frais de port ET la declaration douaniere :
      // hors union douaniere, le colis coute bien plus cher et le client peut
      // avoir des frais a payer a la reception.
      shipping_address_collection: { allowed_countries: ['FR', 'MC'] },
      // Une seule option, celle choisie sur le site : Stripe l'affiche comme
      // ligne de livraison (0 € en relais, DOMICILE_CENTS a domicile) et la
      // reporte sur le recu et la facture.
      shipping_options: [shippingOption],
      phone_number_collection: { enabled: true },
      // Facture obligatoire en vente a distance. Stripe la genere et l'envoie
      // au client ; elle est aussi telechargeable depuis le dashboard.
      invoice_creation: {
        enabled: true,
        invoice_data: {
          description: `AdhanBox — ${configLabel}`,
          footer: [
            'TVA non applicable, article 293 B du CGI (franchise en base de TVA).',
            'Adel Hanifi — AdhanBox, 14 rue du Corps Franc Pommiès, 65500 Vic-en-Bigorre.',
            'SIRET 932 355 589 00023 — contact@adhanbox.fr — adhanbox.fr',
            modeRelais
              ? 'Livraison offerte en point relais (Mondial Relay).'
              : 'Livraison à domicile par Colissimo suivi.',
          ].join('\n'),
          rendering_options: { amount_tax_display: 'exclude_tax' },
          metadata,
        },
      },
      // Un seul champ en plus du formulaire Stripe : le message pour la carte.
      // Du 21/09 au 06/10/2026, deux champs obligatoires redemandaient prenom et
      // nom apres l'adresse (des etiquettes partaient avec un prenom seul) :
      // c'etait de la friction au pire moment (audit du 06/10). Le webhook
      // complete un nom incomplet avec celui porte par la carte, et signale au
      // vendeur les cas douteux ; le reste se regle par email, c'est rare.
      // Stripe plafonne custom_fields a 3 entrees.
      custom_fields: [{
        // Cadeau : message facultatif, recopie a la main sur la carte signee.
        // Lu par le webhook (session.custom_fields) et transmis au vendeur.
        key: 'message_carte',
        label: { type: 'custom', custom: 'Message pour la carte (facultatif)' },
        type: 'text',
        optional: true,
        text: { maximum_length: 120 },
      }],
      // Textes affiches par Stripe : sous le formulaire de livraison, pour
      // obtenir un nom complet sans champ supplementaire ; sous le bouton, la
      // promesse de fabrication. (Limites Stripe : 1 200 caracteres chacun.)
      custom_text: {
        shipping_address: { message: 'Prénom et nom complets, s\'il vous plaît : ils figurent sur l\'étiquette du colis.' },
        submit: { message: 'Fabriquée à la main à la commande, expédiée sous 1 à 2 semaines avec numéro de suivi. Satisfait ou remboursé 14 jours, retour offert. Garantie 2 ans.' },
      },
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
