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

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${command} ${args.join(" ")}`);
  }
}

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
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
  if (sha256(expectedPath) !== sha256(actualPath)) {
    failures.push(expectedRelativePath);
  }
}

function tempOutputPath(fileName) {
  return path.join(tempRoot, fileName);
}

export function hostPrebuiltPlatform({
  platform = process.platform,
  arch = process.arch,
} = {}) {
  // Only platforms with committed prebuilts can run the symbol-level check;
  // anything else falls back to "--metadata-only" at the call site.
  if (platform === "win32") {
    return arch === "x64" ? "win32-x64" : null;
  }
  if (platform === "darwin") {
    return arch === "arm64" ? "darwin-arm64" : null;
  }
  if (platform === "linux") {
    return arch === "x64" ? "linux-x64" : null;
  }
  return null;
}

try {
  run("node", [path.join(repoRoot, "scripts", "verify_release_metadata.mjs")]);
  const platform = hostPrebuiltPlatform();
  run("node", [
    path.join(repoRoot, "scripts", "verify_prebuilt_abi.mjs"),
    platform ?? "--metadata-only",
  ]);

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
    "shell",
    "tray",
  ];

  for (const extension of codegenExtensions) {
    const inputPath = path.join(repoRoot, "extensions", extension, "extension.mbt");
    const outputPath = tempOutputPath(`${extension}.extension.g.mbt`);
    run("moon", [
      "-C",
      path.join(repoRoot, "cli"),
      "run",
      "--target",
      "native",
      ".",
      "--",
      "codegen",
      inputPath,
      "-o",
      outputPath,
    ]);
    compareGeneratedFile(path.join("extensions", extension, "extension.g.mbt"), outputPath);

    const identityOutputPath = tempOutputPath(
      `${extension}.extension_identity.g.mbt`,
    );
    run("moon", [
      "-C",
      path.join(repoRoot, "cli"),
      "run",
      "--target",
      "native",
      ".",
      "--",
      "codegen",
      "--extension-identity",
      path.join(repoRoot, "extensions", extension, "moon.ext"),
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
  ];

  for (const example of codegenExamples) {
    const exampleDir = path.join(repoRoot, "examples", example);
    const registrarOutputPath = tempOutputPath(`${example}.commands.g.mbt`);
    run("moon", [
      "-C",
      path.join(repoRoot, "cli"),
      "run",
      "--target",
      "native",
      ".",
      "--",
      "codegen",
      path.join(exampleDir, "commands.mbt"),
      "-o",
      registrarOutputPath,
    ]);
    compareGeneratedFile(
      path.join("examples", example, "commands.g.mbt"),
      registrarOutputPath,
    );

    const identityOutputPath = tempOutputPath(
      `${example}.extension_identity.g.mbt`,
    );
    run("moon", [
      "-C",
      path.join(repoRoot, "cli"),
      "run",
      "--target",
      "native",
      ".",
      "--",
      "codegen",
      "--extension-identity",
      path.join(exampleDir, "moon.ext"),
      "-o",
      identityOutputPath,
    ]);
    compareGeneratedFile(
      path.join("examples", example, "extension_identity.g.mbt"),
      identityOutputPath,
    );
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

  if (failures.length > 0) {
    console.error(`Generated files are stale: ${failures.join(", ")}`);
    process.exitCode = 1;
  } else {
    console.log("[OK] Generated files are up to date.");
  }
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
