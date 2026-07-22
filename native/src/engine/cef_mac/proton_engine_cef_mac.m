#include "../../proton_engine.h"
#include "../../proton_json.h"

#include "dialog.h"
#include "menu.h"
#include "scheme.h"
#include "window.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#import "include/cef_application_mac.h"
#include "include/internal/cef_string.h"
#include "include/wrapper/cef_library_loader.h"

#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"

#import <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

#include <ctype.h>
#include <crt_externs.h>
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PROTON_ENGINE_MAX_PATH_BYTES 4096
#define PROTON_ENGINE_MAX_URL_BYTES 131072
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
  pthread_mutex_t bridge_lock;
  int bridge_lock_initialized;
};

struct proton_engine_window {
  proton_engine_runtime_t *runtime;
  NSWindow *window;
  NSView *content_view;
  NSView *browser_view;
  id delegate;
  int appkit_closing;
  int browser_close_requested;
  int cef_allows_appkit_close;
  proton_engine_client_t *client;
  cef_browser_t *browser;
  int browser_id;
  proton_window_id_t public_window_id;
  char *html_url;
  char *html;
  size_t html_len;
  char *bridge_config_json;
  int32_t max_bridge_payload_bytes;
  proton_engine_bridge_lifecycle_t bridge_lifecycle;
  char *initial_url;
  int initial_navigation_pending;
  int browser_create_pending;
  int browser_create_scheduled;
  int window_listed;
  int browser_before_close_seen;
  int finalize_after_browser_close;
  uint64_t native_id;
  int width;
  int height;
  int closed;
  int closing;
  struct proton_engine_window *next;
};

typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_engine_window_t *window;
};

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
  cef_life_span_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_life_span_handler_t;

