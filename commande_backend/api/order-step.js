// GET /api/order-step?session=cs_…&step=preparation|montage|expedition&token=…
//     GET /api/order-step?ref=0P4SHMBE&step=…&token=…
//
// Envoie au client l'email correspondant à l'étape de sa commande. Pensé pour
// être cliqué depuis l'email de notification reçu à chaque commande : un lien
// par étape, aucun formulaire à remplir sauf le numéro de suivi.
//
// Même modèle que review-moderate.js : jeton partagé dans l'URL, réponse en
// page HTML (le lien est cliqué depuis un email, pas appelé en AJAX).
//
// Idempotent : chaque envoi laisse une trace dans Blob (orders/<ref>/<step>),
// un deuxième clic ne renvoie pas l'email. Indispensable quand on clique
// depuis un téléphone et qu'on ne sait plus si ça a marché.

import Stripe from 'stripe';
import { Resend } from 'resend';
import { list, put } from '@vercel/blob';
import { stepEmail, esc } from '../lib/email.js';

const FROM_EMAIL = process.env.FROM_EMAIL || 'AdhanBox <commande@adhanbox.fr>';
const STEPS = ['preparation', 'montage', 'expedition'];
const LIBELLE = {
  preparation: 'En préparation',
  montage: 'Assemblée et testée',
  expedition: 'Expédiée',
};

function page(res, status, title, message, tone, extra = '') {
  const color = tone === 'ok' ? '#0C5B45' : tone === 'warn' ? '#B4791A' : '#B23A3A';
  res.statusCode = status;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title></head>
<body style="font-family:-apple-system,Segoe UI,Arial,sans-serif;background:#F6F4EF;margin:0;padding:48px 16px;text-align:center;color:#232323;">
  <div style="max-width:460px;margin:0 auto;background:#fff;border-radius:16px;padding:36px 28px;box-shadow:0 8px 30px rgba(0,0,0,.06);">
    <div style="font-size:44px;line-height:1;">${tone === 'ok' ? '✅' : tone === 'warn' ? '⚠️' : '🚫'}</div>
    <h1 style="color:${color};font-size:22px;margin:16px 0 8px;">${esc(title)}</h1>
    <p style="color:#555;font-size:15px;line-height:1.6;margin:0;">${message}</p>
    ${extra}
  </div>
</body></html>`);
}

/** Formulaire minimal pour saisir le numéro de suivi avant d'envoyer. */
function trackingForm(res, params, livraison) {
  const q = (k) => esc(params[k] || '');
  const relais = livraison && livraison.relais;
  const mr = relais ? ' selected' : '';
  const bloc = relais
    ? `<div style="background:#FBF3E3;border-left:3px solid #B4791A;border-radius:0 8px 8px 0;padding:12px 14px;margin:0 0 20px;font-size:14px;line-height:1.5;">
        <b>Point relais</b> — ${esc(relais.name)}<br>${esc(relais.address || '')}<br>
        code <code style="font-size:15px;background:#fff;padding:1px 6px;border-radius:4px;">${esc(relais.code || '')}</code>
        <span style="color:#666;">· à saisir dans Boxtal</span></div>`
    : '';
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Numéro de suivi</title></head>
<body style="font-family:-apple-system,Segoe UI,Arial,sans-serif;background:#F6F4EF;margin:0;padding:48px 16px;color:#232323;">
  <form method="GET" action="/api/order-step" style="max-width:460px;margin:0 auto;background:#fff;border-radius:16px;padding:32px 28px;box-shadow:0 8px 30px rgba(0,0,0,.06);">
    <h1 style="color:#0C5B45;font-size:20px;margin:0 0 6px;">Expédition — commande ${q('ref')}</h1>
    <p style="color:#666;font-size:14px;line-height:1.6;margin:0 0 20px;">
      Saisissez le numéro de suivi. Il sera envoyé au client avec un lien de suivi.
    </p>
    <input type="hidden" name="session" value="${q('session')}">
    <input type="hidden" name="ref" value="${q('ref')}">
    <input type="hidden" name="step" value="expedition">
    <input type="hidden" name="token" value="${q('token')}">
    ${bloc}
    <label style="display:block;font-size:13px;color:#555;margin-bottom:6px;">Numéro de suivi</label>
    <input name="tracking" required autofocus autocapitalize="characters" autocomplete="off"
           style="width:100%;box-sizing:border-box;font-size:16px;padding:12px 14px;border:1px solid #D8D2C4;border-radius:10px;margin-bottom:16px;">
    <label style="display:block;font-size:13px;color:#555;margin-bottom:6px;">Transporteur</label>
    <select name="carrier"
            style="width:100%;box-sizing:border-box;font-size:16px;padding:12px 14px;border:1px solid #D8D2C4;border-radius:10px;margin-bottom:22px;background:#fff;">
      <option value="Colissimo"${mr ? '' : ' selected'}>Colissimo (domicile)</option>
      <option value="Mondial Relay"${mr}>Mondial Relay (point relais)</option>
    </select>
    <button type="submit"
            style="width:100%;background:#0C5B45;color:#fff;border:none;font-size:16px;font-weight:600;padding:14px;border-radius:999px;cursor:pointer;">
      Envoyer au client
    </button>
  </form>
</body></html>`);
}

