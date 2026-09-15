#include "proton_internal.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#elif !defined(__APPLE__)
#include <gio/gdesktopappinfo.h>
#include <gio/gio.h>
#include <spawn.h>
#include <unistd.h>
extern char **environ;
#endif

#if !defined(__APPLE__)

typedef struct proton_relaunch_plan {
  char *executable;
  char *arguments;
  int32_t arguments_len;
  struct proton_relaunch_plan *next;
} proton_relaunch_plan_t;

static proton_relaunch_plan_t *g_relaunch_head = NULL;
static proton_relaunch_plan_t *g_relaunch_tail = NULL;

static char *proton_app_control_copy(const char *value, size_t length) {
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (length > 0) {
    memcpy(copy, value, length);
  }
  copy[length] = '\0';
  return copy;
}

static int proton_app_control_arguments_valid(const char *arguments,
                                              int32_t arguments_len) {
  if (arguments_len < 0 || (arguments == NULL && arguments_len != 0)) {
    return 0;
  }
  return arguments_len == 0 || arguments[arguments_len - 1] == '\0';
}

#if defined(_WIN32)

static wchar_t *proton_app_control_wide(const char *value) {
  if (value == NULL) {
    return NULL;
  }
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1,
                                   NULL, 0);
  if (length <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)calloc((size_t)length, sizeof(wchar_t));
  if (wide == NULL ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, wide,
                          length) <= 0) {
    free(wide);
    return NULL;
  }
  return wide;
}

static int proton_app_control_append(wchar_t **buffer, size_t *length,
                                     size_t *capacity, const wchar_t *value,
                                     size_t value_len) {
  if (*length + value_len + 1 > *capacity) {
    size_t next = *capacity == 0 ? 64 : *capacity;
    while (next < *length + value_len + 1) {
      next *= 2;
    }
    wchar_t *resized =
        (wchar_t *)realloc(*buffer, next * sizeof(wchar_t));
    if (resized == NULL) {
      return 0;
    }
    *buffer = resized;
    *capacity = next;
  }
  memcpy(*buffer + *length, value, value_len * sizeof(wchar_t));
  *length += value_len;
  (*buffer)[*length] = L'\0';
  return 1;
}

static int proton_app_control_append_quoted(wchar_t **buffer, size_t *length,
                                            size_t *capacity,
                                            const wchar_t *argument) {
  if (!proton_app_control_append(buffer, length, capacity, L"\"", 1)) {
    return 0;
  }
  size_t slashes = 0;
  for (const wchar_t *cursor = argument;; cursor++) {
    if (*cursor == L'\\') {
      slashes++;
      continue;
    }
    size_t copies = slashes;
    if (*cursor == L'\"' || *cursor == L'\0') {
      copies = slashes * 2;
    }
    for (size_t index = 0; index < copies; index++) {
      if (!proton_app_control_append(buffer, length, capacity, L"\\", 1)) {
        return 0;
      }
    }
    slashes = 0;
    if (*cursor == L'\0') {
      break;
    }
    if (*cursor == L'\"' &&
        !proton_app_control_append(buffer, length, capacity, L"\\", 1)) {
      return 0;
    }
    if (!proton_app_control_append(buffer, length, capacity, cursor, 1)) {
      return 0;
    }
  }
  return proton_app_control_append(buffer, length, capacity, L"\"", 1);
}

static wchar_t *proton_app_control_command(const char *executable,
                                           const char *arguments,
                                           int32_t arguments_len,
                                           int include_url) {
  wchar_t *wide_executable = proton_app_control_wide(executable);
  if (wide_executable == NULL) {
    return NULL;
  }
  wchar_t *command = NULL;
  size_t length = 0;
  size_t capacity = 0;
  int ok = proton_app_control_append_quoted(&command, &length, &capacity,
                                            wide_executable);
  free(wide_executable);
  for (int32_t offset = 0; ok && offset < arguments_len;) {
    const char *argument = arguments + offset;
    size_t remaining = (size_t)(arguments_len - offset);
    size_t argument_len = strnlen(argument, remaining);
    if (argument_len == remaining) {
      ok = 0;
      break;
    }
    wchar_t *wide_argument = proton_app_control_wide(argument);
    ok = wide_argument != NULL &&
         proton_app_control_append(&command, &length, &capacity, L" ", 1) &&
         proton_app_control_append_quoted(&command, &length, &capacity,
                                          wide_argument);
    free(wide_argument);
    offset += (int32_t)argument_len + 1;
  }
  if (ok && include_url) {
    ok = proton_app_control_append(&command, &length, &capacity, L" \"%1\"", 5);
  }
  if (!ok) {
    free(command);
    return NULL;
  }
  return command;
}

