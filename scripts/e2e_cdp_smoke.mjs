#!/usr/bin/env node
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import net from "node:net";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const timeoutMs = Number(process.env.LEPUS_CDP_E2E_TIMEOUT_MS ?? "30000");

const allExamples = [
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
  "30_app_asset_origin",
  "31_app_asset_bundle",
  "32_shared_buffer_benchmark",
  "33_app_auto_launch",
  "34_app_keepawake",
  "35_app_microphone",
  "36_app_devtools",
  "37_cef_mvp",
  "38_async_extension_add",
  "39_sync_async_extensions",
  "40_event_broadcast",
  "41_app_commands/app",
];

const scenarios = {
  "38_async_extension_add": {
    waitExpression:
      "Boolean(window.__MoonBit__ && window.__MoonBit__.add && window.__MoonBit__.add.slowAdd)",
    probeExpression: `;(async () => {
      const total = await window.__MoonBit__.add.slowAdd({ left: 8, right: 5 });
      return { total };
    })()`,
    validate(value) {
      return value?.total === 13;
    },
  },
  "39_sync_async_extensions": {
    waitExpression:
      "Boolean(window.__MoonBit__ && window.__MoonBit__.math && window.__MoonBit__.add)",
    probeExpression: `;(async () => {
      const doubled = await window.__MoonBit__.math.double({ value: 7 });
      const sum = await window.__MoonBit__.add.slowAdd({
        left: 4,
        right: 6,
        delay_ms: 20
      });
      return { doubled, sum };
    })()`,
    validate(value) {
      return value?.doubled?.doubled === 14 && value?.sum?.total === 10;
    },
  },
  "40_event_broadcast": {
    waitExpression:
      "Boolean(window.__MoonBit__ && window.__MoonBit__.ticker && window.__MoonBit__.ticker.start)",
    probeExpression: `;(async () => {
      const events = [];
      window.__MoonBit__.ticker.on("tick", (event) => events.push(event));
      const result = await window.__MoonBit__.ticker.start({
        run_id: 77,
        count: 2,
        interval_ms: 100
      });
      return { result, events };
    })()`,
    validate(value) {
      return value?.result?.done?.total === 2 && value?.events?.length >= 1;
    },
  },
  "41_app_commands/app": {
    waitExpression:
      "Boolean(window.__MoonBit__ && window.__MoonBit__.core && window.__MoonBit__.core.invokeOp)",
    probeExpression: `;(async () => {
      const ping = await window.__MoonBit__.core.invokeOp("app:ping", { name: "cdp" });
      const sum = await window.__MoonBit__.core.invokeOp("app:slowAdd", {
        left: 4,
        right: 5,
        delay_ms: 20
      });
      const report = await window.__MoonBit__.core.invokeOp("app:reportProbe", {
        report: JSON.stringify({ source: "cdp", ping, sum })
      });
      return { ping, sum, report };
    })()`,
    validate(value) {
      return value?.sum?.total === 9 && value?.report?.ok === true;
    },
  },
};

const requested = process.argv.slice(2);
const examples = requested.includes("--all-examples")
  ? allExamples
  : requested.length > 0
    ? requested
    : Object.keys(scenarios);

const startupScenario = {
  waitExpression: "document.readyState !== 'loading'",
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)
    ),
  ]);
}

async function reservePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  const port = address.port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function waitForTarget(port, deadline) {
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      if (response.ok) {
        const targets = await response.json();
        const page = targets.find(
          (target) => target.type === "page" && target.webSocketDebuggerUrl,
        );
        if (page) {
          return page;
        }
      }
    } catch (error) {
      lastError = error;
    }
    await sleep(100);
  }
  throw new Error(
    `CDP target did not become available${lastError ? `: ${lastError.message}` : ""}`,
  );
}

