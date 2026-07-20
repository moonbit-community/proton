#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "proton_config.h"

#include "proton_internal.h"
#include "proton_json.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__) || defined(__linux__)
#include <dlfcn.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#endif

#ifdef _WIN32
#define PROTON_PATH_SEPARATOR "\\"
#else
#define PROTON_PATH_SEPARATOR "/"
#endif

#define PROTON_MAX_BRIDGE_BYTES 1048576
#define PROTON_MAX_BRIDGE_CONFIG_BYTES PROTON_MAX_BRIDGE_BYTES
#define PROTON_MAX_BRIDGE_OPS 256
#define PROTON_MAX_BRIDGE_DEV_ORIGINS 16
#define PROTON_MAX_BRIDGE_OP_NAME_BYTES 128
#define PROTON_MAX_MENU_CONFIG_BYTES 65536
#define PROTON_MAX_PATH_BYTES 4096

static bool proton_json_key_allowed(const char *key,
                                    const char *const *allowed_keys,
                                    size_t allowed_key_count) {
  for (size_t i = 0; i < allowed_key_count; i++) {
    if (strcmp(key, allowed_keys[i]) == 0) {
      return true;
    }
  }
  return false;
}

typedef struct {
  const proton_json_doc_t *doc;
  const char *config_name;
  const char *const *allowed_keys;
  size_t allowed_key_count;
  bool has_abi_version;
  int32_t status;
} proton_abi_validation_t;

