#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <direct.h>
#include <windows.h>
#ifdef _MSC_VER
#pragma comment(lib, "advapi32.lib")
#endif
#else
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

#if defined(_MSC_VER)
#define MB_THREAD_LOCAL __declspec(thread)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define MB_THREAD_LOCAL _Thread_local
#else
#define MB_THREAD_LOCAL
#endif

#define MB_STATUS_OK 0
#define MB_STATUS_ERROR -1

static MB_THREAD_LOCAL int32_t mb_last_error_code = 0;
static MB_THREAD_LOCAL char mb_last_error_message[1024] = "";

static void mb_set_error(int32_t code, const char *message) {
  mb_last_error_code = code;
  if (message == NULL) {
    mb_last_error_message[0] = '\0';
    return;
  }
  snprintf(mb_last_error_message, sizeof(mb_last_error_message), "%s", message);
}

static void mb_clear_error(void) {
  mb_set_error(0, "");
}

static moonbit_bytes_t mb_make_bytes_from_buffer(const char *buf, size_t len) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buf, len);
  }
  return out;
}

static char *mb_bytes_to_c_string(moonbit_bytes_t bytes) {
  size_t len = (size_t)Moonbit_array_length(bytes);
  char *buffer = (char *)malloc(len + 1);
  if (buffer == NULL) {
    return NULL;
  }
  if (len > 0) {
    memcpy(buffer, bytes, len);
  }
  buffer[len] = '\0';
  return buffer;
}

#ifdef _WIN32
static void mb_set_windows_error(DWORD code, const char *fallback) {
  wchar_t wide_message[512] = {0};
  DWORD flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD len = FormatMessageW(
    flags,
    NULL,
    code,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    wide_message,
    (DWORD)(sizeof(wide_message) / sizeof(wide_message[0])),
    NULL
  );
  if (len == 0) {
    mb_set_error((int32_t)code, fallback);
    return;
  }

  while (len > 0 &&
         (wide_message[len - 1] == L'\r' || wide_message[len - 1] == L'\n' ||
          wide_message[len - 1] == L' ')) {
    wide_message[len - 1] = L'\0';
    len--;
  }
  char message[512 * 3] = "";
  if (WideCharToMultiByte(CP_UTF8, 0, wide_message, -1, message,
                          (int)sizeof(message), NULL, NULL) <= 0) {
    mb_set_error((int32_t)code, fallback);
    return;
  }
  mb_set_error((int32_t)code, message);
}

static wchar_t *mb_utf8_to_wide(const char *value) {
  if (value == NULL) {
    return NULL;
  }
  int length = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
  if (length <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, length) <= 0) {
    free(wide);
    return NULL;
  }
  return wide;
}

static wchar_t *mb_bytes_to_wide_string(
  moonbit_bytes_t bytes,
  const char *allocation_error,
  const char *conversion_error
) {
  char *utf8_value = mb_bytes_to_c_string(bytes);
  wchar_t *wide_value = NULL;

  if (utf8_value == NULL) {
    mb_set_error(ENOMEM, allocation_error);
    return NULL;
  }

  wide_value = mb_utf8_to_wide(utf8_value);
  free(utf8_value);

  if (wide_value == NULL) {
    mb_set_error(ERROR_INVALID_DATA, conversion_error);
    return NULL;
  }

  return wide_value;
}

