#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const timeoutMs = Number(process.env.PROTON_BRIDGE_E2E_TIMEOUT_MS ?? "60000");
const requestedCdpPort = process.env.PROTON_BRIDGE_E2E_CDP_PORT
  ? Number(process.env.PROTON_BRIDGE_E2E_CDP_PORT)
  : null;
let cdpPort = requestedCdpPort ?? 9222;
const scenarios = process.argv.slice(2).length > 0
  ? process.argv.slice(2)
  : ["41_app_commands"];

function fail(message) {
  console.error(message);
  process.exit(1);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function canBindPort(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => {
      resolve(false);
    });
    server.listen(port, "0.0.0.0", () => {
      server.close(() => {
        resolve(true);
      });
    });
  });
}

async function chooseCdpPort() {
  if (requestedCdpPort !== null) {
    if (await canBindPort(requestedCdpPort)) {
      cdpPort = requestedCdpPort;
      return;
    }
    fail(`requested CDP port is not available: ${requestedCdpPort}`);
  }
  for (let candidate = cdpPort; candidate < cdpPort + 80; candidate += 1) {
    if (await canBindPort(candidate)) {
      if (candidate !== cdpPort) {
        console.log(`CDP port ${cdpPort} is busy; using ${candidate}`);
      }
      cdpPort = candidate;
      return;
    }
  }
  fail(`no available CDP port found starting at ${cdpPort}`);
}

function ensureSupportedScenario(name) {
  if (
    name !== "38_async_extension_add" &&
    name !== "39_sync_async_extensions" &&
    name !== "40_event_broadcast" &&
    name !== "41_app_commands" &&
    name !== "42_attribute_codegen_commands" &&
    name !== "45_bridge_multi_window" &&
    name !== "46_asset_sidecar_resources"
  ) {
    fail(`Unsupported bridge smoke scenario: ${name}`);
  }
}

function supportsMoonBitE2eScenario(name) {
  return name === "41_app_commands";
}

function activeRuntimeDist() {
  const manifestPath = path.join(repoRoot, ".proton", "runtime.json");
  if (fs.existsSync(manifestPath)) {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    if (typeof manifest.dist === "string" && manifest.dist.length > 0) {
      return path.resolve(repoRoot, manifest.dist);
    }
  }
  return path.join(repoRoot, "native", "dist");
}

function pathEnvWithNativeRuntime() {
  const runtimeDist = activeRuntimeDist();
  const binDir = path.join(runtimeDist, "bin");
  if (!fs.existsSync(binDir)) {
    fail(
      [
        `Native runtime bin directory does not exist: ${binDir}`,
        "Run proton_cli cef setup or build and install native first.",
      ].join("\n"),
    );
  }
  const key = process.platform === "win32" ? "Path" : "PATH";
  const currentPath = process.env[key] ?? process.env.PATH ?? "";
  return {
    ...process.env,
    [key]: `${binDir}${path.delimiter}${currentPath}`,
    PROTON_NATIVE_DIST: runtimeDist,
    PROTON_NATIVE_LOG: path.join(repoRoot, "target", "proton-native.log"),
    PROTON_REMOTE_DEBUGGING_PORT: String(cdpPort),
  };
}

function ensureE2eWorkspaceMember() {
  const e2eMod = path.join(repoRoot, "e2e", "moon.mod");
  if (!fs.existsSync(e2eMod)) {
    console.warn("e2e module is not present; running self-contained CDP smoke only.");
    return false;
  }
  const workPath = path.join(repoRoot, "moon.work");
  if (!fs.existsSync(workPath)) {
    fail("e2e module is present, but moon.work is missing");
  }
  const work = fs.readFileSync(workPath, "utf8");
  if (!/"\.\/e2e"/.test(work) && !/'\.\/e2e'/.test(work)) {
    fail("e2e module must be listed in moon.work before running e2e smoke");
  }
  return true;
}

function removeIfExists(filePath) {
  try {
    fs.rmSync(filePath, { force: true });
  } catch {
    // Best-effort cleanup only.
  }
}

function httpJson(url, timeout = 3000) {
  return new Promise((resolve, reject) => {
    const request = http.get(url, { timeout }, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          reject(new Error(`GET ${url} returned ${response.statusCode}: ${body}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on("timeout", () => {
      request.destroy(new Error(`GET ${url} timed out`));
    });
    request.on("error", reject);
  });
}

async function waitForCdpEndpoint() {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      await httpJson(`http://127.0.0.1:${cdpPort}/json/version`);
      return;
    } catch (error) {
      lastError = error;
      await sleep(250);
    }
  }
  throw new Error(`CDP endpoint did not start on ${cdpPort}: ${lastError?.message ?? "timeout"}`);
}

async function waitForPageTarget() {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const targets = await httpJson(`http://127.0.0.1:${cdpPort}/json/list`);
    const page = targets.find((target) =>
      target.type === "page" &&
      (target.url === "proton://app/" || target.title === "MoonBit App Commands")
    );
    if (page?.webSocketDebuggerUrl) {
      return page;
    }
    await sleep(250);
  }
  throw new Error("CDP page target for 41_app_commands was not found");
}

async function waitForPageTargetsByTitle(titles) {
  const expected = new Set(titles);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const targets = await httpJson(`http://127.0.0.1:${cdpPort}/json/list`);
    const found = new Map();
    for (const target of targets) {
      if (
        target.type === "page" &&
        expected.has(target.title) &&
        target.webSocketDebuggerUrl
      ) {
        found.set(target.title, target);
      }
    }
    if (found.size === expected.size) {
      return titles.map((title) => found.get(title));
    }
    await sleep(250);
  }
  throw new Error(`CDP page targets were not found: ${titles.join(", ")}`);
}

async function waitForPageTargetByTitle(title) {
  const [page] = await waitForPageTargetsByTitle([title]);
  return page;
}

async function waitForExit(child, output, description) {
  if (child.exitCode !== null || child.signalCode !== null) {
    if (child.exitCode !== 0) {
      throw new Error(
        `${description} exited with code=${child.exitCode} signal=${child.signalCode}\n${output()}`,
      );
    }
    return { code: child.exitCode, signal: child.signalCode };
  }
  const exit = await Promise.race([
    new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolve({ code, signal }));
    }),
    sleep(timeoutMs).then(() => {
      throw new Error(`${description} did not exit after ${timeoutMs}ms\n${output()}`);
    }),
  ]);
  if (exit.code !== 0) {
    throw new Error(`${description} exited with code=${exit.code} signal=${exit.signal}\n${output()}`);
  }
  return exit;
}

