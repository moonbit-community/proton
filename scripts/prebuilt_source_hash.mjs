#!/usr/bin/env node

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.resolve(scriptDir, "..");

const commonSourceInputs = [
  "cli/cef/cef_platform.mbt",
  "native/CMakeLists.txt",
  "native/include",
  "native/src/app_runner.h",
  "native/src/cef_process.c",
  "native/src/engine/cef_common",
  "native/src/proton.c",
  "native/src/proton_app_instance.c",
  "native/src/proton_app_instance.h",
  "native/src/proton_config.c",
  "native/src/proton_config.h",
  "native/src/proton_engine.h",
  "native/src/proton_handle.h",
  "native/src/proton_internal.h",
  "native/src/proton_json.c",
  "native/src/proton_json.h",
  "native/src/proton_state.c",
  "native/src/proton_state.h",
  "native/src/proton_update.c",
  "native/src/proton_update.h",
  "proton/moon.mod",
];

// Each list describes everything in this repository that can affect the
// corresponding staged runtime. Platform-only sources stay separate so a
// Windows titlebar change does not unnecessarily invalidate macOS and Linux.
export const platformSourceInputs = Object.freeze({
  "darwin-arm64": [
    ...commonSourceInputs,
    ".github/workflows/build-macos-prebuilt.yml",
    "native/src/app_runner.m",
    "native/src/engine/cef_mac",
  ],
  "linux-x64": [
    ...commonSourceInputs,
    ".github/workflows/build-linux-prebuilt.yml",
    "native/src/app_runner_linux.c",
    "native/src/engine/cef_linux",
    "native/src/engine/notification_stub.c",
    "native/src/engine/platform_events_stub.c",
  ],
  "win32-x64": [
    ...commonSourceInputs,
    ".github/workflows/build-windows-prebuilt.yml",
    "native/src/app_runner_win.c",
    "native/src/engine/cef_win",
    "native/src/engine/notification_stub.c",
    "native/src/engine/platform_events_stub.c",
  ],
});

export class PrebuiltSourceHasher {
  constructor(repoRoot) {
    this.repoRoot = path.resolve(repoRoot);
  }

  files(inputPaths) {
    const files = new Set();
    const pending = inputPaths.map(inputPath => path.resolve(this.repoRoot, inputPath));
    while (pending.length > 0) {
      const pathname = pending.pop();
      const relative = path.relative(this.repoRoot, pathname);
      if (relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
        throw new Error(`source input escapes the repository: ${pathname}`);
      }
      let stat;
      try {
        stat = fs.lstatSync(pathname);
      } catch (error) {
        throw new Error(`missing source input ${relative}: ${error.message}`);
      }
      if (stat.isDirectory()) {
        for (const entry of fs.readdirSync(pathname)) {
          pending.push(path.join(pathname, entry));
        }
      } else if (stat.isFile()) {
        files.add(relative.split(path.sep).join("/"));
      } else {
        throw new Error(`source input is not a regular file or directory: ${relative}`);
      }
    }
    return [...files].sort();
  }

  hash(inputPaths) {
    const digest = createHash("sha256");
    for (const relative of this.files(inputPaths)) {
      // Hash the path as well as the bytes so renames and file additions are
      // visible even when their contents match another input.
      digest.update(relative);
      digest.update("\0");
      digest.update(fs.readFileSync(path.join(this.repoRoot, relative)));
      digest.update("\0");
    }
    return `sha256:${digest.digest("hex")}`;
  }
}

export function prebuiltSourceHash({
  repoRoot = defaultRepoRoot,
  platform,
  sourceInputs = platformSourceInputs,
}) {
  const inputs = sourceInputs[platform];
  if (!inputs) {
    throw new Error(`unsupported prebuilt platform: ${platform}`);
  }
  return new PrebuiltSourceHasher(repoRoot).hash(inputs);
}

export function recordPrebuiltSourceHash({
  repoRoot = defaultRepoRoot,
  platform,
  sourceInputs = platformSourceInputs,
}) {
  const manifestPath = path.join(
    repoRoot,
    "proton",
    "prebuilt",
    platform,
    "manifest.json",
  );
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const stampedManifest = {
    platform: manifest.platform,
    proton_version: manifest.proton_version,
    source_hash: prebuiltSourceHash({ repoRoot, platform, sourceInputs }),
    artifacts: manifest.artifacts,
  };
  fs.writeFileSync(manifestPath, `${JSON.stringify(stampedManifest, null, 2)}\n`);
  return stampedManifest.source_hash;
}

export function verifyPrebuiltSourceHashes({
  repoRoot = defaultRepoRoot,
  sourceInputs = platformSourceInputs,
} = {}) {
  const failures = [];
  for (const platform of Object.keys(sourceInputs).sort()) {
    const relativeManifest = `proton/prebuilt/${platform}/manifest.json`;
    const manifestPath = path.join(repoRoot, relativeManifest);
    let manifest;
    try {
      manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    } catch (error) {
      failures.push(`${relativeManifest}: ${error.message}`);
      continue;
    }
    let expected;
    try {
      expected = prebuiltSourceHash({ repoRoot, platform, sourceInputs });
    } catch (error) {
      failures.push(`${platform}: ${error.message}`);
      continue;
    }
    if (manifest.source_hash !== expected) {
      failures.push(
        `${relativeManifest}: stale source_hash; rebuild the ${platform} prebuilt`,
      );
    }
  }
  return failures;
}

function usage() {
  console.error(
    "Usage: node scripts/prebuilt_source_hash.mjs [--verify | --print <platform> | --record <platform>]",
  );
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 2 && args[0] === "--print") {
    try {
      console.log(prebuiltSourceHash({ platform: args[1] }));
    } catch (error) {
      console.error(`Unable to hash Proton prebuilt sources: ${error.message}`);
      process.exitCode = 1;
    }
    return;
  }
  if (args.length === 2 && args[0] === "--record") {
    try {
      const hash = recordPrebuiltSourceHash({ platform: args[1] });
      console.log(`[OK] Recorded ${args[1]} prebuilt source hash ${hash}.`);
    } catch (error) {
      console.error(`Unable to record Proton prebuilt source hash: ${error.message}`);
      process.exitCode = 1;
    }
    return;
  }
  if (args.length > 1 || (args.length === 1 && args[0] !== "--verify")) {
    usage();
    process.exitCode = 2;
    return;
  }
  const failures = verifyPrebuiltSourceHashes();
  if (failures.length > 0) {
    console.error("Proton prebuilt source validation failed:");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log("[OK] Proton prebuilt source hashes match their build inputs.");
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main();
}
