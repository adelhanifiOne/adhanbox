// Webhook Stripe — à la fin d'un paiement (checkout.session.completed ou
// checkout.session.async_payment_succeeded pour Klarna & co) :
//   1. email de confirmation personnalisé au client (merci + config + récap
//      + adresse + date d'expédition) ;
//   2. notification « nouvelle commande » à contact@adhanbox.fr.
// Emails envoyés via Resend. Si RESEND_API_KEY est absente, le webhook
// répond 200 sans rien envoyer (le reçu Stripe standard part quand même).
//
// Signature Node (req, res), helpers désactivés (NODEJS_HELPERS=0) : on lit
// le corps BRUT du flux — indispensable pour vérifier la signature Stripe.
import Stripe from 'stripe';
import { Resend } from 'resend';

const SITE = process.env.SITE_URL || 'https://adhanbox.fr';
const SHIP_DATE = process.env.SHIP_DATE || 'sous 1 à 2 semaines';
const NOTIF_EMAIL = process.env.NOTIF_EMAIL || 'contact@adhanbox.fr';
const BACKEND = process.env.BACKEND_URL || 'https://adhanbox-commande.vercel.app';
// Tant que le domaine n'est pas vérifié chez Resend, utiliser
// 'AdhanBox <onboarding@resend.dev>' (n'envoie qu'à ta propre adresse).
const FROM_EMAIL = process.env.FROM_EMAIL || 'AdhanBox <commande@adhanbox.fr>';

const euros = (cents) =>
  (cents / 100).toLocaleString('fr-FR', { style: 'currency', currency: 'EUR' });

async function readRawBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks);
}

function addressLines(name, a) {
  if (!a) return [];
  return [name, a.line1, a.line2, `${a.postal_code || ''} ${a.city || ''}`.trim(), a.country]
    .filter(Boolean);
}

// Version texte brut de l'email client — un multipart HTML+texte passe
// nettement mieux les filtres anti-spam qu'un HTML seul.
function clientEmailText({ firstName, ref, config, amount, shipToLines }) {
  return [
    `As-salāmu ʿalaykum${firstName ? ' ' + firstName : ''},`,
    '',
    'Merci du fond du cœur pour votre précommande AdhanBox.',
    'Votre boîtier sera fabriqué à la main, à la commande, exactement dans la configuration que vous avez choisie.',
    '',
    `Votre configuration : ${config}`,
    `Commande : N° ${ref}`,
    `Total payé : ${amount} (livraison offerte)`,
    '',
    ...(shipToLines.length ? ['Adresse de livraison :', ...shipToLines, ''] : []),
    `Expédition prévue : ${SHIP_DATE}. Vous serez tenu informé à chaque étape : confirmation, assemblage, envoi avec numéro de suivi.`,
    '',
    'Garantie 2 ans · Retour 14 jours · Paiement sécurisé Stripe',
    'Une question ? Répondez à cet email ou écrivez-nous : contact@adhanbox.fr',
    '',
    'AdhanBox — Fait main en France',
    SITE,
  ].join('\n');
}

