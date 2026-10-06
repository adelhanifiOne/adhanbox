// GET  /api/relais?session_id=cs_…   -> { livraison, relais, adresse, ref }
// POST /api/relais  { session_id, relais: { code, network, name, street, zipCode, city } }
//
// Choix du point relais APRES le paiement (depuis le 06/10/2026). La page
// merci.html, ou le lien de l'email de confirmation, ouvre la carte Boxtal
// avec l'adresse de livraison donnee a Stripe : le point le plus proche est
// selectionne tout seul et enregistre ici ; le client peut en choisir un
// autre jusqu'a l'expedition.
//
// Le choix est ecrit dans les metadonnees du PaymentIntent (toujours
// modifiables, visibles sur la page du paiement dans le dashboard Stripe) et,
// quand Stripe l'accepte, dans celles de la session. api/order-step.js lit
// les deux. Le vendeur recoit un email « Point relais choisi » avec le code.
//
// Le session_id est le secret de ce point d'entree : il n'existe que dans
// l'URL de retour de Stripe et dans l'email du client. On ne renvoie jamais
// ni nom, ni email, ni telephone : seulement ce qui sert a chercher un
// relais (rue, code postal, ville).
//
// Signature Node (req, res), NODEJS_HELPERS=0 (voir checkout.js).
import Stripe from 'stripe';
import { Resend } from 'resend';
import { list } from '@vercel/blob';
import { esc } from '../lib/email.js';

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899',
];
const FROM_EMAIL = process.env.FROM_EMAIL || 'AdhanBox <commande@adhanbox.fr>';
const NOTIF_EMAIL = process.env.NOTIF_EMAIL || 'contact@adhanbox.fr';
const SESSION_RE = /^cs_(live|test)_[A-Za-z0-9]{10,}$/;

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (ALLOWED_ORIGINS.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(obj));
}

async function readJson(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return {}; }
}

// Meme nettoyage que checkout.js : seulement ce qui sert a expedier.
function cleanRelais(r) {
  if (!r || typeof r !== 'object') return null;
  const s = (v, n) => String(v || '').replace(/\s+/g, ' ').trim().slice(0, n);
  const code = s(r.code, 40), network = s(r.network, 40), name = s(r.name, 80);
  const street = s(r.street, 120), zipCode = s(r.zipCode, 10), city = s(r.city, 60);
  if (!code || !network || !name || !zipCode || !city) return null;
  return { code, network, name, street, zipCode, city };
}

/** Point relais deja enregistre : metadonnees du PaymentIntent d'abord
 *  (c'est la qu'ecrit ce fichier), puis celles de la session (choix fait
 *  avant le paiement, anciennes commandes). */
function relaisEnregistre(session) {
  const pi = session.payment_intent && typeof session.payment_intent === 'object' ? session.payment_intent : null;
  const pim = (pi && pi.metadata) || {};
  const m = session.metadata || {};
  const code = pim.relais_code || m.relais_code;
  if (!code) return null;
  return {
    code,
    network: pim.relais_reseau || m.relais_reseau || '',
    name: pim.relais_nom || m.relais_nom || '',
    address: pim.relais_adresse || m.relais_adresse || '',
  };
}

