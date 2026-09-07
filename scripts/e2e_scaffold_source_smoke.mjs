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
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "proton-scaffold-e2e-"));
const projectDir = path.join(tempRoot, "todo");
const frontendDir = path.join(projectDir, "frontend");
const frontendDist = path.join(frontendDir, "dist");
const warrenCoordinate = "moonbit-community/warren@0.3.2";
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
    "backend/todo/backend_wbtest.mbt",
    "backend/todo/commands.mbt",
    "backend/todo/moon.pkg",
    "frontend/internal/query/README.md",
    "frontend/internal/query/moon.pkg",
    "frontend/internal/query/query.mbt",
    "frontend/internal/query/query_wbtest.mbt",
    "frontend/main/main.mbt",
    "frontend/main/model_wbtest.mbt",
    "frontend/main/moon.pkg",
    "frontend/moon.mod",
    "frontend/public/index.html",
    "frontend/public/styles.css",
    "proton.project.json",
    "moon.work",
    "shared/moon.mod",
    "shared/moon.pkg",
    "shared/todo_contract.mbt",
  ].sort();
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
    !backendMod.includes("bin-deps"),
    "generated backend must not depend on a CLI binary shim",
  );
  assert(
    !/dev_build|proton_codegen/.test(todoPackage + backendMod),
    "generated application must use explicit command bindings",
  );
}

function enableSecondWindow() {
  const file = path.join(projectDir, "backend", "app", "main.mbt");
  const source = fs.readFileSync(file, "utf8");
  const updated = source.replace(
    ".load_config()",
    '.add_window("secondary", "Todo E2E Secondary", @proton.AppEntry::Asset("frontend/dist/index.html"))\n  .load_config()',
  ).replace(
    ".commands(fn(registrar) raise { backend.register_commands(registrar) })",
    '.commands(fn(registrar) raise { backend.register_commands(registrar) }, targets=[@proton.RendererTarget::entry(), @proton.RendererTarget::entry(window="secondary")])',
  );
  assert(updated !== source, "could not enable the second validation window");
  fs.writeFileSync(file, updated);
}

function installDirectoryFixture() {
  const fixture = path.join(repoRoot, "scripts", "fixtures", "query_directory");
  const target = path.join(frontendDir, "directory");
  fs.mkdirSync(target);
  fs.copyFileSync(path.join(fixture, "main.mbt"), path.join(target, "main.mbt"));
  fs.copyFileSync(path.join(fixture, "directory_contract.mbt"), path.join(projectDir, "shared", "directory_contract.mbt"));
  const imports = fs.readFileSync(path.join(frontendDir, "main", "moon.pkg"), "utf8");
  fs.writeFileSync(path.join(target, "moon.pkg"), imports.replace('  "moonbit-community/proton_rabbita",\n', ''));
  const appPackage = path.join(projectDir, "backend", "app", "moon.pkg");
  fs.writeFileSync(appPackage, fs.readFileSync(appPackage, "utf8").replace("import {", 'import {\n  "moonbitlang/async/fs",\n  "e2e/todo_shared" @shared,'));
  const root = path.join(tempRoot, "directories");
  for (const name of ["alpha", "beta", "empty", "slow"]) fs.mkdirSync(path.join(root, name), {recursive:true});
  fs.writeFileSync(path.join(root, "alpha", "alpha.txt"), "alpha");
  fs.writeFileSync(path.join(root, "beta", "beta.txt"), "beta");
  fs.writeFileSync(path.join(root, "slow", "slow.txt"), "slow");
  const app = path.join(projectDir, "backend", "app", "main.mbt");
  fs.writeFileSync(app, fs.readFileSync(app, "utf8").replace(
    'backend.register_commands(registrar)',
    `backend.register_commands(registrar)
      registrar.bind(@shared.list_directory, (_context, directory) => {
        if directory == "slow" { @async.sleep(1000) }
        @fs.readdir(${JSON.stringify(root)} + "/" + directory, sort=true)
      })`,
  ));
}