static int32_t proton_protocol_windows_command(
    const char *scheme, const char *executable, const char *arguments,
    int32_t arguments_len, wchar_t **out_scheme, wchar_t **out_command) {
  *out_scheme = proton_app_control_wide(scheme);
  *out_command = proton_app_control_command(executable, arguments, arguments_len,
                                            1);
  if (*out_scheme == NULL || *out_command == NULL) {
    free(*out_scheme);
    free(*out_command);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to encode protocol registration as UTF-16");
  }
  return PROTON_OK;
}

static wchar_t *proton_protocol_windows_key(const wchar_t *scheme,
                                            const wchar_t *suffix) {
  static const wchar_t prefix[] = L"Software\\Classes\\";
  size_t length = wcslen(prefix) + wcslen(scheme) + wcslen(suffix) + 1;
  wchar_t *key = (wchar_t *)calloc(length, sizeof(wchar_t));
  if (key != NULL) {
    _snwprintf(key, length, L"%ls%ls%ls", prefix, scheme, suffix);
  }
  return key;
}

static int32_t proton_protocol_windows_read(const wchar_t *command_key,
                                            wchar_t **out_value) {
  HKEY key = NULL;
  LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, command_key, 0, KEY_QUERY_VALUE,
                              &key);
  if (status == ERROR_FILE_NOT_FOUND) {
    return PROTON_OK;
  }
  if (status != ERROR_SUCCESS) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to open protocol command registry key");
  }
  DWORD bytes = 0;
  status = RegQueryValueExW(key, L"", NULL, NULL, NULL, &bytes);
  if (status == ERROR_SUCCESS && bytes >= sizeof(wchar_t)) {
    *out_value = (wchar_t *)calloc(1, bytes + sizeof(wchar_t));
    if (*out_value == NULL) {
      RegCloseKey(key);
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to allocate protocol command buffer");
    }
    status = RegQueryValueExW(key, L"", NULL, NULL, (BYTE *)*out_value, &bytes);
  }
  RegCloseKey(key);
  if (status == ERROR_FILE_NOT_FOUND) {
    return PROTON_OK;
  }
  if (status != ERROR_SUCCESS) {
    free(*out_value);
    *out_value = NULL;
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to read protocol command registry value");
  }
  return PROTON_OK;
}

#else

static char **proton_app_control_argv(const char *executable,
                                      const char *arguments,
                                      int32_t arguments_len) {
  size_t count = 1;
  for (int32_t index = 0; index < arguments_len; index++) {
    if (arguments[index] == '\0') {
      count++;
    }
  }
  char **argv = (char **)calloc(count + 1, sizeof(char *));
  if (argv == NULL) {
    return NULL;
  }
  argv[0] = (char *)executable;
  size_t position = 1;
  for (int32_t offset = 0; offset < arguments_len;) {
    argv[position++] = (char *)(arguments + offset);
    offset += (int32_t)strlen(arguments + offset) + 1;
  }
  return argv;
}

static char *proton_protocol_linux_desktop(const char *identifier) {
  const char *configured = getenv("CHROME_DESKTOP");
  if (configured != NULL && configured[0] != '\0') {
    return proton_app_control_copy(configured, strlen(configured));
  }
  size_t length = strlen(identifier) + strlen(".desktop") + 1;
  char *desktop = (char *)malloc(length);
  if (desktop != NULL) {
    snprintf(desktop, length, "%s.desktop", identifier);
  }
  return desktop;
}

#endif

int32_t proton_protocol_client_set(const char *scheme, const char *identifier,
                                   const char *executable,
                                   const char *arguments,
                                   int32_t arguments_len,
                                   int32_t *out_changed) {
  if (scheme == NULL || scheme[0] == '\0' || identifier == NULL ||
      identifier[0] == '\0' || executable == NULL || executable[0] == '\0' ||
      out_changed == NULL ||
      !proton_app_control_arguments_valid(arguments, arguments_len)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid protocol client registration");
  }
  *out_changed = 0;
#if defined(_WIN32)
  wchar_t *wide_scheme = NULL;
  wchar_t *command = NULL;
  int32_t result = proton_protocol_windows_command(
      scheme, executable, arguments, arguments_len, &wide_scheme, &command);
  if (result != PROTON_OK) {
    return result;
  }
  wchar_t *protocol_key = proton_protocol_windows_key(wide_scheme, L"");
  wchar_t *command_key =
      proton_protocol_windows_key(wide_scheme, L"\\shell\\open\\command");
  wchar_t *description = NULL;
  size_t description_len = wcslen(wide_scheme) + 5;
  description = (wchar_t *)calloc(description_len, sizeof(wchar_t));
  if (protocol_key == NULL || command_key == NULL || description == NULL) {
    result = proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to allocate protocol registry paths");
    goto cleanup;
  }
  _snwprintf(description, description_len, L"URL:%ls", wide_scheme);
  HKEY protocol = NULL;
  HKEY command_handle = NULL;
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, protocol_key, 0, NULL, 0,
                                KEY_SET_VALUE, NULL, &protocol, NULL);
  if (status == ERROR_SUCCESS) {
    status = RegSetValueExW(protocol, L"", 0, REG_SZ, (BYTE *)description,
                            (DWORD)((wcslen(description) + 1) * sizeof(wchar_t)));
  }
  if (status == ERROR_SUCCESS) {
    status = RegSetValueExW(protocol, L"URL Protocol", 0, REG_SZ,
                            (const BYTE *)L"", sizeof(wchar_t));
  }
  if (status == ERROR_SUCCESS) {
    status = RegCreateKeyExW(HKEY_CURRENT_USER, command_key, 0, NULL, 0,
                             KEY_SET_VALUE, NULL, &command_handle, NULL);
  }
  if (status == ERROR_SUCCESS) {
    status = RegSetValueExW(command_handle, L"", 0, REG_SZ, (BYTE *)command,
                            (DWORD)((wcslen(command) + 1) * sizeof(wchar_t)));
  }
  if (command_handle != NULL) {
    RegCloseKey(command_handle);
  }
  if (protocol != NULL) {
    RegCloseKey(protocol);
  }
  if (status == ERROR_SUCCESS) {
    *out_changed = 1;
    result = proton_set_error(PROTON_OK, NULL);
  } else {
    result = proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to write protocol registry values");
  }