static bool proton_validate_abi_field_type(const proton_json_doc_t *doc,
                                           const char *config_name,
                                           const char *key,
                                           proton_json_value_t value) {
  char text[PROTON_MAX_PATH_BYTES];
  int32_t integer = 0;
  bool boolean = false;
  bool valid = true;
  if (strcmp(key, "abi_version") == 0) {
    return true;
  }
  if (strcmp(config_name, "runtime") == 0) {
    if (strcmp(key, "use_bundled") == 0) {
      valid = proton_json_read_bool(doc, value, &boolean);
    } else if (strcmp(key, "remote_debugging_port") == 0) {
      valid = proton_json_read_int32(doc, value, &integer) && integer >= 0 &&
              integer <= 65535;
    } else if (strcmp(key, "runtime_root") == 0 ||
               strcmp(key, "helper_path") == 0 ||
               strcmp(key, "subprocess_path") == 0 ||
               strcmp(key, "resources_dir") == 0 ||
               strcmp(key, "locales_dir") == 0 ||
               strcmp(key, "cache_dir") == 0) {
      valid = proton_json_read_string(doc, value, text, sizeof(text));
    }
  } else if (strcmp(config_name, "window") == 0) {
    if (strcmp(key, "width") == 0 || strcmp(key, "height") == 0) {
      valid = proton_json_read_int32(doc, value, &integer);
    } else if (strcmp(key, "title") == 0 ||
               strcmp(key, "initial_url") == 0) {
      valid = proton_json_read_string(doc, value, text, sizeof(text));
    }
  } else if (strcmp(config_name, "bridge") == 0) {
    if (strcmp(key, "namespace") == 0) {
      valid = proton_json_read_string(doc, value, text, sizeof(text));
    } else if (strcmp(key, "dev_bootstrap_script") == 0) {
      char *script = proton_json_copy_string(doc, value);
      valid = script != NULL;
      free(script);
    } else if (strcmp(key, "max_payload_bytes") == 0 ||
               strcmp(key, "request_timeout_ms") == 0) {
      valid = proton_json_read_int32(doc, value, &integer) && integer > 0;
    } else if (strcmp(key, "origin_policy") == 0) {
      valid = proton_json_is_object(doc, value);
    } else if (strcmp(key, "ops") == 0) {
      valid = proton_json_is_array(doc, value);
    }
  } else if (strcmp(config_name, "bridge response") == 0) {
    if (strcmp(key, "request_id") == 0) {
      int64_t request_id = 0;
      valid = proton_json_read_int64_string_or_number(doc, value, &request_id);
    } else if (strcmp(key, "ok") == 0) {
      valid = proton_json_read_bool(doc, value, &boolean);
    }
  }
  if (!valid) {
    char message[192];
    snprintf(message, sizeof(message), "%s field has invalid type or range: %s",
             config_name, key);
    proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  return valid;
}

static bool proton_validate_abi_field(const char *key,
                                      proton_json_value_t value,
                                      void *user_data) {
  proton_abi_validation_t *validation = (proton_abi_validation_t *)user_data;
  if (!proton_json_key_allowed(key, validation->allowed_keys,
                               validation->allowed_key_count)) {
    char message[192];
    snprintf(message, sizeof(message), "%s config contains unknown field: %s",
             validation->config_name, key);
    validation->status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
    return false;
  }
  if (strcmp(key, "abi_version") == 0) {
    int32_t abi_version = 0;
    validation->has_abi_version = true;
    if (!proton_json_read_int32(validation->doc, value, &abi_version) ||
        abi_version != PROTON_ABI_VERSION) {
      char message[160];
      snprintf(message, sizeof(message),
               "%s config abi_version must be set to %d",
               validation->config_name, PROTON_ABI_VERSION);
      validation->status =
          proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
      return false;
    }
  }
  if (!proton_validate_abi_field_type(validation->doc,
                                      validation->config_name, key, value)) {
    validation->status = PROTON_ERR_INVALID_ARGUMENT;
    return false;
  }
  return true;
}

static int32_t proton_validate_abi_config(
    const char *config_json,
    const char *config_name,
    const char *const *allowed_keys,
    size_t allowed_key_count) {
  if (config_json == NULL) {
    char message[128];
    snprintf(message, sizeof(message), "%s config_json is required",
             config_name);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }

  proton_json_doc_t doc;
  proton_json_value_t root;
  if (!proton_json_parse(&doc, config_json)) {
    if (doc.trailing_comma) {
      char message[160];
      snprintf(message, sizeof(message), "%s config has a trailing comma",
               config_name);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
    }
    char message[160];
    snprintf(message, sizeof(message), "%s config must be valid JSON",
             config_name);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  if (!proton_json_root_object(&doc, &root)) {
    proton_json_dispose(&doc);
    char message[160];
    snprintf(message, sizeof(message), "%s config must be a JSON object",
             config_name);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }

  proton_abi_validation_t validation = {
      &doc, config_name, allowed_keys, allowed_key_count, false, PROTON_OK};
  bool valid = proton_json_object_each(&doc, root, proton_validate_abi_field,
                                       &validation);
  if (!valid && validation.status == PROTON_OK) {
    char message[160];
    snprintf(message, sizeof(message), "%s config has an invalid field",
             config_name);
    validation.status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  if (validation.status == PROTON_OK && !validation.has_abi_version) {
    char message[160];
    snprintf(message, sizeof(message),
             "%s config must contain \"abi_version\": %d", config_name,
             PROTON_ABI_VERSION);
    validation.status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  proton_json_dispose(&doc);
  return validation.status;
}

static bool proton_parse_json_int_field(const char *config_json,
                                        const char *field_name,
                                        int32_t *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_int32(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok;
}

static bool proton_parse_json_bool_field(const char *config_json,
                                         const char *field_name,
                                         bool *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_bool(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok;
}

static bool proton_parse_json_string_field(const char *config_json,
                                           const char *field_name,
                                           char *out_value,
                                           size_t out_value_len) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_string(&doc, value, out_value, out_value_len);
  proton_json_dispose(&doc);
  return ok;
}

static const char *const proton_runtime_config_keys[] = {
    "abi_version",
    "runtime_root",
    "helper_path",
    "subprocess_path",
    "use_bundled",
    "resources_dir",
    "locales_dir",
    "cache_dir",
    "remote_debugging_port",
};

static const char *const proton_window_config_keys[] = {
    "abi_version",
    "title",
    "width",
    "height",
    "initial_url",
};

static const char *const proton_bridge_config_keys[] = {
    "abi_version",
    "namespace",
    "origin_policy",
    "ops",
    "max_payload_bytes",
    "request_timeout_ms",
    "dev_bootstrap_script",
};

static const char *const proton_bridge_response_keys[] = {
    "abi_version",
    "request_id",
    "ok",
    "payload",
    "error",
};

static const char *const proton_menu_config_keys[] = {
    "abi_version",
    "menus",
};

static bool proton_path_exists(const char *path) {
  struct stat info;
  return path != NULL && path[0] != '\0' && stat(path, &info) == 0;
}

static bool proton_dir_exists(const char *path) {
  struct stat info;
  if (path == NULL || path[0] == '\0' || stat(path, &info) != 0) {
    return false;
  }
#ifdef _WIN32
  return (info.st_mode & _S_IFDIR) != 0;
#else
  return S_ISDIR(info.st_mode);
#endif
}

static bool proton_join_path(char *out,
                             size_t out_len,
                             const char *base,
                             const char *child) {
  if (out == NULL || out_len == 0 || base == NULL || child == NULL ||
      base[0] == '\0' || child[0] == '\0') {
    return false;
  }
  size_t base_len = strlen(base);
  const char *separator = "";
  if (base_len > 0 && base[base_len - 1] != '/' && base[base_len - 1] != '\\') {
    separator = PROTON_PATH_SEPARATOR;
  }
  int written = snprintf(out, out_len, "%s%s%s", base, separator, child);
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_path_parent(char *path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
  size_t len = strlen(path);
  while (len > 0 && (path[len - 1] == '/' || path[len - 1] == '\\')) {
    path[--len] = '\0';
  }
  while (len > 0 && path[len - 1] != '/' && path[len - 1] != '\\') {
    len--;
  }
  if (len == 0) {
    return false;
  }
  path[len - 1] = '\0';
  return path[0] != '\0';
}

static bool proton_path_basename_equals(const char *path, const char *name) {
  if (path == NULL || name == NULL) {
    return false;
  }
  const char *base = path;
  for (const char *cursor = path; *cursor != '\0'; cursor++) {
    if (*cursor == '/' || *cursor == '\\') {
      base = cursor + 1;
    }
  }
#ifdef _WIN32
  return _stricmp(base, name) == 0;
#else
  return strcmp(base, name) == 0;
#endif
}

static bool proton_module_dir(char *out, size_t out_len) {
#ifdef _WIN32
  if (out == NULL || out_len == 0) {
    return false;
  }
  HMODULE module = NULL;
  if (!GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          (LPCSTR)&proton_module_dir, &module)) {
    return false;
  }
  DWORD written = GetModuleFileNameA(module, out, (DWORD)out_len);
  if (written == 0 || written >= out_len) {
    return false;
  }
  return proton_path_parent(out);
#elif defined(__APPLE__) || defined(__linux__)
  if (out == NULL || out_len == 0) {
    return false;
  }
  Dl_info info;
  if (dladdr((const void *)&proton_module_dir, &info) == 0 ||
      info.dli_fname == NULL || info.dli_fname[0] == '\0') {
    return false;
  }
  int written = snprintf(out, out_len, "%s", info.dli_fname);
  if (written < 0 || (size_t)written >= out_len) {
    return false;
  }
  return proton_path_parent(out);
#else
  (void)out;
  (void)out_len;
  return false;
#endif
}

static bool proton_default_runtime_root(char *out, size_t out_len) {
  const char *env_root = getenv("PROTON_RUNTIME_ROOT");
  if (env_root == NULL || env_root[0] == '\0') {
    env_root = getenv("PROTON_NATIVE_DIST");
  }
  if (env_root != NULL && env_root[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_root);
    return written > 0 && (size_t)written < out_len;
  }
  if (!proton_module_dir(out, out_len)) {
    return false;
  }
  if (proton_path_basename_equals(out, "bin")
#ifndef _WIN32
      || proton_path_basename_equals(out, "lib")
#endif
  ) {
    return proton_path_parent(out);
  }
  return true;
}

static bool proton_default_helper_path(char *out, size_t out_len) {
  const char *env_helper = getenv("PROTON_HELPER_PATH");
  if (env_helper != NULL && env_helper[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_helper);
    return written > 0 && (size_t)written < out_len;
  }
  char runtime_root[PROTON_MAX_PATH_BYTES] = {0};
  char bin_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (!proton_default_runtime_root(runtime_root, sizeof(runtime_root)) ||
      !proton_join_path(bin_dir, sizeof(bin_dir), runtime_root, "bin")) {
    return false;
  }
#ifdef _WIN32
  if (proton_join_path(out, out_len, runtime_root, "cef_process.exe") &&
      proton_path_exists(out)) {
    return true;
  }
  return proton_join_path(out, out_len, bin_dir, "cef_process.exe");
#else
  return proton_join_path(out, out_len, bin_dir, "cef_process");
#endif
}

static int32_t proton_require_file(const char *path, const char *label) {
  if (!proton_path_exists(path)) {
    char message[512];
    snprintf(message, sizeof(message), "%s is missing: %s", label,
             path != NULL ? path : "");
    return proton_set_error(PROTON_ERR_ENGINE, message);
  }
  return PROTON_OK;
}

static int32_t proton_require_dir(const char *path, const char *label) {
  if (!proton_dir_exists(path)) {
    char message[512];
    snprintf(message, sizeof(message), "%s directory is missing: %s", label,
             path != NULL ? path : "");
    return proton_set_error(PROTON_ERR_ENGINE, message);
  }
  return PROTON_OK;
}

static int32_t proton_find_engine_library(const char *runtime_root,
                                          char *engine_lib,
                                          size_t engine_lib_len) {
#ifdef _WIN32
  char release_dir[PROTON_MAX_PATH_BYTES] = {0};
  char bin_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (proton_join_path(release_dir, sizeof(release_dir), runtime_root,
                       "Release") &&
      proton_join_path(engine_lib, engine_lib_len, release_dir,
                       "libcef.dll") &&
      proton_path_exists(engine_lib)) {
    return PROTON_OK;
  }
  if (proton_join_path(bin_dir, sizeof(bin_dir), runtime_root, "bin") &&
      proton_join_path(engine_lib, engine_lib_len, bin_dir, "libcef.dll") &&
      proton_path_exists(engine_lib)) {
    return PROTON_OK;
  }
  if (proton_join_path(engine_lib, engine_lib_len, runtime_root,
                       "libcef.dll")) {
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                          "runtime engine library path is too long");
#elif defined(__APPLE__)
  char framework_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (proton_join_path(framework_dir, sizeof(framework_dir), runtime_root,
                       "Chromium Embedded Framework.framework") &&
      proton_join_path(engine_lib, engine_lib_len, framework_dir,
                       "Chromium Embedded Framework") &&
      proton_path_exists(engine_lib)) {
    return PROTON_OK;
  }
  char frameworks_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (proton_join_path(frameworks_dir, sizeof(frameworks_dir), runtime_root,
                       "Frameworks") &&
      proton_join_path(framework_dir, sizeof(framework_dir), frameworks_dir,
                       "Chromium Embedded Framework.framework") &&
      proton_join_path(engine_lib, engine_lib_len, framework_dir,
                       "Chromium Embedded Framework")) {
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                          "runtime framework path is too long");
#else
  char bin_dir[PROTON_MAX_PATH_BYTES] = {0};
  char lib_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (proton_join_path(engine_lib, engine_lib_len, runtime_root,
                       "libcef.so") &&
      proton_path_exists(engine_lib)) {
    return PROTON_OK;
  }
  if (proton_join_path(bin_dir, sizeof(bin_dir), runtime_root, "bin") &&
      proton_join_path(engine_lib, engine_lib_len, bin_dir, "libcef.so") &&
      proton_path_exists(engine_lib)) {
    return PROTON_OK;
  }
  if (proton_join_path(lib_dir, sizeof(lib_dir), runtime_root, "lib") &&
      proton_join_path(engine_lib, engine_lib_len, lib_dir, "libcef.so")) {
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                          "runtime engine library path is too long");
#endif
}

int32_t proton_config_probe_runtime_layout(const char *config_json) {
  char runtime_root[PROTON_MAX_PATH_BYTES] = {0};
  char helper_path[PROTON_MAX_PATH_BYTES] = {0};
  char resources_dir[PROTON_MAX_PATH_BYTES] = {0};
  char locales_dir[PROTON_MAX_PATH_BYTES] = {0};
  char engine_lib[PROTON_MAX_PATH_BYTES] = {0};
  char icu_data[PROTON_MAX_PATH_BYTES] = {0};

  bool use_bundled = false;
  proton_parse_json_bool_field(config_json, "use_bundled", &use_bundled);

  if (!proton_parse_json_string_field(config_json, "runtime_root",
                                      runtime_root, sizeof(runtime_root)) &&
      !(use_bundled &&
        proton_default_runtime_root(runtime_root, sizeof(runtime_root)))) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config requires runtime_root");
  }
  if (!proton_parse_json_string_field(config_json, "helper_path", helper_path,
                                      sizeof(helper_path)) &&
      !proton_parse_json_string_field(config_json, "subprocess_path",
                                      helper_path, sizeof(helper_path)) &&
      !(use_bundled &&
        proton_default_helper_path(helper_path, sizeof(helper_path)))) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config requires helper_path");
  }

  if (!proton_parse_json_string_field(config_json, "resources_dir",
                                      resources_dir, sizeof(resources_dir)) &&
      !proton_join_path(resources_dir, sizeof(resources_dir), runtime_root,
                        "Resources")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime resources_dir is too long");
  }
  if (!proton_parse_json_string_field(config_json, "locales_dir", locales_dir,
                                      sizeof(locales_dir)) &&
      !proton_join_path(locales_dir, sizeof(locales_dir), resources_dir,
                        "locales")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime locales_dir is too long");
  }

  int32_t status =
      proton_find_engine_library(runtime_root, engine_lib, sizeof(engine_lib));
  if (status != PROTON_OK) {
    return status;
  }
  if (!proton_join_path(icu_data, sizeof(icu_data), resources_dir,
                        "icudtl.dat")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime icu data path is too long");
  }

  status = proton_require_file(engine_lib, "runtime engine library");
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_file(helper_path, "runtime helper executable");
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_dir(resources_dir, "runtime resources");
  if (status != PROTON_OK) {
    return status;
  }
#ifndef __APPLE__
  status = proton_require_dir(locales_dir, "runtime locales");
  if (status != PROTON_OK) {
    return status;
  }
#endif
  status = proton_require_file(icu_data, "runtime icu data");
  if (status != PROTON_OK) {
    return status;
  }
  return PROTON_OK;
}

bool proton_config_runtime_requests_engine(const char *config_json) {
  char value[PROTON_MAX_PATH_BYTES] = {0};
  bool use_bundled = false;
  return proton_parse_json_string_field(config_json, "runtime_root", value,
                                        sizeof(value)) ||
         proton_parse_json_string_field(config_json, "helper_path", value,
                                        sizeof(value)) ||
         proton_parse_json_string_field(config_json, "subprocess_path", value,
                                        sizeof(value)) ||
         (proton_parse_json_bool_field(config_json, "use_bundled",
                                       &use_bundled) &&
          use_bundled);
}

static int32_t proton_validate_window_config(const char *config_json,
                                             int32_t *out_width,
                                             int32_t *out_height) {
  if (config_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window config_json is required");
  }

  int32_t width = 0;
  int32_t height = 0;
  if (!proton_parse_json_int_field(config_json, "width", &width) ||
      !proton_parse_json_int_field(config_json, "height", &height)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window config requires numeric width and height");
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window width and height must be positive");
  }

  *out_width = width;
  *out_height = height;
  return PROTON_OK;
}

static bool proton_bridge_op_name_valid(const char *name) {
  if (name == NULL || name[0] == '\0') {
    return false;
  }
  for (const char *cursor = name; *cursor != '\0'; cursor++) {
    unsigned char ch = (unsigned char)*cursor;
    if (ch <= 0x20 || ch >= 0x7f) {
      return false;
    }
  }
  return true;
}

typedef struct {
  const proton_json_doc_t *doc;
  bool has_mode;
  bool has_dev_origins;
  char mode[32];
  int32_t status;
} proton_bridge_origin_policy_validation_t;

static bool proton_bridge_dev_origin_valid(const char *origin) {
  const char *authority = NULL;
  if (origin == NULL) {
    return false;
  }
  if (strncmp(origin, "http://", 7) == 0) {
    authority = origin + 7;
  } else if (strncmp(origin, "https://", 8) == 0) {
    authority = origin + 8;
  } else {
    return false;
  }
  if (*authority == '\0') {
    return false;
  }
  for (const char *cursor = authority; *cursor != '\0'; cursor++) {
    unsigned char ch = (unsigned char)*cursor;
    if (ch <= 0x20 || ch >= 0x7f || ch == '/' || ch == '?' || ch == '#' ||
        ch == '@' || ch == '"' || ch == '\\') {
      return false;
    }
  }
  return true;
}

typedef struct {
  const proton_json_doc_t *doc;
  size_t count;
  int32_t status;
} proton_bridge_dev_origins_validation_t;

static bool proton_validate_bridge_dev_origin_item(proton_json_value_t value,
                                                   void *user_data) {
  proton_bridge_dev_origins_validation_t *validation =
      (proton_bridge_dev_origins_validation_t *)user_data;
  if (validation->count >= PROTON_MAX_BRIDGE_DEV_ORIGINS) {
    validation->status = proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "bridge origin_policy.dev_origins array is too large");
    return false;
  }
  char origin[PROTON_MAX_PATH_BYTES];
  if (!proton_json_read_string(validation->doc, value, origin, sizeof(origin)) ||
      !proton_bridge_dev_origin_valid(origin)) {
    validation->status = proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "bridge origin_policy.dev_origins contains invalid origin");
    return false;
  }
  validation->count++;
  return true;
}

static int32_t proton_validate_bridge_dev_origins(
    const proton_json_doc_t *doc,
    proton_json_value_t value,
    size_t *out_count) {
  if (!proton_json_is_array(doc, value)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge origin_policy.dev_origins must be an array");
  }
  proton_bridge_dev_origins_validation_t validation = {doc, 0, PROTON_OK};
  if (!proton_json_array_each(doc, value,
                              proton_validate_bridge_dev_origin_item,
                              &validation) &&
      validation.status == PROTON_OK) {
    validation.status = proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "bridge origin_policy.dev_origins array is malformed");
  }
  if (out_count != NULL) {
    *out_count = validation.count;
  }
  return validation.status;
}

