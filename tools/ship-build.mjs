// Local helper: select ONE ship, generate platform folders, then run flutter.
//   node tools/ship-build.mjs <SHIP_ID> [flutter args]      default: build apk --release
//   node tools/ship-build.mjs XINHAITONG_26 build windows --release
//   node tools/ship-build.mjs XINHAITONG_26 run -d windows
import { spawnSync } from 'node:child_process';
import { selectShip, listShipIds, ROOT } from './select-ship.mjs';

const [id, ...rest] = process.argv.slice(2);
if (!id) { console.error(`usage: node tools/ship-build.mjs <SHIP_ID> [flutter args]\navailable: ${listShipIds().join(', ') || '(none)'}`); process.exit(1); }
const sh = process.platform === 'win32';
const r0 = selectShip(id);
console.log(`Building ${r0.shipId} as "${r0.productName}" (${r0.identifier})`);
const run = (cmd, args) => spawnSync(cmd, args, { cwd: ROOT, stdio: 'inherit', shell: sh, env: process.env }).status ?? 1;
let code = run('node', ['tools/bootstrap_platforms.mjs']);
if (code === 0) code = run('flutter', ['pub', 'get']);
if (code === 0) {
    const args = rest.length ? rest : ['build', 'apk', '--release'];
    const url = process.env.DS_LICENSE_URL;
    if (url && ['build', 'run'].includes(args[0])) args.push(`--dart-define=DS_LICENSE_URL=${url}`);
    code = run('flutter', args);
}
process.exit(code);
