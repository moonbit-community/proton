#if defined(_WIN32)

#include "../../proton_engine.h"
#include "win_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>
#include <objbase.h>
#include <shobjidl.h>

#include "win_titlebar.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"
#include "../cef_common/view_events.h"

#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_PATH_SEPARATOR '\\'
#define PROTON_ENGINE_DIALOG_CLASS L"ProtonNativeMessageDialog"
// Posted to a frame window when its destruction must be deferred out of a
// CEF callback: tearing the frame down inline during OnBeforeClose can
// invalidate browser teardown state on the external message pump route.
// Posted to a frame window from a child browser's DoClose callback. Destroying
// the child HWND inside that callback re-enters CEF while it is still unwinding
// the browser close state.
static int g_proton_cef_initialized = 0;
static int g_proton_cef_runtime_active = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
static int g_proton_engine_multi_threaded_message_loop = 0;
static int g_proton_engine_window_lock_initialized = 0;
static int32_t g_proton_remote_debugging_port =
    PROTON_REMOTE_DEBUGGING_DISABLED;
static CRITICAL_SECTION g_proton_engine_window_lock;
static proton_engine_window_t *g_proton_engine_windows;
static volatile LONG64 g_proton_engine_scheduled_pump_delay_ms = -1;
/* Set only while this process is inside cef_do_message_loop_work. */
static volatile LONG g_proton_engine_message_pump_active = 0;
static HANDLE g_proton_engine_pump_event = NULL;
/* Main-thread only, so a plain bool: set by proton_engine_host_loop_begin and
   cleared by proton_engine_host_loop_end. */
static bool g_proton_engine_host_loop_active = false;

/* The pump event belongs to the host loop once one is running. It is created
   before the first runtime and has to survive the last one, because the host
   keeps polling through its own shutdown and a closed handle would turn every
   one of those polls into an error. Only a CEF lifetime that created it may
   close it. */
static void proton_engine_release_pump_event(void) {
  if (g_proton_engine_host_loop_active) {
    return;
  }
  if (g_proton_engine_pump_event != NULL) {
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
  }
}
static proton_engine_runtime_t *g_proton_engine_active_runtime = NULL;

int proton_engine_runtime_initialized(void) {
  return g_proton_cef_initialized;
}

proton_engine_window_t *proton_engine_windows_head(void) {
  return g_proton_engine_windows;
}

int32_t proton_engine_runtime_remote_debugging_port(void) {
  return g_proton_remote_debugging_port;
}

void proton_engine_signal_wait_source(
    proton_engine_runtime_t *runtime, uint32_t ready_mask) {
  (void)runtime;
  (void)ready_mask;
  if (g_proton_engine_pump_event != NULL) {
    SetEvent(g_proton_engine_pump_event);
  }
}

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
}

void proton_engine_browser_signal(void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  proton_engine_signal_wait_source(
      window != NULL ? window->runtime : NULL, PROTON_WAIT_EVENT);
}

static int proton_engine_env_equals_ignore_case(const char *value,
                                                const char *expected) {
  if (value == NULL || expected == NULL) {
    return 0;
  }
  while (*value != '\0' && *expected != '\0') {
    if (tolower((unsigned char)*value) !=
        tolower((unsigned char)*expected)) {
      return 0;
    }
    value++;
    expected++;
  }
  return *value == '\0' && *expected == '\0';
}

