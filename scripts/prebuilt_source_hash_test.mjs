import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  PrebuiltSourceHasher,
  platformSourceInputs,
  recordPrebuiltSourceHash,
  verifyPrebuiltSourceHashes,
} from "./prebuilt_source_hash.mjs";

class PrebuiltHashFixture {
  constructor() {
    this.root = fs.mkdtempSync(path.join(os.tmpdir(), "proton-source-hash-test-"));
    this.sourceInputs = { "test-platform": ["native/input"] };
    fs.mkdirSync(path.join(this.root, "native", "input"), { recursive: true });
    fs.mkdirSync(
      path.join(this.root, "proton", "prebuilt", "test-platform"),
      { recursive: true },
    );
    fs.writeFileSync(path.join(this.root, "native", "input", "b.c"), "b\n");
    fs.writeFileSync(path.join(this.root, "native", "input", "a.c"), "a\n");
    fs.writeFileSync(
      path.join(
        this.root,
        "proton",
        "prebuilt",
        "test-platform",
        "manifest.json",
      ),
      `${JSON.stringify({
        platform: "test-platform",
        proton_version: "0.1.0",
        artifacts: { shared_lib: "lib/test" },
      }, null, 2)}\n`,
    );
  }

  record() {
    return recordPrebuiltSourceHash({
      repoRoot: this.root,
      platform: "test-platform",
      sourceInputs: this.sourceInputs,
    });
  }

  verify() {
    return verifyPrebuiltSourceHashes({
      repoRoot: this.root,
      sourceInputs: this.sourceInputs,
    });
  }

  dispose() {
    fs.rmSync(this.root, { recursive: true, force: true });
  }
}

test("hashes directory contents in stable path order", () => {
  const fixture = new PrebuiltHashFixture();
  try {
    const hasher = new PrebuiltSourceHasher(fixture.root);
    assert.equal(
      hasher.hash(["native/input/a.c", "native/input/b.c"]),
      hasher.hash(["native/input"]),
    );
  } finally {
    fixture.dispose();
  }
});

test("excludes CI orchestration from prebuilt source inputs", () => {
  for (const inputs of Object.values(platformSourceInputs)) {
    assert.equal(
      inputs.some(input => input.startsWith(".github/workflows/")),
      false,
    );
  }
});

test("recorded source hash becomes stale after an input changes", () => {
  const fixture = new PrebuiltHashFixture();
  try {
    const recorded = fixture.record();
    assert.match(recorded, /^sha256:[0-9a-f]{64}$/);
    assert.deepEqual(fixture.verify(), []);
    fs.writeFileSync(path.join(fixture.root, "native", "input", "a.c"), "changed\n");
    assert.deepEqual(fixture.verify(), [
      "proton/prebuilt/test-platform/manifest.json: stale source_hash; rebuild the test-platform prebuilt",
    ]);
  } finally {
    fixture.dispose();
  }
});

test("reports missing declared source inputs", () => {
  const fixture = new PrebuiltHashFixture();
  try {
    fs.rmSync(path.join(fixture.root, "native", "input"), {
      recursive: true,
      force: true,
    });
    assert.match(fixture.verify()[0], /missing source input native\/input/);
  } finally {
    fixture.dispose();
  }
});
