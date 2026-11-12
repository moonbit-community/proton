import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

if (process.platform !== 'darwin') throw new Error('Requires a macOS graphical session.');
assert(process.argv.slice(2).every(arg => arg === '--other-space'), 'Unknown option');
const root = fileURLToPath(new URL('../../', import.meta.url));
const output = mkdtempSync(join(tmpdir(), 'proton-occlusion-regression-'));
console.log(`Artifacts: ${output}`);
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed`);
}
run('moon', ['-C', 'e2e', 'build', 'repro_occlusion', '--target', 'native']);
run('moon', ['install', '--path', 'proton/internal/cef_process', '--bin', join(output, 'subprocess')]);
run('swiftc', [join(root, 'e2e/repro_occlusion/capture.swift'), '-o', join(output, 'capture')]);
const binary = resolve(root, '_build/native/debug/build/moonbit-community/proton/e2e/repro_occlusion/repro_occlusion.exe');
const results = [];
const children = new Set();
function launch(command, args, options = {}) {
  const child = spawn(command, args, { detached: true, stdio: ['pipe', 'pipe', 'pipe'], ...options });
  children.add(child);
  return child;
}
function kill(child) {
  try { process.kill(-child.pid, 'SIGKILL'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; }
  children.delete(child);
}
function cleanup() { for (const child of children) kill(child); }
process.once('SIGINT', () => { cleanup(); process.exit(130); });
process.once('SIGTERM', () => { cleanup(); process.exit(143); });
async function until(probe, label) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const value = await probe();
    if (value) return value;
    await sleep(100);
  }
  throw new Error(`Timed out: ${label}`);
}

try {
  for (const enabled of [false, true]) {
    const name = enabled ? 'enabled' : 'default';
    const commandFile = join(output, `${name}-command`);
    writeFileSync(commandFile, '');
    const helper = launch(join(output, 'capture'), []);
    const replies = new Map();
    let ready;
    let token = 0;
    helper.stderr.on('data', data => process.stderr.write(data));
    createInterface({ input: helper.stdout }).on('line', line => {
      const message = JSON.parse(line);
      if (message.ready) ready = message;
      else replies.set(message.token, message);
    });
    await until(() => ready, 'capture helper startup');
    assert(ready.permission, 'Screen Recording permission is required for the capture helper');
    async function native(command, values = {}) {
      const id = ++token;
      helper.stdin.write(JSON.stringify({ command, token: id, ...values }) + '\n');
      const reply = await until(() => replies.get(id), `native ${command}`);
      replies.delete(id);
      assert(!reply.error, reply.error);
      return reply;
    }
    const app = launch(binary, enabled ? [] : ['--default'], {
      cwd: root,
      env: { ...process.env, PROTON_HEADLESS: '0', PROTON_REMOTE_DEBUGGING_PORT: '0',
        PROTON_SUBPROCESS_PATH: join(output, 'subprocess/cef_process'), PROTON_OCCLUSION_COMMAND: commandFile },
    });
    let log = '';
    for (const pipe of [app.stdout, app.stderr]) pipe.on('data', data => {
      log += data;
      writeFileSync(join(output, `${name}.log`), log);
    });
    const endpoint = await until(() => /DevTools listening on (ws:\/\/[^\s]+)/.exec(log)?.[1], 'DevTools endpoint');
    const targets = await until(async () => {
      const list = await (await fetch(`http://${new URL(endpoint).host}/json/list`)).json();
      return list.find(target => target.type === 'page');
    }, 'page target');
    const socket = new WebSocket(targets.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
    let sequence = 0;
    const pending = new Map();
    socket.onmessage = event => {
      const message = JSON.parse(event.data);
      if (message.id) pending.get(message.id)?.(message);
    };
    async function evaluate(expression) {
      const id = ++sequence;
      const response = new Promise(resolve => pending.set(id, resolve));
      socket.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
      let timer;
      try {
        const reply = await Promise.race([response, new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error('Runtime.evaluate timed out')), 10000);
        })]);
        assert(!reply.error && !reply.result.exceptionDetails, JSON.stringify(reply));
        return reply.result.result.value;
      } finally { clearTimeout(timer); pending.delete(id); }
    }
    await until(() => evaluate('typeof readState === "function"'), 'page load');
    async function capture(phase) {
      return native('capture', { pid: app.pid, path: join(output, `${name}-${phase}.png`) });
    }
    function checkColor(capture, rgb) {
      // Display profiles can transform pure CSS primaries. Require the expected
      // dominant channel, distinguishing both phases from the blue background.
      const index = rgb.indexOf(1);
      assert(capture.rgb[index] > 0.7 && capture.rgb.every((channel, i) =>
        i === index || capture.rgb[index] - channel > 0.35), JSON.stringify(capture));
    }
    async function sample(phase, color, expected, placement) {
      await evaluate(`paintMarker(${JSON.stringify(color)})`);
      const before = await evaluate('readState()');
      await sleep(1800); // Includes Chromium's delayed occlusion update; not a production wait.
      const image = await capture(phase);
      const after = await evaluate('readState()');
      results.push({ name, phase, before, after, image });
      writeFileSync(join(output, 'result.json'), JSON.stringify(results, null, 2) + '\n');
      if (placement === 'covered') assert(image.covered && image.onscreen, 'Target must be completely covered');
      if (placement === 'other-space') assert(!image.onscreen, 'Target must be off the active Space');
      if (placement) {
        assert.notEqual(image.frontmostPid, app.pid, 'Capture must not activate the target');
        assert.equal(after.focused, false, 'Page must not gain simulated focus');
        assert.equal(after.visibility, enabled ? 'visible' : 'hidden');
      }
      if (enabled || !placement) {
        checkColor(image, expected);
        assert(after.frames > before.frames, 'New frames must be rendered');
      }
      console.log(`${name}: ${phase} passed`);
    }
    await native('uncover', { pid: app.pid });
    await until(async () => (await native('state', { pid: app.pid })).onscreen &&
      await evaluate('document.visibilityState === "visible" && framesSeen > 0'), 'initial native visibility');
    await sample('visible', 'red', [1, 0, 0]);
    await native('cover', { pid: app.pid });
    await sample('covered-red', 'red', [1, 0, 0], 'covered');
    await sample('covered-green', 'lime', [0, 1, 0], 'covered');
    if (process.argv.includes('--other-space')) {
      await native('fullscreen');
      await until(async () => !(await native('state', { pid: app.pid })).onscreen, 'cover entering another Space');
      await sample('other-space-red', 'red', [1, 0, 0], 'other-space');
      await sample('other-space-green', 'lime', [0, 1, 0], 'other-space');
      await native('fullscreen');
      await until(async () => (await native('state', { pid: app.pid })).onscreen, 'return from cover Space');
    }
    await native('uncover', { pid: app.pid });
    function nativeState() {
      // The fixture writes through the public WindowHandle queries.
      try { return JSON.parse(readFileSync(commandFile + '.state', 'utf8')); }
      catch (error) { if (error.code === 'ENOENT' || error instanceof SyntaxError) return null; throw error; }
    }
    for (const [command, restore] of [['minimize', 'restore'], ['hide', 'show']]) {
      writeFileSync(commandFile, command);
      const state = await until(() => {
        const state = nativeState();
        return state?.command === command && (command === 'minimize' ? state.minimized : !state.visible) && state;
      }, command);
      await sleep(1800);
      results.push({ name, phase: command, native: state, page: await evaluate('readState()') });
      writeFileSync(join(output, 'result.json'), JSON.stringify(results, null, 2) + '\n');
      writeFileSync(commandFile, restore);
      await until(() => {
        const state = nativeState();
        return state?.command === restore && !state.minimized && state.visible;
      }, restore);
      await until(() => evaluate('document.visibilityState === "visible"'), restore);
    }
    await sample('restored', 'lime', [0, 1, 0]);
    socket.close();
    await native('quit');
    kill(helper);
    kill(app);
  }
  console.log('PASS: native captures contain fresh pixels without simulated focus.');
} finally { cleanup(); }
