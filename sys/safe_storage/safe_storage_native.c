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

#if defined(_MSC_VER)
#define MB_THREAD_LOCAL __declspec(thread)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define MB_THREAD_LOCAL _Thread_local
#else
#define MB_THREAD_LOCAL
#endif

static MB_THREAD_LOCAL char mb_safe_storage_error[512];
static MB_THREAD_LOCAL int mb_safe_storage_operation_status;
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
static int keychain_key(unsigned char key[32]) {
  const void *attributes[] = { kSecClass, kSecAttrService, kSecAttrAccount,
                               kSecReturnData, kSecMatchLimit };
  const void *values[] = { kSecClassGenericPassword,
      CFSTR("moonbit-community.proton.safe-storage"), CFSTR("default"),
      kCFBooleanTrue, kSecMatchLimitOne };
  CFMutableDictionaryRef query = CFDictionaryCreateMutable(
      NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  for (size_t i = 0; i < sizeof(attributes) / sizeof(attributes[0]); i++) {
    CFDictionarySetValue(query, attributes[i], values[i]);
  }
  // Keep the existing service/account and the default macOS Keychain backend
  // so previously encrypted data continues to use the same key.
  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching(query, &result);
  if (status == errSecSuccess) {
    int valid = result != NULL && CFGetTypeID(result) == CFDataGetTypeID() &&
                CFDataGetLength((CFDataRef)result) == 32;
    if (valid) memcpy(key, CFDataGetBytePtr((CFDataRef)result), 32);
    if (result != NULL) CFRelease(result);
    CFRelease(query);
    if (!valid) mb_set_error("invalid safe storage key in Keychain");
    return valid;
  }
  if (result != NULL) CFRelease(result);
  if (status != errSecItemNotFound) {
    CFRelease(query);
    mb_set_error("failed to read safe storage key from Keychain");
    return 0;
  }
  if (SecRandomCopyBytes(kSecRandomDefault, 32, key) != errSecSuccess) {
    CFRelease(query);
    mb_set_error("failed to generate safe storage key");
    return 0;
  }
  CFDictionaryRemoveValue(query, kSecReturnData);
  CFDictionaryRemoveValue(query, kSecMatchLimit);
  CFDataRef data = CFDataCreate(NULL, key, 32);
  CFDictionarySetValue(query, kSecValueData, data);
  status = SecItemAdd(query, NULL);
  CFRelease(data);
  CFRelease(query);
  if (status != errSecSuccess) {
    mb_set_error("failed to store safe storage key in Keychain");
    return 0;
  }
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
  unsigned char key[32], iv[16];
  // Reserve the IV separately from the ciphertext and its full padding block.
  size_t moved = 0, out_len = sizeof(iv) + length + kCCBlockSizeAES128;
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
