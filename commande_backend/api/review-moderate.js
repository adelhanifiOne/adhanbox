// GET /api/review-moderate?id=…&action=approve|reject&token=…
// Cible des deux liens de l'email de notification. Protégé par un token partagé
// (REVIEW_ADMIN_TOKEN). Approuver déplace l'avis de reviews/pending/ vers
// reviews/approved/ (⇒ visible sur le site) ; Rejeter le supprime.
//
// Renvoie une petite page HTML de confirmation (le lien est cliqué depuis un
// email, pas appelé en AJAX).
import { list, put, del } from '@vercel/blob';

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function page(res, status, title, message, tone) {
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
    <p style="margin-top:26px;"><a href="https://adhanbox.fr/avis.html" style="color:#0C5B45;font-weight:600;">Voir la page des avis →</a></p>
  </div>
</body></html>`);
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.statusCode = 405; return res.end('Méthode non autorisée'); }

  const url = new URL(req.url, 'http://localhost');
  const id = url.searchParams.get('id') || '';
  const action = url.searchParams.get('action') || '';
  const token = url.searchParams.get('token') || '';

  const ADMIN_TOKEN = process.env.REVIEW_ADMIN_TOKEN || '';
  if (!ADMIN_TOKEN || token !== ADMIN_TOKEN) {
    return page(res, 403, 'Accès refusé', 'Lien de modération invalide ou expiré.', 'err');
  }
  if (!/^[a-f0-9-]{16,}$/i.test(id) || !['approve', 'reject'].includes(action)) {
    return page(res, 400, 'Requête invalide', 'Lien de modération malformé.', 'err');
  }

  try {
    const { blobs } = await list({ prefix: 'reviews/pending/' });
    const pending = blobs.find((b) => b.pathname === `reviews/pending/${id}.json`);

    if (!pending) {
      // Déjà approuvé, déjà rejeté, ou id inconnu.
      return page(res, 200, 'Déjà traité', 'Cet avis a déjà été modéré (ou n\'existe plus).', 'warn');
    }

    if (action === 'reject') {
      await del(pending.url);
      return page(res, 200, 'Avis rejeté', 'L\'avis a été supprimé. Il ne sera pas publié.', 'warn');
    }

    // Approuver : copier le contenu vers reviews/approved/ puis supprimer le pending.
    const r = await fetch(pending.url, { cache: 'no-store' });
    const content = await r.text();
    await put(`reviews/approved/${id}.json`, content, {
      access: 'public',
      addRandomSuffix: false,
      contentType: 'application/json',
    });
    await del(pending.url);
    return page(res, 200, 'Avis publié 🎉', 'L\'avis est maintenant visible sur adhanbox.fr/avis.html (jusqu\'à 5 min de cache).', 'ok');
  } catch (err) {
    console.error('modération avis échouée:', err && err.message);
    return page(res, 500, 'Erreur serveur', 'La modération a échoué. Réessayez dans un instant.', 'err');
  }
}
