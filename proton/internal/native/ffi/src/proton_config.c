#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "proton_config.h"

#include "proton_internal.h"

#include <ctype.h>
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

#define PROTON_MAX_PATH_BYTES 4096

#ifdef __APPLE__
static bool proton_macos_current_executable_path(char *out, size_t out_len);
static bool proton_config_macos_bundle_contents_path(
    const char *executable_path, char *out, size_t out_len);
#endif

static bool proton_path_is_absolute(const char *path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
#ifdef _WIN32
  bool drive_absolute =
      ((path[0] >= 'A' && path[0] <= 'Z') ||
       (path[0] >= 'a' && path[0] <= 'z')) &&
      path[1] == ':' && (path[2] == '/' || path[2] == '\\');
  bool unc_absolute = (path[0] == '/' && path[1] == '/') ||
                      (path[0] == '\\' && path[1] == '\\');
  return drive_absolute || unc_absolute;
#else
  return path[0] == '/';
#endif
}

static bool proton_path_exists(const char *path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
#ifdef _WIN32
  /* Paths are UTF-8; ANSI stat() would mangle non-ASCII locations. */
  wchar_t wide_path[4096];
  struct _stat64 info;
  return MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path,
                             (int)(sizeof(wide_path) /
                                   sizeof(wide_path[0]))) > 0 &&
         _wstat64(wide_path, &info) == 0;
#else
  struct stat info;
  return stat(path, &info) == 0;
#endif
}

static bool proton_dir_exists(const char *path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
#ifdef _WIN32
  wchar_t wide_path[4096];
  struct _stat64 info;
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path,
                          (int)(sizeof(wide_path) /
                                sizeof(wide_path[0]))) <= 0 ||
      _wstat64(wide_path, &info) != 0) {
    return false;
  }
  return (info.st_mode & _S_IFDIR) != 0;
