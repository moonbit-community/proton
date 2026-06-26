#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));

function readPayloadEnv() {
  try {
    const raw = fs.readFileSync(0, "utf8").trim();
    if (raw.length === 0) {
      return {};
    }
    return JSON.parse(raw).env ?? {};
  } catch {
    return {};
  }
}

function envValue(env, name) {
  return env[name] ?? process.env[name] ?? "";
}

function nativeLinkPath(filePath) {
  return filePath.replace(/\\/g, "/");
}

function quote(filePath) {
  return `"${nativeLinkPath(filePath)}"`;
}

function firstExistingDist(candidates) {
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return candidates[0];
}

function defaultDist() {
  return firstExistingDist([
    path.join(moduleRoot, "dist"),
    path.join(moduleRoot, "native", "dist"),
    path.resolve(moduleRoot, "..", "native", "dist"),
  ]);
}

function linkFlags(dist) {
  const libDir = path.join(dist, "lib");
  if (process.platform === "win32") {
    return quote(path.join(libDir, "proton.lib"));
  }
  if (process.platform === "darwin") {
    return `-L${quote(libDir)} -lproton -Wl,-rpath,${quote(libDir)}`;
  }
  return `-L${quote(libDir)} -lproton -Wl,-rpath,${quote(libDir)}`;
}

function linkConfig(dist, packageName) {
  const libDir = path.join(dist, "lib");
  if (process.platform === "win32") {
    return {
      package: packageName,
      link_libs: [nativeLinkPath(path.join(libDir, "proton"))],
    };
  }
  return {
    package: packageName,
    link_libs: ["proton"],
    link_flags: `-L${quote(libDir)} -Wl,-rpath,${quote(libDir)}`,
  };
}

function helperPath(binDir) {
  const exe = process.platform === "win32" ? "cef_process.exe" : "cef_process";
  const candidate = path.join(binDir, exe);
  return fs.existsSync(candidate) ? nativeLinkPath(candidate) : "";
}

export function createNativeLinkConfig(env = readPayloadEnv()) {
  const rawDist = envValue(env, "PROTON_NATIVE_DIST").trim();
  const dist = path.resolve(rawDist.length === 0 ? defaultDist() : rawDist);
  const binDir = path.join(dist, "bin");
  return {
    vars: {
      PROTON_NATIVE_LINK_FLAGS: linkFlags(dist),
      PROTON_NATIVE_STUB_CC_FLAGS: "",
      PROTON_NATIVE_RUNTIME_DIR: nativeLinkPath(binDir),
      PROTON_RUNTIME_ROOT: nativeLinkPath(dist),
      PROTON_HELPER_PATH: helperPath(binDir),
    },
    link_configs: [
      linkConfig(dist, "justjavac/proton/native"),
      linkConfig(dist, "justjavac/proton"),
    ],
  };
}

function main() {
  process.stdout.write(JSON.stringify(createNativeLinkConfig()));
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main();
}