cleanup:
  free(description);
  free(protocol_key);
  free(command_key);
  free(wide_scheme);
  free(command);
  return result;
#else
  char *desktop = proton_protocol_linux_desktop(identifier);
  if (desktop == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate Linux desktop entry name");
  }
  GDesktopAppInfo *app_info = g_desktop_app_info_new(desktop);
  free(desktop);
  if (app_info == NULL) {
    return proton_set_error(
        PROTON_ERR_PLATFORM,
        "the packaged desktop entry is not installed for this application");
  }
  char *content_type = g_strdup_printf("x-scheme-handler/%s", scheme);
  GError *error = NULL;
  gboolean success = content_type != NULL &&
                     g_app_info_set_as_default_for_type(
                         G_APP_INFO(app_info), content_type, &error);
  int had_error = error != NULL;
  if (had_error) {
    proton_set_error(PROTON_ERR_PLATFORM, error->message);
    g_error_free(error);
  }
  g_free(content_type);
  g_object_unref(app_info);
  if (!success) {
    return !had_error
               ? proton_set_error(PROTON_ERR_PLATFORM,
                                  "failed to set the Linux protocol handler")
               : PROTON_ERR_PLATFORM;
  }
  *out_changed = 1;
  return proton_set_error(PROTON_OK, NULL);
#endif
}

int32_t proton_protocol_client_is_default(
    const char *scheme, const char *identifier, const char *executable,
    const char *arguments, int32_t arguments_len, int32_t *out_is_default) {
  if (scheme == NULL || scheme[0] == '\0' || identifier == NULL ||
      identifier[0] == '\0' || executable == NULL || executable[0] == '\0' ||
      out_is_default == NULL ||
      !proton_app_control_arguments_valid(arguments, arguments_len)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid protocol client query");
  }
  *out_is_default = 0;
#if defined(_WIN32)
  wchar_t *wide_scheme = NULL;
  wchar_t *command = NULL;
  int32_t result = proton_protocol_windows_command(
      scheme, executable, arguments, arguments_len, &wide_scheme, &command);
  if (result != PROTON_OK) {
    return result;
  }
  wchar_t *command_key =
      proton_protocol_windows_key(wide_scheme, L"\\shell\\open\\command");
  wchar_t *registered = NULL;
  if (command_key == NULL) {
    result = proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to allocate protocol registry path");
  } else {
    result = proton_protocol_windows_read(command_key, &registered);
    if (result == PROTON_OK && registered != NULL &&
        wcscmp(registered, command) == 0) {
      *out_is_default = 1;
    }
  }
  free(registered);
  free(command_key);
  free(wide_scheme);
  free(command);
  return result;
#else
  GAppInfo *app_info = g_app_info_get_default_for_uri_scheme(scheme);
  if (app_info != NULL) {
    const char *app_id = g_app_info_get_id(app_info);
    char *desktop = proton_protocol_linux_desktop(identifier);
    *out_is_default = app_id != NULL && desktop != NULL &&
                      strcmp(app_id, desktop) == 0;
    free(desktop);
    g_object_unref(app_info);
  }
  return proton_set_error(PROTON_OK, NULL);
#endif
}

int32_t proton_protocol_client_remove(
    const char *scheme, const char *identifier, const char *executable,
    const char *arguments, int32_t arguments_len, int32_t *out_removed) {
  if (out_removed == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "protocol removal result is required");
  }
  *out_removed = 0;
