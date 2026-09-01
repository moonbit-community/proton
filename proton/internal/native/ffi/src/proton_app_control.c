#if !defined(__APPLE__)

#include "proton_internal.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <gio/gdesktopappinfo.h>
#include <gio/gio.h>
#include <spawn.h>
#include <unistd.h>
extern char **environ;
#endif

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