function buildDirectoryFixture() {
  const output = run("moon", ["-C", "frontend", "run", "directory", "--target", "js", "--release", "--build-only"], {cwd:projectDir, capture:true}).trim();
  const artifacts = output.split("\n").filter(line => line.startsWith("{"))
    .map(line => JSON.parse(line)).find(value => Array.isArray(value.artifacts_path));
  const built = artifacts?.artifacts_path.find(file => file.endsWith(".js"));
  assert(built && isFile(built), `missing directory frontend output: ${output}`);
  const publicDir = path.join(frontendDir, "public");
  fs.copyFileSync(built, path.join(publicDir, "directory.js"));
  fs.writeFileSync(path.join(publicDir, "directory.html"), '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Directory browser</title><link rel="stylesheet" href="./styles.css"></head><body><main id="app"></main><script src="./directory.js"></script></body></html>');
}

function connectLocalSourceModules() {
  const localMembers = [
    "contract",
    "client",
    "rabbita",
    "config",
    "rsa",
    "updater",
    "sys/ffi",
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
}

function verifyPackagedApp() {
  const appDir = path.join(
    projectDir,
    "dist",
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
        if (message.method === "Runtime.exceptionThrown") console.error(JSON.stringify(message.params));
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
  try {
    await waitUntil(
      async () => (await client.evaluate(expression)) === true,
      description,
    );
  } catch (error) {
    throw new Error(`${error.message}\nPage: ${await client.evaluate("document.body.innerText")}`);
  }
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
        const initial = await invoke("app:list_todos", { query: "" });
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
        const createReply = await invoke("app:create_todo", {
          title: "Verify typed bridge",
        });
        const created = await invoke("app:list_todos", { query: "" });
        await new Promise((resolve) => setTimeout(resolve, 100));
        const createdBody = document.body.innerText;
        const completeReply = await invoke("app:set_todo_completed", {
          id: created.todos[0].id,
          completed: true,
        });
        const completed = await invoke("app:list_todos", { query: "" });
        const deleteReply = await invoke("app:delete_todo", {
          id: created.todos[0].id,
        });
        await new Promise((resolve) => setTimeout(resolve, 100));
        const deleted = await invoke("app:list_todos", { query: "" });
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
  if (staticServer) {
    return `http://127.0.0.1:${staticServer.address().port}/`;
  }
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
  assert(!state.body.includes("No todos yet.") && !state.body.includes("No matching todos."), "failed initial load must not display an empty result");
}

async function probeDirectoryBrowser(client) {
  const url = await client.evaluate('new URL("directory.html", location.href).href');
  await client.send("Page.navigate", {url});
  await waitForExpression(client, 'document.body.innerText.includes("alpha.txt")', "initial real directory read");
  await client.evaluate(`(() => {
    const core = window.__MoonBit__.core;
    const invoke = core.invokeJson.bind(core);
    window.__directoryReads = 0;
    window.__directoryAborts = 0;
    core.invokeJson = (route, raw, options) => {
      if (route === "app:list_directory") {
        window.__directoryReads++;
        options.signal.addEventListener("abort", () => window.__directoryAborts++);
      }
      return invoke(route, raw, options);
    };
  })()`);
  const click = label => client.evaluate(`Array.from(document.querySelectorAll("button")).find(button => button.textContent === ${JSON.stringify(label)}).click()`);
  await click("Open slow");
  await waitForExpression(client, 'document.body.innerText.includes("Loading slow") && document.body.innerText.includes("Directory: alpha") && document.body.innerText.includes("alpha.txt")', "retained data identifies its original directory");
  await click("Open beta");
  await waitForExpression(client, 'document.body.innerText.includes("beta.txt") && window.__directoryAborts === 1', "directory replacement cancels previous read");
  await sleep(1100);
  assert(await client.evaluate('!document.body.innerText.includes("slow.txt")'), "late directory response replaced current data");
  await click("Open missing");
  await waitForExpression(client, 'document.body.innerText.includes("Cannot read missing") && document.body.innerText.includes("Directory: beta")', "failed navigation preserves the previous directory");
  assert(await client.evaluate('!document.body.innerText.includes("Empty directory.")'), "failed directory read looks empty");
  const reads = await client.evaluate('window.__directoryReads');
  await sleep(150);
  assert(await client.evaluate('window.__directoryReads') === reads, "failure triggered an automatic retry loop");
  await click("Reload directory");
  await waitForExpression(client, `window.__directoryReads === ${reads + 1} && document.body.innerText.includes("Cannot read missing")`, "explicit directory retry");
  await click("Open empty");
  await waitForExpression(client, 'document.body.innerText.includes("Empty directory.") && !document.body.innerText.includes("Cannot read")', "successful empty directory");
  await click("Open slow");
  await waitForExpression(client, 'document.body.innerText.includes("Loading slow")', "pending directory before component disposal");
  await click("Close browser");
  await waitForExpression(client, 'document.body.innerText.includes("Directory browser closed.") && window.__directoryAborts === 2', "component disposal cancels its query");
  await sleep(1100);
  assert(await client.evaluate('!document.body.innerText.includes("slow.txt")'), "disposed query delivered late data");
  await click("Open browser");
  await waitForExpression(client, 'document.body.innerText.includes("alpha.txt")', "fresh component owns a fresh query");
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

function setFrontendPackageRevision(revision) {
  const indexPath = path.join(frontendDir, "public", "index.html");
  const source = fs.readFileSync(indexPath, "utf8");
  const updated = source.replace(
    /<body(?: data-package-revision="[^"]*")?>/,
    `<body data-package-revision=${JSON.stringify(revision)}>`,
  );
  assert(updated !== source, `could not set frontend package revision ${revision}`);
  fs.writeFileSync(indexPath, updated);
}

async function runPackagedAppSmoke(executable, expectedRevision) {
  const cdpPort = await choosePort(9322);
  const packagedEnv = {
    ...process.env,
    PROTON_NO_UPDATE_CHECK: "1",
    PROTON_REMOTE_DEBUGGING_PORT: String(cdpPort),
  };
  delete packagedEnv.PROTON_HELPER_PATH;
  delete packagedEnv.PROTON_RUNTIME_ROOT;
  delete packagedEnv.PROTON_MODE;
  appProcess = spawn(executable, [`--remote-debugging-port=${cdpPort}`], {
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
    await waitForExpression(
      client,
      `document.body.dataset.packageRevision === ${JSON.stringify(expectedRevision)}`,
      `packaged frontend revision ${expectedRevision}`,
    );
    await probeTodoBridge(client);
    await client.evaluate('document.querySelector("form").dispatchEvent(new Event("submit", {bubbles:true, cancelable:true}))');
    await waitForExpression(client, 'document.body.innerText.includes("Enter a non-empty title.")', "typed business rejection");
    await client.evaluate(`(() => {
      const input = document.querySelector('input[placeholder="What needs doing?"]');
      input.value = "Created through Rabbita";
      input.dispatchEvent(new Event("input", {bubbles:true}));
      document.querySelector("form").dispatchEvent(new Event("submit", {bubbles:true, cancelable:true}));
    })()`);
    await waitForExpression(client, 'document.body.innerText.includes("Created through Rabbita")', "Rabbita async write effect");
    await client.evaluate('document.querySelector(".delete-button").click()');
    await waitForExpression(client, '!document.body.innerText.includes("Created through Rabbita")', "Rabbita delete effect");
    const secondPage = await waitUntil(async () => {
      const response = await fetch("http://127.0.0.1:" + cdpPort + "/json/list");
      const pages = await response.json();
      return pages.find(target => target.type === "page" && target.id !== page.id &&
        target.webSocketDebuggerUrl && target.url.includes("index.html"));
    }, "the second Todo window");
    const second = new CdpClient(secondPage.webSocketDebuggerUrl);
    await second.open();
    try {
      await second.send("Runtime.enable");
      await waitForExpression(second, 'Boolean(window.__MoonBit__?.core?.invokeOp)', "second bridge");
      await client.evaluate('window.__MoonBit__.core.invokeOp("app:create_todo", {title:"Shared across windows"})', true);
      await waitForExpression(second, 'document.body.innerText.includes("Shared across windows")', "cross-window invalidation");
      await waitForExpression(client, 'document.body.innerText.includes("Shared across windows")', "initial list before delayed search");
      await client.evaluate(`(() => {
        const core = window.__MoonBit__.core;
        const original = core.invokeJson.bind(core);
        window.__searchAbortCount = 0;
        core.invokeJson = (route, raw, options) => {
          const result = original(route, raw, options);
          if (route === "app:list_todos" && JSON.parse(raw).query === "Shared") {
            options.signal.addEventListener("abort", () => window.__searchAbortCount++);
            return result.then(value => new Promise(resolve => setTimeout(() => resolve(value), 300)));
          }
          return result;
        };
        const input = document.querySelector('input[placeholder="Search todos"]');
        input.value = "Shared";
        input.dispatchEvent(new Event("input", {bubbles:true}));
      })()`);
      await sleep(50);
      assert(await client.evaluate('document.querySelectorAll(".todo-row").length > 0 && document.body.innerText.includes("Shared across windows")'), "refresh must retain the current list");
      await client.evaluate(`(() => {
        const input = document.querySelector('input[placeholder="Search todos"]');
        input.value = "no matches";
        input.dispatchEvent(new Event("input", {bubbles:true}));
      })()`);
      await sleep(400);
      await waitForExpression(client, 'window.__searchAbortCount > 0 && document.querySelectorAll(".todo-row").length === 0 && document.body.innerText.includes("No matching todos.")', "cancelled search cannot overwrite the latest query");
      await client.evaluate(`(() => {
        const input = document.querySelector('input[placeholder="Search todos"]');
        input.value = "";
        input.dispatchEvent(new Event("input", {bubbles:true}));
      })()`);
      await waitForExpression(client, 'document.body.innerText.includes("Shared across windows")', "reset search");
      await second.evaluate('(async () => { const data = await window.__MoonBit__.core.invokeOp("app:list_todos", {query:""}); await window.__MoonBit__.core.invokeOp("app:delete_todo", {id:data.todos[0].id}); })()', true);
      await waitForExpression(client, '!document.body.innerText.includes("Shared across windows")', "reverse cross-window invalidation");
    } finally { second.close(); }
    await probeDirectoryBrowser(client);
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
  run("moon", ["--version"], { capture: true });
  run("moonx", ["--target", "native", warrenCoordinate, "--help"], {
    capture: true,
  });

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
  run("moon", ["fmt", "--check"], { cwd: projectDir });
  connectLocalSourceModules();
  enableSecondWindow();
  installDirectoryFixture();
  run("moon", ["fmt"], { cwd: projectDir });
  localCli(["-C", projectDir, "cef", "setup"]);

  run("moon", ["check", "--target", "js,native", "--diagnostic-limit", "80"], { cwd: projectDir });
  run("moon", ["-C", "frontend", "test", "--target", "js"], { cwd: projectDir });
  run("moon", ["-C", "backend", "test", "todo", "--target", "native"], { cwd: projectDir });
  run("moon", ["fmt", "--check"], { cwd: projectDir });
  run(
    "moonx",
    [
      "--target",
      "native",
      warrenCoordinate,
      "build",
      "--browser-entry",
      "main",
    ],
    { cwd: frontendDir },
  );
  run(
    "moon",
    ["-C", "backend", "build", "app", "--target", "native", "--diagnostic-limit", "80"],
    { cwd: projectDir, env: runtimeEnv() },
  );
  buildDirectoryFixture();
  setFrontendPackageRevision("first");
  localCli(["-C", projectDir, "package", "--release", "--format", "app", "--sign"], {
    env: runtimeEnv({
      PROTON_MACOS_ALLOW_ADHOC: "1",
      PROTON_MACOS_SIGNING_IDENTITY: "-",
    }),
    timeout: 600000,
  });
  let packaged = verifyPackagedApp();
  await runPackagedAppSmoke(packaged.executable, "first");
  setFrontendPackageRevision("second");
  localCli(["-C", projectDir, "package", "--release", "--format", "app", "--sign"], {
    env: runtimeEnv({
      PROTON_MACOS_ALLOW_ADHOC: "1",
      PROTON_MACOS_SIGNING_IDENTITY: "-",
    }),
    timeout: 600000,
  });
  packaged = verifyPackagedApp();
  await runPackagedAppSmoke(packaged.executable, "second");
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