// ── Email client : merci + détail complet de la commande ──
function clientEmailHtml({ firstName, ref, config, amount, shipTo }) {
  const row = (label, value) => `
    <tr>
      <td style="padding:6px 0;color:#6B6B6B;font-size:14px;">${label}</td>
      <td style="padding:6px 0;color:#232323;font-size:14px;font-weight:600;text-align:right;">${value}</td>
    </tr>`;
  return `
<div style="background:#F6F4EF;padding:32px 16px;font-family:'Helvetica Neue',Arial,sans-serif;">
  <table role="presentation" width="100%" style="max-width:560px;margin:0 auto;border-collapse:collapse;">
    <tr><td style="background:#0C5B45;border-radius:14px 14px 0 0;padding:28px 32px;text-align:center;">
      <div style="font-family:Georgia,'Times New Roman',serif;font-size:26px;color:#E9C46A;font-weight:700;letter-spacing:.5px;">AdhanBox</div>
      <div style="color:#CFE5DD;font-size:12px;margin-top:4px;letter-spacing:1px;">FAIT MAIN EN FRANCE</div>
    </td></tr>
    <tr><td style="background:#FFFFFF;padding:32px;">
      <div style="font-size:20px;color:#0C5B45;font-family:Georgia,serif;font-weight:700;">As-salāmu ʿalaykum${firstName ? ' ' + firstName : ''} 🌙</div>
      <p style="color:#444;font-size:15px;line-height:1.6;margin:14px 0 0;">
        Merci du fond du cœur pour votre précommande. Votre AdhanBox sera
        <b>fabriquée à la main, à la commande</b>, exactement dans la
        configuration que vous avez choisie&nbsp;:
      </p>

      <div style="background:#F6F4EF;border-radius:10px;padding:18px 20px;margin:20px 0;">
        <div style="font-size:12px;letter-spacing:1px;color:#0C5B45;font-weight:700;margin-bottom:8px;">VOTRE CONFIGURATION</div>
        <div style="font-size:16px;color:#232323;font-weight:600;">${config}</div>
      </div>

      <table role="presentation" width="100%" style="border-collapse:collapse;border-top:1px solid #EEE;">
        ${row('Commande', 'N° ' + ref)}
        ${row('AdhanBox — Précommande', amount)}
        ${row('Livraison', 'Offerte')}
        <tr>
          <td style="padding:10px 0;color:#0C5B45;font-size:15px;font-weight:700;border-top:1px solid #EEE;">Total payé</td>
          <td style="padding:10px 0;color:#0C5B45;font-size:15px;font-weight:700;text-align:right;border-top:1px solid #EEE;">${amount}</td>
        </tr>
      </table>

      ${shipTo ? `
      <div style="margin-top:18px;">
        <div style="font-size:12px;letter-spacing:1px;color:#0C5B45;font-weight:700;margin-bottom:6px;">ADRESSE DE LIVRAISON</div>
        <div style="font-size:14px;color:#444;line-height:1.5;">${shipTo}</div>
      </div>` : ''}

      <div style="background:#FBF7EC;border-left:3px solid #C9A227;border-radius:0 8px 8px 0;padding:14px 16px;margin-top:22px;">
        <div style="font-size:14px;color:#5B4A17;line-height:1.6;">
          📦 <b>Expédition prévue : ${SHIP_DATE}.</b><br>
          Vous serez tenu informé à chaque étape&nbsp;: confirmation, assemblage
          de votre boîtier, puis envoi avec numéro de suivi.
        </div>
      </div>

      <p style="color:#777;font-size:13px;line-height:1.6;margin:22px 0 0;">
        Garantie 2 ans · Retour 14 jours · Paiement sécurisé Stripe<br>
        Une question&nbsp;? Répondez simplement à cet email ou écrivez-nous à
        <a href="mailto:contact@adhanbox.fr" style="color:#0C5B45;">contact@adhanbox.fr</a>.
      </p>
    </td></tr>
    <tr><td style="background:#0C5B45;border-radius:0 0 14px 14px;padding:20px 32px;text-align:center;">
      <div style="font-family:Georgia,serif;color:#E9C46A;font-size:15px;">بِسْمِ ٱللَّٰهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ</div>
      <div style="color:#CFE5DD;font-size:12px;margin-top:6px;">© AdhanBox · Adel Hanifi · <a href="${SITE}" style="color:#CFE5DD;">adhanbox.fr</a></div>
    </td></tr>
  </table>
</div>`;
}

// ── Email vendeur : notification nouvelle commande ──
function sellerEmailHtml({ ref, config, amount, name, email, phone, shipTo, piId, sessionId }) {
  const li = (k, v) => v ? `<li><b>${k} :</b> ${v}</li>` : '';
  return `
<div style="font-family:Arial,sans-serif;font-size:15px;color:#232323;line-height:1.7;">
  <h2 style="color:#0C5B45;">🎉 Nouvelle précommande AdhanBox</h2>
  <ul style="padding-left:18px;">
    ${li('Commande', 'N° ' + ref)}
    ${li('Configuration', '<span style="color:#0C5B45;font-weight:700;">' + config + '</span>')}
    ${li('Montant', amount)}
    ${li('Client', name)}
    ${li('Email', email)}
    ${li('Téléphone', phone)}
  </ul>
  ${shipTo ? `<p><b>Livraison :</b><br>${shipTo}</p>` : ''}
  <p><a href="https://dashboard.stripe.com/payments/${piId}">Voir le paiement dans Stripe →</a></p>
  ${stepButtons(sessionId)}
</div>`;
}

