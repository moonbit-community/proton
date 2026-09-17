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
#include <assert.h>
static unsigned char test_key[32];
static int test_key_exists;
static void check_key_query(CFDictionaryRef query) {
  assert(CFEqual(CFDictionaryGetValue(query, kSecClass), kSecClassGenericPassword));
  assert(CFEqual(CFDictionaryGetValue(query, kSecAttrService),
                 CFSTR("moonbit-community.proton.safe-storage")));
  assert(CFEqual(CFDictionaryGetValue(query, kSecAttrAccount), CFSTR("default")));
  assert(!CFDictionaryContainsKey(query, kSecUseDataProtectionKeychain));
}
static OSStatus test_find_key(CFDictionaryRef query, CFTypeRef *result) {
  check_key_query(query);
  assert(CFDictionaryGetValue(query, kSecReturnData) == kCFBooleanTrue);
  assert(CFEqual(CFDictionaryGetValue(query, kSecMatchLimit), kSecMatchLimitOne));
  *result = NULL;
  if (!test_key_exists) return errSecItemNotFound;
  *result = CFDataCreate(NULL, test_key, 32);
  return errSecSuccess;
}
static OSStatus test_add_key(CFDictionaryRef query, CFTypeRef *result) {
  check_key_query(query);
  assert(result == NULL && !test_key_exists);
  assert(!CFDictionaryContainsKey(query, kSecReturnData));
  assert(!CFDictionaryContainsKey(query, kSecMatchLimit));
  CFDataRef data = CFDictionaryGetValue(query, kSecValueData);
  assert(CFDataGetLength(data) == 32);
  memcpy(test_key, CFDataGetBytePtr(data), 32);
  test_key_exists = 1;
  return errSecSuccess;
}
#define SecItemCopyMatching test_find_key
#define SecItemAdd test_add_key
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