static bool proton_validate_bridge_origin_policy_field(
    const char *key,
    proton_json_value_t value,
    void *user_data) {
  proton_bridge_origin_policy_validation_t *validation =
      (proton_bridge_origin_policy_validation_t *)user_data;
  if (strcmp(key, "mode") == 0) {
    char mode[32];
    if (!proton_json_read_string(validation->doc, value, mode, sizeof(mode)) ||
        (strcmp(mode, "app_only") != 0 &&
         strcmp(mode, "app_and_dev_origins") != 0)) {
      validation->status = proton_set_error(
          PROTON_ERR_INVALID_ARGUMENT,
          "bridge origin_policy.mode must be app_only or app_and_dev_origins");
      return false;
    }
    snprintf(validation->mode, sizeof(validation->mode), "%s", mode);
    validation->has_mode = true;
    return true;
  }
  if (strcmp(key, "dev_origins") == 0) {
    size_t count = 0;
    int32_t status =
        proton_validate_bridge_dev_origins(validation->doc, value, &count);
    if (status != PROTON_OK) {
      validation->status = status;
      return false;
    }
    validation->has_dev_origins = true;
    if (count == 0) {
      validation->status = proton_set_error(
          PROTON_ERR_INVALID_ARGUMENT,
          "bridge origin_policy.dev_origins must not be empty");
      return false;
    }
    return true;
  }
  {
    char message[160];
    snprintf(message, sizeof(message),
             "bridge origin_policy contains unknown field: %s", key);
    validation->status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
    return false;
  }
}

