// Print the ship IDs to build as a JSON array (used by the GitHub Actions matrix).
//   node tools/list-ships.mjs            -> every ship in ships-lib/
//   node tools/list-ships.mjs all
//   node tools/list-ships.mjs "A,B"      -> only those (an unknown ID is an error)
import { listShipIds } from './select-ship.mjs';

const want = (process.argv[2] || 'all').trim();
const all = listShipIds();
let ids = all;
if (want && want.toLowerCase() !== 'all') {
    ids = want.split(/[\s,]+/).filter(Boolean);
    const bad = ids.filter((i) => !all.includes(i));
    if (bad.length) { console.error(`Unknown ship(s): ${bad.join(', ')}. Available: ${all.join(', ')}`); process.exit(1); }
}
console.log(JSON.stringify(ids));
