#include "../../proton_engine.h"
#include "../../proton_config.h"
#include "../../proton_json.h"

#include "dialog.h"
#include "launch_input.h"
#include "platform_events.h"
#include "menu.h"
#include "window.h"

#include "../cef_common/document.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#import "include/cef_application_mac.h"
#include "include/internal/cef_string.h"
#include "include/wrapper/cef_library_loader.h"

#include "../cef_common/app_origin.h"
#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/bridge_response.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/view_events.h"

#import <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

#include <ctype.h>
#include <crt_externs.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define PROTON_ENGINE_MAX_PATH_BYTES 4096
#define PROTON_ENGINE_MAX_URL_BYTES 131072
#define PROTON_ENGINE_MAX_BRIDGE_REQUESTS 256
#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
/* NSScreen and other AppKit state must be accessed on the main thread.
   When the ABI is invoked from a worker thread, marshal the wrapped call
   to the main queue synchronously and return its status. */
#define PROTON_ENGINE_RETURN_ON_MAIN(body)                     \
  if (![NSThread isMainThread]) {                              \
    __block int32_t proton_engine_main_status = PROTON_OK;     \
    dispatch_sync(dispatch_get_main_queue(), ^{                \
      proton_engine_main_status = (body);                      \
    });                                                        \
    return proton_engine_main_status;                          \
  }
typedef struct proton_engine_client proton_engine_client_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  char *asset_root;
  int64_t next_bridge_request_id;
  char *bridge_queue[PROTON_ENGINE_MAX_BRIDGE_REQUESTS];
  size_t bridge_head;
  size_t bridge_count;
  int64_t bridge_cancellations[PROTON_ENGINE_MAX_BRIDGE_REQUESTS];
  size_t bridge_cancellation_head;
  size_t bridge_cancellation_count;
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
  int close_interception_enabled;
  int close_interception_bypass;
  int close_request_pending;
  uint64_t close_request_id;
  proton_browser_session_t *browser_session;
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
  int zoom_percent;
  int headless;
  int headless_hidden;
  int headless_focused;
  int osr_paint_seen;
  int osr_paint_width;
  int osr_paint_height;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int closed;
  int closing;
  struct proton_engine_view *views;
  struct proton_engine_window *next;
};

typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_engine_window_t *window;
  proton_engine_view_t *view;
};

/* A web contents view: an extra browser hosted inside a window's content
   view, positioned in top-left content coordinates. Views own a browser and
   an NSView but no NSWindow; their teardown mirrors the window browser
   close/finalize state machine and is gated on CEF's on_before_close. The
   struct itself is owned by the window's view list and is only freed from
   proton_engine_window_free, so native ABI slots can never hold a dangling
   pointer regardless of how the view was closed. */
