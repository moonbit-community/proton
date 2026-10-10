#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const cli = process.env.PROTON_REGISTRY_CLI ?? "proton_cli";
const tempRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "proton-scaffold-registry-"),
);
const projectDir = path.join(tempRoot, "todo");
const smokeEnv = { ...process.env, PROTON_NO_UPDATE_CHECK: "1" };
for (const name of ["PROTON_RUNTIME_ROOT", "PROTON_RUNTIME_STORE", "PROTON_HELPER_PATH", "PROTON_CEF_SETUP_BOOTSTRAP"]) {
  delete smokeEnv[name];
}
let succeeded = false;

function moduleVersion(relativePath) {
  const source = fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
  const match = source.match(/^version\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error(`${relativePath} is missing its module version`);
  }
  return match[1];
}

function run(command, args, options = {}) {
  console.log(`+ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? tempRoot,
    env: smokeEnv,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
    timeout: options.timeout ?? 300000,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function verifyInstalledCliVersion() {
  const expected = moduleVersion("cli/moon.mod");
  const output = run(cli, ["--version"], { capture: true }).trim();
  const match = output.match(/^proton_cli\s+(\S+)$/);
  if (!match) {
    throw new Error(`could not parse installed CLI version: ${output}`);
  }
  if (match[1] !== expected) {
    throw new Error(
      `registry smoke requires proton_cli ${expected}, installed ${match[1]}`,
    );
  }
}

function expectDependency(relativePath, moduleName, version) {
  const source = fs.readFileSync(path.join(projectDir, relativePath), "utf8");
  const declaration = `"${moduleName}@${version}"`;
  if (!source.includes(declaration)) {
    throw new Error(`${relativePath} is missing ${declaration}`);
  }
}

function verifyGeneratedDependencies() {
  expectDependency(
    "shared/moon.mod",
    "moonbit-community/proton_contract",
    moduleVersion("contract/moon.mod"),
  );
  expectDependency(
    "frontend/moon.mod",
    "moonbit-community/proton_client",
    moduleVersion("client/moon.mod"),
  );
  expectDependency(
    "frontend/moon.mod",
    "moonbit-community/proton_rabbita",
    moduleVersion("rabbita/moon.mod"),
  );
  expectDependency(
    "backend/moon.mod",
    "moonbit-community/proton",
    moduleVersion("proton/moon.mod"),
  );
  expectDependency(
    "backend/moon.mod",
    "moonbit-community/proton_contract",
    moduleVersion("contract/moon.mod"),
  );
  const backend = fs.readFileSync(
    path.join(projectDir, "backend/moon.mod"),
    "utf8",
  );
  if (backend.includes("bin-deps")) {
    throw new Error("backend/moon.mod must not depend on a CLI binary shim");
  }
  if (/proton_codegen|dev_build/.test(backend)) {
    throw new Error("the application scaffold must not require codegen");
  }
}

async function verifyRegistryCdp() {
  const consumer = path.join(tempRoot, "cdp-consumer");
  fs.mkdirSync(consumer);
  const asyncDependency = fs.readFileSync(path.join(repoRoot, "cdp/moon.mod"), "utf8")
    .match(/"moonbitlang\/async@[^"]+"/)[0];
  fs.writeFileSync(path.join(consumer, "moon.mod"), `name = "registry/cdp_smoke"
version = "0.0.0"
import { "moonbit-community/proton_cdp@${moduleVersion("cdp/moon.mod")}", ${asyncDependency} }
preferred_target = "native"
`);
  fs.writeFileSync(path.join(consumer, "moon.pkg"), `import {
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbit-community/proton_cdp/client",
  "moonbit-community/proton_cdp/page",
}
supported_targets = "+native"
options(is_main: true)
`);
  fs.writeFileSync(path.join(consumer, "main.mbt"), `///|
async fn main {
  @async.with_task_group(tasks => {
    let page = @page.Page::connect(tasks, @client.parse_cdp_target(@env.args()[1]))
    assert_eq(page.evaluate("1 + 1"), Json(2))
    println("Registry CDP evaluation passed")
  })
}
`);
  run("moon", ["update"], { cwd: consumer });
  run("moon", ["build", "--target", "native"], { cwd: consumer });
  const profile = path.join(consumer, "profile");
  const log = fs.openSync(path.join(consumer, "chrome.log"), "w");
  const browser = spawn(process.env.PROTON_REGISTRY_CHROME ?? "google-chrome", [
    "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
    "--no-first-run", "--no-default-browser-check", "about:blank",
  ], { stdio: ["ignore", log, log] });
  fs.closeSync(log);
  let launchError;
  browser.on("error", error => { launchError = error; });
  const stopped = new Promise(resolve => browser.on("close", resolve));
  try {
    const portFile = path.join(profile, "DevToolsActivePort");
    const deadline = Date.now() + 60000;
    while (!fs.existsSync(portFile)) {
      if (launchError) throw launchError;
      if (browser.exitCode !== null || Date.now() >= deadline) {
        throw new Error(`Chrome did not provide a CDP endpoint (exit=${browser.exitCode}); see ${consumer}/chrome.log`);
      }
      await sleep(100);
    }
    const [port, browserPath] = fs.readFileSync(portFile, "utf8").trim().split(/\r?\n/);
    run("moon", ["run", ".", "--target", "native", "--", `ws://127.0.0.1:${port}${browserPath}`], { cwd: consumer });
  } finally {
    browser.kill();
    await stopped;
  }
}

try {
  verifyInstalledCliVersion();
  if (process.platform === "linux") {
    run("appimagetool", ["--version"]);
  }
  run(cli, [
    "-C",
    tempRoot,
    "new",
    "todo",
    "--title",
    "Registry Todo",
    "--author",
    "registry_smoke",
    "--identifier",
    "dev.proton.registry-smoke",
    "--no-check",
    "--no-git",
    "-y",
  ]);
  verifyGeneratedDependencies();
  run(cli, ["-C", projectDir, "cef", "setup"], { timeout: 900000 });
  run("moon", ["check", "--target", "js,native", "--diagnostic-limit", "80"], {
    cwd: projectDir,
  });
  run(cli, ["-C", projectDir, "build"], { timeout: 900000 });
  const format = process.platform === "linux" ? "appimage" : "app";
  const packageArgs = ["-C", projectDir, "package", "--release", "--format", format];
  if (process.platform === "linux") {
    // The scaffold has no default icon; AppImage packaging requires a PNG.
    const icon = path.join(projectDir, "registry-smoke.png");
    fs.writeFileSync(icon, Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=",
      "base64",
    ));
    packageArgs.push("--icon", icon);
  }
  run(cli, [...packageArgs, "--dry-run"], { timeout: 900000 });
  run(cli, packageArgs, { timeout: 900000 });
  await verifyRegistryCdp();
  succeeded = true;
  console.log("Registry scaffold smoke passed.");
} finally {
  if (succeeded) {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } else {
    console.error(`Registry scaffold artifacts retained at ${tempRoot}`);
  }
}
