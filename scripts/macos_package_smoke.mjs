#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const exampleName = "47_dev_extension_js";
const productName = "Proton Dev Extension JS";
const executableName = "proton-dev-extension-js";
const exampleDir = path.join(repoRoot, "examples", exampleName);
const distDir = path.join(exampleDir, "target", "proton-dist");
const appPath = path.join(distDir, `${productName}.app`);
const archivePath = `${appPath}.zip`;
const timeoutMs = Number(
  process.env.PROTON_MACOS_PACKAGE_SMOKE_TIMEOUT_MS ?? "30000",
);
const shutdownTimeoutMs = Number(
  process.env.PROTON_MACOS_PACKAGE_SMOKE_SHUTDOWN_TIMEOUT_MS ?? "5000",
);
let appProcess = null;
let appProcessClosed = false;
let appLog = null;
let appSpawnError = null;
let tempDir = null;

function fail(message) {
  throw new Error(message);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env: options.env ?? process.env,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) {
    fail(`failed to run ${command}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
    fail(
      `${command} exited with code ${result.status}${output ? `\n${output}` : ""}`,
    );
  }
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function requirePath(target, instruction) {
  if (!fs.existsSync(target)) {
    fail(`missing ${target}\n${instruction}`);
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function canBindPort(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => resolve(false));
    server.listen(port, "127.0.0.1", () => {
      server.close(() => resolve(true));
    });
  });
}

async function chooseCdpPort() {
  const requested = Number(
    process.env.PROTON_MACOS_PACKAGE_SMOKE_CDP_PORT ?? "9387",
  );
  for (let port = requested; port < requested + 80; port += 1) {
    if (await canBindPort(port)) {
      return port;
    }
  }
  fail(`no available CDP port found starting at ${requested}`);
}

function readJson(url) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        if (response.statusCode !== 200) {
          reject(new Error(`HTTP ${response.statusCode}`));
          return;
        }
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.once("error", reject);
  });
}

async function waitForPage(port) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    if (appSpawnError) {
      fail(`failed to launch packaged app: ${appSpawnError.message}`);
    }
    if (appProcess.exitCode !== null) {
      fail(`packaged app exited early with code ${appProcess.exitCode}`);
    }
    try {
      const targets = await readJson(`http://127.0.0.1:${port}/json/list`);
      const page = targets.find((target) => target.type === "page");
      if (page) {
        return page;
      }
    } catch (error) {
      lastError = error;
    }
    await delay(200);
  }
  fail(`timed out waiting for packaged app CDP${lastError ? `: ${lastError}` : ""}`);
}

function childProcessCommands(parentPid) {
  const pgrep = spawnSync("pgrep", ["-P", String(parentPid)], {
    encoding: "utf8",
  });
  if (pgrep.status === 1) {
    return [];
  }
  if (pgrep.error || pgrep.status !== 0) {
    fail(`failed to inspect helper processes for ${parentPid}`);
  }
  return pgrep.stdout
    .split(/\r?\n/)
    .filter(Boolean)
    .map((pid) => ({
      pid: Number(pid),
      command: run("ps", ["-p", pid, "-o", "command="], { capture: true }).trim(),
    }));
}

function processExists(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitForExit(child, timeout = shutdownTimeoutMs) {
  if (
    child.exitCode !== null ||
    child.signalCode !== null ||
    (child === appProcess && appProcessClosed)
  ) {
    return true;
  }
  return await new Promise((resolve) => {
    let settled = false;
    const finish = (exited) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      child.off("exit", onExit);
      child.off("close", onExit);
      child.off("error", onError);
      resolve(exited);
    };
    const onExit = () => finish(true);
    const onError = () => finish(true);
    const timer = setTimeout(() => finish(false), timeout);
    child.once("exit", onExit);
    child.once("close", onExit);
    child.once("error", onError);
  });
}

async function stopAppProcess() {
  if (
    !appProcess ||
    appProcessClosed ||
    appProcess.exitCode !== null ||
    appProcess.signalCode !== null
  ) {
    return;
  }
  appProcess.kill("SIGTERM");
  if (await waitForExit(appProcess)) {
    return;
  }
  appProcess.kill("SIGKILL");
  if (!(await waitForExit(appProcess, 2000))) {
    fail(`packaged app process ${appProcess.pid} did not terminate`);
  }
}

async function waitForHelpersToExit(helpers) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (helpers.every(({ pid }) => !processExists(pid))) {
      return;
    }
    await delay(100);
  }
  fail("CEF helper processes did not exit with the packaged app");
}

