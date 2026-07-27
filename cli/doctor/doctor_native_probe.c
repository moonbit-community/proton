#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

static int32_t doctor_copy_text(char *buffer, int32_t buffer_len,
                                const char *text);

/*
 * Keep this stub limited to the platform dynamic-loader boundary. Probe
 * sequencing, buffer sizing, user-facing diagnostics, and JSON interpretation
 * belong in doctor_native_probe.mbt.
 */
#ifdef _WIN32
#include <windows.h>
typedef HMODULE doctor_library_t;
#define doctor_symbol(lib, name) GetProcAddress(lib, name)
#define doctor_close(lib) FreeLibrary(lib)

static void doctor_windows_error(char *buffer, int32_t buffer_len,
                                 DWORD error_code) {
  if (buffer == NULL || buffer_len <= 0) {
    return;
  }

  wchar_t wide_message[512] = {0};
  DWORD wide_length = FormatMessageW(
      FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL,
      error_code, 0, wide_message,
      (DWORD)(sizeof(wide_message) / sizeof(wide_message[0])), NULL);
  while (wide_length > 0 &&
         (wide_message[wide_length - 1] == L'\r' ||
          wide_message[wide_length - 1] == L'\n' ||
          wide_message[wide_length - 1] == L' ')) {
    wide_length--;
  }
  if (wide_length > 0) {
    char utf8_message[1024] = {0};
    int converted = WideCharToMultiByte(
        CP_UTF8, 0, wide_message, (int)wide_length, utf8_message,
        (int)sizeof(utf8_message) - 1, NULL, NULL);
    if (converted > 0) {
      utf8_message[converted] = '\0';
      snprintf(buffer, (size_t)buffer_len, "Windows error %lu: %s",
               (unsigned long)error_code, utf8_message);
      return;
    }
  }
  snprintf(buffer, (size_t)buffer_len, "Windows error %lu",
           (unsigned long)error_code);
}

static doctor_library_t doctor_open(const char *path, char *error_buffer,
                                    int32_t error_buffer_len) {
  int wide_length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                        NULL, 0);
  if (wide_length <= 0) {
    doctor_windows_error(error_buffer, error_buffer_len, GetLastError());
    return NULL;
  }
  wchar_t *wide_path =
      (wchar_t *)malloc((size_t)wide_length * sizeof(wchar_t));
  if (wide_path == NULL) {
    doctor_copy_text(error_buffer, error_buffer_len,
                     "out of memory while converting UTF-8 library path");
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide_path,
                          wide_length) != wide_length) {
    DWORD error_code = GetLastError();
    free(wide_path);
    doctor_windows_error(error_buffer, error_buffer_len, error_code);
    return NULL;
  }
  doctor_library_t library = LoadLibraryW(wide_path);
  DWORD error_code = library == NULL ? GetLastError() : ERROR_SUCCESS;
  free(wide_path);
  if (library == NULL) {
    doctor_windows_error(error_buffer, error_buffer_len, error_code);
  }
  return library;
}
#else
#include <dlfcn.h>
typedef void *doctor_library_t;
#define doctor_symbol(lib, name) dlsym(lib, name)
#define doctor_close(lib) dlclose(lib)

static doctor_library_t doctor_open(const char *path, char *error_buffer,
                                    int32_t error_buffer_len) {
  doctor_library_t library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) {
    const char *error = dlerror();
    doctor_copy_text(error_buffer, error_buffer_len,
                     error == NULL ? "dlopen failed" : error);
  }
  return library;
}
#endif

enum {
  DOCTOR_NATIVE_OK = 0,
  DOCTOR_NATIVE_LOAD_ERROR = -1,
  DOCTOR_NATIVE_SYMBOL_ERROR = -2,
  DOCTOR_NATIVE_INVALID_ARGUMENT = -4,
  DOCTOR_NATIVE_INVALID_HANDLE = -5,
  DOCTOR_NATIVE_ABI_MISMATCH = -6,
};

typedef int32_t (*doctor_abi_fn)(void);
typedef int32_t (*doctor_info_fn)(char *, int32_t, int32_t *);
typedef int32_t (*doctor_probe_fn)(const char *);
typedef int32_t (*doctor_error_fn)(char *, int32_t);
typedef int32_t (*doctor_create_fn)(const char *, int64_t *);
typedef int32_t (*doctor_destroy_fn)(int64_t);