async function waitForNativeLog(predicate, description) {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const deadline = Date.now() + timeoutMs;
  let log = "";
  while (Date.now() < deadline) {
    log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
    if (predicate(log)) {
      return log;
    }
    await sleep(100);
  }
  throw new Error(`timed out waiting for native log: ${description}\n${log}`);
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
      if (message.id && this.pending.has(message.id)) {
        const { resolve, reject } = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) {
          reject(new Error(`${message.error.message}: ${JSON.stringify(message.error)}`));
        } else {
          resolve(message.result);
        }
      }
    });
    await new Promise((resolve, reject) => {
      this.socket.addEventListener("open", resolve, { once: true });
      this.socket.addEventListener("error", reject, { once: true });
    });
  }

  send(method, params = {}) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("CDP websocket is not open");
    }
    const id = this.nextId++;
    const message = JSON.stringify({ id, method, params });
    const response = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.socket.send(message);
    return response;
  }

  sendNoWait(method, params = {}) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return;
    }
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, method, params }));
  }

  async evaluate(expression, awaitPromise = false) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise,
      returnByValue: true,
    });
    if (result.exceptionDetails) {
      throw new Error(JSON.stringify(result.exceptionDetails));
    }
    return result.result?.value;
  }

  close() {
    if (this.socket) {
      this.socket.close();
    }
  }
}

async function waitForBridge(client) {
  await waitForExpression(
    client,
    "Boolean(window.__MoonBit__?.core?.invokeOp)",
    "window.__MoonBit__.core.invokeOp",
  );
}

async function waitForExpression(client, expression, description) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const ready = await client.evaluate(expression);
      if (ready === true) {
        return;
      }
    } catch (error) {
      lastError = error;
    }
    await sleep(100);
  }
  const suffix = lastError ? `: ${lastError.message}` : "";
  throw new Error(`timed out waiting for ${description}${suffix}`);
}

async function runCdpProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTarget();
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForBridge(client);
    const result = await client.evaluate(
      `(
        async () => {
          const invoke = window.__MoonBit__?.core?.invokeOp;
          const out = {
            url: location.href,
            title: document.title,
            hasBridge: typeof invoke === "function",
          };
          out.ping = await invoke("ext:app/ping", { name: "proton" });
          out.sum = await invoke("ext:app/slowAdd", {
            left: 20,
            right: 22,
            delay_ms: 50,
          });
          try {
            await invoke("ext:app/unknown", {});
            out.unknownRejected = false;
          } catch (error) {
            out.unknownRejected = true;
            out.unknownMessage = String(error && error.message ? error.message : error);
          }
          try {
            await invoke("ext:app/fail", {
              message: "Failure crossed command boundary",
            });
            out.failRejected = false;
          } catch (error) {
            out.failRejected = true;
            out.failMessage = String(error && error.message ? error.message : error);
          }
          try {
            await invoke("ext:app/ping", {
              oversized: "x".repeat(1048577),
            });
            out.largePayloadRejected = false;
          } catch (error) {
            out.largePayloadRejected = true;
            out.largePayloadMessage = String(error && error.message ? error.message : error);
          }
          return out;
        }
      )()`,
      true,
    );
    assertProbeResult(result);
    const queueFull = await runQueueFullProbe(client);
    const reload = await runReloadProbe(client);
    const nonProton = await runNonProtonProbe(client);
    return { ...result, queueFull, reload, nonProton };
  } finally {
    client.close();
  }
}

async function runMultiWindowRoutingProbe() {
  await waitForCdpEndpoint();
  const [pageA, pageB] = await waitForPageTargetsByTitle([
    "Bridge Multi A",
    "Bridge Multi B",
  ]);
  const clientA = new CdpClient(pageA.webSocketDebuggerUrl);
  const clientB = new CdpClient(pageB.webSocketDebuggerUrl);
  await Promise.all([clientA.open(), clientB.open()]);
  try {
    await Promise.all([
      clientA.send("Runtime.enable"),
      clientB.send("Runtime.enable"),
    ]);
    await Promise.all([waitForBridge(clientA), waitForBridge(clientB)]);
    const expression = (delayMs) => `(
      async () => {
        const invoke = window.__MoonBit__?.core?.invokeOp;
        const label = window.__bridgeMultiLabel;
        const response = await invoke("ext:multi/identify", {
          label,
          delay_ms: ${delayMs},
        });
        return {
          url: location.href,
          title: document.title,
          label,
          hasBridge: typeof invoke === "function",
          response,
        };
      }
    )()`;
    const resultA = clientA.evaluate(expression(220), true);
    const resultB = clientB.evaluate(expression(20), true);
    const [a, b] = await Promise.all([resultA, resultB]);
    const result = {
      a: { targetId: pageA.id, ...a },
      b: { targetId: pageB.id, ...b },
    };
    assertMultiWindowRoutingProbeResult(result);
    return result;
  } finally {
    clientA.close();
    clientB.close();
  }
}

async function runAsyncAddProxyProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTargetByTitle("MoonBit Async Add Extension");
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd)",
      "window.__MoonBit__.add.slowAdd",
    );
    const result = await client.evaluate(
      `(
        async () => {
          const reply = await window.__MoonBit__.add.slowAdd({
            left: 2,
            right: 3,
          });
          return {
            url: location.href,
            title: document.title,
            hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
            hasProxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
            reply,
          };
        }
      )()`,
      true,
    );
    assertAsyncAddProxyProbeResult(result);
    return result;
  } finally {
    client.close();
  }
}

async function runSyncAsyncProxyProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTargetByTitle("MoonBit Sync + Async Extensions");
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.math?.double && window.__MoonBit__?.add?.slowAdd)",
      "window.__MoonBit__ math/add proxies",
    );
    const result = await client.evaluate(
      `(
        async () => {
          const doubled = await window.__MoonBit__.math.double({ value: 21 });
          const added = await window.__MoonBit__.add.slowAdd({
            left: 20,
            right: 22,
            delay_ms: 10,
          });
          return {
            url: location.href,
            title: document.title,
            hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
            hasMathProxy: typeof window.__MoonBit__?.math?.double === "function",
            hasAddProxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
            doubled,
            added,
          };
        }
      )()`,
      true,
    );
    assertSyncAsyncProxyProbeResult(result);
    return result;
  } finally {
    client.close();
  }
}

