#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#else
#include <unistd.h>
#endif

typedef struct {
  FILE *file;
} proton_logging_file_t;

static void proton_logging_close_handle(proton_logging_file_t *handle) {
  if (handle == NULL || handle->file == NULL) {
    return;
  }
  (void)fclose(handle->file);
  handle->file = NULL;
}

static void proton_logging_file_finalizer(void *payload) {
  proton_logging_close_handle((proton_logging_file_t *)payload);
}

#ifndef _WIN32
static char *proton_logging_copy_bytes(moonbit_bytes_t bytes) {
  int32_t length = Moonbit_array_length(bytes);
  char *copy = (char *)malloc((size_t)length + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (length > 0) {
    memcpy(copy, bytes, (size_t)length);
  }
  copy[length] = '\0';
  return copy;
}
#else
static wchar_t *proton_logging_utf8_to_wide(moonbit_bytes_t bytes) {
  int32_t length = Moonbit_array_length(bytes);
  int wide_length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        (const char *)bytes, length, NULL, 0);
  if (wide_length <= 0) {
    return NULL;
  }
  wchar_t *wide =
      (wchar_t *)malloc(((size_t)wide_length + 1) * sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                          (const char *)bytes, length, wide,
                          wide_length) != wide_length) {
    free(wide);
    return NULL;
  }
  wide[wide_length] = L'\0';
  return wide;
}
#endif

MOONBIT_FFI_EXPORT proton_logging_file_t *
proton_logging_open_file(moonbit_bytes_t path) {
  proton_logging_file_t *handle =
      (proton_logging_file_t *)moonbit_make_external_object(
          proton_logging_file_finalizer,
          (uint32_t)sizeof(proton_logging_file_t));
  if (handle == NULL) {
    return NULL;
  }
  handle->file = NULL;
#ifdef _WIN32
  wchar_t *wide_path = proton_logging_utf8_to_wide(path);
  if (wide_path != NULL) {
    handle->file = _wfopen(wide_path, L"ab");
    free(wide_path);
  }
#else
  char *native_path = proton_logging_copy_bytes(path);
  if (native_path != NULL) {
    handle->file = fopen(native_path, "ab");
    free(native_path);
  }
#endif
  return handle;
}

MOONBIT_FFI_EXPORT int32_t
proton_logging_file_is_open(proton_logging_file_t *handle) {
  return handle != NULL && handle->file != NULL;
}

MOONBIT_FFI_EXPORT int32_t proton_logging_write_file(
    proton_logging_file_t *handle, moonbit_bytes_t data) {
  if (handle == NULL || handle->file == NULL) {
    return -1;
  }
  int32_t length = Moonbit_array_length(data);
  if (length > 0 &&
      fwrite(data, 1, (size_t)length, handle->file) != (size_t)length) {
    return -1;
  }
  return fflush(handle->file) == 0 ? 0 : -1;
}

MOONBIT_FFI_EXPORT void
proton_logging_close_file(proton_logging_file_t *handle) {
  proton_logging_close_handle(handle);
}

MOONBIT_FFI_EXPORT int32_t proton_logging_write_stderr(moonbit_bytes_t data) {
  int32_t length = Moonbit_array_length(data);
  if (length > 0 &&
      fwrite(data, 1, (size_t)length, stderr) != (size_t)length) {
    return -1;
  }
  return fflush(stderr) == 0 ? 0 : -1;
}

MOONBIT_FFI_EXPORT int32_t proton_logging_process_id(void) {
#ifdef _WIN32
  return (int32_t)GetCurrentProcessId();
#else
  return (int32_t)getpid();
#endif
}
