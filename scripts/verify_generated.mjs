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

try {
  const codegenExtensions = [
    "auto_launch",
    "clipboard",
    "dialog",
    "global_hotkey",
    "keepawake",
    "microphone",
    "notification",
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
  }

  const embedScript = path.join(repoRoot, "scripts", "embed_asset.mjs");
  const embedAssets = [
    {
      input: "extensions/fs/assets/node_fs_helper.js",
      output: "extensions/fs/generated_fs_helper_template.mbt",
      identifier: "fs_helper_template_resource",
      tempName: "generated_fs_helper_template.mbt",
    },
    {
      input: "extensions/path/assets/node_path_helper.js",
      output: "extensions/path/generated_path_helper_template.mbt",
      identifier: "path_helper_template_resource",
      tempName: "generated_path_helper_template.mbt",
    },
  ];

  for (const asset of embedAssets) {
    const outputPath = tempOutputPath(asset.tempName);
    run("node", [
      embedScript,
      path.join(repoRoot, asset.input),
      outputPath,
      asset.identifier,
    ]);
    compareGeneratedFile(asset.output, outputPath);
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
