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

function moduleName(relativePath) {
  const text = readText(relativePath);
  const match = text.match(/^name\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error(`${relativePath} is missing a name field`);
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

function templateDefault(text, name) {
  const match = text.match(
    new RegExp(`^let ${name}\\s*=\\s*"([^"]+)"`, "m"),
  );
  if (!match) {
    failures.push(`cli/new/templates.mbt: missing ${name}`);
    return null;
  }
  return match[1];
}

function checkTemplateDefaults(expected) {
  const text = readText("cli/new/templates.mbt");
  for (const [name, version] of Object.entries(expected)) {
    const actual = templateDefault(text, name);
    if (actual !== null) {
      checkEqual(`cli/new/templates.mbt ${name}`, actual, version);
    }
  }
}

const workspaceModuleManifests = [
  "cdp/moon.mod",
  "codegen/moon.mod",
  "config/moon.mod",
  "contract/moon.mod",
  "rsa/moon.mod",
  "updater/moon.mod",
  "sys/auto_launch/moon.mod",
  "sys/clipboard/moon.mod",
  "sys/ffi/moon.mod",
  "sys/global_hotkey/moon.mod",
  "sys/keepawake/moon.mod",
  "sys/microphone/moon.mod",
  "sys/tray/moon.mod",
  "client/moon.mod",
  "rabbita/moon.mod",
  "proton/moon.mod",
  "extensions/moon.mod",
  "cli/moon.mod",
  "examples/moon.mod",
  "e2e/moon.mod",
];

function checkLockstepVersions(expectedVersion) {
  const workspaceModuleNames = new Set(
    workspaceModuleManifests.map(moduleName),
  );
  for (const manifest of workspaceModuleManifests) {
    checkEqual(`${manifest} version`, moduleVersion(manifest), expectedVersion);
    for (const match of readText(manifest).matchAll(/"([^"]+)@([^"]+)"/g)) {
      const [, dependency, version] = match;
      if (workspaceModuleNames.has(dependency)) {
        checkEqual(
          `${manifest} ${dependency} dependency`,
          version,
          expectedVersion,
        );
      }
    }
  }
}

const protonVersion = moduleVersion("proton/moon.mod");
const codegenVersion = moduleVersion("codegen/moon.mod");
const configVersion = moduleVersion("config/moon.mod");
const contractVersion = moduleVersion("contract/moon.mod");
const clientVersion = moduleVersion("client/moon.mod");
const rabbitaVersion = moduleVersion("rabbita/moon.mod");
const cliVersion = moduleVersion("cli/moon.mod");
checkLockstepVersions(protonVersion);
checkTemplateDefaults({
  default_proton_version: protonVersion,
  default_proton_codegen_version: codegenVersion,
  default_proton_cli_version: cliVersion,
  default_proton_contract_version: contractVersion,
  default_proton_client_version: clientVersion,
  default_proton_rabbita_version: rabbitaVersion,
});
checkEqual(
  "proton/moon.mod proton_config dependency",
  moduleImportVersion("proton/moon.mod", "moonbit-community/proton_config"),
  configVersion,
);
checkEqual(
  "cli/moon.mod proton_config dependency",
  moduleImportVersion("cli/moon.mod", "moonbit-community/proton_config"),
  configVersion,
);
checkEqual(
  "proton/moon.mod proton_contract dependency",
  moduleImportVersion("proton/moon.mod", "moonbit-community/proton_contract"),
  contractVersion,
);
checkEqual(
  "client/moon.mod proton_contract dependency",
  moduleImportVersion("client/moon.mod", "moonbit-community/proton_contract"),
  contractVersion,
);
checkEqual(
  "rabbita/moon.mod proton_contract dependency",
  moduleImportVersion("rabbita/moon.mod", "moonbit-community/proton_contract"),
  contractVersion,
);
checkEqual(
  "rabbita/moon.mod proton_client dependency",
  moduleImportVersion("rabbita/moon.mod", "moonbit-community/proton_client"),
  clientVersion,
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
    `[OK] Release metadata and workspace modules match lockstep version ${protonVersion}.`,
  );
}