typedef struct {
  cef_load_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_load_handler_t;

typedef struct {
  cef_request_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_request_handler_t;

typedef struct {
  cef_scheme_handler_factory_t factory;
  proton_engine_ref_counted_t refs;
} proton_engine_scheme_factory_t;

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
  char framework_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  int32_t remote_debugging_port;
} proton_engine_runtime_config_t;

typedef struct {
  char title[512];
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t width;
  int32_t height;
} proton_engine_window_config_t;

static int g_proton_cef_initialized = 0;
static int g_proton_cef_library_loaded = 0;
static int g_proton_cef_runtime_active = 0;
static int g_proton_cef_shutdown_registered = 0;
static int g_proton_app_terminating = 0;
static proton_engine_app_t g_app;
static proton_engine_browser_process_handler_t g_browser_process_handler;
static proton_engine_render_process_handler_t g_render_process_handler;
static proton_engine_v8_handler_t g_v8_handler;
static proton_engine_life_span_handler_t g_life_span_handler;
static proton_engine_load_handler_t g_load_handler;
static proton_engine_request_handler_t g_request_handler;
static proton_engine_scheme_factory_t g_scheme_factory;
static proton_engine_window_t *g_windows = NULL;
static uint64_t g_next_window_native_id = 1;
static proton_engine_bridge_pending_t *g_bridge_pending = NULL;
static atomic_llong g_scheduled_pump_delay_ms = ATOMIC_VAR_INIT(-1);
static atomic_int g_runtime_wait_log_count = ATOMIC_VAR_INIT(0);
static atomic_uint g_wait_source_ready_mask = ATOMIC_VAR_INIT(PROTON_WAIT_NONE);
static CFRunLoopRef g_wait_run_loop = NULL;
static CFRunLoopSourceRef g_wait_source = NULL;

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static void proton_engine_log_to_env(const char *env_name,
                                     const char *format,
                                     va_list args) {
  const char *path = getenv(env_name);
  if (path == NULL || path[0] == '\0') {
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

static void proton_engine_wait_source_perform(void *info) {
  (void)info;
}

static void proton_engine_teardown_wait_source(void) {
  if (g_wait_source != NULL) {
    if (g_wait_run_loop != NULL) {
      CFRunLoopRemoveSource(g_wait_run_loop, g_wait_source,
                            kCFRunLoopDefaultMode);
    }
    CFRelease(g_wait_source);
    g_wait_source = NULL;
  }
  if (g_wait_run_loop != NULL) {
    CFRelease(g_wait_run_loop);
    g_wait_run_loop = NULL;
  }
}

static int proton_engine_setup_wait_source(char *error, size_t error_len) {
  proton_engine_teardown_wait_source();
  atomic_store_explicit(&g_wait_source_ready_mask, PROTON_WAIT_NONE,
                        memory_order_release);
  g_wait_run_loop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
  CFRunLoopSourceContext context;
  memset(&context, 0, sizeof(context));
  context.perform = proton_engine_wait_source_perform;
  g_wait_source = CFRunLoopSourceCreate(NULL, 0, &context);
  if (g_wait_source == NULL) {
    proton_engine_teardown_wait_source();
    proton_engine_set_message(error, error_len,
                              "failed to create runtime wait source");
    return 0;
  }
  CFRunLoopAddSource(g_wait_run_loop, g_wait_source, kCFRunLoopDefaultMode);
  return 1;
}

static void proton_engine_signal_wait_source(uint32_t ready_mask) {
  if (ready_mask != PROTON_WAIT_NONE) {
    atomic_fetch_or_explicit(&g_wait_source_ready_mask, ready_mask,
                             memory_order_release);
  }
  if (g_wait_source != NULL) {
    CFRunLoopSourceSignal(g_wait_source);
  }
  if (g_wait_run_loop != NULL) {
    CFRunLoopWakeUp(g_wait_run_loop);
  }
}

static int64_t proton_engine_get_scheduled_pump_delay_ms(void) {
  return atomic_load_explicit(&g_scheduled_pump_delay_ms, memory_order_acquire);
}

static void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
  atomic_store_explicit(&g_scheduled_pump_delay_ms, (long long)delay_ms,
                        memory_order_release);
  if (delay_ms <= 0) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_reset_scheduled_pump(void) {
  atomic_store_explicit(&g_scheduled_pump_delay_ms, -1, memory_order_release);
}

static void proton_engine_log_runtime_wait_ready(uint32_t ready_mask,
                                                 uint32_t interest_mask) {
  int count =
      atomic_fetch_add_explicit(&g_runtime_wait_log_count, 1,
                                memory_order_relaxed) +
      1;
  if (count <= 16) {
    proton_engine_debug_log("runtime_wait ready mask=%u interest=%u",
                            ready_mask, interest_mask);
  }
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

static bool proton_engine_join_path(char *out,
                                    size_t out_len,
                                    const char *base,
                                    const char *child) {
  if (out == NULL || out_len == 0 || base == NULL || child == NULL ||
      base[0] == '\0' || child[0] == '\0') {
    return false;
  }
  const char *separator = base[strlen(base) - 1] == '/' ? "" : "/";
  int written = snprintf(out, out_len, "%s%s%s", base, separator, child);
  return written >= 0 && (size_t)written < out_len;
}

static bool proton_engine_path_parent(char *path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
  size_t len = strlen(path);
  while (len > 0 && path[len - 1] == '/') {
    path[--len] = '\0';
  }
  while (len > 0 && path[len - 1] != '/') {
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
  const char *base = strrchr(path, '/');
  base = base == NULL ? path : base + 1;
  return strcmp(base, name) == 0;
}

static bool proton_engine_dir_exists(const char *path) {
  struct stat info;
  return path != NULL && path[0] != '\0' && stat(path, &info) == 0 &&
         S_ISDIR(info.st_mode);
}

static bool proton_engine_module_dir(char *out, size_t out_len) {
  if (out == NULL || out_len == 0) {
    return false;
  }
  Dl_info info;
  if (dladdr((const void *)&proton_engine_module_dir, &info) == 0 ||
      info.dli_fname == NULL || info.dli_fname[0] == '\0') {
    return false;
  }
  int written = snprintf(out, out_len, "%s", info.dli_fname);
  if (written < 0 || (size_t)written >= out_len) {
    return false;
  }
  return proton_engine_path_parent(out);
}

static bool proton_engine_default_runtime_root(char *out, size_t out_len) {
  // TODO: Resolve bundled runtime paths once in the public ABI layer and pass
  // explicit paths into the engine. macOS app packaging should generate the
  // standard CEF Helper.app layout instead of relying on environment overrides.
  const char *env_root = getenv("PROTON_RUNTIME_ROOT");
  if (env_root == NULL || env_root[0] == '\0') {
    env_root = getenv("PROTON_NATIVE_DIST");
  }
  if (env_root != NULL && env_root[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_root);
    return written > 0 && (size_t)written < out_len;
  }
  if (!proton_engine_module_dir(out, out_len)) {
    return false;
  }
  if (proton_engine_path_basename_equals(out, "bin") ||
      proton_engine_path_basename_equals(out, "lib")) {
    return proton_engine_path_parent(out);
  }
  return true;
}

static bool proton_engine_default_helper_path(char *out, size_t out_len) {
  const char *env_helper = getenv("PROTON_HELPER_PATH");
  if (env_helper != NULL && env_helper[0] != '\0') {
    int written = snprintf(out, out_len, "%s", env_helper);
    return written > 0 && (size_t)written < out_len;
  }
  char runtime_root[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  char bin_dir[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  if (!proton_engine_default_runtime_root(runtime_root, sizeof(runtime_root)) ||
      !proton_engine_join_path(bin_dir, sizeof(bin_dir), runtime_root, "bin")) {
    return false;
  }
  return proton_engine_join_path(out, out_len, bin_dir, "cef_process");
}

static int proton_engine_load_cef_library(
    const proton_engine_runtime_config_t *config,
    char *error,
    size_t error_len) {
  if (g_proton_cef_library_loaded) {
    return 1;
  }
  if (config == NULL || config->framework_dir[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime framework path is required");
    return 0;
  }
  char framework_binary[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  if (!proton_engine_join_path(framework_binary, sizeof(framework_binary),
                               config->framework_dir,
                               "Chromium Embedded Framework")) {
    proton_engine_set_message(error, error_len,
                              "runtime framework binary path is too long");
    return 0;
  }
  proton_engine_debug_log("cef_load_library path=%s", framework_binary);
  if (!cef_load_library(framework_binary)) {
    proton_engine_set_message(error, error_len, "failed to load CEF framework");
    return 0;
  }
  g_proton_cef_library_loaded = 1;
  return 1;
}

static void proton_engine_unload_cef_library(void) {
  if (g_proton_cef_library_loaded) {
    (void)cef_unload_library();
    g_proton_cef_library_loaded = 0;
  }
}

#include "../cef_common/strings.h"
#include "../cef_common/json_fields.h"

static void proton_engine_append_switch(cef_command_line_t *command_line,
                                        const char *name) {
  if (command_line == NULL || name == NULL || name[0] == '\0') {
    return;
  }
  cef_string_t switch_name = {0};
  proton_engine_set_string(&switch_name, name);
  command_line->append_switch(command_line, &switch_name);
  cef_string_clear(&switch_name);
}

static void proton_engine_append_switch_with_value(
    cef_command_line_t *command_line,
    const char *name,
    const char *value) {
  if (command_line == NULL || name == NULL || name[0] == '\0') {
    return;
  }
  cef_string_t switch_name = {0};
  cef_string_t switch_value = {0};
  proton_engine_set_string(&switch_name, name);
  proton_engine_set_string(&switch_value, value != NULL ? value : "");
  command_line->append_switch_with_value(command_line, &switch_name,
                                         &switch_value);
  cef_string_clear(&switch_name);
  cef_string_clear(&switch_value);
}

static int proton_engine_feature_list_contains(const char *features,
                                               const char *feature) {
  if (features == NULL || feature == NULL || feature[0] == '\0') {
    return 0;
  }
  size_t feature_len = strlen(feature);
  const char *cursor = features;
  while (*cursor != '\0') {
    while (*cursor == ',') {
      cursor++;
    }
    const char *end = strchr(cursor, ',');
    size_t entry_len = end != NULL ? (size_t)(end - cursor) : strlen(cursor);
    if (entry_len == feature_len && strncmp(cursor, feature, feature_len) == 0) {
      return 1;
    }
    if (end == NULL) {
      break;
    }
    cursor = end + 1;
  }
  return 0;
}

static void proton_engine_disable_feature(cef_command_line_t *command_line,
                                          const char *feature) {
  if (command_line == NULL || feature == NULL || feature[0] == '\0') {
    return;
  }
  cef_string_t switch_name = {0};
  proton_engine_set_string(&switch_name, "disable-features");
  char *current =
      proton_engine_userfree_to_utf8(command_line->get_switch_value(
          command_line, &switch_name));
  if (proton_engine_feature_list_contains(current, feature)) {
    free(current);
    cef_string_clear(&switch_name);
    return;
  }
  char merged[1024] = {0};
  if (current != NULL && current[0] != '\0') {
    snprintf(merged, sizeof(merged), "%s,%s", current, feature);
  } else {
    snprintf(merged, sizeof(merged), "%s", feature);
  }
  free(current);
#if CEF_API_ADDED(14100)
  if (command_line->remove_switch != NULL) {
    command_line->remove_switch(command_line, &switch_name);
  }
#endif
  cef_string_clear(&switch_name);
  proton_engine_append_switch_with_value(command_line, "disable-features",
                                         merged);
}

#define PROTON_ENGINE_REF_INCREMENT(refs) \
  atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) \
  (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) \
  atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../cef_common/bridge_json.h"

static int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

static int proton_engine_url_is_proton(const char *url) {
  return url != NULL && strncmp(url, "proton://", 9) == 0;
}

static proton_engine_client_t *proton_engine_client_from_base(
    cef_client_t *client) {
  return (proton_engine_client_t *)client;
}

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL || window->window_listed) {
    return;
  }
  window->next = g_windows;
  g_windows = window;
  window->window_listed = 1;
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
  proton_engine_window_t **cursor = &g_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      window->window_listed = 0;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static proton_engine_window_t *proton_engine_window_from_browser(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->browser_id == browser_id) {
      return window;
    }
  }
  return NULL;
}

static proton_engine_window_t *proton_engine_window_from_native_id(
    uint64_t native_id) {
  if (native_id == 0) {
    return NULL;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->native_id == native_id) {
      return window;
    }
  }
  return NULL;
}

uint64_t proton_engine_window_native_id(proton_engine_window_t *window) {
  return window != NULL ? window->native_id : 0;
}

NSWindow *proton_engine_window_get_native_window(proton_engine_window_t *window) {
  return window != NULL ? window->window : nil;
}

NSWindow *proton_engine_window_retain_native_window(
    proton_engine_window_t *window) {
  NSWindow *native_window = proton_engine_window_get_native_window(window);
  return native_window != nil ? [native_window retain] : nil;
}

int proton_engine_window_is_closed_or_missing(proton_engine_window_t *window) {
  return window == NULL || window->window == nil || window->closed;
}

proton_engine_window_t *proton_engine_window_lookup_native_id(
    uint64_t native_id) {
  return proton_engine_window_from_native_id(native_id);
}

proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser) {
  return proton_engine_window_from_browser(browser);
}

const char *proton_engine_window_html_url(proton_engine_window_t *window) {
  return window != NULL ? window->html_url : NULL;
}

const char *proton_engine_window_html(proton_engine_window_t *window,
                                     size_t *len) {
  if (len != NULL) {
    *len = window != NULL ? window->html_len : 0;
  }
  return window != NULL ? window->html : NULL;
}

proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window) {
  return window != NULL ? window->public_window_id : PROTON_INVALID_HANDLE;
}

proton_window_id_t
proton_engine_window_public_id_for_native_window(NSWindow *native_window) {
  if (native_window == nil) {
    return PROTON_INVALID_HANDLE;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->window == native_window) {
      return window->public_window_id;
    }
  }
  return PROTON_INVALID_HANDLE;
}

static int proton_engine_runtime_has_pending_platform_work(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->runtime != runtime) {
      continue;
    }
    if (window->browser_create_pending || window->browser_create_scheduled ||
        (window->browser != NULL && window->appkit_closing && !window->closed)) {
      return 1;
    }
  }
  return 0;
}

