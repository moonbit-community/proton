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
  const libDir = path.join(root, "Release");
  requirePath(root, "Release/libcef.lib");
  requirePath(root, "Release/libcef.dll");
  requirePath(root, "Resources/icudtl.dat");
  return {
    link_search_paths: [nativeLinkPath(libDir)],
    link_libs: ["libcef", "user32", "gdi32", "ole32", "shell32"],
  };
}

function macosConfig(root) {
  const frameworkDir = path.join(root, "Release");
  requirePath(root, "include/capi/cef_app_capi.h");
  requirePath(
    root,
    "Release/Chromium Embedded Framework.framework/Chromium Embedded Framework",
  );
  return {
    link_flags:
      `-F ${nativeLinkPath(frameworkDir)} -framework "Chromium Embedded Framework"`,
  };
}

function linuxConfig(root) {
  requirePath(root, "include/capi/cef_app_capi.h");
  requirePath(root, "Release/libcef.so");
  requirePath(root, "Resources/icudtl.dat");
  const libDir = path.join(root, "Release");
  return {
    link_search_paths: [nativeLinkPath(libDir)],
    link_libs: ["cef", "dl", "pthread"],
    link_flags: `-Wl,-rpath,${nativeLinkPath(libDir)}`,
  };
}

function platformConfig(root) {
  if (process.platform === "win32") {
    return windowsConfig(root);
  }
  if (process.platform === "darwin") {
    return macosConfig(root);
  }
  return linuxConfig(root);
}

function main() {
  const env = optionalPayloadEnv();
  const rawRoot = envValue(env, "LEPUS_CEF_ROOT").trim();

  if (rawRoot.length === 0) {
    process.stdout.write(JSON.stringify({
      vars: {
        LEPUS_CEF_ENABLED: "0",
      },
      link_configs: [],
    }));
    return;
  }

  const root = path.resolve(rawRoot);
  const config = platformConfig(root);
  process.stdout.write(JSON.stringify({
    vars: {
      LEPUS_CEF_ENABLED: "1",
      LEPUS_CEF_ROOT: nativeLinkPath(root),
    },
    link_configs: [
      {
        package: "justjavac/lepus_cef",
        ...config,
      },
    ],
  }));
}

main();
