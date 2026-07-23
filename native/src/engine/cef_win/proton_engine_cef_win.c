#include "../../proton_engine.h"
#include "../../proton_json.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#include "proton_win_titlebar.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"

#include <ctype.h>
#include <limits.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_PATH_SEPARATOR '\\'
#define PROTON_ENGINE_MAX_PATH_BYTES 4096
#define PROTON_ENGINE_MAX_URL_BYTES 131072
#define PROTON_ENGINE_WINDOW_CLASS L"ProtonNativeWindow"
#define PROTON_ENGINE_MAX_BRIDGE_REQUESTS 256
#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
typedef struct proton_engine_client proton_engine_client_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int64_t next_bridge_request_id;
  char *bridge_queue[PROTON_ENGINE_MAX_BRIDGE_REQUESTS];
  size_t bridge_head;
  size_t bridge_count;
  CRITICAL_SECTION bridge_lock;
  int bridge_lock_initialized;
  HANDLE bridge_event;
};

struct proton_engine_window {
  HWND hwnd;
  proton_engine_runtime_t *runtime;
  proton_window_id_t public_window_id;
  cef_client_t *client;
  cef_browser_t *browser;
  int browser_id;
  char *html_url;
  char *html;
  size_t html_len;
  char *bridge_config_json;
  int32_t max_bridge_payload_bytes;
  proton_engine_bridge_lifecycle_t bridge_lifecycle;
  int width;
  int height;
  int titlebar_overlay;
  proton_win_titlebar_region_t *draggable_regions;
  size_t draggable_region_count;
  int draggable_regions_reported;
  int closed;
  struct proton_engine_window *next;
};

typedef struct {
  LONG refs;
} proton_engine_ref_counted_t;

typedef struct {
  cef_app_t app;
  proton_engine_ref_counted_t refs;
} proton_engine_app_t;

typedef struct {
  cef_browser_process_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_browser_process_handler_t;

typedef struct {
  cef_render_process_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_render_process_handler_t;

typedef struct {
  cef_v8_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_v8_handler_t;

typedef struct {
  cef_load_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_load_handler_t;

typedef struct {
  cef_drag_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_drag_handler_t;

typedef struct {
  cef_request_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_request_handler_t;

typedef struct {
  cef_scheme_handler_factory_t factory;
  proton_engine_ref_counted_t refs;
} proton_engine_scheme_factory_t;

typedef struct {
  cef_resource_handler_t handler;
  proton_engine_ref_counted_t refs;
  char *html;
  size_t html_len;
  char *mime_type;
  size_t offset;
} proton_engine_html_resource_handler_t;

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_engine_window_t *window;
};

typedef struct proton_engine_bridge_pending {
  int64_t request_id;
  int browser_id;
  int renderer_pending_id;
  char *page_instance;
  cef_frame_t *frame;
  struct proton_engine_bridge_pending *next;
} proton_engine_bridge_pending_t;

typedef struct {
  char runtime_root[PROTON_ENGINE_MAX_PATH_BYTES];
  char helper_path[PROTON_ENGINE_MAX_PATH_BYTES];
  char resources_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char locales_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char cache_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  int32_t remote_debugging_port;
} proton_engine_runtime_config_t;

static int g_proton_cef_initialized = 0;
static int g_proton_cef_shutdown_registered = 0;
static int g_proton_cef_runtime_active = 0;
static int g_proton_engine_multi_threaded_message_loop = 0;
static int g_proton_engine_app_initialized = 0;
static int g_proton_engine_factory_initialized = 0;
static int g_proton_engine_window_lock_initialized = 0;
static proton_engine_app_t g_proton_engine_app;
static proton_engine_browser_process_handler_t
    g_proton_engine_browser_process_handler;
static proton_engine_render_process_handler_t
    g_proton_engine_render_process_handler;
static proton_engine_v8_handler_t g_proton_engine_v8_handler;
static proton_engine_load_handler_t g_proton_engine_load_handler;
static proton_engine_drag_handler_t g_proton_engine_drag_handler;
static proton_engine_request_handler_t g_proton_engine_request_handler;
static proton_engine_scheme_factory_t g_proton_engine_scheme_factory;
static CRITICAL_SECTION g_proton_engine_window_lock;
static proton_engine_window_t *g_proton_engine_windows;
static proton_engine_bridge_pending_t *g_proton_engine_bridge_pending;
static char g_proton_engine_resources_dir[PROTON_ENGINE_MAX_PATH_BYTES];
static char g_proton_engine_locales_dir[PROTON_ENGINE_MAX_PATH_BYTES];
static volatile LONG64 g_proton_engine_scheduled_pump_delay_ms = -1;
static volatile LONG g_proton_engine_runtime_wait_log_count = 0;
static HANDLE g_proton_engine_pump_event = NULL;

static void CEF_CALLBACK proton_engine_on_loading_state_change(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    int isLoading,
    int canGoBack,
    int canGoForward);
static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_transition_type_t transition_type);
static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode);
static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_errorcode_t errorCode,
    const cef_string_t *errorText,
    const cef_string_t *failedUrl);
static void CEF_CALLBACK proton_engine_on_draggable_regions_changed(
    cef_drag_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    size_t regions_count,
    const cef_draggable_region_t *regions);
static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string);

static void proton_engine_log_to_env(const char *env_name,
                                     const char *format,
                                     va_list args) {
  char path[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  DWORD written = GetEnvironmentVariableA(env_name, path, (DWORD)sizeof(path));
  if (written == 0 || written >= sizeof(path)) {
    return;
  }
  FILE *file = fopen(path, "ab");
  if (file == NULL) {
    return;
  }
  vfprintf(file, format, args);
  fputc('\n', file);
  fclose(file);
}

static void proton_engine_debug_log(const char *format, ...) {
  va_list args;
  va_start(args, format);
  proton_engine_log_to_env("PROTON_NATIVE_LOG", format, args);
  va_end(args);
}

static void proton_engine_verbose_log(const char *format, ...) {
  va_list args;
  va_start(args, format);
  proton_engine_log_to_env("PROTON_NATIVE_LOG_VERBOSE", format, args);
  va_end(args);
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

static void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
  InterlockedExchange64(&g_proton_engine_scheduled_pump_delay_ms,
                        (LONG64)delay_ms);
  if (g_proton_engine_pump_event != NULL && delay_ms <= 0) {
    SetEvent(g_proton_engine_pump_event);
  }
}

static void proton_engine_reset_scheduled_pump(void) {
  InterlockedExchange64(&g_proton_engine_scheduled_pump_delay_ms, -1);
  if (g_proton_engine_pump_event != NULL) {
    ResetEvent(g_proton_engine_pump_event);
  }
}

static void proton_engine_log_runtime_wait_ready(uint32_t ready_mask,
                                                 uint32_t interest_mask) {
  LONG count = InterlockedIncrement(&g_proton_engine_runtime_wait_log_count);
  if (count <= 16) {
    proton_engine_debug_log("runtime_wait ready mask=%u interest=%u",
                            ready_mask, interest_mask);
  }
}

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
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

static bool proton_engine_path_basename_equals(const char *path,
                                               const char *name) {
  if (path == NULL || name == NULL) {
    return false;
  }
  const char *base = path;
  for (const char *cursor = path; *cursor != '\0'; cursor++) {
    if (*cursor == '/' || *cursor == '\\') {
      base = cursor + 1;
    }
  }
  return _stricmp(base, name) == 0;
}

static bool proton_engine_module_dir(char *out, size_t out_len) {
  if (out == NULL || out_len == 0) {
    return false;
  }
  HMODULE module = NULL;
  if (!GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          (LPCSTR)&proton_engine_module_dir, &module)) {
    return false;
  }
  DWORD written = GetModuleFileNameA(module, out, (DWORD)out_len);
  if (written == 0 || written >= out_len) {
    return false;
  }
  return proton_engine_path_parent(out);
}

static bool proton_engine_default_runtime_root(char *out, size_t out_len) {
  if (!proton_engine_module_dir(out, out_len)) {
    return false;
  }
  if (proton_engine_path_basename_equals(out, "bin")) {
    return proton_engine_path_parent(out);
  }
  return true;
}

static bool proton_engine_default_helper_path(char *out, size_t out_len) {
  char bin_dir[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  if (!proton_engine_module_dir(bin_dir, sizeof(bin_dir))) {
    return false;
  }
  return proton_engine_join_path(out, out_len, bin_dir, "cef_process.exe");
}

#include "../cef_common/strings.h"
#include "../cef_common/assets.h"
#include "../cef_common/json_fields.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) ((refs)->refs)
#define PROTON_ENGINE_REF_STORE(refs, value) ((refs)->refs = (value))
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../cef_common/bridge_json.h"

static void proton_engine_init_window_lock(void) {
  if (!g_proton_engine_window_lock_initialized) {
    InitializeCriticalSection(&g_proton_engine_window_lock);
    g_proton_engine_window_lock_initialized = 1;
  }
}

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_init_window_lock();
  EnterCriticalSection(&g_proton_engine_window_lock);
  window->next = g_proton_engine_windows;
  g_proton_engine_windows = window;
  LeaveCriticalSection(&g_proton_engine_window_lock);
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
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

static void proton_engine_runtime_bridge_lock(proton_engine_runtime_t *runtime) {
  if (runtime != NULL && runtime->bridge_lock_initialized) {
    EnterCriticalSection(&runtime->bridge_lock);
  }
}

static void proton_engine_runtime_bridge_unlock(
    proton_engine_runtime_t *runtime) {
  if (runtime != NULL && runtime->bridge_lock_initialized) {
    LeaveCriticalSection(&runtime->bridge_lock);
  }
}

static void proton_engine_runtime_sync_bridge_event_locked(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL || runtime->bridge_event == NULL) {
    return;
  }
  if (runtime->bridge_count > 0) {
    SetEvent(runtime->bridge_event);
  } else {
    ResetEvent(runtime->bridge_event);
  }
}

static int proton_engine_runtime_has_bridge_request(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  int has_request = 0;
  proton_engine_runtime_bridge_lock(runtime);
  has_request = runtime->bridge_count > 0;
  proton_engine_runtime_sync_bridge_event_locked(runtime);
  proton_engine_runtime_bridge_unlock(runtime);
  return has_request;
}

static int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime,
    char *request_json) {
  if (runtime == NULL || request_json == NULL) {
    return 0;
  }
  int ok = 0;
  proton_engine_runtime_bridge_lock(runtime);
  if (runtime->bridge_count < PROTON_ENGINE_MAX_BRIDGE_REQUESTS) {
    size_t index =
        (runtime->bridge_head + runtime->bridge_count) %
        PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
    runtime->bridge_queue[index] = request_json;
    runtime->bridge_count++;
    proton_engine_runtime_sync_bridge_event_locked(runtime);
    ok = 1;
  }
  proton_engine_runtime_bridge_unlock(runtime);
  return ok;
}

static char *proton_engine_runtime_pop_bridge_request(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return NULL;
  }
  char *request_json = NULL;
  proton_engine_runtime_bridge_lock(runtime);
  if (runtime->bridge_count > 0) {
    request_json = runtime->bridge_queue[runtime->bridge_head];
    runtime->bridge_queue[runtime->bridge_head] = NULL;
    runtime->bridge_head =
        (runtime->bridge_head + 1) % PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
    runtime->bridge_count--;
    proton_engine_runtime_sync_bridge_event_locked(runtime);
  }
  proton_engine_runtime_bridge_unlock(runtime);
  return request_json;
}

