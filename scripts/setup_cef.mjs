#!/usr/bin/env node

import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const defaultCefName =
  "cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal";
const defaultCacheDir = path.join(repoRoot, ".cef-cache");
const defaultBaseUrl = "https://cef-builds.spotifycdn.com";

function fail(message) {
  console.error(message);
  process.exit(1);
}

function usage() {
  console.log(`Usage:
  node ./scripts/setup_cef.mjs [options]

Options:
  --cache <path>            Cache directory. Defaults to .cef-cache.
  --name <cef_binary_name>  CEF binary directory/archive name.
  --url <url>               Full CEF archive URL.
  --help                    Show this help.

Examples:
  node ./scripts/setup_cef.mjs
  node ./scripts/setup_cef.mjs --cache .cef-cache-local`);
}

function parseArgs(argv) {
  const options = {
    cache: defaultCacheDir,
    name: defaultCefName,
    url: "",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else if (arg === "--cache") {
      options.cache = requireValue(argv, ++i, arg);
    } else if (arg === "--name") {
      options.name = requireValue(argv, ++i, arg);
    } else if (arg === "--url") {
      options.url = requireValue(argv, ++i, arg);
    } else {
      fail(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function requireValue(argv, index, optionName) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    fail(`Missing value for ${optionName}`);
  }
  return value;
}

function requiredCefFiles(root) {
  return [
    "include/capi/cef_app_capi.h",
    "include/capi/cef_browser_capi.h",
    "include/capi/cef_client_capi.h",
    "include/capi/cef_v8_capi.h",
    "Release/libcef.lib",
    "Release/libcef.dll",
    "Resources/icudtl.dat",
  ].map((relativePath) => path.join(root, relativePath));
}

function validateCefRoot(root) {
  const missing = requiredCefFiles(root).filter((filePath) => !fs.existsSync(filePath));
  if (missing.length > 0) {
    fail(`Invalid CEF root: ${root}\nMissing:\n${missing.join("\n")}`);
  }
}

function archiveUrl(options) {
  return options.url || `${defaultBaseUrl}/${options.name}.tar.bz2`;
}

function download(url, destination) {
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  return new Promise((resolve, reject) => {
    const request = https.get(url, (response) => {
      if (
        response.statusCode >= 300 &&
        response.statusCode < 400 &&
        response.headers.location
      ) {
        response.resume();
        download(response.headers.location, destination).then(resolve, reject);
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Download failed with HTTP ${response.statusCode}: ${url}`));
        return;
      }
      const file = fs.createWriteStream(destination);
      response.pipe(file);
      file.on("finish", () => {
        file.close(resolve);
      });
      file.on("error", reject);
    });
    request.on("error", reject);
  });
}

function extractTarBz2(archivePath, cacheDir) {
  fs.mkdirSync(cacheDir, { recursive: true });
  const result = spawnSync("tar", ["-xjf", archivePath, "-C", cacheDir], {
    stdio: "inherit",
  });
  if (result.status !== 0) {
    fail(`tar failed with exit code ${result.status}`);
  }
}

async function main() {
  if (process.platform !== "win32") {
    fail("The Lepus CEF backend is currently Windows-only.");
  }

  const options = parseArgs(process.argv.slice(2));
  const cacheDir = path.resolve(options.cache);
  const cefRoot = path.join(cacheDir, options.name);
  const archivePath = path.join(cacheDir, `${options.name}.tar.bz2`);

  if (!fs.existsSync(cefRoot)) {
    if (!fs.existsSync(archivePath)) {
      const url = archiveUrl(options);
      console.error(`[INFO] Downloading CEF: ${url}`);
      await download(url, archivePath);
    } else {
      console.error(`[INFO] Using cached archive: ${archivePath}`);
    }
    console.error(`[INFO] Extracting: ${archivePath}`);
    extractTarBz2(archivePath, cacheDir);
  }

  validateCefRoot(cefRoot);
  console.log(cefRoot);
}

main().catch((error) => {
  fail(error.stack || error.message);
});
