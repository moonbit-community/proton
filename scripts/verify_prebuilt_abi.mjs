#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.resolve(scriptDir, "..");

const platformLayouts = {
  "darwin-arm64": {
    libraryKey: "shared_lib",
    requiredArtifactKeys: ["shared_lib", "helper", "header"],
  },
  "darwin-x64": {
    libraryKey: "shared_lib",
    requiredArtifactKeys: ["shared_lib", "helper", "header"],
  },
  "linux-x64": {
    libraryKey: "shared_lib",
    requiredArtifactKeys: ["shared_lib", "helper", "header"],
  },
  "win32-x64": {
    libraryKey: "dll",
    importLibraryKey: "import_lib",
    requiredArtifactKeys: ["dll", "helper", "import_lib", "header"],
  },
};
// Only platforms with committed release artifacts are mandatory. Additional
// layouts may be declared here ahead of publishing their first prebuilt.
const requiredPlatforms = ["darwin-arm64", "linux-x64", "win32-x64"];

export function publicAbiSymbols(headerText) {
  const symbols = new Set();
  const withoutComments = headerText
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/.*$/gm, "");
  const declarationPattern = /^[ \t]*PROTON_API\b([^;]*);/gm;
  for (const declaration of withoutComments.matchAll(declarationPattern)) {
    const name = declaration[1].match(/\b(proton_[A-Za-z0-9_]+)\s*\(/);
    if (name) {
      symbols.add(name[1]);
    }
  }
  return [...symbols].sort();
}

export function exportedProtonSymbols(toolOutput) {
  const symbols = new Set();
  const pattern = /(?:^|[^A-Za-z0-9_])(?:__imp_)?_?(proton_[A-Za-z0-9_]+)/g;
  for (const match of toolOutput.matchAll(pattern)) {
    symbols.add(match[1]);
  }
  return [...symbols].sort();
}

export function compareSymbolSets(
  label,
  expectedSymbols,
  actualSymbols,
) {
  const failures = [];
  const expected = new Set(expectedSymbols);
  const actual = new Set(actualSymbols);
  for (const symbol of expected) {
    if (!actual.has(symbol)) {
      failures.push(`${label}: missing public ABI export ${symbol}`);
    }
  }
  for (const symbol of actual) {
    if (!expected.has(symbol)) {
      failures.push(`${label}: unexpected Proton export ${symbol}`);
    }
  }
  return failures;
}

function relativeArtifactPath(platformRoot, value, label, failures) {
  if (typeof value !== "string" || value.length === 0) {
    failures.push(`${label}: missing non-empty artifact path`);
    return null;
  }
  if (path.isAbsolute(value)) {
    failures.push(`${label}: artifact path must be relative: ${value}`);
    return null;
  }
  const resolved = path.resolve(platformRoot, value);
  if (!resolved.startsWith(platformRoot + path.sep)) {
    failures.push(`${label}: artifact path escapes the platform directory: ${value}`);
    return null;
  }
  return resolved;
}

function readManifest(manifestPath, failures) {
  try {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
      failures.push(`${manifestPath}: manifest must be a JSON object`);
      return null;
    }
    return manifest;
  } catch (error) {
    failures.push(`${manifestPath}: ${error.message}`);
    return null;
  }
}

function readTextFile(filePath, label, failures) {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (error) {
    failures.push(`${label}: ${error.message}`);
    return null;
  }
}

function protonModuleVersion(repoRoot, failures) {
  const modulePath = path.join(repoRoot, "proton", "moon.mod");
  const text = readTextFile(modulePath, "proton/moon.mod", failures);
  if (text === null) {
    return null;
  }
  const match = text.match(/^version\s*=\s*"([^"]+)"/m);
  if (!match) {
    failures.push("proton/moon.mod: missing version field");
    return null;
  }
  return match[1];
}

function regularFile(pathname, label, failures) {
  try {
    if (!fs.lstatSync(pathname).isFile()) {
      failures.push(`${label}: not a regular file`);
      return false;
    }
    return true;
  } catch (error) {
    failures.push(`${label}: ${error.message}`);
    return false;
  }
}

