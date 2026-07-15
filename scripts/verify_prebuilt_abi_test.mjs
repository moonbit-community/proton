import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  compareSymbolSets,
  exportedProtonSymbols,
  publicAbiSymbols,
  verifyPrebuiltAbi,
} from "./verify_prebuilt_abi.mjs";

test("extracts multiline public ABI declarations from the header", () => {
  const header = `
#define PROTON_API __attribute__((visibility("default")))
// PROTON_API must not make the next private declaration public.
int32_t proton_private(void);
PROTON_API int32_t proton_abi_version(void);
PROTON_API int32_t
proton_runtime_info_json(char *buffer,
                                            int32_t buffer_len,
                                            int32_t *out_required_len);
int32_t proton_engine_internal(void);
`;
  assert.deepEqual(publicAbiSymbols(header), [
    "proton_abi_version",
    "proton_runtime_info_json",
  ]);
});

test("normalizes nm and dumpbin export names", () => {
  const output = `
0000000000001000 T _proton_abi_version
0000000000002000 T proton_runtime_info_json
0000000000003000 T __imp_proton_runtime_wait
       3   0x1234  proton_window_show
unrelated_symbol
`;
  assert.deepEqual(exportedProtonSymbols(output), [
    "proton_abi_version",
    "proton_runtime_info_json",
    "proton_runtime_wait",
    "proton_window_show",
  ]);
});

test("requires the exact public export set", () => {
  assert.deepEqual(
    compareSymbolSets(
      "library",
      ["proton_public"],
      ["proton_public", "proton_unexpected"],
    ),
    ["library: unexpected Proton export proton_unexpected"],
  );
});

test("metadata validation requires every shipped platform", () => {
  const repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), "proton-abi-test-"));
  try {
    fs.mkdirSync(path.join(repoRoot, "native", "include"), { recursive: true });
    fs.mkdirSync(path.join(repoRoot, "proton", "prebuilt", "linux-x64"), {
      recursive: true,
    });
    fs.mkdirSync(
      path.join(repoRoot, "proton", "prebuilt", "linux-x64", "lib", "libproton.so"),
      { recursive: true },
    );
    fs.writeFileSync(
      path.join(repoRoot, "native", "include", "proton_native.h"),
      "PROTON_API int32_t proton_abi_version(void);\n",
    );
    fs.writeFileSync(
      path.join(repoRoot, "proton", "moon.mod"),
      'version = "0.1.0"\n',
    );
    fs.writeFileSync(
      path.join(repoRoot, "proton", "prebuilt", "linux-x64", "manifest.json"),
      JSON.stringify({
        platform: "linux-x64",
        proton_version: "0.1.0",
        artifacts: {
          shared_lib: "lib/libproton.so",
          helper: "bin/cef_process",
          header: "include/proton_native.h",
        },
      }),
    );
    const failures = verifyPrebuiltAbi({ repoRoot });
    assert(failures.includes("proton/prebuilt/darwin-arm64: missing"));
    assert(failures.includes("proton/prebuilt/win32-x64: missing"));
    assert(
      failures.includes(
        "proton/prebuilt/linux-x64/lib/libproton.so: not a regular file",
      ),
    );
  } finally {
    fs.rmSync(repoRoot, { recursive: true, force: true });
  }
});

test("rejects non-object manifests", () => {
  const repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), "proton-abi-test-"));
  try {
    fs.mkdirSync(path.join(repoRoot, "native", "include"), { recursive: true });
    fs.mkdirSync(path.join(repoRoot, "proton", "prebuilt", "linux-x64"), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(repoRoot, "native", "include", "proton_native.h"),
      "PROTON_API int32_t proton_abi_version(void);\n",
    );
    fs.writeFileSync(
      path.join(repoRoot, "proton", "moon.mod"),
      'version = "0.1.0"\n',
    );
    const manifestPath = path.join(
      repoRoot,
      "proton",
      "prebuilt",
      "linux-x64",
      "manifest.json",
    );
    fs.writeFileSync(manifestPath, "null\n");
    const failures = verifyPrebuiltAbi({ repoRoot });
    assert(failures.includes(`${manifestPath}: manifest must be a JSON object`));
  } finally {
    fs.rmSync(repoRoot, { recursive: true, force: true });
  }
});
