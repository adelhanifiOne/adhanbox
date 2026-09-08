// GET /api/cron-avis          — appelé par Vercel chaque jour (voir vercel.json)
// GET /api/cron-avis?dry=1    — montre ce qui partirait, sans rien envoyer
//
// Dix jours après l'email « Expédiée », envoie l'email « Avis et photo ».
// Le colis met 2 à 4 jours : le client a donc vécu une semaine avec le boîtier.
//
// Tout repose sur les traces que laisse api/order-step.js dans Blob :
//   orders/<ref>/expedition.json  -> date d'envoi (et transporteur)
//   orders/<ref>/avis.json        -> déjà envoyé (à la main ou par ici)
// Idempotent par construction : on n'envoie que s'il n'y a pas de avis.json,
// et on en écrit un aussitôt l'email parti. Un bouton « 4 · Avis » cliqué la
// veille laisse la même trace : la tâche ne renverra rien.
//
// Les traces ne portent aucune donnée personnelle (le store est public, le
// chemin prévisible). Prénom, configuration et email sont retrouvés chez
// Stripe à chaque passage, pour le lot du jour seulement. Les traces écrites
// avant cette règle contenaient email, prénom, config et numéro de suivi :
// chaque passage — essai à blanc compris — les réécrit épurées, puis n'a
// plus rien à faire.
//
// GET /api/cron-avis?liste=1  — inventaire des mails d'étape envoyés, par
// commande (lecture seule, même garde). L'email vient de Stripe.
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
const MAX_SESSIONS_STRIPE = 1000;
const STEPS = ['preparation', 'montage', 'expedition', 'avis'];
const CHAMPS_PERSONNELS = ['to', 'firstName', 'config', 'tracking'];
const BLOB_OPTS = { access: 'public', contentType: 'application/json', addRandomSuffix: false };

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(obj, null, 2));
}

/** Ce qu'une trace a le droit de contenir. */
function epurer(trace) {
  const t = { step: trace.step, ref: trace.ref, sentAt: trace.sentAt };
  if (trace.carrier) t.carrier = trace.carrier;
  if (trace.par) t.par = trace.par;
  return t;
}

/** Lit chaque trace ; celles qui portent encore des données personnelles
 *  sont réécrites au même chemin, épurées. Renvoie les traces lues. */
async function nettoyerTraces(blobs) {
  const traces = new Map();
  const bilan = { relues: 0, reecrites: 0, echecs: [] };
  for (const b of blobs) {
    let trace;
    try { trace = await (await fetch(b.url)).json(); } catch { continue; }
    bilan.relues++;
    if (CHAMPS_PERSONNELS.some((k) => k in trace)) {
      try {
        await put(b.pathname, JSON.stringify(epurer(trace)), { ...BLOB_OPTS, allowOverwrite: true });
        bilan.reecrites++;
      } catch (e) {
        bilan.echecs.push({ pathname: b.pathname, erreur: e.message });
      }
    }
    traces.set(b.pathname, trace);
  }
  return { traces, bilan };
}

/** Email, prénom et configuration depuis Stripe, pour le lot du jour.
 *  On remonte les sessions jusqu'à avoir trouvé toutes les références. */
