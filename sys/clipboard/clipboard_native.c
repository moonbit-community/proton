#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#endif
#else
#include <sys/wait.h>
#include <unistd.h>
#define MB_POPEN popen
#define MB_PCLOSE pclose
#endif

#define MB_STATUS_OK 0
#define MB_STATUS_NOT_AVAILABLE 1
#define MB_STATUS_PERMISSION_DENIED 2
#define MB_STATUS_BACKEND_FAILURE 3

#if defined(_MSC_VER)
#define MB_THREAD_LOCAL __declspec(thread)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define MB_THREAD_LOCAL _Thread_local
#else
#define MB_THREAD_LOCAL
#endif

static MB_THREAD_LOCAL int32_t mb_last_error_code = MB_STATUS_OK;
static MB_THREAD_LOCAL char mb_last_error_message[512] = "";

static void mb_set_error(int32_t code, const char *message) {
  mb_last_error_code = code;
  if (message == NULL) {
    mb_last_error_message[0] = '\0';
    return;
  }
  snprintf(mb_last_error_message, sizeof(mb_last_error_message), "%s", message);
}

static moonbit_bytes_t mb_make_bytes_from_buffer(const char *buf, size_t len) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buf, len);
  }
  return out;
}

#ifndef _WIN32
static int mb_command_exists(const char *name) {
  const char *path = getenv("PATH");
  if (path == NULL || *path == '\0') {
    return 0;
  }

  size_t name_len = strlen(name);
  const char *segment = path;

  while (1) {
    const char *separator = strchr(segment, ':');
    size_t segment_len =
      separator == NULL ? strlen(segment) : (size_t)(separator - segment);
    size_t candidate_len = segment_len + 1 + name_len + 1;
    char *candidate = (char *)malloc(candidate_len);
    if (candidate == NULL) {
      return 0;
    }

    if (segment_len > 0) {
      memcpy(candidate, segment, segment_len);
      candidate[segment_len] = '/';
      memcpy(candidate + segment_len + 1, name, name_len + 1);
    } else {
      memcpy(candidate, name, name_len + 1);
    }

    int found = access(candidate, X_OK) == 0;
    free(candidate);
    if (found) {
      return 1;
    }

    if (separator == NULL) {
      break;
    }
    segment = separator + 1;
  }

  return 0;
}

static int mb_unix_clipboard_backend_available(void) {
#if defined(__APPLE__)
  return mb_command_exists("pbcopy") && mb_command_exists("pbpaste");
#elif defined(__linux__)
  if (mb_command_exists("wl-copy") && mb_command_exists("wl-paste")) {
    return 1;
  }
  if (mb_command_exists("xclip")) {
    return 1;
  }
  if (mb_command_exists("xsel")) {
    return 1;
  }
  return 0;
#else
  return 0;
#endif
}
#endif

#ifdef _WIN32
static int mb_win32_error_to_status(DWORD err) {
  if (err == ERROR_ACCESS_DENIED || err == ERROR_CLIPBOARD_NOT_OPEN) {
    return MB_STATUS_PERMISSION_DENIED;
  }
  return MB_STATUS_BACKEND_FAILURE;
}

static int mb_win_read_clipboard(char **out_buf, size_t *out_len) {
  *out_buf = NULL;
  *out_len = 0;

  if (!OpenClipboard(NULL)) {
    return mb_win32_error_to_status(GetLastError());
  }

  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    CloseClipboard();
    *out_buf = (char *)malloc(1);
    if (*out_buf == NULL) {
      return MB_STATUS_BACKEND_FAILURE;
    }
    (*out_buf)[0] = '\0';
    return MB_STATUS_OK;
  }

  HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (handle == NULL) {
    DWORD err = GetLastError();
    CloseClipboard();
    return mb_win32_error_to_status(err);
  }

  const wchar_t *value = (const wchar_t *)GlobalLock(handle);
  if (value == NULL) {
    DWORD err = GetLastError();
    CloseClipboard();
    return mb_win32_error_to_status(err);
  }

  int utf8_len_with_nul = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (utf8_len_with_nul <= 0) {
    GlobalUnlock(handle);
    CloseClipboard();
    return MB_STATUS_BACKEND_FAILURE;
  }

  int utf8_len = utf8_len_with_nul - 1;
  char *buf = (char *)malloc((size_t)utf8_len + 1);
  if (buf == NULL) {
    GlobalUnlock(handle);
    CloseClipboard();
    return MB_STATUS_BACKEND_FAILURE;
  }

  int converted =
    WideCharToMultiByte(CP_UTF8, 0, value, -1, buf, utf8_len_with_nul, NULL, NULL);
  GlobalUnlock(handle);
  CloseClipboard();
  if (converted <= 0) {
    free(buf);
    return MB_STATUS_BACKEND_FAILURE;
  }

  *out_buf = buf;
  *out_len = (size_t)utf8_len;
  return MB_STATUS_OK;
}

