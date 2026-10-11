// One-time (and re-runnable) project setup:
//   1. create the Ed25519 signing key in server/data/ (if missing)
//   2. write the public half to assets/keys/license_public.key (bundled into the app)
//   3. encrypt every ships-src/*.ship.json into ships-lib/*.shipx
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, ensureKeypair, publicKeyB64 } from '../server/store.mjs';
import { packShip } from './pack-ship.mjs';

ensureKeypair();
const pubFile = path.join(ROOT, 'assets', 'keys', 'license_public.key');
fs.mkdirSync(path.dirname(pubFile), { recursive: true });
fs.writeFileSync(pubFile, publicKeyB64());
console.log('public key ->', path.relative(ROOT, pubFile));

const srcDir = path.join(ROOT, 'ships-src');
if (fs.existsSync(srcDir)) {
    for (const f of fs.readdirSync(srcDir).filter((x) => x.endsWith('.ship.json'))) console.log('packed', packShip(path.join(srcDir, f)));
}
console.log('\nKeep server/data/ private and backed up: losing private.pem or ship-keys.json locks every customer out.');
