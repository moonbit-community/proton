import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
import net from 'node:net';
import test, { after } from 'node:test';
import { cefApiVersion, runtimeLayoutVersion, runtimeRequirements } from '../../../../cef_requirements.generated.mjs';
const here = path.dirname(fileURLToPath(import.meta.url));
const ffi = path.resolve(here, '..');
const identifiers = new Set();
after(() => {
  if (process.platform !== 'win32') for (const id of identifiers) {
    rmSync(endpoint(id), { force: true });
    rmSync(endpoint(id).replace(/\.sock$/, '.lock'), { force: true });
  }
});
const temp = mkdtempSync(path.join(tmpdir(), 'proton-instance-test-'));
after(() => rmSync(temp, { recursive: true, force: true }));
const platform = `${process.platform}-${process.arch}`;
const requirement = runtimeRequirements[platform];
const sdk = path.join(process.env.PROTON_RUNTIME_STORE || path.join(homedir(), '.proton/store'), platform,
  `cef-${requirement.sha256}-layout-${runtimeLayoutVersion}`, 'sdk');
const binary = path.join(temp, 'instance.exe');
const flags = [`CEF_API_VERSION=${cefApiVersion}`, 'PROTON_APP_INSTANCE_TIMEOUT_MS=1000'];
const sources = [path.join(ffi, 'src/proton_app_instance.c'), path.join(here, 'app_instance/harness.c')];
const includes = [path.join(ffi, 'include'), path.join(ffi, 'src'), sdk];
const build = process.platform === 'win32'
  ? spawnSync('cl', ['/nologo', '/std:c11', ...flags.map(x => '/D'+x), ...includes.map(x => '/I'+x), ...sources, '/Fe:'+binary, '/Fo:'+temp+path.sep, '/link', 'advapi32.lib', 'user32.lib'], { encoding: 'utf8' })
  : spawnSync(process.env.CC || 'cc', ['-pthread', ...flags.map(x => '-D'+x), ...includes.map(x => '-I'+x), ...sources, '-o', binary], { encoding: 'utf8' });
assert.equal(build.status, 0, `${build.error || ''}${build.stdout}${build.stderr}`);
function launch(t, id) {
  const child = spawn(binary, [id]);
  child.output = '';
  child.stdout.on('data', data => { child.output += data; });
  child.stderr.on('data', data => { child.output += data; });
  child.done = once(child, 'exit');
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    await child.done;
  });
  return child;
}
async function until(predicate, message, timeout = 4000) {
  const deadline = performance.now() + timeout;
  while (!predicate()) {
    assert.ok(performance.now() < deadline, message());
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
async function primary(t) {
  const id = `proton-test-${process.pid}-${crypto.randomUUID()}`;
  identifiers.add(id);
  const child = launch(t, id);
  await until(() => child.output.includes('RESULT 0 1'), () => child.output);
  return { child, id };
}
test('a stalled application loop cannot report successful forwarding', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  child.stdin.write('attach\n');
  await until(() => child.output.includes('ATTACH 0'), () => child.output);
  const secondary = launch(t, id);
  await until(() => secondary.exitCode !== null, () => secondary.output);
  assert.equal(secondary.exitCode, 1, secondary.output);
  assert.match(secondary.output, /confirm|timed out/);
});
async function command(child, text, response) {
  child.stdin.write(text+'\n');
  await until(() => child.output.includes(response), () => child.output);
}
async function accepted(t, owner, id, request = 1) {
  const child = launch(t, id);
  await until(() => owner.output.includes(`QUEUED ${request}\n`), () => owner.output);
  owner.stdin.write('pump\n');
  await until(() => child.exitCode !== null, () => child.output);
  assert.equal(child.exitCode, 0, child.output);
  assert.match(child.output, /RESULT 0 0/);
}
test('forwarding succeeds after the application loop accepts it', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  await command(child, 'attach', 'ATTACH 0');
  await accepted(t, child, id);
  await command(child, 'quit', 'DESTROY 0');
});
test('startup buffers an activation until a runtime is attached', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  const secondary = launch(t, id);
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(secondary.exitCode, null, secondary.output);
  await command(child, 'attach', 'ATTACH 0');
  await until(() => child.output.includes('QUEUED 1\n'), () => child.output);
  child.stdin.write('pump\n');
  await until(() => secondary.exitCode !== null, () => secondary.output);
  assert.equal(secondary.exitCode, 0, secondary.output);
});
test('stopping rejects pending and new activations without releasing ownership', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  await command(child, 'attach', 'ATTACH 0');
  const pending = launch(t, id);
  await until(() => child.output.includes('QUEUED 1\n'), () => child.output);
  await command(child, 'stop', 'STOPPED');
  await until(() => pending.exitCode !== null, () => pending.output);
  assert.equal(pending.exitCode, 1);
  assert.match(pending.output, /shutting down/);
  const later = launch(t, id);
  await until(() => later.exitCode !== null, () => later.output);
  assert.equal(later.exitCode, 1);
  assert.match(later.output, /shutting down/);
});
test('a detached runtime cannot return to startup buffering', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  await command(child, 'attach', 'ATTACH 0');
  await command(child, 'detach', 'DETACHED');
  const secondary = launch(t, id);
  await until(() => secondary.exitCode !== null, () => secondary.output);
  assert.equal(secondary.exitCode, 1);
  assert.match(secondary.output, /shutting down/);
});
test('an expired event cannot acknowledge a later connection', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  await command(child, 'attach', 'ATTACH 0');
  const expired = launch(t, id);
  await until(() => expired.exitCode !== null, () => expired.output);
  assert.equal(expired.exitCode, 1);
  await accepted(t, child, id, 2);
  assert.match(child.output, /ACCEPT 1 0/);
  assert.match(child.output, /ACCEPT 2 1/);
});
function endpoint(id) {
  let hash = 1469598103934665603n;
  for (const byte of Buffer.from(id)) hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 1099511628211n);
  return `/tmp/proton-${process.getuid()}/${hash.toString(16).padStart(16, '0')}.sock`;
}
for (const [name, bytes] of [['header', [0]], ['payload', [0, 0, 0, 10, 123]]]) {
test(`a partial ${name} expires and the listener serves the next client`, { skip: process.platform === 'win32', timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  await command(child, 'attach', 'ATTACH 0');
  const slow = net.createConnection(endpoint(id));
  t.after(() => slow.destroy());
  slow.on('error', () => {});
  const closed = once(slow, 'close');
  await once(slow, 'connect');
  slow.write(Buffer.from(bytes));
  let timer;
  try {
    await Promise.race([closed, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('partial client did not expire')), 3000); })]);
  } finally { clearTimeout(timer); }
  await accepted(t, child, id);
});
}
test('a frozen primary cannot block forwarding indefinitely', { skip: process.platform === 'win32', timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  child.kill('SIGSTOP');
  t.after(() => child.kill('SIGCONT'));
  const secondary = launch(t, id);
  await until(() => secondary.exitCode !== null, () => secondary.output);
  assert.equal(secondary.exitCode, 1);
  assert.match(secondary.output, /confirm|deadline/);
  child.kill('SIGCONT');
});
test('owner death permits reacquisition despite leftover endpoint files', { timeout: 10000 }, async t => {
  const { child, id } = await primary(t);
  child.kill('SIGKILL');
  await child.done;
  const next = launch(t, id);
  await until(() => next.output.includes('RESULT 0 1'), () => next.output);
  await command(next, 'quit', 'DESTROY 0');
});
