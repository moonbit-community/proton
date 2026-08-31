#if defined(__APPLE__)

#include "../ffi/src/proton_engine.h"
#include "../ffi/src/proton_config.h"
#include "../ffi/src/proton_event.h"
#include "../ffi/src/proton_json.h"

#include "mac_dialog.h"
#include "mac_internal.h"
#include "mac_launch_input.h"
#include "mac_menu.h"
#include "mac_window.h"

#include "../ffi/src/engine/cef_common/message.h"
#include "../ffi/src/engine/cef_common/profile_storage.h"
#include "../ffi/src/engine/cef_common/scheme.h"

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

#include "../ffi/src/engine/cef_common/app_origin.h"
#include "../ffi/src/engine/cef_common/bridge_renderer.h"
#include "../ffi/src/engine/cef_common/bridge_lifecycle.h"
#include "../ffi/src/engine/cef_common/browser_session.h"
#include "../ffi/src/engine/cef_common/view_events.h"

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
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int g_proton_cef_initialized = 0;
static int g_proton_cef_library_loaded = 0;
static int g_proton_cef_runtime_active = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
static int32_t g_proton_remote_debugging_port =
    PROTON_REMOTE_DEBUGGING_DISABLED;

/* Guards g_windows list membership read by CEF callback threads. Keep this
   lock leaf-only: never call back into engine or CEF code while held. */
static pthread_mutex_t g_proton_engine_window_lock = PTHREAD_MUTEX_INITIALIZER;

void proton_engine_window_lock(void) {
  pthread_mutex_lock(&g_proton_engine_window_lock);
}

void proton_engine_window_unlock(void) {
  pthread_mutex_unlock(&g_proton_engine_window_lock);
}
static uint64_t g_next_view_native_id = 1;
static atomic_bool g_external_message_pump_enabled = false;
// Main-thread only, so a plain bool: set by proton_engine_host_loop_begin and
// cleared by proton_engine_host_loop_end, both of which refuse other threads.
static bool g_host_loop_active = false;
static atomic_llong g_scheduled_pump_deadline_ms = -1;
static atomic_bool g_message_pump_active = false;
static atomic_uint g_wait_source_ready_mask = PROTON_WAIT_NONE;
static CFRunLoopRef g_wait_run_loop = NULL;
static CFRunLoopSourceRef g_wait_source = NULL;

int proton_engine_runtime_initialized(void) {
  return g_proton_cef_initialized;
}