static size_t proton_engine_runtime_clear_bridge_queue(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  size_t removed = 0;
  proton_engine_runtime_bridge_lock(runtime);
  for (size_t i = 0; i < PROTON_ENGINE_MAX_BRIDGE_REQUESTS; i++) {
    if (runtime->bridge_queue[i] != NULL) {
      removed++;
    }
    free(runtime->bridge_queue[i]);
    runtime->bridge_queue[i] = NULL;
  }
  runtime->bridge_head = 0;
  runtime->bridge_count = 0;
  proton_engine_runtime_sync_bridge_event_locked(runtime);
  proton_engine_runtime_bridge_unlock(runtime);
  proton_engine_debug_log("bridge_queue_clear removed=%llu",
                          (unsigned long long)removed);
  return removed;
}

static int proton_engine_runtime_remove_bridge_request(
    proton_engine_runtime_t *runtime,
    int64_t request_id) {
  if (runtime == NULL) {
    return 0;
  }
  char *kept[PROTON_ENGINE_MAX_BRIDGE_REQUESTS] = {0};
  size_t kept_count = 0;
  int removed = 0;
  proton_engine_runtime_bridge_lock(runtime);
  for (size_t i = 0; i < runtime->bridge_count; i++) {
    size_t index =
        (runtime->bridge_head + i) % PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
    char *request_json = runtime->bridge_queue[index];
    runtime->bridge_queue[index] = NULL;
    int64_t queued_request_id = 0;
    if (request_json != NULL &&
        proton_engine_json_read_int64_field(request_json, "request_id",
                                            &queued_request_id) &&
        queued_request_id == request_id) {
      free(request_json);
      removed++;
      continue;
    }
    if (request_json != NULL && kept_count < PROTON_ENGINE_MAX_BRIDGE_REQUESTS) {
      kept[kept_count++] = request_json;
    }
  }
  runtime->bridge_head = 0;
  runtime->bridge_count = kept_count;
  for (size_t i = 0; i < kept_count; i++) {
    runtime->bridge_queue[i] = kept[i];
  }
  proton_engine_runtime_sync_bridge_event_locked(runtime);
  proton_engine_runtime_bridge_unlock(runtime);
  if (removed > 0) {
    proton_engine_debug_log("bridge_queue_remove request=%lld removed=%d",
                            (long long)request_id, removed);
  }
  return removed;
}

static char *proton_engine_request_url(cef_request_t *request) {
  if (request == NULL) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(request->get_url(request));
}

static int proton_engine_url_is_proton(const char *url) {
  return url != NULL && strncmp(url, "proton://", 9) == 0;
}

static int CEF_CALLBACK proton_engine_html_handler_release(
    cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  LONG value = InterlockedDecrement(&refs->refs);
  if (value <= 0) {
    proton_engine_html_resource_handler_t *handler =
        (proton_engine_html_resource_handler_t *)base;
    free(handler->html);
    free(handler->mime_type);
    free(handler);
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK proton_engine_html_open(
    cef_resource_handler_t *self,
    cef_request_t *request,
    int *handle_request,
    cef_callback_t *callback) {
  (void)self;
  (void)callback;
  char *url = proton_engine_request_url(request);
  proton_engine_verbose_log("html_open url=%s", proton_engine_log_url(url));
  free(url);
  if (handle_request != NULL) {
    *handle_request = 0;
  }
  return 0;
}

static int CEF_CALLBACK proton_engine_html_process_request(
    cef_resource_handler_t *self,
    cef_request_t *request,
    cef_callback_t *callback) {
  (void)self;
  char *url = proton_engine_request_url(request);
  proton_engine_verbose_log("html_process_request url=%s",
                            proton_engine_log_url(url));
  free(url);
  if (callback != NULL) {
    callback->cont(callback);
  }
  return 1;
}

static void CEF_CALLBACK proton_engine_html_get_response_headers(
    cef_resource_handler_t *self,
    cef_response_t *response,
    int64_t *response_length,
    cef_string_t *redirect_url) {
  (void)redirect_url;
  proton_engine_html_resource_handler_t *handler =
      (proton_engine_html_resource_handler_t *)self;
  if (response != NULL) {
    cef_string_t mime = {0};
    cef_string_t charset = {0};
    proton_engine_set_string(&mime, handler->mime_type != NULL
                                        ? handler->mime_type
                                        : "text/html");
    proton_engine_set_string(&charset, "utf-8");
    response->set_status(response, 200);
    response->set_mime_type(response, &mime);
    response->set_charset(response, &charset);
    cef_string_clear(&mime);
    cef_string_clear(&charset);
  }
  if (response_length != NULL) {
    *response_length = -1;
  }
  proton_engine_verbose_log("html_headers length=%llu",
                            (unsigned long long)handler->html_len);
}

static int CEF_CALLBACK proton_engine_html_skip(
    cef_resource_handler_t *self,
    int64_t bytes_to_skip,
    int64_t *bytes_skipped,
    cef_resource_skip_callback_t *callback) {
  (void)callback;
  proton_engine_html_resource_handler_t *handler =
      (proton_engine_html_resource_handler_t *)self;
  if (bytes_to_skip < 0) {
    if (bytes_skipped != NULL) {
      *bytes_skipped = -1;
    }
    return 0;
  }
  size_t remaining = handler->html_len - handler->offset;
  size_t skipped = (size_t)bytes_to_skip;
  if (skipped > remaining) {
    skipped = remaining;
  }
  handler->offset += skipped;
  if (bytes_skipped != NULL) {
    *bytes_skipped = (int64_t)skipped;
  }
  return 1;
}

static int CEF_CALLBACK proton_engine_html_read(
    cef_resource_handler_t *self,
    void *data_out,
    int bytes_to_read,
    int *bytes_read,
    cef_resource_read_callback_t *callback) {
  (void)callback;
  proton_engine_html_resource_handler_t *handler =
      (proton_engine_html_resource_handler_t *)self;
  if (bytes_read != NULL) {
    *bytes_read = 0;
  }
  if (data_out == NULL || bytes_to_read <= 0 ||
      handler->offset >= handler->html_len) {
    proton_engine_verbose_log(
        "html_read eof bytes_to_read=%d offset=%llu len=%llu", bytes_to_read,
        (unsigned long long)handler->offset,
        (unsigned long long)handler->html_len);
    return 0;
  }
  size_t remaining = handler->html_len - handler->offset;
  size_t to_copy = (size_t)bytes_to_read;
  if (to_copy > remaining) {
    to_copy = remaining;
  }
  memcpy(data_out, handler->html + handler->offset, to_copy);
  handler->offset += to_copy;
  if (bytes_read != NULL) {
    *bytes_read = (int)to_copy;
  }
  proton_engine_verbose_log("html_read bytes=%d offset=%llu",
                            bytes_read != NULL ? *bytes_read : 0,
                            (unsigned long long)handler->offset);
  return 1;
}

static int CEF_CALLBACK proton_engine_html_read_response(
    cef_resource_handler_t *self,
    void *data_out,
    int bytes_to_read,
    int *bytes_read,
    cef_callback_t *callback) {
  (void)callback;
  return proton_engine_html_read(self, data_out, bytes_to_read, bytes_read,
                                 NULL);
}

static void CEF_CALLBACK proton_engine_html_cancel(
    cef_resource_handler_t *self) {
  (void)self;
}

static cef_resource_handler_t *proton_engine_html_handler_new(
    const char *html,
    size_t html_len,
    const char *mime_type) {
  proton_engine_html_resource_handler_t *handler =
      (proton_engine_html_resource_handler_t *)calloc(1, sizeof(*handler));
  if (handler == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&handler->handler.base,
      sizeof(handler->handler), &handler->refs);
  handler->handler.base.release = proton_engine_html_handler_release;
  handler->handler.open = proton_engine_html_open;
  handler->handler.process_request = proton_engine_html_process_request;
  handler->handler.get_response_headers =
      proton_engine_html_get_response_headers;
  handler->handler.skip = proton_engine_html_skip;
  handler->handler.read = proton_engine_html_read;
  handler->handler.read_response = proton_engine_html_read_response;
  handler->handler.cancel = proton_engine_html_cancel;
  handler->html = proton_engine_strdup_len(html, html_len);
  handler->mime_type = proton_engine_strdup(mime_type != NULL ? mime_type
                                                              : "text/html");
  if (handler->html == NULL || handler->mime_type == NULL) {
    free(handler->html);
    free(handler->mime_type);
    free(handler);
    return NULL;
  }
  handler->html_len = html_len;
  return &handler->handler;
}

static int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

static cef_resource_handler_t *proton_engine_find_asset_handler(
    int browser_id,
    const char *url) {
  if (browser_id == 0 || url == NULL || !g_proton_engine_window_lock_initialized) {
    return NULL;
  }
  cef_resource_handler_t *handler = NULL;
  EnterCriticalSection(&g_proton_engine_window_lock);
  for (proton_engine_window_t *window = g_proton_engine_windows;
       window != NULL; window = window->next) {
    if (window->browser_id != browser_id) {
      continue;
    }
    if (window->html_url != NULL && strcmp(window->html_url, url) == 0 &&
        window->html != NULL) {
      handler =
          proton_engine_html_handler_new(window->html, window->html_len,
                                         "text/html");
      break;
    }
    char *asset_path = proton_engine_url_to_asset_path(url);
    if (asset_path != NULL) {
      char *html_path = proton_engine_url_to_asset_path(window->html_url);
      char *asset_root = proton_engine_asset_path_dirname(html_path);
      if (proton_engine_asset_path_is_under_root(asset_path, asset_root)) {
        char *data = NULL;
        size_t data_len = 0;
        if (proton_engine_read_asset_file(asset_path, &data, &data_len)) {
          handler = proton_engine_html_handler_new(
              data, data_len, proton_engine_asset_mime_type(asset_path));
          free(data);
        }
      }
      free(asset_root);
      free(html_path);
      free(asset_path);
      break;
    }
  }
  LeaveCriticalSection(&g_proton_engine_window_lock);
  return handler;
}

static proton_engine_window_t *proton_engine_find_window_by_browser_id(
    int browser_id) {
  if (browser_id == 0 || !g_proton_engine_window_lock_initialized) {
    return NULL;
  }
  proton_engine_window_t *found = NULL;
  EnterCriticalSection(&g_proton_engine_window_lock);
  for (proton_engine_window_t *window = g_proton_engine_windows;
       window != NULL; window = window->next) {
    if (window->browser_id == browser_id) {
      found = window;
      break;
    }
  }
  LeaveCriticalSection(&g_proton_engine_window_lock);
  return found;
}

static size_t proton_engine_bridge_pending_count(void) {
  size_t count = 0;
  for (proton_engine_bridge_pending_t *pending =
           g_proton_engine_bridge_pending;
       pending != NULL; pending = pending->next) {
    count++;
  }
  return count;
}

static void proton_engine_bridge_pending_free(
    proton_engine_bridge_pending_t *pending) {
  if (pending == NULL) {
    return;
  }
  if (pending->frame != NULL) {
    pending->frame->base.release((cef_base_ref_counted_t *)pending->frame);
  }
  free(pending->page_instance);
  free(pending);
}

static int proton_engine_bridge_pending_add(int64_t request_id,
                                            int browser_id,
                                            int renderer_pending_id,
                                            const char *page_instance,
                                            cef_frame_t *frame) {
  if (frame == NULL || page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  if (proton_engine_bridge_pending_count() >=
      PROTON_ENGINE_MAX_BRIDGE_PENDING) {
    return 0;
  }
  proton_engine_bridge_pending_t *pending =
      (proton_engine_bridge_pending_t *)calloc(1, sizeof(*pending));
  if (pending == NULL) {
    return 0;
  }
  pending->request_id = request_id;
  pending->browser_id = browser_id;
  pending->renderer_pending_id = renderer_pending_id;
  pending->page_instance = proton_engine_strdup(page_instance);
  if (pending->page_instance == NULL) {
    free(pending);
    return 0;
  }
  frame->base.add_ref((cef_base_ref_counted_t *)frame);
  pending->frame = frame;
  pending->next = g_proton_engine_bridge_pending;
  g_proton_engine_bridge_pending = pending;
  return 1;
}

static void proton_engine_bridge_pending_remove_context(
    proton_engine_runtime_t *runtime,
    int browser_id,
    const char *page_instance) {
  // A stale context release must not cancel requests from its replacement.
  if (page_instance == NULL || page_instance[0] == '\0') {
    return;
  }
  proton_engine_bridge_pending_t **cursor =
      &g_proton_engine_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_remove_bridge_request(runtime, request_id);
      proton_engine_bridge_pending_free(pending);
      continue;
    }
    cursor = &pending->next;
  }
}

static proton_engine_bridge_pending_t *proton_engine_bridge_pending_take(
    int64_t request_id) {
  proton_engine_bridge_pending_t **cursor = &g_proton_engine_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->request_id == request_id) {
      *cursor = pending->next;
      pending->next = NULL;
      return pending;
    }
    cursor = &pending->next;
  }
  return NULL;
}