function inspectCommand(platform, libraryPath) {
  if (platform === "darwin-arm64") {
    return { command: "nm", args: ["-gU", libraryPath] };
  }
  if (platform === "linux-x64") {
    return { command: "nm", args: ["-D", "--defined-only", libraryPath] };
  }
  if (platform === "win32-x64") {
    return process.platform === "win32"
      ? { command: "dumpbin", args: ["/nologo", "/exports", libraryPath] }
      : { command: "objdump", args: ["-p", libraryPath] };
  }
  throw new Error(`unsupported prebuilt platform: ${platform}`);
}

function inspectExports(platform, libraryPath, failures) {
  const { command, args } = inspectCommand(platform, libraryPath);
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error) {
    failures.push(
      `${platform}: failed to run ${command}: ${result.error.message}`,
    );
    return [];
  }
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    failures.push(
      `${platform}: ${command} failed with exit code ${result.status}` +
        (detail.length > 0 ? `: ${detail}` : ""),
    );
    return [];
  }
  return exportedProtonSymbols(result.stdout);
}

function inspectImportLibrary(platform, libraryPath, failures) {
  const command = process.platform === "win32" ? "dumpbin" : "nm";
  const args =
    process.platform === "win32"
      ? ["/nologo", "/linkermember:1", libraryPath]
      : [libraryPath];
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error) {
    failures.push(
      `${platform}: failed to run ${command} for import library: ${result.error.message}`,
    );
    return [];
  }
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    failures.push(
      `${platform}: ${command} failed for import library with exit code ${result.status}` +
        (detail.length > 0 ? `: ${detail}` : ""),
    );
    return [];
  }
  return exportedProtonSymbols(result.stdout);
}

