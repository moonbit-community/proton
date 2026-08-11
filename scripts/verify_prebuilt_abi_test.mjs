import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  compareSymbolSets,
  exportedAllSymbols,
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
    ["library: unexpected export proton_unexpected"],
  );
});

test("extracts every nm export, not only proton_* ones", () => {
  const output = `
0000000000001000 T _proton_abi_version
0000000000002000 T _cef_api_hash
0000000000003000 T proton_runtime_wait
`;
  assert.deepEqual(exportedAllSymbols(output, "nm"), [
    "cef_api_hash",
    "proton_abi_version",
    "proton_runtime_wait",
  ]);
});

test("extracts every dumpbin export", () => {
  const output = `
    ordinal hint RVA      name
          1    0 00001234 proton_abi_version
          2    1 00005678 cef_api_hash
          3    2 0000A1B0 cef_forwarded (forwarded to libcef.cef_forwarded)
`;
  assert.deepEqual(exportedAllSymbols(output, "dumpbin"), [
    "cef_api_hash",
    "cef_forwarded",
    "proton_abi_version",
  ]);
});

test("nm parser accepts absolute and weak symbol types", () => {
  const output = `
0000000000001000 T _proton_abi_version
0000000000002000 A _cef_absolute
0000000000003000 W _cef_weak
`;
  assert.deepEqual(exportedAllSymbols(output, "nm"), [
    "cef_absolute",
    "cef_weak",
    "proton_abi_version",
  ]);
});

test("extracts GNU and llvm objdump PE exports", () => {
  const gnu = `
[Ordinal/Name Pointer] Table
\t[   0] proton_abi_version
\t[   1] cef_api_hash
`;
  assert.deepEqual(exportedAllSymbols(gnu, "objdump"), [
    "cef_api_hash",
    "proton_abi_version",
  ]);
  const llvm = `
Export Table:
 DLL name: proton.dll
 Ordinal base: 1
 Ordinal      RVA  Name
       1   0x61c0  proton_abi_version
       2   0x61d0  cef_api_hash
`;
  assert.deepEqual(exportedAllSymbols(llvm, "objdump"), [
    "cef_api_hash",
    "proton_abi_version",
  ]);
});

test("objdump parser ignores export address table entries", () => {
  const gnuAddressTable = `
 Export Address Table -- Ordinal Base 1
\t[   0] + base[   1] 11000 Export RVA
\t[   1] + base[   2] 12000 Export RVA
`;
  assert.deepEqual(exportedAllSymbols(gnuAddressTable, "objdump"), []);
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
        source_hash: "not-a-source-hash",
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
        "proton/prebuilt/linux-x64/manifest.json: invalid source_hash",
      ),
    );
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