static void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime,
    int browser_id) {
  proton_engine_bridge_pending_t **cursor = &g_proton_engine_bridge_pending;
  size_t removed_pending = 0;
  int removed_queued = 0;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id) {
      *cursor = pending->next;
      removed_queued += proton_engine_runtime_remove_bridge_request(
          runtime, pending->request_id);
      proton_engine_bridge_pending_free(pending);
      removed_pending++;
      continue;
    }
    cursor = &pending->next;
  }
  proton_engine_debug_log(
      "bridge_pending_remove_browser browser=%d pending=%llu queued=%d",
      browser_id, (unsigned long long)removed_pending, removed_queued);
}

static void proton_engine_bridge_pending_clear_all(void) {
  proton_engine_bridge_pending_t *pending = g_proton_engine_bridge_pending;
  g_proton_engine_bridge_pending = NULL;
  size_t removed = 0;
  while (pending != NULL) {
    proton_engine_bridge_pending_t *next = pending->next;
    proton_engine_bridge_pending_free(pending);
    pending = next;
    removed++;
  }
  proton_engine_debug_log("bridge_pending_clear_all removed=%llu",
                          (unsigned long long)removed);
}

static int proton_engine_send_bridge_response_to_frame(
    cef_frame_t *frame,
    int renderer_pending_id,
    int ok,
    const char *payload_json,
    const char *error_message) {
  if (frame == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name, PROTON_ENGINE_BRIDGE_RESPONSE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 4);
  args->set_int(args, 0, renderer_pending_id);
  args->set_bool(args, 1, ok ? 1 : 0);
  cef_string_t payload = {0};
  cef_string_t error = {0};
  proton_engine_set_string(&payload, payload_json != NULL ? payload_json : "null");
  proton_engine_set_string(&error, error_message != NULL ? error_message : "");
  args->set_string(args, 2, &payload);
  args->set_string(args, 3, &error);
  cef_string_clear(&payload);
  cef_string_clear(&error);
  frame->send_process_message(frame, PID_RENDERER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

static void proton_engine_reject_renderer_request(cef_frame_t *frame,
                                                  int renderer_pending_id,
                                                  const char *message) {
  (void)proton_engine_send_bridge_response_to_frame(
      frame, renderer_pending_id, 0, "null",
      message != NULL ? message : "bridge request rejected");
}

static cef_resource_handler_t *CEF_CALLBACK proton_engine_scheme_create(
    cef_scheme_handler_factory_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    const cef_string_t *scheme_name,
    cef_request_t *request) {
  (void)self;
  (void)frame;
  (void)scheme_name;
  char *url = proton_engine_request_url(request);
  cef_resource_handler_t *handler =
      proton_engine_find_asset_handler(proton_engine_browser_id(browser), url);
  proton_engine_verbose_log("scheme_create browser=%d url=%s handler=%d",
                            proton_engine_browser_id(browser),
                            proton_engine_log_url(url), handler != NULL);
  free(url);
  return handler;
}

static void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar) {
  (void)self;
  if (registrar == NULL) {
    return;
  }
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  registrar->add_custom_scheme(
      registrar, &scheme, CEF_SCHEME_OPTION_SECURE | CEF_SCHEME_OPTION_FETCH_ENABLED);
  cef_string_clear(&scheme);
}

static void proton_engine_init_scheme_factory(void) {
  if (g_proton_engine_factory_initialized) {
    return;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_scheme_factory.factory.base,
      sizeof(g_proton_engine_scheme_factory.factory),
      &g_proton_engine_scheme_factory.refs);
  g_proton_engine_scheme_factory.factory.create = proton_engine_scheme_create;
  g_proton_engine_factory_initialized = 1;
}

static int proton_engine_register_scheme_factory(void) {
  proton_engine_init_scheme_factory();
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  int ok = cef_register_scheme_handler_factory(
      &scheme, NULL, &g_proton_engine_scheme_factory.factory);
  cef_string_clear(&scheme);
  return ok;
}

static void proton_engine_append_switch(cef_command_line_t *command_line,
                                        const char *name) {
  cef_string_t switch_name = {0};
  proton_engine_set_string(&switch_name, name);
  command_line->append_switch(command_line, &switch_name);
  cef_string_clear(&switch_name);
}

static void proton_engine_append_switch_with_value(
    cef_command_line_t *command_line,
    const char *name,
    const char *value) {
  if (value == NULL || value[0] == '\0') {
    return;
  }
  cef_string_t switch_name = {0};
  cef_string_t switch_value = {0};
  proton_engine_set_string(&switch_name, name);
  proton_engine_set_string(&switch_value, value);
  command_line->append_switch_with_value(command_line, &switch_name,
                                         &switch_value);
  cef_string_clear(&switch_name);
  cef_string_clear(&switch_value);
}

static char *proton_engine_v8_value_to_utf8(cef_v8_value_t *value) {
  if (value == NULL || !value->is_string(value)) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(value->get_string_value(value));
}

static int proton_engine_send_bridge_request_to_browser(
    cef_frame_t *frame,
    int pending_id,
    const char *op,
    const char *payload_json,
    const char *page_instance) {
  if (frame == NULL || op == NULL || payload_json == NULL ||
      page_instance == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 4);
  args->set_int(args, 0, pending_id);
  cef_string_t op_value = {0};
  cef_string_t payload_value = {0};
  cef_string_t page_instance_value = {0};
  proton_engine_set_string(&op_value, op);
  proton_engine_set_string(&payload_value, payload_json);
  proton_engine_set_string(&page_instance_value, page_instance);
  args->set_string(args, 1, &op_value);
  args->set_string(args, 2, &payload_value);
  args->set_string(args, 3, &page_instance_value);
  cef_string_clear(&op_value);
  cef_string_clear(&payload_value);
  cef_string_clear(&page_instance_value);
  frame->send_process_message(frame, PID_BROWSER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

static int CEF_CALLBACK proton_engine_v8_execute(
    cef_v8_handler_t *self,
    const cef_string_t *name,
    cef_v8_value_t *object,
    size_t argumentsCount,
    cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval,
    cef_string_t *exception) {
  (void)self;
  (void)object;
  char *function_name = proton_engine_cef_string_to_utf8(name);
  int handled = function_name != NULL &&
                strcmp(function_name, PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION) == 0;
  proton_engine_verbose_log("v8_execute name=%s handled=%d argc=%llu",
                            function_name != NULL ? function_name : "",
                            handled, (unsigned long long)argumentsCount);
  free(function_name);
  if (!handled) {
    return 0;
  }
  if (retval != NULL) {
    *retval = NULL;
  }
  if (argumentsCount < 4 || arguments[0] == NULL ||
      !arguments[0]->is_int(arguments[0])) {
    proton_engine_set_string(exception,
                             "invokeOp requires pending id, name, payload and page instance");
    return 1;
  }
  int pending_id = arguments[0]->get_int_value(arguments[0]);
  char *op = proton_engine_v8_value_to_utf8(arguments[1]);
  char *payload_json = proton_engine_v8_value_to_utf8(arguments[2]);
  char *page_instance = proton_engine_v8_value_to_utf8(arguments[3]);
  if (!proton_engine_bridge_op_is_valid(op) ||
      !proton_engine_bridge_payload_is_valid(
          payload_json, PROTON_ENGINE_MAX_BRIDGE_BYTES) ||
      page_instance == NULL || page_instance[0] == '\0' ||
      strlen(page_instance) >= PROTON_ENGINE_MAX_BRIDGE_OP_BYTES) {
    proton_engine_debug_log(
        "bridge_reject_invalid_renderer pending=%d op=%s payload_bytes=%llu",
        pending_id, op != NULL ? op : "",
        (unsigned long long)(payload_json != NULL ? strlen(payload_json) : 0));
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "invalid bridge request");
    return 1;
  }
  cef_v8_context_t *context = cef_v8_context_get_current_context();
  if (context == NULL) {
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "no current V8 context");
    return 1;
  }
  cef_browser_t *browser = context->get_browser(context);
  cef_frame_t *frame = context->get_frame(context);
  if (browser == NULL || frame == NULL) {
    if (browser != NULL) {
      browser->base.release((cef_base_ref_counted_t *)browser);
    }
    if (frame != NULL) {
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
    context->base.release((cef_base_ref_counted_t *)context);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "bridge requires a browser frame");
    return 1;
  }
  int browser_id = proton_engine_browser_id(browser);
  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  proton_engine_verbose_log("v8_invoke_frame browser=%d url=%s", browser_id,
                            proton_engine_log_url(frame_url));
  if (!proton_engine_url_is_bridge_candidate(frame_url)) {
    browser->base.release((cef_base_ref_counted_t *)browser);
    frame->base.release((cef_base_ref_counted_t *)frame);
    context->base.release((cef_base_ref_counted_t *)context);
    free(op);
    free(payload_json);
    free(page_instance);
    free(frame_url);
    proton_engine_set_string(exception,
                             "bridge is not available for this page");
    return 1;
  }
  free(frame_url);
  int ok = proton_engine_send_bridge_request_to_browser(
      frame, pending_id, op, payload_json, page_instance);
  proton_engine_verbose_log("v8_invoke pending=%d browser=%d ok=%d op=%s",
                            pending_id, browser_id, ok, op != NULL ? op : "");
  if (!ok) {
    proton_engine_set_string(exception, "failed to send bridge request");
  }
  browser->base.release((cef_base_ref_counted_t *)browser);
  frame->base.release((cef_base_ref_counted_t *)frame);
  context->base.release((cef_base_ref_counted_t *)context);
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
}

static void CEF_CALLBACK proton_engine_on_web_kit_initialized(
    cef_render_process_handler_t *self) {
  (void)self;
  proton_engine_verbose_log("bridge_extension_register skipped");
}

static void CEF_CALLBACK proton_engine_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  (void)self;
  proton_engine_bridge_renderer_on_context_created(
      browser, frame, context, &g_proton_engine_v8_handler.handler);
}

static void CEF_CALLBACK proton_engine_on_context_released(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  (void)self;
  proton_engine_bridge_renderer_on_context_released(browser, frame, context);
}

static int CEF_CALLBACK proton_engine_renderer_on_process_message_received(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  (void)self;
  return proton_engine_bridge_renderer_on_process_message_received(
      browser, frame, source_process, message);
}