async function runEventBroadcastProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTargetByTitle("MoonBit Event Broadcast");
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start && window.__MoonBit__?.ticker?.on && window.__MoonBit__?.events?.['@@emitExtensionEvent'])",
      "window.__MoonBit__ ticker event bridge",
    );
    const result = await client.evaluate(
      `(
        async () => {
          window.__eventProbe = [];
          window.__MoonBit__.ticker.on("tick", (event) => {
            window.__eventProbe.push({
              kind: "tick",
              run_id: event.payload.run_id,
              index: event.payload.index,
              total: event.payload.total,
            });
          });
          window.__MoonBit__.ticker.on("done", (event) => {
            window.__eventProbe.push({
              kind: "done",
              run_id: event.payload.run_id,
              total: event.payload.total,
            });
          });
          const reply = await window.__MoonBit__.ticker.start({
            run_id: 9001,
            count: 3,
            interval_ms: 100,
          });
          return {
            url: location.href,
            title: document.title,
            hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
            hasProxy: typeof window.__MoonBit__?.ticker?.start === "function",
            hasEventProxy: typeof window.__MoonBit__?.ticker?.on === "function",
            reply,
            events: window.__eventProbe,
          };
        }
      )()`,
      true,
    );
    assertEventBroadcastProbeResult(result);
    const reload = await runEventBroadcastReloadProbe(client);
    return { ...result, reload };
  } finally {
    client.close();
  }
}

async function runEventBroadcastReloadProbe(client) {
  await client.send("Page.enable");
  await client.evaluate(
    `(() => {
      const start = window.__MoonBit__?.ticker?.start;
      if (typeof start === "function") {
        void start({
          run_id: 9100,
          count: 5,
          interval_ms: 100,
        }).catch(() => {});
      }
      location.reload();
      return true;
    })()`,
  );
  await waitForExpression(
    client,
    `Boolean(
      window.__MoonBit__?.ticker?.start &&
      window.__MoonBit__?.ticker?.on &&
      performance.getEntriesByType("navigation")[0]?.type === "reload"
    )`,
    "event bridge after reload",
  );
  const result = await client.evaluate(
    `(
      async () => {
        window.__eventReloadProbe = [];
        window.__MoonBit__.ticker.on("tick", (event) => {
          window.__eventReloadProbe.push({
            kind: "tick",
            run_id: event.payload.run_id,
            index: event.payload.index,
            total: event.payload.total,
          });
        });
        window.__MoonBit__.ticker.on("done", (event) => {
          window.__eventReloadProbe.push({
            kind: "done",
            run_id: event.payload.run_id,
            total: event.payload.total,
          });
        });
        const reply = await window.__MoonBit__.ticker.start({
          run_id: 9101,
          count: 1,
          interval_ms: 100,
        });
        await new Promise((resolve) => setTimeout(resolve, 700));
        return {
          url: location.href,
          title: document.title,
          hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
          hasProxy: typeof window.__MoonBit__?.ticker?.start === "function",
          hasEventProxy: typeof window.__MoonBit__?.ticker?.on === "function",
          navigationType: performance.getEntriesByType("navigation")[0]?.type,
          reply,
          events: window.__eventReloadProbe,
        };
      }
    )()`,
    true,
  );
  assertEventBroadcastReloadProbeResult(result);
  return result;
}

async function runAttributeCodegenCommandProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTargetByTitle("Proton Attribute Codegen");
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.slowAdd && window.__MoonBit__?.events?.on)",
      "window.__MoonBit__ generated add command bridge",
    );
    const result = await client.evaluate(
      `(
        async () => {
          window.__attributeProbe = [];
          window.__MoonBit__.events.on("add.addFinished", (event) => {
            window.__attributeProbe.push({
              name: event.name,
              extension: event.extension,
              total: event.payload.total,
            });
          });
          const reply = await window.__MoonBit__.add.slowAdd({
            left: 20,
            right: 22,
            delay_ms: 25,
          });
          return {
            url: location.href,
            title: document.title,
            hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
            hasGeneratedProxy: typeof window.__MoonBit__?.add?.slowAdd === "function",
            hasEventApi: typeof window.__MoonBit__?.events?.on === "function",
            reply,
            events: window.__attributeProbe,
          };
        }
      )()`,
      true,
    );
    assertAttributeCodegenCommandProbeResult(result);
    return result;
  } finally {
    client.close();
  }
}

async function runAssetSidecarResourcesProbe() {
  await waitForCdpEndpoint();
  const page = await waitForPageTargetByTitle("Asset Sidecar Resources");
  const client = new CdpClient(page.webSocketDebuggerUrl);
  await client.open();
  try {
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.add?.add && window.__MoonBit__?.add?.reportProbe)",
      "window.__MoonBit__ asset sidecar add command bridge",
    );
    await waitForExpression(
      client,
      'document.querySelector("#result")?.textContent === "12"',
      "asset sidecar app.js automatic add result",
    );
    const result = await client.evaluate(
      `(
        async () => {
          const commandReply = await window.__MoonBit__.add.add({
            left: 30,
            right: 12,
          });
          const probeReply = await window.__MoonBit__.add.reportProbe({
            report: JSON.stringify({
              ok: commandReply === 42,
              source: "smoke",
            }),
          });
          return {
            url: location.href,
            title: document.title,
            hasBridge: typeof window.__MoonBit__?.core?.invokeOp === "function",
            hasGeneratedProxy: typeof window.__MoonBit__?.add?.add === "function",
            hasReportProxy: typeof window.__MoonBit__?.add?.reportProbe === "function",
            autoResult: document.querySelector("#result")?.textContent,
            logText: document.querySelector("#log")?.textContent,
            cssLoaded: getComputedStyle(document.documentElement)
              .getPropertyValue("--accent")
              .trim() !== "",
            scriptElementPresent: Boolean(document.querySelector('script[src="app.js"]')),
            commandReply,
            probeReply,
          };
        }
      )()`,
      true,
    );
    assertAssetSidecarResourcesProbeResult(result);
    return result;
  } finally {
    client.close();
  }
}