static int32_t proton_validate_bridge_origin_policy(
    const proton_json_doc_t *doc,
    proton_json_value_t value) {
  if (!proton_json_is_object(doc, value)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge origin_policy must be an object");
  }
  proton_bridge_origin_policy_validation_t validation = {
      doc, false, false, "", PROTON_OK};
  if (!proton_json_object_each(doc, value,
                               proton_validate_bridge_origin_policy_field,
                               &validation) &&
      validation.status == PROTON_OK) {
    validation.status = proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT, "bridge origin_policy has an invalid field");
  }
  if (validation.status != PROTON_OK) {
    return validation.status;
  }
  if (!validation.has_mode) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge origin_policy requires mode");
  }
  if (strcmp(validation.mode, "app_only") == 0 &&
      validation.has_dev_origins) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "bridge origin_policy.dev_origins requires app_and_dev_origins mode");
  }
  if (strcmp(validation.mode, "app_and_dev_origins") == 0 &&
      !validation.has_dev_origins) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "bridge origin_policy.app_and_dev_origins requires dev_origins");
  }
  return PROTON_OK;
}

typedef struct {
  const proton_json_doc_t *doc;
  bool has_name;
  int32_t status;
} proton_bridge_op_validation_t;

static bool proton_validate_bridge_op_field(const char *key,
                                            proton_json_value_t value,
                                            void *user_data) {
  proton_bridge_op_validation_t *validation =
      (proton_bridge_op_validation_t *)user_data;
  if (strcmp(key, "name") != 0) {
    char message[160];
    snprintf(message, sizeof(message), "bridge op contains unknown field: %s",
             key);
    validation->status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
    return false;
  }
  char name[PROTON_MAX_BRIDGE_OP_NAME_BYTES];
  if (!proton_json_read_string(validation->doc, value, name, sizeof(name)) ||
      !proton_bridge_op_name_valid(name)) {
    validation->status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge op name is invalid");
    return false;
  }
  validation->has_name = true;
  return true;
}

