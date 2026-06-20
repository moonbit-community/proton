#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL(".", import.meta.url));
const defaultCefDirName = ".cef-cache";
const defaultSubprocessPath = path.join(
  repoRoot,
  "_build",
  "native",
  "debug",
  "build",
  "justjavac",
  "proton",
  "cef_process",
  "cef_process.exe",
);

function nativeLinkPath(filePath) {
  if (process.platform !== "win32") {
    return filePath;
  }
  return filePath.replace(/\\/g, "/");
}

function optionalPayloadEnv() {
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

function requiredCefFiles(root, requireVersion) {
  const files = [
    "include/capi/cef_app_capi.h",
    "include/capi/cef_browser_capi.h",
    "include/capi/cef_client_capi.h",
    "include/capi/cef_v8_capi.h",
    "Release/libcef.lib",
    "Release/libcef.dll",
    "Release/icudtl.dat",
    "Release/chrome_100_percent.pak",
    "Release/chrome_200_percent.pak",
    "Release/resources.pak",
    "Resources/icudtl.dat",
  ].map((relativePath) => path.join(root, relativePath));
  if (requireVersion) {
    files.push(path.join(root, "version.txt"));
  }
  return files;
}

function missingCefFiles(root, requireVersion) {
  return requiredCefFiles(root, requireVersion)
    .filter((candidate) => !fs.existsSync(candidate));
}

function isCefRoot(root, requireVersion) {
  return missingCefFiles(root, requireVersion).length === 0;
}

function installGuide(message) {
  return [
    message,
    "",
    "CEF is required for the Windows native backend.",
    "Install it with:",
    "  node .\\scripts\\setup_cef.mjs",
    "",
    `Expected layout: ${path.join(repoRoot, defaultCefDirName)}`,
    "The CEF files should live directly in .cef-cache, with version.txt at the root.",
  ].join("\n");
}

function defaultCefRoot() {
  const candidates = [
    path.resolve(process.cwd(), defaultCefDirName),
    path.join(repoRoot, defaultCefDirName),
  ];
  const unique = [...new Set(candidates)];
  for (const candidate of unique) {
    if (isCefRoot(candidate, true)) {
      return candidate;
    }
  }
  const existing = unique.find((candidate) => fs.existsSync(candidate));
  if (existing) {
    const missing = missingCefFiles(existing, true);
    throw new Error(installGuide(
      `Invalid CEF install directory: ${existing}\nMissing:\n${missing.join("\n")}`,
    ));
  }
  throw new Error(installGuide("CEF is not installed."));
}

function cStringDefine(value) {
  return value.replace(/\\/g, "/").replace(/"/g, "\\\"");
}

function windowsConfig(root) {
  for (const filePath of requiredCefFiles(root, false)) {
    if (!fs.existsSync(filePath)) {
      throw new Error(`Missing CEF file: ${filePath}`);
    }
  }

  return {
    link_libs: [
      nativeLinkPath(path.join(root, "Release/libcef")),
      "user32",
      "gdi32",
      "ole32",
      "shell32",
      "advapi32",
      "comdlg32",
    ],
    link_flags: "/link /DELAYLOAD:libcef.dll delayimp.lib",
  };
}

function main() {
  const env = optionalPayloadEnv();
  const rawRoot = envValue(env, "PROTON_CEF_ROOT").trim();

  if (process.platform !== "win32") {
    process.stdout.write(JSON.stringify({
      vars: {
        PROTON_CEF_ENABLED: "0",
        PROTON_CEF_STUB_CC_FLAGS: "",
      },
      link_configs: [],
    }));
    return;
  }

  const root = rawRoot.length === 0
    ? defaultCefRoot()
    : path.resolve(rawRoot);
  const rawSubprocess = envValue(env, "PROTON_CEF_SUBPROCESS_PATH").trim();
  const subprocess = rawSubprocess.length === 0
    ? defaultSubprocessPath
    : path.resolve(rawSubprocess);
  if (subprocess.length > 0 && !fs.existsSync(subprocess)) {
    if (rawSubprocess.length > 0) {
      throw new Error(`Missing CEF subprocess executable: ${subprocess}`);
    }
  }
  process.stdout.write(JSON.stringify({
    vars: {
      PROTON_CEF_ENABLED: "1",
      PROTON_CEF_ROOT: nativeLinkPath(root),
      PROTON_CEF_SUBPROCESS_PATH: nativeLinkPath(subprocess),
      PROTON_CEF_STUB_CC_FLAGS:
        `/DPROTON_CEF_ENABLED=1 ` +
        `/DPROTON_CEF_ROOT_PATH=\\"${cStringDefine(root)}\\" ` +
        `/DPROTON_CEF_SUBPROCESS_PATH=\\"${cStringDefine(subprocess)}\\" ` +
        `/I"${nativeLinkPath(root)}"`,
    },
    link_configs: [
      {
        package: "justjavac/proton/webview",
        ...windowsConfig(root),
      },
    ],
  }));
}

try {
  main();
} catch (error) {
  console.error(error?.message ?? String(error));
  process.exit(1);
}