#if defined(_WIN32)
  int32_t is_default = 0;
  int32_t result = proton_protocol_client_is_default(
      scheme, identifier, executable, arguments, arguments_len, &is_default);
  if (result != PROTON_OK || !is_default) {
    return result;
  }
  wchar_t *wide_scheme = proton_app_control_wide(scheme);
  if (wide_scheme == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to encode protocol scheme as UTF-16");
  }
  HKEY classes = NULL;
  LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Classes", 0,
                              KEY_ALL_ACCESS, &classes);
  if (status == ERROR_FILE_NOT_FOUND) {
    free(wide_scheme);
    return proton_set_error(PROTON_OK, NULL);
  }
  if (status != ERROR_SUCCESS) {
    free(wide_scheme);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to open the user protocol registry");
  }
  size_t shell_len = wcslen(wide_scheme) + wcslen(L"\\shell") + 1;
  wchar_t *shell = (wchar_t *)calloc(shell_len, sizeof(wchar_t));
  if (shell == NULL) {
    RegCloseKey(classes);
    free(wide_scheme);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate protocol shell path");
  }
  _snwprintf(shell, shell_len, L"%ls\\shell", wide_scheme);
  status = RegDeleteTreeW(classes, shell);
  free(shell);
  if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
    RegCloseKey(classes);
    free(wide_scheme);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to remove protocol command registry key");
  }
  HKEY protocol = NULL;
  status = RegOpenKeyExW(classes, wide_scheme, 0,
                         KEY_QUERY_VALUE | KEY_SET_VALUE, &protocol);
  if (status == ERROR_SUCCESS) {
    (void)RegDeleteValueW(protocol, L"URL Protocol");
    (void)RegDeleteValueW(protocol, L"");
    DWORD subkeys = 0;
    DWORD values = 0;
    if (RegQueryInfoKeyW(protocol, NULL, NULL, NULL, &subkeys, NULL, NULL,
                         &values, NULL, NULL, NULL, NULL) != ERROR_SUCCESS) {
      subkeys = 1;
      values = 1;
    }
    RegCloseKey(protocol);
    if (subkeys == 0 && values == 0) {
      (void)RegDeleteKeyW(classes, wide_scheme);
    }
  } else if (status != ERROR_FILE_NOT_FOUND) {
    RegCloseKey(classes);
    free(wide_scheme);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to open the protocol registry key");
  }
  RegCloseKey(classes);
  free(wide_scheme);
  *out_removed = 1;
  return proton_set_error(PROTON_OK, NULL);
#else
  (void)scheme;
  (void)identifier;
  (void)executable;
  (void)arguments;
  (void)arguments_len;
  return proton_set_error(PROTON_OK, NULL);
#endif
}

int32_t proton_process_schedule_relaunch(const char *executable,
                                         const char *arguments,
                                         int32_t arguments_len) {
  if (executable == NULL || executable[0] == '\0' ||
      !proton_app_control_arguments_valid(arguments, arguments_len)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid relaunch command");
  }
  proton_relaunch_plan_t *plan =
      (proton_relaunch_plan_t *)calloc(1, sizeof(*plan));
  if (plan == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate relaunch plan");
  }
  plan->executable = proton_app_control_copy(executable, strlen(executable));
  plan->arguments =
      proton_app_control_copy(arguments_len == 0 ? "" : arguments,
                              (size_t)arguments_len);
  plan->arguments_len = arguments_len;
  if (plan->executable == NULL || plan->arguments == NULL) {
    free(plan->executable);
    free(plan->arguments);
    free(plan);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to copy relaunch plan");
  }
  if (g_relaunch_tail == NULL) {
    g_relaunch_head = plan;
  } else {
    g_relaunch_tail->next = plan;
  }
  g_relaunch_tail = plan;
  return proton_set_error(PROTON_OK, NULL);
}

static int32_t proton_process_run_plan(const proton_relaunch_plan_t *plan) {
#if defined(_WIN32)
  wchar_t *command = proton_app_control_command(
      plan->executable, plan->arguments, plan->arguments_len, 0);
  if (command == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to encode relaunch command as UTF-16");
  }
  STARTUPINFOW startup = {0};
  PROCESS_INFORMATION process = {0};
  startup.cb = sizeof(startup);
  BOOL started = CreateProcessW(NULL, command, NULL, NULL, FALSE, 0, NULL, NULL,
                                &startup, &process);
  free(command);
  if (!started) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to start the relaunched application");
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return PROTON_OK;
#else
  char **argv = proton_app_control_argv(plan->executable, plan->arguments,
                                        plan->arguments_len);
  if (argv == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate relaunch arguments");
  }
  pid_t child = 0;
  int status =
      posix_spawn(&child, plan->executable, NULL, NULL, argv, environ);
  free(argv);
  if (status != 0) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to start the relaunched application");
  }
  return PROTON_OK;
#endif
}