// ── Boutons d'étape : un clic = un email au client (voir api/order-step.js) ──
// N'apparaissent que si ORDER_ADMIN_TOKEN (ou REVIEW_ADMIN_TOKEN) est defini :
// sans jeton les liens seraient inutilisables.
function stepButtons(sessionId) {
  const token = process.env.ORDER_ADMIN_TOKEN || process.env.REVIEW_ADMIN_TOKEN || '';
  if (!token || !sessionId) return '';
  const btn = (step, label, bg) =>
    `<a href="${BACKEND}/api/order-step?session=${encodeURIComponent(sessionId)}` +
    `&step=${step}&token=${encodeURIComponent(token)}"` +
    ` style="display:inline-block;background:${bg};color:#fff;text-decoration:none;font-weight:600;` +
    `font-size:14px;padding:10px 18px;border-radius:999px;margin:4px 6px 4px 0;">${label}</a>`;
  return `
  <div style="margin-top:22px;padding-top:18px;border-top:1px solid #E6DECF;">
    <p style="margin:0 0 10px;color:#6B6B6B;font-size:13px;">Prévenir le client :</p>
    ${btn('preparation', '1 · En préparation', '#0C5B45')}
    ${btn('montage', '2 · Assemblée', '#0C5B45')}
    ${btn('expedition', '3 · Expédiée', '#B4791A')}
    <p style="margin:10px 0 0;color:#9A9A9A;font-size:12px;">
      Un seul envoi par étape. « Expédiée » demandera le numéro de suivi.
    </p>
  </div>`;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.statusCode = 405; return res.end('Method Not Allowed'); }

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
  const rawBody = await readRawBody(req);
  const signature = req.headers['stripe-signature'];

  let event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('webhook signature invalide:', err && err.message);
    res.statusCode = 400;
    return res.end('Signature invalide');
  }

  const done = (obj) => {
    res.statusCode = 200;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(obj));
  };

  const isPaid =
    (event.type === 'checkout.session.completed' && event.data.object.payment_status === 'paid') ||
    event.type === 'checkout.session.async_payment_succeeded';
  if (!isPaid) return done({ received: true });

  const session = event.data.object;
  const details = session.customer_details || {};
  const shipping = session.shipping_details || session.collected_information?.shipping_details;
  const piId = typeof session.payment_intent === 'string' ? session.payment_intent : '';
  const ref = (piId || session.id).slice(-8).toUpperCase();
  const config = session.metadata?.config || 'Configuration standard';
  const amount = euros(session.amount_total ?? 0);
  const firstName = (details.name || '').trim().split(/\s+/)[0] || '';
  const shipToLines = shipping ? addressLines(shipping.name || details.name, shipping.address) : [];
  const shipTo = shipToLines.join('<br>');

  if (!process.env.RESEND_API_KEY) {
    console.log('RESEND_API_KEY absente — emails non envoyés. Commande:', ref, config);
    return done({ received: true, emails: 'skipped' });
  }

  const resend = new Resend(process.env.RESEND_API_KEY);

  // 1) Email client
  try {
    if (details.email) {
      await resend.emails.send({
        from: FROM_EMAIL,
        to: details.email,
        replyTo: 'contact@adhanbox.fr',
        subject: `Votre précommande AdhanBox est confirmée 🌙 (n° ${ref})`,
        html: clientEmailHtml({ firstName, ref, config, amount, shipTo }),
        text: clientEmailText({ firstName, ref, config, amount, shipToLines }),
      });
    }
  } catch (err) {
    console.error('email client échoué:', err && err.message);
  }

  // 2) Notification vendeur
  try {
    await resend.emails.send({
      from: FROM_EMAIL,
      to: NOTIF_EMAIL,
      subject: `🎉 Nouvelle précommande — ${config} — ${amount}`,
      html: sellerEmailHtml({
        ref, config, amount,
        name: details.name, email: details.email, phone: details.phone,
        shipTo, piId, sessionId: session.id,
      }),
      text: [
        `Nouvelle précommande AdhanBox`,
        `Commande : N° ${ref}`,
        `Configuration : ${config}`,
        `Montant : ${amount}`,
        `Client : ${details.name || '-'} · ${details.email || '-'} · ${details.phone || '-'}`,
        ...(shipToLines.length ? ['Livraison :', ...shipToLines] : []),
        `https://dashboard.stripe.com/payments/${piId}`,
      ].join('\n'),
    });
  } catch (err) {
    console.error('email vendeur échoué:', err && err.message);
  }

  return done({ received: true });
}
