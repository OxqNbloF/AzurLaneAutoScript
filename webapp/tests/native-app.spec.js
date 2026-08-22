const assert = require('node:assert');
const {existsSync, readFileSync} = require('node:fs');
const {join, resolve} = require('node:path');
const {spawnSync} = require('node:child_process');

const bundle = resolve(__dirname, '../dist/Alas.app');
const executable = join(bundle, 'Contents/MacOS/Alas');
const plist = join(bundle, 'Contents/Info.plist');

assert.ok(existsSync(executable), 'native Alas executable is missing');
assert.ok(existsSync(plist), 'Info.plist is missing');
assert.ok(!readFileSync(plist, 'utf8').toLowerCase().includes('electron'), 'bundle metadata still references Electron');

const validation = spawnSync('plutil', ['-lint', plist], {encoding: 'utf8'});
assert.strictEqual(validation.status, 0, validation.stderr || validation.stdout);

const libraries = spawnSync('otool', ['-L', executable], {encoding: 'utf8'});
assert.strictEqual(libraries.status, 0, libraries.stderr || libraries.stdout);
assert.ok(!libraries.stdout.toLowerCase().includes('electron'), 'native executable links Electron');

const expectedRoot = resolve(__dirname, '../..');
const rootResolution = spawnSync(executable, ['--resolve-root'], {
  cwd: '/',
  encoding: 'utf8',
  timeout: 5000,
  env: {...process.env, ALAS_PATH: ''},
});
assert.strictEqual(rootResolution.status, 0, rootResolution.stderr || 'root lookup failed');
assert.strictEqual(rootResolution.signal, null, 'root lookup timed out');
assert.strictEqual(rootResolution.stdout.trim(), expectedRoot, 'native app resolved the wrong Alas root');

console.log('Native macOS bundle verification passed.');
