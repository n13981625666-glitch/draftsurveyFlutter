// End-to-end test of the licence protocol. Plays the role of the Rust client:
// verifies tokens exactly like license.rs and decrypts .shipx exactly like ships.rs.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dslic-'));
process.env.DATA_DIR = tmp;
const store = await import('../store.mjs');
const { packShip } = await import('../../tools/pack-ship.mjs');

store.ensureKeypair();
const pubRaw = Buffer.from(store.publicKeyB64(), 'base64');
const pubKey = crypto.createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), pubRaw]), format: 'der', type: 'spki' });

// a throw-away ship
const shipsDir = path.join(tmp, 'ships');
fs.mkdirSync(shipsDir);
const plain = JSON.stringify({ schemaVersion: 1, ship: { name: 'TEST SHIP' }, secret: 'tables' });
fs.writeFileSync(path.join(tmp, 'TESTSHIP.ship.json'), plain);
packShip(path.join(tmp, 'TESTSHIP.ship.json'), { outDir: shipsDir });
fs.writeFileSync(path.join(tmp, 'OTHER.ship.json'), plain);
packShip(path.join(tmp, 'OTHER.ship.json'), { outDir: shipsDir });
const envelope = JSON.parse(fs.readFileSync(path.join(shipsDir, 'TESTSHIP.shipx'), 'utf8'));

// ---- client side helpers (mirror the Rust code) ----
const verifyToken = (token) => {
    const [p, s] = token.split('.');
    const payload = Buffer.from(p, 'base64url');
    if (!crypto.verify(null, payload, pubKey, Buffer.from(s, 'base64url'))) throw new Error('bad signature');
    return JSON.parse(payload);
};
const openShip = (claims, env) => {
    const g = claims.ships.find((x) => x.id === env.id);
    if (!g) throw new Error('ship_not_licensed');
    const data = Buffer.from(env.data, 'base64');
    const d = crypto.createDecipheriv('aes-256-gcm', Buffer.from(g.key, 'base64'), Buffer.from(env.nonce, 'base64'));
    d.setAAD(Buffer.from(env.id));
    d.setAuthTag(data.subarray(-16));
    return Buffer.concat([d.update(data.subarray(0, -16)), d.final()]).toString('utf8');
};

// ---- start the real server ----
const PORT = 18700 + Math.floor(Math.random() * 200);
const srv = spawn(process.execPath, [path.resolve('server/server.mjs')], { env: { ...process.env, PORT: String(PORT), DATA_DIR: tmp, RATE_LIMIT: '100000' }, stdio: ['ignore', 'pipe', 'inherit'] });
await new Promise((r) => srv.stdout.once('data', r));
const call = async (ep, body) => (await fetch(`http://127.0.0.1:${PORT}/v1/${ep}`, { method: 'POST', body: JSON.stringify(body) })).json();
const M1 = crypto.randomBytes(32).toString('hex'), M2 = crypto.randomBytes(32).toString('hex');
let passed = 0;
const ok = (name) => { passed++; console.log('  ✓', name); };