static moonbit_bytes_t mb_wide_to_bytes(const wchar_t *value) {
  if (value == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  int length = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (length <= 0) {
    return moonbit_make_bytes(0, 0);
  }
  char *buffer = (char *)malloc((size_t)length);
  if (buffer == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, buffer, length, NULL, NULL) <= 0) {
    free(buffer);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t out = mb_make_bytes_from_buffer(buffer, (size_t)(length - 1));
  free(buffer);
  return out;
}

static HKEY mb_open_run_key(REGSAM access) {
  static const wchar_t subkey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  HKEY key = NULL;
  LONG status = RegCreateKeyExW(
    HKEY_CURRENT_USER,
    subkey,
    0,
    NULL,
    REG_OPTION_NON_VOLATILE,
    access,
    NULL,
    &key,
    NULL
  );
  if (status != ERROR_SUCCESS) {
    mb_set_windows_error((DWORD)status, "Failed to open Windows Run registry key");
    return NULL;
  }
  return key;
}

/* Opens the Run key with the requested access without creating it. Query
   and delete paths must not mutate the registry, so a missing key reports
   *out_missing instead of being created the way RegCreateKeyExW would.
   Callers that delete values must request KEY_SET_VALUE in access. */
static HKEY mb_open_run_key_no_create(REGSAM access, int *out_missing) {
  static const wchar_t subkey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  HKEY key = NULL;
  LONG status;
  *out_missing = 0;
  status = RegOpenKeyExW(HKEY_CURRENT_USER, subkey, 0, access, &key);
  if (status == ERROR_FILE_NOT_FOUND) {
    *out_missing = 1;
    return NULL;
  }
  if (status != ERROR_SUCCESS) {
    mb_set_windows_error((DWORD)status, "Failed to open Windows Run registry key");
    return NULL;
  }
  return key;
}
#endif

static int mb_ensure_parent_directory(const char *path) {
  char *copy = NULL;
  size_t len = 0;
  size_t i = 0;

  if (path == NULL) {
    return MB_STATUS_ERROR;
  }

  len = strlen(path);
  copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate directory buffer");
    return MB_STATUS_ERROR;
  }

  memcpy(copy, path, len + 1);

  for (i = 1; i < len; i++) {
    if (copy[i] != '/' && copy[i] != '\\') {
      continue;
    }

    if (i == 2 && copy[1] == ':') {
      continue;
    }

    copy[i] = '\0';
    if (copy[0] != '\0') {
#ifdef _WIN32
      if (_mkdir(copy) != 0 && errno != EEXIST) {
#else
      if (mkdir(copy, 0777) != 0 && errno != EEXIST) {
#endif
        mb_set_error(errno, "Failed to create parent directory");
        free(copy);
        return MB_STATUS_ERROR;
      }
    }
    copy[i] = path[i];
  }

  free(copy);
  return MB_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_platform_code(void) {
#ifdef _WIN32
  return 1;
#elif defined(__APPLE__)
  return 2;
#elif defined(__linux__)
  return 3;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_auto_launch_current_executable_path(void) {
#ifdef _WIN32
  DWORD size = MAX_PATH;
  wchar_t *buffer = NULL;

  while (1) {
    buffer = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
    if (buffer == NULL) {
      mb_set_error(ENOMEM, "Failed to allocate executable path buffer");
      return moonbit_make_bytes(0, 0);
    }

    DWORD written = GetModuleFileNameW(NULL, buffer, size);
    if (written == 0) {
      free(buffer);
      mb_set_windows_error(GetLastError(), "Failed to get current executable path");
      return moonbit_make_bytes(0, 0);
    }

    if (written < size - 1) {
      moonbit_bytes_t out = mb_wide_to_bytes(buffer);
      free(buffer);
      mb_clear_error();
      return out;
    }

    free(buffer);
    size *= 2;
  }
#elif defined(__APPLE__)
  uint32_t size = 0;
  _NSGetExecutablePath(NULL, &size);
  char *buffer = (char *)malloc((size_t)size + 1);
  if (buffer == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate executable path buffer");
    return moonbit_make_bytes(0, 0);
  }
  if (_NSGetExecutablePath(buffer, &size) != 0) {
    free(buffer);
    mb_set_error(errno, "Failed to get current executable path");
    return moonbit_make_bytes(0, 0);
  }
  buffer[size] = '\0';
  mb_clear_error();
  moonbit_bytes_t out = mb_make_bytes_from_buffer(buffer, strlen(buffer));
  free(buffer);
  return out;
#elif defined(__linux__)
  char buffer[PATH_MAX];
  ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (length < 0) {
    mb_set_error(errno, "Failed to get current executable path");
    return moonbit_make_bytes(0, 0);
  }
  buffer[length] = '\0';
  mb_clear_error();
  return mb_make_bytes_from_buffer(buffer, (size_t)length);
#else
  mb_set_error(ENOSYS, "Executable path lookup is unsupported on this platform");
  return moonbit_make_bytes(0, 0);
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_auto_launch_home_directory(void) {
#ifdef _WIN32
  DWORD size = GetEnvironmentVariableW(L"USERPROFILE", NULL, 0);
  if (size == 0) {
    mb_set_windows_error(GetLastError(), "Failed to read USERPROFILE");
    return moonbit_make_bytes(0, 0);
  }

  wchar_t *buffer = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
  if (buffer == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate home directory buffer");
    return moonbit_make_bytes(0, 0);
  }

  if (GetEnvironmentVariableW(L"USERPROFILE", buffer, size) == 0) {
    free(buffer);
    mb_set_windows_error(GetLastError(), "Failed to read USERPROFILE");
    return moonbit_make_bytes(0, 0);
  }

  moonbit_bytes_t out = mb_wide_to_bytes(buffer);
  free(buffer);
  mb_clear_error();
  return out;
#else
  const char *home = getenv("HOME");
  if (home == NULL || *home == '\0') {
    mb_set_error(errno == 0 ? ENOENT : errno, "Failed to read HOME");
    return moonbit_make_bytes(0, 0);
  }
  mb_clear_error();
  return mb_make_bytes_from_buffer(home, strlen(home));
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_write_text_file(moonbit_bytes_t path, moonbit_bytes_t contents) {
  char *file_path = mb_bytes_to_c_string(path);
  char *text = NULL;
  size_t length = (size_t)Moonbit_array_length(contents);
  FILE *file = NULL;

  if (file_path == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate file path buffer");
    return MB_STATUS_ERROR;
  }

  text = (char *)malloc(length + 1);
  if (text == NULL) {
    free(file_path);
    mb_set_error(ENOMEM, "Failed to allocate file contents buffer");
    return MB_STATUS_ERROR;
  }
  if (length > 0) {
    memcpy(text, contents, length);
  }
  text[length] = '\0';

  if (mb_ensure_parent_directory(file_path) != MB_STATUS_OK) {
    free(text);
    free(file_path);
    return MB_STATUS_ERROR;
  }

  file = fopen(file_path, "wb");
  if (file == NULL) {
    mb_set_error(errno, "Failed to open output file");
    free(text);
    free(file_path);
    return MB_STATUS_ERROR;
  }

  if (length > 0 && fwrite(text, 1, length, file) != length) {
    mb_set_error(errno, "Failed to write output file");
    fclose(file);
    free(text);
    free(file_path);
    return MB_STATUS_ERROR;
  }

  fclose(file);
  free(text);
  free(file_path);
  mb_clear_error();
  return MB_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_remove_file(moonbit_bytes_t path) {
  char *file_path = mb_bytes_to_c_string(path);
  if (file_path == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate file path buffer");
    return MB_STATUS_ERROR;
  }

  if (remove(file_path) != 0) {
    if (errno == ENOENT) {
      free(file_path);
      mb_clear_error();
      return MB_STATUS_OK;
    }
    mb_set_error(errno, "Failed to remove file");
    free(file_path);
    return MB_STATUS_ERROR;
  }

  free(file_path);
  mb_clear_error();
  return MB_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_file_exists(moonbit_bytes_t path) {
  char *file_path = mb_bytes_to_c_string(path);
  FILE *file = NULL;

  if (file_path == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate file path buffer");
    return MB_STATUS_ERROR;
  }

  file = fopen(file_path, "rb");
  if (file == NULL) {
    if (errno == ENOENT) {
      free(file_path);
      mb_clear_error();
      return 0;
    }
    mb_set_error(errno, "Failed to check file existence");
    free(file_path);
    return MB_STATUS_ERROR;
  }

  fclose(file);
  free(file_path);
  mb_clear_error();
  return 1;
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_windows_set_run_entry(moonbit_bytes_t name, moonbit_bytes_t command) {
#ifdef _WIN32
  wchar_t *wide_name = NULL;
  wchar_t *wide_command = NULL;
  HKEY key = NULL;
  LONG status = ERROR_SUCCESS;

  wide_name = mb_bytes_to_wide_string(
    name,
    "Failed to allocate registry entry name",
    "Failed to convert registry entry name to UTF-16"
  );
  wide_command = mb_bytes_to_wide_string(
    command,
    "Failed to allocate registry entry command",
    "Failed to convert registry entry command to UTF-16"
  );

  if (wide_name == NULL || wide_command == NULL) {
    free(wide_name);
    free(wide_command);
    return MB_STATUS_ERROR;
  }

  key = mb_open_run_key(KEY_SET_VALUE);
  if (key == NULL) {
    free(wide_name);
    free(wide_command);
    return MB_STATUS_ERROR;
  }

  status = RegSetValueExW(
    key,
    wide_name,
    0,
    REG_SZ,
    (const BYTE *)wide_command,
    (DWORD)((wcslen(wide_command) + 1) * sizeof(wchar_t))
  );

  RegCloseKey(key);
  free(wide_name);
  free(wide_command);

  if (status != ERROR_SUCCESS) {
    mb_set_windows_error((DWORD)status, "Failed to write Windows Run registry value");
    return MB_STATUS_ERROR;
  }

  mb_clear_error();
  return MB_STATUS_OK;
#else
  (void)name;
  (void)command;
  mb_set_error(ENOSYS, "Windows Run registry is unavailable on this platform");
  return MB_STATUS_ERROR;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_windows_delete_run_entry(moonbit_bytes_t name) {
#ifdef _WIN32
  wchar_t *wide_name = mb_bytes_to_wide_string(
    name,
    "Failed to allocate registry entry name",
    "Failed to convert registry entry name to UTF-16"
  );
  HKEY key = NULL;
  LONG status = ERROR_SUCCESS;
  int missing_key = 0;

  if (wide_name == NULL) {
    return MB_STATUS_ERROR;
  }

  key = mb_open_run_key_no_create(KEY_READ | KEY_SET_VALUE, &missing_key);
  if (key == NULL) {
    free(wide_name);
    if (missing_key) {
      mb_clear_error();
      return MB_STATUS_OK;
    }
    return MB_STATUS_ERROR;
  }

  status = RegDeleteValueW(key, wide_name);
  RegCloseKey(key);
  free(wide_name);

  if (status == ERROR_FILE_NOT_FOUND) {
    mb_clear_error();
    return MB_STATUS_OK;
  }
  if (status != ERROR_SUCCESS) {
    mb_set_windows_error((DWORD)status, "Failed to delete Windows Run registry value");
    return MB_STATUS_ERROR;
  }

  mb_clear_error();
  return MB_STATUS_OK;
#else
  (void)name;
  mb_set_error(ENOSYS, "Windows Run registry is unavailable on this platform");
  return MB_STATUS_ERROR;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_windows_run_entry_exists(moonbit_bytes_t name) {
#ifdef _WIN32
  wchar_t *wide_name = mb_bytes_to_wide_string(
    name,
    "Failed to allocate registry entry name",
    "Failed to convert registry entry name to UTF-16"
  );
  HKEY key = NULL;
  DWORD type = 0;
  DWORD size = 0;
  LONG status = ERROR_SUCCESS;
  int missing_key = 0;

  if (wide_name == NULL) {
    return MB_STATUS_ERROR;
  }

  key = mb_open_run_key_no_create(KEY_READ, &missing_key);
  if (key == NULL) {
    free(wide_name);
    if (missing_key) {
      mb_clear_error();
      return 0;
    }
    return MB_STATUS_ERROR;
  }

  status = RegQueryValueExW(key, wide_name, NULL, &type, NULL, &size);
  RegCloseKey(key);
  free(wide_name);

  if (status == ERROR_FILE_NOT_FOUND) {
    mb_clear_error();
    return 0;
  }
  if (status != ERROR_SUCCESS) {
    mb_set_windows_error((DWORD)status, "Failed to query Windows Run registry value");
    return MB_STATUS_ERROR;
  }
  if (type != REG_SZ && type != REG_EXPAND_SZ) {
    mb_clear_error();
    return 0;
  }

  mb_clear_error();
  return 1;
#else
  (void)name;
  mb_set_error(ENOSYS, "Windows Run registry is unavailable on this platform");
  return MB_STATUS_ERROR;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_auto_launch_last_error_code(void) {
  return mb_last_error_code;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_auto_launch_last_error_message(void) {
  return mb_make_bytes_from_buffer(mb_last_error_message, strlen(mb_last_error_message));
}