static cef_log_severity_t proton_engine_cef_log_severity_from_env(void) {
  const char *value = getenv("PROTON_CEF_LOG");
  if (value == NULL || value[0] == '\0' ||
      proton_engine_env_equals_ignore_case(value, "0") ||
      proton_engine_env_equals_ignore_case(value, "false") ||
      proton_engine_env_equals_ignore_case(value, "off") ||
      proton_engine_env_equals_ignore_case(value, "disable") ||
      proton_engine_env_equals_ignore_case(value, "disabled")) {
    return LOGSEVERITY_DISABLE;
  }
  if (proton_engine_env_equals_ignore_case(value, "verbose") ||
      proton_engine_env_equals_ignore_case(value, "debug")) {
    return LOGSEVERITY_VERBOSE;
  }
  if (proton_engine_env_equals_ignore_case(value, "info")) {
    return LOGSEVERITY_INFO;
  }
  if (proton_engine_env_equals_ignore_case(value, "warning") ||
      proton_engine_env_equals_ignore_case(value, "warn")) {
    return LOGSEVERITY_WARNING;
  }
  if (proton_engine_env_equals_ignore_case(value, "error")) {
    return LOGSEVERITY_ERROR;
  }
  if (proton_engine_env_equals_ignore_case(value, "fatal")) {
    return LOGSEVERITY_FATAL;
  }
  if (proton_engine_env_equals_ignore_case(value, "default")) {
    return LOGSEVERITY_DEFAULT;
  }
  return LOGSEVERITY_DEFAULT;
}

static int64_t proton_engine_get_scheduled_pump_delay_ms(void) {
  return (int64_t)InterlockedCompareExchange64(
      &g_proton_engine_scheduled_pump_delay_ms, 0, 0);
}

void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
  InterlockedExchange64(&g_proton_engine_scheduled_pump_delay_ms,
                        (LONG64)delay_ms);
  /* Every delay signals, not just an immediate one. A host blocked with no
     deadline of its own has nothing else to bring it back, and it reads the
     schedule only on its way into a wait -- one that arrives after that read
     would otherwise never be seen. The pump-active guard is what keeps this
     from spinning: the reschedule CEF makes while being pumped stays silent,
     so the loop settles onto the delay instead of the signal. */
  if (InterlockedCompareExchange(&g_proton_engine_message_pump_active, 0, 0) ==
      0) {
    proton_engine_signal_wait_source(g_proton_engine_active_runtime,
                                     PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_reset_scheduled_pump(void) {
  InterlockedExchange64(&g_proton_engine_scheduled_pump_delay_ms, -1);
  if (g_proton_engine_pump_event != NULL) {
    ResetEvent(g_proton_engine_pump_event);
  }
}

static int32_t proton_engine_unsupported(char *error,
                                         size_t error_len,
                                         const char *message) {
  proton_engine_set_message(error, error_len, message);
  return PROTON_ERR_UNSUPPORTED;
}

static bool proton_engine_join_path(char *out,
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
    separator = "\\";
  }
  int written = snprintf(out, out_len, "%s%s%s", base, separator, child);
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_engine_path_parent(char *path) {
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

#include "../cef_common/strings.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) ((refs)->refs)
#define PROTON_ENGINE_REF_STORE(refs, value) ((refs)->refs = (value))
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../cef_common/bridge_request.h"

static void proton_engine_init_window_lock(void) {
  if (!g_proton_engine_window_lock_initialized) {
    InitializeCriticalSection(&g_proton_engine_window_lock);
    g_proton_engine_window_lock_initialized = 1;
  }
}

void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_init_window_lock();
  EnterCriticalSection(&g_proton_engine_window_lock);
  window->next = g_proton_engine_windows;
  g_proton_engine_windows = window;
  LeaveCriticalSection(&g_proton_engine_window_lock);
}

void proton_engine_window_list_remove(proton_engine_window_t *window) {
  if (window == NULL || !g_proton_engine_window_lock_initialized) {
    return;
  }
  EnterCriticalSection(&g_proton_engine_window_lock);
  proton_engine_window_t **cursor = &g_proton_engine_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      break;
    }
    cursor = &(*cursor)->next;
  }
  LeaveCriticalSection(&g_proton_engine_window_lock);
}

int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id,
    int64_t public_window, const char *op, const char *payload,
    const char *page_instance, const char *source_origin) {
  if (runtime == NULL || request_id <= 0 || public_window <= 0 ||
      op == NULL || payload == NULL || page_instance == NULL ||
      source_origin == NULL) {
    return 0;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_BRIDGE_REQUEST);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  event->window = public_window;
  const char *items[] = {op, payload, page_instance, source_origin};
  if (!proton_event_set_items(event, items, 4) ||
      !proton_event_try_publish(event)) {
    proton_event_destroy(event);
    return 0;
  }
  return 1;
}

