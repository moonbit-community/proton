#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "moonbit.h"

#if defined(_WIN32)
#include <windows.h>
#include <wincrypt.h>
#pragma comment(lib, "crypt32.lib")
#elif defined(__APPLE__)
#include <Security/Security.h>
#include <CommonCrypto/CommonCryptor.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CommonCrypto/CommonRandom.h>
#endif

static _Thread_local char mb_safe_storage_error[512];
static _Thread_local int mb_safe_storage_operation_status;
static void mb_set_error(const char *message) {
  mb_safe_storage_operation_status = 0;
  snprintf(mb_safe_storage_error, sizeof(mb_safe_storage_error), "%s", message);
}
static void mb_set_success(void) {
  mb_safe_storage_operation_status = 1;
  mb_safe_storage_error[0] = '\0';
}
static moonbit_bytes_t mb_bytes(const unsigned char *data, size_t len) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) memcpy(out, data, len);
  return out;
}

#if defined(__APPLE__)
static const char *k_service = "moonbit-community.proton.safe-storage";
static const char *k_account = "default";
static int keychain_key(unsigned char key[32]) {
  UInt32 length = 0; void *data = NULL;
  OSStatus status = SecKeychainFindGenericPassword(NULL, (UInt32)strlen(k_service), k_service,
      (UInt32)strlen(k_account), k_account, &length, &data, NULL);
  if (status == errSecSuccess && length == 32) { memcpy(key, data, 32); SecKeychainItemFreeContent(NULL, data); return 1; }
  if (data != NULL) SecKeychainItemFreeContent(NULL, data);
  if (SecRandomCopyBytes(kSecRandomDefault, 32, key) != errSecSuccess) { mb_set_error("failed to generate safe storage key"); return 0; }
  status = SecKeychainAddGenericPassword(NULL, (UInt32)strlen(k_service), k_service,
      (UInt32)strlen(k_account), k_account, 32, key, NULL);
  if (status != errSecSuccess) { mb_set_error("failed to store safe storage key in Keychain"); return 0; }
  return 1;
}
#endif

int32_t mb_safe_storage_is_available(void) {
#if defined(_WIN32) || defined(__APPLE__)
  return 1;
#else
  mb_set_error("safe storage is not implemented on this platform"); return 0;
#endif
}

moonbit_bytes_t mb_safe_storage_encrypt(moonbit_bytes_t value) {
  size_t length = (size_t)Moonbit_array_length(value);
#if defined(_WIN32)
  DATA_BLOB input = { (DWORD)length, (BYTE *)value }, output = { 0 };
  if (!CryptProtectData(&input, L"Proton safe storage", NULL, NULL, NULL, 0, &output)) { mb_set_error("CryptProtectData failed"); return mb_bytes(NULL, 0); }
  moonbit_bytes_t result = mb_bytes(output.pbData, output.cbData); LocalFree(output.pbData); mb_set_success(); return result;
#elif defined(__APPLE__)
  unsigned char key[32], iv[16]; size_t moved = 0, out_len = length + 16;
  if (!keychain_key(key) || SecRandomCopyBytes(kSecRandomDefault, 16, iv) != errSecSuccess) { mb_set_error("failed to initialize safe storage cipher"); return mb_bytes(NULL, 0); }
  unsigned char *out = malloc(out_len); if (out == NULL) { mb_set_error("safe storage allocation failed"); return mb_bytes(NULL, 0); }
  CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 32, iv, value, length, out + 16, out_len - 16, &moved);
  if (status != kCCSuccess) { free(out); mb_set_error("CommonCrypto encryption failed"); return mb_bytes(NULL, 0); }
  memcpy(out, iv, 16); moonbit_bytes_t result = mb_bytes(out, moved + 16); free(out); mb_set_success(); return result;
#else
  (void)value; mb_set_error("safe storage is not implemented on this platform"); return mb_bytes(NULL, 0);
#endif
}

moonbit_bytes_t mb_safe_storage_decrypt(moonbit_bytes_t value) {
  size_t length = (size_t)Moonbit_array_length(value);
#if defined(_WIN32)
  DATA_BLOB input = { (DWORD)length, (BYTE *)value }, output = { 0 };
  if (!CryptUnprotectData(&input, NULL, NULL, NULL, NULL, 0, &output)) { mb_set_error("CryptUnprotectData failed"); return mb_bytes(NULL, 0); }
  moonbit_bytes_t result = mb_bytes(output.pbData, output.cbData); LocalFree(output.pbData); mb_set_success(); return result;
#elif defined(__APPLE__)
  if (length <= 16) { mb_set_error("safe storage payload is truncated"); return mb_bytes(NULL, 0); }
  unsigned char key[32]; size_t moved = 0, out_len = length;
  if (!keychain_key(key)) return mb_bytes(NULL, 0);
  unsigned char *out = malloc(out_len); if (out == NULL) { mb_set_error("safe storage allocation failed"); return mb_bytes(NULL, 0); }
  CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 32, value, value + 16, length - 16, out, out_len, &moved);
  if (status != kCCSuccess) { free(out); mb_set_error("CommonCrypto decryption failed"); return mb_bytes(NULL, 0); }
  moonbit_bytes_t result = mb_bytes(out, moved); free(out); mb_set_success(); return result;
#else
  (void)value; mb_set_error("safe storage is not implemented on this platform"); return mb_bytes(NULL, 0);
#endif
}

moonbit_bytes_t mb_safe_storage_last_error(void) {
  return mb_bytes((const unsigned char *)mb_safe_storage_error, strlen(mb_safe_storage_error));
}

int32_t mb_safe_storage_operation_ok(void) {
  return mb_safe_storage_operation_status;
}