static cef_render_process_handler_t *CEF_CALLBACK
proton_engine_get_render_process_handler(cef_app_t *self) {
  (void)self;
  return &g_proton_engine_render_process_handler.handler;
}

static int CEF_CALLBACK proton_engine_client_on_process_message_received(
    cef_client_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  (void)self;
  if (source_process != PID_RENDERER || browser == NULL || frame == NULL ||
      message == NULL) {
    return 0;
  }
  char *message_name =
      proton_engine_userfree_to_utf8(message->get_name(message));
  int is_request =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE) == 0;
  int is_context_disposed =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_CONTEXT_DISPOSED_MESSAGE) == 0;
  int is_lifecycle =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_LIFECYCLE_MESSAGE) == 0;
  free(message_name);
  int browser_id = proton_engine_browser_id(browser);
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(browser_id);
  if (is_lifecycle) {
    cef_list_value_t *args = message->get_argument_list(message);
    if (window != NULL && frame->is_main(frame) && args != NULL &&
        args->get_size(args) >= 4) {
      char *outcome = proton_engine_userfree_to_utf8(args->get_string(args, 0));
      char *page_instance =
          proton_engine_userfree_to_utf8(args->get_string(args, 1));
      char *url = proton_engine_userfree_to_utf8(args->get_string(args, 2));
      char *diagnostic =
          proton_engine_userfree_to_utf8(args->get_string(args, 3));
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      char *current_url =
          main_frame != NULL
              ? proton_engine_userfree_to_utf8(main_frame->get_url(main_frame))
              : NULL;
      if (url != NULL && current_url != NULL && strcmp(url, current_url) == 0) {
        proton_engine_bridge_lifecycle_update(
            &window->bridge_lifecycle, outcome, page_instance, current_url,
            diagnostic != NULL && diagnostic[0] != '\0' ? diagnostic : NULL);
      }
      free(current_url);
      if (main_frame != NULL) {
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
      free(outcome);
      free(page_instance);
      free(url);
      free(diagnostic);
      if (g_proton_engine_pump_event != NULL) {
        SetEvent(g_proton_engine_pump_event);
      }
    }
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  if (is_context_disposed) {
    cef_list_value_t *args = message->get_argument_list(message);
    char *page_instance = args != NULL && args->get_size(args) >= 1
                              ? proton_engine_userfree_to_utf8(
                                    args->get_string(args, 0))
                              : NULL;
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    proton_engine_bridge_pending_remove_context(
        window != NULL ? window->runtime : NULL, browser_id, page_instance);
    free(page_instance);
    proton_engine_debug_log("browser_bridge_context_disposed browser=%d",
                            browser_id);
    return 1;
  }
  if (!is_request) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL || args->get_size(args) < 4) {
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  int renderer_pending_id = args->get_int(args, 0);
  char *op = proton_engine_userfree_to_utf8(args->get_string(args, 1));
  char *payload_json = proton_engine_userfree_to_utf8(args->get_string(args, 2));
  char *page_instance =
      proton_engine_userfree_to_utf8(args->get_string(args, 3));
  args->base.release((cef_base_ref_counted_t *)args);
  proton_engine_verbose_log("browser_bridge_request browser=%d pending=%d op=%s",
                            proton_engine_browser_id(browser),
                            renderer_pending_id, op != NULL ? op : "");

  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  int page_allowed =
      window != NULL && window->bridge_config_json != NULL &&
      proton_engine_bridge_config_allows_page(window->bridge_config_json,
                                              frame_url);
  if (window == NULL || window->runtime == NULL ||
      window->bridge_config_json == NULL || !page_allowed) {
    proton_engine_debug_log(
        "bridge_reject_origin_not_allowed browser=%d pending=%d url=%s",
        browser_id, renderer_pending_id, proton_engine_log_url(frame_url));
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge origin is not allowed");
    free(frame_url);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(frame_url);
  if (!proton_engine_bridge_config_allows_op(window->bridge_config_json, op)) {
    proton_engine_debug_log("bridge_reject_not_allowed browser=%d pending=%d op=%s",
                            browser_id, renderer_pending_id,
                            op != NULL ? op : "");
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge op is not allowed");
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  if (!proton_engine_bridge_payload_is_valid(
          payload_json, window->max_bridge_payload_bytes) ||
      page_instance == NULL || page_instance[0] == '\0' ||
      strlen(page_instance) >= PROTON_ENGINE_MAX_BRIDGE_OP_BYTES) {
    proton_engine_debug_log("bridge_reject_payload_too_large browser=%d pending=%d op=%s",
                            browser_id, renderer_pending_id,
                            op != NULL ? op : "");
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge payload is too large");
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }

  int64_t request_id = window->runtime->next_bridge_request_id++;
  if (window->runtime->next_bridge_request_id <= 0) {
    window->runtime->next_bridge_request_id = 1;
  }
  size_t request_len =
      strlen(op) + strlen(payload_json) + strlen(page_instance) + 256;
  char *request_json = (char *)malloc(request_len);
  if (request_json == NULL) {
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "failed to allocate bridge request");
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  snprintf(request_json, request_len,
           "{\"abi_version\":1,\"request_id\":\"%lld\",\"window\":\"%lld\","
           "\"op\":\"%s\",\"payload\":%s,\"page_instance\":\"%s\"}",
           (long long)request_id, (long long)window->public_window_id, op,
           payload_json, page_instance);
  if (!proton_engine_bridge_pending_add(request_id, browser_id,
                                        renderer_pending_id, page_instance,
                                        frame) ||
      !proton_engine_runtime_enqueue_bridge_request(window->runtime,
                                                   request_json)) {
    proton_engine_bridge_pending_t *pending =
        proton_engine_bridge_pending_take(request_id);
    proton_engine_bridge_pending_free(pending);
    free(request_json);
    proton_engine_debug_log("bridge_reject_queue_full browser=%d pending=%d op=%s",
                            browser_id, renderer_pending_id,
                            op != NULL ? op : "");
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge request queue is full");
  } else {
    proton_engine_debug_log(
        "bridge_enqueue request=%lld browser=%d pending=%d op=%s",
        (long long)request_id, browser_id, renderer_pending_id,
        op != NULL ? op : "");
  }
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
}

static void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  (void)process_type;
  if (command_line == NULL) {
    return;
  }
  proton_engine_append_switch(command_line, "disable-gpu");
  proton_engine_append_switch(command_line, "disable-background-networking");
  proton_engine_append_switch(command_line, "disable-component-update");
  proton_engine_append_switch(command_line, "disable-domain-reliability");
  proton_engine_append_switch(command_line, "disable-sync");
  proton_engine_append_switch(command_line, "metrics-recording-only");
  proton_engine_append_switch(command_line, "safebrowsing-disable-auto-update");
  proton_engine_append_switch_with_value(command_line, "resources-dir-path",
                                         g_proton_engine_resources_dir);
  proton_engine_append_switch_with_value(command_line, "locales-dir-path",
                                         g_proton_engine_locales_dir);
}

static void CEF_CALLBACK proton_engine_on_schedule_message_pump_work(
    cef_browser_process_handler_t *self,
    int64_t delay_ms) {
  (void)self;
  proton_engine_set_scheduled_pump_delay_ms(delay_ms);
}

static cef_browser_process_handler_t *CEF_CALLBACK
proton_engine_get_browser_process_handler(cef_app_t *self) {
  (void)self;
  return &g_proton_engine_browser_process_handler.handler;
}

static void proton_engine_init_app(void) {
  if (g_proton_engine_app_initialized) {
    return;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_app.app.base,
      sizeof(g_proton_engine_app.app), &g_proton_engine_app.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)
          &g_proton_engine_browser_process_handler.handler.base,
      sizeof(g_proton_engine_browser_process_handler.handler),
      &g_proton_engine_browser_process_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)
          &g_proton_engine_render_process_handler.handler.base,
      sizeof(g_proton_engine_render_process_handler.handler),
      &g_proton_engine_render_process_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_v8_handler.handler.base,
      sizeof(g_proton_engine_v8_handler.handler),
      &g_proton_engine_v8_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_load_handler.handler.base,
      sizeof(g_proton_engine_load_handler.handler),
      &g_proton_engine_load_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_drag_handler.handler.base,
      sizeof(g_proton_engine_drag_handler.handler),
      &g_proton_engine_drag_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_request_handler.handler.base,
      sizeof(g_proton_engine_request_handler.handler),
      &g_proton_engine_request_handler.refs);
  g_proton_engine_browser_process_handler.handler.on_schedule_message_pump_work =
      proton_engine_on_schedule_message_pump_work;
  g_proton_engine_render_process_handler.handler.on_web_kit_initialized =
      proton_engine_on_web_kit_initialized;
  g_proton_engine_render_process_handler.handler.on_context_created =
      proton_engine_on_context_created;
  g_proton_engine_render_process_handler.handler.on_context_released =
      proton_engine_on_context_released;
  g_proton_engine_render_process_handler.handler.on_browser_created =
      proton_engine_bridge_renderer_on_browser_created;
  g_proton_engine_render_process_handler.handler.on_browser_destroyed =
      proton_engine_bridge_renderer_on_browser_destroyed;
  g_proton_engine_render_process_handler.handler.on_process_message_received =
      proton_engine_renderer_on_process_message_received;
  g_proton_engine_v8_handler.handler.execute = proton_engine_v8_execute;
  g_proton_engine_load_handler.handler.on_loading_state_change =
      proton_engine_on_loading_state_change;
  g_proton_engine_load_handler.handler.on_load_start =
      proton_engine_on_load_start;
  g_proton_engine_load_handler.handler.on_load_end = proton_engine_on_load_end;
  g_proton_engine_load_handler.handler.on_load_error =
      proton_engine_on_load_error;
  g_proton_engine_drag_handler.handler.on_draggable_regions_changed =
      proton_engine_on_draggable_regions_changed;
  g_proton_engine_request_handler.handler.on_render_process_terminated =
      proton_engine_on_render_process_terminated;
  g_proton_engine_app.app.on_before_command_line_processing =
      proton_engine_on_before_command_line_processing;
  g_proton_engine_app.app.on_register_custom_schemes =
      proton_engine_on_register_custom_schemes;
  g_proton_engine_app.app.get_browser_process_handler =
      proton_engine_get_browser_process_handler;
  g_proton_engine_app.app.get_render_process_handler =
      proton_engine_get_render_process_handler;
  g_proton_engine_app_initialized = 1;
}

static void proton_engine_check_cef_api_hash(void) {
#ifdef CEF_API_VERSION
  (void)cef_api_hash(CEF_API_VERSION, 0);
#else
  (void)cef_api_hash(0);
#endif
}

static void proton_engine_set_command_line_paths(
    const proton_engine_runtime_config_t *config) {
  if (config == NULL) {
    g_proton_engine_resources_dir[0] = '\0';
    g_proton_engine_locales_dir[0] = '\0';
    return;
  }
  snprintf(g_proton_engine_resources_dir, sizeof(g_proton_engine_resources_dir),
           "%s", config->resources_dir);
  snprintf(g_proton_engine_locales_dir, sizeof(g_proton_engine_locales_dir),
           "%s", config->locales_dir);
}

