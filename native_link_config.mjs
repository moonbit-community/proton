#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

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

function requirePath(root, relativePath) {
  const candidate = path.join(root, relativePath);
  if (!fs.existsSync(candidate)) {
    throw new Error(`Missing CEF file: ${candidate}`);
  }
  return candidate;
}

function windowsConfig(root) {
  requirePath(root, "include/capi/cef_app_capi.h");
  requirePath(root, "include/capi/cef_browser_capi.h");
  requirePath(root, "include/capi/cef_client_capi.h");
  requirePath(root, "include/capi/cef_v8_capi.h");
  requirePath(root, "Release/libcef.lib");
  requirePath(root, "Release/libcef.dll");
  requirePath(root, "Resources/icudtl.dat");

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
  const rawRoot = envValue(env, "LEPUS_CEF_ROOT").trim();

  if (rawRoot.length === 0) {
    process.stdout.write(JSON.stringify({
      vars: {
        LEPUS_CEF_ENABLED: "0",
        LEPUS_CEF_STUB_CC_FLAGS: "",
      },
      link_configs: [],
    }));
    return;
  }

  if (process.platform !== "win32") {
    throw new Error(
      "The root CEF backend is currently implemented for Windows only. " +
      "Unset LEPUS_CEF_ROOT or build on Windows.",
    );
  }

  const root = path.resolve(rawRoot);
  process.stdout.write(JSON.stringify({
    vars: {
      LEPUS_CEF_ENABLED: "1",
      LEPUS_CEF_ROOT: nativeLinkPath(root),
      LEPUS_CEF_STUB_CC_FLAGS:
        `/DLEPUS_CEF_ENABLED=1 /I"${nativeLinkPath(root)}"`,
    },
    link_configs: [
      {
        package: "justjavac/lepus",
        ...windowsConfig(root),
      },
    ],
  }));
}

main();
