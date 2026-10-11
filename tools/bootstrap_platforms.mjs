// Generates the android/ and windows/ runner folders (they are not committed) and applies the ship identity.
//   node tools/bootstrap_platforms.mjs [--platforms=android,windows]
// Needs the Flutter SDK on PATH. Run `node tools/select-ship.mjs <SHIP_ID>` first.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ROOT, IDENTITY_FILE } from './select-ship.mjs';

const arg = process.argv.find((a) => a.startsWith('--platforms='));
const platforms = arg ? arg.split('=')[1] : 'android,windows';
if (!fs.existsSync(IDENTITY_FILE)) { console.error('Run tools/select-ship.mjs <SHIP_ID> first.'); process.exit(1); }
const id = JSON.parse(fs.readFileSync(IDENTITY_FILE, 'utf8'));

const run = (cmd, args) => {
    const r = spawnSync(cmd, args, { cwd: ROOT, stdio: 'inherit', shell: process.platform === 'win32' });
    if (r.status !== 0) process.exit(r.status ?? 1);
};
const org = id.identifier.split('.').slice(0, -1).join('.');
run('flutter', ['create', '--project-name', 'draft_survey', '--org', org, `--platforms=${platforms}`, '.']);

const edit = (file, fn) => {
    const f = path.join(ROOT, file);
    if (!fs.existsSync(f)) return;
    fs.writeFileSync(f, fn(fs.readFileSync(f, 'utf8')));
};

// Android: application id + launcher label (+ internet permission is in the debug manifest only, so add to main)
for (const g of ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
    edit(g, (s) => s.replace(/applicationId\s*=?\s*"[^"]*"/, (m) => m.replace(/"[^"]*"/, `"${id.identifier}"`))
                    .replace(/namespace\s*=?\s*"[^"]*"/, (m) => m.replace(/"[^"]*"/, `"${id.identifier}"`)));
}
edit('android/app/src/main/AndroidManifest.xml', (s) => {
    s = s.replace(/android:label="[^"]*"/, `android:label="${id.productName}"`);
    if (!s.includes('android.permission.INTERNET')) s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
    return s;
});
// NOTE: changing namespace requires MainActivity's package to match; rewrite it.
const kt = path.join(ROOT, 'android/app/src/main/kotlin');
if (fs.existsSync(kt)) {
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
    for (const f of walk(kt).filter((x) => x.endsWith('MainActivity.kt'))) {
        const body = fs.readFileSync(f, 'utf8').replace(/^package .*$/m, `package ${id.identifier}`);
        const dest = path.join(kt, ...id.identifier.split('.'), 'MainActivity.kt');
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.writeFileSync(dest, body);
        if (dest !== f) fs.rmSync(f);
    }
}
// Launcher icons from assets/branding/icons/android/mipmap-*
const iconSrc = path.join(ROOT, 'assets', 'branding', 'icons', 'android');
const res = path.join(ROOT, 'android', 'app', 'src', 'main', 'res');
if (fs.existsSync(iconSrc) && fs.existsSync(res)) fs.cpSync(iconSrc, res, { recursive: true });

// Windows: window title + exe name
edit('windows/runner/main.cpp', (s) => s.replace(/window\.Create\(L"[^"]*"/, `window.Create(L"${id.productName}"`));
edit('windows/CMakeLists.txt', (s) => s.replace(/set\(BINARY_NAME "[^"]*"\)/, 'set(BINARY_NAME "DraftSurvey")'));
const ico = path.join(ROOT, 'assets', 'branding', 'icons', 'icon.ico');
if (fs.existsSync(ico)) fs.copyFileSync(ico, path.join(ROOT, 'windows/runner/resources/app_icon.ico'));
console.log(`\nPlatforms ready for ${id.productName} (${id.identifier}).`);