int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t request_id) {
  if (runtime == NULL || request_id <= 0) {
    return 0;
  }
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_BRIDGE_REQUEST_CANCELLED);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  return proton_event_publish(event);
}

int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

/* The application resource factory lives in cef_common/scheme.c. These are
   the accessors it reads windows through; see cef_common/scheme.h. */

void proton_engine_window_lock(void) {
  proton_engine_init_window_lock();
  EnterCriticalSection(&g_proton_engine_window_lock);
}

void proton_engine_window_unlock(void) {
  LeaveCriticalSection(&g_proton_engine_window_lock);
}

proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser) {
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) != PROTON_BROWSER_ROLE_MAIN) {
    return NULL;
  }
  return (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
}

cef_browser_t *proton_engine_window_browser(proton_engine_window_t *window) {
  return window != NULL
             ? proton_browser_lifecycle_browser(window->browser_lifecycle)
             : NULL;
}

cef_browser_t *proton_engine_view_browser(proton_engine_view_t *view) {
  return view != NULL
             ? proton_browser_lifecycle_browser(view->browser_lifecycle)
             : NULL;
}

proton_engine_view_t *proton_engine_window_lookup_view_browser(
    cef_browser_t *browser) {
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) != PROTON_BROWSER_ROLE_VIEW) {
    return NULL;
  }
  return (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
}

proton_window_id_t proton_engine_view_window_public_id(
    proton_engine_view_t *view) {
  proton_view_id_t view_id = PROTON_INVALID_HANDLE;
  proton_window_id_t window_id = PROTON_INVALID_HANDLE;
  if (view == NULL ||
      !proton_view_events_ids(view->events, &view_id, &window_id)) {
    return PROTON_INVALID_HANDLE;
  }
  return window_id;
}

proton_view_id_t proton_engine_view_public_id(proton_engine_view_t *view) {
  proton_view_id_t view_id = PROTON_INVALID_HANDLE;
  proton_window_id_t window_id = PROTON_INVALID_HANDLE;
  if (view == NULL ||
      !proton_view_events_ids(view->events, &view_id, &window_id)) {
    return PROTON_INVALID_HANDLE;
  }
  return view_id;
}


static void proton_engine_remove_temporary_profile(void) {
  if (g_proton_temporary_profile_path[0] != '\0') {
    proton_profile_storage_remove_temporary(g_proton_temporary_profile_path);
    g_proton_temporary_profile_path[0] = '\0';
  }
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    cef_shutdown();
    g_proton_cef_initialized = 0;
  }
  proton_engine_remove_temporary_profile();
}

const char *proton_engine_name(void) {
  return "cef";
}