/*
 * This is the payload of a MoonBit external object. The object container is
 * owned by the MoonBit GC; only the dynamic library resource is released by
 * the finalizer or by an explicit close.
 */
typedef struct doctor_native_library {
  doctor_library_t library;
  doctor_info_fn info;
  doctor_probe_fn probe;
  doctor_error_fn last_error;
  doctor_create_fn create;
  doctor_destroy_fn destroy;
} doctor_native_library_t;

static int doctor_context_is_open(const doctor_native_library_t *context) {
  return context != NULL && context->library != NULL;
}

static void doctor_mark_context_closed(doctor_native_library_t *context) {
  memset(context, 0, sizeof(*context));
}

static void doctor_release_context(doctor_native_library_t *context) {
  if (!doctor_context_is_open(context)) {
    return;
  }
  doctor_close(context->library);
  doctor_mark_context_closed(context);
}

/*
 * Logically close the MoonBit handle without decrementing the platform loader
 * reference. Once a runtime has been created, keeping the module mapped is
 * safer than unloading code that delayed platform cleanup may still execute.
 * The operating system reclaims the module when the process exits.
 */
static void doctor_abandon_context(doctor_native_library_t *context) {
  if (!doctor_context_is_open(context)) {
    return;
  }
  doctor_mark_context_closed(context);
}

static void doctor_native_library_finalize(void *payload) {
  doctor_native_library_t *context = (doctor_native_library_t *)payload;
  doctor_release_context(context);
}

static doctor_native_library_t *doctor_make_context(void) {
  doctor_native_library_t *context =
      (doctor_native_library_t *)moonbit_make_external_object(
          doctor_native_library_finalize,
          (uint32_t)sizeof(doctor_native_library_t));
  memset(context, 0, sizeof(*context));
  return context;
}

// Copy a diagnostic into caller-owned memory and return its full length.
static int32_t doctor_copy_text(char *buffer, int32_t buffer_len,
                                const char *text) {
  if (text == NULL) {
    text = "";
  }
  size_t required = strlen(text);
  if (buffer != NULL && buffer_len > 0) {
    size_t copy_len = required;
    if (copy_len >= (size_t)buffer_len) {
      copy_len = (size_t)buffer_len - 1;
    }
    memcpy(buffer, text, copy_len);
    buffer[copy_len] = '\0';
  }
  return required > INT32_MAX ? INT32_MAX : (int32_t)required;
}

static int32_t doctor_invalid_handle(char *buffer, int32_t buffer_len) {
  doctor_copy_text(buffer, buffer_len, "invalid native probe handle");
  return DOCTOR_NATIVE_INVALID_HANDLE;
}

static int doctor_output_buffer_is_valid(const char *buffer, int32_t length) {
  return length >= 0 && (length == 0 || buffer != NULL);
}

