import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { mkdtempSync, openSync, closeSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.platform !== 'darwin') throw new Error('This reproduction requires macOS.');
const root = fileURLToPath(new URL('../../', import.meta.url));
const output = mkdtempSync(join(tmpdir(), 'proton-fullscreen-close-'));
console.log(`Artifacts: ${output}`);
function moon(args) {
  const result = spawnSync('moon', args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`moon ${args.join(' ')} failed`);
}
moon(['-C', 'e2e', 'build', 'repro_fullscreen_close', '--target', 'native']);
moon(['install', '--path', 'proton/internal/cef_process', '--bin', join(output, 'helper')]);
const binary = resolve(root, '_build/native/debug/build/moonbit-community/proton/e2e/repro_fullscreen_close/repro_fullscreen_close.exe');
const log = join(output, 'app.log');
const fd = openSync(log, 'w');
const child = spawn(binary, process.argv.includes('--direct-close') ? ['--direct-close'] : [], {
  cwd: root,
  detached: true,
  env: { ...process.env, PROTON_HEADLESS: '0', PROTON_HELPER_PATH: join(output, 'helper/cef_process'), PROTON_REMOTE_DEBUGGING_PORT: '0' },
  stdio: ['ignore', fd, fd],
});
closeSync(fd);
const exit = new Promise((resolve, reject) => {
  child.once('exit', (code, signal) => resolve({ code, signal }));
  child.once('error', reject);
});
function stopChildGroup() {
  try { process.kill(-child.pid, 'SIGKILL'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; }
}
process.once('SIGINT', stopChildGroup);
process.once('SIGTERM', stopChildGroup);
let timer;
try {
  // A separate process group makes cleanup independent of window/CEF shutdown.
  const result = await Promise.race([
    exit,
    new Promise(resolve => { timer = setTimeout(() => resolve(null), 20000); }),
  ]);
  const rows = execFileSync('ps', ['-axo', 'pid=,ppid=,pgid=,command='], { encoding: 'utf8' })
    .trim().split('\n').map(line => /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/.exec(line))
    .filter(row => row && Number(row[3]) === child.pid)
    .map(row => ({ pid: Number(row[1]), ppid: Number(row[2]), command: row[4] }));
  const text = readFileSync(log, 'utf8');
  const summary = {
    mode: process.argv.includes('--direct-close') ? 'direct-close' : 'fullscreen-round-trip',
    exit: result,
    normalExitMarker: text.includes('REPRO: application exited normally'),
    matchingError: text.includes('runtime failed during poll event (-2): window is not initialized'),
    remainingBeforeCleanup: rows,
  };
  writeFileSync(join(output, 'result.json'), JSON.stringify(summary, null, 2) + '\n');
  console.log(text);
  console.log(JSON.stringify(summary, null, 2));
  const passed = summary.normalExitMarker && result?.code === 0 && rows.length === 0 && !summary.matchingError;
  console.log(passed ? 'PASS: application and helpers exited.' : 'FAIL: inspect app.log and result.json; cleanup follows.');
  process.exitCode = passed ? 0 : 1;
} finally {
  clearTimeout(timer);
  stopChildGroup();
  await exit;
  process.removeListener('SIGINT', stopChildGroup);
  process.removeListener('SIGTERM', stopChildGroup);
}