static int32_t proton_engine_parse_runtime_config(
    const char *config_json,
    proton_engine_runtime_config_t *config,
    char *error,
    size_t error_len) {
  if (config_json == NULL || config == NULL) {
    proton_engine_set_message(error, error_len, "runtime config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(config, 0, sizeof(*config));
  bool use_bundled = false;
  proton_engine_parse_json_bool_field(config_json, "use_bundled",
                                      &use_bundled);
  if (!proton_engine_parse_json_string_field(config_json, "runtime_root",
                                             config->runtime_root,
                                             sizeof(config->runtime_root)) &&
      !(use_bundled &&
        proton_engine_default_runtime_root(config->runtime_root,
                                           sizeof(config->runtime_root)))) {
    proton_engine_set_message(error, error_len,
                              "runtime config requires runtime_root");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_parse_json_string_field(config_json, "helper_path",
                                             config->helper_path,
                                             sizeof(config->helper_path)) &&
      !proton_engine_parse_json_string_field(config_json, "subprocess_path",
                                             config->helper_path,
                                             sizeof(config->helper_path)) &&
      !(use_bundled &&
        proton_engine_default_helper_path(config->helper_path,
                                          sizeof(config->helper_path)))) {
    proton_engine_set_message(error, error_len,
                              "runtime config requires helper_path");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_parse_json_string_field(config_json, "resources_dir",
                                             config->resources_dir,
                                             sizeof(config->resources_dir)) &&
      !proton_engine_join_path(config->resources_dir,
                               sizeof(config->resources_dir),
                               config->runtime_root, "Resources")) {
    proton_engine_set_message(error, error_len,
                              "runtime resources_dir is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_parse_json_string_field(config_json, "locales_dir",
                                             config->locales_dir,
                                             sizeof(config->locales_dir)) &&
      !proton_engine_join_path(config->locales_dir, sizeof(config->locales_dir),
                               config->resources_dir, "locales")) {
    proton_engine_set_message(error, error_len,
                              "runtime locales_dir is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_parse_json_string_field(config_json, "cache_dir",
                                        config->cache_dir,
                                        sizeof(config->cache_dir));
  proton_engine_parse_json_int_field(config_json, "remote_debugging_port",
                                     &config->remote_debugging_port);
  return PROTON_OK;
}

static int proton_engine_utf8_to_wide(const char *value,
                                      wchar_t *buffer,
                                      int buffer_len) {
  if (buffer == NULL || buffer_len <= 0) {
    return 0;
  }
  if (value == NULL || value[0] == '\0') {
    value = "Proton";
  }
  int written = MultiByteToWideChar(CP_UTF8, 0, value, -1, buffer, buffer_len);
  if (written <= 0) {
    buffer[0] = L'\0';
    return 0;
  }
  return written;
}

static void proton_engine_browser_add_ref(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.add_ref((cef_base_ref_counted_t *)browser);
  }
}

static void proton_engine_browser_release(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static int proton_engine_overlay_frame_top_thickness(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

static int proton_engine_overlay_caption_band_height(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  return proton_engine_overlay_frame_top_thickness(hwnd) +
         GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
}

static int proton_engine_overlay_caption_buttons_rect(HWND hwnd, RECT *out) {
  if (hwnd == NULL || out == NULL) {
    return 0;
  }
  TITLEBARINFOEX info;
  memset(&info, 0, sizeof(info));
  info.cbSize = sizeof(info);
  SendMessageW(hwnd, WM_GETTITLEBARINFOEX, 0, (LPARAM)&info);

  const int indices[] = {2, 3, 5};
  RECT cluster = {0};
  int found = 0;
  for (size_t i = 0; i < sizeof(indices) / sizeof(indices[0]); i++) {
    RECT rect = info.rgrect[indices[i]];
    if (rect.right <= rect.left || rect.bottom <= rect.top) {
      continue;
    }
    if (!found) {
      cluster = rect;
      found = 1;
    } else {
      cluster.left = min(cluster.left, rect.left);
      cluster.top = min(cluster.top, rect.top);
      cluster.right = max(cluster.right, rect.right);
      cluster.bottom = max(cluster.bottom, rect.bottom);
    }
  }
  if (!found) {
    return 0;
  }

  POINT top_left = {cluster.left, cluster.top};
  POINT bottom_right = {cluster.right, cluster.bottom};
  if (!ScreenToClient(hwnd, &top_left) ||
      !ScreenToClient(hwnd, &bottom_right)) {
    return 0;
  }
  out->left = top_left.x;
  out->top = top_left.y;
  out->right = bottom_right.x;
  out->bottom = bottom_right.y;
  return out->right > out->left && out->bottom > out->top;
}

static void proton_engine_overlay_apply_frame(HWND hwnd) {
  const BOOL use_dark_caption = TRUE;
  (void)DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                              &use_dark_caption,
                              sizeof(use_dark_caption));
  MARGINS margins = {
      .cxLeftWidth = 0,
      .cxRightWidth = 0,
      .cyTopHeight = proton_engine_overlay_caption_band_height(hwnd),
      .cyBottomHeight = 0,
  };
  (void)DwmExtendFrameIntoClientArea(hwnd, &margins);
}

static int proton_engine_overlay_drag_strip_rect(HWND hwnd, RECT *out) {
  if (hwnd == NULL || out == NULL) {
    return 0;
  }

  RECT client;
  RECT window_rect;
  if (!GetClientRect(hwnd, &client) || !GetWindowRect(hwnd, &window_rect)) {
    return 0;
  }

  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  const int padded_border =
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border;
  const int caption_height = GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
  int drag_handle_width = GetSystemMetricsForDpi(SM_CXSIZE, dpi);

  RECT caption_buttons;
  const int has_caption_buttons =
      proton_engine_overlay_caption_buttons_rect(hwnd, &caption_buttons);
  if (has_caption_buttons) {
    const int live_caption_button_width =
        (caption_buttons.right - caption_buttons.left) / 3;
    if (live_caption_button_width > 0) {
      drag_handle_width = live_caption_button_width;
    }
  }

  POINT client_origin = {0, 0};
  if (!ClientToScreen(hwnd, &client_origin)) {
    return 0;
  }
  const int client_top = client_origin.y - window_rect.top;
  const int drag_top_in_window = IsZoomed(hwnd) ? client_top : resize_border_y;

  out->left = client.left;
  out->right = min(client.right, client.left + drag_handle_width);
  out->top = max(client.top, drag_top_in_window - client_top);
  out->bottom = has_caption_buttons
                    ? min(client.bottom, caption_buttons.bottom)
                    : min(client.bottom, out->top + caption_height);
  return out->right > out->left && out->bottom > out->top;
}

static void proton_engine_overlay_subtract_rect(HRGN destination,
                                                const RECT *rect) {
  if (destination == NULL || rect == NULL || rect->right <= rect->left ||
      rect->bottom <= rect->top) {
    return;
  }
  HRGN region =
      CreateRectRgn(rect->left, rect->top, rect->right, rect->bottom);
  if (region != NULL) {
    CombineRgn(destination, destination, region, RGN_DIFF);
    DeleteObject(region);
  }
}

static LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam);

static LRESULT CALLBACK proton_engine_overlay_child_proc(
    HWND hwnd,
    UINT msg,
    WPARAM wparam,
    LPARAM lparam,
    UINT_PTR subclass_id,
    DWORD_PTR ref_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)ref_data;
  if (msg == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, proton_engine_overlay_child_proc, subclass_id);
    return DefSubclassProc(hwnd, msg, wparam, lparam);
  }
  if (window == NULL || !window->titlebar_overlay || window->hwnd == NULL ||
      !IsWindow(window->hwnd)) {
    return DefSubclassProc(hwnd, msg, wparam, lparam);
  }

  if (msg == WM_PARENTNOTIFY && LOWORD(wparam) == WM_CREATE) {
    HWND child = (HWND)lparam;
    if (child != NULL) {
      SetWindowSubclass(child, proton_engine_overlay_child_proc, subclass_id,
                        ref_data);
    }
  }

  if (msg == WM_NCHITTEST) {
    LRESULT hit = proton_engine_overlay_hit_test(window->hwnd, lparam);
    if (hit != HTCLIENT && hit != HTNOWHERE) {
      return hit;
    }
  } else if ((msg == WM_NCLBUTTONDOWN || msg == WM_NCLBUTTONUP ||
              msg == WM_NCLBUTTONDBLCLK || msg == WM_NCRBUTTONDOWN ||
              msg == WM_NCRBUTTONUP || msg == WM_NCRBUTTONDBLCLK) &&
             wparam != HTCLIENT && wparam != HTNOWHERE) {
    return SendMessageW(window->hwnd, msg, wparam, lparam);
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

static BOOL CALLBACK proton_engine_overlay_subclass_descendant(HWND hwnd,
                                                               LPARAM data) {
  if (!SetWindowSubclass(hwnd, proton_engine_overlay_child_proc, 1,
                         (DWORD_PTR)data)) {
    proton_engine_verbose_log("overlay_subclass_failed hwnd=%p error=%lu",
                              (void *)hwnd, GetLastError());
  }
  return TRUE;
}

static void proton_engine_overlay_subclass_browser(
    proton_engine_window_t *window,
    HWND browser_hwnd) {
  if (window == NULL || browser_hwnd == NULL || !window->titlebar_overlay) {
    return;
  }
  if (!SetWindowSubclass(browser_hwnd, proton_engine_overlay_child_proc, 1,
                         (DWORD_PTR)window)) {
    proton_engine_verbose_log("overlay_subclass_failed hwnd=%p error=%lu",
                              (void *)browser_hwnd, GetLastError());
  }
  EnumChildWindows(browser_hwnd, proton_engine_overlay_subclass_descendant,
                   (LPARAM)window);
}

static void proton_engine_resize_browser(proton_engine_window_t *window,
                                         int width,
                                         int height) {
  if (window == NULL || window->browser == NULL) {
    return;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    return;
  }
  HWND child = host->get_window_handle(host);
  if (child != NULL) {
    SetWindowPos(child, NULL, 0, 0, width, height, SWP_NOZORDER);
    if (window->titlebar_overlay) {
      proton_engine_overlay_subclass_browser(window, child);
      RECT client;
      if (GetClientRect(window->hwnd, &client)) {
        HRGN browser_region = CreateRectRgn(client.left, client.top,
                                            client.right, client.bottom);
        RECT cluster;
        if (browser_region != NULL &&
            proton_engine_overlay_caption_buttons_rect(window->hwnd,
                                                        &cluster)) {
          cluster.left = max(cluster.left, client.left);
          cluster.top = max(cluster.top, client.top);
          cluster.right = min(cluster.right, client.right);
          cluster.bottom = min(cluster.bottom, client.bottom);
          proton_engine_overlay_subtract_rect(browser_region, &cluster);
        }
        if (browser_region != NULL) {
          if (SetWindowRgn(child, browser_region, TRUE) != 0) {
            browser_region = NULL;
          }
          if (browser_region != NULL) {
            DeleteObject(browser_region);
          }
        }
      }
    }
  }
  host->base.release((cef_base_ref_counted_t *)host);
}

static LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam) {
  LRESULT system_hit_test = HTNOWHERE;
  (void)DwmDefWindowProc(hwnd, WM_NCHITTEST, 0, lparam, &system_hit_test);

  POINT client_point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ScreenToClient(hwnd, &client_point);
  RECT caption_buttons;
  const int has_caption_buttons =
      proton_engine_overlay_caption_buttons_rect(hwnd, &caption_buttons);
  if (has_caption_buttons) {
    LRESULT caption_hit = proton_win_titlebar_caption_button_hit(
        client_point, &caption_buttons);
    if (caption_hit != HTNOWHERE) {
      system_hit_test = caption_hit;
    }
  }

  RECT window_rect;
  if (!GetWindowRect(hwnd, &window_rect)) {
    return DefWindowProcW(hwnd, WM_NCHITTEST, 0, lparam);
  }

  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  const int padded_border =
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_x =
      GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padded_border;
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border;
  const int maximized = IsZoomed(hwnd);
  POINT client_origin = {0, 0};
  ClientToScreen(hwnd, &client_origin);
  const int client_left = client_origin.x - window_rect.left;
  const int client_top = client_origin.y - window_rect.top;
  RECT drag_strip = {0};
  proton_engine_window_t *window =
      (proton_engine_window_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  if (window == NULL || !window->draggable_regions_reported) {
    (void)proton_engine_overlay_drag_strip_rect(hwnd, &drag_strip);
  }

  proton_win_titlebar_hit_test_input_t input = {
      .x = GET_X_LPARAM(lparam) - window_rect.left,
      .y = GET_Y_LPARAM(lparam) - window_rect.top,
      .width = window_rect.right - window_rect.left,
      .height = window_rect.bottom - window_rect.top,
      .resize_border_x = resize_border_x,
      .resize_border_y = resize_border_y,
      .drag_strip_left = client_left + drag_strip.left,
      .drag_strip_right = client_left + drag_strip.right,
      .drag_strip_top = client_top + drag_strip.top,
      .drag_strip_bottom = client_top + drag_strip.bottom,
      .maximized = maximized,
      .system_hit_test = system_hit_test,
  };
  LRESULT hit = proton_win_titlebar_hit_test(&input);
  if (hit == HTCLIENT && window != NULL &&
      proton_win_titlebar_point_in_draggable_regions(
          client_point, window->draggable_region_count,
          window->draggable_regions)) {
    return HTCAPTION;
  }
  return hit;
}

static LRESULT CALLBACK proton_engine_window_proc(HWND hwnd,
                                                  UINT msg,
                                                  WPARAM wparam,
                                                  LPARAM lparam) {
  proton_engine_window_t *window =
      (proton_engine_window_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
  case WM_NCCREATE: {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    window = (proton_engine_window_t *)create->lpCreateParams;
    if (window != NULL) {
      window->hwnd = hwnd;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)window);
    }
    break;
  }
  case WM_NCCALCSIZE:
    if (window != NULL && window->titlebar_overlay && wparam == TRUE) {
      NCCALCSIZE_PARAMS *params = (NCCALCSIZE_PARAMS *)lparam;
      LONG proposed_top = params->rgrc[0].top;
      LRESULT result = DefWindowProcW(hwnd, msg, wparam, lparam);
      if (result != 0) {
        return result;
      }
      params->rgrc[0].top =
          proposed_top +
          (IsZoomed(hwnd) ? proton_engine_overlay_frame_top_thickness(hwnd)
                          : 0);
      return 0;
    }
    break;
  case WM_NCHITTEST:
    if (window != NULL && window->titlebar_overlay) {
      return proton_engine_overlay_hit_test(hwnd, lparam);
    }
    break;
  case WM_GETMINMAXINFO:
    if (window != NULL && window->titlebar_overlay) {
      HMONITOR monitor =
          MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info;
      memset(&monitor_info, 0, sizeof(monitor_info));
      monitor_info.cbSize = sizeof(monitor_info);
      if (monitor != NULL && GetMonitorInfoW(monitor, &monitor_info)) {
        MINMAXINFO *minmax = (MINMAXINFO *)lparam;
        minmax->ptMaxPosition.x =
            monitor_info.rcWork.left - monitor_info.rcMonitor.left;
        minmax->ptMaxPosition.y =
            monitor_info.rcWork.top - monitor_info.rcMonitor.top;
        minmax->ptMaxSize.x =
            monitor_info.rcWork.right - monitor_info.rcWork.left;
        minmax->ptMaxSize.y =
            monitor_info.rcWork.bottom - monitor_info.rcWork.top;
        return 0;
      }
    }
    break;
  case WM_DPICHANGED:
    if (window != NULL && window->titlebar_overlay) {
      RECT *suggested = (RECT *)lparam;
      SetWindowPos(hwnd, NULL, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      proton_engine_overlay_apply_frame(hwnd);
      RECT client;
      if (GetClientRect(hwnd, &client)) {
        proton_engine_resize_browser(window, client.right - client.left,
                                     client.bottom - client.top);
      }
      return 0;
    }
    break;
  case WM_PARENTNOTIFY:
    if (window != NULL && window->titlebar_overlay &&
        LOWORD(wparam) == WM_CREATE) {
      proton_engine_overlay_subclass_browser(window, (HWND)lparam);
    }
    break;
  case WM_ACTIVATE:
    if (window != NULL && window->titlebar_overlay) {
      proton_engine_overlay_apply_frame(hwnd);
      RECT client;
      if (GetClientRect(hwnd, &client)) {
        proton_engine_resize_browser(window, client.right - client.left,
                                     client.bottom - client.top);
      }
    }
    break;
  case WM_SIZE:
    if (window != NULL) {
      proton_engine_resize_browser(window, LOWORD(lparam), HIWORD(lparam));
    }
    return 0;
  case WM_ERASEBKGND:
    if (window != NULL && window->titlebar_overlay) {
      RECT client;
      GetClientRect(hwnd, &client);
      FillRect((HDC)wparam, &client, (HBRUSH)GetStockObject(BLACK_BRUSH));
      return 1;
    }
    break;
  case WM_PAINT:
    if (window != NULL && window->titlebar_overlay) {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(hwnd, &paint);
      FillRect(dc, &paint.rcPaint, (HBRUSH)GetStockObject(BLACK_BRUSH));
      EndPaint(hwnd, &paint);
      return 0;
    }
    break;
  case WM_CLOSE:
    if (window != NULL) {
      proton_engine_debug_log("window_wm_close browser=%d", window->browser_id);
      if (window->browser != NULL) {
        proton_engine_bridge_pending_remove_browser(window->runtime,
                                                   window->browser_id);
        cef_browser_host_t *host = window->browser->get_host(window->browser);
        if (host != NULL) {
          host->close_browser(host, 1);
          host->base.release((cef_base_ref_counted_t *)host);
        }
        proton_engine_browser_release(window->browser);
        window->browser = NULL;
      }
      DestroyWindow(hwnd);
      return 0;
    }
    break;
  case WM_DESTROY:
    if (window != NULL) {
      window->closed = 1;
      window->hwnd = NULL;
      proton_engine_debug_log("window_wm_destroy browser=%d",
                              window->browser_id);
    }
    return 0;
  default:
    break;
  }
  if (window != NULL && window->titlebar_overlay) {
    LRESULT dwm_result = 0;
    if (DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result)) {
      return dwm_result;
    }
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static void proton_engine_register_window_class(void) {
  static int registered = 0;
  if (registered) {
    return;
  }
  WNDCLASSW wc;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = proton_engine_window_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = PROTON_ENGINE_WINDOW_CLASS;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassW(&wc);
  registered = 1;
}

static cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self);
static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self);
static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self);