static int mb_win_write_clipboard(const char *utf8_text, size_t utf8_len) {
  int wide_len = 0;
  if (utf8_len > 0) {
    wide_len = MultiByteToWideChar(CP_UTF8, 0, utf8_text, (int)utf8_len, NULL, 0);
    if (wide_len <= 0) {
      return MB_STATUS_BACKEND_FAILURE;
    }
  }

  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, (size_t)(wide_len + 1) * sizeof(wchar_t));
  if (handle == NULL) {
    return MB_STATUS_BACKEND_FAILURE;
  }

  wchar_t *buffer = (wchar_t *)GlobalLock(handle);
  if (buffer == NULL) {
    GlobalFree(handle);
    return MB_STATUS_BACKEND_FAILURE;
  }

  if (wide_len > 0) {
    int converted =
      MultiByteToWideChar(CP_UTF8, 0, utf8_text, (int)utf8_len, buffer, wide_len);
    if (converted <= 0) {
      GlobalUnlock(handle);
      GlobalFree(handle);
      return MB_STATUS_BACKEND_FAILURE;
    }
  }
  buffer[wide_len] = L'\0';
  GlobalUnlock(handle);

  if (!OpenClipboard(NULL)) {
    GlobalFree(handle);
    return mb_win32_error_to_status(GetLastError());
  }

  if (!EmptyClipboard()) {
    DWORD err = GetLastError();
    CloseClipboard();
    GlobalFree(handle);
    return mb_win32_error_to_status(err);
  }

  if (SetClipboardData(CF_UNICODETEXT, handle) == NULL) {
    DWORD err = GetLastError();
    CloseClipboard();
    GlobalFree(handle);
    return mb_win32_error_to_status(err);
  }

  CloseClipboard();
  return MB_STATUS_OK;
}
#endif

#ifndef _WIN32
static int mb_exit_code_from_pclose(int pclose_rc) {
  if (pclose_rc == -1) {
    return -1;
  }
  if (WIFEXITED(pclose_rc)) {
    return WEXITSTATUS(pclose_rc);
  }
  return -1;
}

static int mb_run_read_command(const char *command, char **out_buf, size_t *out_len) {
  FILE *pipe = MB_POPEN(command, "r");
  if (pipe == NULL) {
    return -1;
  }

  size_t cap = 1024;
  size_t len = 0;
  char *buf = (char *)malloc(cap);
  if (buf == NULL) {
    MB_PCLOSE(pipe);
    return -1;
  }

  while (1) {
    if (len == cap) {
      cap *= 2;
      char *next = (char *)realloc(buf, cap);
      if (next == NULL) {
        free(buf);
        MB_PCLOSE(pipe);
        return -1;
      }
      buf = next;
    }

    size_t n = fread(buf + len, 1, cap - len, pipe);
    len += n;
    if (n == 0) {
      if (feof(pipe)) {
        break;
      }
      free(buf);
      MB_PCLOSE(pipe);
      return -1;
    }
  }

  int exit_code = mb_exit_code_from_pclose(MB_PCLOSE(pipe));
  if (exit_code != 0) {
    free(buf);
    return exit_code;
  }

  *out_buf = buf;
  *out_len = len;
  return 0;
}

static int mb_run_write_command(const char *command, const char *text, size_t len) {
  FILE *pipe = MB_POPEN(command, "w");
  if (pipe == NULL) {
    return -1;
  }

  if (len > 0 && fwrite(text, 1, len, pipe) != len) {
    MB_PCLOSE(pipe);
    return -1;
  }

  return mb_exit_code_from_pclose(MB_PCLOSE(pipe));
}

static int mb_try_read_commands(const char *const *commands, size_t command_count,
                                char **out_buf, size_t *out_len) {
  int saw_not_available = 0;
  int saw_permission_denied = 0;

  for (size_t i = 0; i < command_count; i++) {
    int rc = mb_run_read_command(commands[i], out_buf, out_len);
    if (rc == 0) {
      return MB_STATUS_OK;
    }
    if (rc == 127) {
      saw_not_available = 1;
      continue;
    }
    if (rc == 126) {
      saw_permission_denied = 1;
      continue;
    }
  }

  if (saw_permission_denied) {
    return MB_STATUS_PERMISSION_DENIED;
  }
  if (saw_not_available) {
    return MB_STATUS_NOT_AVAILABLE;
  }
  return MB_STATUS_BACKEND_FAILURE;
}