struct proton_engine_view {
  proton_engine_window_t *window;
  proton_engine_client_t *client;
  cef_browser_t *browser;
  int browser_id;
  NSView *browser_view;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int visible;
  uint64_t native_id;
  char *initial_url;
  int initial_navigation_pending;
  int browser_create_pending;
  int browser_create_scheduled;
  int browser_close_requested;
  int browser_before_close_seen;
  int finalize_after_browser_close;
  int finalized;
  int osr_paint_seen;
  int closed;
  char *html_url;
  char *html;
  size_t html_len;
  proton_browser_session_t *browser_session;
  proton_view_events_t *events;
  int has_background_color;
  uint32_t background_color;
  struct proton_engine_view *next;
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
  cef_download_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_download_handler_t;

typedef struct {
  cef_permission_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_permission_handler_t;

typedef struct {
  cef_render_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_render_handler_t;

typedef struct {
  cef_display_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_display_handler_t;

typedef struct {
  cef_scheme_handler_factory_t factory;
  proton_engine_ref_counted_t refs;
} proton_engine_scheme_factory_t;

typedef struct {
  cef_task_t task;
  proton_engine_ref_counted_t refs;
  uint64_t native_id;
} proton_engine_initial_navigation_task_t;

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
  int headless;
  int persist_session_cookies;
} proton_engine_runtime_config_t;

typedef struct {
  char title[512];
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t width;
  int32_t height;
  int size_hint;
  int titlebar_overlay;
  proton_browser_policy_t browser_policy;
} proton_engine_window_config_t;

static int g_proton_cef_initialized = 0;
static int g_proton_cef_library_loaded = 0;
static int g_proton_cef_runtime_active = 0;
static int g_proton_cef_shutdown_registered = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
static int g_proton_app_terminating = 0;
static proton_engine_app_t g_app;
static proton_engine_browser_process_handler_t g_browser_process_handler;
static proton_engine_render_process_handler_t g_render_process_handler;
static proton_engine_v8_handler_t g_v8_handler;
static proton_engine_life_span_handler_t g_life_span_handler;
static proton_engine_load_handler_t g_load_handler;
static proton_engine_request_handler_t g_request_handler;
static proton_engine_download_handler_t g_download_handler;
static proton_engine_permission_handler_t g_permission_handler;
static proton_engine_render_handler_t g_render_handler;
static proton_engine_display_handler_t g_display_handler;
static proton_engine_scheme_factory_t g_scheme_factory;
static proton_engine_window_t *g_windows = NULL;

/* Guards g_windows list membership and the per-window html/html_url/html_len
   fields. Writers run on the main thread; the scheme handler factory reads
   them on CEF's IO thread, so both sides must take this lock. Keep critical
   sections leaf-only: never call back into engine or CEF code while held. */
static pthread_mutex_t g_proton_engine_window_lock = PTHREAD_MUTEX_INITIALIZER;

void proton_engine_window_lock(void) {
  pthread_mutex_lock(&g_proton_engine_window_lock);
}

void proton_engine_window_unlock(void) {
  pthread_mutex_unlock(&g_proton_engine_window_lock);
}
static uint64_t g_next_window_native_id = 1;
static uint64_t g_next_view_native_id = 1;
static proton_engine_bridge_pending_t *g_bridge_pending = NULL;
static atomic_bool g_external_message_pump_enabled = ATOMIC_VAR_INIT(false);
// Main-thread only, so a plain bool: set by proton_engine_host_loop_begin and
// cleared by proton_engine_host_loop_end, both of which refuse other threads.
static bool g_host_loop_active = false;
static atomic_llong g_scheduled_pump_deadline_ms = ATOMIC_VAR_INIT(-1);
static atomic_bool g_message_pump_active = ATOMIC_VAR_INIT(false);
static atomic_int g_runtime_wait_log_count = ATOMIC_VAR_INIT(0);
static atomic_uint g_wait_source_ready_mask = ATOMIC_VAR_INIT(PROTON_WAIT_NONE);
static CFRunLoopRef g_wait_run_loop = NULL;
static CFRunLoopSourceRef g_wait_source = NULL;
static pthread_mutex_t g_wakeup_fd_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_wakeup_write_fd = -1;

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

static void proton_engine_signal_wakeup_fd(unsigned char wakeup_byte) {
  pthread_mutex_lock(&g_wakeup_fd_lock);
  if (g_wakeup_write_fd >= 0) {
    ssize_t written;
    do {
      written = write(g_wakeup_write_fd, &wakeup_byte, sizeof(wakeup_byte));
    } while (written < 0 && errno == EINTR);
  }
  pthread_mutex_unlock(&g_wakeup_fd_lock);
}

static void proton_engine_clear_wakeup_fd(void) {
  pthread_mutex_lock(&g_wakeup_fd_lock);
  if (g_wakeup_write_fd >= 0) {
    close(g_wakeup_write_fd);
    g_wakeup_write_fd = -1;
  }
  pthread_mutex_unlock(&g_wakeup_fd_lock);
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

// The source outlives any one CEF lifetime once a host loop owns it, so an
// existing source on this run loop is reused rather than rebuilt. Rebuilding
// would drop a signal already latched on it, and a dropped wakeup deadlocks
// the host.
static int proton_engine_setup_wait_source(char *error, size_t error_len) {
  if (g_wait_source != NULL && g_wait_run_loop == CFRunLoopGetCurrent()) {
    return 1;
  }
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
  if (atomic_load_explicit(&g_external_message_pump_enabled,
                           memory_order_acquire)) {
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
  proton_engine_signal_wakeup_fd((unsigned char)ready_mask);
}

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  (void)runtime;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_browser_signal(void *user_data) {
  (void)user_data;
  proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
}

static int64_t proton_engine_monotonic_time_ms(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return 0;
  }
  return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int64_t proton_engine_get_scheduled_pump_delay_ms(void) {
  int64_t deadline = atomic_load_explicit(&g_scheduled_pump_deadline_ms,
                                          memory_order_acquire);
  if (deadline < 0) {
    return -1;
  }
  int64_t remaining = deadline - proton_engine_monotonic_time_ms();
  return remaining > 0 ? remaining : 0;
}

static void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
  if (!atomic_load_explicit(&g_external_message_pump_enabled,
                            memory_order_acquire)) {
    return;
  }
  int64_t deadline = proton_engine_monotonic_time_ms();
  if (delay_ms > 0 && deadline <= INT64_MAX - delay_ms) {
    deadline += delay_ms;
  }
  atomic_store_explicit(&g_scheduled_pump_deadline_ms, (long long)deadline,
                        memory_order_release);
  proton_engine_debug_log("schedule_message_pump delay_ms=%lld",
                          (long long)delay_ms);
  // Every delay signals, not just an immediate one. A host blocked with no
  // deadline of its own has nothing else to bring it back, and it reads the
  // schedule only on its way into a wait -- one that arrives after that read
  // would otherwise never be seen. This does not spin: the reschedule CEF makes
  // while being pumped happens with g_message_pump_active set and stays silent,
  // so the loop settles onto the deadline instead of the signal.
  if (!atomic_load_explicit(&g_message_pump_active, memory_order_acquire)) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_reset_scheduled_pump(void) {
  atomic_store_explicit(&g_scheduled_pump_deadline_ms, -1,
                        memory_order_release);
}

// Resets the pump state a CEF lifetime owns. The wait source is not part of
// that when a host loop is running: it belongs to the thread, is created before
// the first runtime, and has to survive the last one -- the host keeps polling
// through its own shutdown, and a torn-down source turns every one of those
// polls into an error.
static void proton_engine_reset_external_message_pump(void) {
  if (!g_host_loop_active) {
    proton_engine_teardown_wait_source();
    atomic_store_explicit(&g_external_message_pump_enabled, false,
                          memory_order_release);
  }
  atomic_store_explicit(&g_message_pump_active, false, memory_order_release);
  atomic_store_explicit(&g_wait_source_ready_mask, PROTON_WAIT_NONE,
                        memory_order_release);
  atomic_store_explicit(&g_runtime_wait_log_count, 0, memory_order_release);
  proton_engine_reset_scheduled_pump();
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
  // TODO: Resolve the bundled runtime root once in the public config layer and
  // pass it into the engine, as is now done for helper discovery.
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

static proton_engine_client_t *proton_engine_client_from_base(
    cef_client_t *client) {
  return (proton_engine_client_t *)client;
}

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL || window->window_listed) {
    return;
  }
  proton_engine_window_lock();
  window->next = g_windows;
  g_windows = window;
  window->window_listed = 1;
  proton_engine_window_unlock();
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
  proton_engine_window_lock();
  proton_engine_window_t **cursor = &g_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      window->window_listed = 0;
      break;
    }
    cursor = &(*cursor)->next;
  }
  proton_engine_window_unlock();
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

static proton_engine_window_t *proton_engine_window_from_browser_client(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_engine_window_t *window = NULL;
  if (cef_client != NULL) {
    proton_engine_client_t *client = proton_engine_client_from_base(cef_client);
    window = client != NULL ? client->window : NULL;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return window;
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

static proton_engine_view_t *proton_engine_view_from_browser(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    for (proton_engine_view_t *view = window->views; view != NULL;
         view = view->next) {
      if (view->browser_id == browser_id) {
        return view;
      }
    }
  }
  return NULL;
}

static proton_engine_view_t *proton_engine_view_from_native_id(
    uint64_t native_id) {
  if (native_id == 0) {
    return NULL;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    for (proton_engine_view_t *view = window->views; view != NULL;
         view = view->next) {
      if (view->native_id == native_id) {
        return view;
      }
    }
  }
  return NULL;
}

// Resolves a view through the browser's client. Unlike the browser-id list
// scan this also works while browser creation is still running, before the
// view records its browser id.
static proton_engine_view_t *proton_engine_view_from_browser_client(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_engine_view_t *view = NULL;
  if (cef_client != NULL) {
    proton_engine_client_t *client = proton_engine_client_from_base(cef_client);
    view = client != NULL ? client->view : NULL;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return view;
}

uint64_t proton_engine_window_native_id(proton_engine_window_t *window) {
  return window != NULL ? window->native_id : 0;
}

int proton_engine_runtime_is_headless(proton_engine_runtime_t *runtime) {
  return runtime != NULL && runtime->headless;
}

int proton_engine_window_is_headless(proton_engine_window_t *window) {
  return window != NULL && window->headless;
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
  return window == NULL || window->closed ||
         (!window->headless && window->window == nil);
}

proton_engine_window_t *proton_engine_window_lookup_native_id(
    uint64_t native_id) {
  return proton_engine_window_from_native_id(native_id);
}

proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser) {
  return proton_engine_window_from_browser(browser);
}

cef_browser_t *proton_engine_window_browser(proton_engine_window_t *window) {
  return window != NULL ? window->browser : NULL;
}

const char *proton_engine_window_html_url(proton_engine_window_t *window) {
  return window != NULL ? window->html_url : NULL;
}

const char *proton_engine_runtime_asset_root(
    proton_engine_window_t *window) {
  proton_engine_runtime_t *runtime = window != NULL ? window->runtime : NULL;
  if (runtime == NULL && g_windows != NULL) {
    runtime = g_windows->runtime;
  }
  return runtime != NULL ? runtime->asset_root : NULL;
}

const char *proton_engine_window_html(proton_engine_window_t *window,
                                     size_t *len) {
  if (len != NULL) {
    *len = window != NULL ? window->html_len : 0;
  }
  return window != NULL ? window->html : NULL;
}

void proton_engine_window_replace_document(proton_engine_window_t *window,
                                           char *url, char *html,
                                           size_t html_len) {
  if (window == NULL) {
    free(url);
    free(html);
    return;
  }
  free(window->html_url);
  free(window->html);
  window->html_url = url;
  window->html = html;
  window->html_len = html_len;
}

void proton_engine_runtime_adopt_asset_root(proton_engine_window_t *window,
                                            char *root) {
  proton_engine_runtime_t *runtime = window != NULL ? window->runtime : NULL;
  if (runtime == NULL && g_windows != NULL) {
    runtime = g_windows->runtime;
  }
  if (runtime == NULL) {
    free(root);
    return;
  }
  runtime->asset_root = root;
}

proton_engine_view_t *proton_engine_window_lookup_view_browser(
    cef_browser_t *browser) {
  return proton_engine_view_from_browser(browser);
}

const char *proton_engine_view_html_url(proton_engine_view_t *view) {
  return view != NULL ? view->html_url : NULL;
}

const char *proton_engine_view_html(proton_engine_view_t *view, size_t *len) {
  if (len != NULL) {
    *len = view != NULL ? view->html_len : 0;
  }
  return view != NULL ? view->html : NULL;
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

// NULL means every window, so the host loop keeps driving browser creation for
// runtimes whose handle it does not hold.
static int proton_engine_runtime_has_pending_platform_work(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (runtime != NULL && window->runtime != runtime) {
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
  int has_request =
      runtime->bridge_count > 0 || runtime->bridge_cancellation_count > 0;
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

static int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t request_id) {
  if (runtime == NULL || request_id <= 0) {
    return 0;
  }
  int ok = 0;
  proton_engine_runtime_bridge_lock(runtime);
  if (runtime->bridge_cancellation_count <
      PROTON_ENGINE_MAX_BRIDGE_REQUESTS) {
    size_t index =
        (runtime->bridge_cancellation_head +
         runtime->bridge_cancellation_count) %
        PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
    runtime->bridge_cancellations[index] = request_id;
    runtime->bridge_cancellation_count++;
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
  runtime->bridge_cancellation_head = 0;
  runtime->bridge_cancellation_count = 0;
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

static int proton_engine_bridge_pending_cancel(
    proton_engine_runtime_t *runtime,
    int browser_id,
    int renderer_pending_id,
    const char *page_instance) {
  if (page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        pending->renderer_pending_id == renderer_pending_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      int removed =
          proton_engine_runtime_remove_bridge_request(runtime, request_id);
      if (removed == 0 &&
          !proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id)) {
        proton_engine_debug_log(
            "bridge_cancel_queue_full request=%lld browser=%d pending=%d",
            (long long)request_id, browser_id, renderer_pending_id);
      }
      proton_engine_bridge_pending_free(pending);
      return 1;
    }
    cursor = &pending->next;
  }
  return 0;
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
      int removed =
          proton_engine_runtime_remove_bridge_request(runtime, request_id);
      if (removed == 0 &&
          !proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id)) {
        proton_engine_debug_log(
            "bridge_cancel_queue_full request=%lld browser=%d pending=%d",
            (long long)request_id, browser_id,
            pending->renderer_pending_id);
      }
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
  proton_engine_register_app_custom_schemes(registrar);
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

static void CEF_CALLBACK proton_engine_osr_get_view_rect(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_rect_t *rect) {
  (void)self;
  if (rect == NULL) {
    return;
  }
  rect->x = 0;
  rect->y = 0;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL) {
    // CEF can query the viewport while browser creation is still running,
    // before the view records its browser id; resolve via the client then.
    view = proton_engine_view_from_browser_client(browser);
  }
  if (view != NULL) {
    rect->width = view->width > 0 ? view->width : 1;
    rect->height = view->height > 0 ? view->height : 1;
    return;
  }
  proton_engine_window_t *window =
      proton_engine_window_from_browser_client(browser);
  rect->width = window != NULL && window->width > 0 ? window->width : 1;
  rect->height = window != NULL && window->height > 0 ? window->height : 1;
}

static int CEF_CALLBACK proton_engine_osr_get_screen_info(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_screen_info_t *screen_info) {
  if (screen_info == NULL) {
    return 0;
  }
  cef_rect_t rect = {0};
  proton_engine_osr_get_view_rect(self, browser, &rect);
  screen_info->device_scale_factor = 1.0f;
  screen_info->depth = 32;
  screen_info->depth_per_component = 8;
  screen_info->is_monochrome = 0;
  screen_info->rect = rect;
  screen_info->available_rect = rect;
  return 1;
}

static void CEF_CALLBACK proton_engine_osr_on_popup_show(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    int show) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_window_from_browser_client(browser);
  if (window != NULL) {
    window->osr_popup_visible = show ? 1 : 0;
  }
}

static void CEF_CALLBACK proton_engine_osr_on_popup_size(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    const cef_rect_t *rect) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_window_from_browser_client(browser);
  if (window != NULL && rect != NULL) {
    window->osr_popup_rect = *rect;
  }
}

static void CEF_CALLBACK proton_engine_osr_on_paint(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_paint_element_type_t type,
    size_t dirty_rects_count,
    const cef_rect_t *dirty_rects,
    const void *buffer,
    int width,
    int height) {
  (void)self;
  (void)dirty_rects_count;
  (void)dirty_rects;
  (void)buffer;
  proton_engine_window_t *window =
      proton_engine_window_from_browser_client(browser);
  if (window == NULL) {
    // View browsers track paint separately from window OSR state; one log
    // line per browser is enough for e2e to prove the view viewport size.
    proton_engine_view_t *view = proton_engine_view_from_browser(browser);
    if (view != NULL && type == PET_VIEW && width > 0 && height > 0 &&
        !view->osr_paint_seen) {
      view->osr_paint_seen = 1;
      proton_engine_debug_log("view_osr_paint browser=%d size=%dx%d",
                              view->browser_id, width, height);
    }
    return;
  }
  if (!window->headless || type != PET_VIEW || width <= 0 ||
      height <= 0) {
    return;
  }
  window->osr_paint_width = width;
  window->osr_paint_height = height;
  if (!window->osr_paint_seen) {
    window->osr_paint_seen = 1;
    proton_engine_debug_log("osr_paint browser=%d size=%dx%d",
                            proton_engine_browser_id(browser), width, height);
  }
}

static void proton_engine_window_mark_closed(proton_engine_window_t *window);
static void proton_engine_window_release_browser(proton_engine_window_t *window);
static int proton_engine_window_request_browser_close(
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
static void proton_engine_view_on_after_created(proton_engine_view_t *view,
                                                cef_browser_t *browser);
static void proton_engine_view_on_before_close(proton_engine_view_t *view,
                                               cef_browser_t *browser);
static void proton_engine_window_close_views(
    proton_engine_window_t *window);
static void proton_engine_window_layout_views(
    proton_engine_window_t *window);
static void proton_engine_window_free_views(
    proton_engine_window_t *window);
static void proton_engine_view_release_browser(proton_engine_view_t *view);
static void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);

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

static void CEF_CALLBACK proton_engine_initial_navigation_task_execute(
    cef_task_t *base) {
  proton_engine_initial_navigation_task_t *task =
      (proton_engine_initial_navigation_task_t *)base;
  proton_engine_window_t *window =
      proton_engine_window_from_native_id(task->native_id);
  if (window == NULL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      free(task);
    });
    return;
  }
  window->initial_navigation_pending = 0;
  proton_engine_window_load_initial_url(window);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  uint64_t native_id = task->native_id;
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_window_t *pending_window =
        proton_engine_window_from_native_id(native_id);
    if (pending_window != NULL) {
      proton_engine_window_finalize_if_ready(pending_window);
    }
    free(task);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static int proton_engine_window_schedule_initial_navigation(
    proton_engine_window_t *window) {
  proton_engine_initial_navigation_task_t *task =
      calloc(1, sizeof(*task));
  if (task == NULL) {
    return 0;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&task->task,
                                 sizeof(task->task), &task->refs);
  task->task.execute = proton_engine_initial_navigation_task_execute;
  task->native_id = window->native_id;
  int posted = cef_post_task(TID_UI, &task->task);
  if (!posted) {
    free(task);
  }
  return posted;
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
  (void)frame;
  (void)popup_id;
  (void)target_frame_name;
  (void)popupFeatures;
  (void)windowInfo;
  (void)client;
  (void)settings;
  (void)extra_info;
  (void)no_javascript_access;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_popup(
      window != NULL ? window->browser_session : NULL, target_url,
      target_disposition, user_gesture);
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
  if (client != NULL && client->view != NULL) {
    proton_engine_view_on_after_created(client->view, browser);
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
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
  proton_engine_window_lock();
  window->browser_id = browser->get_identifier(browser);
  proton_engine_window_unlock();
  window->browser_create_scheduled = 0;
  if (host != NULL) {
    if (window->headless) {
      if (window->headless_hidden && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
      if (window->headless_focused && host->set_focus != NULL) {
        host->set_focus(host, 1);
      }
    } else {
      window->browser_view = (__bridge NSView *)host->get_window_handle(host);
    }
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
  // The main browser view must stay below any web contents views, including
  // views created before this browser finished loading.
  proton_engine_window_layout_views(window);
  proton_engine_debug_log("create_browser id=%d size=%dx%d",
                          window->browser_id, window->width, window->height);

  if (window->closed || window->finalize_after_browser_close) {
    window->initial_navigation_pending = 0;
    proton_engine_window_request_browser_close(window, 1);
    proton_engine_window_release_browser(window);
    proton_engine_window_finalize_if_ready(window);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  if (!proton_engine_window_schedule_initial_navigation(window)) {
    window->initial_navigation_pending = 0;
    proton_engine_debug_log("initial_navigation_post_failed browser=%d",
                            window->browser_id);
    proton_engine_window_mark_closed(window);
    proton_engine_window_request_browser_close(window, 1);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    proton_engine_view_on_before_close(view, browser);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL) {
    proton_engine_debug_log("browser_before_close browser=%d",
                            window->browser_id);
    window->browser_before_close_seen = 1;
    proton_engine_window_close_views(window);
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
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    proton_engine_debug_log("view_browser_do_close browser=%d",
                            view->browser_id);
    if (view->browser_view != nil) {
      // A view browser owns no top-level window, so the default behavior for
      // windowed rendering (performClose: on the browser's top-level parent
      // window) would target the owning NSWindow and be cancelled by its
      // delegate, leaving the browser in a partially closed state. Take over
      // the close: detach the browser host view so its dealloc completes the
      // teardown via WindowDestroyed().
      [view->browser_view removeFromSuperview];
      view->browser_view = nil;
      return 1;
    }
    if (view->window != NULL && view->window->headless) {
      // Windowless (headless) rendering has no host view; returning false lets
      // CEF destroy the browser object immediately.
      return 0;
    }
    // Defensive: a windowed view with no host view pointer — either it was
    // never captured (the browser host or its window handle was unavailable
    // at creation), or windowWillClose already cleared it while the NSWindow
    // teardown is still pending. CEF only asks do_close before
    // WindowDestroyed, so no dealloc handshake can complete this teardown
    // from here — but returning false is strictly worse: CEF's default would
    // performClose: the owning NSWindow, which the window delegate cancels.
    // Cancel the default and log the wedge; in the windowWillClose interleave
    // the pending teardown still completes via WindowDestroyed.
    proton_engine_debug_log("view_browser_do_close_without_host_view browser=%d",
                            view->browser_id);
    return 1;
  }
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

static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self) {
  (void)self;
  g_download_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_download_handler.handler);
  return &g_download_handler.handler;
}

static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self) {
  (void)self;
  g_permission_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_permission_handler.handler);
  return &g_permission_handler.handler;
}

static cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self) {
  proton_engine_client_t *client = proton_engine_client_from_base(self);
  if (client == NULL) {
    return NULL;
  }
  if (client->view != NULL) {
    if (client->view->window == NULL || !client->view->window->headless) {
      return NULL;
    }
  } else if (client->window == NULL || !client->window->headless) {
    return NULL;
  }
  g_render_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_render_handler.handler);
  return &g_render_handler.handler;
}

static void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL) {
    return;
  }
  char *title_utf8 = proton_engine_cef_string_to_utf8(title);
  proton_engine_debug_log("view_title browser=%d title=%s", view->browser_id,
                          title_utf8 != NULL ? title_utf8 : "");
  proton_view_events_title_updated(view->events, title_utf8);
  free(title_utf8);
  proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
}

static cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self) {
  (void)self;
  g_display_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_display_handler.handler);
  return &g_display_handler.handler;
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
static int CEF_CALLBACK proton_engine_on_before_browse(
    cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect);
static int CEF_CALLBACK proton_engine_on_certificate_error(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_errorcode_t cert_error, const cef_string_t *request_url,
    cef_sslinfo_t *ssl_info, cef_callback_t *callback);
static int CEF_CALLBACK proton_engine_can_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    const cef_string_t *url, const cef_string_t *request_method);
static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback);
static void CEF_CALLBACK proton_engine_on_download_updated(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback);
static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback);

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
  g_request_handler.handler.on_before_browse =
      proton_engine_on_before_browse;
  g_request_handler.handler.on_certificate_error =
      proton_engine_on_certificate_error;
  g_request_handler.handler.on_render_process_terminated =
      proton_engine_on_render_process_terminated;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_download_handler.handler.base,
      sizeof(g_download_handler.handler), &g_download_handler.refs);
  g_download_handler.handler.can_download = proton_engine_can_download;
  g_download_handler.handler.on_before_download =
      proton_engine_on_before_download;
  g_download_handler.handler.on_download_updated =
      proton_engine_on_download_updated;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_permission_handler.handler.base,
      sizeof(g_permission_handler.handler), &g_permission_handler.refs);
  g_permission_handler.handler.on_request_media_access_permission =
      proton_engine_on_media_permission;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_render_handler.handler.base,
      sizeof(g_render_handler.handler), &g_render_handler.refs);
  g_render_handler.handler.get_view_rect = proton_engine_osr_get_view_rect;
  g_render_handler.handler.get_screen_info = proton_engine_osr_get_screen_info;
  g_render_handler.handler.on_popup_show = proton_engine_osr_on_popup_show;
  g_render_handler.handler.on_popup_size = proton_engine_osr_on_popup_size;
  g_render_handler.handler.on_paint = proton_engine_osr_on_paint;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_display_handler.handler.base,
      sizeof(g_display_handler.handler), &g_display_handler.refs);
  g_display_handler.handler.on_title_change = proton_engine_on_title_change;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_scheme_factory.factory.base,
      sizeof(g_scheme_factory.factory), &g_scheme_factory.refs);
  g_scheme_factory.factory.create = proton_engine_scheme_create;
  proton_engine_menu_set_signal_callback(proton_engine_signal_wait_source);
  proton_engine_dialog_set_signal_callback(proton_engine_signal_wait_source);
  proton_engine_platform_event_set_signal_callback(
      proton_engine_signal_wait_source);
  initialized = 1;
}

static int proton_engine_send_bridge_response_to_frame(
    cef_frame_t *frame,
    int renderer_pending_id,
    int ok,
    const char *payload_json,
    const char *error_text) {
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
  proton_engine_set_string(&error, error_text != NULL ? error_text : "");
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
    const char *action,
    int pending_id,
    const char *op,
    const char *payload_json,
    const char *page_instance) {
  if (frame == NULL || action == NULL || op == NULL || payload_json == NULL ||
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
  args->set_size(args, 5);
  cef_string_t action_value = {0};
  cef_string_t op_value = {0};
  cef_string_t payload_value = {0};
  cef_string_t page_instance_value = {0};
  proton_engine_set_string(&action_value, action);
  proton_engine_set_string(&op_value, op);
  proton_engine_set_string(&payload_value, payload_json);
  proton_engine_set_string(&page_instance_value, page_instance);
  args->set_string(args, 0, &action_value);
  args->set_int(args, 1, pending_id);
  args->set_string(args, 2, &op_value);
  args->set_string(args, 3, &payload_value);
  args->set_string(args, 4, &page_instance_value);
  cef_string_clear(&action_value);
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
  if (argumentsCount < 5 || arguments[0] == NULL ||
      !arguments[0]->is_string(arguments[0]) || arguments[1] == NULL ||
      !arguments[1]->is_int(arguments[1])) {
    proton_engine_set_string(exception,
                             "invokeOp requires action, pending id, name, payload and page instance");
    return 1;
  }
  char *action = proton_engine_v8_value_to_utf8(arguments[0]);
  int pending_id = arguments[1]->get_int_value(arguments[1]);
  char *op = proton_engine_v8_value_to_utf8(arguments[2]);
  char *payload_json = proton_engine_v8_value_to_utf8(arguments[3]);
  char *page_instance = proton_engine_v8_value_to_utf8(arguments[4]);
  int is_request = action != NULL && strcmp(action, "request") == 0;
  int is_cancel = action != NULL && strcmp(action, "cancel") == 0;
  if ((!is_request && !is_cancel) ||
      (is_request &&
       (!proton_engine_bridge_op_is_valid(op) ||
        !proton_engine_bridge_payload_is_valid(
            payload_json, PROTON_ENGINE_MAX_BRIDGE_BYTES))) ||
      !proton_engine_bridge_page_instance_is_valid(page_instance)) {
    proton_engine_debug_log(
        "bridge_reject_invalid_renderer pending=%d op=%s payload_bytes=%llu",
        pending_id, op != NULL ? op : "",
        (unsigned long long)(payload_json != NULL ? strlen(payload_json) : 0));
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "invalid bridge request");
    return 1;
  }
  cef_v8_context_t *context = cef_v8_context_get_current_context();
  if (context == NULL) {
    free(action);
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
    free(action);
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
    free(action);
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
          frame, action, pending_id, op, payload_json, page_instance)) {
    proton_engine_set_string(exception, "failed to send bridge request");
  }
  browser->base.release((cef_base_ref_counted_t *)browser);
  frame->base.release((cef_base_ref_counted_t *)frame);
  context->base.release((cef_base_ref_counted_t *)context);
  free(action);
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
      int url_matches = proton_engine_urls_same_document(url, current_url);
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
  if (args == NULL || args->get_size(args) < 5) {
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  char *action = proton_engine_userfree_to_utf8(args->get_string(args, 0));
  int renderer_pending_id = args->get_int(args, 1);
  char *op = proton_engine_userfree_to_utf8(args->get_string(args, 2));
  char *payload_json = proton_engine_userfree_to_utf8(args->get_string(args, 3));
  char *page_instance =
      proton_engine_userfree_to_utf8(args->get_string(args, 4));
  args->base.release((cef_base_ref_counted_t *)args);
  if (action != NULL && strcmp(action, "cancel") == 0) {
    int cancelled = proton_engine_bridge_pending_cancel(
        window != NULL ? window->runtime : NULL, browser_id,
        renderer_pending_id, page_instance);
    proton_engine_debug_log(
        "browser_bridge_cancel browser=%d pending=%d cancelled=%d",
        browser_id, renderer_pending_id, cancelled);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  if (action == NULL || strcmp(action, "request") != 0) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(action);
  proton_engine_debug_log("browser_bridge_request browser=%d pending=%d op=%s",
                          browser_id, renderer_pending_id,
                          op != NULL ? op : "");

  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  int64_t request_id = 0;
  char *request_json = NULL;
  proton_engine_bridge_request_status_t build_status =
      window == NULL || window->runtime == NULL
          ? PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED
          : proton_engine_bridge_build_request_json(
                window->bridge_config_json, frame_url, op, payload_json,
                page_instance, window->max_bridge_payload_bytes,
                window->public_window_id,
                &window->runtime->next_bridge_request_id, &request_id,
                &request_json);
  if (build_status != PROTON_ENGINE_BRIDGE_REQUEST_OK) {
    proton_engine_debug_log(
        "%s browser=%d pending=%d op=%s url=%s",
        proton_engine_bridge_request_reject_event(build_status), browser_id,
        renderer_pending_id, op != NULL ? op : "",
        proton_engine_log_url(frame_url));
    proton_engine_reject_renderer_request(
        frame, renderer_pending_id,
        proton_engine_bridge_request_reject_message(build_status));
    free(frame_url);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(frame_url);
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
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame) && url != NULL &&
        strcmp(url, "about:blank") != 0) {
      proton_view_events_navigated(view->events, url);
      proton_view_events_loading_changed(view->events, 1);
      proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
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
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame)) {
      proton_view_events_loading_changed(view->events, 0);
      proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
  proton_engine_debug_log("load_end browser=%d main=%d status=%d url=%s",
                          proton_engine_browser_id(browser),
                          frame != NULL ? frame->is_main(frame) : 0,
                          httpStatusCode, url != NULL ? url : "");
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
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
  if (frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    char *view_message = proton_engine_cef_string_to_utf8(errorText);
    char *view_url = proton_engine_cef_string_to_utf8(failedUrl);
    proton_view_events_load_failed(view->events, view_url, (int32_t)errorCode,
                                   view_message);
    free(view_message);
    free(view_url);
    proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  char *message = proton_engine_cef_string_to_utf8(errorText);
  char *url = proton_engine_cef_string_to_utf8(failedUrl);
  if (window != NULL && window->bridge_config_json != NULL && url != NULL) {
    proton_engine_bridge_lifecycle_report_load_failure(
        &window->bridge_lifecycle, url,
        message != NULL && message[0] != '\0' ? message
                                               : "main frame failed to load",
        errorCode == ERR_ABORTED);
  }
  free(message);
  free(url);
}

static int CEF_CALLBACK proton_engine_on_before_browse(
    cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_browse(
      window != NULL ? window->browser_session : NULL, frame, request,
      user_gesture, is_redirect);
}

static int CEF_CALLBACK proton_engine_on_certificate_error(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_errorcode_t cert_error, const cef_string_t *request_url,
    cef_sslinfo_t *ssl_info, cef_callback_t *callback) {
  (void)self;
  (void)ssl_info;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_certificate_error(
      window != NULL ? window->browser_session : NULL, cert_error,
      request_url, callback);
}

static int CEF_CALLBACK proton_engine_can_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    const cef_string_t *url, const cef_string_t *request_method) {
  (void)self;
  (void)url;
  (void)request_method;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_can_download(
      window != NULL ? window->browser_session : NULL);
}

