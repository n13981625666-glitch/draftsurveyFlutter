// Encrypt a plaintext ship profile into ships-lib/<ID>.shipx and register its key with the licence server.
// (src/ships/ is generated per build by tools/select-ship.mjs — it only ever holds the ONE ship being built.)
//   node tools/pack-ship.mjs ships-src/NORSE_SUCCESSION.ship.json [--rotate]
// The plaintext (ships-src/) and the keys (server/data/) must never be committed or shipped.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, loadShipKeys, saveShipKeys } from '../server/store.mjs';

export function packShip(file, { rotate = false, outDir: outDirOpt } = {}) {
    const id = path.basename(file).replace(/\.ship\.json$/i, '').replace(/[^\w-]+/g, '_');
    const plain = fs.readFileSync(file, 'utf8');
    const profile = JSON.parse(plain);                    // must be valid JSON
    if (!profile.ship || !profile.ship.name) throw new Error(`${file}: not a ship profile`);

    const keys = loadShipKeys();
    if (!keys[id] || rotate) keys[id] = crypto.randomBytes(32).toString('base64');
    saveShipKeys(keys);

    const nonce = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', Buffer.from(keys[id], 'base64'), nonce);
    cipher.setAAD(Buffer.from(id));
    const ct = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final(), cipher.getAuthTag()]);   // ciphertext || tag

    // "licensee" (who the ship data is licensed to) travels in the clear so the start-up splash can show it before the licence check
    const licensee = typeof profile.licensee === 'string' ? profile.licensee.trim() : '';
    const envelope = { v: 1, id, name: profile.ship.name, ...(licensee ? { licensee } : {}), nonce: nonce.toString('base64'), data: ct.toString('base64') };
    const outDir = outDirOpt || path.join(ROOT, 'ships-lib');
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(path.join(outDir, `${id}.shipx`), JSON.stringify(envelope));

    return id;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
    const args = process.argv.slice(2);
    const files = args.filter((a) => !a.startsWith('--'));
    if (!files.length) { console.error('usage: node tools/pack-ship.mjs <ship.json> [--rotate]'); process.exit(1); }
    for (const f of files) console.log('packed', packShip(f, { rotate: args.includes('--rotate') }));
}