async function runQueueFullProbe(client) {
  const result = await client.evaluate(
    `(
      async () => {
        const invoke = window.__MoonBit__?.core?.invokeOp;
        const count = 320;
        const calls = Array.from({ length: count }, (_, index) =>
          invoke("ext:app/slowAdd", {
            left: index,
            right: 1,
            delay_ms: 3500,
          })
        );
        const settled = await Promise.allSettled(calls);
        const rejectedMessages = settled
          .filter((item) => item.status === "rejected")
          .map((item) => String(item.reason && item.reason.message ? item.reason.message : item.reason));
        return {
          requested: count,
          fulfilled: settled.filter((item) => item.status === "fulfilled").length,
          rejected: rejectedMessages.length,
          fullRejected: rejectedMessages.some((message) =>
            message.includes("bridge request queue is full")
          ),
          firstRejectedMessage: rejectedMessages[0] || "",
        };
      }
    )()`,
    true,
  );
  assertQueueFullProbeResult(result);
  return result;
}

async function runReloadProbe(client) {
  await client.send("Page.enable");
  await client.evaluate(
    `(() => {
      const invoke = window.__MoonBit__?.core?.invokeOp;
      if (typeof invoke === "function") {
        void invoke("ext:app/slowAdd", {
          left: 1,
          right: 2,
          delay_ms: 1000,
        }).catch(() => {});
      }
      location.reload();
      return true;
    })()`,
  );
  await waitForExpression(
    client,
    `Boolean(
      window.__MoonBit__?.core?.invokeOp &&
      performance.getEntriesByType("navigation")[0]?.type === "reload"
    )`,
    "bridge after reload",
  );
  const result = await client.evaluate(
    `(
      async () => {
        const invoke = window.__MoonBit__?.core?.invokeOp;
        return {
          url: location.href,
          title: document.title,
          hasBridge: typeof invoke === "function",
          navigationType: performance.getEntriesByType("navigation")[0]?.type,
          ping: await invoke("ext:app/ping", { name: "reload" }),
        };
      }
    )()`,
    true,
  );
  assertReloadProbeResult(result);
  return result;
}

async function runNonProtonProbe(client) {
  await client.send("Page.enable");
  const filePath = path.join(repoRoot, "target", "non-proton-bridge-probe.html");
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    "<!doctype html><title>Non Proton File Probe</title><h1>file probe</h1>",
    "utf8",
  );
  const fileUrl = pathToFileURL(filePath).href;
  const httpServer = http.createServer((request, response) => {
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(
      "<!doctype html><title>Non Proton HTTP Probe</title><h1>http probe</h1>",
    );
  });
  await new Promise((resolve, reject) => {
    httpServer.once("error", reject);
    httpServer.listen(0, "127.0.0.1", resolve);
  });
  const address = httpServer.address();
  const httpUrl = `http://127.0.0.1:${address.port}/probe.html`;
  try {
    const about = await navigateAndReadBridgeGlobals(client, "about:blank");
    const file = await navigateAndReadBridgeGlobals(client, fileUrl);
    const httpPage = await navigateAndReadBridgeGlobals(client, httpUrl);
    const result = { about, file, http: httpPage };
    assertNonProtonProbeResult(result);
    return result;
  } finally {
    await new Promise((resolve) => {
      httpServer.close(resolve);
      httpServer.closeAllConnections?.();
    });
  }
}

async function runWindowCloseLifecycleProbe(env, scenario) {
  cleanupWorkspaceProcesses();
  const child = spawnApp(env, scenario);
  const output = collectOutput(child);
  let client = null;
  try {
    await waitForCdpEndpoint();
    const page = await waitForPageTarget();
    client = new CdpClient(page.webSocketDebuggerUrl);
    await client.open();
    await client.send("Runtime.enable");
    await waitForBridge(client);
    await client.evaluate(
      `(() => {
        const invoke = window.__MoonBit__?.core?.invokeOp;
        if (typeof invoke !== "function") {
          throw new Error("bridge is not installed");
        }
        window.__protonLifecyclePending = invoke("ext:app/slowAdd", {
          left: 7,
          right: 8,
          delay_ms: 3500,
        }).catch(() => {});
        return true;
      })()`,
    );
    await waitForNativeLog(
      (log) => /bridge_enqueue .*op=ext:app\/slowAdd/.test(log),
      "pending slowAdd request to enter bridge queue",
    );
    await closeScenarioWindow(client, child.pid);
    await waitForExit(child, output, "window close lifecycle app");
    const lifecycle = assertNativeLogLifecycleGuards();
    return lifecycle;
  } finally {
    if (client) {
      client.close();
    }
    await terminateTree(child);
    cleanupWorkspaceProcesses();
  }
}

async function runEventBroadcastWindowCloseLifecycleProbe(env, scenario) {
  cleanupWorkspaceProcesses();
  const child = spawnApp(env, scenario);
  const output = collectOutput(child);
  let client = null;
  try {
    await waitForCdpEndpoint();
    const page = await waitForPageTargetByTitle("MoonBit Event Broadcast");
    client = new CdpClient(page.webSocketDebuggerUrl);
    await client.open();
    await client.send("Runtime.enable");
    await waitForExpression(
      client,
      "Boolean(window.__MoonBit__?.core?.invokeOp && window.__MoonBit__?.ticker?.start)",
      "window.__MoonBit__.ticker.start for close lifecycle",
    );
    await client.evaluate(
      `(() => {
        window.__protonEventLifecyclePending = window.__MoonBit__.ticker.start({
          run_id: 9102,
          count: 8,
          interval_ms: 100,
        }).catch(() => {});
        return true;
      })()`,
    );
    await waitForNativeLog(
      (log) => /bridge_enqueue .*op=ext:ticker\/start/.test(log),
      "pending ticker request to enter bridge queue",
    );
    await sleep(250);
    await closeScenarioWindow(client, child.pid);
    await waitForExit(child, output, "event broadcast window close lifecycle app");
    return assertNativeLogEventLifecycleGuards();
  } finally {
    if (client) {
      client.close();
    }
    await terminateTree(child);
    cleanupWorkspaceProcesses();
  }
}

async function navigateAndReadBridgeGlobals(client, url) {
  await client.send("Page.navigate", { url });
  await waitForExpression(
    client,
    `document.readyState !== "loading" && location.href === ${JSON.stringify(url)}`,
    `navigation to ${url}`,
  );
  return await client.evaluate(
    `({
      url: location.href,
      title: document.title,
      hasBridge: Boolean(window.__MoonBit__?.core?.invokeOp),
      hasNativeInvoke: typeof window.__protonNativeInvokeOp === "function"
    })`,
  );
}

