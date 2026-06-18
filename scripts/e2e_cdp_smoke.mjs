#!/usr/bin/env node
import { spawn } from "node:child_process";
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const timeoutMs = Number(process.env.LEPUS_CDP_E2E_TIMEOUT_MS ?? "30000");

const defaultScenarios = [
  "01_run",
  "01_tauri_like_helloworld",
  "02_local",
  "03_remote",
  "04_user_agent",
  "05_alert",
  "06_onload",
  "07_inject_js",
  "08_eval",
  "09_dispatch",
  "10_bind",
  "11_multi_window",
  "12_embed",
  "14_beforeunload",
  "15_close",
  "17_extension",
  "18_extension_fs",
  "19_app_fs",
  "20_app_desktop",
  "21_app_shell",
  "22_app_config",
  "23_ops_runtime",
  "24_app_multi_window",
  "25_app_system",
  "26_app_path",
  "27_app_notification",
  "28_app_tray",
  "29_app_global_hotkey",
  "33_app_auto_launch",
  "34_app_keepawake",
  "35_app_microphone",
  "37_cef_mvp",
  "38_async_extension_add",
  "39_sync_async_extensions",
  "40_event_broadcast",
  "41_app_commands",
  "42_attribute_codegen_commands",
  "43_cef_bind_smoke",
];

const scenarios = process.argv.slice(2).length > 0
  ? process.argv.slice(2)
  : defaultScenarios;

let cachedCefEnv = null;

const directScenarios = new Map([
  ["09_dispatch", { mustInclude: null }],
  ["43_cef_bind_smoke", { mustInclude: "[\"ok\"]" }],
]);

const startupScenarios = new Map([
  ["05_alert", { aliveAfterMs: 2000 }],
]);

function resolveCefRoot() {
  if (process.env.LEPUS_CEF_ROOT) {
    return process.env.LEPUS_CEF_ROOT;
  }
  const cache = path.join(repoRoot, ".cef-cache");
  if (!existsSync(cache)) {
    throw new Error("LEPUS_CEF_ROOT is unset and .cef-cache does not exist; run node ./scripts/setup_cef.mjs first.");
  }
  const candidates = readdirSync(cache)
    .filter((name) => name.startsWith("cef_binary_") && name.includes("windows64"))
    .map((name) => path.join(cache, name))
    .filter((candidate) => existsSync(path.join(candidate, "Release", "libcef.dll")));
  if (candidates.length === 0) {
    throw new Error("LEPUS_CEF_ROOT is unset and no extracted Windows CEF binary was found in .cef-cache.");
  }
  return candidates.sort().at(-1);
}

function ensureCefSubprocess(env) {
  const configured = env.LEPUS_CEF_SUBPROCESS_PATH;
  if (configured && existsSync(configured)) {
    return configured;
  }
  const build = spawnSync("moon", ["build", "src/cef_process", "--target", "native"], {
    cwd: repoRoot,
    env,
    stdio: "inherit",
  });
  if (build.status !== 0) {
    throw new Error("failed to build src/cef_process");
  }
  const exe = path.join(
    repoRoot,
    "_build",
    "native",
    "debug",
    "build",
    "justjavac",
    "lepus",
    "cef_process",
    "cef_process.exe",
  );
  if (!existsSync(exe)) {
    throw new Error(`CEF subprocess executable was not created: ${exe}`);
  }
  return exe;
}

function cefEnv() {
  if (cachedCefEnv) {
    return cachedCefEnv;
  }
  const cefRoot = resolveCefRoot();
  const env = {
    ...process.env,
    LEPUS_CEF_ROOT: cefRoot,
  };
  env.LEPUS_CEF_SUBPROCESS_PATH = ensureCefSubprocess(env);
  cachedCefEnv = env;
  return env;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function reservePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function terminateTree(child) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return;
  }
  if (process.platform === "win32") {
    await new Promise((resolve) => {
      spawn("taskkill", ["/pid", String(child.pid), "/t", "/f"], {
        stdio: "ignore",
      }).once("exit", resolve);
    });
  } else {
    child.kill("SIGTERM");
  }
}

