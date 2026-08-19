#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "proton-generated-check-"));
const failures = [];
const abiFailures = [];
const skipPrebuiltAbi = process.argv.includes("--skip-prebuilt-abi");
const codegenWasm = path.join(
  repoRoot,
  "_build/wasm/debug/build/moonbit-community/proton_codegen/proton_codegen.wasm",
);

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${command} ${args.join(" ")}`);
  }
}

function runAllowFailure(command, args) {
  return (
    spawnSync(command, args, { cwd: repoRoot, stdio: "inherit" }).status === 0
  );
}

function runCodegen(args) {
  run("moonrun", [codegenWasm, ...args]);
}

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

/// Generated sources are text; a CRLF checkout on Windows must not turn an
/// otherwise identical file into a stale one, so compare with EOLs folded.
function normalizedTextSha256(filePath) {
  const text = fs.readFileSync(filePath, "utf8").replace(/\r\n/g, "\n");
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

function compareGeneratedFile(expectedRelativePath, actualPath) {
  const expectedPath = path.join(repoRoot, expectedRelativePath);
  if (!fs.existsSync(expectedPath)) {
    failures.push(`missing expected file: ${expectedRelativePath}`);
    return;
  }
  if (!fs.existsSync(actualPath)) {
    failures.push(`generator did not create: ${expectedRelativePath}`);
    return;
  }
  if (normalizedTextSha256(expectedPath) !== normalizedTextSha256(actualPath)) {
    failures.push(expectedRelativePath);
  }
}

function tempOutputPath(fileName) {
  return path.join(tempRoot, fileName);
}

/// Every platform staged under proton/prebuilt/ ships from this repository, so
/// all of them are validated regardless of the host. Checking only the host
/// platform lets a rebuild that covers one platform pass while the others still
/// carry binaries that predate the current public header.
export function stagedPrebuiltPlatforms() {
  const prebuiltRoot = path.join(repoRoot, "proton", "prebuilt");
  if (!fs.existsSync(prebuiltRoot)) {
    return [];
  }
  return fs
    .readdirSync(prebuiltRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
}

try {
  run("node", [path.join(repoRoot, "scripts", "verify_release_metadata.mjs")]);
  const platforms = stagedPrebuiltPlatforms();
  if (skipPrebuiltAbi || platforms.length === 0) {
    run("node", [
      path.join(repoRoot, "scripts", "verify_prebuilt_abi.mjs"),
      "--metadata-only",
    ]);
  }
  /// Each platform is reported before the run ends, so a single stale prebuilt
  /// does not hide the state of the others or of the codegen comparison below.
  /// Platforms whose artifact format the host inspection tool cannot read
  /// (for example GNU nm on a Mach-O dylib) are skipped rather than reported
  /// as failures; every platform is still verified on its own host's CI leg.
  for (const platform of skipPrebuiltAbi ? [] : platforms) {
    const probe = spawnSync(
      "node",
      [
        path.join(repoRoot, "scripts", "verify_prebuilt_abi.mjs"),
        "--tool-probe",
        platform,
      ],
      { encoding: "utf8" },
    );
    if (probe.status !== 0) {
      const detail = (probe.stdout || probe.stderr || "")
        .trim()
        .replace(/^\[SKIP\]\s*/, "");
      console.log(`[SKIP] ${platform}: ${detail}`);
      continue;
    }
    if (
      !runAllowFailure("node", [
        path.join(repoRoot, "scripts", "verify_prebuilt_abi.mjs"),
        platform,
      ])
    ) {
      abiFailures.push(platform);
    }
  }

  const codegenExtensions = [
    "auto_launch",
    "clipboard",
    "dialog",
    "fs",
    "global_hotkey",
    "keepawake",
    "microphone",
    "notification",
    "path",
    "power_monitor",
    "shell",
    "tray",
    "updater",
  ];

  run("moon", ["build", "codegen", "--target", "wasm"]);

  for (const extension of codegenExtensions) {
    const inputPath = path.join(repoRoot, "extensions", extension, "extension.mbt");
    const outputPath = tempOutputPath(`${extension}.extension.g.mbt`);
    runCodegen([
      inputPath,
      "-o",
      outputPath,
    ]);
    compareGeneratedFile(path.join("extensions", extension, "extension.g.mbt"), outputPath);

    const identityOutputPath = tempOutputPath(
      `${extension}.extension_identity.g.mbt`,
    );
    runCodegen([
      "--extension-identity",
      path.join(repoRoot, "extensions", extension, "proton.ext.json"),
      "--identity-name",
      "extension",
      "-o",
      identityOutputPath,
    ]);
    compareGeneratedFile(
      path.join(
        "extensions",
        extension,
        "contract",
        "extension_identity.g.mbt",
      ),
      identityOutputPath,
    );
  }

  const codegenExamples = [
    "38_async_extension_add",
    "42_attribute_codegen_commands",
    "46_asset_sidecar_resources",
    "e2e_fixtures",
  ];

  for (const example of codegenExamples) {
    const exampleDir = path.join(repoRoot, "examples", example);
    const registrarOutputPath = tempOutputPath(`${example}.commands.g.mbt`);
    runCodegen([
      path.join(exampleDir, "commands.mbt"),
      "-o",
      registrarOutputPath,
    ]);
    compareGeneratedFile(
      path.join("examples", example, "commands.g.mbt"),
      registrarOutputPath,
    );

    if (example !== "e2e_fixtures") {
      const identityOutputPath = tempOutputPath(
        `${example}.extension_identity.g.mbt`,
      );
      runCodegen([
        "--extension-identity",
        path.join(exampleDir, "proton.ext.json"),
        "-o",
        identityOutputPath,
      ]);
      compareGeneratedFile(
        path.join("examples", example, "extension_identity.g.mbt"),
        identityOutputPath,
      );
    }
  }

  const newTemplatesOutput = tempOutputPath("templates.generated.mbt");
  run("node", [
    path.join(repoRoot, "scripts", "generate_new_templates.mjs"),
    newTemplatesOutput,
  ]);
  compareGeneratedFile("cli/new/templates.generated.mbt", newTemplatesOutput);

  const bridgeBootstrapOutput = tempOutputPath("bridge_bootstrap.generated.h");
  run("node", [
    path.join(repoRoot, "scripts", "generate_bridge_bootstrap.mjs"),
    bridgeBootstrapOutput,
  ]);
  compareGeneratedFile(
    "native/src/engine/cef_common/bridge_bootstrap.generated.h",
    bridgeBootstrapOutput,
  );

  if (abiFailures.length > 0) {
    console.error(
      `Prebuilt runtimes do not export the current public ABI: ${abiFailures.join(", ")}`,
    );
    process.exitCode = 1;
  }
  if (failures.length > 0) {
    console.error(`Generated files are stale: ${failures.join(", ")}`);
    process.exitCode = 1;
  } else {
    console.log("[OK] Generated files are up to date.");
  }
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