MOONBIT_FFI_EXPORT doctor_native_library_t *proton_doctor_native_open(
    moonbit_bytes_t library_path, int32_t expected_abi_version,
    int32_t *out_abi_version, int32_t *out_status, char *error_buffer,
    int32_t error_buffer_len) {
  doctor_native_library_t *context = doctor_make_context();
  if (out_abi_version != NULL) {
    *out_abi_version = 0;
  }
  if (out_status != NULL) {
    *out_status = DOCTOR_NATIVE_INVALID_ARGUMENT;
  }
  if (out_abi_version == NULL || out_status == NULL) {
    doctor_copy_text(error_buffer, error_buffer_len,
                     "ABI and status output pointers are required");
    return context;
  }
  if (library_path == NULL) {
    doctor_copy_text(error_buffer, error_buffer_len, "library_path is required");
    return context;
  }

  doctor_library_t library =
      doctor_open((const char *)library_path, error_buffer, error_buffer_len);
  if (library == NULL) {
    *out_status = DOCTOR_NATIVE_LOAD_ERROR;
    return context;
  }

  /* ABI is the only symbol touched before compatibility is established. */
  doctor_abi_fn abi = (doctor_abi_fn)doctor_symbol(
      library, "proton_abi_version");
  if (abi == NULL) {
    doctor_close(library);
    *out_status = DOCTOR_NATIVE_SYMBOL_ERROR;
    doctor_copy_text(error_buffer, error_buffer_len, "proton_abi_version");
    return context;
  }
  int32_t actual_abi_version = abi();
  *out_abi_version = actual_abi_version;
  if (actual_abi_version != expected_abi_version) {
    doctor_close(library);
    *out_status = DOCTOR_NATIVE_ABI_MISMATCH;
    doctor_copy_text(error_buffer, error_buffer_len, "");
    return context;
  }

  /* Resolve the rest of the ABI only after the version check above. */
  doctor_info_fn info =
      (doctor_info_fn)doctor_symbol(library, "proton_runtime_info_json");
  doctor_probe_fn probe =
      (doctor_probe_fn)doctor_symbol(library, "proton_runtime_probe_json");
  doctor_error_fn last_error =
      (doctor_error_fn)doctor_symbol(library, "proton_last_error_message");
  doctor_create_fn create = (doctor_create_fn)doctor_symbol(
      library, "proton_runtime_create_json");
  doctor_destroy_fn destroy =
      (doctor_destroy_fn)doctor_symbol(library, "proton_runtime_destroy");

  const char *missing_symbol = NULL;
  if (info == NULL) {
    missing_symbol = "proton_runtime_info_json";
  } else if (probe == NULL) {
    missing_symbol = "proton_runtime_probe_json";
  } else if (last_error == NULL) {
    missing_symbol = "proton_last_error_message";
  } else if (create == NULL) {
    missing_symbol = "proton_runtime_create_json";
  } else if (destroy == NULL) {
    missing_symbol = "proton_runtime_destroy";
  }
  if (missing_symbol != NULL) {
    doctor_close(library);
    *out_status = DOCTOR_NATIVE_SYMBOL_ERROR;
    doctor_copy_text(error_buffer, error_buffer_len, missing_symbol);
    return context;
  }
  context->library = library;
  context->info = info;
  context->probe = probe;
  context->last_error = last_error;
  context->create = create;
  context->destroy = destroy;
  *out_status = DOCTOR_NATIVE_OK;
  doctor_copy_text(error_buffer, error_buffer_len, "");
  return context;
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_close(
    doctor_native_library_t *handle) {
  if (!doctor_context_is_open(handle)) {
    return DOCTOR_NATIVE_INVALID_HANDLE;
  }
  doctor_release_context(handle);
  return DOCTOR_NATIVE_OK;
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_abandon(
    doctor_native_library_t *handle) {
  if (!doctor_context_is_open(handle)) {
    return DOCTOR_NATIVE_INVALID_HANDLE;
  }
  doctor_abandon_context(handle);
  return DOCTOR_NATIVE_OK;
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_runtime_info_json(
    doctor_native_library_t *handle, char *buffer, int32_t buffer_len,
    int32_t *out_required_len) {
  if (!doctor_context_is_open(handle)) {
    return doctor_invalid_handle(buffer, buffer_len);
  }
  if (out_required_len == NULL ||
      !doctor_output_buffer_is_valid(buffer, buffer_len)) {
    return DOCTOR_NATIVE_INVALID_ARGUMENT;
  }
  return handle->info(buffer, buffer_len, out_required_len);
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_runtime_probe_json(
    doctor_native_library_t *handle, moonbit_bytes_t config_json) {
  if (!doctor_context_is_open(handle)) {
    return DOCTOR_NATIVE_INVALID_HANDLE;
  }
  if (config_json == NULL) {
    return DOCTOR_NATIVE_INVALID_ARGUMENT;
  }
  return handle->probe((const char *)config_json);
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_last_error_message(
    doctor_native_library_t *handle, char *buffer, int32_t buffer_len) {
  if (!doctor_context_is_open(handle)) {
    return doctor_invalid_handle(buffer, buffer_len);
  }
  if (!doctor_output_buffer_is_valid(buffer, buffer_len)) {
    return DOCTOR_NATIVE_INVALID_ARGUMENT;
  }
  return handle->last_error(buffer, buffer_len);
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_runtime_create_json(
    doctor_native_library_t *handle, moonbit_bytes_t config_json,
    int64_t *out_runtime) {
  if (!doctor_context_is_open(handle)) {
    return DOCTOR_NATIVE_INVALID_HANDLE;
  }
  if (config_json == NULL || out_runtime == NULL) {
    return DOCTOR_NATIVE_INVALID_ARGUMENT;
  }
  return handle->create((const char *)config_json, out_runtime);
}

MOONBIT_FFI_EXPORT int32_t proton_doctor_native_runtime_destroy(
    doctor_native_library_t *handle, int64_t runtime) {
  if (!doctor_context_is_open(handle)) {
    return DOCTOR_NATIVE_INVALID_HANDLE;
  }
  return handle->destroy(runtime);
}
