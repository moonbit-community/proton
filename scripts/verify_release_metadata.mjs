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

function moduleVersion(relativePath) {
  const text = readText(relativePath);
  const match = text.match(/^version\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error(`${relativePath} is missing a version field`);
  }
  return match[1];
}

function moduleImportVersion(relativePath, moduleName) {
  const text = readText(relativePath);
  const escapedName = moduleName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = text.match(new RegExp(`"${escapedName}@([^"]+)"`));
  if (!match) {
    throw new Error(`${relativePath} is missing ${moduleName} dependency`);
  }
  return match[1];
}

function cliEmbeddedVersion() {
  const text = readText("cli/main.mbt");
  const match = text.match(/^let cli_current_version\s*:\s*String\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error("cli/main.mbt is missing cli_current_version");
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

const protonVersion = moduleVersion("proton/moon.mod");
const configVersion = moduleVersion("config/moon.mod");
const cliVersion = moduleVersion("cli/moon.mod");
checkPrebuiltManifests(protonVersion);
checkTemplateDefaults(protonVersion);
checkEqual(
  "proton/moon.mod proton_config dependency",
  moduleImportVersion("proton/moon.mod", "justjavac/proton_config"),
  configVersion,
);
checkEqual(
  "cli/moon.mod proton_config dependency",
  moduleImportVersion("cli/moon.mod", "justjavac/proton_config"),
  configVersion,
);
checkEqual("cli/main.mbt cli_current_version", cliEmbeddedVersion(), cliVersion);

if (failures.length > 0) {
  console.error("Release metadata is stale:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exitCode = 1;
} else {
  console.log(
    `[OK] Release metadata matches config ${configVersion}, proton ${protonVersion}, and CLI ${cliVersion}.`,
  );
}
