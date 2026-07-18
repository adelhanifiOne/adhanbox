// GET /api/reviews  →  { count, average, reviews: [ { note, texte, prenom, ville, verifie, date } ] }
// Renvoie les avis APPROUVÉS (reviews/approved/*.json dans Vercel Blob), triés
// du plus récent au plus ancien. Réponse mise en cache au bord (CDN) 5 min pour
// ne pas relister le Blob à chaque visite.
//
// Signature Node (req, res), helpers désactivés (NODEJS_HELPERS=0).
import { list } from '@vercel/blob';

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899',
];

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (ALLOWED_ORIGINS.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'GET') { res.statusCode = 405; return res.end('Méthode non autorisée'); }

  let reviews = [];
  try {
    const { blobs } = await list({ prefix: 'reviews/approved/' });
    reviews = await Promise.all(blobs.map(async (b) => {
      try {
        const r = await fetch(b.url, { cache: 'no-store' });
        return r.ok ? await r.json() : null;
      } catch { return null; }
    }));
    reviews = reviews
      .filter(Boolean)
      .sort((a, b) => (b.date || '').localeCompare(a.date || ''));
  } catch (err) {
    console.error('lecture avis échouée:', err && err.message);
    // On renvoie une liste vide plutôt qu'une erreur : le site reste debout.
  }

  const count = reviews.length;
  const average = count
    ? Math.round((reviews.reduce((s, r) => s + (r.note || 0), 0) / count) * 10) / 10
    : 0;

  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  // CDN : sert la même réponse 5 min, régénère en tâche de fond jusqu'à 1 h.
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=3600');
  res.end(JSON.stringify({ count, average, reviews }));
}
