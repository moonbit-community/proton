#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const failures = [];

function readText(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
}

function protonModuleVersion() {
  const text = readText("proton/moon.mod");
  const match = text.match(/^version\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error("proton/moon.mod is missing a version field");
  }
  return match[1];
}

function checkEqual(label, actual, expected) {
  if (actual !== expected) {
    failures.push(`${label}: expected ${expected}, got ${actual}`);
  }
}

function checkPrebuiltManifests(expectedVersion) {
  const prebuiltRoot = path.join(repoRoot, "proton", "prebuilt");
  for (const platform of fs.readdirSync(prebuiltRoot).sort()) {
    const platformRoot = path.join(prebuiltRoot, platform);
    if (!fs.statSync(platformRoot).isDirectory()) {
      continue;
    }
    const manifestPath = path.join(platformRoot, "manifest.json");
    if (!fs.existsSync(manifestPath)) {
      failures.push(`proton/prebuilt/${platform}/manifest.json: missing`);
      continue;
    }
    const relativeManifest = path.relative(repoRoot, manifestPath);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    checkEqual(`${relativeManifest} platform`, manifest.platform, platform);
    checkEqual(
      `${relativeManifest} proton_version`,
      manifest.proton_version,
      expectedVersion,
    );
  }
}

function checkTemplateDefaults(expectedVersion) {
  const text = readText("cli/new/templates.mbt");
  const match = text.match(/^let default_proton_version\s*=\s*"([^"]+)"/m);
  if (!match) {
    failures.push("cli/new/templates.mbt: missing default_proton_version");
    return;
  }
  checkEqual(
    "cli/new/templates.mbt default_proton_version",
    match[1],
    expectedVersion,
  );
}

const expectedVersion = protonModuleVersion();
checkPrebuiltManifests(expectedVersion);
checkTemplateDefaults(expectedVersion);

if (failures.length > 0) {
  console.error("Release metadata is stale:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exitCode = 1;
} else {
  console.log(`[OK] Release metadata matches proton ${expectedVersion}.`);
}