typedef struct {
  const proton_json_doc_t *doc;
  size_t op_count;
  int32_t status;
} proton_bridge_ops_validation_t;

static bool proton_validate_bridge_ops_item(proton_json_value_t value,
                                            void *user_data) {
  proton_bridge_ops_validation_t *validation =
      (proton_bridge_ops_validation_t *)user_data;
  if (validation->op_count >= PROTON_MAX_BRIDGE_OPS) {
    validation->status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge ops array is too large");
    return false;
  }
  if (!proton_json_is_object(validation->doc, value)) {
    validation->status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge op must be an object");
    return false;
  }
  proton_bridge_op_validation_t op_validation = {
      validation->doc, false, PROTON_OK};
  if (!proton_json_object_each(validation->doc, value,
                               proton_validate_bridge_op_field,
                               &op_validation) &&
      op_validation.status == PROTON_OK) {
    op_validation.status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge op has an invalid field");
  }
  if (op_validation.status != PROTON_OK) {
    validation->status = op_validation.status;
    return false;
  }
  if (!op_validation.has_name) {
    validation->status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge op requires name");
    return false;
  }
  validation->op_count++;
  return true;
}

static int32_t proton_validate_bridge_ops(const proton_json_doc_t *doc,
                                          proton_json_value_t value) {
  if (!proton_json_is_array(doc, value)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge ops must be an array");
  }
  proton_bridge_ops_validation_t validation = {doc, 0, PROTON_OK};
  if (!proton_json_array_each(doc, value, proton_validate_bridge_ops_item,
                              &validation) &&
      validation.status == PROTON_OK) {
    validation.status =
        proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "bridge ops array is malformed");
  }
  return validation.status;
}

