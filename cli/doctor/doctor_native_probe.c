#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
typedef HMODULE doctor_library_t;
#define doctor_open(path) LoadLibraryA(path)
#define doctor_symbol(lib, name) GetProcAddress(lib, name)
#define doctor_close(lib) FreeLibrary(lib)
static const char *doctor_load_error(void) { return "LoadLibrary failed"; }
#else
#include <dlfcn.h>
typedef void *doctor_library_t;
#define doctor_open(path) dlopen(path, RTLD_NOW | RTLD_LOCAL)
#define doctor_symbol(lib, name) dlsym(lib, name)
#define doctor_close(lib) dlclose(lib)
static const char *doctor_load_error(void) {
  const char *error = dlerror();
  return error == NULL ? "dlopen failed" : error;
}
#endif

typedef int32_t (*doctor_abi_fn)(void);
typedef int32_t (*doctor_info_fn)(char *, int32_t, int32_t *);
typedef int32_t (*doctor_probe_fn)(const char *);
typedef int32_t (*doctor_error_fn)(char *, int32_t);
typedef int32_t (*doctor_create_fn)(const char *, int64_t *);
typedef int32_t (*doctor_destroy_fn)(int64_t);

static moonbit_bytes_t doctor_copy_text(const char *text) {
  size_t length = strlen(text);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length + 1, 0);
  memcpy(result, text, length + 1);
  return result;
}

static void doctor_json_escape(char *output, size_t capacity, const char *text) {
  size_t written = 0;
  for (const unsigned char *cursor = (const unsigned char *)text;
       *cursor != 0 && written + 2 < capacity; cursor++) {
    unsigned char ch = *cursor;
    if (ch == '\\' || ch == '"') {
      output[written++] = '\\';
      output[written++] = (char)ch;
    } else if (ch == '\n' || ch == '\r' || ch == '\t') {
      output[written++] = ' ';
    } else if (ch >= 0x20) {
      output[written++] = (char)ch;
    }
  }
  output[written] = 0;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_doctor_native_probe(
    moonbit_bytes_t library_path, moonbit_bytes_t config_json) {
  char result[4096] = {0};
  doctor_library_t library = doctor_open((const char *)library_path);
  if (library == NULL) {
    char escaped[2048] = {0};
    doctor_json_escape(escaped, sizeof(escaped), doctor_load_error());
    snprintf(result, sizeof(result), "{\"load_error\":\"%s\"}", escaped);
    return doctor_copy_text(result);
  }

  doctor_abi_fn abi = (doctor_abi_fn)doctor_symbol(library, "proton_abi_version");
  doctor_info_fn info =
      (doctor_info_fn)doctor_symbol(library, "proton_runtime_info_json");
  doctor_probe_fn probe =
      (doctor_probe_fn)doctor_symbol(library, "proton_runtime_probe_json");
  doctor_error_fn last_error =
      (doctor_error_fn)doctor_symbol(library, "proton_last_error_message");
  doctor_create_fn create =
      (doctor_create_fn)doctor_symbol(library, "proton_runtime_create_json");
  doctor_destroy_fn destroy =
      (doctor_destroy_fn)doctor_symbol(library, "proton_runtime_destroy");
  if (abi == NULL || info == NULL || probe == NULL || last_error == NULL ||
      create == NULL || destroy == NULL) {
    snprintf(result, sizeof(result),
             "{\"symbol_error\":\"required proton ABI symbol is missing\"}");
    doctor_close(library);
    return doctor_copy_text(result);
  }

  char info_json[1024] = {0};
  int32_t required = 0;
  int32_t info_status = info(info_json, (int32_t)sizeof(info_json), &required);
  int32_t probe_status = probe((const char *)config_json);
  char error[1024] = {0};
  if (probe_status < 0) {
    last_error(error, (int32_t)sizeof(error));
  }
  int32_t smoke_status = probe_status;
  if (probe_status >= 0) {
    int64_t runtime = 0;
    smoke_status = create((const char *)config_json, &runtime);
    if (smoke_status >= 0) {
      smoke_status = destroy(runtime);
    }
    if (smoke_status < 0) {
      last_error(error, (int32_t)sizeof(error));
    }
  }
  char escaped_error[2048] = {0};
  doctor_json_escape(escaped_error, sizeof(escaped_error), error);
  if (info_status < 0) {
    snprintf(info_json, sizeof(info_json), "null");
  }
  snprintf(result, sizeof(result),
           "{\"abi_version\":%d,\"info_status\":%d,\"info\":%s,"
           "\"probe_status\":%d,\"smoke_status\":%d,"
           "\"probe_error\":\"%s\"}",
           abi(), info_status, info_json, probe_status, smoke_status,
           escaped_error);
  doctor_close(library);
  return doctor_copy_text(result);
}
