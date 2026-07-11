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

function darwinWarningFlags(cc) {
  if (!/^(?:.*\/)?(?:clang|cc)$/.test(cc)) {
    return "";
  }
  // ld64 has a narrow switch for duplicate libraries, but duplicate rpaths
  // only honor the general warning suppressor. Keep this Darwin-only.
  return "-Wl,-no_warn_duplicate_libraries -Wl,-w";
}

function firstExistingDist(candidates) {
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return candidates[0];
}

function platformId() {
  return `${process.platform}-${process.arch}`;
}

function packagePrebuiltDist() {
  return path.resolve(moduleRoot, "prebuilt", platformId());
}

function findProjectRootWithRuntime(start) {
  for (let current = path.resolve(start); ; current = path.dirname(current)) {
    const manifest = path.join(current, ".proton", "runtime.json");
    if (fs.existsSync(manifest)) {
      return { root: current, manifest };
    }
    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }
  }
}

function activeRuntimeDist() {
  const found = findProjectRootWithRuntime(process.cwd());
  if (!found) {
    return "";
  }
  try {
    const manifest = JSON.parse(fs.readFileSync(found.manifest, "utf8"));
    if (manifest.platform && manifest.platform !== platformId()) {
      return "";
    }
    if (typeof manifest.dist !== "string" || manifest.dist.length === 0) {
      return "";
    }
    const dist = path.isAbsolute(manifest.dist)
      ? manifest.dist
      : path.resolve(found.root, manifest.dist);
    return fs.existsSync(dist) ? dist : "";
  } catch {
    return "";
  }
}

function defaultDist() {
  const activeDist = activeRuntimeDist();
  if (activeDist.length > 0) {
    return activeDist;
  }
  return firstExistingDist([
    packagePrebuiltDist(),
    path.resolve(moduleRoot, "..", "native", "dist"),
  ]);
}

function appendFlags(...parts) {
  return parts.filter(part => part.length > 0).join(" ");
}

function linuxRpathLinkFlag(binDir, cc) {
  return cc.length > 0 ? `-Wl,-rpath-link,${quote(binDir)}` : "";
}

function linkFlags(dist, cc, rpathOverride) {
  const libDir = path.join(dist, "lib");
  const binDir = path.join(dist, "bin");
  if (process.platform === "win32") {
    return quote(path.join(libDir, "proton.lib"));
  }
  if (process.platform === "darwin") {
    const rpath = rpathOverride.length > 0 ? rpathOverride : libDir;
    return appendFlags(
      `-L${quote(libDir)} -lproton -Wl,-rpath,${quote(rpath)}`,
      darwinWarningFlags(cc),
    );
  }
  return appendFlags(
    `-L${quote(libDir)} -lproton -Wl,-rpath,${quote(libDir)}`,
    linuxRpathLinkFlag(binDir, cc),
  );
}

function linkConfig(dist, packageName, cc, rpathOverride) {
  const libDir = path.join(dist, "lib");
  const binDir = path.join(dist, "bin");
  if (process.platform === "win32") {
    return {
      package: packageName,
      link_libs: [nativeLinkPath(path.join(libDir, "proton"))],
    };
  }
  return {
    package: packageName,
    link_libs: ["proton"],
    link_flags:
      process.platform === "darwin"
        ? appendFlags(
          `-L${quote(libDir)} -Wl,-rpath,${quote(rpathOverride.length > 0 ? rpathOverride : libDir)}`,
          darwinWarningFlags(cc),
        )
        : appendFlags(
          `-L${quote(libDir)} -Wl,-rpath,${quote(libDir)}`,
          linuxRpathLinkFlag(binDir, cc),
        ),
  };
}

function helperPath(binDir) {
  const exe = process.platform === "win32" ? "cef_process.exe" : "cef_process";
  const candidate = path.join(binDir, exe);
  return fs.existsSync(candidate) ? nativeLinkPath(candidate) : "";
}

export function createNativeLinkConfig(env = readPayloadEnv()) {
  const rawDist = envValue(env, "PROTON_NATIVE_DIST").trim();
  const cc = envValue(env, "MOON_CC").trim();
  const rpathOverride = envValue(env, "PROTON_PACKAGE_RPATH").trim();
  const dist = path.resolve(rawDist.length === 0 ? defaultDist() : rawDist);
  const binDir = path.join(dist, "bin");
  return {
    vars: {
      PROTON_NATIVE_LINK_FLAGS: linkFlags(dist, cc, rpathOverride),
      PROTON_NATIVE_STUB_CC_FLAGS: "",
      PROTON_NATIVE_RUNTIME_DIR: nativeLinkPath(binDir),
      PROTON_RUNTIME_ROOT: nativeLinkPath(dist),
      PROTON_HELPER_PATH: helperPath(binDir),
    },
    link_configs: [
      linkConfig(dist, "justjavac/proton/native", cc, rpathOverride),
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
