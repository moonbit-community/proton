#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL(".", import.meta.url));
const defaultCefRoot = path.join(repoRoot, ".cef-cache");
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

function cStringDefine(value) {
  return value.replace(/\\/g, "/").replace(/"/g, "\\\"");
}

function emptyConfig() {
  return {
    vars: {
      PROTON_CEF_ENABLED: "0",
      PROTON_CEF_STUB_CC_FLAGS: "",
    },
    link_configs: [],
  };
}

function windowsConfig(root, subprocess) {
  return {
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
      },
    ],
  };
}

function main() {
  const env = optionalPayloadEnv();
  const rawRoot = envValue(env, "PROTON_CEF_ROOT").trim();

  if (process.platform !== "win32") {
    process.stdout.write(JSON.stringify(emptyConfig()));
    return;
  }

  const root = rawRoot.length === 0
    ? defaultCefRoot
    : path.resolve(rawRoot);
  const rawSubprocess = envValue(env, "PROTON_CEF_SUBPROCESS_PATH").trim();
  const subprocess = rawSubprocess.length === 0
    ? defaultSubprocessPath
    : path.resolve(rawSubprocess);
  process.stdout.write(JSON.stringify(windowsConfig(root, subprocess)));
}

try {
  main();
} catch (error) {
  console.error(error?.message ?? String(error));
  process.exit(1);
}