/** Retrouve la session Stripe : par id direct, ou par référence courte. */
async function findSession(stripe, { session, ref }) {
  if (session) {
    return stripe.checkout.sessions.retrieve(session, { expand: ['payment_intent'] });
  }
  // Référence courte (8 derniers caractères du PaymentIntent, ou de la session).
  // Volume attendu : quelques dizaines de commandes, une page suffit.
  const wanted = String(ref).toUpperCase();
  const { data } = await stripe.checkout.sessions.list({ limit: 100 });
  return data.find((s) => {
    const pi = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
    return (pi || s.id).slice(-8).toUpperCase() === wanted;
  }) || null;
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.statusCode = 405; return res.end('Méthode non autorisée'); }

  const url = new URL(req.url, 'http://localhost');
  const p = Object.fromEntries(url.searchParams.entries());
  const { session, ref, step, tracking, carrier, token } = p;

  const ADMIN_TOKEN = process.env.ORDER_ADMIN_TOKEN || process.env.REVIEW_ADMIN_TOKEN || '';
  if (!ADMIN_TOKEN || token !== ADMIN_TOKEN) {
    return page(res, 403, 'Accès refusé', 'Lien invalide ou expiré.', 'err');
  }
  if (!STEPS.includes(step)) {
    return page(res, 400, 'Requête invalide', `Étape inconnue. Attendu&nbsp;: ${STEPS.join(', ')}.`, 'err');
  }
  if (!session && !ref) {
    return page(res, 400, 'Requête invalide', 'Il manque la commande (session ou ref).', 'err');
  }
  if (!process.env.STRIPE_SECRET_KEY || !process.env.RESEND_API_KEY) {
    return page(res, 500, 'Configuration incomplète', 'Clé Stripe ou Resend absente côté serveur.', 'err');
  }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  const s = await findSession(stripe, { session, ref });
  if (!s) {
    return page(res, 404, 'Commande introuvable', `Aucune commande ne correspond à «&nbsp;${esc(ref || session)}&nbsp;».`, 'err');
  }
  // Mode de livraison choisi à la commande (metadata posées par checkout.js).
  const m = s.metadata || {};
  const livraison = {
    relais: m.livraison === 'Point relais' && m.relais_code
      ? { code: m.relais_code, network: m.relais_reseau || '', name: m.relais_nom || '',
          address: m.relais_adresse || '' }
      : null,
  };

  // Expédition sans numéro de suivi : on demande d'abord — en montrant le
  // point relais et son code, et en présélectionnant le bon transporteur.
  if (step === 'expedition' && !tracking) return trackingForm(res, p, livraison);

  const d = s.customer_details || {};
  const to = d.email;
  if (!to) {
    return page(res, 422, 'Pas d\'adresse email', 'Cette commande ne porte pas d\'adresse email client.', 'err');
  }
  const pi = typeof s.payment_intent === 'string' ? s.payment_intent : s.payment_intent?.id;
  const shortRef = (pi || s.id).slice(-8).toUpperCase();
  const firstName = (d.name || '').trim().split(/\s+/)[0] || '';
  const config = s.metadata?.config || '';

  // Idempotence : a-t-on déjà envoyé cette étape pour cette commande ?
  const marker = `orders/${shortRef}/${step}.json`;
  try {
    const { blobs } = await list({ prefix: `orders/${shortRef}/` });
    if (blobs.some((b) => b.pathname === marker)) {
      return page(res, 200, 'Déjà envoyé',
        `L'email «&nbsp;${esc(LIBELLE[step])}&nbsp;» a déjà été envoyé pour la commande <b>${esc(shortRef)}</b>.`,
        'warn');
    }
  } catch {
    // Blob indisponible : on continue plutôt que de bloquer un envoi légitime.
  }

  const { subject, html } = stepEmail(step, { firstName, ref: shortRef, config, tracking, carrier,
                                             relais: livraison.relais });
  const resend = new Resend(process.env.RESEND_API_KEY);
  const sent = await resend.emails.send({ from: FROM_EMAIL, to, subject, html });
  if (sent.error) {
    return page(res, 502, 'Envoi échoué', esc(sent.error.message || 'Resend a refusé l\'envoi.'), 'err');
  }

  try {
    await put(marker, JSON.stringify({
      step, ref: shortRef, to, tracking: tracking || null,
      carrier: carrier || null, sentAt: new Date().toISOString(),
    }), { access: 'public', contentType: 'application/json', addRandomSuffix: false });
  } catch {
    // L'email est parti : ne pas transformer un échec de traçage en erreur.
  }

  return page(res, 200, 'Email envoyé',
    `«&nbsp;${esc(LIBELLE[step])}&nbsp;» envoyé à <b>${esc(to)}</b> pour la commande <b>${esc(shortRef)}</b>.`,
    'ok',
    `<p style="margin-top:22px;color:#777;font-size:13px;">Vous pouvez fermer cette page.</p>`);
}
