#!/usr/bin/env node

// Validates the generated scaffold against this checkout's source modules.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const timeoutMs = Number(process.env.PROTON_SCAFFOLD_E2E_TIMEOUT_MS ?? "60000");
const nativeDist = path.resolve(
  process.env.PROTON_NATIVE_DIST ?? path.join(repoRoot, "native", "dist"),
);
const nativeBin = path.join(nativeDist, "bin");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "proton-scaffold-e2e-"));
const projectDir = path.join(tempRoot, "todo");
const frontendDir = path.join(projectDir, "frontend");
const frontendDist = path.join(frontendDir, "dist");
let appProcess = null;
let staticServer = null;
let succeeded = false;

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch {
    return false;
  }
}

function isDirectory(directory) {
  try {
    return fs.statSync(directory).isDirectory();
  } catch {
    return false;
  }
}

function run(command, args, options = {}) {
  console.log(`+ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    env: options.env ?? process.env,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
    timeout: options.timeout ?? 300000,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    const output = options.capture
      ? `\n${result.stdout ?? ""}${result.stderr ?? ""}`
      : "";
    fail(`${command} exited with status ${result.status}${output}`);
  }
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function runtimeEnv(extra = {}) {
  return {
    ...process.env,
    PATH: `${nativeBin}${path.delimiter}${process.env.PATH ?? ""}`,
    PROTON_NATIVE_DIST: nativeDist,
    PROTON_NO_UPDATE_CHECK: "1",
    ...extra,
  };
}

function localCli(args, options = {}) {
  return run(
    "moon",
    ["-C", path.join(repoRoot, "cli"), "run", ".", "--", ...args],
    options,
  );
}

function walkFiles(root, relative = "") {
  const files = [];
  for (const entry of fs.readdirSync(path.join(root, relative), {
    withFileTypes: true,
  })) {
    const child = path.join(relative, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(root, child));
    } else if (entry.isFile()) {
      files.push(child.split(path.sep).join("/"));
    }
  }
  return files.sort();
}

function verifyGeneratedTree() {
  const expected = [
    ".gitignore",
    "AGENTS.md",
    "README.md",
    "backend/app/main.mbt",
    "backend/app/moon.pkg",
    "backend/moon.mod",
    "backend/todo/backend.mbt",
    "backend/todo/commands.g.mbt",
    "backend/todo/commands.mbt",
    "backend/todo/moon.pkg",
    "frontend/main/main.mbt",
    "frontend/main/moon.pkg",
    "frontend/moon.mod",
    "frontend/public/index.html",
    "frontend/public/styles.css",
    "moon.proton",
    "moon.work",
    "shared/moon.mod",
    "shared/moon.pkg",
    "shared/todo_contract.mbt",
  ];
  const actual = walkFiles(projectDir);
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `generated file tree differs:\n${actual.join("\n")}`,
  );

  const backendMod = fs.readFileSync(
    path.join(projectDir, "backend", "moon.mod"),
    "utf8",
  );
  const todoPackage = fs.readFileSync(
    path.join(projectDir, "backend", "todo", "moon.pkg"),
    "utf8",
  );
  assert(
    backendMod.includes('"bin-deps": { "justjavac/proton_cli": "0.1.10" }'),
    "generated backend does not declare the Proton CLI binary dependency",
  );
  assert(
    todoPackage.includes(
      'command: "$mooncake_bin/proton_cli codegen $input -o $output"',
    ),
    "generated backend does not use its declared Proton CLI binary",
  );
}

function verifyCommittedCodegen() {
  const generated = path.join(
    projectDir,
    "backend",
    "todo",
    "commands.g.mbt",
  );
  const fresh = path.join(tempRoot, "commands.fresh.mbt");
  localCli([
    "codegen",
    path.join(projectDir, "backend", "todo", "commands.mbt"),
    "-o",
    fresh,
  ]);
  assert(
    fs.readFileSync(generated, "utf8") === fs.readFileSync(fresh, "utf8"),
    "generated commands.g.mbt is stale",
  );
}

function connectLocalSourceModules() {
  const localMembers = [
    "contract",
    "client",
    "rabbita",
    "config",
    "proton",
  ].map((name) => path.join(repoRoot, name));
  const work = [
    "members = [",
    '  "./shared",',
    '  "./frontend",',
    '  "./backend",',
    ...localMembers.map((member) => `  ${JSON.stringify(member)},`),
    "]",
    "",
  ].join("\n");
  fs.writeFileSync(path.join(projectDir, "moon.work"), work);

  const backendModPath = path.join(projectDir, "backend", "moon.mod");
  const backendMod = fs.readFileSync(backendModPath, "utf8");
  const withoutUnpublishedCli = backendMod.replace(
    '  "bin-deps": { "justjavac/proton_cli": "0.1.10" },\n',
    "",
  );
  assert(
    withoutUnpublishedCli !== backendMod,
    "could not remove the unpublished CLI dependency from the source smoke",
  );
  fs.writeFileSync(backendModPath, withoutUnpublishedCli);

  const todoPackagePath = path.join(projectDir, "backend", "todo", "moon.pkg");
  const todoPackage = fs.readFileSync(todoPackagePath, "utf8");
  const withoutDevBuild = todoPackage.replace(
    /\nrule\([\s\S]*?\n\)\n\ndev_build\([\s\S]*?\n\)\n/,
    "",
  );
  assert(
    withoutDevBuild !== todoPackage,
    "could not disable the unpublished CLI dev_build for the source smoke",
  );
  fs.writeFileSync(todoPackagePath, withoutDevBuild);
}

function verifyPackagedApp() {
  const appDir = path.join(
    projectDir,
    "target",
    "proton-dist",
    "Todo E2E.app",
  );
  assert(fs.existsSync(appDir), `packaged app is missing: ${appDir}`);
  for (const asset of ["index.html", "index.js", "styles.css"]) {
    assert(
      isFile(
        path.join(
          appDir,
          "Contents",
          "Resources",
          "frontend",
          "dist",
          asset,
        ),
      ),
      `packaged frontend asset is missing: ${asset}`,
    );
  }
  const executables = fs.readdirSync(path.join(appDir, "Contents", "MacOS"));
  assert(
    executables.length === 1,
    `expected one app executable, found: ${executables.join(", ")}`,
  );
  const helperNames = [
    "Todo E2E Helper",
    "Todo E2E Helper (Alerts)",
    "Todo E2E Helper (GPU)",
    "Todo E2E Helper (Plugin)",
    "Todo E2E Helper (Renderer)",
  ];
  for (const helperName of helperNames) {
    const helper = path.join(
      appDir,
      "Contents",
      "Frameworks",
      `${helperName}.app`,
    );
    assert(isDirectory(helper), `packaged helper is missing: ${helperName}`);
    assert(
      isFile(path.join(helper, "Contents", "MacOS", helperName)),
      `packaged helper executable is missing: ${helperName}`,
    );
    const plist = fs.readFileSync(
      path.join(helper, "Contents", "Info.plist"),
      "utf8",
    );
    assert(
      plist.includes(
        `<key>CFBundleExecutable</key><string>${helperName}</string>`,
      ),
      `packaged helper plist does not name its executable: ${helperName}`,
    );
  }
  return {
    appDir,
    executable: path.join(appDir, "Contents", "MacOS", executables[0]),
  };
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

async function choosePort(start) {
  for (let port = start; port < start + 200; port += 1) {
    if (await canBindPort(port)) {
      return port;
    }
  }
  fail(`no available port found from ${start}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function httpJson(url, requestTimeout = 2000) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, { timeout: requestTimeout }, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          reject(new Error(`GET ${url} returned ${response.statusCode}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on("timeout", () => request.destroy(new Error("request timed out")));
    request.on("error", reject);
  });
}

async function waitUntil(action, description, limit = timeoutMs) {
  const deadline = Date.now() + limit;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const value = await action();
      if (value) {
        return value;
      }
    } catch (error) {
      lastError = error;
    }
    await sleep(100);
  }
  const detail = lastError ? `: ${lastError.message}` : "";
  fail(`timed out waiting for ${description}${detail}`);
}

class CdpClient {
  constructor(url) {
    this.url = url;
    this.nextId = 1;
    this.pending = new Map();
    this.socket = null;
  }

  async open() {
    this.socket = new WebSocket(this.url);
    this.socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      const pending = this.pending.get(message.id);
      if (!pending) {
        return;
      }
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message));
      } else {
        pending.resolve(message.result);
      }
    });
    await new Promise((resolve, reject) => {
      this.socket.addEventListener("open", resolve, { once: true });
      this.socket.addEventListener("error", reject, { once: true });
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    const response = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.socket.send(JSON.stringify({ id, method, params }));
    return response;
  }

  sendNoWait(method, params = {}) {
    this.socket.send(
      JSON.stringify({ id: this.nextId++, method, params }),
    );
  }

  async evaluate(expression, awaitPromise = false) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise,
      returnByValue: true,
    });
    if (result.exceptionDetails) {
      fail(`CDP evaluation failed: ${JSON.stringify(result.exceptionDetails)}`);
    }
    return result.result?.value;
  }

  close() {
    this.socket?.close();
  }
}

async function waitForPage(cdpPort) {
  return await waitUntil(async () => {
    const targets = await httpJson(`http://127.0.0.1:${cdpPort}/json/list`);
    return targets.find(
      (target) =>
        target.type === "page" &&
        target.title === "Todo E2E" &&
        target.webSocketDebuggerUrl,
    );
  }, "the Todo E2E page");
}

async function waitForExpression(client, expression, description) {
  await waitUntil(
    async () => (await client.evaluate(expression)) === true,
    description,
  );
}

async function probeTodoBridge(client) {
  await waitForExpression(
    client,
    `Boolean(
      window.__MoonBit__?.core?.invokeOp &&
      window.__MoonBit__?.events?.onJson
    )`,
    "the typed application bridge",
  );
  const result = await client.evaluate(
    `(
      async () => {
        const invoke = window.__MoonBit__.core.invokeOp;
        const events = [];
        const unsubscribe = window.__MoonBit__.events.onJson(
          "app:todos_changed",
          (payload) => events.push(JSON.parse(payload)),
        );
        const initial = await invoke("app:list_todos", null);
        let remoteFailure;
        try {
          await invoke("app:create_todo", null);
        } catch (error) {
          remoteFailure = {
            name: error && error.name,
            code: error && error.code,
            message: error && error.message,
          };
        }
        const created = await invoke("app:create_todo", {
          title: "Verify typed bridge",
        });
        await new Promise((resolve) => setTimeout(resolve, 100));
        const createdBody = document.body.innerText;
        const completed = await invoke("app:set_todo_completed", {
          id: created.todos[0].id,
          completed: true,
        });
        const deleted = await invoke("app:delete_todo", {
          id: created.todos[0].id,
        });
        await new Promise((resolve) => setTimeout(resolve, 100));
        unsubscribe();
        return {
          initial,
          created,
          completed,
          deleted,
          events,
          createdBody,
          remoteFailure,
        };
      }
    )()`,
    true,
  );
  assert(
    result.initial.version === 0 && result.initial.todos.length === 0,
    `unexpected initial snapshot: ${JSON.stringify(result.initial)}`,
  );
  assert(
    result.remoteFailure?.name === "ProtonBridgeError" &&
      result.remoteFailure?.code === "op_failed" &&
      result.remoteFailure?.message ===
        "invalid payload for op app:create_todo",
    `remote failure code was not preserved: ${JSON.stringify(result.remoteFailure)}`,
  );
  assert(
    result.created.version === 1 &&
      result.created.todos[0]?.title === "Verify typed bridge",
    `unexpected create snapshot: ${JSON.stringify(result.created)}`,
  );
  assert(
    result.completed.version === 2 &&
      result.completed.todos[0]?.completed === true,
    `unexpected complete snapshot: ${JSON.stringify(result.completed)}`,
  );
  assert(
    result.deleted.version === 3 && result.deleted.todos.length === 0,
    `unexpected delete snapshot: ${JSON.stringify(result.deleted)}`,
  );
  assert(
    result.events.map((event) => event.version).join(",") === "1,2,3",
    `unexpected live events: ${JSON.stringify(result.events)}`,
  );
  assert(
    result.createdBody.includes("Verify typed bridge") &&
      result.createdBody.includes("Revision 1"),
    `Rabbita view did not receive the live snapshot:\n${result.createdBody}`,
  );
}

function contentType(file) {
  if (file.endsWith(".html")) return "text/html; charset=utf-8";
  if (file.endsWith(".js")) return "text/javascript; charset=utf-8";
  if (file.endsWith(".css")) return "text/css; charset=utf-8";
  return "application/octet-stream";
}

async function startStaticFrontend() {
  staticServer = http.createServer((request, response) => {
    const requestPath = new URL(request.url, "http://127.0.0.1").pathname;
    const relative = requestPath === "/"
      ? "index.html"
      : decodeURIComponent(requestPath.slice(1));
    const file = path.resolve(frontendDist, relative);
    if (
      !file.startsWith(`${path.resolve(frontendDist)}${path.sep}`) ||
      !isFile(file)
    ) {
      response.writeHead(404);
      response.end("Not found");
      return;
    }
    response.writeHead(200, { "content-type": contentType(file) });
    response.end(fs.readFileSync(file));
  });
  await new Promise((resolve, reject) => {
    staticServer.once("error", reject);
    staticServer.listen(0, "127.0.0.1", resolve);
  });
  return `http://127.0.0.1:${staticServer.address().port}/`;
}

async function probeBridgeUnavailable(client) {
  const url = await startStaticFrontend();
  await client.send("Page.navigate", { url });
  await waitForExpression(
    client,
    `(
      document.readyState !== "loading" &&
      location.href === ${JSON.stringify(url)} &&
      document.body.innerText.includes("The Proton bridge is unavailable")
    )`,
    "the ordinary-browser BridgeUnavailable state",
  );
  const state = await client.evaluate(
    `({
      hasBridge: Boolean(window.__MoonBit__?.core?.invokeOp),
      body: document.body.innerText,
    })`,
  );
  assert(state.hasBridge === false, "ordinary HTTP page unexpectedly has a bridge");
}

function collectOutput(child) {
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });
  return () => output;
}