async function runMoonBitE2eProbe(env, scenario) {
  const child = spawn(
    "moon",
    ["-C", "e2e", "run", "test", "--target", "native", "--diagnostic-limit", "120"],
    {
      cwd: repoRoot,
      env: {
        ...env,
        MBT_PROTON_E2E_SCENARIO: scenario,
        MBT_CDP_TARGET: String(cdpPort),
        MBT_PROTON_E2E_TIMEOUT_MS: String(timeoutMs),
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  const output = collectOutput(child);
  const exit = await Promise.race([
    new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolve({ code, signal }));
    }),
    sleep(timeoutMs + 15000).then(() => {
      throw new Error(`MoonBit e2e timed out after ${timeoutMs + 15000}ms\n${output()}`);
    }),
  ]);
  if (exit.code !== 0 || !output().includes(`CDP e2e passed: ${scenario}`)) {
    throw new Error(`MoonBit e2e failed for ${scenario}: code=${exit.code} signal=${exit.signal}\n${output()}`);
  }
  return output().trim();
}

function assertProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`probe returned non-object result: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "MoonBit App Commands") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (result.hasBridge !== true) {
    throw new Error("bridge was not installed");
  }
  if (result.ping?.message !== "Hello proton from the app command layer") {
    throw new Error(`unexpected ping result: ${JSON.stringify(result.ping)}`);
  }
  if (result.sum?.total !== 42 || result.sum?.source !== "commands") {
    throw new Error(`unexpected slowAdd result: ${JSON.stringify(result.sum)}`);
  }
  if (result.unknownRejected !== true) {
    throw new Error("unknown op did not reject");
  }
  if (!String(result.unknownMessage ?? "").includes("bridge op is not allowed")) {
    throw new Error(`unexpected unknown op message: ${result.unknownMessage}`);
  }
  if (result.failRejected !== true) {
    throw new Error("failing command did not reject");
  }
  if (!String(result.failMessage ?? "").includes("Failure crossed command boundary")) {
    throw new Error(`unexpected failing command message: ${result.failMessage}`);
  }
  if (result.largePayloadRejected !== true) {
    throw new Error("oversized payload did not reject");
  }
  const largePayloadMessage = String(result.largePayloadMessage ?? "");
  if (
    !largePayloadMessage.includes("invalid bridge request") &&
    !largePayloadMessage.includes("bridge payload is too large")
  ) {
    throw new Error(`unexpected oversized payload message: ${result.largePayloadMessage}`);
  }
}

function assertMultiWindowRoutingProbeResult(result) {
  for (const [key, label] of [["a", "A"], ["b", "B"]]) {
    const page = result[key];
    if (!page || typeof page !== "object") {
      throw new Error(`multi-window ${label} returned non-object: ${JSON.stringify(page)}`);
    }
    if (page.url !== `proton://app/${label}`) {
      throw new Error(`multi-window ${label} URL mismatch: ${page.url}`);
    }
    if (page.title !== `Bridge Multi ${label}`) {
      throw new Error(`multi-window ${label} title mismatch: ${page.title}`);
    }
    if (page.label !== label) {
      throw new Error(`multi-window ${label} JS label mismatch: ${page.label}`);
    }
    if (page.hasBridge !== true) {
      throw new Error(`multi-window ${label} bridge was not installed`);
    }
    if (page.response?.label !== label) {
      throw new Error(`multi-window ${label} response crossed windows: ${JSON.stringify(page.response)}`);
    }
    if (!page.response?.request_id) {
      throw new Error(`multi-window ${label} response is missing request_id`);
    }
    if (!page.response?.window) {
      throw new Error(`multi-window ${label} response is missing window handle`);
    }
  }
  if (result.a.targetId === result.b.targetId) {
    throw new Error("multi-window probe used the same CDP target for both windows");
  }
  if (result.a.response.request_id === result.b.response.request_id) {
    throw new Error("multi-window responses reused the same request_id");
  }
  if (result.a.response.window === result.b.response.window) {
    throw new Error("multi-window responses reported the same native window handle");
  }
}

function assertAsyncAddProxyProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`async add proxy probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "MoonBit Async Add Extension") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (result.hasBridge !== true || result.hasProxy !== true) {
    throw new Error(`async add proxy was not installed: ${JSON.stringify(result)}`);
  }
  if (result.reply !== 5) {
    throw new Error(`unexpected async add reply: ${JSON.stringify(result.reply)}`);
  }
}

function assertSyncAsyncProxyProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`sync/async proxy probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "MoonBit Sync + Async Extensions") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (
    result.hasBridge !== true ||
    result.hasMathProxy !== true ||
    result.hasAddProxy !== true
  ) {
    throw new Error(`sync/async proxies were not installed: ${JSON.stringify(result)}`);
  }
  if (
    result.doubled?.value !== 21 ||
    result.doubled?.doubled !== 42 ||
    result.doubled?.source !== "sync command extension"
  ) {
    throw new Error(`unexpected math.double reply: ${JSON.stringify(result.doubled)}`);
  }
  if (
    result.added?.total !== 42 ||
    result.added?.waited_ms !== 10 ||
    result.added?.source !== "async command extension"
  ) {
    throw new Error(`unexpected add.slowAdd reply: ${JSON.stringify(result.added)}`);
  }
}

function assertEventBroadcastProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`event broadcast probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "MoonBit Event Broadcast") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (
    result.hasBridge !== true ||
    result.hasProxy !== true ||
    result.hasEventProxy !== true
  ) {
    throw new Error(`event broadcast bridge was not installed: ${JSON.stringify(result)}`);
  }
  if (result.reply?.done?.run_id !== 9001 || result.reply?.done?.total !== 3) {
    throw new Error(`unexpected event broadcast reply: ${JSON.stringify(result.reply)}`);
  }
  if (!Array.isArray(result.reply?.ticks) || result.reply.ticks.length !== 3) {
    throw new Error(`event broadcast reply did not include three ticks: ${JSON.stringify(result.reply)}`);
  }
  const events = Array.isArray(result.events) ? result.events : [];
  const tickEvents = events.filter((event) => event.kind === "tick");
  const doneEvents = events.filter((event) => event.kind === "done");
  if (
    tickEvents.length !== 3 ||
    tickEvents[0]?.index !== 1 ||
    tickEvents[1]?.index !== 2 ||
    tickEvents[2]?.index !== 3
  ) {
    throw new Error(`unexpected tick events: ${JSON.stringify(events)}`);
  }
  if (doneEvents.length !== 1 || doneEvents[0]?.run_id !== 9001 || doneEvents[0]?.total !== 3) {
    throw new Error(`unexpected done events: ${JSON.stringify(events)}`);
  }
}

function assertEventBroadcastReloadProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`event broadcast reload probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL after event reload, got ${result.url}`);
  }
  if (result.title !== "MoonBit Event Broadcast") {
    throw new Error(`unexpected title after event reload: ${result.title}`);
  }
  if (
    result.hasBridge !== true ||
    result.hasProxy !== true ||
    result.hasEventProxy !== true
  ) {
    throw new Error(`event bridge was not reinstalled after reload: ${JSON.stringify(result)}`);
  }
  if (result.navigationType !== "reload") {
    throw new Error(`expected reload navigation type, got ${result.navigationType}`);
  }
  if (result.reply?.done?.run_id !== 9101 || result.reply?.done?.total !== 1) {
    throw new Error(`unexpected event reload reply: ${JSON.stringify(result.reply)}`);
  }
  const events = Array.isArray(result.events) ? result.events : [];
  const currentRunDone = events.filter((event) =>
    event.kind === "done" && event.run_id === 9101 && event.total === 1
  );
  if (currentRunDone.length !== 1) {
    throw new Error(`event reload did not deliver the current done event: ${JSON.stringify(events)}`);
  }
  const staleEvents = events.filter((event) => event.run_id === 9100);
  if (staleEvents.length !== 0) {
    throw new Error(`event reload delivered stale pre-reload events: ${JSON.stringify(events)}`);
  }
}

function assertAttributeCodegenCommandProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`attribute codegen probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "Proton Attribute Codegen") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (
    result.hasBridge !== true ||
    result.hasGeneratedProxy !== true ||
    result.hasEventApi !== true
  ) {
    throw new Error(`generated command bridge was not installed: ${JSON.stringify(result)}`);
  }
  if (result.reply?.total !== 42 || result.reply?.waited_ms !== 25) {
    throw new Error(`unexpected generated slowAdd reply: ${JSON.stringify(result.reply)}`);
  }
  if (!Array.isArray(result.events) || result.events.length !== 1) {
    throw new Error(`expected one generated event: ${JSON.stringify(result.events)}`);
  }
  const event = result.events[0];
  if (event.extension !== "add" || event.name !== "addFinished" || event.total !== 42) {
    throw new Error(`unexpected generated event payload: ${JSON.stringify(result.events)}`);
  }
}

function assertAssetSidecarResourcesProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`asset sidecar probe returned non-object: ${JSON.stringify(result)}`);
  }
  if (!String(result.url ?? "").startsWith("proton://app/")) {
    throw new Error(`expected proton://app/ URL, got ${result.url}`);
  }
  if (result.title !== "Asset Sidecar Resources") {
    throw new Error(`unexpected title: ${result.title}`);
  }
  if (
    result.hasBridge !== true ||
    result.hasGeneratedProxy !== true ||
    result.hasReportProxy !== true
  ) {
    throw new Error(`asset sidecar command bridge was not installed: ${JSON.stringify(result)}`);
  }
  if (result.autoResult !== "12") {
    throw new Error(`asset sidecar app.js did not run automatic add: ${JSON.stringify(result)}`);
  }
  if (result.cssLoaded !== true || result.scriptElementPresent !== true) {
    throw new Error(`asset sidecar resources were not loaded: ${JSON.stringify(result)}`);
  }
  if (result.commandReply !== 42 || result.probeReply?.ok !== true) {
    throw new Error(`unexpected asset sidecar command replies: ${JSON.stringify(result)}`);
  }
}

function assertReloadProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`reload probe returned non-object result: ${JSON.stringify(result)}`);
  }
  if (result.url !== "proton://app/") {
    throw new Error(`expected proton://app/ URL after reload, got ${result.url}`);
  }
  if (result.title !== "MoonBit App Commands") {
    throw new Error(`unexpected title after reload: ${result.title}`);
  }
  if (result.hasBridge !== true) {
    throw new Error("bridge was not reinstalled after reload");
  }
  if (result.navigationType !== "reload") {
    throw new Error(`expected reload navigation type, got ${result.navigationType}`);
  }
  if (result.ping?.message !== "Hello reload from the app command layer") {
    throw new Error(`unexpected reload ping result: ${JSON.stringify(result.ping)}`);
  }
}

function assertQueueFullProbeResult(result) {
  if (!result || typeof result !== "object") {
    throw new Error(`queue full probe returned non-object result: ${JSON.stringify(result)}`);
  }
  if (result.requested !== 320) {
    throw new Error(`unexpected queue full request count: ${JSON.stringify(result)}`);
  }
  if (result.fulfilled <= 0) {
    throw new Error(`queue full probe had no fulfilled requests: ${JSON.stringify(result)}`);
  }
  if (result.rejected <= 0 || result.fullRejected !== true) {
    throw new Error(`queue full probe did not reject overflow requests: ${JSON.stringify(result)}`);
  }
}

function assertNonProtonProbeResult(result) {
  for (const [name, page] of Object.entries(result)) {
    if (!page || typeof page !== "object") {
      throw new Error(`${name} non-proton probe returned non-object: ${JSON.stringify(page)}`);
    }
    if (page.hasBridge !== false) {
      throw new Error(`${name} page unexpectedly has window.__MoonBit__.core.invokeOp`);
    }
    if (page.hasNativeInvoke !== false) {
      throw new Error(`${name} page unexpectedly has __protonNativeInvokeOp`);
    }
  }
}

function spawnApp(env, scenario) {
  return spawn("moon", ["-C", "examples", "run", scenario, "--target", "native", "--diagnostic-limit", "120"], {
    cwd: repoRoot,
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
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

async function terminateTree(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) {
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
  if (child.exitCode !== null || child.signalCode !== null) {
    return;
  }
  await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    sleep(5000),
  ]);
}

function cleanupWorkspaceProcesses() {
  if (process.platform !== "win32") {
    const result = spawnSync("ps", ["-axo", "pid=,command="], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    if (result.status !== 0) {
      return;
    }
    const candidates = [];
    for (const line of result.stdout.split(/\r?\n/)) {
      const match = line.match(/^\s*(\d+)\s+(.*)$/);
      if (!match) {
        continue;
      }
      const pid = Number(match[1]);
      const command = match[2];
      if (
        pid !== process.pid &&
        command.includes(repoRoot) &&
        !command.includes("scripts/e2e_bridge_smoke.mjs")
      ) {
        candidates.push(pid);
      }
    }
    for (const pid of candidates) {
      try {
        process.kill(pid, "SIGTERM");
      } catch {
        // Best-effort cleanup only.
      }
    }
    return;
  }
  const script = `
$root = (Resolve-Path -LiteralPath '${repoRoot.replace(/'/g, "''")}').Path
Get-CimInstance Win32_Process |
  Where-Object {
    ($_.CommandLine -like "*$root*") -or
    ($_.ExecutablePath -like "$root\\_build\\native\\*") -or
    ($_.ExecutablePath -like "$root\\.proton\\runtimes\\*\\bin\\cef_process.exe") -or
    ($_.ExecutablePath -like "$root\\native\\dist\\bin\\cef_process.exe")
  } |
  Where-Object { $_.ProcessId -ne $PID } |
  ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
  }
`;
  spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    cwd: repoRoot,
    stdio: "ignore",
  });
}