int32_t proton_config_validate_bridge(const char *bridge_json) {
  if (bridge_json != NULL && strlen(bridge_json) > PROTON_MAX_BRIDGE_CONFIG_BYTES) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge config is too large");
  }
  int32_t status = proton_validate_abi_config(
      bridge_json, "bridge", proton_bridge_config_keys,
      sizeof(proton_bridge_config_keys) / sizeof(proton_bridge_config_keys[0]));
  if (status != PROTON_OK) {
    return status;
  }

  proton_json_doc_t doc;
  proton_json_value_t root;
  if (!proton_json_parse(&doc, bridge_json) ||
      !proton_json_root_object(&doc, &root)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge config must be a JSON object");
  }

  proton_json_value_t value;
  if (proton_json_object_get(&doc, root, "namespace", &value)) {
    char namespace_value[64];
    if (!proton_json_read_string(&doc, value, namespace_value,
                                 sizeof(namespace_value)) ||
        strcmp(namespace_value, "__MoonBit__") != 0) {
      proton_json_dispose(&doc);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge namespace must be __MoonBit__");
    }
  }

  if (proton_json_object_get(&doc, root, "origin_policy", &value)) {
    status = proton_validate_bridge_origin_policy(&doc, value);
    if (status != PROTON_OK) {
      proton_json_dispose(&doc);
      return status;
    }
  }

  if (proton_json_object_get(&doc, root, "dev_bootstrap_script", &value)) {
    char *script = proton_json_copy_string(&doc, value);
    if (script == NULL) {
      proton_json_dispose(&doc);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge dev_bootstrap_script must be a string");
    }
    free(script);
  }

  if (!proton_json_object_get(&doc, root, "ops", &value)) {
    proton_json_dispose(&doc);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge config requires ops");
  }
  status = proton_validate_bridge_ops(&doc, value);
  if (status != PROTON_OK) {
    proton_json_dispose(&doc);
    return status;
  }

  if (proton_json_object_get(&doc, root, "max_payload_bytes", &value)) {
    int32_t max_payload_bytes = 0;
    if (!proton_json_read_int32(&doc, value, &max_payload_bytes) ||
        max_payload_bytes <= 0 ||
        max_payload_bytes > PROTON_MAX_BRIDGE_BYTES) {
      proton_json_dispose(&doc);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge max_payload_bytes is invalid");
    }
  }

  if (proton_json_object_get(&doc, root, "request_timeout_ms", &value)) {
    int32_t timeout_ms = 0;
    if (!proton_json_read_int32(&doc, value, &timeout_ms) || timeout_ms <= 0) {
      proton_json_dispose(&doc);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge request_timeout_ms is invalid");
    }
  }

  proton_json_dispose(&doc);
  return PROTON_OK;
}

