#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const cli = process.env.PROTON_REGISTRY_CLI ?? "proton_cli";
const tempRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "proton-scaffold-registry-"),
);
const projectDir = path.join(tempRoot, "todo");
let succeeded = false;

function moduleVersion(relativePath) {
  const source = fs.readFileSync(path.join(repoRoot, relativePath), "utf8");
  const match = source.match(/^version\s*=\s*"([^"]+)"/m);
  if (!match) {
    throw new Error(`${relativePath} is missing its module version`);
  }
  return match[1];
}

function run(command, args, options = {}) {
  console.log(`+ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? tempRoot,
    env: { ...process.env, PROTON_NO_UPDATE_CHECK: "1" },
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
    timeout: options.timeout ?? 300000,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}`);
  }
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function verifyInstalledCliVersion() {
  const expected = moduleVersion("cli/moon.mod");
  const output = run(cli, ["--version"], { capture: true }).trim();
  const match = output.match(/^proton_cli\s+(\S+)$/);
  if (!match) {
    throw new Error(`could not parse installed CLI version: ${output}`);
  }
  if (match[1] !== expected) {
    throw new Error(
      `registry smoke requires proton_cli ${expected}, installed ${match[1]}`,
    );
  }
}

function expectDependency(relativePath, moduleName, version) {
  const source = fs.readFileSync(path.join(projectDir, relativePath), "utf8");
  const declaration = `"${moduleName}@${version}"`;
  if (!source.includes(declaration)) {
    throw new Error(`${relativePath} is missing ${declaration}`);
  }
}

function verifyGeneratedDependencies() {
  expectDependency(
    "shared/moon.mod",
    "moonbit-community/proton_contract",
    moduleVersion("contract/moon.mod"),
  );
  expectDependency(
    "frontend/moon.mod",
    "moonbit-community/proton_client",
    moduleVersion("client/moon.mod"),
  );
  expectDependency(
    "frontend/moon.mod",
    "moonbit-community/proton_rabbita",
    moduleVersion("rabbita/moon.mod"),
  );
  expectDependency(
    "backend/moon.mod",
    "moonbit-community/proton",
    moduleVersion("proton/moon.mod"),
  );
  expectDependency(
    "backend/moon.mod",
    "moonbit-community/proton_contract",
    moduleVersion("contract/moon.mod"),
  );
  const backend = fs.readFileSync(
    path.join(projectDir, "backend/moon.mod"),
    "utf8",
  );
  if (backend.includes("bin-deps")) {
    throw new Error("backend/moon.mod must not depend on a CLI binary shim");
  }
  const codegen = `moonx moonbit-community/proton_codegen@${moduleVersion("codegen/moon.mod")}`;
  if (!backend.includes(codegen)) {
    throw new Error(`backend/moon.mod is missing ${codegen}`);
  }
}

function useLocalCodegenPackage() {
  const backendModPath = path.join(projectDir, "backend", "moon.mod");
  const source = fs.readFileSync(backendModPath, "utf8");
  const coordinate = `moonx moonbit-community/proton_codegen@${moduleVersion("codegen/moon.mod")}`;
  const localCommand = `moon run '${path.join(repoRoot, "codegen")}' --target wasm --`;
  const updated = source.replace(coordinate, localCommand);
  if (updated === source || updated.includes(coordinate)) {
    throw new Error("could not select the local codegen package");
  }
  fs.writeFileSync(backendModPath, updated);
}

try {
  verifyInstalledCliVersion();
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
    "--no-check",
    "--no-git",
    "-y",
  ]);
  verifyGeneratedDependencies();
  useLocalCodegenPackage();
  run("moon", ["check", "--target", "js,native", "--diagnostic-limit", "80"], {
    cwd: projectDir,
  });
  if (!fs.existsSync(path.join(projectDir, "backend/todo/commands.g.mbt"))) {
    throw new Error("Moon prebuild did not generate backend/todo/commands.g.mbt");
  }
  succeeded = true;
  console.log("Registry scaffold smoke passed.");
} finally {
  if (succeeded) {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  } else {
    console.error(`Registry scaffold artifacts retained at ${tempRoot}`);
  }
}
