import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(
  path.join(testDir, "../src/engine/cef_common/bridge_bootstrap.js"),
  "utf8",
);

function createBridge(url = "proton://app/") {
  const calls = [];
  const location = new URL(url);
  const context = vm.createContext({
    URL,
    Promise,
    location,
  });
  const install = vm.runInContext(source, context);
  const dispatcher = install(
    (action, id, name, payloadJson, pageInstance) =>
      calls.push({ action, id, name, payloadJson, pageInstance }),
    {
      source_origin: location.protocol === "proton:" ? "app" : location.origin,
      ops: [
        { name: "ext:add/sum" },
        { name: "app:ping" },
        { name: "app:devtoys.fs.stat" },
      ],
      extensions: [{ namespace: "add", apis: ["sum"] }],
      initialization_units: [],
    },
    "renderer-page-1",
  );
  return { calls, context, dispatcher };
}

test("installs the public bridge synchronously", () => {
  const { context, dispatcher } = createBridge();
  assert.ok(dispatcher);
  assert.equal(typeof context.__MoonBit__.core.invokeJson, "function");
  assert.equal(typeof context.__MoonBit__.core.invokeOp, "function");
  assert.equal(typeof context.__MoonBit__.events.onJson, "function");
  assert.equal(typeof context.__MoonBit__.add.sum, "function");
  assert.equal("ready" in context.__MoonBit__, false);
  assert.equal(context.__protonNativeInvokeOp, undefined);
});

test("rejects a missing native-selected grant", () => {
  const context = vm.createContext({
    URL,
    Promise,
    location: new URL("proton://app/"),
  });
  const install = vm.runInContext(source, context);
  assert.throws(
    () => install(() => {}, null, "renderer-page-1"),
    /grant must be an object/,
  );
});

test("settles one request through the private dispatcher", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.add.sum({ left: 20, right: 22 });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].action, "request");
  assert.equal(calls[0].name, "ext:add/sum");
  assert.deepEqual(JSON.parse(calls[0].payloadJson), {
    left: 20,
    right: 22,
  });
  assert.equal(calls[0].pageInstance, dispatcher.pageInstance);
  assert.equal(
    dispatcher.dispatchResponse(calls[0].id, true, '{"total":42}', ""),
    true,
  );
  assert.equal((await resultPromise).total, 42);
});

test("preserves JSON text across the typed bridge primitive", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.core.invokeJson(
    "app:echo",
    '{"value":"ping"}',
  );
  assert.equal(calls[0].name, "app:echo");
  assert.equal(calls[0].payloadJson, '{"value":"ping"}');
  dispatcher.dispatchResponse(calls[0].id, true, '{"value":"pong"}', "");
  assert.equal(await resultPromise, '{"value":"pong"}');
});

test("rejects JSON requests with structured bridge errors", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.core.invokeJson("app:fail", "{}");
  dispatcher.dispatchResponse(
    calls[0].id,
    false,
    "",
    '{"code":"backend_failed","message":"command failed","detail":"test"}',
  );
  await assert.rejects(resultPromise, (error) => {
    assert.equal(error.name, "ProtonBridgeError");
    assert.equal(error.code, "backend_failed");
    assert.equal(error.message, "command failed");
    assert.equal(error.detail, "test");
    return true;
  });
});

test("cancels renderer pending state without settling late replies", async () => {
  const { calls, context, dispatcher } = createBridge();
  const controller = new AbortController();
  const resultPromise = context.__MoonBit__.core.invokeJson(
    "app:cancel",
    "{}",
    { signal: controller.signal },
  );
  controller.abort();
  await assert.rejects(resultPromise, (error) => {
    assert.equal(error.code, "request_cancelled");
    return true;
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1], {
    action: "cancel",
    id: calls[0].id,
    name: "",
    payloadJson: "",
    pageInstance: dispatcher.pageInstance,
  });
  assert.equal(
    dispatcher.dispatchResponse(calls[0].id, true, '{"late":true}', ""),
    false,
  );
});

