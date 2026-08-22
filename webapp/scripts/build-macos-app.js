#!/usr/bin/env node

const {copyFileSync, chmodSync, mkdirSync, rmSync} = require('node:fs');
const {join, resolve} = require('node:path');
const {spawnSync} = require('node:child_process');

const webappRoot = resolve(__dirname, '..');
const bundle = join(webappRoot, 'dist', 'Alas.app');
const contents = join(bundle, 'Contents');
const macOS = join(contents, 'MacOS');
const resources = join(contents, 'Resources');
const executable = join(macOS, 'Alas');
const moduleCache = join(webappRoot, 'dist', '.module-cache');

const run = (command, args) => {
  const result = spawnSync(command, args, {
    cwd: webappRoot,
    stdio: 'inherit',
    env: {...process.env, CLANG_MODULE_CACHE_PATH: moduleCache},
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
};

rmSync(bundle, {recursive: true, force: true});
mkdirSync(macOS, {recursive: true});
mkdirSync(resources, {recursive: true});

run('xcrun', [
  'clang',
  'native/main.m',
  '-fobjc-arc',
  '-O2',
  '-mmacosx-version-min=12.0',
  `-fmodules-cache-path=${moduleCache}`,
  '-framework', 'AppKit',
  '-framework', 'WebKit',
  '-o', executable,
]);

copyFileSync(join(webappRoot, 'native', 'Info.plist'), join(contents, 'Info.plist'));
copyFileSync(join(webappRoot, 'buildResources', 'icon.icns'), join(resources, 'AppIcon.icns'));
chmodSync(executable, 0o755);

run('plutil', ['-lint', join(contents, 'Info.plist')]);
run('codesign', ['--force', '--deep', '--sign', '-', bundle]);

console.log(`Native macOS application built at ${bundle}`);
