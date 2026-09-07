#!/usr/bin/env node

// Exercise the real native cipher through the public MoonBit API without
// reading or writing the user's Keychain. Also verify standalone module linking.
import { mkdtempSync, cpSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

if (process.platform !== "darwin") {
  console.log("[SKIP] macOS safe storage regression test");
  process.exit(0);
}
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temporary = mkdtempSync(path.join(tmpdir(), "proton-safe-storage-"));
try {
  cpSync(path.join(root, "sys/safe_storage"), temporary, {
    recursive: true,
    filter: source => !["_build", ".mooncakes"].includes(path.basename(source)),
  });
  const source = path.join(temporary, "safe_storage_native.c");
  const keychainFixture = `
#include <Security/Security.h>
#include <stdlib.h>
#include <string.h>
static OSStatus test_find_key(CFTypeRef keychain, UInt32 service_len,
    const char *service, UInt32 account_len, const char *account,
    UInt32 *length, void **data, SecKeychainItemRef *item) {
  (void)keychain; (void)service_len; (void)service;
  (void)account_len; (void)account; (void)item;
  *length = 32;
  *data = malloc(32);
  if (*data == NULL) return errSecAllocate;
  memset(*data, 0x42, 32);
  return errSecSuccess;
}
static OSStatus test_free_key(SecKeychainAttributeList *attributes, void *data) {
  (void)attributes; free(data); return errSecSuccess;
}
static OSStatus test_add_key(SecKeychainRef keychain, UInt32 service_len,
    const char *service, UInt32 account_len, const char *account,
    UInt32 length, const void *data, SecKeychainItemRef *item) {
  (void)keychain; (void)service_len; (void)service;
  (void)account_len; (void)account; (void)length; (void)data; (void)item;
  abort();
}
#define SecKeychainFindGenericPassword test_find_key
#define SecKeychainItemFreeContent test_free_key
#define SecKeychainAddGenericPassword test_add_key
`;
  writeFileSync(source, keychainFixture + readFileSync(source, "utf8"));
  writeFileSync(path.join(temporary, "cipher_test.mbt"), `
///|
test "native safe storage roundtrips padding boundaries and UTF-8" {
  for input in ["", "a", "123456789012345", "1234567890123456",
    "12345678901234567", "12345678901234567890123456789012", "你好 🔐"] {
    let payload = match @proton_safe_storage.encrypt_string(input) {
      Ok(payload) => payload
      Err(message) => fail(message)
    }
    assert_eq(@proton_safe_storage.decrypt_string(payload), Ok(input))
  }
}
`);
  const result = spawnSync("moon", ["-C", temporary, "test", "--target", "native"], {
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exitCode = result.status ?? 1;
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