static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_download(
      window != NULL ? window->browser_session : NULL, download_item,
      suggested_name, callback);
}

static void CEF_CALLBACK proton_engine_on_download_updated(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  proton_browser_session_download_updated(
      window != NULL ? window->browser_session : NULL, download_item,
      callback);
}

static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback) {
  (void)self;
  (void)frame;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_media_permission(
      window != NULL ? window->browser_session : NULL, requesting_origin,
      requested_permissions, callback);
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
  client->client.get_download_handler =
      proton_engine_client_get_download_handler;
  client->client.get_permission_handler =
      proton_engine_client_get_permission_handler;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
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
  bool headless = false;
  proton_engine_parse_json_bool_field(config_json, "use_bundled",
                                      &use_bundled);
  proton_engine_parse_json_bool_field(config_json, "headless", &headless);
  config->headless = headless ? 1 : 0;
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
        proton_config_default_helper_path(config->helper_path,
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
  bool persist_session_cookies = false;
  if (proton_engine_parse_json_bool_field(config_json,
                                          "persist_session_cookies",
                                          &persist_session_cookies)) {
    config->persist_session_cookies =
        config->cache_dir[0] != '\0' && persist_session_cookies ? 1 : 0;
  } else {
    config->persist_session_cookies = config->cache_dir[0] != '\0' ? 1 : 0;
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
  char size_hint[32] = {0};
  if (proton_engine_parse_json_string_field(
          config_json, "size_hint", size_hint, sizeof(size_hint))) {
    if (strcmp(size_hint, "fixed") == 0) {
      config->size_hint = 1;
    } else if (strcmp(size_hint, "min") == 0) {
      config->size_hint = 2;
    } else if (strcmp(size_hint, "max") == 0) {
      config->size_hint = 3;
    } else if (strcmp(size_hint, "none") != 0) {
      proton_engine_set_message(
          error, error_len,
          "window size_hint must be none, fixed, min, or max");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
  }
  char titlebar_style[32] = {0};
  if (proton_engine_parse_json_string_field(
          config_json, "titlebar_style", titlebar_style,
          sizeof(titlebar_style))) {
    if (strcmp(titlebar_style, "overlay") == 0) {
      config->titlebar_overlay = 1;
    } else if (strcmp(titlebar_style, "default") != 0) {
      proton_engine_set_message(
          error, error_len,
          "window titlebar_style must be default or overlay");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
  }
  return proton_browser_policy_parse_window_json(
      config_json, &config->browser_policy, error, error_len);
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

static int proton_engine_window_request_browser_close(
    proton_engine_window_t *window,
    int force_close) {
  if (window == NULL || window->browser == NULL) {
    return 0;
  }
  if (window->browser_close_requested && !force_close) {
    return 1;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    return 0;
  }
  window->browser_close_requested = 1;
  host->close_browser(host, force_close);
  host->base.release((cef_base_ref_counted_t *)host);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return 1;
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
    proton_engine_window_close_views(window);
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
- (void)windowStateDidChange:(NSNotification *)notification {
  (void)notification;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

- (void)windowDidMove:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidResize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidResignKey:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (BOOL)windowShouldClose:(id)sender {
  (void)sender;
  if (window == NULL || window->closed) {
    return YES;
  }
  if (window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return NO;
  }
  window->close_interception_bypass = 0;
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
  proton_engine_window_close_views(window);
  // A deferred view close (beforeunload/unload still in flight) leaves the
  // view's browser host view attached, and the NSWindow teardown that follows
  // releases the whole view tree, dealloc'ing every CefBrowserHostView and
  // firing its WindowDestroyed(). Clear each view's borrowed browser_view
  // pointer now so view_on_before_close cannot message a dangling pointer
  // afterwards. Do NOT removeFromSuperview here: the resulting dealloc would
  // re-enter CEF (WindowDestroyed -> DestroyBrowser -> on_before_close ->
  // finalize) and can free this window and its view structs while this loop
  // and the code below still use them.
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    view->browser_view = nil;
  }
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

@interface ProtonContentView : NSView {
@public
  proton_engine_window_t *window;
}
@end

@implementation ProtonContentView
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  if (window != NULL) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
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
  proton_engine_launch_input_install();
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

static void proton_engine_remove_temporary_profile(void) {
  if (g_proton_temporary_profile_path[0] != '\0') {
    proton_profile_storage_remove_temporary(g_proton_temporary_profile_path);
    g_proton_temporary_profile_path[0] = '\0';
  }
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    proton_engine_debug_log("cef_shutdown");
    cef_shutdown();
    g_proton_cef_initialized = 0;
  }
  proton_engine_remove_temporary_profile();
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

  if (!proton_engine_load_cef_library(&config, error, error_len)) {
    proton_engine_remove_temporary_profile();
    return PROTON_ERR_ENGINE;
  }
  proton_engine_ensure_appkit();
  proton_engine_init_handlers();
  proton_engine_check_cef_api_hash();
  proton_engine_reset_external_message_pump();
  atomic_store_explicit(&g_external_message_pump_enabled, true,
                        memory_order_release);
  if (!proton_engine_setup_wait_source(error, error_len)) {
    proton_engine_reset_external_message_pump();
    proton_engine_unload_cef_library();
    proton_engine_remove_temporary_profile();
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
  settings.windowless_rendering_enabled = config.headless;
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  settings.remote_debugging_port = config.remote_debugging_port;
  settings.persist_session_cookies = config.persist_session_cookies;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.framework_dir_path, config.framework_dir);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  if (!temporary_profile) {
    proton_engine_set_string(&settings.cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, &g_app.app, NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.framework_dir_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.cache_path);
    cef_string_clear(&settings.root_cache_path);
    proton_engine_reset_external_message_pump();
    proton_engine_unload_cef_library();
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_debug_log("runtime_create remote_debugging_port=%d",
                          config.remote_debugging_port);

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.framework_dir_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.cache_path);
  cef_string_clear(&settings.root_cache_path);

  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(*runtime));
  if (runtime == NULL) {
    proton_engine_cef_shutdown();
    proton_engine_reset_external_message_pump();
    proton_engine_set_message(error, error_len,
                              "failed to allocate runtime state");
    return PROTON_ERR_ENGINE;
  }
  runtime->owns_cef_runtime = 1;
  runtime->headless = config.headless;
  runtime->next_bridge_request_id = 1;
  if (pthread_mutex_init(&runtime->bridge_lock, NULL) == 0) {
    runtime->bridge_lock_initialized = 1;
  }
  g_proton_cef_initialized = 1;
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_app_scheme_factory(&g_scheme_factory.factory)) {
    proton_engine_cef_shutdown();
    proton_engine_reset_external_message_pump();
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
    proton_engine_reset_external_message_pump();
    runtime->owns_cef_runtime = 0;
  }
  if (runtime->bridge_lock_initialized) {
    pthread_mutex_destroy(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
  }
  proton_engine_clear_wakeup_fd();
  g_proton_cef_runtime_active = 0;
  /* The e2e suite uses this as proof that native shutdown completed. */
  proton_engine_debug_log("runtime_destroy_complete");
  free(runtime->asset_root);
  free(runtime);
  return PROTON_OK;
}

// A NULL runtime means every window in the process, the same rule the host
// loop follows everywhere else: it owns the main thread on behalf of whatever
// runtimes happen to exist, and holds a handle to none of them.
static void proton_engine_runtime_create_pending_browsers(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if ((runtime != NULL && window->runtime != runtime) ||
        !window->browser_create_pending || window->browser_create_scheduled ||
        window->closed) {
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
      // been registered to this window. Mark the navigation pending before
      // creation, then post it to CEF's UI task runner from on_after_created.
      pending_window->initial_navigation_pending = 1;
      int32_t status = proton_engine_window_create_browser(
          pending_window, "about:blank", error, sizeof(error));
      if (status != PROTON_OK) {
        pending_window->initial_navigation_pending = 0;
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
      for (proton_engine_view_t *view = window->views; view != NULL;
           view = view->next) {
        view->browser_before_close_seen = 1;
        view->finalize_after_browser_close = 1;
        proton_engine_view_release_browser(view);
        proton_engine_view_finalize_if_ready(view);
      }
      window->browser_before_close_seen = 1;
      proton_engine_window_release_browser(window);
      proton_engine_window_finalize_if_ready(window);
    }
    window = next;
  }
}

int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  atomic_store_explicit(&g_message_pump_active, true, memory_order_release);
  proton_engine_reset_scheduled_pump();
  proton_engine_runtime_create_pending_browsers(runtime);
  proton_engine_pump_appkit_cef_once();
  atomic_store_explicit(&g_message_pump_active, false, memory_order_release);
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

int32_t proton_engine_host_loop_begin(char *error, size_t error_len) {
  if (!pthread_main_np()) {
    proton_engine_set_message(error, error_len,
                              "the host loop must start on the main thread");
    return PROTON_ERR_WRONG_THREAD;
  }
  if (g_host_loop_active) {
    return PROTON_OK;
  }
  // The wait source is plain CoreFoundation and needs no CEF, so it can exist
  // long before a runtime does. It has to be a source rather than a bare
  // CFRunLoopWakeUp: a source stays signalled until the loop next runs, while
  // a wakeup delivered to a loop that is not running is simply lost, and the
  // trait's contract says a lost wakeup deadlocks the program.
  atomic_store_explicit(&g_external_message_pump_enabled, true,
                        memory_order_release);
  if (!proton_engine_setup_wait_source(error, error_len)) {
    atomic_store_explicit(&g_external_message_pump_enabled, false,
                          memory_order_release);
    return PROTON_ERR_PLATFORM;
  }
  g_host_loop_active = true;
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
  if (!g_proton_cef_initialized) {
    return PROTON_OK;
  }
  // The wait above only blocks; it does not dispatch. AppKit posts events to a
  // run-loop source but sends them from its own loop, which nobody is running,
  // so the events stay queued until this pump dequeues them -- and this is the
  // only caller of cef_do_message_loop_work while the host loop owns the main
  // thread. Skipping it on a timed-out wait would strand work that arrived
  // through a path that does not signal the wait source.
  atomic_store_explicit(&g_message_pump_active, true, memory_order_release);
  proton_engine_reset_scheduled_pump();
  proton_engine_pump_appkit_cef_once();
  atomic_store_explicit(&g_message_pump_active, false, memory_order_release);
  return PROTON_OK;
}

void proton_engine_host_loop_end(void) {
  if (!pthread_main_np()) {
    return;
  }
  g_host_loop_active = false;
  proton_engine_teardown_wait_source();
  atomic_store_explicit(&g_external_message_pump_enabled, false,
                        memory_order_release);
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
  // A NULL runtime waits for host-loop wakeups alone. The host loop is running
  // before the first engine runtime exists -- application code does file IO
  // while it is still deciding what runtime to build -- and a wait that
  // refused to block until then would leave those wakeups nowhere to land.
  if (runtime != NULL && !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (g_wait_source == NULL) {
    proton_engine_set_message(error, error_len, "host loop is not running");
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

  // Negative means PROTON_WAIT_TIMEOUT_INFINITE; the ABI rejects every other
  // negative value before reaching here. -1 stays out of the arithmetic below
  // so it cannot be mistaken for a duration.
  int wait_forever = timeout_ms < 0;
  int64_t wait_timeout = wait_forever ? 0 : (int64_t)timeout_ms;
  int waiting_for_platform_pump = 0;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_proton_cef_initialized) {
    int64_t pump_delay = PROTON_ENGINE_MAX_MESSAGE_PUMP_DELAY_MS;
    int64_t scheduled_delay = proton_engine_get_scheduled_pump_delay_ms();
    if (scheduled_delay >= 0 && scheduled_delay < pump_delay) {
      pump_delay = scheduled_delay;
    }
    if (wait_forever || pump_delay <= wait_timeout) {
      wait_timeout = pump_delay;
      wait_forever = 0;
      waiting_for_platform_pump = 1;
    }
  }

  // Nothing is cleared before waiting. Bits set while the host was running its
  // own code -- not inside this wait -- are the ones that matter most, and
  // clearing first would throw them away; the exchange below is what consumes
  // them. Re-reporting a bit the host has already handled only costs it a
  // spurious poll, while dropping one costs it the notification entirely.
  CFRunLoopRunResult run_result = kCFRunLoopRunTimedOut;
  CFAbsoluteTime start_time = CFAbsoluteTimeGetCurrent();
  if (wait_forever || wait_timeout > 0) {
    // CFRunLoopRunInMode has no "forever", so an interval far beyond any
    // process lifetime stands in for it. Unlike a sentinel this one is only
    // ever reached by a run loop with no sources left to signal it, which is
    // a hung host either way.
    CFTimeInterval seconds =
        wait_forever ? 1.0e9 : ((CFTimeInterval)wait_timeout) / 1000.0;
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
    } else if (waiting_for_platform_pump &&
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

int32_t proton_engine_runtime_set_wakeup_fd(proton_engine_runtime_t *runtime,
                                            int32_t wakeup_fd,
                                            char *error,
                                            size_t error_len) {

  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }

  int owned_fd = -1;
  if (wakeup_fd >= 0) {
    owned_fd = dup(wakeup_fd);
    if (owned_fd < 0) {
      proton_engine_set_message(error, error_len,
                                "failed to duplicate runtime wakeup fd");
      return PROTON_ERR_PLATFORM;
    }
    int flags = fcntl(owned_fd, F_GETFL);
    if (flags < 0 || fcntl(owned_fd, F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(owned_fd, F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(owned_fd, F_SETNOSIGPIPE, 1) < 0) {
      close(owned_fd);
      proton_engine_set_message(error, error_len,
                                "failed to configure runtime wakeup fd");
      return PROTON_ERR_PLATFORM;
    }
  }

  pthread_mutex_lock(&g_wakeup_fd_lock);
  int previous_fd = g_wakeup_write_fd;
  g_wakeup_write_fd = owned_fd;
  pthread_mutex_unlock(&g_wakeup_fd_lock);
  if (previous_fd >= 0) {
    close(previous_fd);
  }
  if (owned_fd >= 0) {
    proton_engine_signal_wakeup_fd(PROTON_WAIT_PLATFORM);
  }
  return PROTON_OK;
}

int32_t proton_engine_runtime_prepare_wakeup_source(
    proton_engine_runtime_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  proton_engine_set_message(
      error, error_len,
      "macOS uses proton_runtime_set_wakeup_fd for its wakeup source");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_runtime_activate_wakeup_source(
    proton_engine_runtime_t *runtime, char *error, size_t error_len) {
  (void)runtime;
  proton_engine_set_message(
      error, error_len,
      "macOS uses proton_runtime_set_wakeup_fd for its wakeup source");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_runtime_next_wakeup_delay_ms(
    proton_engine_runtime_t *runtime,
    int64_t *out_delay_ms,
    char *error,
    size_t error_len) {

  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_delay_ms == NULL) {
    proton_engine_set_message(error, error_len, "out_delay_ms is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_delay_ms = proton_engine_get_scheduled_pump_delay_ms();
  proton_engine_debug_log("next_wakeup_delay_ms=%lld",
                          (long long)*out_delay_ms);
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
  if (runtime->headless) {
    proton_engine_set_message(error, error_len,
                              "native menus are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
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

int32_t proton_engine_runtime_poll_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t *out_request_id,
    int32_t *out_present,
    char *error,
    size_t error_len) {
  if (out_request_id != NULL) {
    *out_request_id = 0;
  }
  if (out_present != NULL) {
    *out_present = 0;
  }
  if (runtime == NULL || out_request_id == NULL || out_present == NULL) {
    proton_engine_set_message(
        error, error_len,
        "runtime, out_request_id and out_present are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_runtime_bridge_lock(runtime);
  if (runtime->bridge_cancellation_count > 0) {
    *out_request_id =
        runtime->bridge_cancellations[runtime->bridge_cancellation_head];
    runtime->bridge_cancellation_head =
        (runtime->bridge_cancellation_head + 1) %
        PROTON_ENGINE_MAX_BRIDGE_REQUESTS;
    runtime->bridge_cancellation_count--;
    *out_present = 1;
  }
  proton_engine_runtime_bridge_unlock(runtime);
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
  proton_engine_bridge_response_t response;
  int parse_status =
      proton_engine_bridge_response_parse(response_json, &response);
  if (parse_status == PROTON_ENGINE_BRIDGE_RESPONSE_INVALID) {
    proton_engine_set_message(error, error_len,
                              "bridge response payload is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (parse_status == PROTON_ENGINE_BRIDGE_RESPONSE_NO_MEMORY) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate bridge response payload");
    return PROTON_ERR_ENGINE;
  }
  int64_t request_id = response.request_id;
  proton_engine_bridge_pending_t *pending =
      proton_engine_bridge_pending_take(request_id);
  if (pending == NULL) {
    proton_engine_bridge_response_dispose(&response);
    proton_engine_debug_log("bridge_response_no_pending request=%lld",
                            (long long)request_id);
    proton_engine_set_message(error, error_len,
                              "bridge request is no longer pending");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }

  int sent = proton_engine_send_bridge_response_to_frame(
      pending->frame, pending->renderer_pending_id, response.ok,
      response.payload_json, response.error_json);
  proton_engine_bridge_response_dispose(&response);
  proton_engine_bridge_pending_free(pending);
  if (!sent) {
    proton_engine_debug_log("bridge_response_send_failed request=%lld",
                            (long long)request_id);
    proton_engine_set_message(error, error_len,
                              "failed to send bridge response to renderer");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }
  proton_engine_debug_log("bridge_response_sent request=%lld",
                          (long long)request_id);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
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
  if (runtime->headless && config.titlebar_overlay) {
    proton_engine_set_message(
        error, error_len,
        "titlebar overlay is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
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
  window->zoom_percent = 100;
  window->headless = runtime->headless;
  window->bridge_config_json =
      proton_engine_json_copy_raw_field(config_json, "bridge");
  window->max_bridge_payload_bytes = PROTON_ENGINE_MAX_BRIDGE_BYTES;
  if (window->bridge_config_json != NULL) {
    proton_engine_bridge_config_read_max_payload(
        window->bridge_config_json, &window->max_bridge_payload_bytes);
  }
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, NULL);
  if (window->browser_session == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser session");
    return PROTON_ERR_ENGINE;
  }
  window->client = proton_engine_client_create(window);
  if (window->client == NULL) {
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  ProtonWindowDelegate *delegate = nil;
  if (!window->headless) {
    NSRect rect = NSMakeRect(0, 0, config.width, config.height);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable;
    if (config.size_hint != 1) {
      style |= NSWindowStyleMaskResizable;
    }
    if (config.titlebar_overlay) {
      style |= NSWindowStyleMaskFullSizeContentView;
    }
    NSString *title = [NSString stringWithUTF8String:config.title];
    window->window = [[NSWindow alloc] initWithContentRect:rect
                                                 styleMask:style
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    if (window->window == nil) {
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    [window->window setReleasedWhenClosed:YES];
    [window->window setTitle:title != nil ? title : @"Proton"];
    NSSize configured_size = NSMakeSize(config.width, config.height);
    if (config.size_hint == 2) {
      [window->window setContentMinSize:configured_size];
    } else if (config.size_hint == 3) {
      [window->window setContentMaxSize:configured_size];
    }
    if (config.titlebar_overlay) {
      [window->window setTitleVisibility:NSWindowTitleHidden];
      [window->window setTitlebarAppearsTransparent:YES];
    }
    [window->window center];
    ProtonContentView *content_view = [[ProtonContentView alloc]
        initWithFrame:[[window->window contentView] bounds]];
    content_view->window = window;
    [content_view setAutoresizingMask:NSViewWidthSizable |
                                      NSViewHeightSizable];
    [window->window setContentView:content_view];
    window->content_view = content_view;
    [content_view release];
    delegate = [[ProtonWindowDelegate alloc] init];
    delegate->window = window;
    window->delegate = delegate;
    [window->window setDelegate:delegate];
  }

  proton_engine_debug_log("window_create title=%s size=%dx%d initial_url=%s",
                          config.title, config.width, config.height,
                          config.initial_url);

  window->initial_url =
      proton_engine_strdup(config.initial_url[0] != '\0' ? config.initial_url
                                                         : "about:blank");
  if (window->initial_url == NULL) {
    if (window->window != nil) {
      [window->window close];
    }
    if (delegate != nil) {
      [delegate release];
    }
    free(window->client);
    proton_browser_session_destroy(window->browser_session);
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
  proton_engine_window_lock();
  proton_engine_window_free_views(window);
  free(window->client);
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  free(window->initial_url);
  proton_browser_session_destroy(window->browser_session);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
  proton_engine_window_unlock();
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
  if (window->browser_create_scheduled ||
      window->initial_navigation_pending) {
    return;
  }
  if (window->browser_id != 0 && !window->browser_before_close_seen) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->finalized) {
      return;
    }
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
  proton_engine_window_close_views(window);
  if (window->browser != NULL) {
    if (!proton_engine_window_request_browser_close(window, 1)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_window_mark_closed(window);
    proton_engine_window_defer_finalize(window);
    proton_engine_window_release_browser(window);
    proton_engine_window_finalize_if_ready(window);
    return PROTON_OK;
  }
  proton_engine_window_mark_closed(window);
  proton_engine_window_defer_finalize(window);
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_hidden = 0;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 0);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    [window->window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_hidden = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    [window->window orderOut:nil];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless && window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  window->close_interception_bypass = 0;
  if (!window->headless) {
    [window->window performClose:nil];
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    if (!proton_engine_window_request_browser_close(window, 0)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    return PROTON_OK;
  }
  proton_engine_window_mark_closed(window);
  window->browser_create_pending = 0;
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {

  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_focused = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->set_focus(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    [NSApp activateIgnoringOtherApps:YES];
    [window->window makeKeyAndOrderFront:nil];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
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

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->width = width;
  window->height = height;
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    NSRect frame = [window->window frame];
    frame.size.width = width;
    frame.size.height = height;
    [window->window setFrame:frame display:YES animate:NO];
  }
  return PROTON_OK;
}

static CGFloat proton_engine_primary_screen_top(void) {
  NSArray<NSScreen *> *screens = [NSScreen screens];
  NSScreen *primary = screens.count > 0 ? screens[0] : nil;
  return primary != nil ? NSMaxY(primary.frame) : 0.0;
}

static int32_t proton_engine_macos_top_y(NSRect frame) {
  return (int32_t)llround(proton_engine_primary_screen_top() - NSMaxY(frame));
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {

  if (window == NULL || action == NULL ||
      (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len,
                              "window and action are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (action->kind == PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT) {
    if (window->browser == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser is not initialized");
      return PROTON_ERR_NOT_INITIALIZED;
    }
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available");
      return PROTON_ERR_ENGINE;
    }
    const double factor = (double)action->value / 100.0;
    host->set_zoom_level(host, log(factor) / log(1.2));
    host->base.release((cef_base_ref_counted_t *)host);
    window->zoom_percent = action->value;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "native window operation is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  switch (action->kind) {
  case PROTON_ENGINE_WINDOW_MINIMIZE:
    [window->window miniaturize:nil];
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    if ([window->window isMiniaturized]) {
      [window->window deminiaturize:nil];
    }
    if (![window->window isZoomed]) {
      [window->window zoom:nil];
    }
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    if ((window->window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
      [window->window toggleFullScreen:nil];
    }
    if ([window->window isMiniaturized]) {
      [window->window deminiaturize:nil];
    }
    if ([window->window isZoomed]) {
      [window->window zoom:nil];
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN: {
    const BOOL fullscreen =
        (window->window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (fullscreen != (action->value != 0)) {
      [window->window toggleFullScreen:nil];
    }
    break;
  }
  case PROTON_ENGINE_WINDOW_SET_POSITION: {
    NSRect frame = window->window.frame;
    const CGFloat cocoa_y =
        proton_engine_primary_screen_top() - action->y - frame.size.height;
    [window->window
        setFrameOrigin:NSMakePoint((CGFloat)action->x, cocoa_y)];
    break;
  }
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    window->window.level =
        action->value != 0 ? NSFloatingWindowLevel : NSNormalWindowLevel;
    break;
  default:
    proton_engine_set_message(error, error_len,
                              "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state,
    char *error,
    size_t error_len) {

  if (window == NULL || out_state == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and out_state are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(out_state, 0, sizeof(*out_state));
  out_state->zoom_percent =
      window->zoom_percent > 0 ? window->zoom_percent : 100;
  out_state->scale_factor_percent = 100;
  if (window->headless) {
    out_state->width = window->width;
    out_state->height = window->height;
    out_state->visible = !window->headless_hidden;
    out_state->focused = window->headless_focused;
    return PROTON_OK;
  }
  if (window->window == nil) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  const NSRect frame = window->window.frame;
  NSScreen *screen = window->window.screen;
  if (screen == nil) {
    screen = [NSScreen mainScreen];
  }
  const NSRect monitor = screen != nil ? screen.frame : NSZeroRect;
  const NSRect work = screen != nil ? screen.visibleFrame : NSZeroRect;
  out_state->x = (int32_t)llround(frame.origin.x);
  out_state->y = proton_engine_macos_top_y(frame);
  out_state->width = (int32_t)llround(frame.size.width);
  out_state->height = (int32_t)llround(frame.size.height);
  out_state->monitor_x = (int32_t)llround(monitor.origin.x);
  out_state->monitor_y = proton_engine_macos_top_y(monitor);
  out_state->monitor_width = (int32_t)llround(monitor.size.width);
  out_state->monitor_height = (int32_t)llround(monitor.size.height);
  out_state->work_x = (int32_t)llround(work.origin.x);
  out_state->work_y = proton_engine_macos_top_y(work);
  out_state->work_width = (int32_t)llround(work.size.width);
  out_state->work_height = (int32_t)llround(work.size.height);
  out_state->scale_factor_percent =
      (int32_t)llround(window->window.backingScaleFactor * 100.0);
  out_state->visible = window->window.isVisible ? 1 : 0;
  out_state->focused = window->window.isKeyWindow ? 1 : 0;
  out_state->minimized = window->window.isMiniaturized ? 1 : 0;
  out_state->maximized = window->window.isZoomed ? 1 : 0;
  out_state->fullscreen =
      (window->window.styleMask & NSWindowStyleMaskFullScreen) != 0 ? 1 : 0;
  out_state->always_on_top =
      window->window.level > NSNormalWindowLevel ? 1 : 0;
  NSAppearance *appearance = window->window.effectiveAppearance;
  NSAppearanceName match = [appearance
      bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
      ]];
  out_state->theme = [match isEqualToString:NSAppearanceNameDarkAqua] ? 2 : 1;
  return PROTON_OK;
}

int32_t proton_engine_window_set_close_interception(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {

  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->close_interception_enabled = enabled != 0;
  if (!window->close_interception_enabled) {
    window->close_request_pending = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len) {

  if (window == NULL || out_request_id == NULL || out_pending == NULL) {
    proton_engine_set_message(
        error, error_len,
        "window, out_request_id, and out_pending are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request_id = window->close_request_id;
  *out_pending = window->close_request_pending;
  return PROTON_OK;
}

int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len) {

  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!window->close_request_pending ||
      window->close_request_id != request_id) {
    proton_engine_set_message(error, error_len,
                              "window close request is no longer pending");
    return PROTON_ERR_STALE_WINDOW_REQUEST;
  }
  window->close_request_pending = 0;
  if (allow && !window->closed) {
    window->close_interception_bypass = 1;
    if (window->headless) {
      return proton_engine_window_close(window, error, error_len);
    }
    [window->window performClose:nil];
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

static int32_t proton_engine_window_load_document(
    proton_engine_window_t *window, const char *html,
    const char *document_url, const char *asset_root, char *error,
    size_t error_len) {
  char *url = NULL;
  size_t html_len = 0;
  int32_t status = proton_engine_window_install_document(
      window, html, document_url, asset_root, &url, &html_len, error,
      error_len);
  if (status != PROTON_OK) {
    return status;
  }
  /* Before the browser exists there is nothing to navigate, so the create
     path picks this url up as its initial navigation instead. */
  if ((window->browser == NULL &&
       (window->browser_create_pending || window->browser_create_scheduled)) ||
      window->initial_navigation_pending) {
    free(window->initial_url);
    window->initial_url = url;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  proton_engine_debug_log("load_html browser=%d document_url=%s bytes=%llu",
                          window->browser_id, url,
                          (unsigned long long)html_len);
  status = proton_engine_window_load_url(window, url, error, error_len);
  free(url);
  return status;
}

int32_t proton_engine_window_load_html(proton_engine_window_t *window,
                                       const char *html,
                                       const char *base_url,
                                       char *error,
                                       size_t error_len) {

  return proton_engine_window_load_document(window, html, base_url, NULL,
                                             error, error_len);
}

int32_t proton_engine_window_load_asset(proton_engine_window_t *window,
                                        const char *html,
                                        const char *document_url,
                                        const char *asset_root,
                                        char *error,
                                        size_t error_len) {

  if (asset_root == NULL || asset_root[0] == '\0') {
    proton_engine_set_message(error, error_len, "asset_root is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return proton_engine_window_load_document(
      window, html, document_url, asset_root, error, error_len);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_poll_browser_event_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_poll_event_json(
      window->browser_session, buffer, buffer_len, out_required_len, error,
      error_len);
}

int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len) {

  if (window == NULL || window->browser_session == NULL ||
      window->browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(
      window->browser_session, window->browser, command_json, error,
      error_len);
}

int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len) {

  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_respond_json(
      window->browser_session, response_json, error, error_len);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

void proton_engine_window_bind_public_id(proton_engine_window_t *window,
                                         proton_window_id_t public_window) {

  if (window != NULL) {
    window->public_window_id = public_window;
    proton_browser_session_bind_window(window->browser_session,
                                       public_window);
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


// MARK: - Web contents views
//
// A view is an extra browser hosted inside a window's content view, following
// the Electron WebContentsView model: explicit top-left bounds, visibility,
// z-order, and an independent load_url target. Views reuse the window's
// deferred browser-creation dance (CEF issue 3810) and mirror the window
// browser close/finalize state machine: closing is gated on CEF's
// on_before_close, and the owning window's finalize waits until every view
// has left its view list.

typedef struct {
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int visible;
  int has_background_color;
  uint32_t background_color;
} proton_engine_view_config_t;

typedef struct {
  cef_task_t task;
  proton_engine_ref_counted_t refs;
  uint64_t native_id;
} proton_engine_view_navigation_task_t;

static void proton_engine_view_list_add(proton_engine_window_t *window,
                                        proton_engine_view_t *view) {
  proton_engine_window_lock();
  view->next = window->views;
  window->views = view;
  proton_engine_window_unlock();
}

// Converts the public top-left bounds into the content view's bottom-left
// coordinate space and pins the view to the top edge so window resizes keep
// the Electron-style top-left anchoring.
static void proton_engine_view_apply_frame(proton_engine_view_t *view) {
  if (view == NULL || view->window == NULL ||
      view->window->content_view == nil || view->browser_view == nil) {
    return;
  }
  CGFloat content_height = view->window->content_view.bounds.size.height;
  NSRect frame = NSMakeRect((CGFloat)view->x,
                            content_height - (CGFloat)view->y -
                                (CGFloat)view->height,
                            (CGFloat)view->width, (CGFloat)view->height);
  [view->browser_view setFrame:frame];
  [view->browser_view setAutoresizingMask:NSViewMinYMargin];
  [view->browser_view setHidden:view->visible ? NO : YES];
}

// Re-orders view browser views above the window's main browser view by
// ascending (z_order, native_id); the main browser view stays at the bottom
// because it was added first and is never re-added here.
static void proton_engine_window_layout_views(proton_engine_window_t *window) {
  if (window == NULL || window->content_view == nil) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->browser_view != nil && !view->closed) {
      count++;
    }
  }
  if (count == 0) {
    return;
  }
  proton_engine_view_t **order =
      (proton_engine_view_t **)malloc(count * sizeof(*order));
  if (order == NULL) {
    return;
  }
  size_t index = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->browser_view != nil && !view->closed) {
      order[index++] = view;
    }
  }
  for (size_t i = 1; i < count; i++) {
    proton_engine_view_t *current = order[i];
    size_t j = i;
    while (j > 0 &&
           (order[j - 1]->z_order > current->z_order ||
            (order[j - 1]->z_order == current->z_order &&
             order[j - 1]->native_id > current->native_id))) {
      order[j] = order[j - 1];
      j--;
    }
    order[j] = current;
  }
  for (size_t i = 0; i < count; i++) {
    [window->content_view addSubview:order[i]->browser_view
                          positioned:NSWindowAbove
                          relativeTo:nil];
  }
  free(order);
}

static void proton_engine_view_release_browser(proton_engine_view_t *view) {
  if (view != NULL && view->browser != NULL) {
    cef_browser_t *browser = view->browser;
    view->browser = NULL;
    proton_engine_browser_release(browser);
  }
}

static int proton_engine_view_request_browser_close(proton_engine_view_t *view,
                                                    int force_close) {
  if (view == NULL || view->browser == NULL) {
    return 0;
  }
  if (view->browser_close_requested && !force_close) {
    return 1;
  }
  view->browser_close_requested = 1;
  cef_browser_host_t *host = view->browser->get_host(view->browser);
  if (host == NULL) {
    return 0;
  }
  host->close_browser(host, force_close);
  host->base.release((cef_base_ref_counted_t *)host);
  // For windowed rendering the browser only dies once its host view leaves
  // the view hierarchy (CefBrowserHostView dealloc -> WindowDestroyed). The
  // detach is owned by do_close, which runs inside the close handshake above
  // and cancels CEF's default performClose: on the owning NSWindow. Do NOT
  // detach here: when CEF defers the close past this call (beforeunload or
  // unload handlers), do_close would later find browser_view already nil and
  // fall through to CEF's default, which the window delegate cancels, wedging
  // the browser half-closed and leaking it.
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return 1;
}

static void proton_engine_view_mark_closed(proton_engine_view_t *view) {
  if (view == NULL) {
    return;
  }
  if (!view->closed) {
    proton_engine_debug_log("view_closed browser=%d", view->browser_id);
  }
  view->closed = 1;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_view_defer_finalize(proton_engine_view_t *view) {
  if (view == NULL) {
    return;
  }
  if (!view->finalize_after_browser_close && view->browser_id != 0) {
    proton_engine_debug_log("view_browser_close_deferred browser=%d",
                            view->browser_id);
  }
  view->finalize_after_browser_close = 1;
  view->browser_create_pending = 0;
  if (view->client != NULL && !view->browser_create_scheduled) {
    view->client->view = NULL;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_window_free_views(proton_engine_window_t *window) {
  proton_engine_view_t *view = window->views;
  window->views = NULL;
  while (view != NULL) {
    proton_engine_view_t *next = view->next;
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    free(view->html_url);
    free(view->html);
    free(view->client);
    free(view->initial_url);
    free(view);
    view = next;
  }
}

static void proton_engine_view_finalize_if_ready(proton_engine_view_t *view) {
  if (view == NULL || view->finalized ||
      !view->finalize_after_browser_close) {
    return;
  }
  if (view->browser_create_scheduled || view->initial_navigation_pending) {
    return;
  }
  if (view->browser_id != 0 && !view->browser_before_close_seen) {
    return;
  }
  // Resource cleanup only. The struct stays in the window's view list and is
  // freed by proton_engine_window_free once every view has finalized, which
  // keeps native ABI view slots valid for the whole window lifetime.
  if (view->client != NULL) {
    view->client->view = NULL;
  }
  if (view->browser_view != nil) {
    [view->browser_view removeFromSuperview];
    view->browser_view = nil;
  }
  view->finalized = 1;
  // The window's own finalize is gated on every view being finalized; this
  // call is a no-op unless the window is waiting on exactly this view.
  proton_engine_window_finalize_if_ready(view->window);
}

static void proton_engine_window_close_views(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->closed) {
      if (view->browser != NULL) {
        proton_engine_view_request_browser_close(view, 1);
        proton_engine_view_mark_closed(view);
        proton_engine_view_defer_finalize(view);
        proton_engine_view_release_browser(view);
      } else {
        proton_engine_view_mark_closed(view);
        proton_engine_view_defer_finalize(view);
      }
    } else if (!view->finalize_after_browser_close) {
      // Already closed by the page (JS window.close): allow its cleanup to
      // complete so the window finalize gate can pass.
      proton_engine_view_defer_finalize(view);
    }
    proton_engine_view_finalize_if_ready(view);
  }
}

static int32_t proton_engine_view_create_browser(proton_engine_view_t *view,
                                                 char *error,
                                                 size_t error_len) {
  proton_engine_window_t *window = view->window;
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
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  }
  CGFloat content_height = window->content_view != nil
                               ? window->content_view.bounds.size.height
                               : (CGFloat)(view->y + view->height);
  window_info.bounds.x = view->x;
  window_info.bounds.y =
      (int)(content_height - (CGFloat)view->y - (CGFloat)view->height);
  window_info.bounds.width = view->width;
  window_info.bounds.height = view->height;
  if (view->has_background_color) {
    browser_settings.background_color = view->background_color;
  }
  proton_engine_set_string(&window_info.window_name, "ProtonView");
  proton_engine_set_string(&url, "about:blank");
  int accepted = cef_browser_host_create_browser(
      &window_info, &view->client->client, &url, &browser_settings, NULL,
      NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (!accepted) {
    proton_engine_set_message(error, error_len, "view browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

static void proton_engine_view_schedule_browser_create(
    proton_engine_view_t *view) {
  uint64_t native_id = view->native_id;
  view->browser_create_scheduled = 1;
  // Mirror the window path: create CEF browsers after the main run loop has
  // started pumping (CEF issue 3810).
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_view_t *pending_view =
        proton_engine_view_from_native_id(native_id);
    if (pending_view == NULL) {
      return;
    }
    if (pending_view->closed || !pending_view->browser_create_pending) {
      pending_view->browser_create_scheduled = 0;
      proton_engine_view_finalize_if_ready(pending_view);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
      return;
    }
    pending_view->browser_create_pending = 0;
    pending_view->initial_navigation_pending = 1;
    char error[512] = {0};
    int32_t status =
        proton_engine_view_create_browser(pending_view, error, sizeof(error));
    if (status != PROTON_OK) {
      pending_view->initial_navigation_pending = 0;
      pending_view->browser_create_scheduled = 0;
      proton_engine_debug_log("view_create_browser_failed status=%d error=%s",
                              status, error);
      proton_engine_view_mark_closed(pending_view);
      proton_engine_view_finalize_if_ready(pending_view);
    }
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static void CEF_CALLBACK proton_engine_view_navigation_task_execute(
    cef_task_t *base) {
  proton_engine_view_navigation_task_t *task =
      (proton_engine_view_navigation_task_t *)base;
  proton_engine_view_t *view = proton_engine_view_from_native_id(
      task->native_id);
  if (view == NULL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      free(task);
    });
    return;
  }
  view->initial_navigation_pending = 0;
  if (view->initial_url != NULL && view->initial_url[0] != '\0' &&
      strcmp(view->initial_url, "about:blank") != 0) {
    char error[512] = {0};
    int32_t status = proton_engine_view_load_url(view, view->initial_url,
                                                 error, sizeof(error));
    if (status != PROTON_OK) {
      proton_engine_debug_log("view_load_initial_url_failed status=%d error=%s",
                              status, error);
      proton_engine_view_mark_closed(view);
      proton_engine_view_request_browser_close(view, 1);
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  uint64_t native_id = task->native_id;
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_view_t *pending_view =
        proton_engine_view_from_native_id(native_id);
    if (pending_view != NULL) {
      proton_engine_view_finalize_if_ready(pending_view);
    }
    free(task);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static int proton_engine_view_schedule_initial_navigation(
    proton_engine_view_t *view) {
  proton_engine_view_navigation_task_t *task = calloc(1, sizeof(*task));
  if (task == NULL) {
    return 0;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&task->task,
                                 sizeof(task->task), &task->refs);
  task->task.execute = proton_engine_view_navigation_task_execute;
  task->native_id = view->native_id;
  int posted = cef_post_task(TID_UI, &task->task);
  if (!posted) {
    free(task);
  }
  return posted;
}

static void proton_engine_view_on_after_created(proton_engine_view_t *view,
                                                cef_browser_t *browser) {
  if (view == NULL || browser == NULL) {
    return;
  }
  proton_engine_window_t *window = view->window;
  cef_browser_host_t *host = browser->get_host(browser);
  browser->base.add_ref((cef_base_ref_counted_t *)browser);
  view->browser = browser;
  view->browser_id = browser->get_identifier(browser);
  view->browser_create_scheduled = 0;
  if (host != NULL) {
    if (window->headless) {
      if (!view->visible && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
    } else {
      view->browser_view = (__bridge NSView *)host->get_window_handle(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
  }
  if (window->content_view != nil && view->browser_view != nil) {
    if (view->browser_view.superview == nil) {
      [window->content_view addSubview:view->browser_view];
    }
    proton_engine_view_apply_frame(view);
    proton_engine_window_layout_views(window);
  }
  proton_engine_debug_log("view_create_browser id=%d rect=%d,%d %dx%d",
                          view->browser_id, (int)view->x, (int)view->y,
                          (int)view->width, (int)view->height);

  if (view->closed || view->finalize_after_browser_close) {
    view->initial_navigation_pending = 0;
    proton_engine_view_request_browser_close(view, 1);
    proton_engine_view_release_browser(view);
    proton_engine_view_finalize_if_ready(view);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  if (!proton_engine_view_schedule_initial_navigation(view)) {
    view->initial_navigation_pending = 0;
    proton_engine_debug_log("view_initial_navigation_post_failed browser=%d",
                            view->browser_id);
    proton_engine_view_mark_closed(view);
    proton_engine_view_request_browser_close(view, 1);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_view_on_before_close(proton_engine_view_t *view,
                                               cef_browser_t *browser) {
  (void)browser;
  if (view == NULL) {
    return;
  }
  proton_engine_debug_log("view_browser_before_close browser=%d",
                          view->browser_id);
  view->browser_before_close_seen = 1;
  proton_engine_view_mark_closed(view);
  proton_engine_view_release_browser(view);
  if (view->browser_view != nil) {
    [view->browser_view removeFromSuperview];
    view->browser_view = nil;
  }
  // A page-initiated close (JS window.close) reaches here without a prior
  // engine destroy; let the cleanup state machine finish so the struct can be
  // reclaimed with its owning window.
  view->finalize_after_browser_close = 1;
  proton_engine_view_finalize_if_ready(view);
}

static proton_engine_client_t *proton_engine_view_client_create(
    proton_engine_view_t *view) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->view = view;
  // Views wire the life span, load, display, and render handlers: life span
  // drives the close state machine, load/display feed the view event stream,
  // and the render handler gives headless (OSR) views a viewport. Navigation
  // policy, bridge, downloads, and permissions stay window-scoped for now,
  // and CEF defaults (cancel popups, no bridge bootstrap) apply to view
  // browsers.
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_display_handler = proton_engine_client_get_display_handler;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
  return client;
}

// Parses "#RRGGBB" or "#AARRGGBB" into a cef_color_t (0xAARRGGBB).
static int proton_engine_parse_color_argb(const char *text,
                                          uint32_t *out_color) {
  if (text == NULL || text[0] != '#') {
    return 0;
  }
  size_t len = strlen(text);
  if (len != 7 && len != 9) {
    return 0;
  }
  for (size_t i = 1; i < len; i++) {
    if (!isxdigit((unsigned char)text[i])) {
      return 0;
    }
  }
  unsigned long value = strtoul(text + 1, NULL, 16);
  if (len == 7) {
    value |= 0xFF000000UL;
  }
  *out_color = (uint32_t)value;
  return 1;
}

static int32_t proton_engine_parse_view_config(
    const char *config_json,
    proton_engine_view_config_t *config,
    char *error,
    size_t error_len) {
  if (config_json == NULL || config == NULL) {
    proton_engine_set_message(error, error_len, "view config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(config, 0, sizeof(*config));
  config->visible = 1;
  if (!proton_engine_parse_json_int_field(config_json, "width",
                                          &config->width) ||
      !proton_engine_parse_json_int_field(config_json, "height",
                                          &config->height)) {
    proton_engine_set_message(error, error_len,
                              "view config requires numeric width and height");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (config->width <= 0 || config->height <= 0) {
    proton_engine_set_message(error, error_len,
                              "view width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_parse_json_int_field(config_json, "x", &config->x);
  proton_engine_parse_json_int_field(config_json, "y", &config->y);
  proton_engine_parse_json_int_field(config_json, "z_order", &config->z_order);
  bool visible = true;
  if (proton_engine_parse_json_bool_field(config_json, "visible", &visible)) {
    config->visible = visible ? 1 : 0;
  }
  proton_engine_parse_json_string_field(config_json, "initial_url",
                                        config->initial_url,
                                        sizeof(config->initial_url));
  char background_color[16] = {0};
  if (proton_engine_parse_json_string_field(
          config_json, "background_color", background_color,
          sizeof(background_color))) {
    if (!proton_engine_parse_color_argb(background_color,
                                        &config->background_color)) {
      proton_engine_set_message(
          error, error_len,
          "view background_color must be #RRGGBB or #AARRGGBB");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
    config->has_background_color = 1;
  }
  return PROTON_OK;
}

int32_t proton_engine_view_create_json(proton_engine_window_t *window,
                                       const char *config_json,
                                       proton_engine_view_t **out_view,
                                       char *error,
                                       size_t error_len) {

  if (out_view == NULL) {
    proton_engine_set_message(error, error_len, "out_view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_view = NULL;
  if (window == NULL || config_json == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and view config are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->closed) {
    proton_engine_set_message(error, error_len, "window is closed");
    return PROTON_ERR_DESTROYED;
  }
  if (!g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_view_config_t config;
  int32_t status =
      proton_engine_parse_view_config(config_json, &config, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }

  proton_engine_view_t *view =
      (proton_engine_view_t *)calloc(1, sizeof(*view));
  if (view == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  view->window = window;
  view->native_id = g_next_view_native_id++;
  if (g_next_view_native_id == 0) {
    g_next_view_native_id = 1;
  }
  view->x = config.x;
  view->y = config.y;
  view->width = config.width;
  view->height = config.height;
  view->z_order = config.z_order;
  view->visible = config.visible;
  view->client = proton_engine_view_client_create(view);
  if (view->client == NULL) {
    free(view);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }
  view->initial_url = proton_engine_strdup(
      config.initial_url[0] != '\0' ? config.initial_url : "about:blank");
  if (view->initial_url == NULL) {
    free(view->client);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to copy initial browser url");
    return PROTON_ERR_ENGINE;
  }
  // Views own a browser session with a fixed, non-interactive policy so the
  // usual browser commands (back/forward/reload/stop/devtools) work per view;
  // ASK flows are never used here.
  proton_browser_policy_t view_policy = {PROTON_BROWSER_POLICY_ALLOW,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         1};
  view->browser_session = proton_browser_session_create(
      &view_policy, proton_engine_browser_signal, NULL);
  view->events = proton_view_events_create();
  if (view->browser_session == NULL || view->events == NULL) {
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    free(view->initial_url);
    free(view->client);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  view->has_background_color = config.has_background_color;
  view->background_color = config.background_color;
  proton_engine_debug_log("view_create rect=%d,%d %dx%d visible=%d z=%d",
                          (int)view->x, (int)view->y, (int)view->width,
                          (int)view->height, view->visible,
                          (int)view->z_order);
  view->browser_create_pending = 1;
  proton_engine_view_list_add(window, view);
  proton_engine_view_schedule_browser_create(view);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  *out_view = view;
  return PROTON_OK;
}

int32_t proton_engine_view_destroy(proton_engine_view_t *view,
                                   char *error,
                                   size_t error_len) {

  if (view == NULL) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->closed) {
    return PROTON_OK;
  }
  if (view->browser != NULL) {
    if (!proton_engine_view_request_browser_close(view, 1)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_view_mark_closed(view);
    proton_engine_view_defer_finalize(view);
    proton_engine_view_release_browser(view);
    proton_engine_view_finalize_if_ready(view);
    return PROTON_OK;
  }
  proton_engine_view_mark_closed(view);
  proton_engine_view_defer_finalize(view);
  proton_engine_view_finalize_if_ready(view);
  return PROTON_OK;
}

int32_t proton_engine_view_set_bounds(proton_engine_view_t *view,
                                      int32_t x,
                                      int32_t y,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {

  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "view width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->x = x;
  view->y = y;
  view->width = width;
  view->height = height;
  if (view->window != NULL && view->window->headless) {
    if (view->browser != NULL) {
      cef_browser_host_t *host = view->browser->get_host(view->browser);
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    proton_engine_view_apply_frame(view);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_visible(proton_engine_view_t *view,
                                       int32_t visible,
                                       char *error,
                                       size_t error_len) {

  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->visible = visible ? 1 : 0;
  if (view->window != NULL && view->window->headless) {
    if (view->browser != NULL) {
      cef_browser_host_t *host = view->browser->get_host(view->browser);
      if (host != NULL && host->was_hidden != NULL) {
        host->was_hidden(host, view->visible ? 0 : 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else if (view->browser_view != nil) {
    [view->browser_view setHidden:view->visible ? NO : YES];
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_z_order(proton_engine_view_t *view,
                                       int32_t z_order,
                                       char *error,
                                       size_t error_len) {

  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->z_order = z_order;
  proton_engine_window_layout_views(view->window);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_load_url(proton_engine_view_t *view,
                                    const char *url,
                                    char *error,
                                    size_t error_len) {

  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((view->browser == NULL &&
       (view->browser_create_pending || view->browser_create_scheduled)) ||
      view->initial_navigation_pending) {
    char *url_copy =
        proton_engine_strdup(url != NULL && url[0] != '\0' ? url : "about:blank");
    if (url_copy == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
    free(view->initial_url);
    view->initial_url = url_copy;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = view->browser->get_main_frame(view->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t cef_url = {0};
  proton_engine_set_string(&cef_url, url != NULL ? url : "about:blank");
  proton_engine_debug_log("view_load_url browser=%d url=%s", view->browser_id,
                          url != NULL ? url : "about:blank");
  frame->load_url(frame, &cef_url);
  cef_string_clear(&cef_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_eval(proton_engine_view_t *view,
                                const char *script,
                                char *error,
                                size_t error_len) {

  if (view == NULL || view->closed || view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = view->browser->get_main_frame(view->browser);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_load_html(proton_engine_view_t *view,
                                     const char *html,
                                     const char *base_url,
                                     char *error,
                                     size_t error_len) {

  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
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
  if ((view->browser == NULL &&
       (view->browser_create_pending || view->browser_create_scheduled)) ||
      view->initial_navigation_pending) {
    pending_url = proton_engine_strdup(effective_base_url);
    if (pending_url == NULL) {
      free(url_copy);
      free(html_copy);
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
  }
  proton_engine_window_lock();
  free(view->html_url);
  free(view->html);
  view->html_url = url_copy;
  view->html = html_copy;
  view->html_len = strlen(html_copy);
  proton_engine_window_unlock();
  if (pending_url != NULL) {
    free(view->initial_url);
    view->initial_url = pending_url;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  proton_engine_debug_log("view_load_html browser=%d base_url=%s bytes=%llu",
                          view->browser_id, effective_base_url,
                          (unsigned long long)view->html_len);
  return proton_engine_view_load_url(view, effective_base_url, error,
                                     error_len);
}

int32_t proton_engine_view_browser_command_json(proton_engine_view_t *view,
                                                const char *command_json,
                                                char *error,
                                                size_t error_len) {

  if (view == NULL || view->closed || view->browser_session == NULL ||
      view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(view->browser_session,
                                             view->browser, command_json,
                                             error, error_len);
}

int32_t proton_engine_view_poll_event_json(proton_engine_view_t *view,
                                           char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len,
                                           char *error,
                                           size_t error_len) {
  (void)error;
  (void)error_len;
  // The ABI event sweep calls this on the runtime owner thread; the event
  // queue carries its own lock, so no main-thread marshal here.
  if (view == NULL || view->events == NULL) {
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_view_events_poll_json(view->events, buffer, buffer_len,
                                      out_required_len);
}

void proton_engine_view_bind_public_id(proton_engine_view_t *view,
                                       proton_view_id_t public_view) {

  if (view != NULL && view->window != NULL) {
    proton_view_events_bind(view->events, public_view,
                            proton_engine_window_public_id(view->window));
  }
}

int32_t proton_engine_screen_enumerate(
    proton_engine_screen_info_t *out_screens,
    int32_t max_screens,
    int32_t *out_count,
    char *error,
    size_t error_len) {
  PROTON_ENGINE_RETURN_ON_MAIN(
      proton_engine_screen_enumerate(out_screens, max_screens, out_count,
                                     error, error_len));
  if (out_screens == NULL || out_count == NULL || max_screens <= 0) {
    proton_engine_set_message(error, error_len,
                              "out_screens, out_count are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = 0;

  @autoreleasepool {
    NSArray *screens = [NSScreen screens];
    NSUInteger count = [screens count];
    if (count == 0) {
      return PROTON_OK;
    }
    NSScreen *primary = [screens objectAtIndex:0];
    NSRect primaryFrame = [primary frame];

    int32_t idx = 0;
    for (NSUInteger i = 0; i < count && idx < max_screens; i++) {
      NSScreen *screen = [screens objectAtIndex:i];
      NSRect frame = [screen frame];
      NSRect visibleFrame = [screen visibleFrame];

      /* macOS uses a bottom-left origin; convert to top-left so the
         coordinates match Windows/Linux and the rest of the Proton API. */
      proton_engine_screen_info_t *info = &out_screens[idx];
      info->id = (int32_t)i;
      info->x = (int32_t)frame.origin.x;
      info->y = (int32_t)(primaryFrame.size.height - frame.origin.y -
                          frame.size.height);
      info->width = (int32_t)frame.size.width;
      info->height = (int32_t)frame.size.height;
      info->work_x = (int32_t)visibleFrame.origin.x;
      info->work_y = (int32_t)(primaryFrame.size.height -
                               visibleFrame.origin.y -
                               visibleFrame.size.height);
      info->work_width = (int32_t)visibleFrame.size.width;
      info->work_height = (int32_t)visibleFrame.size.height;

      CGFloat scaleFactor = [screen backingScaleFactor];
      info->scale_factor_percent = (int32_t)(scaleFactor * 100.0);
      info->is_primary = (i == 0) ? 1 : 0;

      idx++;
    }
    *out_count = idx;
  }
  return PROTON_OK;
}