async function waitForExit(child, output) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return { code: child.exitCode, signal: child.signalCode };
  }
  return await Promise.race([
    new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolve({ code, signal }));
    }),
    sleep(timeoutMs).then(() => {
      fail(`packaged app did not exit after close\n${output()}`);
    }),
  ]);
}

function processLinesForProject() {
  const result = spawnSync("ps", ["-axo", "pid=,command="], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`ps failed: ${result.stderr}`);
  }
  return result.stdout
    .split("\n")
    .filter((line) => line.includes(projectDir));
}

async function waitForNoProjectProcesses() {
  await waitUntil(
    () => processLinesForProject().length === 0,
    "all packaged app and helper processes to exit",
    10000,
  );
}

async function closeApplication(cdpPort) {
  const version = await httpJson(`http://127.0.0.1:${cdpPort}/json/version`);
  assert(
    version.webSocketDebuggerUrl,
    "CDP browser endpoint does not expose a websocket",
  );
  const browser = new CdpClient(version.webSocketDebuggerUrl);
  await browser.open();
  browser.sendNoWait("Browser.close");
  await sleep(250);
  browser.close();
}

async function terminateApp() {
  if (!appProcess || appProcess.exitCode !== null || appProcess.signalCode !== null) {
    return;
  }
  const signal = (name) => {
    try {
      appProcess.kill(name);
    } catch (error) {
      if (error.code !== "ESRCH") {
        throw error;
      }
    }
  };
  signal("SIGTERM");
  await Promise.race([
    new Promise((resolve) => appProcess.once("exit", resolve)),
    sleep(3000),
  ]);
  if (appProcess.exitCode === null && appProcess.signalCode === null) {
    signal("SIGKILL");
  }
}