test("rejects an invalid abort signal without poisoning disposal", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.core.invokeJson(
    "app:invalid-signal",
    "{}",
    { signal: {} },
  );
  let failure;
  try {
    await resultPromise;
  } catch (error) {
    failure = error;
  }
  assert.equal(failure?.name, "TypeError");
  assert.equal(
    failure?.message,
    "Proton bridge options.signal must be an AbortSignal",
  );
  assert.equal(calls.length, 0);
  assert.doesNotThrow(() => dispatcher.dispose("test complete"));
  assert.equal(calls.length, 0);
});

test("rolls back pending state when abort listener registration fails", async () => {
  const { calls, context, dispatcher } = createBridge();
  const signal = {
    aborted: false,
    addEventListener() {
      throw new Error("registration failed");
    },
    removeEventListener() {},
  };
  await assert.rejects(
    context.__MoonBit__.core.invokeJson(
      "app:registration-failure",
      "{}",
      { signal },
    ),
    /registration failed/,
  );
  assert.equal(calls.length, 0);
  assert.doesNotThrow(() => dispatcher.dispose("test complete"));
  assert.equal(calls.length, 0);
});

test("delivers extension events and supports unsubscribe", () => {
  const { context, dispatcher } = createBridge();
  const received = [];
  const unsubscribe = context.__MoonBit__.add.on("finished", (event) => {
    received.push(event.payload.total);
  });
  assert.equal(
    dispatcher.dispatchEvent(
      '{"kind":"extension","extension":"add","name":"finished","payload":{"total":42}}',
    ),
    true,
  );
  unsubscribe();
  dispatcher.dispatchEvent(
    '{"kind":"extension","extension":"add","name":"finished","payload":{"total":43}}',
  );
  assert.deepEqual(received, [42]);
});

test("delivers raw JSON event payloads on typed routes", () => {
  const { context, dispatcher } = createBridge();
  const received = [];
  const unsubscribe = context.__MoonBit__.events.onJson(
    "ext:add/finished",
    (payloadJson) => received.push(payloadJson),
  );
  dispatcher.dispatchEvent(
    '{"kind":"extension","extension":"add","name":"finished","payload":{"total":42}}',
  );
  unsubscribe();
  assert.deepEqual(received, ['{"total":42}']);
});

test("drops events targeted at a different page instance", async () => {
  const { calls, context, dispatcher } = createBridge();
  const request = context.__MoonBit__.add.sum({});
  const pageInstance = calls[0].pageInstance;
  const received = [];
  context.__MoonBit__.add.on("finished", (event) => received.push(event));
  assert.equal(
    dispatcher.dispatchEvent(
      JSON.stringify({
        kind: "extension",
        extension: "add",
        name: "finished",
        payload: null,
        page_instance: `${pageInstance}-stale`,
      }),
    ),
    false,
  );
  dispatcher.dispatchResponse(calls[0].id, true, "null", "");
  await request;
  assert.deepEqual(received, []);
});

test("rejects pending requests when the context is disposed", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.add.sum({});
  dispatcher.dispose("navigation replaced the context");
  await assert.rejects(resultPromise, /navigation replaced the context/);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].action, "cancel");
  assert.equal(calls[1].id, calls[0].id);
  await assert.rejects(
    context.__MoonBit__.add.sum({}),
    /context has been disposed/,
  );
});

test("keeps a request pending until an explicit response", async () => {
  const { calls, context, dispatcher } = createBridge();
  let settled = false;
  const resultPromise = context.__MoonBit__.core.invokeOp("app:wait", {});
  resultPromise.then(
    () => { settled = true; },
    () => { settled = true; },
  );
  await new Promise((resolve) => setTimeout(resolve, 5));
  assert.equal(settled, false);
  assert.equal(calls.length, 1);
  dispatcher.dispatchResponse(calls[0].id, true, '{"done":true}', "");
  assert.equal((await resultPromise).done, true);
});

