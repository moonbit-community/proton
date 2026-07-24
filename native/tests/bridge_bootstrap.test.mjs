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
  const context = vm.createContext({
    URL,
    Promise,
    clearTimeout,
    location: { href: url },
    setTimeout,
  });
  const install = vm.runInContext(source, context);
  const dispatcher = install(
    (id, name, payloadJson, pageInstance) =>
      calls.push({ id, name, payloadJson, pageInstance }),
    {
      origin_policy: {
        mode: "app_and_dev_origins",
        dev_origins: ["http://localhost:5173"],
      },
      request_timeout_ms: 1000,
      extensions: [{ namespace: "add", apis: ["sum"] }],
    },
    "renderer-page-1",
  );
  return { calls, context, dispatcher };
}

test("installs the public bridge synchronously", () => {
  const { context, dispatcher } = createBridge();
  assert.ok(dispatcher);
  assert.equal(typeof context.__MoonBit__.core.invokeOp, "function");
  assert.equal(typeof context.__MoonBit__.add.sum, "function");
  assert.equal("ready" in context.__MoonBit__, false);
  assert.equal(context.__protonNativeInvokeOp, undefined);
});

test("settles one request through the private dispatcher", async () => {
  const { calls, context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.add.sum({ left: 20, right: 22 });
  assert.equal(calls.length, 1);
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
  const { context, dispatcher } = createBridge();
  const resultPromise = context.__MoonBit__.add.sum({});
  dispatcher.dispose("navigation replaced the context");
  await assert.rejects(resultPromise, /navigation replaced the context/);
  await assert.rejects(
    context.__MoonBit__.add.sum({}),
    /context has been disposed/,
  );
});

test("uses the page instance assigned by native", () => {
  const { dispatcher } = createBridge("https://example.com/");
  assert.equal(dispatcher.pageInstance, "renderer-page-1");
});