#else
  struct stat info;
  if (stat(path, &info) != 0) {
    return false;
  }
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
  if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          (LPCWSTR)&proton_module_dir, &module)) {
    return false;
  }
  wchar_t wide_path[4096] = {0};
  DWORD wide_written = GetModuleFileNameW(
      module, wide_path, (DWORD)(sizeof(wide_path) / sizeof(wide_path[0])));
  if (wide_written == 0 ||
      wide_written >= sizeof(wide_path) / sizeof(wide_path[0])) {
    return false;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, wide_path, -1, out, (int)out_len,
                          NULL, NULL) <= 0) {
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

bool proton_config_default_runtime_root(char *out, size_t out_len) {
  const char *env_root = getenv("PROTON_RUNTIME_ROOT");
  if (env_root != NULL && env_root[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_root);
    return written > 0 && (size_t)written < out_len;
  }
#ifdef __APPLE__
  char executable_path[PROTON_MAX_PATH_BYTES] = {0};
  char contents_dir[PROTON_MAX_PATH_BYTES] = {0};
  char resources_dir[PROTON_MAX_PATH_BYTES] = {0};
  return proton_macos_current_executable_path(executable_path,
                                               sizeof(executable_path)) &&
         proton_config_macos_bundle_contents_path(
             executable_path, contents_dir, sizeof(contents_dir)) &&
         proton_join_path(resources_dir, sizeof(resources_dir), contents_dir,
                          "Resources") &&
         proton_join_path(out, out_len, resources_dir, "proton");
#elif defined(_WIN32)
  return proton_module_dir(out, out_len);
#else
  (void)out;
  (void)out_len;
  return false;
#endif
}

#ifdef __APPLE__
static bool proton_macos_current_executable_path(char *out, size_t out_len) {
  if (out == NULL || out_len == 0 || out_len > UINT32_MAX) {
    return false;
  }
  uint32_t size = (uint32_t)out_len;
  if (_NSGetExecutablePath(out, &size) != 0) {
    return false;
  }
  char resolved[PROTON_MAX_PATH_BYTES] = {0};
  if (realpath(out, resolved) == NULL) {
    return true;
  }
  int written = snprintf(out, out_len, "%s", resolved);
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_path_has_app_suffix(const char *path) {
  if (path == NULL) {
    return false;
  }
  size_t length = strlen(path);
  return length > 4 && strcmp(path + length - 4, ".app") == 0;
}

static bool proton_config_macos_bundle_contents_path(
    const char *executable_path, char *out, size_t out_len) {
  if (executable_path == NULL || executable_path[0] == '\0' || out == NULL ||
      out_len == 0) {
    return false;
  }
  char macos_dir[PROTON_MAX_PATH_BYTES] = {0};
  int written = snprintf(macos_dir, sizeof(macos_dir), "%s", executable_path);
  if (written < 0 || (size_t)written >= sizeof(macos_dir) ||
      !proton_path_parent(macos_dir) ||
      !proton_path_basename_equals(macos_dir, "MacOS")) {
    return false;
  }
  char contents_dir[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(contents_dir, sizeof(contents_dir), "%s", macos_dir);
  if (written < 0 || (size_t)written >= sizeof(contents_dir) ||
      !proton_path_parent(contents_dir) ||
      !proton_path_basename_equals(contents_dir, "Contents")) {
    return false;
  }
  char app_dir[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(app_dir, sizeof(app_dir), "%s", contents_dir);
  if (written < 0 || (size_t)written >= sizeof(app_dir) ||
      !proton_path_parent(app_dir) || !proton_path_has_app_suffix(app_dir)) {
    return false;
  }
  char app_parent[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(app_parent, sizeof(app_parent), "%s", app_dir);
  if (written < 0 || (size_t)written >= sizeof(app_parent) ||
      !proton_path_parent(app_parent)) {
    return false;
  }
  if (proton_path_basename_equals(app_parent, "Frameworks")) {
    if (!proton_path_parent(app_parent) ||
        !proton_path_basename_equals(app_parent, "Contents")) {
      return false;
    }
    written = snprintf(out, out_len, "%s", app_parent);
  } else {
    written = snprintf(out, out_len, "%s", contents_dir);
  }
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_config_macos_is_helper_executable(
    const char *executable_path) {
  char macos_dir[PROTON_MAX_PATH_BYTES] = {0};
  int written = snprintf(macos_dir, sizeof(macos_dir), "%s", executable_path);
  if (written < 0 || (size_t)written >= sizeof(macos_dir) ||
      !proton_path_parent(macos_dir)) {
    return false;
  }
  char contents_dir[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(contents_dir, sizeof(contents_dir), "%s", macos_dir);
  if (written < 0 || (size_t)written >= sizeof(contents_dir) ||
      !proton_path_parent(contents_dir)) {
    return false;
  }
  char app_dir[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(app_dir, sizeof(app_dir), "%s", contents_dir);
  if (written < 0 || (size_t)written >= sizeof(app_dir) ||
      !proton_path_parent(app_dir)) {
    return false;
  }
  return proton_path_parent(app_dir) &&
         proton_path_basename_equals(app_dir, "Frameworks");
}

bool proton_config_macos_bundle_helper_path(const char *executable_path,
                                            char *out,
                                            size_t out_len) {
  if (executable_path == NULL || executable_path[0] == '\0' || out == NULL ||
      out_len == 0) {
    return false;
  }
  char contents_dir[PROTON_MAX_PATH_BYTES] = {0};
  if (!proton_config_macos_bundle_contents_path(
          executable_path, contents_dir, sizeof(contents_dir))) {
    return false;
  }
  char app_dir[PROTON_MAX_PATH_BYTES] = {0};
  int written = snprintf(app_dir, sizeof(app_dir), "%s", contents_dir);
  if (written < 0 || (size_t)written >= sizeof(app_dir) ||
      !proton_path_parent(app_dir)) {
    return false;
  }
  const char *app_name = strrchr(app_dir, '/');
  app_name = app_name == NULL ? app_dir : app_name + 1;
  size_t app_name_len = strlen(app_name);
  if (!proton_path_has_app_suffix(app_name)) {
    return false;
  }
  size_t product_name_len = app_name_len - 4;
  char helper_name[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(helper_name, sizeof(helper_name), "%.*s Helper",
                     (int)product_name_len, app_name);
  if (written < 0 || (size_t)written >= sizeof(helper_name)) {
    return false;
  }
  char frameworks_dir[PROTON_MAX_PATH_BYTES] = {0};
  char helper_bundle_name[PROTON_MAX_PATH_BYTES] = {0};
  char helper_app[PROTON_MAX_PATH_BYTES] = {0};
  char helper_contents[PROTON_MAX_PATH_BYTES] = {0};
  char helper_macos[PROTON_MAX_PATH_BYTES] = {0};
  written = snprintf(helper_bundle_name, sizeof(helper_bundle_name), "%s.app",
                     helper_name);
  if (written < 0 || (size_t)written >= sizeof(helper_bundle_name) ||
      !proton_join_path(frameworks_dir, sizeof(frameworks_dir), contents_dir,
                        "Frameworks") ||
      !proton_join_path(helper_app, sizeof(helper_app), frameworks_dir,
                        helper_bundle_name) ||
      !proton_join_path(helper_contents, sizeof(helper_contents), helper_app,
                        "Contents") ||
      !proton_join_path(helper_macos, sizeof(helper_macos), helper_contents,
                        "MacOS") ||
      !proton_join_path(out, out_len, helper_macos, helper_name)) {
    return false;
  }
  return true;
}
#endif

bool proton_config_default_helper_path(char *out, size_t out_len) {
  const char *env_helper = getenv("PROTON_HELPER_PATH");
  if (env_helper != NULL && env_helper[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_helper);
    return written > 0 && (size_t)written < out_len;
  }
#ifdef __APPLE__
  char executable_path[PROTON_MAX_PATH_BYTES] = {0};
  if (proton_macos_current_executable_path(executable_path,
                                           sizeof(executable_path))) {
    if (proton_config_macos_is_helper_executable(executable_path)) {
      int written = snprintf(out, out_len, "%s", executable_path);
      return written >= 0 && (size_t)written < out_len;
    }
    if (proton_config_macos_bundle_helper_path(executable_path, out, out_len) &&
        proton_path_exists(out)) {
      return true;
    }
  }
#endif
#ifdef _WIN32
  char executable_dir[PROTON_MAX_PATH_BYTES] = {0};
  return proton_module_dir(executable_dir, sizeof(executable_dir)) &&
         proton_join_path(out, out_len, executable_dir, "cef_process.exe");
#else
  return false;
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

static bool proton_copy_runtime_path(char *out, size_t out_len,
                                     const char *value) {
  if (out == NULL || out_len == 0 || value == NULL || value[0] == '\0') {
    return false;
  }
  int written = snprintf(out, out_len, "%s", value);
  return written >= 0 && (size_t)written < out_len;
}

int32_t proton_config_prepare_runtime(
    int32_t use_bundled, const char *runtime_root, const char *helper_path,
    const char *resources_dir, const char *locales_dir, const char *cache_dir,
    const char *locale, const char *accept_languages,
    const char *dialog_ok_label, const char *dialog_cancel_label,
    int32_t remote_debugging_port, int32_t headless,
    int32_t persist_session_cookies,
    proton_engine_runtime_config_t *out_config) {
  if (out_config == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config output is required");
  }
  if (remote_debugging_port != PROTON_REMOTE_DEBUGGING_EPHEMERAL &&
      remote_debugging_port != PROTON_REMOTE_DEBUGGING_DISABLED &&
      (remote_debugging_port < 1024 || remote_debugging_port > 65535)) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "runtime remote debugging must be disabled, ephemeral, or use a port "
        "between 1024 and 65535");
  }
  if (cache_dir != NULL && cache_dir[0] != '\0' &&
      !proton_path_is_absolute(cache_dir)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime cache_dir must be an absolute path");
  }

  proton_engine_runtime_config_t config;
  memset(&config, 0, sizeof(config));
  if (!proton_copy_runtime_path(config.runtime_root,
                                sizeof(config.runtime_root), runtime_root) &&
      !(use_bundled && proton_config_default_runtime_root(
                            config.runtime_root,
                            sizeof(config.runtime_root)))) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config requires runtime_root");
  }
  if (!proton_copy_runtime_path(config.helper_path,
                                sizeof(config.helper_path), helper_path) &&
      !(use_bundled && proton_config_default_helper_path(
                            config.helper_path,
                            sizeof(config.helper_path)))) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config requires helper_path");
  }
  if (!proton_copy_runtime_path(config.resources_dir,
                                sizeof(config.resources_dir), resources_dir) &&
      !proton_join_path(config.resources_dir, sizeof(config.resources_dir),
                        config.runtime_root, "Resources")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime resources_dir is too long");
  }
  if (!proton_copy_runtime_path(config.locales_dir,
                                sizeof(config.locales_dir), locales_dir) &&
      !proton_join_path(config.locales_dir, sizeof(config.locales_dir),
                        config.resources_dir, "locales")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime locales_dir is too long");
  }
#ifdef __APPLE__
  if (!proton_dir_exists(config.locales_dir)) {
    config.locales_dir[0] = '\0';
  }
#endif
#ifdef __APPLE__
  char frameworks_dir[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  if (!proton_join_path(frameworks_dir, sizeof(frameworks_dir),
                        config.runtime_root, "Frameworks") ||
      !proton_join_path(config.framework_dir, sizeof(config.framework_dir),
                        frameworks_dir,
                        "Chromium Embedded Framework.framework")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime framework path is too long");
  }
#endif
  if (cache_dir != NULL && cache_dir[0] != '\0' &&
      !proton_copy_runtime_path(config.cache_dir, sizeof(config.cache_dir),
                                cache_dir)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime cache_dir is too long");
  }
  if (locale != NULL && locale[0] != '\0' &&
      !proton_copy_runtime_path(config.locale, sizeof(config.locale), locale)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime locale is too long");
  }
  if (accept_languages != NULL && accept_languages[0] != '\0' &&
      !proton_copy_runtime_path(config.accept_languages,
                                sizeof(config.accept_languages),
                                accept_languages)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime accept_languages is too long");
  }
  if (dialog_ok_label != NULL && dialog_ok_label[0] != '\0' &&
      !proton_copy_runtime_path(config.dialog_ok_label,
                                sizeof(config.dialog_ok_label),
                                dialog_ok_label)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime dialog OK label is too long");
  }
  if (dialog_cancel_label != NULL && dialog_cancel_label[0] != '\0' &&
      !proton_copy_runtime_path(config.dialog_cancel_label,
                                sizeof(config.dialog_cancel_label),
                                dialog_cancel_label)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime dialog cancel label is too long");
  }
  config.remote_debugging_port = remote_debugging_port;
  config.headless = headless != 0;
  config.persist_session_cookies =
      config.cache_dir[0] != '\0' && persist_session_cookies != 0;
  *out_config = config;
  return PROTON_OK;
}

int32_t proton_config_probe_runtime(
    const proton_engine_runtime_config_t *config) {
  if (config == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime config is required");
  }
  char engine_lib[PROTON_MAX_PATH_BYTES] = {0};
  char icu_data[PROTON_MAX_PATH_BYTES] = {0};
  int32_t status = proton_find_engine_library(
      config->runtime_root, engine_lib, sizeof(engine_lib));
  if (status != PROTON_OK) {
    return status;
  }
  if (!proton_join_path(icu_data, sizeof(icu_data), config->resources_dir,
                        "icudtl.dat")) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime icu data path is too long");
  }

  status = proton_require_file(engine_lib, "runtime engine library");
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_file(config->helper_path,
                               "runtime helper executable");
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_dir(config->resources_dir, "runtime resources");
  if (status != PROTON_OK) {
    return status;
  }
#ifndef __APPLE__
  status = proton_require_dir(config->locales_dir, "runtime locales");
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

static bool proton_copy_config_text(char *out, size_t out_len,
                                    const char *value) {
  if (out == NULL || out_len == 0 || value == NULL) {
    return false;
  }
  int written = snprintf(out, out_len, "%s", value);
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_browser_policy_mode_valid(int32_t mode) {
  return mode >= PROTON_BROWSER_POLICY_ALLOW &&
         mode <= PROTON_BROWSER_POLICY_ASK;
}

int32_t proton_config_prepare_window(
    const char *title, int32_t width, int32_t height, const char *initial_url,
    int32_t size_hint, int32_t titlebar_overlay, int32_t theme_preference,
    int32_t navigation_policy,
    const char *titlebar_minimize_label, const char *titlebar_maximize_label,
    const char *titlebar_restore_label, const char *titlebar_close_label,
    int32_t new_window_policy, int32_t download_policy,
    int32_t certificate_policy, int32_t media_policy, int32_t devtools,
    proton_bridge_config_t *bridge_config,
    proton_engine_window_config_t *out_config) {
  if (out_config == NULL || title == NULL || initial_url == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window config is required");
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window width and height must be positive");
  }
  if (size_hint < 0 || size_hint > 3) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window size hint is invalid");
  }
  if (theme_preference < PROTON_WINDOW_THEME_PREFERENCE_SYSTEM ||
      theme_preference > PROTON_WINDOW_THEME_PREFERENCE_DARK) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window theme is invalid");
  }
  if (!proton_browser_policy_mode_valid(navigation_policy) ||
      !proton_browser_policy_mode_valid(new_window_policy) ||
      !proton_browser_policy_mode_valid(download_policy) ||
      !proton_browser_policy_mode_valid(certificate_policy) ||
      !proton_browser_policy_mode_valid(media_policy) ||
      new_window_policy == PROTON_BROWSER_POLICY_ALLOW ||
      certificate_policy == PROTON_BROWSER_POLICY_ALLOW ||
      media_policy == PROTON_BROWSER_POLICY_ALLOW) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window browser policy is invalid");
  }
  proton_engine_window_config_t config;
  memset(&config, 0, sizeof(config));
  if (!proton_copy_config_text(config.title, sizeof(config.title), title) ||
      !proton_copy_config_text(config.initial_url,
                               sizeof(config.initial_url), initial_url)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window title or initial_url is too long");
  }
  config.width = width;
  config.height = height;
  config.size_hint = size_hint;
  config.titlebar_overlay = titlebar_overlay != 0;
  config.theme_preference =
      (proton_window_theme_preference_t)theme_preference;
  if ((titlebar_minimize_label != NULL && titlebar_minimize_label[0] != '\0' &&
       !proton_copy_config_text(config.titlebar_minimize_label,
                                sizeof(config.titlebar_minimize_label),
                                titlebar_minimize_label)) ||
      (titlebar_maximize_label != NULL && titlebar_maximize_label[0] != '\0' &&
       !proton_copy_config_text(config.titlebar_maximize_label,
                                sizeof(config.titlebar_maximize_label),
                                titlebar_maximize_label)) ||
      (titlebar_restore_label != NULL && titlebar_restore_label[0] != '\0' &&
       !proton_copy_config_text(config.titlebar_restore_label,
                                sizeof(config.titlebar_restore_label),
                                titlebar_restore_label)) ||
      (titlebar_close_label != NULL && titlebar_close_label[0] != '\0' &&
       !proton_copy_config_text(config.titlebar_close_label,
                                sizeof(config.titlebar_close_label),
                                titlebar_close_label))) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window titlebar label is too long");
  }
  if (config.titlebar_overlay &&
      (config.titlebar_minimize_label[0] == '\0' ||
       config.titlebar_maximize_label[0] == '\0' ||
       config.titlebar_restore_label[0] == '\0' ||
       config.titlebar_close_label[0] == '\0')) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "window titlebar overlay requires framework control labels");
  }
  config.browser_policy.navigation =
      (proton_browser_policy_mode_t)navigation_policy;
  config.browser_policy.new_window =
      (proton_browser_policy_mode_t)new_window_policy;
  config.browser_policy.download =
      (proton_browser_policy_mode_t)download_policy;
  config.browser_policy.certificate =
      (proton_browser_policy_mode_t)certificate_policy;
  config.browser_policy.media = (proton_browser_policy_mode_t)media_policy;
  config.browser_policy.devtools = devtools != 0;
  config.bridge_config = bridge_config;
  config.max_bridge_payload_bytes =
      proton_bridge_config_max_payload_bytes(bridge_config);
  *out_config = config;
  return PROTON_OK;
}

bool proton_parse_color_argb(const char *text, uint32_t *out_color) {
  if (text == NULL || text[0] == '\0') {
    return false;
  }
  if (text[0] != '#') {
    return false;
  }
  size_t len = strlen(text);
  if (len != 7 && len != 9) {
    return false;
  }
  for (size_t index = 1; index < len; index++) {
    if (!isxdigit((unsigned char)text[index])) {
      return false;
    }
  }
  unsigned long value = strtoul(text + 1, NULL, 16);
  if (len == 7) {
    value |= 0xFF000000UL;
  }
  *out_color = (uint32_t)value;
  return true;
}

int32_t proton_config_prepare_view(
    int32_t x, int32_t y, int32_t width, int32_t height, int32_t visible,
    int32_t z_order, const char *initial_url, const char *background_color,
    proton_engine_view_config_t *out_config) {
  if (out_config == NULL || initial_url == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "view config is required");
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "view width and height must be positive");
  }
  proton_engine_view_config_t config;
  memset(&config, 0, sizeof(config));
  if (!proton_copy_config_text(config.initial_url,
                               sizeof(config.initial_url), initial_url)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "view initial_url is too long");
  }
  config.x = x;
  config.y = y;
  config.width = width;
  config.height = height;
  config.visible = visible != 0;
  config.z_order = z_order;
  if (background_color != NULL && background_color[0] != '\0') {
    if (!proton_parse_color_argb(background_color,
                                 &config.background_color)) {
      return proton_set_error(
          PROTON_ERR_INVALID_ARGUMENT,
          "view background_color must be #RRGGBB or #AARRGGBB");
    }
    config.has_background_color = 1;
  }
  *out_config = config;
  return PROTON_OK;
}