static int mb_try_write_commands(const char *const *commands, size_t command_count,
                                 const char *text, size_t len) {
  int saw_not_available = 0;
  int saw_permission_denied = 0;

  for (size_t i = 0; i < command_count; i++) {
    int rc = mb_run_write_command(commands[i], text, len);
    if (rc == 0) {
      return MB_STATUS_OK;
    }
    if (rc == 127) {
      saw_not_available = 1;
      continue;
    }
    if (rc == 126) {
      saw_permission_denied = 1;
      continue;
    }
  }

  if (saw_permission_denied) {
    return MB_STATUS_PERMISSION_DENIED;
  }
  if (saw_not_available) {
    return MB_STATUS_NOT_AVAILABLE;
  }
  return MB_STATUS_BACKEND_FAILURE;
}
#endif

static int mb_try_read_clipboard(char **out_buf, size_t *out_len) {
#ifdef _WIN32
  return mb_win_read_clipboard(out_buf, out_len);
#elif __APPLE__
  static const char *const commands[] = { "pbpaste" };
  return mb_try_read_commands(commands, sizeof(commands) / sizeof(commands[0]), out_buf, out_len);
#elif __linux__
  static const char *const commands[] = {
    "wl-paste -n 2>/dev/null",
    "xclip -selection clipboard -o 2>/dev/null",
    "xsel --clipboard --output 2>/dev/null",
  };
  return mb_try_read_commands(commands, sizeof(commands) / sizeof(commands[0]), out_buf, out_len);
#else
  (void)out_buf;
  (void)out_len;
  return MB_STATUS_NOT_AVAILABLE;
#endif
}

static int mb_try_write_clipboard(const char *text, size_t len) {
#ifdef _WIN32
  return mb_win_write_clipboard(text, len);
#elif __APPLE__
  static const char *const commands[] = { "pbcopy" };
  return mb_try_write_commands(commands, sizeof(commands) / sizeof(commands[0]), text, len);
#elif __linux__
  static const char *const commands[] = {
    "wl-copy 2>/dev/null",
    "xclip -selection clipboard 2>/dev/null",
    "xsel --clipboard --input 2>/dev/null",
  };
  return mb_try_write_commands(commands, sizeof(commands) / sizeof(commands[0]), text, len);
#else
  (void)text;
  (void)len;
  return MB_STATUS_NOT_AVAILABLE;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_clipboard_platform_supported(void) {
#if defined(_WIN32)
  return 1;
#elif defined(__APPLE__) || defined(__linux__)
  return mb_unix_clipboard_backend_available();
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_clipboard_read_text(void) {
  char *buffer = NULL;
  size_t len = 0;
  int rc = mb_try_read_clipboard(&buffer, &len);

  if (rc == MB_STATUS_OK) {
    mb_set_error(MB_STATUS_OK, "");
    moonbit_bytes_t result = mb_make_bytes_from_buffer(buffer, len);
    free(buffer);
    return result;
  }

  if (rc == MB_STATUS_NOT_AVAILABLE) {
    mb_set_error(MB_STATUS_NOT_AVAILABLE, "Clipboard backend is unavailable on this system");
  } else if (rc == MB_STATUS_PERMISSION_DENIED) {
    mb_set_error(MB_STATUS_PERMISSION_DENIED, "Clipboard permission denied");
  } else {
    mb_set_error(MB_STATUS_BACKEND_FAILURE, "Failed to read clipboard");
  }

  return moonbit_make_bytes(0, 0);
}

MOONBIT_FFI_EXPORT int32_t mb_clipboard_write_text(moonbit_bytes_t text) {
  size_t len = (size_t)Moonbit_array_length(text);
  int rc = mb_try_write_clipboard((const char *)text, len);

  if (rc == MB_STATUS_OK) {
    mb_set_error(MB_STATUS_OK, "");
    return MB_STATUS_OK;
  }

  if (rc == MB_STATUS_NOT_AVAILABLE) {
    mb_set_error(MB_STATUS_NOT_AVAILABLE, "Clipboard backend is unavailable on this system");
    return MB_STATUS_NOT_AVAILABLE;
  }
  if (rc == MB_STATUS_PERMISSION_DENIED) {
    mb_set_error(MB_STATUS_PERMISSION_DENIED, "Clipboard permission denied");
    return MB_STATUS_PERMISSION_DENIED;
  }

  mb_set_error(MB_STATUS_BACKEND_FAILURE, "Failed to write clipboard");
  return MB_STATUS_BACKEND_FAILURE;
}

MOONBIT_FFI_EXPORT int32_t mb_clipboard_last_error_code(void) {
  return mb_last_error_code;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_clipboard_last_error_message(void) {
  return mb_make_bytes_from_buffer(mb_last_error_message, strlen(mb_last_error_message));
}
