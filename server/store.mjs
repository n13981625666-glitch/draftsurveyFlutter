// Shared by the HTTP server and the admin CLI: key material, licence database, token signing.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const DATA_DIR = process.env.DATA_DIR || path.join(ROOT, 'server', 'data');
const F_PRIV = path.join(DATA_DIR, 'private.pem');
const F_LIC = path.join(DATA_DIR, 'licenses.json');
const F_SHIPKEYS = path.join(DATA_DIR, 'ship-keys.json');

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const DAY = 86400;
export const nowSec = () => Math.floor(Date.now() / 1000);

fs.mkdirSync(DATA_DIR, { recursive: true });

/* ---------- key material ---------- */
export function ensureKeypair() {
    if (!fs.existsSync(F_PRIV)) {
        const { privateKey } = crypto.generateKeyPairSync('ed25519');
        fs.writeFileSync(F_PRIV, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
    }
    return loadPrivateKey();
}
export function loadPrivateKey() {
    return crypto.createPrivateKey(fs.readFileSync(F_PRIV));
}
/** Raw 32-byte public key, base64 (what the Rust app embeds). */
export function publicKeyB64() {
    const pub = crypto.createPublicKey(loadPrivateKey());
    return pub.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
}

/* ---------- small JSON "database" (re-read on every call so the CLI and server never disagree) ---------- */
const readJson = (f, fallback) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : fallback);
const writeJson = (f, v) => {
    fs.writeFileSync(f + '.tmp', JSON.stringify(v, null, 2));
    fs.renameSync(f + '.tmp', f);
};
export const loadLicenses = () => readJson(F_LIC, {});
export const saveLicenses = (db) => writeJson(F_LIC, db);
export const loadShipKeys = () => readJson(F_SHIPKEYS, {});
export const saveShipKeys = (k) => writeJson(F_SHIPKEYS, k);

export function newLicenseKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // no 0/O/1/I
    const group = () => Array.from(crypto.randomBytes(4), (b) => alphabet[b % alphabet.length]).join('');
    return `DS-${group()}-${group()}-${group()}-${group()}`;
}

/* ---------- licence logic ---------- */
export function shipIdsFor(lic, shipKeys = loadShipKeys()) {
    return lic.ships === '*' ? Object.keys(shipKeys) : lic.ships.filter((id) => shipKeys[id]);
}

/** token = base64url(payload) . base64url(Ed25519 signature over the payload bytes) */
export function signToken(key, lic, machine) {
    const shipKeys = loadShipKeys();
    const payload = Buffer.from(JSON.stringify({
        v: 1,
        lic: key,
        customer: lic.customer,
        machine,
        issued: nowSec(),
        expires: lic.expiresAt,
        ships: shipIdsFor(lic, shipKeys).map((id) => ({ id, key: shipKeys[id] })),
    }));
    const sig = crypto.sign(null, payload, loadPrivateKey());
    return `${b64u(payload)}.${b64u(sig)}`;
}

/**
 * Expiry modes:
 *   expiresAt (unix s)  -> fixed calendar end date, set now
 *   days, start='issue' -> (default) days counted from today, i.e. from the moment the key is created
 *   days, start='activation' -> the clock starts at first activation (old behaviour)
 */
export function createLicense({ customer, days, ships = '*', maxDevices = 1, note = '', expiresAt = null, start = 'issue' }) {
    if (!(expiresAt > 0) && !(days > 0)) throw new Error('A licence needs --days (>0) or --expires.');
    const db = loadLicenses();
    let key;
    do { key = newLicenseKey(); } while (db[key]);
    db[key] = {
        customer, days, ships, maxDevices, note,
        createdAt: nowSec(), activatedAt: null,
        expiresAt: expiresAt || (start === 'activation' ? null : nowSec() + days * DAY),
        revoked: false, devices: {},
    };
    saveLicenses(db);
    return key;
}

/**
 * Pure decision used by both endpoints.
 * returns { status: 'ok'|'invalid'|'revoked'|'expired'|'device_limit', token? }
 */
