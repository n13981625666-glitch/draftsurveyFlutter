// Licence server. Zero dependencies. Run behind an HTTPS reverse proxy (Caddy / nginx).
//   PORT=8787 node server/server.mjs
import http from 'node:http';
import { ensureKeypair, evaluate, authorizeSync, pushShared, listShared } from './store.mjs';

ensureKeypair();
const PORT = Number(process.env.PORT || 8787);

// naive per-IP rate limit: 30 requests / minute (RATE_LIMIT overrides, the test suite raises it)
const MAX_PER_MIN = Number(process.env.RATE_LIMIT || 30);
const hits = new Map();
function limited(ip) {
    const t = Date.now();
    const arr = (hits.get(ip) || []).filter((x) => t - x < 60_000);
    arr.push(t);
    hits.set(ip, arr);
    return arr.length > MAX_PER_MIN;
}

const send = (res, code, obj) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(obj));
};

// POST routes and the largest body each accepts (bytes)
const ROUTES = {
    '/v1/activate': 4096,
    '/v1/check': 4096,
    '/v1/sync/push': 256 * 1024,
    '/v1/sync/list': 4096,
};

http.createServer((req, res) => {
    const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').toString().split(',')[0].trim();
    const limit = ROUTES[req.url];
    if (req.method !== 'POST' || !limit) return send(res, 404, { status: 'not_found' });
    if (limited(ip)) return send(res, 429, { status: 'rate_limited' });

    const chunks = [];
    let size = 0, tooBig = false;
    req.on('data', (c) => {
        size += c.length;
        if (size > limit) { tooBig = true; return; }
        chunks.push(c);
    });
    req.on('end', () => {
        if (tooBig) return send(res, 413, { status: 'too_large' });
        let j;
        try { j = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return send(res, 400, { status: 'invalid' }); }
        if (!j || typeof j !== 'object') return send(res, 400, { status: 'invalid' });

        if (req.url.startsWith('/v1/sync/')) return handleSync(req.url, j, ip, res);

        const r = evaluate(j.key, j.machine, { activate: req.url === '/v1/activate' });
        console.log(new Date().toISOString(), req.url, ip, String(j.key).slice(0, 7) + '…', r.status);
        send(res, 200, r);
    });
}).listen(PORT, () => console.log(`licence server on :${PORT}`));

/** Shared survey data: { token, ship, data? }. Only licences that hold the ship can read or write its pool. */
function handleSync(url, j, ip, res) {
    const a = authorizeSync(j.token, j.ship);
    if (a.status !== 'ok') return send(res, 200, { status: a.status });

    if (url === '/v1/sync/push') {
        // an export is the array getSurveyExportData() makes
        if (!Array.isArray(j.data) || !j.data.every((x) => x && typeof x === 'object')) return send(res, 200, { status: 'bad_data' });
        const n = pushShared(j.ship, a.lic, a.machine, j.data);
        console.log(new Date().toISOString(), url, ip, j.ship, 'stored', n);
        return send(res, 200, { status: 'ok', stored: n });
    }
    return send(res, 200, { status: 'ok', items: listShared(j.ship, a.lic, a.machine) });
}