int32_t proton_engine_execute_process(
    const proton_engine_runtime_config_t *config, int32_t *out_exit_code,
    char *error, size_t error_len) {
  if (config == NULL) {
    proton_engine_set_message(error, error_len, "runtime config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_set_command_line_paths(config);
  proton_engine_init_app();
  proton_engine_check_cef_api_hash();

  cef_main_args_t args;
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  int exit_code = cef_execute_process(&args, proton_engine_cef_app(), NULL);
  if (out_exit_code != NULL) {
    *out_exit_code = exit_code;
  }
  return exit_code >= 0 ? PROTON_PROCESS_HANDLED : PROTON_OK;
}

int32_t proton_engine_runtime_create(
    const proton_engine_runtime_config_t *input_config,
    proton_engine_runtime_t **out_runtime, char *error, size_t error_len) {
  if (out_runtime == NULL) {
    proton_engine_set_message(error, error_len, "out_runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_runtime = NULL;

  if (g_proton_cef_runtime_active) {
    proton_engine_set_message(error, error_len, "runtime is already active");
    return PROTON_ERR_ALREADY_INITIALIZED;
  }

  if (input_config == NULL) {
    proton_engine_set_message(error, error_len, "runtime config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_runtime_config_t config = *input_config;
  g_proton_remote_debugging_port = config.remote_debugging_port;
  int temporary_profile = config.cache_dir[0] == '\0';
  if (temporary_profile) {
    if (!proton_profile_storage_create_temporary(
            config.cache_dir, sizeof(config.cache_dir), error, error_len)) {
      return PROTON_ERR_ENGINE;
    }
    snprintf(g_proton_temporary_profile_path,
             sizeof(g_proton_temporary_profile_path), "%s", config.cache_dir);
    config.persist_session_cookies = 0;
  }
  proton_engine_set_command_line_paths(&config);
  proton_engine_init_app();
  proton_engine_check_cef_api_hash();

  cef_main_args_t args;
  cef_settings_t settings;
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  memset(&settings, 0, sizeof(settings));
  settings.size = sizeof(settings);
  settings.no_sandbox = 1;
  settings.multi_threaded_message_loop = 0;
  settings.external_message_pump = 1;
  settings.windowless_rendering_enabled = config.headless;
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  g_proton_engine_multi_threaded_message_loop = 0;
  settings.remote_debugging_port = config.remote_debugging_port > 0
                                       ? config.remote_debugging_port
                                       : PROTON_REMOTE_DEBUGGING_DISABLED;
  settings.persist_session_cookies = config.persist_session_cookies;

  if (settings.external_message_pump &&
      g_proton_engine_pump_event == NULL) {
    g_proton_engine_pump_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (g_proton_engine_pump_event == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to create CEF pump wake event");
      proton_engine_remove_temporary_profile();
      return PROTON_ERR_PLATFORM;
    }
  }
  proton_engine_reset_scheduled_pump();

  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  proton_engine_set_string(&settings.locale, config.locale);
  proton_engine_set_string(&settings.accept_language_list,
                           config.accept_languages);
  proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  if (!temporary_profile) {
    proton_engine_set_string(&settings.cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, proton_engine_cef_app(), NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.locale);
    cef_string_clear(&settings.accept_language_list);
    cef_string_clear(&settings.cache_path);
    cef_string_clear(&settings.root_cache_path);
    proton_engine_release_pump_event();
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.locale);
  cef_string_clear(&settings.accept_language_list);
  cef_string_clear(&settings.cache_path);
  cef_string_clear(&settings.root_cache_path);
  g_proton_cef_initialized = 1;
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    proton_engine_release_pump_event();
    proton_engine_set_message(error, error_len,
                              "failed to register proton scheme handler");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(proton_engine_runtime_t));
  if (runtime == NULL) {
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    proton_engine_release_pump_event();
    proton_engine_set_message(error, error_len,
                              "failed to allocate runtime state");
    return PROTON_ERR_ENGINE;
  }
  runtime->owns_cef_runtime = 1;
  runtime->headless = config.headless;
  runtime->next_bridge_request_id = 1;
  runtime->browsers = proton_browser_registry_create(
      proton_engine_browser_client_factory, runtime);
  if (runtime->browsers == NULL) {
    free(runtime);
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    proton_engine_release_pump_event();
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser registry");
    return PROTON_ERR_ENGINE;
  }
  snprintf(runtime->dialog_ok_label, sizeof(runtime->dialog_ok_label), "%s",
           config.dialog_ok_label);
  snprintf(runtime->dialog_cancel_label,
           sizeof(runtime->dialog_cancel_label), "%s",
           config.dialog_cancel_label);
  InitializeCriticalSection(&runtime->wakeup_lock);
  runtime->wakeup_lock_initialized = 1;
  g_proton_engine_active_runtime = runtime;
  *out_runtime = runtime;
  return PROTON_OK;
}

static void proton_engine_dispose_runtime_state(
    proton_engine_runtime_t *runtime) {
  proton_engine_bridge_pending_clear_all();
  proton_engine_release_pump_event();
  proton_engine_reset_scheduled_pump();
  if (g_proton_engine_active_runtime == runtime) {
    g_proton_engine_active_runtime = NULL;
  }
  g_proton_cef_runtime_active = 0;
  proton_menu_bar_destroy(runtime->menu_definition);
  proton_browser_registry_destroy(runtime->browsers);
  free(runtime);
}

int32_t proton_engine_runtime_destroy_ready(proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  proton_browser_registry_begin_shutdown(runtime->browsers);
  if (!g_proton_engine_window_lock_initialized) {
    return g_proton_engine_windows == NULL &&
           proton_browser_registry_shutdown_ready(runtime->browsers);
  }
  int32_t ready = 1;
  EnterCriticalSection(&g_proton_engine_window_lock);
  for (proton_engine_window_t *window = g_proton_engine_windows;
       window != NULL; window = window->next) {
    if (window->runtime == runtime) {
      ready = 0;
      break;
    }
  }
  LeaveCriticalSection(&g_proton_engine_window_lock);
  return ready && proton_engine_closed_windows_ready_for_shutdown() &&
         proton_browser_registry_shutdown_ready(runtime->browsers);
}

int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_dialog_cancel_runtime(runtime);
  proton_browser_registry_begin_shutdown(runtime->browsers);
  if (runtime->owns_cef_runtime) {
    if (!proton_engine_runtime_destroy_ready(runtime)) {
      proton_engine_set_message(error, error_len,
                                "runtime still owns closing browser windows");
      return PROTON_ERR_BUSY;
    }
    proton_engine_cef_shutdown();
    proton_engine_free_closed_windows();
    runtime->owns_cef_runtime = 0;
  }
  proton_engine_dispose_runtime_state(runtime);
  return PROTON_OK;
}

int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  InterlockedExchange(&g_proton_engine_message_pump_active, 1);
  proton_engine_reset_scheduled_pump();
  MSG msg;
  while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  if (!g_proton_engine_multi_threaded_message_loop) {
    cef_do_message_loop_work();
  }
  InterlockedExchange(&g_proton_engine_message_pump_active, 0);
  return PROTON_OK;
}

int32_t proton_engine_host_loop_begin(char *error, size_t error_len) {
  /* The pump event is process-wide and needs no CEF, so the host loop can own
     it before the first runtime exists. Manual-reset on purpose: a wakeup
     delivered while nothing is waiting must leave the next wait returning
     immediately, because the trait's contract makes a lost wakeup a deadlock. */
  if (g_proton_engine_pump_event == NULL) {
    g_proton_engine_pump_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (g_proton_engine_pump_event == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to create the host loop event");
      return PROTON_ERR_PLATFORM;
    }
  }
  g_proton_engine_host_loop_active = true;
  return PROTON_OK;
}

int32_t proton_engine_host_loop_poll(int32_t timeout_ms,
                                     uint32_t *out_ready_mask,
                                     char *error,
                                     size_t error_len) {
  int32_t status = proton_engine_runtime_wait(
      NULL, PROTON_WAIT_ALL, timeout_ms, out_ready_mask, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  /* The wait above only blocks on handles; it dispatches nothing. This is
     where the thread's message queue drains and the only caller of
     cef_do_message_loop_work while the host loop owns the main thread.
     The reset comes before the CEF check because the pump event is
     manual-reset: a wakeup that arrived before the first runtime existed would
     otherwise leave every later wait returning immediately. */
  InterlockedExchange(&g_proton_engine_message_pump_active, 1);
  proton_engine_reset_scheduled_pump();
  MSG msg;
  while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  if (g_proton_cef_initialized &&
      !g_proton_engine_multi_threaded_message_loop) {
    cef_do_message_loop_work();
  }
  InterlockedExchange(&g_proton_engine_message_pump_active, 0);
  return PROTON_OK;
}

void proton_engine_host_loop_end(void) {
  g_proton_engine_host_loop_active = false;
  proton_engine_release_pump_event();
}

int32_t proton_engine_runtime_wait(proton_engine_runtime_t *runtime,
                                   uint32_t interest_mask,
                                   int32_t timeout_ms,
                                   uint32_t *out_ready_mask,
                                   char *error,
                                   size_t error_len) {
  if (out_ready_mask != NULL) {
    *out_ready_mask = PROTON_WAIT_NONE;
  }
  /* A NULL runtime waits for host-loop wakeups alone. The host loop is running
     before the first engine runtime exists -- application code does file IO
     while it is still deciding what runtime to build -- and a wait that
     refused to block until then would leave those wakeups nowhere to land. */
  if (runtime != NULL && !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (g_proton_engine_pump_event == NULL) {
    proton_engine_set_message(error, error_len, "host loop is not running");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_ready_mask == NULL) {
    proton_engine_set_message(error, error_len, "out_ready_mask is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  uint32_t ready_mask = PROTON_WAIT_NONE;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  if (ready_mask != PROTON_WAIT_NONE) {
    *out_ready_mask = ready_mask;
    return PROTON_OK;
  }

  HANDLE handles[1];
  DWORD handle_count = 0;
  DWORD pump_handle_index = MAXDWORD;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_proton_engine_pump_event != NULL) {
    pump_handle_index = handle_count;
    handles[handle_count++] = g_proton_engine_pump_event;
  }

  // Negative means PROTON_WAIT_TIMEOUT_INFINITE; the ABI rejects every other
  // negative value first. Assigning it straight into a DWORD would happen to
  // produce Win32's INFINITE, which is the right answer for the wrong reason
  // and would break the moment the sentinel changed, so it is spelled out.
  int wait_forever = timeout_ms < 0;
  int64_t requested_timeout = wait_forever ? 0 : (int64_t)timeout_ms;
  int waiting_for_platform_pump = 0;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_proton_cef_initialized &&
      !g_proton_engine_multi_threaded_message_loop) {
    int64_t pump_delay = PROTON_ENGINE_MAX_MESSAGE_PUMP_DELAY_MS;
    int64_t scheduled_delay = proton_engine_get_scheduled_pump_delay_ms();
    if (scheduled_delay >= 0 && scheduled_delay < pump_delay) {
      pump_delay = scheduled_delay;
    }
    if (wait_forever || pump_delay <= requested_timeout) {
      requested_timeout = pump_delay;
      wait_forever = 0;
      waiting_for_platform_pump = 1;
    }
  }
  DWORD wait_timeout = wait_forever ? INFINITE : (DWORD)requested_timeout;

  DWORD wake_mask =
      (interest_mask & PROTON_WAIT_PLATFORM) != 0 ? QS_ALLINPUT : 0;
  DWORD wait_result = MsgWaitForMultipleObjectsEx(
      handle_count, handle_count > 0 ? handles : NULL, wait_timeout, wake_mask,
      MWMO_INPUTAVAILABLE);
  if (wait_result == WAIT_FAILED) {
    char message[128];
    snprintf(message, sizeof(message),
             "runtime wait failed with Windows error %lu",
             (unsigned long)GetLastError());
    proton_engine_set_message(error, error_len, message);
    return PROTON_ERR_PLATFORM;
  }

  if (wait_result >= WAIT_OBJECT_0 &&
      wait_result < WAIT_OBJECT_0 + handle_count) {
    DWORD ready_index = wait_result - WAIT_OBJECT_0;
    if (ready_index == pump_handle_index) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else if (wait_result == WAIT_OBJECT_0 + handle_count) {
    if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else if (wait_result == WAIT_TIMEOUT) {
    if (waiting_for_platform_pump) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else {
    proton_engine_set_message(error, error_len,
                              "runtime wait returned an unexpected status");
    return PROTON_ERR_PLATFORM;
  }

  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  *out_ready_mask = ready_mask & interest_mask;
  return PROTON_OK;
}

#endif