static void proton_engine_runtime_bridge_lock(proton_engine_runtime_t *runtime) {
  if (runtime != NULL && runtime->bridge_lock_initialized) {
    pthread_mutex_lock(&runtime->bridge_lock);
  }
}

static void proton_engine_runtime_bridge_unlock(
    proton_engine_runtime_t *runtime) {
  if (runtime != NULL && runtime->bridge_lock_initialized) {
    pthread_mutex_unlock(&runtime->bridge_lock);
  }
}

static int proton_engine_runtime_has_bridge_request(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  proton_engine_runtime_bridge_lock(runtime);
  int has_request = runtime->bridge_count > 0;
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
    ok = 1;
  }
  proton_engine_runtime_bridge_unlock(runtime);
  if (ok) {
    proton_engine_signal_wait_source(PROTON_WAIT_BRIDGE);
  }
  return ok;
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
  proton_engine_runtime_bridge_unlock(runtime);
  if (removed > 0) {
    proton_engine_debug_log("bridge_queue_remove request=%lld removed=%d",
                            (long long)request_id, removed);
  }
  return removed;
}

static size_t proton_engine_bridge_pending_count(void) {
  size_t count = 0;
  for (proton_engine_bridge_pending_t *pending = g_bridge_pending;
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
  pending->next = g_bridge_pending;
  g_bridge_pending = pending;
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
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
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
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
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
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  size_t removed_pending = 0;
  int removed_queued = 0;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      removed_queued += proton_engine_runtime_remove_bridge_request(
          runtime, request_id);
      proton_engine_debug_log("bridge_pending_remove request=%lld browser=%d",
                              (long long)request_id, browser_id);
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
  proton_engine_bridge_pending_t *pending = g_bridge_pending;
  g_bridge_pending = NULL;
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

static void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar) {
  (void)self;
  if (registrar == NULL) {
    return;
  }
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  // Give proton:// documents a real origin and allow CORS-mode same-origin
  // resources such as @font-face to reach the custom scheme handler.
  registrar->add_custom_scheme(
      registrar, &scheme,
      CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE |
          CEF_SCHEME_OPTION_CORS_ENABLED | CEF_SCHEME_OPTION_FETCH_ENABLED);
  cef_string_clear(&scheme);
}

static void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  (void)process_type;
  proton_engine_append_switch(command_line, "disable-background-networking");
  proton_engine_append_switch(command_line, "disable-component-update");
  proton_engine_append_switch(command_line, "disable-domain-reliability");
  proton_engine_append_switch(command_line, "disable-sync");
  proton_engine_append_switch(command_line, "metrics-recording-only");
  proton_engine_append_switch(command_line, "safebrowsing-disable-auto-update");
  proton_engine_append_switch(command_line, "use-mock-keychain");
  // Proton does not use Chrome's self-update code-sign clone path. Leaving it
  // enabled makes Chromium launch a macOS cleanup helper during shutdown, which
  // CEF apps do not need and which can crash packaged apps on recent Chromium.
  proton_engine_disable_feature(command_line, "MacAppCodeSignClone");
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
  g_browser_process_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_browser_process_handler.handler);
  return &g_browser_process_handler.handler;
}

static void proton_engine_window_mark_closed(proton_engine_window_t *window);
static void proton_engine_window_release_browser(proton_engine_window_t *window);
static void proton_engine_window_request_browser_close(
    proton_engine_window_t *window,
    int force_close);
static void proton_engine_window_free(proton_engine_window_t *window);
static void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window);
static int32_t proton_engine_window_create_browser(proton_engine_window_t *window,
                                                   const char *initial_url,
                                                   char *error,
                                                   size_t error_len);
static void proton_engine_drain_cef_close_work(void);
static void proton_engine_free_deferred_finalizing_windows(void);

static void proton_engine_window_load_initial_url(
    proton_engine_window_t *window) {
  if (window == NULL || window->closed || window->browser == NULL ||
      window->initial_url == NULL || window->initial_url[0] == '\0' ||
      strcmp(window->initial_url, "about:blank") == 0) {
    return;
  }
  char error[512] = {0};
  int32_t status = proton_engine_window_load_url(
      window, window->initial_url, error, sizeof(error));
  if (status != PROTON_OK) {
    proton_engine_debug_log("load_initial_url_failed status=%d error=%s",
                            status, error);
    proton_engine_window_mark_closed(window);
    proton_engine_window_request_browser_close(window, 1);
  }
}

static int CEF_CALLBACK proton_engine_on_before_popup(
    cef_life_span_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int popup_id,
    const cef_string_t *target_url,
    const cef_string_t *target_frame_name,
    cef_window_open_disposition_t target_disposition,
    int user_gesture,
    const cef_popup_features_t *popupFeatures,
    cef_window_info_t *windowInfo,
    cef_client_t **client,
    cef_browser_settings_t *settings,
    struct _cef_dictionary_value_t **extra_info,
    int *no_javascript_access) {
  (void)self;
  (void)browser;
  (void)frame;
  (void)popup_id;
  (void)target_url;
  (void)target_frame_name;
  (void)target_disposition;
  (void)user_gesture;
  (void)popupFeatures;
  (void)windowInfo;
  (void)client;
  (void)settings;
  (void)extra_info;
  (void)no_javascript_access;
  return 1;
}