int32_t proton_process_run_relaunches(void) {
  int32_t first_error = PROTON_OK;
  while (g_relaunch_head != NULL) {
    proton_relaunch_plan_t *plan = g_relaunch_head;
    g_relaunch_head = plan->next;
    int32_t status = proton_process_run_plan(plan);
    if (first_error == PROTON_OK && status != PROTON_OK) {
      first_error = status;
    }
    free(plan->executable);
    free(plan->arguments);
    free(plan);
  }
  g_relaunch_tail = NULL;
  return first_error == PROTON_OK ? proton_set_error(PROTON_OK, NULL)
                                  : first_error;
}

void proton_process_exit(int32_t exit_code) {
  (void)proton_process_run_relaunches();
#if defined(_WIN32)
  ExitProcess((UINT)exit_code);
#else
  _exit(exit_code);
#endif
}

#endif

/* Jump list support. The builder mirrors the menu configuration builder: it
   owns copies of every string and hands the finished list to one apply call,
   so the FFI keeps passing typed scalars. */
typedef struct proton_jump_list_item {
  int32_t kind;
  char *path;
  char *arguments;
  char *title;
  char *description;
  char *icon_path;
  int32_t icon_index;
  char *working_directory;
} proton_jump_list_item_t;

typedef struct proton_jump_list_category {
  int32_t kind;
  char *name;
  proton_jump_list_item_t *items;
  size_t item_count;
  size_t item_capacity;
} proton_jump_list_category_t;

struct proton_jump_list_builder {
  proton_jump_list_category_t *categories;
  size_t category_count;
  size_t category_capacity;
  /* Items append to the most recent category, in the order the builder
     receives them. */
  proton_jump_list_category_t *current;
};

proton_jump_list_builder_t *proton_jump_list_builder_null(void) {
  return NULL;
}

static char *proton_jump_list_duplicate(const char *value) {
  if (value == NULL || value[0] == '\0') {
    return NULL;
  }
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, length + 1);
  return copy;
}

static void proton_jump_list_free_item(proton_jump_list_item_t *item) {
  free(item->path);
  free(item->arguments);
  free(item->title);
  free(item->description);
  free(item->icon_path);
  free(item->working_directory);
}

int32_t proton_jump_list_builder_create(
    proton_jump_list_builder_t **out_builder) {
  if (out_builder == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_builder is required");
  }
  *out_builder = NULL;
  proton_jump_list_builder_t *builder = (proton_jump_list_builder_t *)calloc(
      1, sizeof(proton_jump_list_builder_t));
  if (builder == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate the jump list builder");
  }
  *out_builder = builder;
  proton_set_error(PROTON_OK, NULL);
  return PROTON_OK;
}

int32_t proton_jump_list_builder_add_category(
    proton_jump_list_builder_t *builder, int32_t kind, const char *name) {
  if (builder == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "builder is required");
  }
  if (kind < PROTON_JUMP_LIST_CATEGORY_TASKS ||
      kind > PROTON_JUMP_LIST_CATEGORY_FREQUENT) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "jump list category kind is invalid");
  }
  if (kind == PROTON_JUMP_LIST_CATEGORY_CUSTOM &&
      (name == NULL || name[0] == '\0')) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "a custom jump list category requires a name");
  }
  if (builder->category_count == builder->category_capacity) {
    size_t capacity = builder->category_capacity == 0
                          ? 4
                          : builder->category_capacity * 2;
    proton_jump_list_category_t *categories =
        (proton_jump_list_category_t *)realloc(
            builder->categories, capacity * sizeof(proton_jump_list_category_t));
    if (categories == NULL) {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to grow the jump list categories");
    }
    builder->categories = categories;
    builder->category_capacity = capacity;
  }
  proton_jump_list_category_t *category =
      &builder->categories[builder->category_count];
  memset(category, 0, sizeof(*category));
  category->kind = kind;
  category->name = proton_jump_list_duplicate(name);
  if (kind == PROTON_JUMP_LIST_CATEGORY_CUSTOM && category->name == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to copy the jump list category name");
  }
  builder->category_count++;
  builder->current = category;
  proton_set_error(PROTON_OK, NULL);
  return PROTON_OK;
}

