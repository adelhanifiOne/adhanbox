// Compteur de parcours du site adhanbox.fr (11/10/2026).
//
// Cloudflare Web Analytics (docs/mesure.js) compte les pages vues, mais pas
// jusqu'ou on descend dans une page ni sur quoi on clique. Ce Worker recoit
// les petits signaux envoyes par docs/mesure.js et incremente des COMPTEURS
// PAR JOUR dans la base D1 « adhanbox-mesure » : jamais une ligne par
// visiteur, ni IP, ni identifiant, ni cookie. D'ou l'absence de bandeau.
//
//   POST https://adhanbox-mesure.adhanbox.workers.dev/
//   corps (text/plain, pour eviter le pre-vol CORS de sendBeacon) :
//   {"page":"/","quoi":"defile-50","source":"instagram"}
//
// Lecture : requete SQL sur D1 (compte Cloudflare d'Adel), par exemple
//   SELECT quoi, SUM(n) FROM compteurs WHERE page='/' AND jour>='2026-10-11' GROUP BY quoi
//
// Publie depuis Claude via l'API Cloudflare (binding D1 « DB »).

const ORIGINES = /^https:\/\/(www\.)?adhanbox\.fr$/;
const PAGE = /^\/[a-z0-9\-\/.]{0,40}$/;
const QUOI = /^[a-z0-9\-:.\/]{1,60}$/;
const SOURCES = new Set(['instagram', 'facebook', 'google', 'tiktok', 'interne', 'direct', 'autre']);

export default {
  async fetch(req, env) {
    const origin = req.headers.get('Origin') || '';
    const cors = ORIGINES.test(origin) ? { 'Access-Control-Allow-Origin': origin } : {};
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'POST' } });
    if (req.method !== 'POST' || !cors['Access-Control-Allow-Origin']) return new Response('', { status: 403 });
    let e;
    try { e = JSON.parse(await req.text()); } catch { return new Response('', { status: 400, headers: cors }); }
    const page = String(e.page || '');
    const quoi = String(e.quoi || '');
    const source = SOURCES.has(e.source) ? e.source : 'autre';
    if (!PAGE.test(page) || !QUOI.test(quoi)) return new Response('', { status: 400, headers: cors });
    const jour = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });   // AAAA-MM-JJ
    await env.DB.prepare(
      'INSERT INTO compteurs (jour, page, quoi, source, n) VALUES (?, ?, ?, ?, 1) ' +
      'ON CONFLICT (jour, page, quoi, source) DO UPDATE SET n = n + 1'
    ).bind(jour, page, quoi, source).run();
    return new Response('', { status: 204, headers: cors });
  },
};