static void CEF_CALLBACK proton_engine_on_after_created(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  if (browser == NULL) {
    return;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  cef_client_t *cef_client = host != NULL ? host->get_client(host) : NULL;
  proton_engine_client_t *client =
      cef_client != NULL ? proton_engine_client_from_base(cef_client) : NULL;
  proton_engine_window_t *window = client != NULL ? client->window : NULL;
  if (cef_client != NULL) {
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  if (window == NULL) {
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
  }

  browser->base.add_ref((cef_base_ref_counted_t *)browser);
  window->browser = browser;
  window->browser_id = browser->get_identifier(browser);
  window->browser_create_scheduled = 0;
  if (host != NULL) {
    window->browser_view = (__bridge NSView *)host->get_window_handle(host);
    host->base.release((cef_base_ref_counted_t *)host);
  }
  if (window->content_view != nil && window->browser_view != nil &&
      window->browser_view.superview == nil) {
    [window->content_view addSubview:window->browser_view];
  }
  if (window->content_view != nil && window->browser_view != nil) {
    [window->browser_view setFrame:window->content_view.bounds];
    [window->browser_view setAutoresizingMask:NSViewWidthSizable |
                                          NSViewHeightSizable];
  }
  proton_engine_debug_log("create_browser id=%d size=%dx%d",
                          window->browser_id, window->width, window->height);

  if (window->closed || window->finalize_after_browser_close) {
    proton_engine_window_request_browser_close(window, 1);
    proton_engine_window_release_browser(window);
    proton_engine_window_finalize_if_ready(window);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  window->initial_navigation_pending = 1;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL) {
    proton_engine_debug_log("browser_before_close browser=%d",
                            window->browser_id);
    window->browser_before_close_seen = 1;
    proton_engine_window_mark_closed(window);
    proton_engine_window_release_browser(window);
    if (window->window != nil && !window->appkit_closing) {
      [window->window close];
    }
    proton_engine_window_finalize_if_ready(window);
  }
}

static int CEF_CALLBACK proton_engine_do_close(cef_life_span_handler_t *self,
                                               cef_browser_t *browser) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL) {
    proton_engine_debug_log("browser_do_close browser=%d",
                            window->browser_id);
    window->cef_allows_appkit_close = 1;
  }
  return 0;
}

static cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self) {
  (void)self;
  g_life_span_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_life_span_handler.handler);
  return &g_life_span_handler.handler;
}

static cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self) {
  (void)self;
  g_load_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_load_handler.handler);
  return &g_load_handler.handler;
}

static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self) {
  (void)self;
  g_request_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_request_handler.handler);
  return &g_request_handler.handler;
}

static cef_render_process_handler_t *CEF_CALLBACK
proton_engine_get_render_process_handler(cef_app_t *self);
static void CEF_CALLBACK proton_engine_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context);
static void CEF_CALLBACK proton_engine_on_context_released(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context);
static cef_browser_process_handler_t *CEF_CALLBACK
proton_engine_get_browser_process_handler(cef_app_t *self);
static int CEF_CALLBACK proton_engine_renderer_on_process_message_received(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message);
static int CEF_CALLBACK proton_engine_v8_execute(
    cef_v8_handler_t *self,
    const cef_string_t *name,
    cef_v8_value_t *object,
    size_t argumentsCount,
    cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval,
    cef_string_t *exception);
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
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_errorcode_t errorCode, const cef_string_t *errorText,
    const cef_string_t *failedUrl);
static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string);

static void proton_engine_init_handlers(void) {
  static int initialized = 0;
  if (initialized) {
    return;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&g_app.app.base,
                                 sizeof(g_app.app), &g_app.refs);
  g_app.app.on_before_command_line_processing =
      proton_engine_on_before_command_line_processing;
  g_app.app.on_register_custom_schemes =
      proton_engine_on_register_custom_schemes;
  g_app.app.get_browser_process_handler =
      proton_engine_get_browser_process_handler;
  g_app.app.get_render_process_handler =
      proton_engine_get_render_process_handler;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_browser_process_handler.handler.base,
      sizeof(g_browser_process_handler.handler), &g_browser_process_handler.refs);
  g_browser_process_handler.handler.on_schedule_message_pump_work =
      proton_engine_on_schedule_message_pump_work;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_render_process_handler.handler.base,
      sizeof(g_render_process_handler.handler), &g_render_process_handler.refs);
  g_render_process_handler.handler.on_context_created =
      proton_engine_on_context_created;
  g_render_process_handler.handler.on_context_released =
      proton_engine_on_context_released;
  g_render_process_handler.handler.on_browser_created =
      proton_engine_bridge_renderer_on_browser_created;
  g_render_process_handler.handler.on_browser_destroyed =
      proton_engine_bridge_renderer_on_browser_destroyed;
  g_render_process_handler.handler.on_process_message_received =
      proton_engine_renderer_on_process_message_received;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_v8_handler.handler.base,
      sizeof(g_v8_handler.handler), &g_v8_handler.refs);
  g_v8_handler.handler.execute = proton_engine_v8_execute;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_life_span_handler.handler.base,
      sizeof(g_life_span_handler.handler), &g_life_span_handler.refs);
  g_life_span_handler.handler.on_before_popup = proton_engine_on_before_popup;
  g_life_span_handler.handler.on_after_created = proton_engine_on_after_created;
  g_life_span_handler.handler.do_close = proton_engine_do_close;
  g_life_span_handler.handler.on_before_close = proton_engine_on_before_close;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_load_handler.handler.base,
      sizeof(g_load_handler.handler), &g_load_handler.refs);
  g_load_handler.handler.on_load_start = proton_engine_on_load_start;
  g_load_handler.handler.on_load_end = proton_engine_on_load_end;
  g_load_handler.handler.on_load_error = proton_engine_on_load_error;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_request_handler.handler.base,
      sizeof(g_request_handler.handler), &g_request_handler.refs);
  g_request_handler.handler.on_render_process_terminated =
      proton_engine_on_render_process_terminated;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_scheme_factory.factory.base,
      sizeof(g_scheme_factory.factory), &g_scheme_factory.refs);
  g_scheme_factory.factory.create = proton_engine_scheme_create;
  initialized = 1;
}