int32_t proton_jump_list_builder_add_item(
    proton_jump_list_builder_t *builder, int32_t kind, const char *path,
    const char *arguments, const char *title, const char *description,
    const char *icon_path, int32_t icon_index,
    const char *working_directory) {
  if (builder == NULL || builder->current == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "a jump list category is required before an item");
  }
  if (kind < PROTON_JUMP_LIST_ITEM_TASK ||
      kind > PROTON_JUMP_LIST_ITEM_FILE) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "jump list item kind is invalid");
  }
  if (kind != PROTON_JUMP_LIST_ITEM_SEPARATOR &&
      (path == NULL || path[0] == '\0')) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "jump list item path is required");
  }
  proton_jump_list_category_t *category = builder->current;
  if (category->item_count == category->item_capacity) {
    size_t capacity = category->item_capacity == 0
                          ? 4
                          : category->item_capacity * 2;
    proton_jump_list_item_t *items = (proton_jump_list_item_t *)realloc(
        category->items, capacity * sizeof(proton_jump_list_item_t));
    if (items == NULL) {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "failed to grow the jump list items");
    }
    category->items = items;
    category->item_capacity = capacity;
  }
  proton_jump_list_item_t *item = &category->items[category->item_count];
  memset(item, 0, sizeof(*item));
  item->kind = kind;
  item->path = proton_jump_list_duplicate(path);
  item->arguments = proton_jump_list_duplicate(arguments);
  item->title = proton_jump_list_duplicate(title);
  item->description = proton_jump_list_duplicate(description);
  item->icon_path = proton_jump_list_duplicate(icon_path);
  item->icon_index = icon_index;
  item->working_directory = proton_jump_list_duplicate(working_directory);
  if (kind != PROTON_JUMP_LIST_ITEM_SEPARATOR && item->path == NULL) {
    proton_jump_list_free_item(item);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to copy the jump list item path");
  }
  category->item_count++;
  proton_set_error(PROTON_OK, NULL);
  return PROTON_OK;
}

void proton_jump_list_builder_destroy(proton_jump_list_builder_t *builder) {
  if (builder == NULL) {
    return;
  }
  for (size_t index = 0; index < builder->category_count; index++) {
    proton_jump_list_category_t *category = &builder->categories[index];
    for (size_t item_index = 0; item_index < category->item_count;
         item_index++) {
      proton_jump_list_free_item(&category->items[item_index]);
    }
    free(category->items);
    free(category->name);
  }
  free(builder->categories);
  free(builder);
}

#if defined(_WIN32)

