import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

function isFile(file) {
  try {
    return fs.statSync(file).isFile();
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

function environmentValue(env, name) {
  const key = Object.keys(env).find(key => key.toLowerCase() === name.toLowerCase());
  return key === undefined ? undefined : env[key];
}

// The resource compiler is part of the Windows SDK already required for the
// native host build. A normal shell need not have run VsDevCmd beforehand.
export function findResourceCompiler(env) {
  const searchPath = environmentValue(env, "PATH");
  for (const directory of searchPath?.split(path.delimiter) ?? []) {
    if (!directory) continue;
    const candidate = path.join(directory.replace(/^"|"$/g, ""), "rc.exe");
    if (isFile(candidate)) return candidate;
  }
  const roots = [];
  const configured = environmentValue(env, "WindowsSdkDir");
  if (configured) roots.push(configured);
  const programFiles = environmentValue(env, "ProgramFiles(x86)");
  if (programFiles) roots.push(path.join(programFiles, "Windows Kits", "10"));
  const hostArch = process.arch === "arm64" ? "arm64" : "x64";
  for (const root of roots) {
    const bin = path.join(root, "bin");
    let versions;
    try {
      versions = fs.readdirSync(bin, { withFileTypes: true })
        .filter(entry => entry.isDirectory() && /^\d+(\.\d+)+$/.test(entry.name))
        .map(entry => entry.name)
        .sort((a, b) => b.localeCompare(a, "en", { numeric: true }));
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    const version = environmentValue(env, "WindowsSDKVersion")?.replace(/[\\/]+$/, "");
    if (version) versions.unshift(version);
    for (const sdkVersion of new Set(versions)) {
      for (const arch of [hostArch, "x86"]) {
        const candidate = path.join(bin, sdkVersion, arch, "rc.exe");
        if (isFile(candidate)) return candidate;
      }
    }
  }
  throw new Error("Windows icon compilation requires rc.exe from the Windows SDK; install the SDK or use a Visual Studio developer shell");
}

function validateIcon(bytes, file) {
  const invalid = () => { throw new Error(`Invalid Windows ICO: ${file}`); };
  if (bytes.length < 6 || bytes.readUInt16LE(0) !== 0 || bytes.readUInt16LE(2) !== 1) invalid();
  const count = bytes.readUInt16LE(4);
  const directoryEnd = 6 + count * 16;
  if (count === 0 || bytes.length < directoryEnd) invalid();
  for (let i = 0; i < count; i++) {
    const entry = 6 + i * 16;
    const size = bytes.readUInt32LE(entry + 8);
    const offset = bytes.readUInt32LE(entry + 12);
    if (size === 0 || offset < directoryEnd || offset + size > bytes.length) invalid();
  }
}

// This private build request is set only on the application Moon subprocess.
// JSON null means no icon, including when removing a previous configuration.
export function compileWindowsIcon(request, env = process.env) {
  if (request === undefined) return undefined;
  const resource = JSON.parse(request);
  if (resource === null) return undefined;
  if (typeof resource.icon !== "string" || !path.isAbsolute(resource.icon) ||
      typeof resource.output_dir !== "string" || !path.isAbsolute(resource.output_dir)) {
    throw new Error("PROTON_WINDOWS_APP_RESOURCE requires absolute icon and output_dir paths");
  }
  const bytes = fs.readFileSync(resource.icon);
  validateIcon(bytes, resource.icon);
  const digest = createHash("sha256").update("proton-windows-icon-v1\0").update(bytes).digest("hex");
  const output = path.join(resource.output_dir, `${digest}.res`);
  if (isFile(output)) return output;
  const compiler = findResourceCompiler(env);
  fs.mkdirSync(resource.output_dir, { recursive: true });
  const staging = fs.mkdtempSync(path.join(resource.output_dir, "compile-"));
  try {
    // Fixed relative names avoid RC string escaping and source path encodings.
    fs.writeFileSync(path.join(staging, "app.ico"), bytes);
    fs.writeFileSync(path.join(staging, "app.rc"), '1 ICON "app.ico"\n');
    const result = spawnSync(compiler, ["/nologo", "/fo", "app.res", "app.rc"], {
      cwd: staging, env, encoding: "utf8", windowsHide: true,
    });
    if (result.error) throw new Error(`Cannot start Windows resource compiler: ${result.error.message}`);
    if (result.status !== 0) {
      throw new Error(`Windows icon compilation failed (${result.status ?? result.signal}): ${(result.stderr + result.stdout).trim()}`);
    }
    // Concurrent builds may compile the same content. Never expose partial
    // output to the linker, and accept an already-published identical result.
    try {
      fs.renameSync(path.join(staging, "app.res"), output);
    } catch (error) {
      if (!isFile(output) || !fs.readFileSync(output).equals(fs.readFileSync(path.join(staging, "app.res")))) throw error;
    }
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
  return output;
}