static int proton_engine_register_scheme_factory(void) {
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  int ok =
      cef_register_scheme_handler_factory(&scheme, NULL,
                                          &g_scheme_factory.factory);
  cef_string_clear(&scheme);
  return ok;
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
  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
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
  if (!proton_engine_send_bridge_request_to_browser(
          frame, pending_id, op, payload_json, page_instance)) {
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

static void CEF_CALLBACK proton_engine_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  (void)self;
  proton_engine_bridge_renderer_on_context_created(
      browser, frame, context, &g_v8_handler.handler);
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
  g_render_process_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_render_process_handler.handler);
  return &g_render_process_handler.handler;
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
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
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
      int url_matches = url != NULL && current_url != NULL &&
                        strcmp(url, current_url) == 0;
      int updated =
          url_matches
              ? proton_engine_bridge_lifecycle_update(
                    &window->bridge_lifecycle, outcome, page_instance,
                    current_url,
                    diagnostic != NULL && diagnostic[0] != '\0' ? diagnostic
                                                                 : NULL)
              : 0;
      proton_engine_debug_log(
          "bridge_lifecycle browser=%d outcome=%s page=%s url_matches=%d updated=%d revision=%llu",
          browser_id, outcome != NULL ? outcome : "",
          page_instance != NULL ? page_instance : "", url_matches, updated,
          (unsigned long long)proton_engine_bridge_lifecycle_revision(
              &window->bridge_lifecycle));
      free(current_url);
      if (main_frame != NULL) {
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
      free(outcome);
      free(page_instance);
      free(url);
      free(diagnostic);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_debug_log("browser_bridge_request browser=%d pending=%d op=%s",
                          browser_id, renderer_pending_id,
                          op != NULL ? op : "");

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

static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_transition_type_t transition_type) {
  (void)self;
  (void)transition_type;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_debug_log("load_start browser=%d main=%d url=%s",
                          proton_engine_browser_id(browser),
                          frame != NULL ? frame->is_main(frame) : 0,
                          url != NULL ? url : "");
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
  proton_engine_debug_log("load_end browser=%d main=%d status=%d url=%s",
                          proton_engine_browser_id(browser),
                          frame != NULL ? frame->is_main(frame) : 0,
                          httpStatusCode, url != NULL ? url : "");
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL && window->initial_navigation_pending && frame != NULL &&
      frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") == 0) {
    window->initial_navigation_pending = 0;
    proton_engine_window_load_initial_url(window);
  }
  if (window != NULL && window->bridge_config_json != NULL && frame != NULL &&
      frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") != 0) {
    (void)proton_engine_bridge_send_lifecycle_probe(frame);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_errorcode_t errorCode, const cef_string_t *errorText,
    const cef_string_t *failedUrl) {
  (void)self;
  (void)errorCode;
  if (frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  char *message = proton_engine_cef_string_to_utf8(errorText);
  char *url = proton_engine_cef_string_to_utf8(failedUrl);
  if (window != NULL && window->bridge_config_json != NULL && url != NULL) {
    proton_engine_bridge_lifecycle_report_browser_failure(
        &window->bridge_lifecycle, url, "entry_load_failed",
        message != NULL && message[0] != '\0' ? message
                                               : "main frame failed to load",
        0);
  }
  free(message);
  free(url);
}

static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window == NULL || window->bridge_config_json == NULL || window->closing) {
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
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
  free(detail);
  free(url);
  if (frame != NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
  }
}

static proton_engine_client_t *proton_engine_client_create(
    proton_engine_window_t *window) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->window = window;
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_request_handler =
      proton_engine_client_get_request_handler;
  client->client.on_process_message_received =
      proton_engine_client_on_process_message_received;
  return client;
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
  if (!proton_engine_dir_exists(config->locales_dir)) {
    config->locales_dir[0] = '\0';
  }
  char frameworks_dir[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  if (!proton_engine_join_path(frameworks_dir, sizeof(frameworks_dir),
                               config->runtime_root, "Frameworks") ||
      !proton_engine_join_path(config->framework_dir,
                               sizeof(config->framework_dir), frameworks_dir,
                               "Chromium Embedded Framework.framework")) {
    proton_engine_set_message(error, error_len,
                              "runtime framework path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_parse_json_string_field(config_json, "cache_dir",
                                        config->cache_dir,
                                        sizeof(config->cache_dir));
  if (config->cache_dir[0] == '\0') {
    const char *tmp_dir = getenv("TMPDIR");
    if (tmp_dir == NULL || tmp_dir[0] == '\0') {
      tmp_dir = "/tmp";
    }
    int written = snprintf(config->cache_dir, sizeof(config->cache_dir),
                           "%s%sproton-cef-%ld", tmp_dir,
                           tmp_dir[strlen(tmp_dir) - 1] == '/' ? "" : "/",
                           (long)getpid());
    if (written < 0 || (size_t)written >= sizeof(config->cache_dir)) {
      proton_engine_set_message(error, error_len,
                                "runtime cache_dir path is too long");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
    mkdir(config->cache_dir, 0700);
  }
  proton_engine_parse_json_int_field(config_json, "remote_debugging_port",
                                     &config->remote_debugging_port);
  return PROTON_OK;
}

static int32_t proton_engine_parse_window_config(
    const char *config_json,
    proton_engine_window_config_t *config,
    char *error,
    size_t error_len) {
  if (config_json == NULL || config == NULL) {
    proton_engine_set_message(error, error_len, "window config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(config, 0, sizeof(*config));
  if (!proton_engine_parse_json_string_field(config_json, "title",
                                             config->title,
                                             sizeof(config->title))) {
    snprintf(config->title, sizeof(config->title), "%s", "Proton");
  }
  if (!proton_engine_parse_json_int_field(config_json, "width",
                                          &config->width)) {
    config->width = 800;
  }
  if (!proton_engine_parse_json_int_field(config_json, "height",
                                          &config->height)) {
    config->height = 600;
  }
  proton_engine_parse_json_string_field(config_json, "initial_url",
                                        config->initial_url,
                                        sizeof(config->initial_url));
  return PROTON_OK;
}

static void proton_engine_browser_release(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static void proton_engine_window_release_browser(proton_engine_window_t *window) {
  if (window != NULL && window->browser != NULL) {
    cef_browser_t *browser = window->browser;
    window->browser = NULL;
    proton_engine_browser_release(browser);
  }
}

static void proton_engine_window_request_browser_close(
    proton_engine_window_t *window,
    int force_close) {
  if (window == NULL || window->browser == NULL) {
    return;
  }
  if (window->browser_close_requested && !force_close) {
    return;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host != NULL) {
    window->browser_close_requested = 1;
    host->close_browser(host, force_close);
    host->base.release((cef_base_ref_counted_t *)host);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_window_mark_closed(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  if (!window->closed) {
    proton_engine_debug_log("window_closed browser=%d", window->browser_id);
  }
  window->closed = 1;
  proton_engine_bridge_pending_remove_browser(window->runtime,
                                              window->browser_id);
  proton_engine_dialog_complete_window_closed(window->native_id);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static int proton_engine_request_all_windows_close(void) {
  int requested = 0;
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->closed) {
      continue;
    }
    requested = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->close_browser(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
        continue;
      }
    }
    proton_engine_window_mark_closed(window);
    if (window->window != nil) {
      [window->window close];
    }
  }
  return requested;
}

@interface ProtonWindowDelegate : NSObject <NSWindowDelegate> {
@public
  proton_engine_window_t *window;
}
@end

@implementation ProtonWindowDelegate
- (BOOL)windowShouldClose:(id)sender {
  (void)sender;
  if (window == NULL || window->closed) {
    return YES;
  }
  if (window->browser == NULL) {
    window->appkit_closing = 1;
    return YES;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    window->appkit_closing = 1;
    return YES;
  }
  int allow_close = 0;
  if (host->is_ready_to_be_closed != NULL &&
      host->is_ready_to_be_closed(host)) {
    allow_close = 1;
    window->appkit_closing = 1;
  } else if (host->try_close_browser != NULL) {
    window->browser_close_requested = 1;
    allow_close = host->try_close_browser(host);
    if (allow_close) {
      window->appkit_closing = 1;
    }
  } else if (window->cef_allows_appkit_close) {
    allow_close = 1;
    window->appkit_closing = 1;
  } else {
    window->browser_close_requested = 1;
    host->close_browser(host, 0);
  }
  proton_engine_debug_log("window_should_close browser=%d allow=%d",
                          window->browser_id, allow_close);
  host->base.release((cef_base_ref_counted_t *)host);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return allow_close ? YES : NO;
}

- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  if (window == NULL) {
    return;
  }
  proton_engine_debug_log("window_will_close browser=%d", window->browser_id);
  window->appkit_closing = 1;
  if (window->browser != NULL) {
    // AppKit has already closed the user-visible window. Publish that lifecycle
    // edge immediately; CEF on_before_close is only browser resource cleanup.
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    proton_engine_window_mark_closed(window);
    if (window->browser_view != nil) {
      [window->browser_view removeFromSuperview];
    }
  } else {
    proton_engine_window_mark_closed(window);
  }
  window->window = nil;
  window->content_view = nil;
  window->browser_view = nil;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}
@end

@interface ProtonApplication : NSApplication <CefAppProtocol> {
@private
  BOOL handlingSendEvent_;
}
@end

@implementation ProtonApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  BOOL wasHandling = handlingSendEvent_;
  handlingSendEvent_ = YES;
  [super sendEvent:event];
  handlingSendEvent_ = wasHandling;
}

- (void)terminate:(id)sender {
  (void)sender;
  proton_engine_debug_log("app_terminate");
  g_proton_app_terminating = 1;
  if (g_proton_cef_initialized && proton_engine_request_all_windows_close()) {
    return;
  }
  [super terminate:sender];
}
@end

static void proton_engine_ensure_appkit(void) {
  [ProtonApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp finishLaunching];
  proton_engine_menu_install_default();
}

static char *proton_engine_data_url_for_html(const char *html) {
  if (html == NULL) {
    html = "";
  }
  const char *prefix = "data:text/html;charset=utf-8,";
  size_t prefix_len = strlen(prefix);
  size_t html_len = strlen(html);
  size_t max_len = prefix_len + html_len * 3 + 1;
  char *url = (char *)malloc(max_len);
  if (url == NULL) {
    return NULL;
  }
  memcpy(url, prefix, prefix_len);
  char *out = url + prefix_len;
  static const char hex[] = "0123456789ABCDEF";
  for (size_t i = 0; i < html_len; i++) {
    unsigned char c = (unsigned char)html[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
        c == '~') {
      *out++ = (char)c;
    } else {
      *out++ = '%';
      *out++ = hex[c >> 4];
      *out++ = hex[c & 15];
    }
  }
  *out = '\0';
  return url;
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    cef_shutdown();
    g_proton_cef_initialized = 0;
  }
}

static void proton_engine_check_cef_api_hash(void) {
#ifdef CEF_API_VERSION
  (void)cef_api_hash(CEF_API_VERSION, 0);
#else
  (void)cef_api_hash(0);
#endif
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
  if (!proton_engine_load_cef_library(&config, error, error_len)) {
    return PROTON_ERR_ENGINE;
  }
  proton_engine_check_cef_api_hash();
  cef_main_args_t args;
  memset(&args, 0, sizeof(args));
  args.argc = *_NSGetArgc();
  args.argv = *_NSGetArgv();
  proton_engine_init_handlers();
  int exit_code = cef_execute_process(&args, &g_app.app, NULL);
  proton_engine_unload_cef_library();
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

  if (!proton_engine_load_cef_library(&config, error, error_len)) {
    return PROTON_ERR_ENGINE;
  }
  proton_engine_ensure_appkit();
  proton_engine_init_handlers();
  proton_engine_check_cef_api_hash();
  if (!proton_engine_setup_wait_source(error, error_len)) {
    proton_engine_unload_cef_library();
    return PROTON_ERR_ENGINE;
  }

  cef_main_args_t args;
  cef_settings_t settings;
  memset(&args, 0, sizeof(args));
  args.argc = *_NSGetArgc();
  args.argv = *_NSGetArgv();
  memset(&settings, 0, sizeof(settings));
  settings.size = sizeof(settings);
  settings.no_sandbox = 1;
  settings.multi_threaded_message_loop = 0;
  settings.external_message_pump = 1;
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  settings.remote_debugging_port = config.remote_debugging_port;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.framework_dir_path, config.framework_dir);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  if (config.cache_dir[0] != '\0') {
    proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, &g_app.app, NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.framework_dir_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.root_cache_path);
    proton_engine_teardown_wait_source();
    proton_engine_unload_cef_library();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_debug_log("runtime_create remote_debugging_port=%d",
                          config.remote_debugging_port);

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.framework_dir_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.root_cache_path);

  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(*runtime));
  if (runtime == NULL) {
    proton_engine_cef_shutdown();
    proton_engine_teardown_wait_source();
    proton_engine_set_message(error, error_len,
                              "failed to allocate runtime state");
    return PROTON_ERR_ENGINE;
  }
  runtime->owns_cef_runtime = 1;
  runtime->next_bridge_request_id = 1;
  if (pthread_mutex_init(&runtime->bridge_lock, NULL) == 0) {
    runtime->bridge_lock_initialized = 1;
  }
  g_proton_cef_initialized = 1;
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    proton_engine_teardown_wait_source();
    g_proton_cef_runtime_active = 0;
    proton_engine_set_message(error, error_len,
                              "failed to register proton scheme handler");
    return PROTON_ERR_ENGINE;
  }
  if (!g_proton_cef_shutdown_registered) {
    atexit(proton_engine_cef_shutdown);
    g_proton_cef_shutdown_registered = 1;
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
  proton_engine_dialog_dispose_runtime(runtime);
  proton_engine_menu_clear_runtime(runtime);
  if (runtime->owns_cef_runtime) {
    proton_engine_runtime_clear_bridge_queue(runtime);
    proton_engine_bridge_pending_clear_all();
    proton_engine_drain_cef_close_work();
    proton_engine_cef_shutdown();
    proton_engine_free_deferred_finalizing_windows();
    proton_engine_teardown_wait_source();
    runtime->owns_cef_runtime = 0;
  }
  if (runtime->bridge_lock_initialized) {
    pthread_mutex_destroy(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
  }
  g_proton_cef_runtime_active = 0;
  free(runtime);
  return PROTON_OK;
}

static void proton_engine_runtime_create_pending_browsers(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->runtime != runtime || !window->browser_create_pending ||
        window->browser_create_scheduled || window->closed) {
      continue;
    }
    uint64_t native_id = window->native_id;
    window->browser_create_scheduled = 1;
    // Create CEF browsers after the main run loop has started pumping.
    dispatch_async(dispatch_get_main_queue(), ^{
      proton_engine_window_t *pending_window =
          proton_engine_window_from_native_id(native_id);
      if (pending_window == NULL) {
        return;
      }
      if (pending_window->closed || !pending_window->browser_create_pending) {
        pending_window->browser_create_scheduled = 0;
        proton_engine_window_finalize_if_ready(pending_window);
        proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
        return;
      }
      pending_window->browser_create_pending = 0;
      char error[512] = {0};
      // TODO(CEF issue 3810): See
      // https://github.com/chromiumembedded/cef/issues/3810. Keep browser
      // creation scheduled after the macOS run loop is pumping, and don't let
      // CEF's initial navigation touch Proton resources before cef_browser_t has
      // been registered to this window. Create about:blank first, then navigate
      // after browser_id exists.
      int32_t status = proton_engine_window_create_browser(
          pending_window, "about:blank", error, sizeof(error));
      if (status != PROTON_OK) {
        pending_window->browser_create_scheduled = 0;
        proton_engine_debug_log("create_browser_failed status=%d error=%s",
                                status, error);
        proton_engine_window_mark_closed(pending_window);
        proton_engine_window_finalize_if_ready(pending_window);
      }
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    });
  }
}

