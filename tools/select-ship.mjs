// Pick ONE ship for this build: one code base, many ships.
//   node tools/select-ship.mjs <SHIP_ID>
//   1. copies ships-lib/<SHIP_ID>.shipx to assets/ships/ (emptying it first) and writes assets/ships/index.json
//   2. writes tools/.ship-identity.json (app name + application id) which bootstrap_platforms.mjs applies to the
//      generated android/ and windows/ folders, so different ships install side by side.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LIB = path.join(ROOT, 'ships-lib');
const OUT = path.join(ROOT, 'assets', 'ships');
export const IDENTITY_FILE = path.join(ROOT, 'tools', '.ship-identity.json');
const BASE = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools', 'app-identity.json'), 'utf8'));

export function listShipIds() {
    if (!fs.existsSync(LIB)) return [];
    return fs.readdirSync(LIB).filter((f) => f.endsWith('.shipx')).map((f) => f.replace(/\.shipx$/, '')).sort();
}

/** Application id is "<base>.<ship>": letters/digits only, a segment must not start with a digit. */
export function shipIdentifier(baseId, shipId) {
    let seg = shipId.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (!seg) throw new Error(`ship id "${shipId}" has no letters or digits to build an app identifier from`);
    if (/^[0-9]/.test(seg)) seg = 's' + seg;
    return `${baseId}.${seg}`;
}

export function selectShip(shipId) {
    const ids = listShipIds();
    if (!ids.includes(shipId)) throw new Error(`No ships-lib/${shipId}.shipx. Available: ${ids.join(', ') || '(none)'}`);
    const text = fs.readFileSync(path.join(LIB, `${shipId}.shipx`), 'utf8');
    const env = JSON.parse(text);
    if (env.id !== shipId) throw new Error(`ships-lib/${shipId}.shipx contains ship id "${env.id}" — file name and id must match`);

    fs.mkdirSync(OUT, { recursive: true });
    for (const f of fs.readdirSync(OUT)) if (f.endsWith('.shipx') || f === 'index.json') fs.rmSync(path.join(OUT, f));
    fs.writeFileSync(path.join(OUT, `${shipId}.shipx`), text);
    fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify([`${shipId}.shipx`]));

    const shipName = String(env.name || shipId).replace(/[<>:"/\\|?*\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim();
    const identity = {
        shipId,
        productName: `${BASE.productName} ${shipName}`,
        identifier: shipIdentifier(BASE.identifier, shipId),
    };
    fs.writeFileSync(IDENTITY_FILE, JSON.stringify(identity, null, 2) + '\n');
    return { ...identity, name: env.name, licensee: env.licensee || '' };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const id = process.argv[2];
    if (!id) { console.error(`usage: node tools/select-ship.mjs <SHIP_ID>\navailable: ${listShipIds().join(', ') || '(none)'}`); process.exit(1); }
    try {
        const r = selectShip(id);
        console.log(`ship      : ${r.shipId} (${r.name})${r.licensee ? ' — licensed to ' + r.licensee : ''}\napp name  : ${r.productName}\nidentifier: ${r.identifier}`);
    } catch (e) { console.error(e.message); process.exit(1); }
}