function run(command, args, options = {}) {
  const child = spawn(command, args, {
    cwd: repoRoot,
    env: { ...process.env, ...options.env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });
  return { child, output: () => output };
}

async function waitForExit(child, timeout, label) {
  return await Promise.race([
    new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolve({ code, signal }));
    }),
    sleep(timeout).then(() => {
      throw new Error(`${label} timed out after ${timeout}ms`);
    }),
  ]);
}

async function runScenario(name) {
  const directScenario = directScenarios.get(name);
  if (directScenario) {
    await runDirectScenario(name, directScenario);
    return;
  }

  const startupScenario = startupScenarios.get(name);
  if (startupScenario) {
    await runStartupScenario(name, startupScenario);
    return;
  }

  const port = await reservePort();
  const baseEnv = cefEnv();
  const app = run("moon", ["-C", "examples", "run", name, "--target", "native"], {
    env: { ...baseEnv, LEPUS_CEF_REMOTE_DEBUGGING_PORT: String(port) },
  });

  try {
    await sleep(1000);
    const probe = run("moon", ["-C", "e2e", "run", "test", "--target", "native"], {
      env: {
        ...baseEnv,
        MBT_CDP_TARGET: String(port),
        MBT_LEPUS_E2E_SCENARIO: name,
        MBT_LEPUS_E2E_TIMEOUT_MS: String(timeoutMs),
      },
    });
    try {
      const exit = await waitForExit(probe.child, timeoutMs + 15000, `CDP probe ${name}`);
      const probeOutput = probe.output().trim();
      if (
        exit.code !== 0 ||
        !probeOutput.includes(`CDP e2e passed: ${name}`) ||
        probeOutput.includes(" FAILED: ") ||
        probeOutput.includes("Failure(")
      ) {
        throw new Error(
          `CDP probe failed for ${name}\n\nProbe output:\n${probeOutput}\n\nApp output:\n${app.output().trim()}`,
        );
      }
      console.log(probeOutput || `CDP e2e passed: ${name}`);
    } catch (error) {
      await terminateTree(probe.child);
      throw error;
    }
  } finally {
    await terminateTree(app.child);
  }
}

async function runStartupScenario(name, expectation) {
  const app = run("moon", ["-C", "examples", "run", name, "--target", "native"], {
    env: cefEnv(),
  });
  try {
    const exitOrAlive = await Promise.race([
      new Promise((resolve, reject) => {
        app.child.once("error", reject);
        app.child.once("exit", (code, signal) => resolve({ code, signal }));
      }),
      sleep(expectation.aliveAfterMs).then(() => null),
    ]);
    const output = app.output().trim();
    if (exitOrAlive !== null || output.includes("Failure(")) {
      throw new Error(
        `startup scenario failed for ${name}\n\nOutput:\n${output}`,
      );
    }
    console.log(`startup e2e passed: ${name}`);
  } finally {
    await terminateTree(app.child);
  }
}

async function runDirectScenario(name, expectation) {
  const app = run("moon", ["-C", "examples", "run", name, "--target", "native"], {
    env: cefEnv(),
  });
  try {
    const exit = await waitForExit(app.child, timeoutMs + 15000, `direct scenario ${name}`);
    const output = app.output().trim();
    if (
      exit.code !== 0 ||
      output.includes("Failure(") ||
      (expectation.mustInclude && !output.includes(expectation.mustInclude))
    ) {
      throw new Error(
        `direct scenario failed for ${name}\n\nOutput:\n${output}`,
      );
    }
    console.log(`direct e2e passed: ${name}`);
  } catch (error) {
    await terminateTree(app.child);
    throw error;
  }
}

for (const scenario of scenarios) {
  await runScenario(scenario);
}