static void proton_engine_pump_appkit_cef_once(void) {
  // The host drives this pump from its own event loop and never enters the
  // AppKit run loop, so nothing ever drains the thread's autorelease state.
  // Without this pool every tick's autoreleased objects (NSEvent, AppKit
  // window-cache enumeration, CEF's ObjC work) are immortal — and with
  // Chromium's allocator shim owning the default malloc zone they pile up
  // inside PartitionAlloc's reservation until the address space fragments
  // into hundreds of thousands of VM regions and an allocation finally
  // traps. Observed as an overnight-idle SIGTRAP under autoreleaseFullPage.
  @autoreleasepool {
    bool sent_event = false;
    for (;;) {
      NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                          untilDate:[NSDate distantPast]
                                             inMode:NSDefaultRunLoopMode
                                            dequeue:YES];
      if (event == nil) {
        break;
      }
      [NSApp sendEvent:event];
      sent_event = true;
    }
    // AppKit's own loop only updates windows after dispatching an event.
    // This pump runs ~60x/s at idle; an unconditional updateWindows posts
    // window-cache notifications (and their allocation churn) on every one
    // of those empty ticks, which slowly burns PartitionAlloc address space
    // via Chromium's allocator shim.
    if (sent_event) {
      [NSApp updateWindows];
    }
    cef_do_message_loop_work();
  }
}

