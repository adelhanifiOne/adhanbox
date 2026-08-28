// Gabarit d'email partagé + corps des 3 emails d'étape.
//
// Placé hors de api/ : Vercel ne route que api/, donc ce fichier n'est pas
// exposé comme fonction.
//
// Note : api/stripe-webhook.js garde son propre gabarit, écrit avant celui-ci.
// Il fonctionne et sert deux commandes en cours — on ne le refactore pas
// aujourd'hui pour ne rien casser sur le chemin critique du paiement.

const SITE = process.env.SITE_URL || 'https://adhanbox.fr';

export const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/** Coquille visuelle commune : bandeau vert, carte blanche, pied de page. */
export function shell(bodyHtml) {
  return `
<div style="background:#F6F4EF;padding:32px 16px;font-family:'Helvetica Neue',Arial,sans-serif;">
  <table role="presentation" width="100%" style="max-width:560px;margin:0 auto;border-collapse:collapse;">
    <tr><td style="background:#0C5B45;border-radius:14px 14px 0 0;padding:28px 32px;text-align:center;">
      <div style="font-family:Georgia,'Times New Roman',serif;font-size:26px;color:#E9C46A;font-weight:700;letter-spacing:.5px;">AdhanBox</div>
      <div style="color:#CFE5DD;font-size:12px;margin-top:4px;letter-spacing:1px;">FAIT MAIN EN FRANCE</div>
    </td></tr>
    <tr><td style="background:#FFFFFF;padding:32px;">
      ${bodyHtml}
      <p style="color:#777;font-size:13px;line-height:1.6;margin:22px 0 0;">
        Garantie 2 ans · Retour 14 jours<br>
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

const salut = (p) => `<div style="font-size:20px;color:#0C5B45;font-family:Georgia,serif;font-weight:700;">As-salāmu ʿalaykum${p ? ' ' + esc(p) : ''} 🌙</div>`;
const par = (t) => `<p style="color:#444;font-size:15px;line-height:1.6;margin:14px 0 0;">${t}</p>`;

function encadre(contenu) {
  return `
    <div style="margin:22px 0 0;background:#F6F4EF;border-radius:12px;padding:18px 20px;">
      ${contenu}
    </div>`;
}

function etapes(courante) {
  const l = [
    ['Commande confirmée', 1],
    ['En préparation', 2],
    ['Assemblée et testée', 3],
    ['Expédiée', 4],
  ];
  return encadre(l.map(([nom, n]) => {
    const fait = n <= courante;
    return `<div style="color:${fait ? '#0C5B45' : '#9A9A9A'};font-size:14px;font-weight:${n === courante ? '700' : '400'};padding:3px 0;">
      ${fait ? '✓' : '○'} ${nom}</div>`;
  }).join(''));
}

/**
 * Corps des 3 emails d'étape.
 * @param {'preparation'|'montage'|'expedition'} step
 */
export function stepEmail(step, { firstName, ref, config, tracking, carrier }) {
  const conf = config
    ? par(`Votre configuration&nbsp;: <b style="color:#0C5B45;">${esc(config)}</b>`)
    : '';
  const num = par(`Commande n°&nbsp;<b>${esc(ref)}</b>`);

  if (step === 'preparation') {
    return {
      subject: `Votre AdhanBox n° ${ref} est en préparation`,
      html: shell(`
        ${salut(firstName)}
        ${par(`Votre AdhanBox vient d'entrer en préparation. Vous faites partie des toutes premières commandes, et je tenais à vous l'annoncer moi-même.`)}
        ${conf}
        ${par(`Votre boîtier sera imprimé et assemblé à la main, à l'unité, puis testé un par un avant de partir. C'est ce qui prend du temps, et c'est aussi ce qui fait la différence.`)}
        ${etapes(2)}
        ${num}`),
    };
  }

  if (step === 'montage') {
    return {
      subject: `Votre AdhanBox n° ${ref} est assemblée`,
      html: shell(`
        ${salut(firstName)}
        ${par(`Votre AdhanBox est <b>assemblée et testée</b>. Elle a passé le contrôle : audio, lumière, connexion et déclenchement de l'adhan à l'heure.`)}
        ${conf}
        ${par(`Il ne reste plus qu'à l'emballer. Vous recevrez votre numéro de suivi dès qu'elle partira.`)}
        ${etapes(3)}
        ${num}`),
    };
  }

  // expedition
  const lien = tracking
    ? `<p style="margin:16px 0 0;text-align:center;">
         <a href="https://www.laposte.fr/outils/suivre-vos-envois?code=${encodeURIComponent(tracking)}"
            style="display:inline-block;background:#0C5B45;color:#fff;text-decoration:none;font-weight:600;font-size:15px;padding:12px 26px;border-radius:999px;">
            Suivre mon colis →</a>
       </p>
       <p style="color:#777;font-size:13px;text-align:center;margin:10px 0 0;">
         ${esc(carrier || 'Colissimo')} · n° ${esc(tracking)}</p>`
    : '';

  return {
    subject: `Votre AdhanBox n° ${ref} est en route`,
    html: shell(`
      ${salut(firstName)}
      ${par(`Ça y est&nbsp;: votre AdhanBox est <b>partie</b>. 📦`)}
      ${conf}
      ${encadre(lien || par('Votre numéro de suivi vous sera communiqué dans la journée.'))}
      ${par(`À la réception, branchez-la en USB-C et suivez la notice glissée dans la boîte : l'installation prend moins de cinq minutes.`)}
      ${par(`Si quoi que ce soit vous surprend à l'ouverture, écrivez-moi avant toute chose. J'y répondrai personnellement.`)}
      ${etapes(4)}
      ${num}`),
  };
}
