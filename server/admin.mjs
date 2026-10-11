// Admin CLI — run on the server machine (edits the same data files the server reads).
//   node server/admin.mjs create --customer "ACME Shipping" (--days 365 | --expires 2027-06-30) [--start issue|activation] [--ships A,B | --ships "*"] [--devices 1] [--note "..."]
//   node server/admin.mjs list
//   node server/admin.mjs show   <KEY>
//   node server/admin.mjs revoke <KEY>          (client notices at its next online check)
//   node server/admin.mjs restore <KEY>
//   node server/admin.mjs extend <KEY> --days 30
//   node server/admin.mjs set-expiry <KEY> --expires 2027-06-30
//   node server/admin.mjs set-ships <KEY> --ships A,B     (or "*")
//   node server/admin.mjs reset-devices <KEY>   (customer changed computer / reinstalled phone)
import { createLicense, loadLicenses, saveLicenses, loadShipKeys, nowSec } from './store.mjs';

const [cmd, ...rest] = process.argv.slice(2);
const flags = {};
const pos = [];
for (let i = 0; i < rest.length; i++) {
    if (rest[i].startsWith('--')) flags[rest[i].slice(2)] = rest[++i];
    else pos.push(rest[i]);
}
const fmt = (t) => (t ? new Date(t * 1000).toISOString().slice(0, 10) : '-');
const parseShips = (s) => (s === undefined || s === '*' ? '*' : s.split(',').map((x) => x.trim()).filter(Boolean));
const fail = (m) => { console.error(m); process.exit(1); };
const getLic = () => {
    const db = loadLicenses();
    const k = (pos[0] || '').toUpperCase();
    if (!db[k]) fail('No such licence key.');
    return { db, k, lic: db[k] };
};

switch (cmd) {
    case 'create': {
        if (!flags.customer || (!flags.days && !flags.expires)) fail('--customer and (--days or --expires YYYY-MM-DD) are required');
        let expiresAt = null;
        if (flags.expires) {
            // end of that calendar day, China time (UTC+8)
            const ms = Date.parse(`${flags.expires}T23:59:59+08:00`);
            if (!ms) fail('--expires must look like 2027-06-30');
            expiresAt = Math.floor(ms / 1000);
        }
        const ships = parseShips(flags.ships);
        const known = Object.keys(loadShipKeys());
        if (ships !== '*') for (const s of ships) if (!known.includes(s)) fail(`Unknown ship "${s}". Packed ships: ${known.join(', ') || '(none)'}`);
        const key = createLicense({ customer: flags.customer, days: Number(flags.days || 0), expiresAt, start: flags.start === 'activation' ? 'activation' : 'issue', ships, maxDevices: Number(flags.devices || 1), note: flags.note || '' });
        console.log(key);
        break;
    }
    case 'list': {
        const db = loadLicenses();
        for (const [k, l] of Object.entries(db)) {
            const state = l.revoked ? 'REVOKED' : l.expiresAt && l.expiresAt <= nowSec() ? 'expired' : l.activatedAt ? 'active' : 'unused';
            console.log(`${k}  ${state.padEnd(8)} ${l.customer}  days=${l.days}  expires=${fmt(l.expiresAt)}  devices=${Object.keys(l.devices).length}/${l.maxDevices}  ships=${l.ships === '*' ? '*' : l.ships.join(',')}`);
        }
        break;
    }
    case 'show': { const { k, lic } = getLic(); console.log(k, JSON.stringify(lic, null, 2)); break; }
    case 'revoke': { const { db, lic } = getLic(); lic.revoked = true; saveLicenses(db); console.log('revoked'); break; }
    case 'restore': { const { db, lic } = getLic(); lic.revoked = false; saveLicenses(db); console.log('restored'); break; }
    case 'extend': {
        const { db, lic } = getLic();
        const d = Number(flags.days);
        if (!d) fail('--days required');
        if (lic.expiresAt) lic.expiresAt += d * 86400; else lic.days += d;
        saveLicenses(db);
        console.log('now expires', lic.expiresAt ? fmt(lic.expiresAt) : `${lic.days} days after activation`);
        break;
    }
    case 'set-expiry': {   // set-expiry <KEY> --expires 2027-06-30   (fixes a key whose date is wrong)
        const { db, lic } = getLic();
        const ms = Date.parse(`${flags.expires}T23:59:59+08:00`);
        if (!ms) fail('--expires must look like 2027-06-30');
        lic.expiresAt = Math.floor(ms / 1000);
        saveLicenses(db);
        console.log('now expires', fmt(lic.expiresAt));
        break;
    }
    case 'set-ships': { const { db, lic } = getLic(); lic.ships = parseShips(flags.ships); saveLicenses(db); console.log('ok'); break; }
    case 'reset-devices': { const { db, lic } = getLic(); lic.devices = {}; saveLicenses(db); console.log('ok'); break; }
    default: console.log('commands: create | list | show | revoke | restore | extend | set-expiry | set-ships | reset-devices');
}