static wchar_t *proton_jump_list_wide(const char *value) {
  if (value == NULL || value[0] == '\0') {
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

/* The longest description Windows accepts before it silently drops the item. */
#define PROTON_JUMP_LIST_MAX_DESCRIPTION 260

static bool proton_jump_list_set_title(IShellLinkW *link, const wchar_t *title) {
  if (title == NULL) {
    return true;
  }
  IPropertyStore *store = NULL;
  if (FAILED(link->lpVtbl->QueryInterface(link, &IID_IPropertyStore,
                                          (void **)&store)) ||
      store == NULL) {
    return false;
  }
  PROPVARIANT value;
  memset(&value, 0, sizeof(value));
  value.vt = VT_LPWSTR;
  /* The store copies the string during SetValue, so the caller keeps the
     buffer. */
  value.pwszVal = (LPWSTR)title;
  HRESULT result = store->lpVtbl->SetValue(store, &PKEY_Title, &value);
  if (SUCCEEDED(result)) {
    result = store->lpVtbl->Commit(store);
  }
  store->lpVtbl->Release(store);
  return SUCCEEDED(result);
}

static bool proton_jump_list_append_task(const proton_jump_list_item_t *item,
                                         IObjectCollection *collection) {
  if (item->description != NULL) {
    int description_length =
        MultiByteToWideChar(CP_UTF8, 0, item->description, -1, NULL, 0);
    if (description_length - 1 > PROTON_JUMP_LIST_MAX_DESCRIPTION) {
      return false;
    }
  }
  IShellLinkW *link = NULL;
  HRESULT result = CoCreateInstance(&CLSID_ShellLink, NULL,
                                    CLSCTX_INPROC_SERVER, &IID_IShellLinkW,
                                    (void **)&link);
  if (FAILED(result) || link == NULL) {
    return false;
  }
  wchar_t *path = proton_jump_list_wide(item->path);
  wchar_t *arguments = proton_jump_list_wide(item->arguments);
  wchar_t *description = proton_jump_list_wide(item->description);
  wchar_t *working_directory = proton_jump_list_wide(item->working_directory);
  wchar_t *icon_path = proton_jump_list_wide(item->icon_path);
  wchar_t *title = proton_jump_list_wide(item->title);
  bool appended = path != NULL &&
                  SUCCEEDED(link->lpVtbl->SetPath(link, path)) &&
                  (arguments == NULL ||
                   SUCCEEDED(link->lpVtbl->SetArguments(link, arguments))) &&
                  (description == NULL ||
                   SUCCEEDED(link->lpVtbl->SetDescription(link, description))) &&
                  (working_directory == NULL ||
                   SUCCEEDED(link->lpVtbl->SetWorkingDirectory(
                       link, working_directory))) &&
                  (icon_path == NULL ||
                   SUCCEEDED(link->lpVtbl->SetIconLocation(
                       link, icon_path, item->icon_index))) &&
                  proton_jump_list_set_title(link, title);
  if (appended) {
    appended = SUCCEEDED(collection->lpVtbl->AddObject(
        collection, (IUnknown *)link));
  }
  free(path);
  free(arguments);
  free(description);
  free(working_directory);
  free(icon_path);
  free(title);
  link->lpVtbl->Release(link);
  return appended;
}

static bool proton_jump_list_append_separator(IObjectCollection *collection) {
  IShellLinkW *link = NULL;
  HRESULT result = CoCreateInstance(&CLSID_ShellLink, NULL,
                                    CLSCTX_INPROC_SERVER, &IID_IShellLinkW,
                                    (void **)&link);
  if (FAILED(result) || link == NULL) {
    return false;
  }
  IPropertyStore *store = NULL;
  bool appended = false;
  if (SUCCEEDED(link->lpVtbl->QueryInterface(link, &IID_IPropertyStore,
                                             (void **)&store)) &&
      store != NULL) {
    PROPVARIANT value;
    memset(&value, 0, sizeof(value));
    value.vt = VT_BOOL;
    value.boolVal = VARIANT_TRUE;
    result =
        store->lpVtbl->SetValue(store, &PKEY_AppUserModel_IsDestListSeparator,
                                &value);
    if (SUCCEEDED(result)) {
      result = store->lpVtbl->Commit(store);
    }
    if (SUCCEEDED(result)) {
      appended = SUCCEEDED(
          collection->lpVtbl->AddObject(collection, (IUnknown *)link));
    }
    store->lpVtbl->Release(store);
  }
  link->lpVtbl->Release(link);
  return appended;
}

static bool proton_jump_list_append_file(const proton_jump_list_item_t *item,
                                         IObjectCollection *collection) {
  wchar_t *path = proton_jump_list_wide(item->path);
  if (path == NULL) {
    return false;
  }
  IShellItem *file = NULL;
  bool appended = false;
  if (SUCCEEDED(SHCreateItemFromParsingName(path, NULL, &IID_IShellItem,
                                            (void **)&file)) &&
      file != NULL) {
    appended = SUCCEEDED(
        collection->lpVtbl->AddObject(collection, (IUnknown *)file));
    file->lpVtbl->Release(file);
  }
  free(path);
  return appended;
}

/* Appends one category and reports the Electron result code for it. Items that
   fail individually are dropped, the rule Electron documents: it is better to
   show part of the category than none of it. */
static int32_t proton_jump_list_append_category(
    ICustomDestinationList *destinations,
    const proton_jump_list_category_t *category) {
  if (category->kind == PROTON_JUMP_LIST_CATEGORY_RECENT) {
    return SUCCEEDED(destinations->lpVtbl->AppendKnownCategory(
               destinations, KDC_RECENT))
               ? PROTON_JUMP_LIST_OK
               : PROTON_JUMP_LIST_ERROR;
  }
  if (category->kind == PROTON_JUMP_LIST_CATEGORY_FREQUENT) {
    return SUCCEEDED(destinations->lpVtbl->AppendKnownCategory(
               destinations, KDC_FREQUENT))
               ? PROTON_JUMP_LIST_OK
               : PROTON_JUMP_LIST_ERROR;
  }
  if (category->item_count == 0) {
    return PROTON_JUMP_LIST_OK;
  }
  IObjectCollection *collection = NULL;
  if (FAILED(CoCreateInstance(&CLSID_EnumerableObjectCollection, NULL,
                              CLSCTX_INPROC_SERVER, &IID_IObjectCollection,
                              (void **)&collection)) ||
      collection == NULL) {
    return PROTON_JUMP_LIST_ERROR;
  }
  int32_t result = PROTON_JUMP_LIST_OK;
  size_t appended_count = 0;
  for (size_t index = 0; index < category->item_count; index++) {
    const proton_jump_list_item_t *item = &category->items[index];
    bool appended = false;
    switch (item->kind) {
    case PROTON_JUMP_LIST_ITEM_TASK:
      appended = proton_jump_list_append_task(item, collection);
      break;
    case PROTON_JUMP_LIST_ITEM_SEPARATOR:
      if (category->kind != PROTON_JUMP_LIST_CATEGORY_TASKS) {
        result = PROTON_JUMP_LIST_INVALID_SEPARATOR;
      } else {
        appended = proton_jump_list_append_separator(collection);
      }
      break;
    case PROTON_JUMP_LIST_ITEM_FILE:
      appended = proton_jump_list_append_file(item, collection);
      break;
    default:
      break;
    }
    if (appended) {
      appended_count++;
    }
  }
  if (appended_count == 0) {
    collection->lpVtbl->Release(collection);
    return result;
  }
  if (appended_count < category->item_count && result == PROTON_JUMP_LIST_OK) {
    result = PROTON_JUMP_LIST_ERROR;
  }
  IObjectArray *items = NULL;
  HRESULT hr = collection->lpVtbl->QueryInterface(collection, &IID_IObjectArray,
                                                  (void **)&items);
  collection->lpVtbl->Release(collection);
  if (FAILED(hr) || items == NULL) {
    return PROTON_JUMP_LIST_ERROR;
  }
  if (category->kind == PROTON_JUMP_LIST_CATEGORY_TASKS) {
    hr = destinations->lpVtbl->AddUserTasks(destinations, items);
    if (FAILED(hr) && result == PROTON_JUMP_LIST_OK) {
      result = PROTON_JUMP_LIST_ERROR;
    }
  } else {
    wchar_t *name = proton_jump_list_wide(category->name);
    if (name == NULL) {
      items->lpVtbl->Release(items);
      return PROTON_JUMP_LIST_ERROR;
    }
    hr = destinations->lpVtbl->AppendCategory(destinations, name, items);
    free(name);
    if (FAILED(hr)) {
      if (hr == (HRESULT)0x80040F03) {
        result = PROTON_JUMP_LIST_FILE_TYPE_REGISTRATION_ERROR;
      } else if (hr == E_ACCESSDENIED) {
        result = PROTON_JUMP_LIST_CUSTOM_CATEGORY_ACCESS_DENIED;
      } else if (result == PROTON_JUMP_LIST_OK) {
        result = PROTON_JUMP_LIST_ERROR;
      }
    }
  }
  items->lpVtbl->Release(items);
  return result;
}

static int32_t proton_jump_list_apply_platform(
    proton_jump_list_builder_t *builder, int32_t *out_result) {
  *out_result = PROTON_JUMP_LIST_ERROR;
  ICustomDestinationList *destinations = NULL;
  if (FAILED(CoCreateInstance(&CLSID_DestinationList, NULL,
                              CLSCTX_INPROC_SERVER, &IID_ICustomDestinationList,
                              (void **)&destinations)) ||
      destinations == NULL) {
    return PROTON_OK;
  }
  /* The jump list belongs to the AppUserModelID of the process, which is what
     the taskbar button uses too. An installed application registers that
     identity; without one Windows derives it from the executable path, and
     leaving the destination list unset keeps both in step. */
  PWSTR explicit_app_id = NULL;
  if (SUCCEEDED(GetCurrentProcessExplicitAppUserModelID(&explicit_app_id)) &&
      explicit_app_id != NULL && explicit_app_id[0] != L'\0') {
    if (FAILED(destinations->lpVtbl->SetAppID(destinations,
                                              explicit_app_id))) {
      CoTaskMemFree(explicit_app_id);
      destinations->lpVtbl->Release(destinations);
      return PROTON_OK;
    }
  }
  CoTaskMemFree(explicit_app_id);
  if (builder == NULL) {
    *out_result = SUCCEEDED(destinations->lpVtbl->DeleteList(destinations, NULL))
                      ? PROTON_JUMP_LIST_OK
                      : PROTON_JUMP_LIST_ERROR;
    destinations->lpVtbl->Release(destinations);
    return PROTON_OK;
  }
  UINT min_slots = 0;
  IObjectArray *removed = NULL;
  if (FAILED(destinations->lpVtbl->BeginList(destinations, &min_slots,
                                             &IID_IObjectArray,
                                             (void **)&removed))) {
    destinations->lpVtbl->Release(destinations);
    return PROTON_OK;
  }
  if (removed != NULL) {
    removed->lpVtbl->Release(removed);
  }
  int32_t result = PROTON_JUMP_LIST_OK;
  for (size_t index = 0; index < builder->category_count; index++) {
    int32_t latest =
        proton_jump_list_append_category(destinations,
                                         &builder->categories[index]);
    /* Keep the first specific error, the rule Electron applies so the result
       is the most useful one. */
    if ((result == PROTON_JUMP_LIST_OK || result == PROTON_JUMP_LIST_ERROR) &&
        latest != PROTON_JUMP_LIST_OK) {
      result = latest;
    }
  }
  /* Some categories may have failed, but a partial list is better than none,
     so the transaction still commits unless it committed nothing. */
  if (FAILED(destinations->lpVtbl->CommitList(destinations)) &&
      result == PROTON_JUMP_LIST_OK) {
    result = PROTON_JUMP_LIST_ERROR;
  }
  destinations->lpVtbl->Release(destinations);
  *out_result = result;
  return PROTON_OK;
}

#else

static int32_t proton_jump_list_apply_platform(
    proton_jump_list_builder_t *builder, int32_t *out_result) {
  (void)builder;
  *out_result = PROTON_JUMP_LIST_UNSUPPORTED;
  return PROTON_OK;
}

#endif

int32_t proton_jump_list_apply(proton_jump_list_builder_t *categories,
                               int32_t *out_result) {
  if (out_result == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_result is required");
  }
  *out_result = PROTON_JUMP_LIST_ERROR;
  int32_t status = proton_jump_list_apply_platform(categories, out_result);
  if (status != PROTON_OK) {
    return status;
  }
  proton_set_error(PROTON_OK, NULL);
  return PROTON_OK;
}