static void proton_engine_drain_cef_close_work(void) {
  if (!g_proton_cef_initialized) {
    return;
  }
  // CEF may schedule immediate cleanup work while closing the last browser.
  // Drain only immediate external-message-pump work; do not sleep here.
  for (int i = 0; i < 32; i++) {
    proton_engine_reset_scheduled_pump();
    proton_engine_pump_appkit_cef_once();
    if (proton_engine_get_scheduled_pump_delay_ms() != 0) {
      break;
    }
  }
}

static void proton_engine_free_deferred_finalizing_windows(void) {
  proton_engine_window_t *window = g_windows;
  while (window != NULL) {
    proton_engine_window_t *next = window->next;
    if (window->finalize_after_browser_close) {
      window->browser_before_close_seen = 1;
      proton_engine_window_release_browser(window);
      proton_engine_window_finalize_if_ready(window);
    }
    window = next;
  }
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
  proton_engine_runtime_create_pending_browsers(runtime);
  proton_engine_pump_appkit_cef_once();
  return PROTON_OK;
}

static uint32_t proton_engine_runtime_ready_mask(
    proton_engine_runtime_t *runtime,
    uint32_t interest_mask) {
  uint32_t ready_mask = PROTON_WAIT_NONE;
  if ((interest_mask & PROTON_WAIT_BRIDGE) != 0 &&
      proton_engine_runtime_has_bridge_request(runtime)) {
    ready_mask |= PROTON_WAIT_BRIDGE;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      (proton_engine_get_scheduled_pump_delay_ms() == 0 ||
       proton_engine_runtime_has_pending_platform_work(runtime))) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  return ready_mask & interest_mask;
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

  proton_engine_runtime_create_pending_browsers(runtime);
  uint32_t ready_mask = proton_engine_runtime_ready_mask(runtime, interest_mask);
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
    *out_ready_mask = ready_mask;
    return PROTON_OK;
  }

  uint32_t wait_timeout = timeout_ms;
  int waiting_for_scheduled_pump = 0;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
    int64_t scheduled_delay = proton_engine_get_scheduled_pump_delay_ms();
    if (scheduled_delay > 0 && scheduled_delay <= (int64_t)wait_timeout) {
      wait_timeout = (uint32_t)scheduled_delay;
      waiting_for_scheduled_pump = 1;
    }
  }

  atomic_store_explicit(&g_wait_source_ready_mask, PROTON_WAIT_NONE,
                        memory_order_release);
  CFRunLoopRunResult run_result = kCFRunLoopRunTimedOut;
  CFAbsoluteTime start_time = CFAbsoluteTimeGetCurrent();
  if (wait_timeout > 0) {
    CFTimeInterval seconds = ((CFTimeInterval)wait_timeout) / 1000.0;
    // Same reasoning as the pump: run-loop sources and timers autorelease,
    // and no outer pool exists on the host's main thread.
    @autoreleasepool {
      run_result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, true);
    }
  }
  CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start_time;

  uint32_t signaled_mask = atomic_exchange_explicit(
      &g_wait_source_ready_mask, PROTON_WAIT_NONE, memory_order_acquire);
  ready_mask |= signaled_mask & interest_mask;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
    if (run_result == kCFRunLoopRunHandledSource ||
        run_result == kCFRunLoopRunStopped) {
      int bridge_only_source =
          (signaled_mask & PROTON_WAIT_BRIDGE) != 0 &&
          (signaled_mask & PROTON_WAIT_PLATFORM) == 0;
      if (!bridge_only_source) {
        ready_mask |= PROTON_WAIT_PLATFORM;
      }
    } else if (waiting_for_scheduled_pump &&
               elapsed * 1000.0 >= (CFAbsoluteTime)wait_timeout) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  }
  ready_mask |= proton_engine_runtime_ready_mask(runtime, interest_mask);
  ready_mask &= interest_mask;
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
  }
  *out_ready_mask = ready_mask;
  return PROTON_OK;
}