int32_t proton_config_validate_menu(const char *menu_json) {
  if (menu_json != NULL && strlen(menu_json) > PROTON_MAX_MENU_CONFIG_BYTES) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu config is too large");
  }
  int32_t status = proton_validate_abi_config(
      menu_json, "menu", proton_menu_config_keys,
      sizeof(proton_menu_config_keys) / sizeof(proton_menu_config_keys[0]));
  if (status != PROTON_OK) {
    return status;
  }

  proton_json_doc_t doc;
  proton_json_value_t root;
  if (!proton_json_parse(&doc, menu_json) ||
      !proton_json_root_object(&doc, &root)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu config must be a JSON object");
  }

  proton_json_value_t menus;
  if (!proton_json_object_get(&doc, root, "menus", &menus)) {
    proton_json_dispose(&doc);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "menu config requires menus");
  }
  if (!proton_json_is_array(&doc, menus)) {
    status = proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "menu config menus must be an array");
  }
  proton_json_dispose(&doc);
  return status;
}

int32_t proton_config_validate_bridge_response(const char *response_json) {
  int32_t status = proton_validate_abi_config(
      response_json, "bridge response", proton_bridge_response_keys,
      sizeof(proton_bridge_response_keys) /
          sizeof(proton_bridge_response_keys[0]));
  if (status != PROTON_OK) {
    return status;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, response_json) ||
      !proton_json_root_object(&doc, &root)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response must be a JSON object");
  }
  int64_t request_id = 0;
  if (!proton_json_object_get(&doc, root, "request_id", &value) ||
      !proton_json_read_int64_string_or_number(&doc, value, &request_id) ||
      request_id <= 0) {
    proton_json_dispose(&doc);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response requires positive request_id");
  }
  bool ok = false;
  if (!proton_json_object_get(&doc, root, "ok", &value) ||
      !proton_json_read_bool(&doc, value, &ok)) {
    proton_json_dispose(&doc);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response requires boolean ok");
  }
  proton_json_dispose(&doc);
  return PROTON_OK;
}

int32_t proton_config_validate_runtime(const char *config_json) {
  return proton_validate_abi_config(
      config_json, "runtime", proton_runtime_config_keys,
      sizeof(proton_runtime_config_keys) / sizeof(proton_runtime_config_keys[0]));
}

int32_t proton_config_validate_window(const char *config_json,
                                      int32_t *out_width,
                                      int32_t *out_height) {
  int32_t status = proton_validate_abi_config(
      config_json, "window", proton_window_config_keys,
      sizeof(proton_window_config_keys) / sizeof(proton_window_config_keys[0]));
  if (status != PROTON_OK) {
    return status;
  }
  return proton_validate_window_config(config_json, out_width, out_height);
}