function verifyBundle() {
  const contents = path.join(appPath, "Contents");
  const helper = path.join(
    contents,
    "Frameworks",
    `${productName} Helper.app`,
  );
  const targets = [
    path.join(
      contents,
      "Resources",
      "proton",
      "Frameworks",
      "Chromium Embedded Framework.framework",
    ),
    ...["libEGL.dylib", "libGLESv2.dylib", "libvk_swiftshader.dylib", "cef_process"].map(
      (name) => path.join(contents, "Resources", "proton", "bin", name),
    ),
    path.join(contents, "Resources", "proton", "lib", "libproton.dylib"),
    helper,
    path.join(contents, "MacOS", executableName),
    appPath,
  ];
  for (const target of targets) {
    requirePath(target, "the macOS package layout is incomplete");
    run("codesign", ["--verify", "--strict", "--verbose=2", target]);
  }
  run("codesign", [
    "--verify",
    "--deep",
    "--strict",
    "--verbose=2",
    appPath,
  ]);
  run("plutil", [
    "-lint",
    path.join(contents, "Info.plist"),
    path.join(helper, "Contents", "Info.plist"),
    path.join(contents, "Resources", "proton.entitlements"),
  ]);
  const infoPlist = path.join(contents, "Info.plist");
  const plistExpectations = new Map([
    ["CFBundleIdentifier", "com.justjavac.proton.dev-extension-js"],
    ["CFBundleShortVersionString", "0.1.0"],
    ["CFBundleVersion", "0.1.0"],
  ]);
  for (const [key, expected] of plistExpectations) {
    const actual = run(
      "plutil",
      ["-extract", key, "raw", "-o", "-", infoPlist],
      { capture: true },
    ).trim();
    if (actual !== expected) {
      fail(`unexpected ${key}: ${actual}`);
    }
  }
  const icon = spawnSync(
    "plutil",
    ["-extract", "CFBundleIconFile", "raw", "-o", "-", infoPlist],
    { encoding: "utf8" },
  );
  if (icon.status === 0) {
    fail("CFBundleIconFile was declared without a configured .icns icon");
  }
  for (const target of [appPath, helper]) {
    const entitlements = run("codesign", ["-d", "--entitlements", "-", target], {
      capture: true,
    });
    for (const key of [
      "com.apple.security.cs.allow-jit",
      "com.apple.security.cs.allow-unsigned-executable-memory",
      "com.apple.security.cs.disable-library-validation",
    ]) {
      if (!entitlements.includes(key)) {
        fail(`missing ${key} in ad-hoc entitlements for ${target}`);
      }
    }
  }
  const archiveCheck = run("unzip", ["-t", archivePath], { capture: true });
  if (!archiveCheck.includes("No errors detected in compressed data")) {
    fail("zip integrity output did not confirm success");
  }
  const leftovers = fs
    .readdirSync(distDir)
    .filter(
      (name) =>
        name.endsWith(".staging.app") ||
        name.endsWith(".backup") ||
        name.endsWith(".notary.zip"),
    );
  if (leftovers.length > 0) {
    fail(`temporary package artifacts remain: ${leftovers.join(", ")}`);
  }
}

async function launchBundle() {
  const cdpPort = await chooseCdpPort();
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "proton-macos-package-smoke-"));
  run("ditto", ["-x", "-k", archivePath, tempDir]);
  const extractedApp = path.join(tempDir, `${productName}.app`);
  const executable = path.join(
    extractedApp,
    "Contents",
    "MacOS",
    executableName,
  );
  appLog = path.join(tempDir, "app.log");
  appProcessClosed = false;
  appSpawnError = null;
  const logFd = fs.openSync(appLog, "w");
  let logOpen = true;
  const closeLog = () => {
    if (logOpen) {
      fs.closeSync(logFd);
      logOpen = false;
    }
  };
  appProcess = spawn(executable, [], {
    cwd: tempDir,
    env: {
      ...process.env,
      PROTON_REMOTE_DEBUGGING_PORT: String(cdpPort),
    },
    stdio: ["ignore", logFd, logFd],
  });
  appProcess.once("spawn", closeLog);
  appProcess.once("close", () => {
    appProcessClosed = true;
    closeLog();
  });
  appProcess.once("error", (error) => {
    appSpawnError = error;
    appProcessClosed = true;
    closeLog();
  });
  const page = await waitForPage(cdpPort);
  const expectedPage = "/Contents/Resources/frontend/dist/index.html";
  if (!page.url.includes(expectedPage)) {
    fail(`packaged page URL is outside the bundle: ${page.url}`);
  }
  const helpers = childProcessCommands(appProcess.pid);
  if (helpers.length !== 3) {
    fail(`expected 3 CEF helper processes, found ${helpers.length}`);
  }
  const helperExecutable = `${productName} Helper.app/Contents/MacOS/cef_process`;
  if (helpers.some(({ command }) => !command.includes(helperExecutable))) {
    fail("a CEF helper process is not using the nested Helper.app executable");
  }
  console.log(`CDP page: ${page.url}`);
  console.log(`CEF helpers: ${helpers.length}`);
  await stopAppProcess();
  await waitForHelpersToExit(helpers);
}

async function cleanup() {
  await stopAppProcess();
  if (tempDir) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function main() {
  if (process.platform !== "darwin") {
    fail("macOS package smoke requires a macOS host");
  }
  requirePath(
    path.join(repoRoot, ".proton", "runtime.json"),
    "run `moon -C cli run . -- -C .. cef setup` first",
  );
  requirePath(
    path.join(exampleDir, "frontend", "node_modules"),
    "run `npm ci` in examples/47_dev_extension_js/frontend first",
  );
  run(
    "moon",
    [
      "-C",
      "cli",
      "run",
      ".",
      "--",
      "-C",
      "../examples",
      "package",
      exampleName,
      "--config",
      `${exampleName}/moon.proton`,
      "--sign",
      "--target",
      "app",
      "--target",
      "zip",
    ],
    {
      env: {
        ...process.env,
        PROTON_MACOS_ALLOW_ADHOC: "1",
        PROTON_MACOS_SIGNING_IDENTITY: "-",
      },
    },
  );
  requirePath(appPath, "proton_cli package did not create the app bundle");
  requirePath(archivePath, "proton_cli package did not create the zip archive");
  verifyBundle();
  await launchBundle();
  console.log("[OK] macOS ad-hoc package smoke passed");
}

try {
  await main();
} catch (error) {
  if (appLog && fs.existsSync(appLog)) {
    const log = fs.readFileSync(appLog, "utf8").trim();
    if (log) {
      console.error(log);
    }
  }
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
} finally {
  try {
    await cleanup();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
