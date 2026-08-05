#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "moonbit.h"

static moonbit_bytes_t moonbit_tray_copy_message(const char *message) {
  int32_t len;
  moonbit_bytes_t bytes;
  if (message == NULL) {
    message = "";
  }
  len = (int32_t)strlen(message);
  bytes = moonbit_make_bytes(len, 0);
  if (len > 0) {
    memcpy(bytes, message, (size_t)len);
  }
  return bytes;
}

static const unsigned char moonbit_tray_test_bmp[] = {
    0x42, 0x4d, 0x3a, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x36, 0x00, 0x00, 0x00, 0x28, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x13, 0x0b,
    0x00, 0x00, 0x13, 0x0b, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x66,
    0xcc, 0xff};

/* Paths crossing this boundary are UTF-8; on Windows the ANSI CRT calls
   would mangle non-ASCII temp directories, so go through the wide CRT. */
static FILE *moonbit_tray_test_fopen_write(const char *path) {
#ifdef _WIN32
  wchar_t wide_path[1024];
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path,
                          (int)(sizeof(wide_path) /
                                sizeof(wide_path[0]))) <= 0) {
    return NULL;
  }
  return _wfopen(wide_path, L"wb");
#else
  return fopen(path, "wb");
#endif
}

static int moonbit_tray_test_remove(const char *path) {
#ifdef _WIN32
  wchar_t wide_path[1024];
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path,
                          (int)(sizeof(wide_path) /
                                sizeof(wide_path[0]))) <= 0) {
    return 0;
  }
  return _wremove(wide_path) == 0;
#else
  return remove(path) == 0;
#endif
}

static int32_t moonbit_tray_test_icon_path_buffer(
    char *path,
    size_t path_size) {
#ifdef _WIN32
  wchar_t wide_temp[1024];
  DWORD wide_len;
  int len;
  int written;
  size_t temp_len;
  if (path_size == 0) {
    return 0;
  }
  wide_len = GetTempPathW(
      (DWORD)(sizeof(wide_temp) / sizeof(wide_temp[0])), wide_temp);
  if (wide_len == 0 ||
      wide_len >= sizeof(wide_temp) / sizeof(wide_temp[0])) {
    return 0;
  }
  len = WideCharToMultiByte(CP_UTF8, 0, wide_temp, -1, path, (int)path_size,
                            NULL, NULL);
  if (len <= 1) {
    return 0;
  }
  temp_len = (size_t)(len - 1);
  written = snprintf(
      path + temp_len,
      path_size - temp_len,
      "moonbit-tray-test-icon-%lu.bmp",
      (unsigned long)GetCurrentProcessId());
  return written > 0 && (size_t)written < path_size - temp_len;
#else
  const char *tmp = getenv("TMPDIR");
  if (tmp == NULL || tmp[0] == '\0') {
    tmp = "/tmp";
  }
  {
    int written = snprintf(
        path,
        path_size,
        "%s/moonbit-tray-test-icon-%lu.bmp",
        tmp,
        (unsigned long)getpid());
    return written > 0 && (size_t)written < path_size;
  }
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_tray_test_icon_path(void) {
  char path[1024];
  FILE *file;
  if (!moonbit_tray_test_icon_path_buffer(path, sizeof(path))) {
    return moonbit_tray_copy_message("");
  }
  file = moonbit_tray_test_fopen_write(path);
  if (file == NULL) {
    return moonbit_tray_copy_message("");
  }
  if (fwrite(
          moonbit_tray_test_bmp,
          1,
          sizeof(moonbit_tray_test_bmp),
          file) != sizeof(moonbit_tray_test_bmp)) {
    fclose(file);
    moonbit_tray_test_remove(path);
    return moonbit_tray_copy_message("");
  }
  fclose(file);
  return moonbit_tray_copy_message(path);
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_test_remove_file(
    moonbit_bytes_t path) {
  const char *text = (const char *)path;
  if (text == NULL || text[0] == '\0') {
    return 0;
  }
  return moonbit_tray_test_remove(text);
}

