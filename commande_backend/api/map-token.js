// GET /api/map-token
// Fournit au navigateur le jeton du composant carte Boxtal (points relais).
//
// Le composant @boxtal/parcel-point-map exige un accessToken obtenu en
// echangeant la cle d'acces + la cle secrete de l'application « Composant
// carte » contre un JWT (POST https://api.boxtal.com/iam/account-app/token,
// Basic auth). Le JWT vit 60 min ; seul lui transite vers la page — les deux
// cles restent ici, dans les variables d'environnement Vercel.
//
// Interrupteur : si BOXTAL_ACCESS_KEY / BOXTAL_SECRET_KEY sont absentes, la
// reponse est { enabled: false } et le site n'affiche que la livraison a
// domicile, exactement comme avant.
//
// Signature Node (req, res), NODEJS_HELPERS=0 (voir checkout.js).

const ALLOWED_ORIGINS = [
  'https://adhanbox.fr',
  'https://www.adhanbox.fr',
  'http://localhost:8899', // tests locaux (python -m http.server)
];

const TOKEN_URL = 'https://api.boxtal.com/iam/account-app/token';
// On renouvelle 10 min avant l'expiration reelle (60 min) : un client qui a
// recu le jeton juste avant le rafraichissement garde le temps de chercher.
const REFRESH_MARGIN_MS = 10 * 60 * 1000;

// Cache par instance de fonction : Vercel reutilise les instances (Fluid
// Compute), donc en pratique on n'appelle Boxtal que ~une fois par heure.
let cache = { token: null, exp: 0 };

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (ALLOWED_ORIGINS.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, status, obj) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(obj));
}

function jwtExpiryMs(token) {
  try {
    const payload = token.split('.')[1];
    const json = Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    const exp = JSON.parse(json).exp;
    return exp ? exp * 1000 : 0;
  } catch { return 0; }
}

async function fetchToken(accessKey, secretKey) {
  const auth = Buffer.from(`${accessKey}:${secretKey}`).toString('base64');
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, Accept: 'application/json' },
  });
  if (!r.ok) throw new Error(`Boxtal token HTTP ${r.status}`);
  const data = await r.json();
  if (!data || !data.accessToken) throw new Error('Boxtal token: reponse sans accessToken');
  return data.accessToken;
}

export default async function handler(req, res) {
  applyCors(req, res);
  if (req.method === 'OPTIONS') { res.statusCode = 204; return res.end(); }
  if (req.method !== 'GET') return sendJson(res, 405, { error: 'Méthode non autorisée' });

  const accessKey = process.env.BOXTAL_ACCESS_KEY;
  const secretKey = process.env.BOXTAL_SECRET_KEY;
  if (!accessKey || !secretKey) return sendJson(res, 200, { enabled: false });

  try {
    const now = Date.now();
    if (!cache.token || now > cache.exp - REFRESH_MARGIN_MS) {
      const token = await fetchToken(accessKey, secretKey);
      // Sans exp lisible on garde le jeton 45 min, en dessous de sa duree reelle.
      cache = { token, exp: jwtExpiryMs(token) || now + 45 * 60 * 1000 };
    }
    return sendJson(res, 200, {
      enabled: true,
      accessToken: cache.token,
      expiresAt: new Date(cache.exp).toISOString(),
      // Reseau propose sur le site. Code Boxtal (suffixe _NETWORK obligatoire).
      networks: ['MONR_NETWORK'],
    });
  } catch (err) {
    console.error('map-token error:', err && err.message);
    // Le front retombe sur la livraison a domicile : on ne bloque jamais la vente.
    return sendJson(res, 200, { enabled: false, error: 'indisponible' });
  }
}
