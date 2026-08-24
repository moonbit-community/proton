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
let codegenWasm;

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${command} ${args.join(" ")}`);
  }
}

function buildArtifact(args) {
  const result = spawnSync("moon", args, {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr ?? "");
    throw new Error(`Command failed: moon ${args.join(" ")}`);
  }
  const artifacts = JSON.parse(result.stdout).artifacts_path;
  if (!Array.isArray(artifacts) || artifacts.length !== 1) {
    throw new Error(`Expected one Moon artifact, received: ${result.stdout}`);
  }
  return artifacts[0];
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

try {
  run("node", [path.join(repoRoot, "scripts", "verify_release_metadata.mjs")]);
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
    "screen_monitor",
    "shell",
    "tray",
    "updater",
  ];

  codegenWasm = buildArtifact([
    "run",
    "codegen",
    "--target",
    "wasm",
    "--build-only",
  ]);

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
    "proton/internal/native/ffi/src/engine/cef_common/bridge_bootstrap.generated.h",
    bridgeBootstrapOutput,
  );

  const runtimeRequirementsMoon = tempOutputPath("requirements.generated.mbt");
  const runtimeRequirementsJs = tempOutputPath("cef_requirements.generated.mjs");
  run("node", [
    path.join(repoRoot, "scripts", "generate_runtime_requirements.mjs"),
    runtimeRequirementsMoon,
    runtimeRequirementsJs,
  ]);
  compareGeneratedFile(
    "cefsetup/store/requirements.generated.mbt",
    runtimeRequirementsMoon,
  );
  compareGeneratedFile(
    "proton/cef_requirements.generated.mjs",
    runtimeRequirementsJs,
  );

  if (failures.length > 0) {
    console.error(`Generated files are stale: ${failures.join(", ")}`);
    process.exitCode = 1;
  } else {
    console.log("[OK] Generated files are up to date.");
  }
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
