import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, existsSync, rmSync, unlinkSync, chmodSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
import test from 'node:test';

const here = path.dirname(fileURLToPath(import.meta.url));
function run(program, args, options = {}) {
  return spawnSync(program, args, { encoding: 'utf8', timeout: 30000, ...options });
}
function ok(result) {
  assert.equal(result.status, 0, `${result.error || ''}${result.stdout}${result.stderr}`);
}
function bundle(location, revision) {
  mkdirSync(path.join(location, 'Contents/MacOS'), { recursive: true });
  copyFileSync('/usr/bin/true', path.join(location, 'Contents/MacOS/app'));
  writeFileSync(path.join(location, 'Contents/Info.plist'), `<?xml version="1.0"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>app</string>
<key>CFBundleIdentifier</key><string>com.example.proton-cleanup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>ProtonUpdateRevision</key><string>${revision}</string></dict></plist>`);
  ok(run('codesign', ['--force', '--sign', '-', '--identifier', 'com.example.proton-cleanup', location]));
}

test('macOS retained update ownership and cleanup', { skip: process.platform !== 'darwin', timeout: 120000 }, async t => {
  const temp = mkdtempSync(path.join(tmpdir(), 'proton-update-test-'));
  t.after(() => rmSync(temp, { recursive: true, force: true }));
  const binary = path.join(temp, 'harness');
  ok(run(process.env.CC || 'cc', ['-I'+path.join(here, '../include'), path.join(here, 'update_cleanup/harness.c'), '-framework', 'CoreFoundation', '-framework', 'Security', '-o', binary]));
  let next = 0;
  function fixture() {
    const root = path.join(temp, String(next++));
    const app = path.join(root, 'dist/App.app');
    const store = path.join(root, 'dist/.App.app.proton-update');
    const archive = path.join(root, 'update.zip');
    bundle(app, 1);
    bundle(path.join(root, 'release/App.app'), 2);
    ok(run('/usr/bin/ditto', ['-c', '-k', '--keepParent', path.join(root, 'release/App.app'), archive]));
    const invoke = (command, extra = [], env = {}) => run(binary, [command, app, ...extra], { env: { ...process.env, ...env } });
    return { root, app, store, archive, invoke };
  }
  await t.test('retains the old bundle in a hidden owned directory until confirmation', () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    assert.ok(existsSync(path.join(f.store, 'previous.app/Contents/Info.plist')));
    ok(f.invoke('cleanup'));
    assert.ok(!existsSync(path.join(f.store, 'previous.app')));
    assert.ok(!existsSync(path.join(f.store, 'deleting.app')));
    ok(run('codesign', ['--verify', '--strict', f.app]));
  });
  for (const fault of ['interrupt', 'fail']) {
    await t.test(`resumes after deletion ${fault} without needing a valid bundle`, () => {
      const f = fixture();
      ok(f.invoke('install', [f.archive]));
      const result = f.invoke('cleanup', [], { PROTON_TEST_DELETE_FAULT: fault });
      assert.equal(result.status, fault === 'interrupt' ? 77 : 1, result.stdout);
      assert.ok(existsSync(path.join(f.store, 'deleting.app')));
      assert.ok(!existsSync(path.join(f.store, 'deleting.app/Contents/Info.plist')));
      ok(f.invoke('cleanup'));
      assert.ok(!existsSync(path.join(f.store, 'deleting.app')));
    });
  }
  for (const fault of ['before-transition', 'after-transition']) {
    await t.test(`recovers at the atomic cleanup transition: ${fault}`, () => {
      const f = fixture();
      ok(f.invoke('install', [f.archive]));
      const result = f.invoke('cleanup', [], { PROTON_TEST_DELETE_FAULT: fault });
      assert.equal(result.status, fault === 'before-transition' ? 1 : 77);
      const state = fault === 'before-transition' ? 'previous.app' : 'deleting.app';
      ok(run('codesign', ['--verify', '--strict', path.join(f.store, state)]));
      ok(f.invoke('cleanup'));
      assert.ok(!existsSync(path.join(f.store, state)));
    });
  }
  await t.test('does not follow links in retained state or bundle contents', () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    const outside = path.join(f.root, 'outside');
    mkdirSync(outside);
    writeFileSync(path.join(outside, 'keep'), 'untouched');
    symlinkSync(outside, path.join(f.store, 'previous.app/link'));
    ok(f.invoke('cleanup'));
    assert.equal(readFileSync(path.join(outside, 'keep'), 'utf8'), 'untouched');
    symlinkSync(outside, path.join(f.store, 'deleting.app'));
    assert.equal(f.invoke('cleanup').status, 1);
    assert.equal(readFileSync(path.join(outside, 'keep'), 'utf8'), 'untouched');
  });
  await t.test('does not discard a recovery copy of the same revision', () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    bundle(f.app, 1);
    ok(f.invoke('cleanup'));
    assert.ok(existsSync(path.join(f.store, 'previous.app/Contents/Info.plist')));
  });
  await t.test('restores the old app when installing the replacement fails', () => {
    const f = fixture();
    const result = f.invoke('install', [f.archive], { PROTON_TEST_INSTALL_FAILURE: '1' });
    assert.equal(result.status, 1, result.stdout);
    assert.match(readFileSync(path.join(f.app, 'Contents/Info.plist'), 'utf8'), /<string>1<\/string>/);
    assert.ok(!existsSync(path.join(f.store, 'previous.app')));
    ok(run('codesign', ['--verify', '--strict', f.app]));
    ok(f.invoke('install', [f.archive]));
  });
  await t.test('does not overwrite an unconfirmed or partially deleted previous update', () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    bundle(path.join(f.root, 'release/App.app'), 3);
    const nextArchive = path.join(f.root, 'next.zip');
    ok(run('/usr/bin/ditto', ['-c', '-k', '--keepParent', path.join(f.root, 'release/App.app'), nextArchive]));
    assert.equal(f.invoke('install', [nextArchive]).status, 1);
    assert.equal(f.invoke('cleanup', [], { PROTON_TEST_DELETE_FAULT: 'interrupt' }).status, 77);
    assert.equal(f.invoke('install', [nextArchive]).status, 1);
    ok(f.invoke('cleanup'));
    ok(f.invoke('install', [nextArchive]));
  });
  await t.test('continues to reject invalid signatures and downgrade revisions', () => {
    const f = fixture();
    writeFileSync(path.join(f.root, 'release/App.app/Contents/Info.plist'), 'tampered');
    ok(run('/usr/bin/ditto', ['-c', '-k', '--keepParent', path.join(f.root, 'release/App.app'), f.archive]));
    assert.equal(f.invoke('install', [f.archive]).status, 1);
    bundle(path.join(f.root, 'release/App.app'), 0);
    ok(run('/usr/bin/ditto', ['-c', '-k', '--keepParent', path.join(f.root, 'release/App.app'), f.archive]));
    assert.equal(f.invoke('install', [f.archive]).status, 1);
    assert.ok(!existsSync(f.store));
    ok(run('codesign', ['--verify', '--strict', f.app]));
  });
  await t.test('does not scan or claim historical sibling bundles', () => {
    const f = fixture();
    for (const suffix of ['.backup', '.previous-ABC123']) bundle(f.app+suffix, 0);
    ok(f.invoke('cleanup'));
    assert.ok(!existsSync(f.store));
    assert.ok(!existsSync(f.app+'.proton-update.lock'));
    assert.ok(existsSync(f.app+'.backup'));
    assert.ok(existsSync(f.app+'.previous-ABC123'));
  });
  await t.test('rejects a symlink or shared storage directory', () => {
    const f = fixture();
    const outside = path.join(f.root, 'outside');
    mkdirSync(outside);
    symlinkSync(outside, f.store);
    assert.equal(f.invoke('install', [f.archive]).status, 1);
    unlinkSync(f.store);
    mkdirSync(f.store, { mode: 0o755 });
    chmodSync(f.store, 0o755);
    assert.equal(f.invoke('install', [f.archive]).status, 1);
    ok(run('codesign', ['--verify', '--strict', f.app]));
  });
  await t.test('serializes installation and cleanup under the existing commit lock', async () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    const holder = spawn(binary, ['lock', f.app]);
    const done = once(holder, 'exit');
    t.after(() => holder.kill());
    await once(holder.stdout, 'data');
    try {
      assert.equal(f.invoke('cleanup').status, 1);
      assert.equal(f.invoke('install', [f.archive]).status, 1);
      assert.ok(existsSync(path.join(f.store, 'previous.app')));
    } finally {
      holder.stdin.end('\n');
      await done;
    }
    ok(f.invoke('cleanup'));
  });
  await t.test('Moon package discovery ignores partially deleted retained bundles', () => {
    const f = fixture();
    ok(f.invoke('install', [f.archive]));
    const pkg = path.join(f.store, 'previous.app/Contents/Resources/lib/core/prelude');
    mkdirSync(pkg, { recursive: true });
    writeFileSync(path.join(pkg, 'moon.pkg'), '');
    writeFileSync(path.join(pkg, 'bad.mbt'), 'THIS IS NOT VALID MOONBIT');
    writeFileSync(path.join(f.root, 'moon.mod'), 'name = "test/update_cleanup"\n');
    writeFileSync(path.join(f.root, 'moon.pkg'), '');
    ok(run('moon', ['check', '--target', 'native'], { cwd: f.root }));
    const result = f.invoke('cleanup', [], { PROTON_TEST_DELETE_FAULT: 'interrupt' });
    assert.equal(result.status, 77);
    ok(run('moon', ['check', '--target', 'native'], { cwd: f.root }));
    ok(f.invoke('cleanup'));
  });
});