test("forwards invokeOp cancellation to native", async () => {
  const { calls, context, dispatcher } = createBridge();
  const controller = new AbortController();
  const resultPromise = context.__MoonBit__.add.sum(
    {},
    { signal: controller.signal },
  );
  controller.abort();
  await assert.rejects(resultPromise, (error) => {
    assert.equal(error.code, "request_cancelled");
    return true;
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1], {
    action: "cancel",
    id: calls[0].id,
    name: "",
    payloadJson: "",
    pageInstance: dispatcher.pageInstance,
  });
});

test("uses the page instance assigned by native", () => {
  const { dispatcher } = createBridge("https://example.com/");
  assert.equal(dispatcher.pageInstance, "renderer-page-1");
});

test("exposes a proxy for every granted application command", async () => {
  const { calls, context, dispatcher } = createBridge();
  assert.equal(typeof context.__MoonBit__.app.ping, "function");
  assert.equal(typeof context.__MoonBit__.app["devtoys.fs.stat"], "function");

  const ping = context.__MoonBit__.app.ping({ value: 1 });
  assert.equal(calls[0].name, "app:ping");
  assert.deepEqual(JSON.parse(calls[0].payloadJson), { value: 1 });
  dispatcher.dispatchResponse(calls[0].id, true, '{"ok":true}', "");
  assert.equal((await ping).ok, true);

  const stat = context.__MoonBit__.app["devtoys.fs.stat"]({ path: "/tmp" });
  assert.equal(calls[1].name, "app:devtoys.fs.stat");
  dispatcher.dispatchResponse(calls[1].id, true, '{"kind":"dir"}', "");
  assert.equal((await stat).kind, "dir");
});

test("prefixes dynamic application command invocations", async () => {
  const { calls, context, dispatcher } = createBridge();
  const result = context.__MoonBit__.app.invoke("ping", { value: 2 });
  assert.equal(calls[0].name, "app:ping");
  dispatcher.dispatchResponse(calls[0].id, true, "null", "");
  await result;
});

test("does not expose application proxies for extension routes", () => {
  const { context } = createBridge();
  assert.equal(context.__MoonBit__.app.sum, undefined);
  assert.equal(context.__MoonBit__.app["ext:add/sum"], undefined);
});

test("delivers application events through the app namespace", () => {
  const { context, dispatcher } = createBridge();
  const received = [];
  const unsubscribe = context.__MoonBit__.app.on("changed", (event) => {
    received.push(event);
  });
  assert.equal(
    dispatcher.dispatchEvent(
      '{"kind":"frontend","name":"changed","payload":{"total":42}}',
    ),
    true,
  );
  unsubscribe();
  dispatcher.dispatchEvent(
    '{"kind":"frontend","name":"changed","payload":{"total":43}}',
  );
  assert.equal(received.length, 1);
  assert.equal(received[0].name, "changed");
  assert.equal(received[0].payload.total, 42);
});

test("keeps application events out of the extension name table", () => {
  const { context, dispatcher } = createBridge();
  const viaExtension = [];
  const viaFriendlyName = [];
  context.__MoonBit__.add.on("finished", (event) => viaExtension.push(event));
  context.__MoonBit__.events.on(
    "add.finished",
    (event) => viaFriendlyName.push(event),
  );

  // An application event whose name collides with extension "add"'s
  // "finished" route must not reach either friendly-name listener.
  dispatcher.dispatchEvent(
    '{"kind":"frontend","name":"add.finished","payload":{"secret":"app"}}',
  );
  assert.deepEqual(viaExtension, []);
  assert.deepEqual(viaFriendlyName, []);

  // The extension event still reaches them.
  dispatcher.dispatchEvent(
    '{"kind":"extension","extension":"add","name":"finished","payload":{"total":42}}',
  );
  assert.equal(viaExtension.length, 1);
  assert.equal(viaFriendlyName.length, 1);
});

test("rejects a non-function application event listener", () => {
  const { context } = createBridge();
  assert.throws(
    () => context.__MoonBit__.app.on("changed", null),
    /MoonBit.app.on expects a listener function/,
  );
});