export function verifyPrebuiltAbi({
  repoRoot = defaultRepoRoot,
  symbolPlatform = null,
} = {}) {
  const failures = [];
  const sourceHeaderPath = path.join(
    repoRoot,
    "native",
    "include",
    "proton_native.h",
  );
  if (!fs.existsSync(sourceHeaderPath)) {
    return [`native/include/proton_native.h: missing`];
  }
  const sourceHeader = readTextFile(
    sourceHeaderPath,
    "native/include/proton_native.h",
    failures,
  );
  if (sourceHeader === null) {
    return failures;
  }
  const expectedSymbols = publicAbiSymbols(sourceHeader);
  if (expectedSymbols.length === 0) {
    failures.push("native/include/proton_native.h: no PROTON_API symbols found");
  }
  const expectedVersion = protonModuleVersion(repoRoot, failures);

  const prebuiltRoot = path.join(repoRoot, "proton", "prebuilt");
  if (!fs.existsSync(prebuiltRoot)) {
    return [...failures, "proton/prebuilt: missing"];
  }
  const platforms = fs
    .readdirSync(prebuiltRoot)
    .filter(name => fs.statSync(path.join(prebuiltRoot, name)).isDirectory())
    .sort();

  for (const platform of requiredPlatforms) {
    if (!platforms.includes(platform)) {
      failures.push(`proton/prebuilt/${platform}: missing`);
    }
  }

  if (symbolPlatform !== null && !platforms.includes(symbolPlatform)) {
    if (!requiredPlatforms.includes(symbolPlatform)) {
      failures.push(`unsupported prebuilt platform: ${symbolPlatform}`);
    }
  }

  for (const platform of platforms) {
    const layout = platformLayouts[platform];
    if (!layout) {
      failures.push(
        `proton/prebuilt/${platform}: unsupported platform; add its ABI layout to scripts/verify_prebuilt_abi.mjs`,
      );
      continue;
    }
    const platformRoot = path.join(prebuiltRoot, platform);
    const manifestPath = path.join(platformRoot, "manifest.json");
    if (!fs.existsSync(manifestPath)) {
      failures.push(`proton/prebuilt/${platform}/manifest.json: missing`);
      continue;
    }
    const manifest = readManifest(manifestPath, failures);
    if (!manifest) {
      continue;
    }
    const allowedManifestFields = ["platform", "proton_version", "artifacts"];
    for (const key of Object.keys(manifest)) {
      if (!allowedManifestFields.includes(key)) {
        failures.push(
          `proton/prebuilt/${platform}/manifest.json: unknown field ${key}`,
        );
      }
    }
    if (manifest.platform !== platform) {
      failures.push(
        `proton/prebuilt/${platform}/manifest.json: expected platform ${platform}, got ${manifest.platform}`,
      );
    }
    if (
      expectedVersion !== null &&
      manifest.proton_version !== expectedVersion
    ) {
      failures.push(
        `proton/prebuilt/${platform}/manifest.json: expected proton_version ${expectedVersion}, got ${manifest.proton_version}`,
      );
    }
    if (
      !manifest.artifacts ||
      typeof manifest.artifacts !== "object" ||
      Array.isArray(manifest.artifacts)
    ) {
      failures.push(
        `proton/prebuilt/${platform}/manifest.json: missing artifacts object`,
      );
      continue;
    }
    for (const key of Object.keys(manifest.artifacts)) {
      if (!layout.requiredArtifactKeys.includes(key)) {
        failures.push(
          `proton/prebuilt/${platform}/manifest.json: unknown artifacts field ${key}`,
        );
      }
    }
    const resolvedArtifacts = {};
    for (const key of layout.requiredArtifactKeys) {
      const resolved = relativeArtifactPath(
        platformRoot,
        manifest.artifacts[key],
        `proton/prebuilt/${platform}/manifest.json artifacts.${key}`,
        failures,
      );
      if (
        resolved !== null &&
        regularFile(
          resolved,
          `proton/prebuilt/${platform}/${manifest.artifacts[key]}`,
          failures,
        )
      ) {
        resolvedArtifacts[key] = resolved;
      }
    }

    const prebuiltHeaderPath = resolvedArtifacts.header;
    if (prebuiltHeaderPath) {
      const prebuiltHeader = readTextFile(
        prebuiltHeaderPath,
        `proton/prebuilt/${platform}/${manifest.artifacts.header}`,
        failures,
      );
      if (prebuiltHeader !== null && prebuiltHeader !== sourceHeader) {
        failures.push(
          `proton/prebuilt/${platform}/${manifest.artifacts.header}: differs from native/include/proton_native.h`,
        );
      }
    }

    if (symbolPlatform === platform) {
      const libraryPath = resolvedArtifacts[layout.libraryKey];
      if (libraryPath) {
        failures.push(
          ...compareSymbolSets(
            `proton/prebuilt/${platform}/${manifest.artifacts[layout.libraryKey]}`,
            expectedSymbols,
            inspectExports(platform, libraryPath, failures),
          ),
        );
      }
      if (layout.importLibraryKey) {
        const importLibraryPath = resolvedArtifacts[layout.importLibraryKey];
        if (importLibraryPath) {
          const importSymbols = new Set(
            inspectImportLibrary(platform, importLibraryPath, failures),
          );
          for (const symbol of expectedSymbols) {
            if (!importSymbols.has(symbol)) {
              failures.push(
                `proton/prebuilt/${platform}/${manifest.artifacts[layout.importLibraryKey]}: missing public ABI import ${symbol}`,
              );
            }
          }
        }
      }
    }
  }

  return failures;
}

function usage() {
  console.error(
    "Usage: node scripts/verify_prebuilt_abi.mjs [--metadata-only | <platform>]",
  );
}

function main() {
  const args = process.argv.slice(2);
  if (args.length > 1) {
    usage();
    process.exitCode = 2;
    return;
  }
  const symbolPlatform =
    args.length === 0 || args[0] === "--metadata-only" ? null : args[0];
  const failures = verifyPrebuiltAbi({ symbolPlatform });
  if (failures.length > 0) {
    console.error("Proton prebuilt ABI validation failed:");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exitCode = 1;
    return;
  }
  if (symbolPlatform === null) {
    console.log(
      "[OK] Proton prebuilt manifests, artifacts, and public headers are consistent.",
    );
  } else {
    console.log(
      `[OK] Proton ${symbolPlatform} prebuilt exports the complete public ABI.`,
    );
  }
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main();
}
