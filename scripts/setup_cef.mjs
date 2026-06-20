#!/usr/bin/env node

import fs from "node:fs";
import https from "node:https";
import os from "node:os";
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
  --name <cef_binary_name>  CEF binary directory/archive name.
  --url <url>               Full CEF archive URL.
  --help                    Show this help.

Examples:
  node ./scripts/setup_cef.mjs`);
}

function parseArgs(argv) {
  const options = {
    name: defaultCefName,
    url: "",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
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

function sourceCefFiles(root) {
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

function installedCefFiles(root) {
  return [
    ...sourceCefFiles(root).map((filePath) => path.relative(root, filePath)),
    "Release/icudtl.dat",
    "Release/chrome_100_percent.pak",
    "Release/chrome_200_percent.pak",
    "Release/resources.pak",
  ].map((relativePath) => path.join(root, relativePath));
}

function validateCefRoot(root) {
  const missing = [
    ...installedCefFiles(root),
    path.join(root, "version.txt"),
  ].filter((filePath) => !fs.existsSync(filePath));
  if (missing.length > 0) {
    fail(`Invalid CEF root: ${root}\nMissing:\n${missing.join("\n")}`);
  }
}

function hasSourceCefFiles(root) {
  return sourceCefFiles(root).every((filePath) => fs.existsSync(filePath));
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

function extractTarBz2(archivePath, destination) {
  fs.mkdirSync(destination, { recursive: true });
  const result = spawnSync("tar", ["-xjf", archivePath, "-C", destination], {
    stdio: "inherit",
  });
  if (result.status !== 0) {
    fail(`tar failed with exit code ${result.status}`);
  }
}

function assertSafeInstallDir(installDir) {
  const parsed = path.parse(installDir);
  if (
    installDir === parsed.root ||
    installDir === repoRoot ||
    installDir === path.dirname(repoRoot)
  ) {
    fail(`Refusing to replace unsafe CEF install directory: ${installDir}`);
  }
}

function findExtractedRoot(extractDir, name) {
  const named = path.join(extractDir, name);
  if (hasSourceCefFiles(named)) {
    return named;
  }
  const candidates = fs.readdirSync(extractDir)
    .filter((entry) => entry.startsWith("cef_binary_"))
    .map((entry) => path.join(extractDir, entry))
    .filter((entry) => hasSourceCefFiles(entry));
  if (candidates.length === 1) {
    return candidates[0];
  }
  fail(`Could not find extracted CEF root in ${extractDir}`);
}

function installCefRoot(extractedRoot, installDir, name) {
  assertSafeInstallDir(installDir);
  fs.rmSync(installDir, { recursive: true, force: true });
  fs.mkdirSync(installDir, { recursive: true });
  fs.cpSync(extractedRoot, installDir, { recursive: true });
  normalizeCefRuntimeLayout(installDir);
  fs.writeFileSync(path.join(installDir, "version.txt"), `${name}\n`, "utf8");
}

function normalizeCefRuntimeLayout(root) {
  const releaseDir = path.join(root, "Release");
  const resourcesDir = path.join(root, "Resources");
  fs.mkdirSync(releaseDir, { recursive: true });
  for (const fileName of [
    "icudtl.dat",
    "chrome_100_percent.pak",
    "chrome_200_percent.pak",
    "resources.pak",
  ]) {
    const source = path.join(resourcesDir, fileName);
    if (fs.existsSync(source)) {
      fs.copyFileSync(source, path.join(releaseDir, fileName));
    }
  }
}

async function main() {
  if (process.platform !== "win32") {
    fail("The Proton CEF backend is currently Windows-only.");
  }

  const options = parseArgs(process.argv.slice(2));
  const installDir = path.resolve(defaultCacheDir);
  const versionPath = path.join(installDir, "version.txt");
  const installedVersion = fs.existsSync(versionPath)
    ? fs.readFileSync(versionPath, "utf8").trim()
    : "";

  if (installedVersion === options.name) {
    normalizeCefRuntimeLayout(installDir);
  } else {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "proton-cef-"));
    const archivePath = path.join(tempDir, `${options.name}.tar.bz2`);
    try {
      const url = archiveUrl(options);
      console.error(`[INFO] Downloading CEF: ${url}`);
      await download(url, archivePath);
      console.error(`[INFO] Extracting: ${archivePath}`);
      extractTarBz2(archivePath, tempDir);
      const extractedRoot = findExtractedRoot(tempDir, options.name);
      console.error(`[INFO] Installing CEF into: ${installDir}`);
      installCefRoot(extractedRoot, installDir, options.name);
    } finally {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }

  validateCefRoot(installDir);
  console.log(installDir);
}

main().catch((error) => {
  fail(error.stack || error.message);
});
