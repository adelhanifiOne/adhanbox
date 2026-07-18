// POST /api/review  { note, texte, prenom, ville, email?, hp? }
// Dépôt d'un avis client (ou testeur) depuis adhanbox.fr/avis.html.
//
// L'avis est stocké EN ATTENTE dans Vercel Blob (reviews/pending/{id}.json),
// puis une notification t'est envoyée par email (Resend) avec deux liens :
// Approuver / Rejeter. Aucun email ni IP n'est stocké — la vérification
// « acheteur » et la notif se font ici, à la soumission uniquement (RGPD).
//
// Signature Node (req, res), helpers désactivés (NODEJS_HELPERS=0) — lecture
// du flux et réponses en Node pur, comme checkout.js / stripe-webhook.js.
import { put } from '@vercel/blob';
import { Resend } from 'resend';
import Stripe from 'stripe';
import { randomUUID } from 'node:crypto';

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899',
];

const NOTIF_EMAIL = process.env.NOTIF_EMAIL || 'contact@adhanbox.fr';
const FROM_EMAIL = process.env.FROM_EMAIL || 'AdhanBox <commande@adhanbox.fr>';
// Base publique de ce backend, pour construire les liens de modération.
const BACKEND = process.env.BACKEND_URL || 'https://adhanbox-commande.vercel.app';
const ADMIN_TOKEN = process.env.REVIEW_ADMIN_TOKEN || '';

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

const clean = (s, max) => String(s == null ? '' : s).replace(/\s+/g, ' ').trim().slice(0, max);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Un client Stripe existe pour cet email ⇒ il a payé (customer_creation:'always'
// ne crée le client qu'au paiement). Sert uniquement au badge « acheteur vérifié ».
async function isVerifiedBuyer(email) {
  if (!email || !process.env.STRIPE_SECRET_KEY) return false;
  try {
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
    const r = await stripe.customers.list({ email: email.trim().toLowerCase(), limit: 1 });
    return r.data.length > 0;
  } catch (err) {
    console.error('vérif acheteur échouée:', err && err.message);
    return false;
  }
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'POST') return sendJson(res, 405, { error: 'Méthode non autorisée' });

  const body = await readJson(req);

  // Piège à bots : champ caché « hp » que seuls les robots remplissent.
  if (body.hp) return sendJson(res, 200, { ok: true }); // faux succès, rien stocké

  const note = parseInt(body.note, 10);
  const texte = clean(body.texte, 1000);
  const prenom = clean(body.prenom, 40);
  const ville = clean(body.ville, 60);
  const email = clean(body.email, 120);

  if (!(note >= 1 && note <= 5)) return sendJson(res, 400, { error: 'Note invalide (1 à 5).' });
  if (texte.length < 10) return sendJson(res, 400, { error: 'Votre avis est un peu court (10 caractères minimum).' });
  if (!prenom) return sendJson(res, 400, { error: 'Merci d\'indiquer votre prénom.' });
  // Anti-spam simple : pas de liens dans un avis.
  if (/https?:\/\/|www\.|\[url/i.test(texte)) {
    return sendJson(res, 400, { error: 'Merci de retirer les liens de votre avis.' });
  }

  const verifie = await isVerifiedBuyer(email);

  const id = randomUUID();
  const review = {
    id,
    note,
    texte,
    prenom,
    ville,
    verifie,
    date: new Date().toISOString(),
  };

  try {
    await put(`reviews/pending/${id}.json`, JSON.stringify(review), {
      access: 'public',           // ne contient AUCUNE donnée personnelle
      addRandomSuffix: false,
      contentType: 'application/json',
    });
  } catch (err) {
    console.error('stockage avis échoué:', err && err.message);
    return sendJson(res, 500, { error: 'Erreur serveur — réessayez plus tard.' });
  }

  // Notification vendeur avec liens de modération (non bloquant).
  if (process.env.RESEND_API_KEY && ADMIN_TOKEN) {
    const link = (action) =>
      `${BACKEND}/api/review-moderate?id=${id}&action=${action}&token=${encodeURIComponent(ADMIN_TOKEN)}`;
    const stars = '★'.repeat(note) + '☆'.repeat(5 - note);
    try {
      const resend = new Resend(process.env.RESEND_API_KEY);
      await resend.emails.send({
        from: FROM_EMAIL,
        to: NOTIF_EMAIL,
        subject: `📝 Nouvel avis (${note}/5) — ${prenom}${ville ? ' · ' + ville : ''}`,
        html: `
<div style="font-family:Arial,sans-serif;font-size:15px;color:#232323;line-height:1.7;max-width:560px;">
  <h2 style="color:#0C5B45;">📝 Nouvel avis en attente de modération</h2>
  <p style="font-size:20px;color:#C9A227;margin:0;">${stars} <span style="color:#666;font-size:14px;">(${note}/5)</span></p>
  <p style="background:#F6F4EF;border-radius:10px;padding:16px 18px;font-style:italic;">« ${esc(texte)} »</p>
  <p><b>${esc(prenom)}</b>${ville ? ' · ' + esc(ville) : ''}${verifie ? ' · <span style="color:#0C5B45;">✔ acheteur vérifié</span>' : ' · <span style="color:#999;">non vérifié</span>'}</p>
  <p style="margin-top:24px;">
    <a href="${link('approve')}" style="background:#0C5B45;color:#fff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:700;margin-right:10px;">✔ Approuver (publier)</a>
    <a href="${link('reject')}" style="background:#eee;color:#333;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:700;">✕ Rejeter</a>
  </p>
</div>`,
        text: [
          `Nouvel avis en attente (${note}/5)`,
          `« ${texte} »`,
          `${prenom}${ville ? ' · ' + ville : ''}${verifie ? ' · acheteur vérifié' : ''}`,
          '',
          `Approuver : ${link('approve')}`,
          `Rejeter   : ${link('reject')}`,
        ].join('\n'),
      });
    } catch (err) {
      console.error('notif avis échouée:', err && err.message);
    }
  }

  return sendJson(res, 200, { ok: true });
}