int32_t proton_engine_runtime_set_menu_json(proton_engine_runtime_t *runtime,
                                            const char *menu_json,
                                            char *error,
                                            size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (menu_json == NULL) {
    proton_engine_set_message(error, error_len, "menu_json is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  __block int32_t status = PROTON_OK;
  char main_error[512] = {0};
  char *main_error_buffer = main_error;
  void (^work)(void) = ^{
    status = proton_engine_menu_set_json_on_main(
        menu_json, main_error_buffer, sizeof(main_error));
  };
  if ([NSThread isMainThread]) {
    work();
  } else {
    dispatch_sync(dispatch_get_main_queue(), work);
  }
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len, main_error);
  } else {
    proton_engine_menu_set_runtime(runtime);
  }
  return status;
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
  size_t queued = runtime->bridge_count;
  proton_engine_runtime_bridge_unlock(runtime);
  int64_t request_id = 0;
  (void)proton_engine_json_read_int64_field(request_json, "request_id",
                                            &request_id);
  proton_engine_debug_log("bridge_dequeue request=%lld queued=%zu",
                          (long long)request_id, queued);
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
      error_message = proton_engine_json_copy_string_field(response_json,
                                                           "message");
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
  proton_engine_debug_log("bridge_response_sent request=%lld",
                          (long long)request_id);
  return PROTON_OK;
}

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
  proton_engine_debug_log("create_browser_start initial_url=%s size=%dx%d",
                          initial_url != NULL ? initial_url : "",
                          window != NULL ? window->width : 0,
                          window != NULL ? window->height : 0);
  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  if (window->content_view != nil) {
    window_info.parent_view = (__bridge void *)window->content_view;
  }
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = window->width;
  window_info.bounds.height = window->height;
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
  int accepted = cef_browser_host_create_browser(
      &window_info, &window->client->client, &url, &browser_settings,
      extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  proton_engine_debug_log("create_browser_accepted accepted=%d", accepted);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (!accepted) {
    proton_engine_set_message(error, error_len, "browser creation failed");
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
  proton_engine_window_config_t config;
  int32_t status =
      proton_engine_parse_window_config(config_json, &config, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }

  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate window state");
    return PROTON_ERR_ENGINE;
  }
  window->runtime = runtime;
  window->native_id = g_next_window_native_id++;
  if (g_next_window_native_id == 0) {
    g_next_window_native_id = 1;
  }
  window->width = config.width;
  window->height = config.height;
  window->bridge_config_json =
      proton_engine_json_copy_raw_field(config_json, "bridge");
  window->max_bridge_payload_bytes = PROTON_ENGINE_MAX_BRIDGE_BYTES;
  if (window->bridge_config_json != NULL) {
    proton_engine_bridge_config_read_max_payload(
        window->bridge_config_json, &window->max_bridge_payload_bytes);
  }
  window->client = proton_engine_client_create(window);
  if (window->client == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  NSRect rect = NSMakeRect(0, 0, config.width, config.height);
  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                     NSWindowStyleMaskMiniaturizable |
                     NSWindowStyleMaskResizable;
  NSString *title = [NSString stringWithUTF8String:config.title];
  window->window = [[NSWindow alloc] initWithContentRect:rect
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
  if (window->window == nil) {
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "window creation failed");
    return PROTON_ERR_PLATFORM;
  }
  [window->window setReleasedWhenClosed:YES];
  [window->window setTitle:title != nil ? title : @"Proton"];
  [window->window center];
  window->content_view = [window->window contentView];
  ProtonWindowDelegate *delegate = [[ProtonWindowDelegate alloc] init];
  delegate->window = window;
  window->delegate = delegate;
  [window->window setDelegate:delegate];

  proton_engine_debug_log("window_create title=%s size=%dx%d initial_url=%s",
                          config.title, config.width, config.height,
                          config.initial_url);

  window->initial_url =
      proton_engine_strdup(config.initial_url[0] != '\0' ? config.initial_url
                                                         : "about:blank");
  if (window->initial_url == NULL) {
    [window->window close];
    [delegate release];
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to copy initial browser url");
    return PROTON_ERR_ENGINE;
  }
  window->browser_create_pending = 1;
  proton_engine_window_list_add(window);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  *out_window = window;
  return PROTON_OK;
}

static void proton_engine_window_free(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  if (window->delegate != nil) {
    [window->delegate release];
    window->delegate = nil;
  }
  free(window->client);
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  free(window->initial_url);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
}

static void proton_engine_window_detach_native_window(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == nil) {
    if (window != NULL) {
      window->content_view = nil;
      window->browser_view = nil;
    }
    return;
  }
  NSWindow *native_window = window->window;
  window->window = nil;
  window->content_view = nil;
  window->browser_view = nil;
  [native_window setDelegate:nil];
  [native_window close];
}

static void proton_engine_window_defer_finalize(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  if (!window->finalize_after_browser_close && window->browser_id != 0) {
    proton_engine_debug_log("browser_close_deferred browser=%d",
                            window->browser_id);
  }
  window->finalize_after_browser_close = 1;
  window->browser_create_pending = 0;
  window->runtime = NULL;
  if (window->client != NULL && !window->browser_create_scheduled) {
    window->client->window = NULL;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window) {
  if (window == NULL || !window->finalize_after_browser_close) {
    return;
  }
  if (window->browser_create_scheduled) {
    return;
  }
  if (window->browser_id != 0 && !window->browser_before_close_seen) {
    return;
  }
  proton_engine_window_list_remove(window);
  if (window->client != NULL) {
    window->client->window = NULL;
  }
  proton_engine_window_detach_native_window(window);
  proton_engine_window_free(window);
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  (void)error;
  (void)error_len;
  proton_engine_window_mark_closed(window);
  if (window->browser != NULL) {
    proton_engine_window_request_browser_close(window, 1);
    proton_engine_window_defer_finalize(window);
    proton_engine_window_release_browser(window);
    proton_engine_window_finalize_if_ready(window);
    return PROTON_OK;
  }
  proton_engine_window_defer_finalize(window);
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  [window->window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  [window->window orderOut:nil];
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->browser != NULL) {
    proton_engine_window_request_browser_close(window, 0);
    return PROTON_OK;
  }
  [window->window close];
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  [window->window makeKeyAndOrderFront:nil];
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  NSString *value = [NSString stringWithUTF8String:title != NULL ? title : ""];
  [window->window setTitle:value != nil ? value : @""];
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->window == nil) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  NSRect frame = [window->window frame];
  frame.size.width = width;
  frame.size.height = height;
  [window->window setFrame:frame display:YES animate:NO];
  window->width = width;
  window->height = height;
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((window->browser == NULL &&
       (window->browser_create_pending || window->browser_create_scheduled)) ||
      window->initial_navigation_pending) {
    char *url_copy =
        proton_engine_strdup(url != NULL && url[0] != '\0' ? url : "about:blank");
    if (url_copy == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
    free(window->initial_url);
    window->initial_url = url_copy;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t cef_url = {0};
  proton_engine_set_string(&cef_url, url != NULL ? url : "about:blank");
  proton_engine_debug_log("load_url browser=%d url=%s", window->browser_id,
                          url != NULL ? url : "about:blank");
  frame->load_url(frame, &cef_url);
  cef_string_clear(&cef_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_load_html(proton_engine_window_t *window,
                                       const char *html,
                                       const char *base_url,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (html == NULL) {
    html = "";
  }
  const char *effective_base_url =
      base_url != NULL && base_url[0] != '\0' ? base_url : "proton://app/";
  if (!proton_engine_url_is_proton(effective_base_url)) {
    proton_engine_set_message(error, error_len,
                              "base_url must use the proton:// scheme");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char *url_copy = proton_engine_strdup(effective_base_url);
  char *html_copy = proton_engine_strdup(html);
  char *pending_url = NULL;
  if (url_copy == NULL || html_copy == NULL) {
    free(url_copy);
    free(html_copy);
    proton_engine_set_message(error, error_len, "failed to copy html");
    return PROTON_ERR_ENGINE;
  }
  if ((window->browser == NULL &&
       (window->browser_create_pending || window->browser_create_scheduled)) ||
      window->initial_navigation_pending) {
    pending_url = proton_engine_strdup(effective_base_url);
    if (pending_url == NULL) {
      free(url_copy);
      free(html_copy);
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
  }
  free(window->html_url);
  free(window->html);
  window->html_url = url_copy;
  window->html = html_copy;
  window->html_len = strlen(html_copy);
  if (pending_url != NULL) {
    free(window->initial_url);
    window->initial_url = pending_url;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  proton_engine_debug_log("load_html browser=%d base_url=%s bytes=%llu",
                          window->browser_id, effective_base_url,
                          (unsigned long long)window->html_len);
  int32_t status = proton_engine_window_load_url(window, effective_base_url,
                                                 error, error_len);
  return status;
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
  cef_string_t script_url = {0};
  proton_engine_set_string(&code, script != NULL ? script : "");
  proton_engine_set_string(&script_url, "proton://eval.js");
  frame->execute_java_script(frame, &code, &script_url, 1);
  cef_string_clear(&code);
  cef_string_clear(&script_url);
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