function closeWindowsForProcessTree(rootPid) {
  if (process.platform !== "win32") {
    process.kill(rootPid, "SIGTERM");
    return;
  }
  const script = `
$rootPid = ${Number(rootPid)}
$all = Get-CimInstance Win32_Process
$ids = [System.Collections.Generic.HashSet[int]]::new()
[void]$ids.Add($rootPid)
$changed = $true
while ($changed) {
  $changed = $false
  foreach ($process in $all) {
    if ($ids.Contains([int]$process.ParentProcessId) -and -not $ids.Contains([int]$process.ProcessId)) {
      [void]$ids.Add([int]$process.ProcessId)
      $changed = $true
    }
  }
}
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ProtonE2EWindowClose {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
"@
$closed = 0
$callback = [ProtonE2EWindowClose+EnumWindowsProc]{
  param([IntPtr]$hwnd, [IntPtr]$lParam)
  $windowPid = 0
  [void][ProtonE2EWindowClose]::GetWindowThreadProcessId($hwnd, [ref]$windowPid)
  if ($ids.Contains($windowPid) -and [ProtonE2EWindowClose]::IsWindowVisible($hwnd)) {
    [void][ProtonE2EWindowClose]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    $script:closed += 1
  }
  return $true
}
[void][ProtonE2EWindowClose]::EnumWindows($callback, [IntPtr]::Zero)
if ($closed -le 0) {
  Write-Error "no visible windows found for process tree $rootPid"
  exit 1
}
`;
  const result = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`failed to close lifecycle window: ${result.stderr || result.stdout}`);
  }
}

async function closeScenarioWindow(client, rootPid) {
  if (process.platform === "win32") {
    closeWindowsForProcessTree(rootPid);
    return;
  }
  try {
    const version = await httpJson(`http://127.0.0.1:${cdpPort}/json/version`);
    if (version?.webSocketDebuggerUrl) {
      const browser = new CdpClient(version.webSocketDebuggerUrl);
      await browser.open();
      browser.sendNoWait("Browser.close");
      await sleep(1000);
      browser.close();
      return;
    }
  } catch {
    // Fall back to the page target below.
  }
  client.sendNoWait("Page.close");
  await sleep(1000);
}

async function runScenario(name, hasMoonBitE2e) {
  ensureSupportedScenario(name);
  const env = pathEnvWithNativeRuntime();
  fs.mkdirSync(path.join(repoRoot, "target"), { recursive: true });
  removeIfExists(path.join(repoRoot, "target", "proton-native.log"));
  removeIfExists(path.join(repoRoot, "examples", "target", "app-commands.probe.json"));
  cleanupWorkspaceProcesses();
  const child = spawnApp(env, name);
  const output = collectOutput(child);
  let result = null;
  try {
    result = await Promise.race([
      (async () => {
        let moonbitE2eOutput = "";
        if (hasMoonBitE2e && supportsMoonBitE2eScenario(name)) {
          await waitForCdpEndpoint();
          moonbitE2eOutput = await runMoonBitE2eProbe(env, name);
          console.log(moonbitE2eOutput);
        } else if (hasMoonBitE2e) {
          console.log(`MoonBit e2e module does not define ${name}; running JS/CDP smoke only.`);
        }
        const cdpResult = await runCdpScenarioProbe(name);
        const nativeLogGuards = assertNativeLogScenarioGuards(name);
        cdpResult.nativeLogGuards = nativeLogGuards;
        return { moonbitE2eOutput, cdpResult };
      })(),
      new Promise((_, reject) => {
        child.once("exit", (code, signal) => {
          reject(new Error(`scenario exited before CDP probe completed: code=${code} signal=${signal}\n${output()}`));
        });
      }),
      sleep(timeoutMs).then(() => {
        throw new Error(`bridge smoke timed out after ${timeoutMs}ms\n${output()}`);
      }),
    ]);
  } finally {
    await terminateTree(child);
    cleanupWorkspaceProcesses();
  }
  if (name === "41_app_commands") {
    const lifecycle = await runWindowCloseLifecycleProbe(env, name);
    result.cdpResult.lifecycle = lifecycle;
  }
  if (name === "40_event_broadcast") {
    const lifecycle = await runEventBroadcastWindowCloseLifecycleProbe(
      env,
      name,
    );
    result.cdpResult.lifecycle = lifecycle;
  }
  console.log(`bridge e2e passed: ${name}`);
  console.log(JSON.stringify(result.cdpResult));
}

async function runCdpScenarioProbe(name) {
  if (name === "38_async_extension_add") {
    return await runAsyncAddProxyProbe();
  }
  if (name === "39_sync_async_extensions") {
    return await runSyncAsyncProxyProbe();
  }
  if (name === "40_event_broadcast") {
    return await runEventBroadcastProbe();
  }
  if (name === "42_attribute_codegen_commands") {
    return await runAttributeCodegenCommandProbe();
  }
  if (name === "45_bridge_multi_window") {
    return await runMultiWindowRoutingProbe();
  }
  if (name === "46_asset_sidecar_resources") {
    return await runAssetSidecarResourcesProbe();
  }
  return await runCdpProbe();
}

function assertNativeLogScenarioGuards(name) {
  if (name === "38_async_extension_add") {
    return assertNativeLogOpsEnqueued(["ext:add/slowAdd"]);
  }
  if (name === "39_sync_async_extensions") {
    return assertNativeLogOpsEnqueued([
      "ext:math/double",
      "ext:add/slowAdd",
    ]);
  }
  if (name === "40_event_broadcast") {
    return assertNativeLogOpsEnqueued(["ext:ticker/start"]);
  }
  if (name === "42_attribute_codegen_commands") {
    return assertNativeLogOpsEnqueued(["ext:add/slowAdd"]);
  }
  if (name === "45_bridge_multi_window") {
    return assertNativeLogMultiWindowGuards();
  }
  if (name === "46_asset_sidecar_resources") {
    return assertNativeLogOpsEnqueued([
      "ext:add/add",
      "ext:add/reportProbe",
    ]);
  }
  return assertNativeLogBridgeGuards();
}

