#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const cli = process.env.PROTON_REGISTRY_CLI ?? "proton_cli";
const tempRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "proton-scaffold-registry-"),
);
const projectDir = path.join(tempRoot, "todo");
let succeeded = false;

function run(command, args, options = {}) {
  console.log(`+ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? tempRoot,
    env: process.env,
    encoding: "utf8",
    stdio: "inherit",
    timeout: options.timeout ?? 300000,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
}

try {
  run(cli, [
    "-C",
    tempRoot,
    "new",
    "todo",
    "--title",
    "Registry Todo",
    "--author",
    "registry_smoke",
    "--identifier",
    "dev.proton.registry-smoke",
    "--no-git",
    "-y",
  ]);
  run("moon", ["check", "--diagnostic-limit", "80"], {
    cwd: projectDir,
  });
  succeeded = true;
  console.log("Registry scaffold smoke passed.");
} finally {
  if (succeeded) {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } else {
    console.error(`Registry scaffold artifacts retained at ${tempRoot}`);
  }
}