uint64_t proton_engine_allocate_view_native_id(void) {
  uint64_t native_id = g_next_view_native_id++;
  if (g_next_view_native_id == 0) {
    g_next_view_native_id = 1;
  }
  return native_id;
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

void proton_engine_signal_wait_source(uint32_t ready_mask) {
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
}

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  (void)runtime;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_browser_signal(void *user_data) {
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
  proton_engine_reset_scheduled_pump();
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

static bool proton_engine_dir_exists(const char *path) {
  struct stat info;
  return path != NULL && path[0] != '\0' && stat(path, &info) == 0 &&
         S_ISDIR(info.st_mode);
}

int proton_engine_load_cef_library(
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
  if (!cef_load_library(framework_binary)) {
    proton_engine_set_message(error, error_len, "failed to load CEF framework");
    return 0;
  }
  g_proton_cef_library_loaded = 1;
  return 1;
}

void proton_engine_unload_cef_library(void) {
  if (g_proton_cef_library_loaded) {
    (void)cef_unload_library();
    g_proton_cef_library_loaded = 0;
  }
}

#include "../ffi/src/engine/cef_common/strings.h"
#include "../ffi/src/engine/cef_common/json_fields.h"

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
#include "../ffi/src/engine/cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../ffi/src/engine/cef_common/bridge_json.h"

void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar) {
  (void)self;
  proton_engine_register_app_custom_schemes(registrar);
}

void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  if ((process_type == NULL || process_type->length == 0) &&
      g_proton_remote_debugging_port ==
          PROTON_REMOTE_DEBUGGING_EPHEMERAL) {
    proton_engine_append_switch_with_value(command_line,
                                           "remote-debugging-port", "0");
  }
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

void CEF_CALLBACK proton_engine_on_schedule_message_pump_work(
    cef_browser_process_handler_t *self,
    int64_t delay_ms) {
  (void)self;
  proton_engine_set_scheduled_pump_delay_ms(delay_ms);
}

void CEF_CALLBACK proton_engine_osr_get_view_rect(
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

int CEF_CALLBACK proton_engine_osr_get_screen_info(
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

void CEF_CALLBACK proton_engine_osr_on_popup_show(
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

void CEF_CALLBACK proton_engine_osr_on_popup_size(
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

void CEF_CALLBACK proton_engine_osr_on_paint(
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
  (void)browser;
  (void)type;
  (void)width;
  (void)height;
}

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
  proton_event_t *event = proton_event_create(PROTON_EVENT_QUIT_REQUESTED);
  if (event != NULL && proton_event_publish(event)) {
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

int32_t proton_engine_execute_process(
    const proton_engine_runtime_config_t *config, int32_t *out_exit_code,
    char *error, size_t error_len) {
  if (config == NULL) {
    proton_engine_set_message(error, error_len, "runtime config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_engine_load_cef_library(config, error, error_len)) {
    return PROTON_ERR_ENGINE;
  }
  proton_engine_check_cef_api_hash();
  cef_main_args_t args;
  memset(&args, 0, sizeof(args));
  args.argc = *_NSGetArgc();
  args.argv = *_NSGetArgv();
  proton_engine_init_handlers();
  int exit_code = cef_execute_process(&args, proton_engine_cef_app(), NULL);
  proton_engine_unload_cef_library();
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
  settings.remote_debugging_port = config.remote_debugging_port > 0
                                       ? config.remote_debugging_port
                                       : PROTON_REMOTE_DEBUGGING_DISABLED;
  settings.persist_session_cookies = config.persist_session_cookies;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.framework_dir_path, config.framework_dir);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  proton_engine_set_string(&settings.locale, config.locale);
  proton_engine_set_string(&settings.accept_language_list,
                           config.accept_languages);
  proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  if (!temporary_profile) {
    proton_engine_set_string(&settings.cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, proton_engine_cef_app(), NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.framework_dir_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.locale);
    cef_string_clear(&settings.accept_language_list);
    cef_string_clear(&settings.cache_path);
    cef_string_clear(&settings.root_cache_path);
    proton_engine_reset_external_message_pump();
    proton_engine_unload_cef_library();
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  g_proton_cef_initialized = 1;

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.framework_dir_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.locale);
  cef_string_clear(&settings.accept_language_list);
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
  runtime->browsers = proton_browser_registry_create(
      proton_engine_browser_client_factory, runtime);
  if (runtime->browsers == NULL) {
    free(runtime);
    proton_engine_cef_shutdown();
    proton_engine_reset_external_message_pump();
    g_proton_cef_runtime_active = 0;
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser registry");
    return PROTON_ERR_ENGINE;
  }
  snprintf(runtime->dialog_ok_label, sizeof(runtime->dialog_ok_label), "%s",
           config.dialog_ok_label);
  snprintf(runtime->dialog_cancel_label,
           sizeof(runtime->dialog_cancel_label), "%s",
           config.dialog_cancel_label);
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    proton_engine_reset_external_message_pump();
    g_proton_cef_runtime_active = 0;
    proton_browser_registry_destroy(runtime->browsers);
    free(runtime);
    proton_engine_set_message(error, error_len,
                              "failed to register proton scheme handler");
    return PROTON_ERR_ENGINE;
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
    if (!proton_engine_runtime_destroy_ready(runtime)) {
      proton_engine_set_message(error, error_len,
                                "runtime still owns closing browser windows");
      return PROTON_ERR_BUSY;
    }
    proton_engine_bridge_pending_clear_all();
    proton_engine_cef_shutdown();
    proton_engine_reset_external_message_pump();
    runtime->owns_cef_runtime = 0;
  }
  proton_browser_registry_destroy(runtime->browsers);
  g_proton_cef_runtime_active = 0;
  free(runtime);
  return PROTON_OK;
}

int32_t proton_engine_runtime_destroy_ready(proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  proton_browser_registry_begin_shutdown(runtime->browsers);
  return !proton_engine_runtime_has_windows(runtime) &&
         proton_browser_registry_shutdown_ready(runtime->browsers);
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

static void proton_engine_run_external_message_pump_once(void) {
  atomic_store_explicit(&g_message_pump_active, true, memory_order_release);
  proton_engine_reset_scheduled_pump();
  proton_engine_pump_appkit_cef_once();
  atomic_store_explicit(&g_message_pump_active, false, memory_order_release);
}

int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_runtime_create_pending_browsers(runtime);
  proton_engine_run_external_message_pump_once();
  return PROTON_OK;
}

static uint32_t proton_engine_runtime_ready_mask(
    proton_engine_runtime_t *runtime,
    uint32_t interest_mask) {
  uint32_t ready_mask = PROTON_WAIT_NONE;
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
  proton_engine_run_external_message_pump_once();
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

  // Negative means PROTON_WAIT_TIMEOUT_INFINITE; the ABI rejects every other
  // negative value before reaching here. -1 stays out of the arithmetic below
  // so it cannot be mistaken for a duration. Already-ready native work makes
  // this a non-blocking turn, but does not skip CoreFoundation: an immediate
  // CEF schedule can otherwise keep returning early forever and starve the
  // AppKit sources that destroy a closing browser's view hierarchy.
  int wait_forever = timeout_ms < 0 && ready_mask == PROTON_WAIT_NONE;
  int64_t wait_timeout =
      timeout_ms < 0 || ready_mask != PROTON_WAIT_NONE ? 0
                                                       : (int64_t)timeout_ms;
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
  CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start_time;

  uint32_t signaled_mask = atomic_exchange_explicit(
      &g_wait_source_ready_mask, PROTON_WAIT_NONE, memory_order_acquire);
  ready_mask |= signaled_mask & interest_mask;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0) {
    if (run_result == kCFRunLoopRunHandledSource ||
        run_result == kCFRunLoopRunStopped) {
      int event_only_source =
          (signaled_mask & PROTON_WAIT_EVENT) != 0 &&
          (signaled_mask & PROTON_WAIT_PLATFORM) == 0;
      if (!event_only_source) {
        ready_mask |= PROTON_WAIT_PLATFORM;
      }
    } else if (waiting_for_platform_pump &&
               elapsed * 1000.0 >= (CFAbsoluteTime)wait_timeout) {
      ready_mask |= PROTON_WAIT_PLATFORM;
    }
  }
  ready_mask |= proton_engine_runtime_ready_mask(runtime, interest_mask);
  ready_mask &= interest_mask;
  *out_ready_mask = ready_mask;
  return PROTON_OK;
}

int32_t proton_engine_runtime_set_menu(
    proton_engine_runtime_t *runtime, const proton_menu_bar_t *menu_bar,
    char *error, size_t error_len) {

  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (runtime->headless) {
    proton_engine_set_message(error, error_len,
                              "native menus are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (menu_bar == NULL) {
    proton_engine_set_message(error, error_len, "menu config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  __block int32_t status = PROTON_OK;
  char main_error[512] = {0};
  char *main_error_buffer = main_error;
  void (^work)(void) = ^{
    status = proton_engine_menu_set_on_main(
        menu_bar, main_error_buffer, sizeof(main_error));
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
#endif

void proton_mac_engine_link_anchor(void) {}
