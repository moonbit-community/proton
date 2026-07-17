#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const nativeRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(nativeRoot, "..");
const dist = path.resolve(process.argv[2] ?? path.join(nativeRoot, "dist"));
const configScript = path.join(repoRoot, "proton", "native_link_config.mjs");
const developmentDist = path.join(nativeRoot, "dist");

function fail(message) {
  console.error(message);
  process.exit(1);
}

function requireFile(filePath, label) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    fail(`${label} is missing: ${filePath}`);
  }
}

function requireDir(dirPath, label) {
  if (!fs.existsSync(dirPath) || !fs.statSync(dirPath).isDirectory()) {
    fail(`${label} is missing: ${dirPath}`);
  }
}

function normalizedForLink(filePath) {
  return filePath.replace(/\\/g, "/");
}

function readLinkConfig(payload, cwd = repoRoot) {
  const result = spawnSync(process.execPath, [configScript], {
    cwd,
    input: JSON.stringify(payload),
    encoding: "utf8",
  });

  if (result.status !== 0) {
    fail(result.stderr.trim() || "proton/native_link_config.mjs failed");
  }

  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`proton/native_link_config.mjs returned invalid JSON: ${error.message}`);
  }
}

const binDir = path.join(dist, "bin");
const libDir = path.join(dist, "lib");
requireDir(binDir, "Proton native runtime directory");
requireDir(libDir, "Proton native library directory");

let expectedLinkNeedle;
if (process.platform === "win32") {
  const dll = path.join(binDir, "proton.dll");
  const importLib = path.join(libDir, "proton.lib");
  requireFile(dll, "Proton DLL");
  requireFile(importLib, "Proton import library");
  expectedLinkNeedle = normalizedForLink(importLib);
} else if (process.platform === "darwin") {
  const dylib = path.join(libDir, "libproton.dylib");
  requireFile(dylib, "Proton dylib");
  expectedLinkNeedle = `-L"${normalizedForLink(libDir)}"`;
} else {
  const so = path.join(libDir, "libproton.so");
  requireFile(so, "Proton shared library");
  expectedLinkNeedle = `-L"${normalizedForLink(libDir)}"`;
}

const config = readLinkConfig({ env: { PROTON_NATIVE_DIST: dist } });

const vars = config?.vars ?? {};
if (vars.PROTON_NATIVE_RUNTIME_DIR !== normalizedForLink(binDir)) {
  fail(
    `PROTON_NATIVE_RUNTIME_DIR mismatch: expected ${normalizedForLink(binDir)}, got ${vars.PROTON_NATIVE_RUNTIME_DIR}`,
  );
}

if (process.platform === "win32") {
  const helperPath = vars.PROTON_HELPER_PATH;
  const expectedHelper = path.join(binDir, "cef_process.exe");
  if (fs.existsSync(expectedHelper)) {
    if (typeof helperPath !== "string" || helperPath.length === 0) {
      fail("PROTON_HELPER_PATH is missing from native link config");
    }
    if (path.resolve(helperPath) !== path.resolve(expectedHelper)) {
      fail(
        `PROTON_HELPER_PATH mismatch: expected ${expectedHelper}, got ${helperPath}`,
      );
    }
    requireFile(helperPath, "Proton helper executable");
  }
}

const linkFlags = vars.PROTON_NATIVE_LINK_FLAGS ?? "";
if (!linkFlags.includes(expectedLinkNeedle)) {
  fail(
    `PROTON_NATIVE_LINK_FLAGS does not reference installed library: ${linkFlags}`,
  );
}

if (process.platform === "darwin") {
  const packageRpath = "@executable_path/../Resources/proton/lib";
  const packageConfig = readLinkConfig({
    env: {
      PROTON_NATIVE_DIST: dist,
      PROTON_PACKAGE_RPATH: packageRpath,
    },
  });
  const packageFlags = packageConfig?.vars?.PROTON_NATIVE_LINK_FLAGS ?? "";
  if (!packageFlags.includes(packageRpath)) {
    fail(`package rpath is missing from native link flags: ${packageFlags}`);
  }
  if (packageFlags.includes(`-rpath,\"${normalizedForLink(libDir)}\"`)) {
    fail(`package link flags retain the absolute runtime rpath: ${packageFlags}`);
  }
}

if (fs.existsSync(developmentDist)) {
  const isolatedCwd = fs.mkdtempSync(
    path.join(os.tmpdir(), "proton-link-config-"),
  );
  try {
    const defaultConfig = readLinkConfig({ env: {} }, isolatedCwd);
    const defaultRoot = defaultConfig?.vars?.PROTON_RUNTIME_ROOT ?? "";
    if (defaultRoot !== normalizedForLink(developmentDist)) {
      fail(
        `default native dist mismatch: expected ${normalizedForLink(developmentDist)}, got ${defaultRoot}`,
      );
    }
  } finally {
    fs.rmSync(isolatedCwd, { recursive: true, force: true });
  }
}

process.stdout.write(
  `Proton native link config ok: ${vars.PROTON_NATIVE_RUNTIME_DIR}\n`,
);
