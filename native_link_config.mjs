#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

function nativeLinkPath(filePath) {
  if (process.platform !== "win32") {
    return filePath;
  }
  return filePath.replace(/\\/g, "/");
}

function requireFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing vendored native library: ${filePath}`);
  }
  return filePath;
}

function configuredLinkMode(env) {
  const rawValue =
    env.LEPUS_WEBVIEW_LINK ??
    process.env.LEPUS_WEBVIEW_LINK ??
    env.WEBVIEW_LINK ??
    process.env.WEBVIEW_LINK ??
    "static";
  const value = String(rawValue).trim().toLowerCase();
  if (value === "static") {
    return "static";
  }
  if (value === "shared" || value === "dynamic") {
    return "shared";
  }
  throw new Error(
    `Unsupported LEPUS_WEBVIEW_LINK value "${rawValue}". Use "static" or "shared".`,
  );
}

function linkDir(vendoredLibDir, target, mode) {
  return nativeLinkPath(path.join(vendoredLibDir, target, mode));
}

function linuxSystemLinkFlags() {
  try {
    return execFileSync(
      "pkg-config",
      ["--libs", "gtk+-3.0", "webkit2gtk-4.1"],
      { encoding: "utf8" },
    ).trim();
  } catch (error) {
    throw new Error(
      "Failed to resolve Linux system link flags via pkg-config for gtk+-3.0 and webkit2gtk-4.1. " +
      "Install the development packages before building MoonBit code.\n" +
      String(error),
    );
  }
}

function main() {
  const payload = JSON.parse(fs.readFileSync(0, "utf8"));
  const env = payload.env ?? {};
  const isWindows = process.platform === "win32" || env.OS === "Windows_NT";
  const rootDir = path.dirname(fileURLToPath(import.meta.url));
  const vendoredLibDir = path.join(rootDir, "lib");
  const mode = configuredLinkMode(env);

  if (isWindows) {
    const platformLibDir = linkDir(vendoredLibDir, "windows-x64", mode);
    requireFile(path.join(vendoredLibDir, "windows-x64", mode, "webview.lib"));
    if (mode === "shared") {
      requireFile(path.join(vendoredLibDir, "windows-x64", mode, "webview.dll"));
    }
    const webviewLib = nativeLinkPath(path.join(platformLibDir, "webview"));
    process.stdout.write(JSON.stringify({
      link_configs: [
        {
          package: "justjavac/lepus",
          link_libs: [
            webviewLib,
            "advapi32",
            "ole32",
            "shell32",
            "shlwapi",
            "user32",
            "version",
          ],
        },
      ],
    }));
    return;
  }

  if (process.platform === "darwin") {
    const platformLibDir = linkDir(vendoredLibDir, "macos-universal", mode);
    requireFile(
      path.join(
        vendoredLibDir,
        "macos-universal",
        mode,
        mode === "static" ? "libwebview.a" : "libwebview.dylib",
      ),
    );
    let linkFlags = "-framework WebKit";
    if (mode === "shared") {
      linkFlags += ` -Wl,-rpath,${platformLibDir}`;
    }
    process.stdout.write(JSON.stringify({
      link_configs: [
        {
          package: "justjavac/lepus",
          link_search_paths: [platformLibDir],
          link_libs: ["webview", "dl"],
          link_flags: linkFlags,
        },
      ],
    }));
    return;
  }

  const platformLibDir = linkDir(vendoredLibDir, "linux-x64", mode);
  requireFile(
    path.join(
      vendoredLibDir,
      "linux-x64",
      mode,
      mode === "static" ? "libwebview.a" : "libwebview.so",
    ),
  );
  const linkFlags = linuxSystemLinkFlags();
  if (mode === "shared") {
    linkFlags += ` -Wl,-rpath,${platformLibDir}`;
  }
  process.stdout.write(JSON.stringify({
    link_configs: [
      {
        package: "justjavac/lepus",
        link_search_paths: [platformLibDir],
        link_libs: ["webview", "dl"],
        link_flags: linkFlags,
      },
    ],
  }));
}

main();
