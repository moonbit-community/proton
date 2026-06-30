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
    "fs",
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

  if (failures.length > 0) {
    console.error(`Generated files are stale: ${failures.join(", ")}`);
    process.exitCode = 1;
  } else {
    console.log("[OK] Generated files are up to date.");
  }
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