async function completerDepuisStripe(lot) {
  const restants = new Map(lot.map((c) => [c.ref, c]));
  if (!restants.size) return;
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  let vues = 0;
  for await (const s of stripe.checkout.sessions.list({ limit: 100 })) {
    if (!restants.size || ++vues > MAX_SESSIONS_STRIPE) break;
    const pi = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
    const c = restants.get((pi || s.id).slice(-8).toUpperCase());
    if (!c) continue;
    const d = s.customer_details || {};
    c.to = d.email || '';
    c.firstName = (d.name || '').trim().split(/\s+/)[0] || '';
    c.config = s.metadata?.config || '';
    restants.delete(c.ref);
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
  if (!process.env.STRIPE_SECRET_KEY) {
    return sendJson(res, 500, { error: 'STRIPE_SECRET_KEY absente' });
  }

  // 1) Toutes les traces. On les relit toutes pour épurer celles qui
  //    porteraient encore des données personnelles.
  const blobs = [];
  let cursor;
  do {
    const page = await list({ prefix: 'orders/', cursor, limit: 1000 });
    blobs.push(...page.blobs.filter((b) => /^orders\/[^/]+\/[a-z]+\.json$/.test(b.pathname)));
    cursor = page.hasMore ? page.cursor : undefined;
  } while (cursor);
  const { traces, bilan: nettoyage } = await nettoyerTraces(blobs);

  // 2) Regroupées par commande.
  const commandes = new Map();
  for (const b of blobs) {
    const m = b.pathname.match(/^orders\/([^/]+)\/(preparation|montage|expedition|avis)\.json$/);
    if (!m) continue;
    const c = commandes.get(m[1]) || { ref: m[1] };
    c[m[2]] = b;
    commandes.set(m[1], c);
  }
  const dateDe = (b) => {
    const t = traces.get(b.pathname);
    return t ? new Date(t.sentAt || b.uploadedAt).toISOString().slice(0, 10) : '?';
  };

  // ?liste=1 : inventaire de tous les mails d'étape envoyés, par commande.
  // Sert à savoir QUI a reçu QUOI et quand, par exemple pour retrouver les
  // clients invités à répondre à une adresse morte. Les traces ne portant
  // pas l'email, on le demande à Stripe pour toutes les commandes.
  if (url.searchParams.get('liste') === '1') {
    const out = [...commandes.values()].map((c) => {
      const etapes = {};
      for (const step of STEPS) if (c[step]) etapes[step] = dateDe(c[step]);
      return { ref: c.ref, to: '', etapes };
    });
    await completerDepuisStripe(out);
    out.sort((a, b) => Object.values(a.etapes)[0].localeCompare(Object.values(b.etapes)[0]));
    return sendJson(res, 200, { commandes: out.map(({ ref, to, etapes }) => ({ ref, to, etapes })),
                                 nettoyage });
  }

  // 3) Celles expédiées depuis assez longtemps, sans avis envoyé.
  const limite = Date.now() - DELAI_JOURS * 86400e3;
  const candidats = [];
  for (const c of commandes.values()) {
    if (!c.expedition || c.avis) continue;
    const trace = traces.get(c.expedition.pathname);
    if (!trace) continue;
    const sentAt = Date.parse(trace.sentAt || c.expedition.uploadedAt);
    if (!(sentAt <= limite)) continue;
    candidats.push({ ref: c.ref, expedieLe: new Date(sentAt).toISOString().slice(0, 10),
                     to: '', firstName: '', config: '' });
  }
  candidats.sort((a, b) => a.expedieLe.localeCompare(b.expedieLe));
  const lot = candidats.slice(0, MAX_PAR_PASSAGE);
  await completerDepuisStripe(lot);

  if (dry) {
    return sendJson(res, 200, { dry: true, delaiJours: DELAI_JOURS, aEnvoyer: lot,
                                 enAttenteAuDela: candidats.length - lot.length, nettoyage });
  }

  // 4) Envoi, et trace aussitôt.
  const resend = new Resend(process.env.RESEND_API_KEY);
  const envoyes = [], echecs = [];
  for (const c of lot) {
    if (!c.to) { echecs.push({ ref: c.ref, erreur: 'commande ou email introuvable chez Stripe' }); continue; }
    const { subject, html } = stepEmail('avis', { firstName: c.firstName, ref: c.ref, config: c.config });
    const sent = await resend.emails.send({ from: FROM_EMAIL, to: c.to, subject, html,
                                            replyTo: 'contact@adhanbox.fr' });  // voir order-step.js
    if (sent.error) { echecs.push({ ref: c.ref, erreur: sent.error.message }); continue; }
    try {
      await put(`orders/${c.ref}/avis.json`, JSON.stringify({
        step: 'avis', ref: c.ref, sentAt: new Date().toISOString(), par: 'cron',
      }), BLOB_OPTS);
    } catch {
      // L'email est parti : ne pas transformer un échec de traçage en erreur.
    }
    envoyes.push({ ref: c.ref, to: c.to });
  }
  console.log(`[cron-avis] ${envoyes.length} envoyé(s), ${echecs.length} échec(s), `
    + `${nettoyage.reecrites} trace(s) épurée(s)`);
  return sendJson(res, 200, { envoyes, echecs, enAttenteAuDela: candidats.length - lot.length, nettoyage });
}