await chooseCdpPort();
const hasMoonBitE2e = ensureE2eWorkspaceMember();
for (const scenario of scenarios) {
  await runScenario(scenario, hasMoonBitE2e);
}
process.exit(0);

function assertNativeLogBridgeGuards() {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  if (!log.includes("bridge_reject_not_allowed") || !log.includes("op=ext:app/unknown")) {
    throw new Error("native log did not prove unknown op was rejected before enqueue");
  }
  if (/bridge_enqueue .*op=ext:app\/unknown/.test(log)) {
    throw new Error("native log shows unknown op entered the bridge queue");
  }
  const invalidMatches = [
    ...log.matchAll(/bridge_reject_invalid_renderer pending=(\d+) op=ext:app\/ping payload_bytes=(\d+)/g),
  ];
  const oversized = invalidMatches.find((match) => Number(match[2]) > 1048576);
  if (!oversized) {
    throw new Error("native log did not prove oversized payload was rejected in renderer");
  }
  const pendingId = oversized[1];
  const crossedToBrowser = new RegExp(
    `browser_bridge_request browser=\\d+ pending=${pendingId} op=ext:app\\/ping`,
  ).test(log);
  const enqueued = new RegExp(
    `bridge_enqueue .*pending=${pendingId} op=ext:app\\/ping`,
  ).test(log);
  if (crossedToBrowser || enqueued) {
    throw new Error("native log shows oversized payload crossed into browser queue");
  }
  if (!log.includes("bridge_reject_queue_full")) {
    throw new Error("native log did not prove queue full rejection");
  }
  return {
    unknownRejectedBeforeEnqueue: true,
    oversizedRejectedBeforeBrowser: true,
    queueFullRejected: true,
  };
}

function assertNativeLogLifecycleGuards() {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  const pendingCleanup = [
    ...log.matchAll(/bridge_pending_remove_browser browser=\d+ pending=(\d+) queued=(\d+)/g),
  ].some((match) => Number(match[1]) > 0 || Number(match[2]) > 0);
  const staleResponseHandled =
    /bridge_pending_remove request=\d+ browser=\d+/.test(log) ||
    /bridge_response_no_pending request=\d+/.test(log) ||
    /bridge_response_send_failed request=\d+/.test(log);
  const pendingResponseHandled =
    pendingCleanup ||
    staleResponseHandled;
  if (!pendingResponseHandled) {
    throw new Error("native log did not prove pending bridge response state was handled after close");
  }
  const runtimeDestroyCleanup =
    /bridge_queue_clear removed=\d+/.test(log) &&
    /bridge_pending_clear_all removed=\d+/.test(log);
  const windowCloseCleanup =
    process.platform !== "win32" &&
    /window_closed browser=\d+/.test(log) &&
    /bridge_pending_remove_browser browser=\d+/.test(log);
  if (!runtimeDestroyCleanup && !windowCloseCleanup) {
    throw new Error("native log did not prove runtime destroy cleared the bridge queue");
  }
  return {
    windowClosePendingCleanup: pendingCleanup,
    pendingResponseStateHandled: pendingResponseHandled,
    runtimeDestroyCleanup,
  };
}

function assertNativeLogMultiWindowGuards() {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  const matches = [
    ...log.matchAll(/bridge_enqueue request=(\d+) browser=(\d+) pending=(\d+) op=ext:multi\/identify/g),
  ];
  if (matches.length < 2) {
    throw new Error("native log did not prove two multi-window bridge requests were enqueued");
  }
  const requestIds = new Set(matches.map((match) => match[1]));
  const browserIds = new Set(matches.map((match) => match[2]));
  if (requestIds.size < 2) {
    throw new Error("native log did not prove multi-window requests used distinct request ids");
  }
  if (browserIds.size < 2) {
    throw new Error("native log did not prove multi-window requests came from distinct browser ids");
  }
  return {
    multiWindowRequestsEnqueued: true,
    distinctRequestIds: true,
    distinctBrowserIds: true,
  };
}

function assertNativeLogEventLifecycleGuards() {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  if (!/bridge_enqueue .*op=ext:ticker\/start/.test(log)) {
    throw new Error("native log did not prove event lifecycle ticker request was enqueued");
  }
  const pendingCleanup = [
    ...log.matchAll(/bridge_pending_remove_browser browser=\d+ pending=(\d+) queued=(\d+)/g),
  ].some((match) => Number(match[1]) > 0 || Number(match[2]) > 0);
  const staleResponseHandled =
    /bridge_pending_remove request=\d+ browser=\d+/.test(log) ||
    /bridge_response_no_pending request=\d+/.test(log) ||
    /bridge_response_send_failed request=\d+/.test(log);
  const pendingResponseHandled =
    pendingCleanup ||
    staleResponseHandled;
  if (!pendingResponseHandled) {
    throw new Error("native log did not prove event lifecycle pending bridge response state was handled after close");
  }
  const runtimeDestroyCleanup =
    /bridge_queue_clear removed=\d+/.test(log) &&
    /bridge_pending_clear_all removed=\d+/.test(log);
  const windowCloseCleanup =
    process.platform !== "win32" &&
    /window_closed browser=\d+/.test(log) &&
    /bridge_pending_remove_browser browser=\d+/.test(log);
  if (!runtimeDestroyCleanup && !windowCloseCleanup) {
    throw new Error("native log did not prove event lifecycle runtime destroy cleared the bridge queue");
  }
  return {
    eventCommandEnqueued: true,
    windowClosePendingCleanup: pendingCleanup,
    pendingResponseStateHandled: pendingResponseHandled,
    runtimeDestroyCleanup,
  };
}

function assertNativeLogOpsEnqueued(ops) {
  const logPath = path.join(repoRoot, "target", "proton-native.log");
  const log = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  const enqueued = {};
  for (const op of ops) {
    const escaped = op.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (!new RegExp(`bridge_enqueue .*op=${escaped}`).test(log)) {
      throw new Error(`native log did not prove bridge enqueue for ${op}`);
    }
    enqueued[op] = true;
  }
  return { enqueued };
}
