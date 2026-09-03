import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(
  path.join(testDir, "../src/engine/cef_common/window_controls_overlay.js"),
  "utf8",
);

class TestDOMRect {
  constructor(x, y, width, height) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

function createStyle() {
  const values = new Map();
  return {
    removeProperty(name) {
      values.delete(name);
    },
    setProperty(name, value) {
      values.set(name, value);
    },
    snapshot() {
      return Object.fromEntries(values);
    },
  };
}

function createOverlay(initial = [true, 96, 0, 704, 30, 100]) {
  const style = createStyle();
  const context = vm.createContext({
    DOMRect: TestDOMRect,
    Event,
    EventTarget,
    document: {
      documentElement: { style },
      addEventListener() {},
      removeEventListener() {},
    },
    navigator: {},
  });
  const install = vm.runInContext(source, context);
  const dispatcher = install(...initial);
  return { context, dispatcher, style };
}

test("installs Electron-compatible window controls overlay geometry", () => {
  const { context, style } = createOverlay();
  const overlay = context.navigator.windowControlsOverlay;

  assert.equal(overlay.visible, true);
  assert.deepEqual(
    { ...overlay.getTitlebarAreaRect() },
    { x: 96, y: 0, width: 704, height: 30 },
  );
  assert.deepEqual(style.snapshot(), {
    "--proton-titlebar-area-x": "96px",
    "--proton-titlebar-area-y": "0px",
    "--proton-titlebar-area-width": "704px",
    "--proton-titlebar-area-height": "30px",
  });
});

test("fires one geometrychange only when effective CSS geometry changes", () => {
  const { context, dispatcher } = createOverlay();
  const events = [];
  context.navigator.windowControlsOverlay.ongeometrychange = (event) => {
    events.push({
      visible: event.visible,
      rect: { ...event.titlebarAreaRect },
    });
  };

  assert.equal(dispatcher.update(true, 96, 0, 704, 30, 100), false);
  assert.equal(dispatcher.update(true, 192, 0, 1408, 60, 200), false);
  assert.equal(dispatcher.update(true, 96, 0, 604, 30, 100), true);
  assert.deepEqual(events, [{
    visible: true,
    rect: { x: 96, y: 0, width: 604, height: 30 },
  }]);
});

test("removes dynamic CSS geometry while the overlay is not visible", () => {
  const { context, dispatcher, style } = createOverlay();
  const events = [];
  context.navigator.windowControlsOverlay.addEventListener(
    "geometrychange",
    (event) => events.push({
      visible: event.visible,
      rect: { ...event.titlebarAreaRect },
    }),
  );

  assert.equal(dispatcher.update(false, 0, 0, 0, 0, 100), true);
  assert.equal(context.navigator.windowControlsOverlay.visible, false);
  assert.deepEqual(style.snapshot(), {});
  assert.deepEqual(events, [{
    visible: false,
    rect: { x: 0, y: 0, width: 0, height: 0 },
  }]);
});