function openCdp(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const pending = new Map();
    const listeners = new Map();
    let nextId = 1;

    ws.addEventListener("open", () => {
      resolve({
        call(method, params = {}) {
          const id = nextId++;
          ws.send(JSON.stringify({ id, method, params }));
          return new Promise((resolveCall, rejectCall) => {
            pending.set(id, { resolve: resolveCall, reject: rejectCall });
          });
        },
        close() {
          ws.close();
        },
        on(method, handler) {
          if (!listeners.has(method)) {
            listeners.set(method, []);
          }
          listeners.get(method).push(handler);
        },
      });
    });

    ws.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (!message.id || !pending.has(message.id)) {
        if (message.method && listeners.has(message.method)) {
          for (const handler of listeners.get(message.method)) {
            handler(message.params ?? {});
          }
        }
        return;
      }
      const entry = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        entry.reject(new Error(JSON.stringify(message.error)));
      } else {
        entry.resolve(message.result);
      }
    });

    ws.addEventListener("error", () => {
      reject(new Error("failed to open CDP websocket"));
    });

    ws.addEventListener("close", () => {
      for (const entry of pending.values()) {
        entry.reject(new Error("CDP websocket closed"));
      }
      pending.clear();
    });
  });
}

async function waitForBridge(cdp, scenario, deadline) {
  while (Date.now() < deadline) {
    try {
      const result = await cdp.call("Runtime.evaluate", {
        expression: scenario.waitExpression,
        returnByValue: true,
      });
      if (result.result?.value === true) {
        return;
      }
    } catch (error) {
      if (!String(error.message).includes("Execution context was destroyed")) {
        throw error;
      }
    }
    await sleep(100);
  }
  throw new Error("MoonBit JS bridge did not become available");
}

async function evaluateProbe(cdp, scenario) {
  let lastError = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await cdp.call("Runtime.evaluate", {
        awaitPromise: true,
        returnByValue: true,
        expression: scenario.probeExpression,
      });
    } catch (error) {
      lastError = error;
      if (!String(error.message).includes("Execution context was destroyed")) {
        throw error;
      }
      await sleep(250);
    }
  }
  throw lastError;
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

async function runExample(example) {
  const scenario = scenarios[example] ?? startupScenario;
  const functional = scenarios[example] !== undefined;
  const port = await reservePort();
  const child = spawn(
    "moon",
    ["-C", "examples", "run", example, "--target", "native"],
    {
      cwd: repoRoot,
      env: {
        ...process.env,
        WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:
          `--remote-debugging-port=${port} --remote-allow-origins=*`,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let output = "";
  child.stdout.on("data", (chunk) => {
    output += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    output += chunk.toString();
  });

  try {
    const deadline = Date.now() + timeoutMs;
    const target = await waitForTarget(port, deadline);
    const cdp = await withTimeout(openCdp(target.webSocketDebuggerUrl), 5000, "CDP connect");
    await cdp.call("Runtime.enable");
    await cdp.call("Page.enable").catch(() => {});
    cdp.on("Page.javascriptDialogOpening", () => {
      cdp.call("Page.handleJavaScriptDialog", { accept: true }).catch(() => {});
    });
    await waitForBridge(cdp, scenario, deadline);
    if (functional) {
      const probe = await evaluateProbe(cdp, scenario);
      const value = probe.result?.value;
      if (!scenario.validate(value)) {
        throw new Error(`unexpected probe result: ${JSON.stringify({ value, probe })}`);
      }
    }
    await cdp.call("Browser.close").catch(() => {});
    cdp.close();
    await withTimeout(
      new Promise((resolve) => child.once("exit", resolve)),
      5000,
      "example shutdown",
    ).catch(async () => {
      await terminateTree(child);
    });
    console.log(`${functional ? "CDP e2e" : "CDP startup"} passed for ${example} on port ${port}`);
  } catch (error) {
    await terminateTree(child);
    console.error(output.trim());
    throw error;
  }
}

async function main() {
  for (const example of examples) {
    await runExample(example);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