static proton_engine_client_t *proton_engine_client_new(
    proton_engine_window_t *window) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  client->window = window;
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->client.on_process_message_received =
      proton_engine_client_on_process_message_received;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_drag_handler = proton_engine_client_get_drag_handler;
  client->client.get_request_handler =
      proton_engine_client_get_request_handler;
  return client;
}

static void CEF_CALLBACK proton_engine_on_draggable_regions_changed(
    cef_drag_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    size_t regions_count,
    const cef_draggable_region_t *regions) {
  (void)self;
  if (browser == NULL || frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  if (window == NULL || !window->titlebar_overlay) {
    return;
  }

  if (regions_count == 0) {
    free(window->draggable_regions);
    window->draggable_regions = NULL;
    window->draggable_region_count = 0;
    window->draggable_regions_reported = 1;
  } else if (regions != NULL &&
             regions_count <=
                 SIZE_MAX / sizeof(proton_win_titlebar_region_t)) {
    proton_win_titlebar_region_t *copy =
        (proton_win_titlebar_region_t *)malloc(regions_count * sizeof(*copy));
    if (copy == NULL) {
      proton_engine_verbose_log("draggable_regions_allocation_failed count=%zu",
                                regions_count);
      return;
    }
    for (size_t i = 0; i < regions_count; i++) {
      copy[i].x = regions[i].bounds.x;
      copy[i].y = regions[i].bounds.y;
      copy[i].width = regions[i].bounds.width;
      copy[i].height = regions[i].bounds.height;
      copy[i].draggable = regions[i].draggable;
    }
    free(window->draggable_regions);
    window->draggable_regions = copy;
    window->draggable_region_count = regions_count;
    window->draggable_regions_reported = 1;
  }

  cef_browser_host_t *host = browser->get_host(browser);
  if (host != NULL) {
    HWND browser_hwnd = host->get_window_handle(host);
    proton_engine_overlay_subclass_browser(window, browser_hwnd);
    host->base.release((cef_base_ref_counted_t *)host);
  }
  proton_engine_verbose_log("draggable_regions browser=%d count=%zu",
                            window->browser_id,
                            window->draggable_region_count);
}

static void CEF_CALLBACK proton_engine_on_loading_state_change(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    int isLoading,
    int canGoBack,
    int canGoForward) {
  (void)self;
  (void)canGoBack;
  (void)canGoForward;
  proton_engine_verbose_log("loading_state browser=%d loading=%d",
                            proton_engine_browser_id(browser), isLoading);
}

static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_transition_type_t transition_type) {
  (void)self;
  (void)transition_type;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_verbose_log("load_start browser=%d main=%d url=%s",
                            proton_engine_browser_id(browser),
                            frame != NULL ? frame->is_main(frame) : 0,
                            proton_engine_log_url(url));
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode) {
  (void)self;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_verbose_log("load_end browser=%d main=%d status=%d url=%s",
                            proton_engine_browser_id(browser),
                            frame != NULL ? frame->is_main(frame) : 0,
                            httpStatusCode, proton_engine_log_url(url));
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  if (window != NULL && window->bridge_config_json != NULL && frame != NULL &&
      frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") != 0) {
    (void)proton_engine_bridge_send_lifecycle_probe(frame);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_errorcode_t errorCode,
    const cef_string_t *errorText,
    const cef_string_t *failedUrl) {
  (void)self;
  char *text = proton_engine_cef_string_to_utf8(errorText);
  char *url = proton_engine_cef_string_to_utf8(failedUrl);
  proton_engine_debug_log("load_error browser=%d main=%d code=%d text=%s url=%s",
                          proton_engine_browser_id(browser),
                          frame != NULL ? frame->is_main(frame) : 0, errorCode,
                          text != NULL ? text : "", proton_engine_log_url(url));
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  if (window != NULL && window->bridge_config_json != NULL && frame != NULL &&
      frame->is_main(frame) && url != NULL) {
    proton_engine_bridge_lifecycle_report_load_failure(
        &window->bridge_lifecycle, url,
        text != NULL && text[0] != '\0' ? text : "main frame failed to load",
        errorCode == ERR_ABORTED);
  }
  free(text);
  free(url);
}

static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  if (window == NULL || window->bridge_config_json == NULL || window->closed) {
    return;
  }
  cef_frame_t *frame = browser != NULL ? browser->get_main_frame(browser) : NULL;
  char *url =
      frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                    : NULL;
  char *detail = proton_engine_cef_string_to_utf8(error_string);
  if (url != NULL &&
      !(window->bridge_lifecycle.outcome != NULL &&
        strcmp(window->bridge_lifecycle.outcome, "ineligible") == 0 &&
        window->bridge_lifecycle.url != NULL &&
        strcmp(window->bridge_lifecycle.url, url) == 0)) {
    char message[1024];
    snprintf(message, sizeof(message),
             "renderer process terminated (status=%d, error=%d)%s%s",
             (int)status, error_code,
             detail != NULL && detail[0] != '\0' ? ": " : "",
             detail != NULL ? detail : "");
    proton_engine_bridge_lifecycle_report_browser_failure(
        &window->bridge_lifecycle, url, "renderer_process_terminated", message,
        0);
    if (g_proton_engine_pump_event != NULL) {
      SetEvent(g_proton_engine_pump_event);
    }
  }
  free(detail);
  free(url);
  if (frame != NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
  }
}

static cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_load_handler.handler;
}

static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_drag_handler.handler;
}

static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_request_handler.handler;
}

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
  if (window == NULL || window->hwnd == NULL || window->client == NULL) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  RECT rect;
  GetClientRect(window->hwnd, &rect);

  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  window_info.parent_window = window->hwnd;
  window_info.style = WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = rect.right - rect.left;
  window_info.bounds.height = rect.bottom - rect.top;
  proton_engine_set_string(&window_info.window_name, "Proton");
  proton_engine_set_string(&url,
                           initial_url != NULL && initial_url[0] != '\0'
                               ? initial_url
                               : "about:blank");

  cef_value_t *extra_info_value =
      proton_engine_bridge_renderer_extra_info_value(window->bridge_config_json);
  cef_dictionary_value_t *extra_info =
      extra_info_value != NULL
          ? extra_info_value->get_dictionary(extra_info_value)
          : NULL;
  window->browser = cef_browser_host_create_browser_sync(
      &window_info, window->client, &url, &browser_settings, extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);

  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_browser_add_ref(window->browser);
  window->browser_id = proton_engine_browser_id(window->browser);
  proton_engine_verbose_log(
      "create_browser thread=%lu id=%d initial_url=%s size=%ldx%ld",
      GetCurrentThreadId(), window->browser_id,
      proton_engine_log_url(initial_url), rect.right - rect.left,
      rect.bottom - rect.top);
  proton_engine_resize_browser(window, rect.right - rect.left,
                               rect.bottom - rect.top);
  return PROTON_OK;
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    cef_shutdown();
    g_proton_cef_initialized = 0;
  }
}

const char *proton_engine_name(void) {
  return "cef";
}

