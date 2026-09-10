import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { iconBytes } from "../scripts/windows_icon_fixture.mjs";
import { createNativeLinkConfig } from "./build.mjs";
import { compileWindowsIcon, findResourceCompiler } from "./windows_resources.mjs";

function temporary(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "proton icon 测试 "));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return root;
}


test("no resource request needs no SDK or output directory", () => {
  assert.equal(compileWindowsIcon(undefined, {}), undefined);
  assert.equal(compileWindowsIcon("null", {}), undefined);
  assert.throws(() => compileWindowsIcon('{"icon":"relative.ico","output_dir":"relative"}', {}), /absolute/);
});

test("compiler discovery honors PATH and the configured SDK version", t => {
  const root = temporary(t);
  const bin = path.join(root, "bin");
  const arch = process.arch === "arm64" ? "arm64" : "x64";
  for (const version of ["10.0.9.0", "10.0.10.0"]) {
    fs.mkdirSync(path.join(bin, version, arch), { recursive: true });
    fs.writeFileSync(path.join(bin, version, arch, "rc.exe"), "fixture");
  }
  assert.equal(findResourceCompiler({ WindowsSdkDir: root }), path.join(bin, "10.0.10.0", arch, "rc.exe"));
  assert.equal(findResourceCompiler({ WindowsSdkDir: root, WindowsSDKVersion: "10.0.9.0\\" }), path.join(bin, "10.0.9.0", arch, "rc.exe"));
  assert.equal(findResourceCompiler({ Path: path.join(bin, "10.0.9.0", arch), WindowsSdkDir: root }), path.join(bin, "10.0.9.0", arch, "rc.exe"));
  assert.throws(() => findResourceCompiler({}), /rc.exe from the Windows SDK/);
});

test("missing and malformed icons fail before invoking the compiler", t => {
  const root = temporary(t);
  const icon = path.join(root, "icon.ico");
  const request = JSON.stringify({ icon, output_dir: path.join(root, "out") });
  assert.throws(() => compileWindowsIcon(request, {}), { code: "ENOENT" });
  for (const bytes of [Buffer.from("not an ICO"), iconBytes(255).subarray(0, 100)]) {
    fs.writeFileSync(icon, bytes);
    assert.throws(() => compileWindowsIcon(request, {}), /Invalid Windows ICO/);
  }
  fs.writeFileSync(icon, iconBytes(255));
  assert.throws(() => compileWindowsIcon(request, {}), /rc.exe from the Windows SDK/);
});

test("real SDK compiles Unicode paths and changing content changes linker input", { skip: process.platform !== "win32" }, t => {
  const root = temporary(t);
  const icon = path.join(root, 'application icon.ico');
  const request = JSON.stringify({ icon, output_dir: path.join(root, "resources") });
  fs.writeFileSync(icon, iconBytes(255));
  const first = compileWindowsIcon(request);
  assert.ok(fs.statSync(first).size > 0);
  // Identical content is reusable even without the SDK in the environment.
  assert.equal(compileWindowsIcon(request, {}), first);
  fs.writeFileSync(icon, iconBytes(128));
  const second = compileWindowsIcon(request);
  assert.notEqual(second, first);
  assert.notDeepEqual(fs.readFileSync(first), fs.readFileSync(second));

  const config = createNativeLinkConfig({ PROTON_WINDOWS_APP_RESOURCE: request });
  const app = config.link_configs.find(entry => entry.package === "moonbit-community/proton");
  assert.equal(app.link_flags, `"${second.replace(/\\/g, "/")}"`);
  const ffi = config.link_configs.find(entry => entry.package.endsWith("/internal/native/ffi"));
  assert.ok(!ffi.link_flags.includes(second.replace(/\\/g, "/")));
  const removed = createNativeLinkConfig({ PROTON_WINDOWS_APP_RESOURCE: "null" });
  assert.ok(!removed.link_configs.some(entry => entry.package === "moonbit-community/proton"));
  assert.deepEqual(fs.readdirSync(path.join(root, "resources")).sort(), [path.basename(first), path.basename(second)].sort());
});