async function runPackagedAppSmoke(executable) {
  const cdpPort = await choosePort(9322);
  const logPath = path.join(tempRoot, "proton-native.log");
  const packagedEnv = {
    ...process.env,
    PROTON_NATIVE_LOG: logPath,
    PROTON_NO_UPDATE_CHECK: "1",
    PROTON_REMOTE_DEBUGGING_PORT: String(cdpPort),
  };
  delete packagedEnv.PROTON_HELPER_PATH;
  delete packagedEnv.PROTON_NATIVE_DIST;
  delete packagedEnv.PROTON_RUNTIME_ROOT;
  delete packagedEnv.PROTON_DEV;
  delete packagedEnv.PROTON_MODE;
  appProcess = spawn(executable, [], {
    cwd: projectDir,
    env: packagedEnv,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const output = collectOutput(appProcess);
  const page = await Promise.race([
    waitForPage(cdpPort),
    new Promise((_, reject) => {
      appProcess.once("exit", (code, signal) => {
        reject(
          new Error(
            `packaged app exited before its page opened: code=${code} signal=${signal}\n${output()}`,
          ),
        );
      });
    }),
  ]);
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await probeTodoBridge(client);
    await probeBridgeUnavailable(client);
    await closeApplication(cdpPort);
  } finally {
    client.close();
  }
  const exit = await waitForExit(appProcess, output);
  assert(
    exit.code === 0,
    `packaged app exited abnormally: code=${exit.code} signal=${exit.signal}\n${output()}`,
  );
  await waitForNoProjectProcesses();
}

async function main() {
  if (process.platform !== "darwin") {
    fail("the scaffold package and lifecycle smoke currently requires macOS");
  }
  assert(isDirectory(nativeBin), `native runtime is missing: ${nativeBin}`);
  run("moon", ["--version"], { capture: true });
  run("warren", ["--help"], { capture: true });

  localCli([
    "-C",
    tempRoot,
    "new",
    "todo",
    "--title",
    "Todo E2E",
    "--author",
    "e2e",
    "--identifier",
    "dev.proton.scaffold-e2e",
    "--no-check",
    "--no-git",
    "-y",
  ]);
  verifyGeneratedTree();
  verifyCommittedCodegen();
  run("moon", ["fmt", "--check"], { cwd: projectDir });
  connectLocalSourceModules();

  run("moon", ["check", "--target", "js,native", "--diagnostic-limit", "80"], { cwd: projectDir });
  run("moon", ["fmt", "--check"], { cwd: projectDir });
  run("warren", ["build"], { cwd: frontendDir });
  run(
    "moon",
    ["-C", "backend", "build", "app", "--target", "native", "--diagnostic-limit", "80"],
    { cwd: projectDir, env: runtimeEnv() },
  );
  localCli(["-C", projectDir, "package", "--target", "app", "--sign"], {
    env: runtimeEnv({
      PROTON_MACOS_ALLOW_ADHOC: "1",
      PROTON_MACOS_SIGNING_IDENTITY: "-",
    }),
    timeout: 600000,
  });
  const packaged = verifyPackagedApp();
  await runPackagedAppSmoke(packaged.executable);
  succeeded = true;
  console.log("Scaffold E2E passed.");
}

try {
  await main();
} finally {
  if (staticServer) {
    await new Promise((resolve) => {
      staticServer.close(resolve);
      staticServer.closeAllConnections?.();
    });
  }
  await terminateApp();
  if (succeeded) {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } else {
    console.error(`Scaffold E2E artifacts retained at ${tempRoot}`);
  }
}