int32_t proton_engine_execute_process_json(const char *config_json,
                                           int32_t *out_exit_code,
                                           char *error,
                                           size_t error_len) {
  proton_engine_runtime_config_t config;
  int32_t status =
      proton_engine_parse_runtime_config(config_json, &config, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  proton_engine_set_command_line_paths(&config);
  proton_engine_init_app();
  proton_engine_check_cef_api_hash();

  cef_main_args_t args;
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  int exit_code = cef_execute_process(&args, &g_proton_engine_app.app, NULL);
  if (out_exit_code != NULL) {
    *out_exit_code = exit_code;
  }
  return exit_code >= 0 ? PROTON_PROCESS_HANDLED : PROTON_OK;
}

int32_t proton_engine_runtime_create_json(const char *config_json,
                                          proton_engine_runtime_t **out_runtime,
                                          char *error,
                                          size_t error_len) {
  if (out_runtime == NULL) {
    proton_engine_set_message(error, error_len, "out_runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_runtime = NULL;

  if (g_proton_cef_runtime_active) {
    proton_engine_set_message(error, error_len, "runtime is already active");
    return PROTON_ERR_ALREADY_INITIALIZED;
  }

  proton_engine_runtime_config_t config;
  int32_t status =
      proton_engine_parse_runtime_config(config_json, &config, error, error_len);
  if (status != PROTON_OK) {
    return status;
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
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  g_proton_engine_multi_threaded_message_loop = 0;
  settings.remote_debugging_port = config.remote_debugging_port;

  if (g_proton_engine_pump_event == NULL) {
    g_proton_engine_pump_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (g_proton_engine_pump_event == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to create CEF pump wake event");
      return PROTON_ERR_PLATFORM;
    }
  }
  proton_engine_reset_scheduled_pump();

  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  if (config.cache_dir[0] != '\0') {
    proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, &g_proton_engine_app.app, NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.root_cache_path);
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.root_cache_path);
  g_proton_cef_initialized = 1;
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
    proton_engine_set_message(error, error_len,
                              "failed to register proton scheme handler");
    return PROTON_ERR_ENGINE;
  }
  if (!g_proton_cef_shutdown_registered) {
    atexit(proton_engine_cef_shutdown);
    g_proton_cef_shutdown_registered = 1;
  }

  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(proton_engine_runtime_t));
  if (runtime == NULL) {
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
    proton_engine_set_message(error, error_len,
                              "failed to allocate runtime state");
    return PROTON_ERR_ENGINE;
  }
  runtime->owns_cef_runtime = 1;
  runtime->next_bridge_request_id = 1;
  InitializeCriticalSection(&runtime->bridge_lock);
  runtime->bridge_lock_initialized = 1;
  runtime->bridge_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (runtime->bridge_event == NULL) {
    DeleteCriticalSection(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
    free(runtime);
    proton_engine_cef_shutdown();
    g_proton_cef_runtime_active = 0;
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
    proton_engine_set_message(error, error_len,
                              "failed to create bridge wake event");
    return PROTON_ERR_PLATFORM;
  }
  *out_runtime = runtime;
  return PROTON_OK;
}

int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (runtime->owns_cef_runtime) {
    proton_engine_cef_shutdown();
    runtime->owns_cef_runtime = 0;
  }
  proton_engine_runtime_clear_bridge_queue(runtime);
  proton_engine_bridge_pending_clear_all();
  if (runtime->bridge_event != NULL) {
    CloseHandle(runtime->bridge_event);
    runtime->bridge_event = NULL;
  }
  if (runtime->bridge_lock_initialized) {
    DeleteCriticalSection(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
  }
  if (g_proton_engine_pump_event != NULL) {
    CloseHandle(g_proton_engine_pump_event);
    g_proton_engine_pump_event = NULL;
  }
  proton_engine_reset_scheduled_pump();
  g_proton_cef_runtime_active = 0;
  free(runtime);
  return PROTON_OK;
}

int32_t proton_engine_runtime_run(proton_engine_runtime_t *runtime,
                                  char *error,
                                  size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_run_message_loop();
  return PROTON_OK;
}

int32_t proton_engine_runtime_quit(proton_engine_runtime_t *runtime,
                                   char *error,
                                   size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_quit_message_loop();
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
  proton_engine_reset_scheduled_pump();
  MSG msg;
  while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  static int log_count = 0;
  if (log_count < 8) {
    proton_engine_verbose_log("do_message_loop_work thread=%lu",
                              GetCurrentThreadId());
    log_count++;
  }
  if (!g_proton_engine_multi_threaded_message_loop) {
    cef_do_message_loop_work();
  }
  return PROTON_OK;
}

int32_t proton_engine_runtime_wait(proton_engine_runtime_t *runtime,
                                   uint32_t interest_mask,
                                   uint32_t timeout_ms,
                                   uint32_t *out_ready_mask,
                                   char *error,
                                   size_t error_len) {
  if (out_ready_mask != NULL) {
    *out_ready_mask = PROTON_WAIT_NONE;
  }
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_ready_mask == NULL) {
    proton_engine_set_message(error, error_len, "out_ready_mask is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  uint32_t ready_mask = PROTON_WAIT_NONE;
  if ((interest_mask & PROTON_WAIT_BRIDGE) != 0 &&
      proton_engine_runtime_has_bridge_request(runtime)) {
    ready_mask |= PROTON_WAIT_BRIDGE;
  }
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
    *out_ready_mask = ready_mask;
    return PROTON_OK;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
    *out_ready_mask = ready_mask;
    return PROTON_OK;
  }

  HANDLE handles[2];
  DWORD handle_count = 0;
  DWORD bridge_handle_index = MAXDWORD;
  DWORD pump_handle_index = MAXDWORD;
  if ((interest_mask & PROTON_WAIT_BRIDGE) != 0 &&
      runtime->bridge_event != NULL) {
    bridge_handle_index = handle_count;
    handles[handle_count++] = runtime->bridge_event;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_proton_engine_pump_event != NULL) {
    pump_handle_index = handle_count;
    handles[handle_count++] = g_proton_engine_pump_event;
  }

  DWORD wait_timeout = timeout_ms;
  int waiting_for_scheduled_pump = 0;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
    int64_t scheduled_delay = proton_engine_get_scheduled_pump_delay_ms();
    if (scheduled_delay > 0 && scheduled_delay <= (int64_t)wait_timeout) {
      wait_timeout = (DWORD)scheduled_delay;
      waiting_for_scheduled_pump = 1;
    }
  }

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
    if (ready_index == bridge_handle_index) {
      ready_mask |= PROTON_WAIT_BRIDGE;
    }
    if (ready_index == pump_handle_index) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else if (wait_result == WAIT_OBJECT_0 + handle_count) {
    if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else if (wait_result == WAIT_TIMEOUT) {
    if (waiting_for_scheduled_pump) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  } else {
    proton_engine_set_message(error, error_len,
                              "runtime wait returned an unexpected status");
    return PROTON_ERR_PLATFORM;
  }

  if ((interest_mask & PROTON_WAIT_BRIDGE) != 0 &&
      proton_engine_runtime_has_bridge_request(runtime)) {
    ready_mask |= PROTON_WAIT_BRIDGE;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
  }
  *out_ready_mask = ready_mask & interest_mask;
  return PROTON_OK;
}

// TODO: Connect a Windows async event source instead of a POSIX descriptor.
int32_t proton_engine_runtime_set_wakeup_fd(proton_engine_runtime_t *runtime,
                                            int32_t wakeup_fd,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)wakeup_fd;
  proton_engine_set_message(error, error_len,
                            "runtime wakeup fd is not supported on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

// TODO: Expose scheduled pump deadlines with the Windows async event source.
int32_t proton_engine_runtime_next_wakeup_delay_ms(
    proton_engine_runtime_t *runtime,
    int64_t *out_delay_ms,
    char *error,
    size_t error_len) {
  (void)runtime;
  if (out_delay_ms != NULL) {
    *out_delay_ms = -1;
  }
  proton_engine_set_message(
      error, error_len,
      "runtime wakeup delay is not supported on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

// TODO: Implement app menu rendering and command events on Windows.
int32_t proton_engine_runtime_set_menu_json(proton_engine_runtime_t *runtime,
                                            const char *menu_json,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)menu_json;
  proton_engine_set_message(error, error_len,
                            "native app menus are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_runtime_poll_bridge_request_json(
    proton_engine_runtime_t *runtime,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len) {
  (void)error;
  (void)error_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len, "out_required_len is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_runtime_bridge_lock(runtime);
  if (runtime->bridge_count == 0) {
    proton_engine_runtime_bridge_unlock(runtime);
    return PROTON_EVENT_NONE;
  }
  char *request_json = runtime->bridge_queue[runtime->bridge_head];
  int32_t required = (int32_t)strlen(request_json);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    proton_engine_runtime_bridge_unlock(runtime);
    proton_engine_set_message(error, error_len,
                              "bridge request buffer is too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, request_json, (size_t)required + 1);
  runtime->bridge_queue[runtime->bridge_head] = NULL;
  runtime->bridge_head =
      (runtime->bridge_head + 1) % PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
  runtime->bridge_count--;
  proton_engine_runtime_sync_bridge_event_locked(runtime);
  proton_engine_runtime_bridge_unlock(runtime);
  free(request_json);
  return PROTON_OK;
}

int32_t proton_engine_runtime_respond_bridge_request_json(
    proton_engine_runtime_t *runtime,
    const char *response_json,
    char *error,
    size_t error_len) {
  (void)runtime;
  if (response_json == NULL) {
    proton_engine_set_message(error, error_len, "response_json is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int64_t request_id = 0;
  int ok = 0;
  if (!proton_engine_json_read_int64_field(response_json, "request_id",
                                          &request_id) ||
      !proton_engine_json_read_bool_field(response_json, "ok", &ok)) {
    proton_engine_set_message(error, error_len,
                              "bridge response is missing request_id or ok");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_bridge_pending_t *pending =
      proton_engine_bridge_pending_take(request_id);
  if (pending == NULL) {
    proton_engine_debug_log("bridge_response_no_pending request=%lld",
                            (long long)request_id);
    proton_engine_set_message(error, error_len,
                              "bridge request is no longer pending");
    return PROTON_ERR_INVALID_HANDLE;
  }

  char *payload_json = NULL;
  char *error_message = NULL;
  if (ok) {
    payload_json = proton_engine_json_copy_raw_field(response_json, "payload");
    if (payload_json == NULL) {
      payload_json = proton_engine_strdup("null");
    }
  } else {
    char *error_json = proton_engine_json_copy_raw_field(response_json, "error");
    if (error_json != NULL) {
      error_message = proton_engine_json_copy_string_field(error_json, "message");
      free(error_json);
    }
    if (error_message == NULL) {
      error_message = proton_engine_json_copy_string_field(response_json, "message");
    }
    if (error_message == NULL) {
      error_message = proton_engine_strdup("bridge request failed");
    }
  }

  int sent = proton_engine_send_bridge_response_to_frame(
      pending->frame, pending->renderer_pending_id, ok, payload_json,
      error_message);
  free(payload_json);
  free(error_message);
  proton_engine_bridge_pending_free(pending);
  if (!sent) {
    proton_engine_debug_log("bridge_response_send_failed request=%lld",
                            (long long)request_id);
    proton_engine_set_message(error, error_len,
                              "failed to send bridge response to renderer");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_create_json(proton_engine_runtime_t *runtime,
                                         const char *config_json,
                                         proton_engine_window_t **out_window,
                                         char *error,
                                         size_t error_len) {
  if (out_window == NULL) {
    proton_engine_set_message(error, error_len, "out_window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_window = NULL;
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }

  int32_t width = 0;
  int32_t height = 0;
  char title[512] = {0};
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES] = {0};
  char titlebar_style[32] = {0};
  int titlebar_overlay = 0;
  if (!proton_engine_parse_json_int_field(config_json, "width", &width) ||
      !proton_engine_parse_json_int_field(config_json, "height", &height) ||
      width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "window config requires positive width and height");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_parse_json_string_field(config_json, "title", title,
                                             sizeof(title))) {
    snprintf(title, sizeof(title), "Proton");
  }
  if (!proton_engine_parse_json_string_field(config_json, "initial_url",
                                             initial_url,
                                             sizeof(initial_url))) {
    snprintf(initial_url, sizeof(initial_url), "about:blank");
  }
  if (proton_engine_parse_json_string_field(config_json, "titlebar_style",
                                            titlebar_style,
                                            sizeof(titlebar_style))) {
    if (strcmp(titlebar_style, "overlay") == 0) {
      titlebar_overlay = 1;
    } else if (strcmp(titlebar_style, "default") != 0) {
      proton_engine_set_message(
          error, error_len,
          "window titlebar_style must be default or overlay");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
  }

  proton_engine_register_window_class();
  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "failed to allocate window");
    return PROTON_ERR_ENGINE;
  }
  window->width = width;
  window->height = height;
  window->titlebar_overlay = titlebar_overlay;
  window->runtime = runtime;
  window->bridge_config_json =
      proton_engine_json_copy_raw_field(config_json, "bridge");
  window->max_bridge_payload_bytes = PROTON_ENGINE_MAX_BRIDGE_BYTES;
  if (window->bridge_config_json != NULL) {
    proton_engine_bridge_config_read_max_payload(
        window->bridge_config_json, &window->max_bridge_payload_bytes);
  }
  window->client = (cef_client_t *)proton_engine_client_new(window);
  if (window->client == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  wchar_t wide_title[512];
  proton_engine_utf8_to_wide(title, wide_title,
                             (int)(sizeof(wide_title) / sizeof(wide_title[0])));
  DWORD window_style = WS_OVERLAPPEDWINDOW;
  if (window->titlebar_overlay) {
    window_style |= WS_CLIPCHILDREN;
  }
  window->hwnd = CreateWindowExW(0, PROTON_ENGINE_WINDOW_CLASS, wide_title,
                                 window_style, CW_USEDEFAULT, CW_USEDEFAULT,
                                 width, height, NULL, NULL,
                                 GetModuleHandleW(NULL), window);
  if (window->hwnd == NULL) {
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "window creation failed");
    return PROTON_ERR_PLATFORM;
  }
  if (window->titlebar_overlay) {
    proton_engine_overlay_apply_frame(window->hwnd);
    SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  }
  ShowWindow(window->hwnd, SW_SHOW);

  int32_t status =
      proton_engine_window_create_browser(window, initial_url, error, error_len);
  if (status != PROTON_OK) {
    DestroyWindow(window->hwnd);
    free(window->client);
    free(window->html_url);
    free(window->html);
    free(window->bridge_config_json);
    free(window->draggable_regions);
    free(window);
    return status;
  }

  proton_engine_window_list_add(window);
  *out_window = window;
  return PROTON_OK;
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  (void)error;
  (void)error_len;
  if (window == NULL) {
    return PROTON_OK;
  }
  proton_engine_window_list_remove(window);
  if (window->browser != NULL) {
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                               window->browser_id);
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_engine_browser_release(window->browser);
    window->browser = NULL;
  }
  if (window->hwnd != NULL) {
    DestroyWindow(window->hwnd);
    window->hwnd = NULL;
  }
  if (window->client != NULL) {
    ((proton_engine_client_t *)window->client)->window = NULL;
  }
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  free(window->draggable_regions);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  ShowWindow(window->hwnd, SW_SHOW);
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  ShowWindow(window->hwnd, SW_HIDE);
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  SetForegroundWindow(window->hwnd);
  SetFocus(window->hwnd);
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  wchar_t wide_title[512];
  proton_engine_utf8_to_wide(title, wide_title,
                             (int)(sizeof(wide_title) / sizeof(wide_title[0])));
  SetWindowTextW(window->hwnd, wide_title);
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->width = width;
  window->height = height;
  SetWindowPos(window->hwnd, NULL, 0, 0, width, height,
               SWP_NOMOVE | SWP_NOZORDER);
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t value = {0};
  proton_engine_set_string(&value, url);
  proton_engine_verbose_log("load_url thread=%lu browser=%d url=%s",
                            GetCurrentThreadId(), window->browser_id,
                            proton_engine_log_url(url));
  frame->load_url(frame, &value);
  cef_string_clear(&value);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_load_html(proton_engine_window_t *window,
                                       const char *html,
                                       const char *base_url,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  if (!proton_engine_url_is_proton(base_url)) {
    proton_engine_set_message(error, error_len,
                              "base_url must use the proton:// scheme");
    frame->base.release((cef_base_ref_counted_t *)frame);
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  char *url_copy = proton_engine_strdup(base_url);
  char *html_copy = proton_engine_strdup(html);
  if (url_copy == NULL || html_copy == NULL) {
    free(url_copy);
    free(html_copy);
    proton_engine_set_message(error, error_len, "failed to copy html content");
    frame->base.release((cef_base_ref_counted_t *)frame);
    return PROTON_ERR_ENGINE;
  }

  proton_engine_init_window_lock();
  EnterCriticalSection(&g_proton_engine_window_lock);
  free(window->html_url);
  free(window->html);
  window->html_url = url_copy;
  window->html = html_copy;
  window->html_len = strlen(html_copy);
  LeaveCriticalSection(&g_proton_engine_window_lock);

  cef_string_t url_value = {0};
  proton_engine_set_string(&url_value, base_url);
  proton_engine_verbose_log(
      "load_html thread=%lu browser=%d base_url=%s bytes=%llu",
      GetCurrentThreadId(), window->browser_id,
      proton_engine_log_url(base_url), (unsigned long long)window->html_len);
  frame->load_url(frame, &url_value);
  cef_string_clear(&url_value);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t code = {0};
  cef_string_t url = {0};
  proton_engine_set_string(&code, script);
  proton_engine_set_string(&url, "proton://eval/");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL ||
      window->bridge_config_json == NULL) {
    proton_engine_set_message(error, error_len, "bridge is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (!proton_engine_bridge_send_event(window->browser, event_json)) {
    proton_engine_set_message(error, error_len,
                              "failed to send bridge event to renderer");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

void proton_engine_window_bind_public_id(proton_engine_window_t *window,
                                         proton_window_id_t public_window) {
  if (window != NULL) {
    window->public_window_id = public_window;
  }
}

uint64_t proton_engine_window_bridge_revision(proton_engine_window_t *window) {
  return window != NULL
             ? proton_engine_bridge_lifecycle_revision(&window->bridge_lifecycle)
             : 0;
}

int32_t proton_engine_window_bridge_state_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_state_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

int32_t proton_engine_window_take_bridge_failure_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_take_failure_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

// TODO: Implement non-blocking Windows dialogs. These exports are ABI stubs so
// that shared engine interfaces can stay async-only while macOS owns the first
// real async dialog implementation.
int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len) {
  (void)runtime;
  (void)title_utf8;
  (void)title_len;
  (void)message_utf8;
  (void)message_len;
  (void)level;
  if (out_dialog != NULL) {
    *out_dialog = PROTON_INVALID_HANDLE;
  }
  proton_engine_set_message(error, error_len,
                            "runtime dialogs are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_runtime_poll_dialog_result(
    proton_engine_runtime_t *runtime, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len, char *error,
    size_t error_len) {
  (void)dialog;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return proton_engine_runtime_begin_message_dialog(
      runtime, NULL, 0, NULL, 0, 0, NULL, error, error_len);
}

int32_t proton_engine_window_begin_message_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  (void)window;
  (void)title_utf8;
  (void)title_len;
  (void)message_utf8;
  (void)message_len;
  (void)level;
  if (out_dialog != NULL) {
    *out_dialog = PROTON_INVALID_HANDLE;
  }
  proton_engine_set_message(error, error_len,
                            "async native dialogs are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_window_begin_confirm_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_message_dialog(
      window, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_open_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  (void)window;
  (void)title_utf8;
  (void)title_len;
  (void)path_utf8;
  (void)path_len;
  if (out_dialog != NULL) {
    *out_dialog = PROTON_INVALID_HANDLE;
  }
  proton_engine_set_message(error, error_len,
                            "async native dialogs are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_window_begin_save_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_open_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len, out_dialog,
      error, error_len);
}

int32_t proton_engine_window_begin_choose_directory_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_open_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len, out_dialog,
      error, error_len);
}

int32_t proton_engine_window_poll_dialog_result(
    proton_engine_window_t *window,
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len) {
  (void)window;
  (void)dialog;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  proton_engine_set_message(error, error_len,
                            "async native dialogs are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}
// TODO: Drain Windows menu commands once the native menu backend is implemented.
int32_t proton_engine_take_menu_command(
    proton_engine_runtime_t *runtime,
    char *buffer,
    size_t buffer_len,
    proton_window_id_t *out_focused_window,
    int32_t *out_present) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_focused_window == NULL || out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_focused_window = PROTON_INVALID_HANDLE;
  *out_present = 0;
  return PROTON_OK;
}
