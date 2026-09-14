// Requires the setup-managed CEF runtime and helper, like Windows package CI.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { iconBytes } from "./windows_icon_fixture.mjs";
import { findResourceCompiler } from "../proton/windows_resources.mjs";

if (process.platform !== "win32") throw new Error("Run the Windows icon smoke on Windows");
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "proton icon smoke 测试 "));
const app = path.join(root, "app");
const version = fs.readFileSync(path.join(repo, "proton/moon.mod"), "utf8").match(/^version = "([^"]+)"/m)?.[1];
assert.ok(version);
const helper = process.env.PROTON_HELPER_PATH ?? path.join(os.homedir(), ".proton/helpers/win32-x64", version, "cef_process.exe");
const testHome = path.join(root, "home");
const env = {
  ...process.env, PROTON_NO_UPDATE_CHECK: "1",
  USERPROFILE: testHome, HOME: testHome,
  MOON_HOME: process.env.MOON_HOME ?? path.join(os.homedir(), ".moon"),
  PROTON_RUNTIME_STORE: process.env.PROTON_RUNTIME_STORE ?? path.join(os.homedir(), ".proton/store"),
};

function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {
    cwd, env, encoding: "utf8", windowsHide: true, maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed (${result.status}):\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

function cli(...args) {
  return run("moon", ["-C", path.join(repo, "cli"), "run", ".", "--target", "wasm", "--", "-C", app, ...args], repo);
}

// Read resource payloads independently of Proton's writer. This deliberately
// handles only the standard PE resource layout produced by the test build.
function resources(executable) {
  const bytes = fs.readFileSync(executable);
  const pe = bytes.readUInt32LE(0x3c);
  assert.equal(bytes.toString("ascii", pe, pe + 4), "PE\0\0");
  const optional = pe + 24;
  const magic = bytes.readUInt16LE(optional);
  assert.ok(magic === 0x20b || magic === 0x10b);
  const directories = optional + (magic === 0x20b ? 112 : 96);
  const resourceRva = bytes.readUInt32LE(directories + 16);
  if (resourceRva === 0) return [];
  const sections = optional + bytes.readUInt16LE(pe + 20);
  function offset(rva) {
    for (let i = 0; i < bytes.readUInt16LE(pe + 6); i++) {
      const section = sections + i * 40;
      const address = bytes.readUInt32LE(section + 12);
      const size = bytes.readUInt32LE(section + 16);
      if (rva >= address && rva < address + size) return bytes.readUInt32LE(section + 20) + rva - address;
    }
    throw new Error(`Unmapped resource RVA ${rva}`);
  }
  const base = offset(resourceRva);
  const entries = [];
  function walk(relative, ids) {
    assert.ok(ids.length <= 3);
    const directory = base + relative;
    const count = bytes.readUInt16LE(directory + 12) + bytes.readUInt16LE(directory + 14);
    for (let i = 0; i < count; i++) {
      const entry = directory + 16 + i * 8;
      const id = bytes.readUInt32LE(entry);
      const target = bytes.readUInt32LE(entry + 4);
      if (target & 0x80000000) walk(target & 0x7fffffff, [...ids, id]);
      else {
        const data = base + target;
        const start = offset(bytes.readUInt32LE(data));
        entries.push({ ids: [...ids, id], bytes: bytes.subarray(start, start + bytes.readUInt32LE(data + 4)) });
      }
    }
  }
  walk(0, []);
  return entries;
}

function iconResources(executable) {
  return resources(executable).filter(entry => entry.ids[0] === 3 || entry.ids[0] === 14);
}

try {
  // Use the setup/CI helper in a private fixture store, without modifying the
  // developer's immutable helper installation or depending on one in CI.
  const helperRoot = path.join(testHome, ".proton/helpers/win32-x64", version);
  fs.mkdirSync(helperRoot, { recursive: true });
  fs.copyFileSync(helper, path.join(helperRoot, "cef_process.exe"));
  fs.mkdirSync(app);
  const members = [...fs.readFileSync(path.join(repo, "moon.work"), "utf8").matchAll(/"(\.\/[^\"]+)"/g)]
    .map(match => path.resolve(repo, match[1]).replace(/\\/g, "/"));
  fs.writeFileSync(path.join(root, "moon.work"), `members = ${JSON.stringify([...members, "./app"])}\n`);
  fs.writeFileSync(path.join(app, "moon.mod"), `name = "proton_icon_smoke"\nimport { "moonbit-community/proton@${version}" }\npreferred_target = "native"\n`);
  // Existing non-icon resources must survive icon replacement and removal.
  fs.writeFileSync(path.join(app, "app.manifest"), '<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" name="Proton.IconSmoke" type="win32"/></assembly>');
  fs.writeFileSync(path.join(app, "fixture.rc"), '1 24 "app.manifest"\n42 RCDATA { 0x1234 }\n');
  run(findResourceCompiler(env), ["/nologo", "/fo", "fixture.res", "fixture.rc"], app);
  const fixtureLink = JSON.stringify(`"${path.join(app, "fixture.res").replace(/\\/g, "/")}"`);
  fs.writeFileSync(path.join(app, "moon.pkg"), `import { "moonbit-community/proton" }\npkgtype(kind: "executable")\nsupported_targets = "native"\noptions(link: { "native": { "cc-link-flags": ${fixtureLink} } })\n`);
  fs.writeFileSync(path.join(app, "main.mbt"), '///|\nfn main {\n  println(@proton.resource_dir())\n}\n');
  const config = { identifier: "dev.proton.icon-smoke", backend: { path: ".", package: "." }, package: { product_name: "Icon Smoke", version: "1.0.0", icons: ["application icon.ico"], formats: ["app"], output: "dist" } };
  const writeConfig = () => fs.writeFileSync(path.join(app, "proton.project.json"), JSON.stringify(config));
  const icon = path.join(app, "application icon.ico");
  fs.writeFileSync(icon, iconBytes(255));
  writeConfig();
  console.log("Building an application through the Wasm CLI with a multi-size ICO...");
  cli("build");
  const exe = path.join(root, "_build/native/debug/build/proton_icon_smoke/proton_icon_smoke.exe");
  const first = iconResources(exe);
  assert.equal(first.filter(entry => entry.ids[0] === 3).length, 2);
  assert.equal(first.find(entry => entry.ids[0] === 14).bytes.readUInt16LE(4), 2);
  const otherResources = resources(exe).filter(entry => entry.ids[0] !== 3 && entry.ids[0] !== 14);
  assert.ok(otherResources.some(entry => entry.ids[0] === 24), "the host should retain its application manifest");
  fs.writeFileSync(icon, iconBytes(128));
  console.log("Replacing the icon at the same path and checking incremental relinking...");
  cli("build");
  assert.notDeepEqual(iconResources(exe), first);
  assert.deepEqual(resources(exe).filter(entry => entry.ids[0] !== 3 && entry.ids[0] !== 14), otherResources);
  config.package.icons = [];
  writeConfig();
  cli("build");
  assert.deepEqual(iconResources(exe), []);
  console.log("Packaging with an --icon override through the Wasm CLI...");
  cli("package", "--format", "app", "--icon", icon);
  const packaged = path.join(app, "dist/icon-smoke/icon-smoke.exe");
  assert.equal(iconResources(packaged).filter(entry => entry.ids[0] === 3).length, 2);
  assert.deepEqual(iconResources(path.join(app, "dist/icon-smoke/cef_process.exe")), []);
  assert.ok(run(packaged, [], app).trim().length > 0);
  const inspect = path.join(root, "read-icon.ps1");
  fs.writeFileSync(inspect, `param([string]$Executable)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class IconProbe {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  public static extern uint ExtractIconExW(string file, int index, IntPtr large, IntPtr small, uint count);
}
'@
if ([IconProbe]::ExtractIconExW($Executable, -1, [IntPtr]::Zero, [IntPtr]::Zero, 0) -ne 1) { throw 'Windows could not read the application icon' }
`);
  run("powershell.exe", ["-NoProfile", "-File", inspect, packaged]);
  console.log("PASS: Wasm build/package, incremental replacement/removal, CLI override, helper isolation, executable launch and Windows icon extraction.");
} finally {
  // root was created by this invocation, outside the source checkout.
  fs.rmSync(root, { recursive: true, force: true });
}
