// GET /api/cron-avis          — appelé par Vercel chaque jour (voir vercel.json)
// GET /api/cron-avis?dry=1    — montre ce qui partirait, sans rien envoyer
//
// Dix jours après l'email « Expédiée », envoie l'email « Avis et photo ».
// Le colis met 2 à 4 jours : le client a donc vécu une semaine avec le boîtier.
//
// Tout repose sur les traces que laisse api/order-step.js dans Blob :
//   orders/<ref>/expedition.json  -> date d'envoi, email, prénom, config
//   orders/<ref>/avis.json        -> déjà envoyé (à la main ou par ici)
// Idempotent par construction : on n'envoie que s'il n'y a pas de avis.json,
// et on en écrit un aussitôt l'email parti. Un bouton « 4 · Avis » cliqué la
// veille laisse la même trace : la tâche ne renverra rien.
//
// Garde : Vercel envoie `Authorization: Bearer <CRON_SECRET>`. Sans ce secret
// n'importe qui pourrait déclencher des emails aux clients.

import Stripe from 'stripe';
import { Resend } from 'resend';
import { list, put } from '@vercel/blob';
import { stepEmail } from '../lib/email.js';

const FROM_EMAIL = process.env.FROM_EMAIL || 'AdhanBox <commande@adhanbox.fr>';
const DELAI_JOURS = parseInt(process.env.AVIS_DELAI_JOURS || '10', 10);
const MAX_PAR_PASSAGE = 20;   // un rattrapage massif partirait sur plusieurs jours

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj, null, 2));
}

/** Prénom et config depuis Stripe, pour les traces d'expédition antérieures
 *  à l'ajout de ces champs. Une seule liste pour tout le passage. */
async function completerDepuisStripe(manquants) {
  if (!manquants.length || !process.env.STRIPE_SECRET_KEY) return;
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  const { data } = await stripe.checkout.sessions.list({ limit: 100 });
  const parRef = new Map();
  for (const s of data) {
    const pi = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
    parRef.set((pi || s.id).slice(-8).toUpperCase(), s);
  }
  for (const c of manquants) {
    const s = parRef.get(c.ref);
    if (!s) continue;
    const d = s.customer_details || {};
    c.firstName = c.firstName || (d.name || '').trim().split(/\s+/)[0] || '';
    c.config = c.config || s.metadata?.config || '';
    c.to = c.to || d.email || '';
  }
}

export default async function handler(req, res) {
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'Méthode non autorisée' });

  const url = new URL(req.url, 'http://localhost');
  const dry = url.searchParams.get('dry') === '1';
  const secret = process.env.CRON_SECRET || '';
  const auth = req.headers.authorization || '';
  if (!secret || auth !== `Bearer ${secret}`) {
    return sendJson(res, 403, { error: 'Accès refusé' });
  }
  if (!process.env.RESEND_API_KEY) {
    return sendJson(res, 500, { error: 'RESEND_API_KEY absente' });
  }

  // 1) Toutes les traces, regroupées par commande.
  const commandes = new Map();
  let cursor;
  do {
    const page = await list({ prefix: 'orders/', cursor, limit: 1000 });
    for (const b of page.blobs) {
      const m = b.pathname.match(/^orders\/([^/]+)\/(expedition|avis)\.json$/);
      if (!m) continue;
      const c = commandes.get(m[1]) || { ref: m[1] };
      c[m[2]] = b;
      commandes.set(m[1], c);
    }
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);

  // 2) Celles expédiées depuis assez longtemps, sans avis envoyé.
  const limite = Date.now() - DELAI_JOURS * 86400e3;
  const candidats = [];
  for (const c of commandes.values()) {
    if (!c.expedition || c.avis) continue;
    let trace;
    try { trace = await (await fetch(c.expedition.url)).json(); } catch { continue; }
    const sentAt = Date.parse(trace.sentAt || c.expedition.uploadedAt);
    if (!(sentAt <= limite)) continue;
    candidats.push({
      ref: c.ref, to: trace.to || '', firstName: trace.firstName || '',
      config: trace.config || '', expedieLe: new Date(sentAt).toISOString().slice(0, 10),
    });
  }
  candidats.sort((a, b) => a.expedieLe.localeCompare(b.expedieLe));
  const lot = candidats.slice(0, MAX_PAR_PASSAGE);
  await completerDepuisStripe(lot.filter((c) => !c.firstName || !c.to));

  if (dry) {
    return sendJson(res, 200, { dry: true, delaiJours: DELAI_JOURS, aEnvoyer: lot,
                                 enAttenteAuDela: candidats.length - lot.length });
  }

  // 3) Envoi, et trace aussitôt.
  const resend = new Resend(process.env.RESEND_API_KEY);
  const envoyes = [], echecs = [];
  for (const c of lot) {
    if (!c.to) { echecs.push({ ref: c.ref, erreur: 'pas d\'email' }); continue; }
    const { subject, html } = stepEmail('avis', { firstName: c.firstName, ref: c.ref, config: c.config });
    const sent = await resend.emails.send({ from: FROM_EMAIL, to: c.to, subject, html });
    if (sent.error) { echecs.push({ ref: c.ref, erreur: sent.error.message }); continue; }
    try {
      await put(`orders/${c.ref}/avis.json`, JSON.stringify({
        step: 'avis', ref: c.ref, to: c.to, firstName: c.firstName, config: c.config,
        sentAt: new Date().toISOString(), par: 'cron',
      }), { access: 'public', contentType: 'application/json', addRandomSuffix: false });
    } catch {
      // L'email est parti : ne pas transformer un échec de traçage en erreur.
    }
    envoyes.push({ ref: c.ref, to: c.to });
  }
  console.log(`[cron-avis] ${envoyes.length} envoyé(s), ${echecs.length} échec(s)`);
  return sendJson(res, 200, { envoyes, echecs, enAttenteAuDela: candidats.length - lot.length });
}