export function evaluate(key, machine, { activate }) {
    const db = loadLicenses();
    const lic = db[String(key || '').trim().toUpperCase()];
    if (!lic || typeof machine !== 'string' || machine.length < 16) return { status: 'invalid' };
    const k = String(key).trim().toUpperCase();
    if (lic.revoked) return { status: 'revoked' };

    const t = nowSec();
    const known = lic.devices[machine];
    if (!known) {
        if (!activate) return { status: 'invalid' };               // /check from a machine that never activated
        if (Object.keys(lic.devices).length >= lic.maxDevices) return { status: 'device_limit' };
        lic.devices[machine] = { firstSeen: t, lastSeen: t };
    }
    if (activate && !lic.activatedAt) {
        lic.activatedAt = t;
        if (!lic.expiresAt && lic.days > 0) lic.expiresAt = t + lic.days * DAY;   // only 'activation'-mode keys start their clock here
    }
    if (lic.expiresAt && t >= lic.expiresAt) { saveLicenses(db); return { status: 'expired' }; }

    lic.devices[machine].lastSeen = t;
    saveLicenses(db);
    return { status: 'ok', token: signToken(k, lic, machine) };
}

/* ---------- shared survey data (one small ring of the last 5 exports per ship) ---------- */
export const MAX_SHARED = 5;
const DIR_SHARED = path.join(DATA_DIR, 'shared');
fs.mkdirSync(DIR_SHARED, { recursive: true });
const sha256 = (x) => crypto.createHash('sha256').update(x).digest('hex');

/**
 * Who shares with whom. 'ship' (default): every licence that holds the ship shares one pool.
 * SYNC_SCOPE=customer: the pool is per ship AND per customer (two companies never see each other's data).
 */
const SHARE_SCOPE = process.env.SYNC_SCOPE === 'customer' ? 'customer' : 'ship';
const poolFile = (shipId, lic) =>
    path.join(DIR_SHARED, (SHARE_SCOPE === 'customer' ? `${shipId}__${sha256(lic.customer).slice(0, 12)}` : shipId) + '.json');

/** Verify a licence token (signature made by signToken). Returns its claims, or null. */
export function verifyToken(token) {
    const [p, s] = String(token || '').split('.');
    if (!p || !s) return null;
    try {
        const payload = Buffer.from(p, 'base64url');
        const pub = crypto.createPublicKey(loadPrivateKey());
        if (!crypto.verify(null, payload, pub, Buffer.from(s, 'base64url'))) return null;
        return JSON.parse(payload.toString('utf8'));
    } catch { return null; }
}

/**
 * Same checks as a licence check, but from the signed token the app already holds:
 * licence exists, not revoked, not expired, this machine is registered, and the ship is on the licence.
 * returns { status: 'ok', lic, machine } or { status: 'invalid'|'revoked'|'expired'|'ship_not_licensed' }
 */
export function authorizeSync(token, shipId) {
    const claims = verifyToken(token);
    if (!claims) return { status: 'invalid' };
    const lic = loadLicenses()[claims.lic];
    if (!lic || !lic.devices[claims.machine]) return { status: 'invalid' };
    if (lic.revoked) return { status: 'revoked' };
    if (lic.expiresAt && nowSec() >= lic.expiresAt) return { status: 'expired' };
    if (typeof shipId !== 'string' || !/^[\w-]+$/.test(shipId) || !shipIdsFor(lic).includes(shipId)) return { status: 'ship_not_licensed' };
    return { status: 'ok', lic, machine: claims.machine };
}

/** Store one export. An identical export already in the pool is replaced (kept once, moved to the top). */
export function pushShared(shipId, lic, machine, data) {
    const f = poolFile(shipId, lic);
    const hash = sha256(JSON.stringify(data));
    const list = readJson(f, []).filter((e) => e.hash !== hash);
    list.unshift({ id: crypto.randomUUID(), ts: nowSec(), customer: lic.customer, mid: sha256(machine).slice(0, 12), hash, data });
    list.length = Math.min(list.length, MAX_SHARED);
    writeJson(f, list);
    return list.length;
}

/** Newest first. `mine` = pushed from the asking machine. */
export function listShared(shipId, lic, machine) {
    const mid = sha256(machine).slice(0, 12);
    return readJson(poolFile(shipId, lic), []).map((e) => ({ id: e.id, ts: e.ts, customer: e.customer, mine: e.mid === mid, data: e.data }));
}