async function chargerSession(stripe, id) {
  const s = await stripe.checkout.sessions.retrieve(id, { expand: ['payment_intent'] });
  const piId = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
  const ref = (piId || s.id).slice(-8).toUpperCase();
  return { s, piId, ref };
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'GET' && req.method !== 'POST') return sendJson(res, 405, { error: 'Méthode non autorisée' });
  if (!process.env.STRIPE_SECRET_KEY) return sendJson(res, 500, { error: 'Configuration incomplète' });

  const body = req.method === 'POST' ? await readJson(req) : {};
  const url = new URL(req.url, 'http://localhost');
  const sessionId = String(body.session_id || url.searchParams.get('session_id') || '');
  if (!SESSION_RE.test(sessionId)) return sendJson(res, 400, { error: 'Commande inconnue' });

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  let s, piId, ref;
  try {
    ({ s, piId, ref } = await chargerSession(stripe, sessionId));
  } catch (e) {
    return sendJson(res, 404, { error: 'Commande introuvable' });
  }
  if (s.payment_status !== 'paid') return sendJson(res, 409, { error: 'Commande non payée' });

  const m = s.metadata || {};
  const livraison = m.livraison === 'Point relais' ? 'relais' : 'domicile';

  if (req.method === 'GET') {
    const sh = s.shipping_details || s.collected_information?.shipping_details || null;
    const a = (sh && sh.address) || {};
    return sendJson(res, 200, {
      ref,
      livraison,
      relais: relaisEnregistre(s),
      adresse: { street: [a.line1, a.line2].filter(Boolean).join(', '), zipCode: a.postal_code || '', city: a.city || '' },
    });
  }

  // POST : enregistrer (ou changer) le point relais
  if (livraison !== 'relais') return sendJson(res, 409, { error: 'Cette commande est livrée à domicile' });
  const relais = cleanRelais(body.relais);
  if (!relais) return sendJson(res, 400, { error: 'Point relais incomplet' });

  // Trop tard une fois le colis parti : l'etiquette porte deja un relais.
  try {
    const { blobs } = await list({ prefix: `orders/${ref}/` });
    if (blobs.some((b) => b.pathname === `orders/${ref}/expedition.json`)) {
      return sendJson(res, 409, { error: 'Commande déjà expédiée : écrivez-nous pour changer de point relais.' });
    }
  } catch {
    // Blob indisponible : on laisse passer plutot que de bloquer un choix legitime.
  }

  const precedent = relaisEnregistre(s);
  const metadata = {
    relais_code: relais.code,
    relais_reseau: relais.network,
    relais_nom: relais.name,
    relais_adresse: `${relais.street} ${relais.zipCode} ${relais.city}`.trim(),
    relais_choisi_le: new Date().toISOString(),
    relais_a_choisir: '',
  };
  try {
    if (piId) await stripe.paymentIntents.update(piId, { metadata });
  } catch (e) {
    console.error('relais: PaymentIntent non mis a jour:', e && e.message);
    return sendJson(res, 502, { error: 'Enregistrement impossible, réessayez.' });
  }
  try {
    await stripe.checkout.sessions.update(s.id, { metadata });
  } catch (e) {
    // Selon la version de l'API, la session payee n'est plus modifiable :
    // le PaymentIntent suffit, order-step.js le lit en premier.
    console.log('relais: session non mise a jour (' + (e && e.message) + ')');
  }

  // Le vendeur cree l'expedition Boxtal avec ce code : il doit le recevoir.
  if (process.env.RESEND_API_KEY) {
    try {
      const resend = new Resend(process.env.RESEND_API_KEY);
      const adresse = `${relais.street}, ${relais.zipCode} ${relais.city}`;
      await resend.emails.send({
        from: FROM_EMAIL,
        to: NOTIF_EMAIL,
        subject: `📍 Point relais ${precedent ? 'changé' : 'choisi'} — commande N° ${ref}`,
        html: `<div style="font-family:Arial,sans-serif;font-size:15px;color:#232323;line-height:1.7;">
  <h2 style="color:#0C5B45;">📍 Point relais ${precedent ? 'changé' : 'choisi'} — commande N° ${esc(ref)}</h2>
  <p><b>${esc(relais.name)}</b><br>${esc(adresse)}<br>
     code <span style="background:#FBF3E3;padding:1px 6px;border-radius:6px;font-family:monospace;">${esc(relais.code)}</span>
     · réseau ${esc(relais.network)}</p>
  ${precedent ? `<p style="color:#777;">Remplace : ${esc(precedent.name)} (${esc(precedent.code)}).</p>` : ''}
  <p>Le code est aussi dans les métadonnées du paiement : <a href="https://dashboard.stripe.com/payments/${esc(piId || '')}">voir dans Stripe →</a></p>
</div>`,
        text: [`Point relais ${precedent ? 'change' : 'choisi'} — commande N° ${ref}`, relais.name, adresse,
               `code ${relais.code} · reseau ${relais.network}`].join('\n'),
      });
    } catch (e) {
      console.error('relais: email vendeur non envoye:', e && e.message);
    }
  }

  return sendJson(res, 200, { ok: true, relais: { ...relais, address: `${relais.street}, ${relais.zipCode} ${relais.city}` } });
}