try {
    const key = store.createLicense({ customer: 'ACME', days: 30, ships: ['TESTSHIP'], maxDevices: 1 });

    let r = await call('activate', { key, machine: M1 });
    assert.equal(r.status, 'ok');
    let claims = verifyToken(r.token);
    assert.equal(claims.machine, M1);
    assert.equal(claims.customer, 'ACME');
    assert.ok(Math.abs(claims.expires - (claims.issued + 30 * 86400)) < 5);
    ok('activate → signed token, expiry = activation + days');

    assert.equal(openShip(claims, envelope), plain);
    ok('ship decrypts with key from the token');

    assert.throws(() => openShip(claims, { ...envelope, id: 'OTHER' }), /ship_not_licensed/);
    ok('ship not in licence cannot be opened');

    const bad = JSON.parse(JSON.stringify(envelope)); bad.id = 'TESTSHIP';
    const buf = Buffer.from(bad.data, 'base64'); buf[5] ^= 1; bad.data = buf.toString('base64');
    assert.throws(() => openShip(claims, bad));
    ok('tampered ciphertext is rejected');

    const [p, s] = r.token.split('.');
    const forged = Buffer.from(JSON.stringify({ ...claims, expires: claims.expires + 99999999 })).toString('base64url') + '.' + s;
    assert.throws(() => verifyToken(forged), /bad signature/);
    ok('edited token (longer expiry) fails signature check');

    assert.equal((await call('activate', { key, machine: M2 })).status, 'device_limit');
    ok('second device refused (maxDevices=1)');

    const r2 = await call('activate', { key, machine: M1 });
    assert.equal(verifyToken(r2.token).expires, claims.expires);
    ok('re-activating the same device does not restart the clock');

    assert.equal((await call('check', { key, machine: M2 })).status, 'invalid');
    ok('check from a never-activated machine is refused');

    assert.equal((await call('check', { key, machine: M1 })).status, 'ok');
    ok('periodic check ok');

    const db = store.loadLicenses(); db[key].revoked = true; store.saveLicenses(db);
    assert.equal((await call('check', { key, machine: M1 })).status, 'revoked');
    assert.equal((await call('activate', { key, machine: M1 })).status, 'revoked');
    ok('revoked key → check and activate both say revoked');

    db[key].revoked = false; store.saveLicenses(db);
    assert.equal((await call('check', { key, machine: M1 })).status, 'ok');
    ok('restore works');

    db[key].expiresAt = store.nowSec() - 10; store.saveLicenses(db);
    assert.equal((await call('check', { key, machine: M1 })).status, 'expired');
    ok('expired on server → expired');

    db[key].expiresAt = store.nowSec() + 86400 * 5; store.saveLicenses(db);
    const r3 = await call('check', { key, machine: M1 });
    assert.equal(verifyToken(r3.token).expires, db[key].expiresAt);
    ok('extension reaches the client through the next check');

    assert.equal((await call('activate', { key: 'DS-NOPE-NOPE-NOPE-NOPE', machine: M1 })).status, 'invalid');
    ok('unknown key → invalid');

    const key2 = store.createLicense({ customer: 'ALL', days: 1, ships: '*' });
    const c2 = verifyToken((await call('activate', { key: key2, machine: M1 })).token);
    assert.deepEqual(c2.ships.map((x) => x.id).sort(), ['OTHER', 'TESTSHIP']);
    ok('"*" licence grants every packed ship');

    /* ---------- shared survey data ---------- */
    const tokenOf = async (k, m) => (await call('activate', { key: k, machine: m })).token;
    const kA = store.createLicense({ customer: 'ACME', days: 30, ships: ['TESTSHIP'] });
    const kB = store.createLicense({ customer: 'BETA', days: 30, ships: ['TESTSHIP'] });
    const kO = store.createLicense({ customer: 'OTHERCO', days: 30, ships: ['OTHER'] });
    const tA = await tokenOf(kA, M1), tB = await tokenOf(kB, M2), tO = await tokenOf(kO, M1);
    const exp = (n) => [{ survey: 0, fields: { 'survey-0-ballast': String(n) } }];

    assert.deepEqual((await call('sync/list', { token: tA, ship: 'TESTSHIP' })).items, []);
    ok('empty pool lists no data');

    assert.equal((await call('sync/push', { token: tA, ship: 'TESTSHIP', data: exp(1) })).status, 'ok');
    let l = await call('sync/list', { token: tB, ship: 'TESTSHIP' });
    assert.equal(l.items.length, 1);
    assert.deepEqual(l.items[0].data, exp(1));
    assert.equal(l.items[0].customer, 'ACME');
    assert.equal(l.items[0].mine, false);
    assert.equal((await call('sync/list', { token: tA, ship: 'TESTSHIP' })).items[0].mine, true);
    ok('another licence holding the same ship reads it (and "mine" is per machine)');

    assert.equal((await call('sync/list', { token: tO, ship: 'TESTSHIP' })).status, 'ship_not_licensed');
    assert.equal((await call('sync/push', { token: tO, ship: 'TESTSHIP', data: exp(9) })).status, 'ship_not_licensed');
    ok('a licence without that ship can neither read nor write its pool');

    await call('sync/push', { token: tB, ship: 'TESTSHIP', data: exp(1) });
    l = await call('sync/list', { token: tA, ship: 'TESTSHIP' });
    assert.equal(l.items.length, 1);
    assert.equal(l.items[0].customer, 'BETA');
    ok('identical content is kept once (moved to the top)');

    for (let n = 2; n <= 7; n++) await call('sync/push', { token: tA, ship: 'TESTSHIP', data: exp(n) });
    l = await call('sync/list', { token: tB, ship: 'TESTSHIP' });
    assert.equal(l.items.length, 5);
    assert.deepEqual(l.items.map((x) => x.data[0].fields['survey-0-ballast']), ['7', '6', '5', '4', '3']);
    ok('only the newest 5 are kept, newest first');

    const [pp, ss] = tA.split('.');
    const forgedTok = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(pp, 'base64url')), lic: kB })).toString('base64url') + '.' + ss;
    assert.equal((await call('sync/list', { token: forgedTok, ship: 'TESTSHIP' })).status, 'invalid');
    assert.equal((await call('sync/list', { token: 'x.y', ship: 'TESTSHIP' })).status, 'invalid');
    assert.equal((await call('sync/list', { ship: 'TESTSHIP' })).status, 'invalid');
    assert.equal((await call('sync/list', { token: tA, ship: '../private' })).status, 'ship_not_licensed');
    ok('forged / missing token and path tricks are refused');

    assert.equal((await call('sync/push', { token: tA, ship: 'TESTSHIP', data: { not: 'an array' } })).status, 'bad_data');
    const big = await fetch(`http://127.0.0.1:${PORT}/v1/sync/push`, { method: 'POST', body: JSON.stringify({ token: tA, ship: 'TESTSHIP', data: [{ x: 'a'.repeat(300000) }] }) });
    assert.equal(big.status, 413);
    ok('malformed and oversized pushes are refused');

    const dbS = store.loadLicenses();
    dbS[kB].revoked = true; store.saveLicenses(dbS);
    assert.equal((await call('sync/list', { token: tB, ship: 'TESTSHIP' })).status, 'revoked');
    dbS[kB].revoked = false; dbS[kB].expiresAt = store.nowSec() - 5; store.saveLicenses(dbS);
    assert.equal((await call('sync/push', { token: tB, ship: 'TESTSHIP', data: exp(1) })).status, 'expired');
    ok('revoked or expired licences are cut off from the shared data');

    console.log(`\n${passed} checks passed`);
} finally {
    srv.kill();
    fs.rmSync(tmp, { recursive: true, force: true });
}
