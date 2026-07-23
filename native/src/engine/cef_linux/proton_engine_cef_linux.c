#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include "../../proton_engine.h"
#include "../../proton_json.h"
#include "proton_linux_titlebar.h"

#ifndef OS_LINUX
#define OS_LINUX 1
#endif
#ifndef CEF_X11
#define CEF_X11 1
#endif

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_request_capi.h"
#include "include/capi/cef_resource_handler_capi.h"
#include "include/capi/cef_response_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"

#include <gdk/gdkx.h>
#include <gtk/gtk.h>

#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
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

#define PROTON_ENGINE_PATH_SEPARATOR '/'
#define PROTON_ENGINE_MAX_PATH_BYTES 4096
#define PROTON_ENGINE_MAX_URL_BYTES 131072
#define PROTON_ENGINE_MAX_BRIDGE_REQUESTS 256
#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
#define PROTON_ENGINE_CLOSE_DRAIN_LIMIT 5000

enum {
  PROTON_X11_MOVERESIZE_SIZE_TOP_LEFT = 0,
  PROTON_X11_MOVERESIZE_SIZE_TOP = 1,
  PROTON_X11_MOVERESIZE_SIZE_TOP_RIGHT = 2,
  PROTON_X11_MOVERESIZE_SIZE_RIGHT = 3,
  PROTON_X11_MOVERESIZE_SIZE_BOTTOM_RIGHT = 4,
  PROTON_X11_MOVERESIZE_SIZE_BOTTOM = 5,
  PROTON_X11_MOVERESIZE_SIZE_BOTTOM_LEFT = 6,
  PROTON_X11_MOVERESIZE_SIZE_LEFT = 7,
  PROTON_X11_MOVERESIZE_MOVE = 8,
};

typedef struct proton_engine_client proton_engine_client_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int64_t next_bridge_request_id;
  char *bridge_queue[PROTON_ENGINE_MAX_BRIDGE_REQUESTS];
  size_t bridge_head;
  size_t bridge_count;
  pthread_mutex_t bridge_lock;
  int bridge_lock_initialized;
  int wake_read_fd;
  int wake_write_fd;
};

struct proton_engine_window {
  proton_engine_runtime_t *runtime;
  GtkWidget *window;
  GtkWidget *overlay;
  GtkWidget *browser_host;
  GtkWidget *overlay_controls;
  GtkWidget *minimize_button;
  GtkWidget *maximize_button;
  GtkWidget *maximize_image;
  GtkWidget *close_button;
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
  int width;
  int height;
  int titlebar_overlay;
  proton_linux_titlebar_region_t *draggable_regions;
  size_t draggable_region_count;
  int draggable_regions_reported;
  guint32 last_drag_click_time;
  int last_drag_click_x;
  int last_drag_click_y;
  GdkWindow *overlay_input_window;
  int closed;
  int closing;
  int destroy_requested;
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
  char *data;
  size_t len;
  char *mime_type;
  size_t offset;
} proton_engine_resource_handler_t;

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

typedef struct {
  char title[512];
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t width;
  int32_t height;
  int titlebar_overlay;
} proton_engine_window_config_t;

static int g_proton_cef_initialized = 0;
static int g_proton_cef_runtime_active = 0;
static int g_proton_cef_shutdown_registered = 0;
static proton_engine_app_t g_app;
static proton_engine_browser_process_handler_t g_browser_process_handler;
static proton_engine_render_process_handler_t g_render_process_handler;
static proton_engine_v8_handler_t g_v8_handler;
static proton_engine_life_span_handler_t g_life_span_handler;
static proton_engine_load_handler_t g_load_handler;
static proton_engine_drag_handler_t g_drag_handler;
static proton_engine_request_handler_t g_request_handler;
static proton_engine_scheme_factory_t g_scheme_factory;
static proton_engine_window_t *g_windows = NULL;
static proton_engine_bridge_pending_t *g_bridge_pending = NULL;
static atomic_llong g_scheduled_pump_delay_ms = ATOMIC_VAR_INIT(-1);
static atomic_int g_runtime_wait_log_count = ATOMIC_VAR_INIT(0);
static atomic_uint g_wait_source_ready_mask = ATOMIC_VAR_INIT(PROTON_WAIT_NONE);
static proton_engine_runtime_t *g_active_runtime = NULL;
static proton_engine_window_t *g_closed_windows = NULL;

static GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                                       GdkEvent *event,
                                                       gpointer user_data);

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

static int proton_engine_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) {
    return 0;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

static void proton_engine_drain_wake_pipe(proton_engine_runtime_t *runtime) {
  if (runtime == NULL || runtime->wake_read_fd < 0) {
    return;
  }
  char buffer[64];
  for (;;) {
    ssize_t read_count =
        read(runtime->wake_read_fd, buffer, sizeof(buffer));
    if (read_count > 0) {
      continue;
    }
    if (read_count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK ||
                           errno == EINTR)) {
      return;
    }
    return;
  }
}

static void proton_engine_close_wake_pipe(proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return;
  }
  if (runtime->wake_read_fd >= 0) {
    close(runtime->wake_read_fd);
    runtime->wake_read_fd = -1;
  }
  if (runtime->wake_write_fd >= 0) {
    close(runtime->wake_write_fd);
    runtime->wake_write_fd = -1;
  }
}

static int proton_engine_setup_wait_source(proton_engine_runtime_t *runtime,
                                           char *error,
                                           size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return 0;
  }
  runtime->wake_read_fd = -1;
  runtime->wake_write_fd = -1;
  int pipe_fds[2] = {-1, -1};
  if (pipe(pipe_fds) != 0 || !proton_engine_set_nonblocking(pipe_fds[0]) ||
      !proton_engine_set_nonblocking(pipe_fds[1])) {
    if (pipe_fds[0] >= 0) {
      close(pipe_fds[0]);
    }
    if (pipe_fds[1] >= 0) {
      close(pipe_fds[1]);
    }
    proton_engine_set_message(error, error_len,
                              "failed to create runtime wait pipe");
    return 0;
  }
  runtime->wake_read_fd = pipe_fds[0];
  runtime->wake_write_fd = pipe_fds[1];
  atomic_store_explicit(&g_wait_source_ready_mask, PROTON_WAIT_NONE,
                        memory_order_release);
  return 1;
}

static void proton_engine_signal_wait_source(uint32_t ready_mask) {
  if (ready_mask != PROTON_WAIT_NONE) {
    atomic_fetch_or_explicit(&g_wait_source_ready_mask, ready_mask,
                             memory_order_release);
  }
  proton_engine_runtime_t *runtime = g_active_runtime;
  if (runtime != NULL && runtime->wake_write_fd >= 0) {
    char byte = 1;
    ssize_t ignored = write(runtime->wake_write_fd, &byte, 1);
    (void)ignored;
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

#include "../cef_common/strings.h"
#include "../cef_common/assets.h"
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

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  window->next = g_windows;
  g_windows = window;
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
  proton_engine_window_t **cursor = &g_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void proton_engine_window_defer_free(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_window_list_remove(window);
  window->next = g_closed_windows;
  g_closed_windows = window;
}

static void proton_engine_overlay_release_input_windows(
    proton_engine_window_t *window) {
  if (window == NULL || window->overlay_input_window == NULL) {
    return;
  }
  gdk_window_remove_filter(window->overlay_input_window,
                           proton_engine_x11_event_filter, NULL);
  g_object_unref(window->overlay_input_window);
  window->overlay_input_window = NULL;
}

static void proton_engine_window_free_storage(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  free(window->client);
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  free(window->draggable_regions);
  proton_engine_overlay_release_input_windows(window);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
}

static void proton_engine_free_closed_windows(void) {
  proton_engine_window_t *window = g_closed_windows;
  g_closed_windows = NULL;
  while (window != NULL) {
    proton_engine_window_t *next = window->next;
    window->next = NULL;
    proton_engine_window_free_storage(window);
    window = next;
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

static char *proton_engine_request_url(cef_request_t *request) {
  if (request == NULL) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(request->get_url(request));
}

static int CEF_CALLBACK proton_engine_resource_open(
    cef_resource_handler_t *self,
    cef_request_t *request,
    int *handle_request,
    cef_callback_t *callback) {
  (void)request;
  (void)callback;
  if (self == NULL || handle_request == NULL) {
    return 0;
  }
  *handle_request = 1;
  return 1;
}

static void CEF_CALLBACK proton_engine_resource_get_response_headers(
    cef_resource_handler_t *self,
    cef_response_t *response,
    int64_t *response_length,
    cef_string_t *redirectUrl) {
  (void)redirectUrl;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (response != NULL) {
    cef_string_t mime = {0};
    proton_engine_set_string(&mime, handler->mime_type != NULL
                                        ? handler->mime_type
                                        : "text/html");
    response->set_status(response, 200);
    response->set_mime_type(response, &mime);
    cef_string_clear(&mime);
  }
  if (response_length != NULL) {
    *response_length = (int64_t)handler->len;
  }
}

static int CEF_CALLBACK proton_engine_resource_read(
    cef_resource_handler_t *self,
    void *data_out,
    int bytes_to_read,
    int *bytes_read,
    cef_resource_read_callback_t *callback) {
  (void)callback;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (handler == NULL || data_out == NULL || bytes_read == NULL ||
      bytes_to_read <= 0) {
    return 0;
  }
  size_t remaining = handler->offset < handler->len
                         ? handler->len - handler->offset
                         : 0;
  if (remaining == 0) {
    *bytes_read = 0;
    return 0;
  }
  size_t to_copy = remaining < (size_t)bytes_to_read ? remaining
                                                     : (size_t)bytes_to_read;
  memcpy(data_out, handler->data + handler->offset, to_copy);
  handler->offset += to_copy;
  *bytes_read = (int)to_copy;
  return 1;
}

static void CEF_CALLBACK proton_engine_resource_cancel(
    cef_resource_handler_t *self) {
  (void)self;
}

static int CEF_CALLBACK proton_engine_resource_handler_release(
    cef_base_ref_counted_t *base) {
  if (base == NULL) {
    return 0;
  }
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)base;
  int value = atomic_fetch_sub_explicit(&handler->refs.refs, 1,
                                        memory_order_acq_rel) -
              1;
  if (value <= 0) {
    free(handler->data);
    free(handler->mime_type);
    free(handler);
    return 1;
  }
  return 0;
}

static cef_resource_handler_t *proton_engine_resource_handler_create(
    const char *data,
    size_t data_len,
    const char *mime_type) {
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)calloc(1, sizeof(*handler));
  if (handler == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&handler->handler.base,
      sizeof(handler->handler), &handler->refs);
  handler->handler.base.release = proton_engine_resource_handler_release;
  handler->data = (char *)malloc(data_len + 1);
  if (handler->data == NULL) {
    free(handler);
    return NULL;
  }
  memcpy(handler->data, data != NULL ? data : "", data_len);
  handler->data[data_len] = '\0';
  handler->len = data_len;
  handler->mime_type = proton_engine_strdup(mime_type != NULL ? mime_type
                                                              : "text/html");
  if (handler->mime_type == NULL) {
    free(handler->data);
    free(handler);
    return NULL;
  }
  handler->handler.open = proton_engine_resource_open;
  handler->handler.get_response_headers =
      proton_engine_resource_get_response_headers;
  handler->handler.read = proton_engine_resource_read;
  handler->handler.cancel = proton_engine_resource_cancel;
  return &handler->handler;
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
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window == NULL) {
    return NULL;
  }
  char *url = proton_engine_request_url(request);
  cef_resource_handler_t *handler = NULL;
  if (url != NULL && window->html_url != NULL &&
      strcmp(window->html_url, url) == 0 && window->html != NULL) {
    handler = proton_engine_resource_handler_create(window->html,
                                                    window->html_len,
                                                    "text/html");
  } else {
    char *asset_path = proton_engine_url_to_asset_path(url);
    if (asset_path != NULL) {
      char *html_path = proton_engine_url_to_asset_path(window->html_url);
      char *asset_root = proton_engine_asset_path_dirname(html_path);
      if (proton_engine_asset_path_is_under_root(asset_path, asset_root)) {
        char *data = NULL;
        size_t data_len = 0;
        if (proton_engine_read_asset_file(asset_path, &data, &data_len)) {
          handler = proton_engine_resource_handler_create(
              data, data_len, proton_engine_asset_mime_type(asset_path));
          free(data);
        }
      }
      free(asset_root);
      free(html_path);
      free(asset_path);
    }
  }
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
      registrar, &scheme,
      CEF_SCHEME_OPTION_SECURE | CEF_SCHEME_OPTION_FETCH_ENABLED);
  cef_string_clear(&scheme);
}

static void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
  cef_command_line_t *command_line) {
  (void)self;
  (void)process_type;
  proton_engine_append_switch(command_line, "disable-gpu");
  proton_engine_append_switch(command_line, "in-process-gpu");
  proton_engine_append_switch(command_line, "disable-background-networking");
  proton_engine_append_switch(command_line, "disable-component-update");
  proton_engine_append_switch(command_line, "disable-domain-reliability");
  proton_engine_append_switch(command_line, "disable-sync");
  proton_engine_append_switch(command_line, "metrics-recording-only");
  proton_engine_append_switch(command_line, "safebrowsing-disable-auto-update");
  proton_engine_append_switch(command_line, "use-mock-keychain");
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
  return &g_browser_process_handler.handler;
}

static void proton_engine_window_mark_closed(proton_engine_window_t *window);
static void proton_engine_overlay_update_input_shape(
    proton_engine_window_t *window);

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

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL) {
    proton_engine_debug_log("browser_before_close browser=%d",
                            window->browser_id);
    proton_engine_window_mark_closed(window);
    if (window->window != NULL) {
      gtk_widget_destroy(window->window);
    }
    if (window->destroy_requested) {
      proton_engine_window_defer_free(window);
    }
  }
}

static cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self) {
  (void)self;
  return &g_life_span_handler.handler;
}

static cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self) {
  (void)self;
  return &g_load_handler.handler;
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
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
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
                 SIZE_MAX / sizeof(proton_linux_titlebar_region_t)) {
    proton_linux_titlebar_region_t *copy =
        (proton_linux_titlebar_region_t *)malloc(regions_count * sizeof(*copy));
    if (copy == NULL) {
      proton_engine_debug_log("draggable_regions_allocation_failed count=%zu",
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
  proton_engine_debug_log("draggable_regions browser=%d count=%zu",
                          window->browser_id,
                          window->draggable_region_count);
  proton_engine_overlay_update_input_shape(window);
}

static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self) {
  (void)self;
  return &g_drag_handler.handler;
}

static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self) {
  (void)self;
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
      (cef_base_ref_counted_t *)&g_drag_handler.handler.base,
      sizeof(g_drag_handler.handler), &g_drag_handler.refs);
  g_drag_handler.handler.on_draggable_regions_changed =
      proton_engine_on_draggable_regions_changed;

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
}

static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode) {
  (void)self;
  (void)httpStatusCode;
  if (frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  char *url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  if (window != NULL && window->bridge_config_json != NULL && url != NULL &&
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
  client->client.get_drag_handler = proton_engine_client_get_drag_handler;
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
  char titlebar_style[32] = {0};
  if (proton_engine_parse_json_string_field(config_json, "titlebar_style",
                                            titlebar_style,
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
  return PROTON_OK;
}

static void proton_engine_browser_release(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
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
  if (window->browser != NULL) {
    proton_engine_browser_release(window->browser);
    window->browser = NULL;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static gboolean proton_engine_on_window_delete(GtkWidget *widget,
                                               GdkEvent *event,
                                               gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->closed) {
    return FALSE;
  }
  if (window->closing) {
    return FALSE;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      int allow_close = 0;
      if (host->is_ready_to_be_closed != NULL &&
          host->is_ready_to_be_closed(host)) {
        allow_close = 1;
        window->closing = 1;
      } else if (host->try_close_browser != NULL) {
        allow_close = host->try_close_browser(host);
        if (allow_close) {
          window->closing = 1;
        }
      } else {
        host->close_browser(host, 0);
      }
      proton_engine_debug_log("window_delete_close browser=%d allow=%d",
                              window->browser_id, allow_close);
      host->base.release((cef_base_ref_counted_t *)host);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
      return allow_close ? FALSE : TRUE;
    }
  }
  proton_engine_window_mark_closed(window);
  return FALSE;
}

static void proton_engine_on_window_destroy(GtkWidget *widget,
                                            gpointer user_data) {
  (void)widget;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL) {
    window->window = NULL;
    window->browser_host = NULL;
    window->overlay_controls = NULL;
    proton_engine_overlay_release_input_windows(window);
  }
  if (window != NULL && !window->closed) {
    if (window->browser == NULL) {
      proton_engine_window_mark_closed(window);
    }
  }
}

static int proton_engine_window_is_maximized(proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL ||
      gtk_widget_get_window(window->window) == NULL) {
    return 0;
  }
  return (gdk_window_get_state(gtk_widget_get_window(window->window)) &
          GDK_WINDOW_STATE_MAXIMIZED) != 0;
}

static void proton_engine_overlay_update_maximize_button(
    proton_engine_window_t *window) {
  if (window == NULL || window->maximize_image == NULL ||
      window->maximize_button == NULL) {
    return;
  }
  const int maximized = proton_engine_window_is_maximized(window);
  gtk_image_set_from_icon_name(
      GTK_IMAGE(window->maximize_image),
      maximized ? "window-restore-symbolic" : "window-maximize-symbolic",
      GTK_ICON_SIZE_MENU);
  gtk_widget_set_tooltip_text(window->maximize_button,
                              maximized ? "Restore" : "Maximize");
}

static void proton_engine_overlay_toggle_maximize(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL) {
    return;
  }
  if (proton_engine_window_is_maximized(window)) {
    gtk_window_unmaximize(GTK_WINDOW(window->window));
  } else {
    gtk_window_maximize(GTK_WINDOW(window->window));
  }
}

static void proton_engine_overlay_minimize(GtkButton *button,
                                           gpointer user_data) {
  (void)button;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL && window->window != NULL) {
    gtk_window_iconify(GTK_WINDOW(window->window));
  }
}

static void proton_engine_overlay_maximize(GtkButton *button,
                                           gpointer user_data) {
  (void)button;
  proton_engine_overlay_toggle_maximize(
      (proton_engine_window_t *)user_data);
}

static void proton_engine_overlay_close(GtkButton *button,
                                        gpointer user_data) {
  (void)button;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL && window->window != NULL) {
    gtk_window_close(GTK_WINDOW(window->window));
  }
}

static gboolean proton_engine_overlay_window_state(
    GtkWidget *widget,
    GdkEventWindowState *event,
    gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_overlay_update_maximize_button(
      (proton_engine_window_t *)user_data);
  proton_engine_overlay_update_input_shape(
      (proton_engine_window_t *)user_data);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return FALSE;
}

static int proton_engine_overlay_resize_handle(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == NULL) {
    return 0;
  }
  int themed_handle = 0;
  gtk_widget_style_get(window->window, "decoration-resize-handle",
                       &themed_handle, NULL);
  return themed_handle > 1 ? (themed_handle + 1) / 2 : themed_handle;
}

static void proton_engine_overlay_region_union(
    cairo_region_t *region,
    proton_linux_titlebar_rect_t rect) {
  if (region == NULL || rect.width <= 0 || rect.height <= 0) {
    return;
  }
  cairo_rectangle_int_t cairo_rect = {
      .x = rect.x,
      .y = rect.y,
      .width = rect.width,
      .height = rect.height,
  };
  cairo_region_union_rectangle(region, &cairo_rect);
}

static void proton_engine_overlay_region_subtract(
    cairo_region_t *region,
    proton_linux_titlebar_rect_t rect) {
  if (region == NULL || rect.width <= 0 || rect.height <= 0) {
    return;
  }
  cairo_rectangle_int_t cairo_rect = {
      .x = rect.x,
      .y = rect.y,
      .width = rect.width,
      .height = rect.height,
  };
  cairo_region_subtract_rectangle(region, &cairo_rect);
}

static void proton_engine_overlay_update_input_shape(
    proton_engine_window_t *window) {
  if (window == NULL || !window->titlebar_overlay ||
      window->window == NULL || window->browser_host == NULL) {
    return;
  }
  const int width = gtk_widget_get_allocated_width(window->browser_host);
  const int height = gtk_widget_get_allocated_height(window->browser_host);
  if (width <= 0 || height <= 0) {
    return;
  }

  cairo_region_t *region = cairo_region_create();
  if (region == NULL) {
    return;
  }
  const int resize_handle = proton_engine_overlay_resize_handle(window);
  if (!proton_engine_window_is_maximized(window) && resize_handle > 0) {
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, 0, width, resize_handle});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, height - resize_handle,
                                               width, resize_handle});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){0, 0, resize_handle, height});
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){width - resize_handle, 0,
                                               resize_handle, height});
  }

  if (window->draggable_regions_reported) {
    for (size_t i = 0; i < window->draggable_region_count; i++) {
      if (!window->draggable_regions[i].draggable) {
        continue;
      }
      proton_engine_overlay_region_union(
          region,
          (proton_linux_titlebar_rect_t){
              window->draggable_regions[i].x,
              window->draggable_regions[i].y,
              window->draggable_regions[i].width,
              window->draggable_regions[i].height,
          });
    }
    for (size_t i = 0; i < window->draggable_region_count; i++) {
      if (window->draggable_regions[i].draggable) {
        continue;
      }
      proton_engine_overlay_region_subtract(
          region,
          (proton_linux_titlebar_rect_t){
              window->draggable_regions[i].x,
              window->draggable_regions[i].y,
              window->draggable_regions[i].width,
              window->draggable_regions[i].height,
          });
    }
  } else {
    const int fallback_width =
        window->minimize_button != NULL
            ? gtk_widget_get_allocated_width(window->minimize_button)
            : 0;
    const int controls_height =
        window->overlay_controls != NULL
            ? gtk_widget_get_allocated_height(window->overlay_controls)
            : 0;
    const int fallback_height =
        controls_height > resize_handle ? controls_height - resize_handle
                                        : controls_height;
    proton_engine_overlay_region_union(
        region, (proton_linux_titlebar_rect_t){
                    resize_handle,
                    resize_handle,
                    fallback_width,
                    fallback_height,
                });
  }

  if (window->overlay_controls != NULL) {
    int controls_x = 0;
    int controls_y = 0;
    if (gtk_widget_translate_coordinates(window->overlay_controls,
                                         window->browser_host, 0, 0,
                                         &controls_x, &controls_y)) {
      proton_engine_overlay_region_subtract(
          region, (proton_linux_titlebar_rect_t){
                      controls_x,
                      controls_y,
                      gtk_widget_get_allocated_width(window->overlay_controls),
                      gtk_widget_get_allocated_height(
                          window->overlay_controls),
                  });
    }
  }

  cairo_rectangle_int_t bounds = {0, 0, width, height};
  cairo_region_intersect_rectangle(region, &bounds);
  GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
  if (top_gdk_window == NULL || !GDK_IS_X11_WINDOW(top_gdk_window)) {
    cairo_region_destroy(region);
    return;
  }
  GdkDisplay *gdk_display = gdk_window_get_display(top_gdk_window);
  Display *display = GDK_WINDOW_XDISPLAY(top_gdk_window);
  const Window parent = GDK_WINDOW_XID(top_gdk_window);
  XWindowAttributes parent_attributes;
  if (!XGetWindowAttributes(display, parent, &parent_attributes) ||
      parent_attributes.width <= 0 || parent_attributes.height <= 0) {
    cairo_region_destroy(region);
    return;
  }
  const unsigned int device_width = (unsigned int)parent_attributes.width;
  const unsigned int device_height = (unsigned int)parent_attributes.height;

  gdk_x11_display_error_trap_push(gdk_display);
  if (window->overlay_input_window == NULL) {
    XSetWindowAttributes attributes = {
        .event_mask = ButtonPressMask,
    };
    const Window input_window = XCreateWindow(
        display, parent, 0, 0, device_width, device_height, 0, 0, InputOnly,
        CopyFromParent, CWEventMask, &attributes);
    window->overlay_input_window = gdk_x11_window_foreign_new_for_display(
        gdk_display, input_window);
    if (window->overlay_input_window == NULL) {
      XDestroyWindow(display, input_window);
    } else {
      gdk_window_add_filter(window->overlay_input_window,
                            proton_engine_x11_event_filter, NULL);
      gdk_window_set_events(window->overlay_input_window,
                            GDK_BUTTON_PRESS_MASK);
      XWindowAttributes input_attributes;
      if (XGetWindowAttributes(display, input_window, &input_attributes)) {
        XSelectInput(display, input_window,
                     input_attributes.your_event_mask | ButtonPressMask);
      }
    }
  }
  if (window->overlay_input_window != NULL) {
    const Window input_window = GDK_WINDOW_XID(window->overlay_input_window);
    XMoveResizeWindow(display, input_window, 0, 0, device_width,
                      device_height);
    gdk_window_input_shape_combine_region(window->overlay_input_window, region,
                                          0, 0);
    XMapRaised(display, input_window);
  }
  XSync(display, False);
  const int x11_error = gdk_x11_display_error_trap_pop(gdk_display);
  if (x11_error != 0) {
    proton_engine_debug_log("overlay_input_update_failed x11_error=%d",
                            x11_error);
  }
  cairo_region_destroy(region);
}

static GtkWidget *proton_engine_overlay_button(
    const char *icon_name,
    const char *tooltip,
    const char *style_class,
    GCallback callback,
    proton_engine_window_t *window,
    GtkWidget **out_image) {
  GtkWidget *button = gtk_button_new();
  GtkWidget *image =
      gtk_image_new_from_icon_name(icon_name, GTK_ICON_SIZE_MENU);
  if (button == NULL || image == NULL) {
    if (button != NULL) {
      gtk_widget_destroy(button);
    }
    return NULL;
  }
  gtk_button_set_image(GTK_BUTTON(button), image);
  gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(button, FALSE);
  gtk_widget_set_tooltip_text(button, tooltip);
  GtkStyleContext *context = gtk_widget_get_style_context(button);
  gtk_style_context_add_class(context, GTK_STYLE_CLASS_FLAT);
  gtk_style_context_add_class(context, "titlebutton");
  gtk_style_context_add_class(context, style_class);
  g_signal_connect(button, "clicked", callback, window);
  if (out_image != NULL) {
    *out_image = image;
  }
  return button;
}

static int proton_engine_overlay_create_controls(
    proton_engine_window_t *window) {
  if (window == NULL || window->overlay == NULL) {
    return 0;
  }
  GtkWidget *event_box = gtk_event_box_new();
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  if (event_box == NULL || box == NULL) {
    if (event_box != NULL) {
      gtk_widget_destroy(event_box);
    }
    if (box != NULL) {
      gtk_widget_destroy(box);
    }
    return 0;
  }

  window->minimize_button = proton_engine_overlay_button(
      "window-minimize-symbolic", "Minimize", "minimize",
      G_CALLBACK(proton_engine_overlay_minimize), window, NULL);
  window->maximize_button = proton_engine_overlay_button(
      "window-maximize-symbolic", "Maximize", "maximize",
      G_CALLBACK(proton_engine_overlay_maximize), window,
      &window->maximize_image);
  window->close_button = proton_engine_overlay_button(
      "window-close-symbolic", "Close", "close",
      G_CALLBACK(proton_engine_overlay_close), window, NULL);
  if (window->minimize_button == NULL || window->maximize_button == NULL ||
      window->close_button == NULL) {
    gtk_widget_destroy(event_box);
    return 0;
  }

  gtk_box_pack_start(GTK_BOX(box), window->minimize_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), window->maximize_button, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), window->close_button, FALSE, FALSE, 0);
  gtk_container_add(GTK_CONTAINER(event_box), box);
  gtk_event_box_set_visible_window(GTK_EVENT_BOX(event_box), TRUE);
  gtk_widget_set_app_paintable(event_box, TRUE);
  GdkScreen *screen = gtk_widget_get_screen(window->window);
  GdkVisual *rgba_visual =
      screen != NULL ? gdk_screen_get_rgba_visual(screen) : NULL;
  if (rgba_visual != NULL) {
    gtk_widget_set_visual(event_box, rgba_visual);
  }
  gtk_widget_set_name(event_box, "proton-overlay-controls");
  GtkCssProvider *provider = gtk_css_provider_new();
  if (provider != NULL) {
    gtk_css_provider_load_from_data(
        provider,
        "#proton-overlay-controls { background-color: transparent; "
        "background-image: none; }"
        "button { background-color: transparent; background-image: none; "
        "border-color: transparent; box-shadow: none; }"
        "button:hover { background-color: alpha(@theme_fg_color, 0.08); }"
        "button:active { background-color: alpha(@theme_fg_color, 0.14); }"
        "button.close:hover { background-color: #e81123; color: white; }"
        "button.close:active { background-color: #c50f1f; color: white; }",
        -1, NULL);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(event_box), GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->minimize_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->maximize_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(window->close_button),
        GTK_STYLE_PROVIDER(provider), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
  }
  gtk_widget_set_halign(event_box, GTK_ALIGN_END);
  gtk_widget_set_valign(event_box, GTK_ALIGN_START);
  const int resize_handle = proton_engine_overlay_resize_handle(window);
  gtk_widget_set_margin_top(
      event_box, proton_linux_titlebar_control_margin(resize_handle));
  gtk_widget_set_margin_end(event_box, resize_handle);
  gtk_overlay_add_overlay(GTK_OVERLAY(window->overlay), event_box);
  gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(window->overlay), event_box,
                                       FALSE);
  window->overlay_controls = event_box;
  return 1;
}

static int proton_engine_x11_window_is_descendant(Display *display,
                                                   Window child,
                                                   Window ancestor) {
  if (display == NULL || child == None || ancestor == None) {
    return 0;
  }
  Window current = child;
  while (current != None) {
    if (current == ancestor) {
      return 1;
    }
    Window root = None;
    Window parent = None;
    Window *children = NULL;
    unsigned int child_count = 0;
    if (!XQueryTree(display, current, &root, &parent, &children,
                    &child_count)) {
      return 0;
    }
    if (children != NULL) {
      XFree(children);
    }
    if (parent == None || parent == current) {
      return 0;
    }
    current = parent;
  }
  return 0;
}

static int proton_engine_overlay_resize_direction(
    proton_linux_titlebar_hit_t hit) {
  switch (hit) {
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_TOP_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH:
    return PROTON_X11_MOVERESIZE_SIZE_TOP;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_TOP_RIGHT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_RIGHT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM_LEFT;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM;
  case PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST:
    return PROTON_X11_MOVERESIZE_SIZE_BOTTOM_RIGHT;
  default:
    return PROTON_X11_MOVERESIZE_SIZE_TOP;
  }
}

static int proton_engine_overlay_is_resize_hit(
    proton_linux_titlebar_hit_t hit) {
  return hit >= PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST &&
         hit <= PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST;
}

static void proton_engine_overlay_begin_moveresize(
    proton_engine_window_t *window,
    const XButtonEvent *event,
    int direction) {
  if (window == NULL || window->window == NULL || event == NULL ||
      event->display == NULL) {
    return;
  }
  GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
  if (top_gdk_window == NULL) {
    return;
  }
  const Atom moveresize =
      XInternAtom(event->display, "_NET_WM_MOVERESIZE", False);
  if (moveresize == None) {
    return;
  }
  XEvent message;
  memset(&message, 0, sizeof(message));
  message.xclient.type = ClientMessage;
  message.xclient.display = event->display;
  message.xclient.window = GDK_WINDOW_XID(top_gdk_window);
  message.xclient.message_type = moveresize;
  message.xclient.format = 32;
  message.xclient.data.l[0] = event->x_root;
  message.xclient.data.l[1] = event->y_root;
  message.xclient.data.l[2] = direction;
  message.xclient.data.l[3] = Button1;
  message.xclient.data.l[4] = 1;
  XUngrabPointer(event->display, event->time);
  if (!XSendEvent(event->display, event->root, False,
                  SubstructureRedirectMask | SubstructureNotifyMask,
                  &message)) {
    proton_engine_debug_log("overlay_moveresize_send_failed direction=%d",
                            direction);
  } else {
    proton_engine_debug_log("overlay_moveresize direction=%d", direction);
  }
  XFlush(event->display);
}

static proton_linux_titlebar_hit_t proton_engine_overlay_hit_test(
    proton_engine_window_t *window,
    Display *display,
    Window root,
    int root_x,
    int root_y) {
  if (window == NULL || window->browser_host == NULL || display == NULL) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  GdkWindow *browser_gdk_window = gtk_widget_get_window(window->browser_host);
  if (browser_gdk_window == NULL) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const Window browser_xid = GDK_WINDOW_XID(browser_gdk_window);
  int device_x = 0;
  int device_y = 0;
  Window child = None;
  if (!XTranslateCoordinates(display, root, browser_xid, root_x, root_y,
                             &device_x, &device_y, &child)) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  XWindowAttributes attributes;
  if (!XGetWindowAttributes(display, browser_xid, &attributes)) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const int logical_width = gtk_widget_get_allocated_width(window->browser_host);
  const int logical_height =
      gtk_widget_get_allocated_height(window->browser_host);
  proton_linux_titlebar_point_t point = {
      .x = proton_linux_titlebar_device_to_logical(
          device_x, attributes.width, logical_width),
      .y = proton_linux_titlebar_device_to_logical(
          device_y, attributes.height, logical_height),
  };

  proton_linux_titlebar_rect_t controls = {0};
  if (window->overlay_controls != NULL) {
    int controls_x = 0;
    int controls_y = 0;
    if (gtk_widget_translate_coordinates(window->overlay_controls,
                                         window->browser_host, 0, 0,
                                         &controls_x, &controls_y)) {
      controls.x = controls_x;
      controls.y = controls_y;
      controls.width =
          gtk_widget_get_allocated_width(window->overlay_controls);
      controls.height =
          gtk_widget_get_allocated_height(window->overlay_controls);
    }
  }

  const int resize_handle = proton_engine_overlay_resize_handle(window);
  const int fallback_width =
      window->minimize_button != NULL
          ? gtk_widget_get_allocated_width(window->minimize_button)
          : 0;
  proton_linux_titlebar_hit_test_input_t input = {
      .point = point,
      .width = logical_width,
      .height = logical_height,
      .resize_handle = resize_handle,
      .maximized = proton_engine_window_is_maximized(window),
      .controls = controls,
      .fallback_drag =
          {
              .x = resize_handle,
              .y = resize_handle,
              .width = fallback_width,
              .height =
                  controls.height > resize_handle
                      ? controls.height - resize_handle
                      : controls.height,
          },
      .draggable_regions_reported = window->draggable_regions_reported,
      .draggable_region_count = window->draggable_region_count,
      .draggable_regions = window->draggable_regions,
  };
  return proton_linux_titlebar_hit_test(&input);
}

static int proton_engine_overlay_is_double_click(
    proton_engine_window_t *window,
    const XButtonEvent *event) {
  if (window == NULL || event == NULL || window->last_drag_click_time == 0) {
    return 0;
  }
  GtkSettings *settings = gtk_settings_get_default();
  gint double_click_time = 0;
  gint double_click_distance = 0;
  if (settings != NULL) {
    g_object_get(settings, "gtk-double-click-time", &double_click_time,
                 "gtk-double-click-distance", &double_click_distance, NULL);
  }
  const guint32 elapsed = event->time - window->last_drag_click_time;
  return double_click_time > 0 && elapsed <= (guint32)double_click_time &&
         abs(event->x_root - window->last_drag_click_x) <=
             double_click_distance &&
         abs(event->y_root - window->last_drag_click_y) <=
             double_click_distance;
}

static GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                                       GdkEvent *event,
                                                       gpointer user_data) {
  (void)event;
  (void)user_data;
  XEvent *native_event = (XEvent *)xevent;
  if (native_event == NULL || native_event->type != ButtonPress ||
      native_event->xbutton.button != Button1) {
    return GDK_FILTER_CONTINUE;
  }
  Display *display = native_event->xbutton.display;
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (!window->titlebar_overlay || window->window == NULL) {
      continue;
    }
    GdkWindow *top_gdk_window = gtk_widget_get_window(window->window);
    if (top_gdk_window == NULL ||
        !proton_engine_x11_window_is_descendant(
            display, native_event->xbutton.window,
            GDK_WINDOW_XID(top_gdk_window))) {
      continue;
    }
    proton_linux_titlebar_hit_t hit = proton_engine_overlay_hit_test(
        window, display, native_event->xbutton.root,
        native_event->xbutton.x_root, native_event->xbutton.y_root);
    if (proton_engine_overlay_is_resize_hit(hit)) {
      proton_engine_overlay_begin_moveresize(
          window, &native_event->xbutton,
          proton_engine_overlay_resize_direction(hit));
      return GDK_FILTER_REMOVE;
    }
    if (hit != PROTON_LINUX_TITLEBAR_HIT_DRAG) {
      return GDK_FILTER_CONTINUE;
    }
    if (proton_engine_overlay_is_double_click(window,
                                              &native_event->xbutton)) {
      window->last_drag_click_time = 0;
      proton_engine_overlay_toggle_maximize(window);
      return GDK_FILTER_REMOVE;
    }
    window->last_drag_click_time = native_event->xbutton.time;
    window->last_drag_click_x = native_event->xbutton.x_root;
    window->last_drag_click_y = native_event->xbutton.y_root;
    proton_engine_overlay_begin_moveresize(
        window, &native_event->xbutton, PROTON_X11_MOVERESIZE_MOVE);
    return GDK_FILTER_REMOVE;
  }
  return GDK_FILTER_CONTINUE;
}

static void proton_engine_sync_browser_bounds(proton_engine_window_t *window) {
  if (window == NULL || window->browser == NULL ||
      window->browser_host == NULL) {
    return;
  }
  GdkWindow *parent_gdk_window = gtk_widget_get_window(window->browser_host);
  if (parent_gdk_window == NULL) {
    return;
  }
  Display *display = GDK_WINDOW_XDISPLAY(parent_gdk_window);
  XWindowAttributes attributes;
  if (display == NULL ||
      !XGetWindowAttributes(display, GDK_WINDOW_XID(parent_gdk_window),
                            &attributes) ||
      attributes.width <= 0 || attributes.height <= 0) {
    return;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    return;
  }
  const cef_window_handle_t browser_handle = host->get_window_handle(host);
  if (browser_handle != 0) {
    GdkDisplay *gdk_display = gdk_window_get_display(parent_gdk_window);
    XWindowAttributes browser_attributes;
    gdk_x11_display_error_trap_push(gdk_display);
    const int browser_window_valid =
        XGetWindowAttributes(display, (Window)browser_handle,
                             &browser_attributes) != 0;
    if (browser_window_valid) {
      XMoveResizeWindow(display, (Window)browser_handle, 0, 0,
                        (unsigned int)attributes.width,
                        (unsigned int)attributes.height);
    }
    XSync(display, False);
    const int x11_error = gdk_x11_display_error_trap_pop(gdk_display);
    if (!browser_window_valid || x11_error != 0) {
      proton_engine_debug_log(
          "browser_bounds_deferred handle=%lu valid=%d x11_error=%d",
          (unsigned long)browser_handle, browser_window_valid, x11_error);
    }
  }
  if (host->was_resized != NULL) {
    host->was_resized(host);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  if (window->overlay_controls != NULL) {
    GdkWindow *controls_window =
        gtk_widget_get_window(window->overlay_controls);
    if (controls_window != NULL) {
      gdk_window_raise(controls_window);
    }
  }
}

static void proton_engine_browser_host_size_allocate(GtkWidget *widget,
                                                      GtkAllocation *allocation,
                                                      gpointer user_data) {
  (void)widget;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || allocation == NULL) {
    return;
  }
  window->width = allocation->width;
  window->height = allocation->height;
  proton_engine_overlay_update_input_shape(window);
  proton_engine_sync_browser_bounds(window);
}

static gboolean proton_engine_window_configure(GtkWidget *widget,
                                               GdkEventConfigure *event,
                                               gpointer user_data) {
  (void)widget;
  (void)event;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  proton_engine_sync_browser_bounds(window);
  if (window != NULL && window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      if (host->notify_move_or_resize_started != NULL) {
        host->notify_move_or_resize_started(host);
      }
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return FALSE;
}

static void proton_engine_use_default_x11_visual(GtkWidget *widget) {
  if (widget == NULL) {
    return;
  }
  GdkScreen *screen = gtk_widget_get_screen(widget);
  if (screen == NULL || !GDK_IS_X11_SCREEN(screen)) {
    return;
  }
  Display *display = GDK_SCREEN_XDISPLAY(screen);
  Visual *default_visual =
      DefaultVisual(display, GDK_SCREEN_XNUMBER(screen));
  if (default_visual == NULL) {
    return;
  }
  GList *visuals = gdk_screen_list_visuals(screen);
  for (GList *cursor = visuals; cursor != NULL; cursor = cursor->next) {
    GdkVisual *visual = GDK_VISUAL(cursor->data);
    Visual *xvisual = gdk_x11_visual_get_xvisual(visual);
    if (xvisual != NULL && xvisual->visualid == default_visual->visualid) {
      gtk_widget_set_visual(widget, visual);
      break;
    }
  }
  g_list_free(visuals);
}

static int proton_engine_ensure_gtk(char *error, size_t error_len) {
  static int initialized = 0;
  static int available = 0;
  if (initialized) {
    if (!available) {
      proton_engine_set_message(error, error_len,
                                "GTK X11 initialization failed");
    }
    return available;
  }
  int argc = 0;
  char **argv = NULL;
  g_setenv("GDK_BACKEND", "x11", TRUE);
  gdk_set_allowed_backends("x11");
  available = gtk_init_check(&argc, &argv) ? 1 : 0;
  if (available) {
    GdkDisplay *display = gdk_display_get_default();
    if (display == NULL || !GDK_IS_X11_DISPLAY(display)) {
      available = 0;
    }
  }
  initialized = 1;
  if (!available) {
    proton_engine_set_message(error, error_len,
                              "GTK X11 initialization failed");
  }
  return available;
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    proton_engine_debug_log("cef_shutdown_start");
    cef_shutdown();
    g_proton_cef_initialized = 0;
    proton_engine_debug_log("cef_shutdown_done");
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

typedef struct {
  int argc;
  char **argv;
  char *storage;
} proton_engine_main_args_t;

static int proton_engine_read_proc_cmdline(proton_engine_main_args_t *out) {
  if (out == NULL) {
    return 0;
  }
  memset(out, 0, sizeof(*out));
  FILE *file = fopen("/proc/self/cmdline", "rb");
  if (file == NULL) {
    return 0;
  }
  size_t capacity = 4096;
  char *storage = (char *)malloc(capacity);
  if (storage == NULL) {
    fclose(file);
    return 0;
  }
  size_t len = 0;
  for (;;) {
    if (len == capacity) {
      size_t next_capacity = capacity * 2;
      char *next = (char *)realloc(storage, next_capacity);
      if (next == NULL) {
        free(storage);
        fclose(file);
        return 0;
      }
      storage = next;
      capacity = next_capacity;
    }
    size_t read_count = fread(storage + len, 1, capacity - len, file);
    len += read_count;
    if (read_count == 0) {
      break;
    }
  }
  fclose(file);
  if (len == 0) {
    free(storage);
    return 0;
  }
  if (storage[len - 1] != '\0') {
    if (len == capacity) {
      char *next = (char *)realloc(storage, capacity + 1);
      if (next == NULL) {
        free(storage);
        return 0;
      }
      storage = next;
    }
    storage[len++] = '\0';
  }
  int argc = 0;
  for (size_t i = 0; i < len; i++) {
    if (storage[i] == '\0') {
      argc++;
    }
  }
  char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
  if (argv == NULL) {
    free(storage);
    return 0;
  }
  int index = 0;
  char *cursor = storage;
  for (size_t i = 0; i < len && index < argc; i++) {
    if (storage[i] == '\0') {
      argv[index++] = cursor;
      cursor = storage + i + 1;
    }
  }
  out->argc = argc;
  out->argv = argv;
  out->storage = storage;
  return 1;
}

static void proton_engine_free_main_args(proton_engine_main_args_t *args) {
  if (args == NULL) {
    return;
  }
  free(args->argv);
  free(args->storage);
  args->argc = 0;
  args->argv = NULL;
  args->storage = NULL;
}

static void proton_engine_init_main_args(cef_main_args_t *cef_args,
                                         proton_engine_main_args_t *args) {
  if (cef_args == NULL || args == NULL) {
    return;
  }
  memset(cef_args, 0, sizeof(*cef_args));
  if (proton_engine_read_proc_cmdline(args)) {
    cef_args->argc = args->argc;
    cef_args->argv = args->argv;
  }
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
  proton_engine_check_cef_api_hash();
  cef_main_args_t args;
  proton_engine_main_args_t main_args;
  proton_engine_init_main_args(&args, &main_args);
  proton_engine_init_handlers();
  int exit_code = cef_execute_process(&args, &g_app.app, NULL);
  proton_engine_free_main_args(&main_args);
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

  if (!proton_engine_ensure_gtk(error, error_len)) {
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_init_handlers();
  proton_engine_check_cef_api_hash();

  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(*runtime));
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate runtime state");
    return PROTON_ERR_ENGINE;
  }
  runtime->wake_read_fd = -1;
  runtime->wake_write_fd = -1;
  runtime->owns_cef_runtime = 1;
  runtime->next_bridge_request_id = 1;
  if (pthread_mutex_init(&runtime->bridge_lock, NULL) == 0) {
    runtime->bridge_lock_initialized = 1;
  }
  if (!proton_engine_setup_wait_source(runtime, error, error_len)) {
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
    }
    free(runtime);
    return PROTON_ERR_PLATFORM;
  }
  g_active_runtime = runtime;

  cef_main_args_t args;
  proton_engine_main_args_t main_args;
  cef_settings_t settings;
  proton_engine_init_main_args(&args, &main_args);
  memset(&settings, 0, sizeof(settings));
  settings.size = sizeof(settings);
  settings.no_sandbox = 1;
  settings.multi_threaded_message_loop = 0;
  settings.external_message_pump = 1;
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  settings.remote_debugging_port = config.remote_debugging_port;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  if (config.cache_dir[0] != '\0') {
    proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  }

  if (!cef_initialize(&args, &settings, &g_app.app, NULL)) {
    cef_string_clear(&settings.browser_subprocess_path);
    cef_string_clear(&settings.resources_dir_path);
    cef_string_clear(&settings.locales_dir_path);
    cef_string_clear(&settings.root_cache_path);
    proton_engine_free_main_args(&main_args);
    proton_engine_close_wake_pipe(runtime);
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
      runtime->bridge_lock_initialized = 0;
    }
    free(runtime);
    g_active_runtime = NULL;
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_debug_log("runtime_create remote_debugging_port=%d",
                          config.remote_debugging_port);

  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.root_cache_path);
  proton_engine_free_main_args(&main_args);
  g_proton_cef_initialized = 1;
  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    proton_engine_close_wake_pipe(runtime);
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
      runtime->bridge_lock_initialized = 0;
    }
    free(runtime);
    g_active_runtime = NULL;
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

static int proton_engine_runtime_has_windows(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->runtime == runtime) {
      return 1;
    }
  }
  return 0;
}

static int proton_engine_runtime_close_windows(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->runtime != runtime || window->browser == NULL) {
      continue;
    }
    window->destroy_requested = 1;
    window->closing = 1;
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }

  int iterations = 0;
  while (proton_engine_runtime_has_windows(runtime) &&
         iterations < PROTON_ENGINE_CLOSE_DRAIN_LIMIT) {
    cef_do_message_loop_work();
    while (gtk_events_pending()) {
      gtk_main_iteration_do(FALSE);
    }
    usleep(1000);
    iterations++;
  }
  proton_engine_debug_log("runtime_close_windows iterations=%d remaining=%d",
                          iterations,
                          proton_engine_runtime_has_windows(runtime));
  return !proton_engine_runtime_has_windows(runtime);
}

int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_debug_log("runtime_destroy_start owns_cef=%d",
                          runtime->owns_cef_runtime);
  if (runtime->owns_cef_runtime) {
    if (!proton_engine_runtime_close_windows(runtime)) {
      proton_engine_set_message(
          error, error_len,
          "timed out waiting for browser windows to close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_runtime_clear_bridge_queue(runtime);
    proton_engine_bridge_pending_clear_all();
    proton_engine_cef_shutdown();
    proton_engine_free_closed_windows();
    proton_engine_close_wake_pipe(runtime);
    runtime->owns_cef_runtime = 0;
  }
  if (runtime->bridge_lock_initialized) {
    pthread_mutex_destroy(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
  }
  if (g_active_runtime == runtime) {
    g_active_runtime = NULL;
  }
  g_proton_cef_runtime_active = 0;
  proton_engine_debug_log("runtime_destroy_done");
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
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
  cef_do_message_loop_work();
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
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_main_context_pending(NULL)) {
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
  int poll_result = 0;
  if (runtime->wake_read_fd >= 0) {
    struct pollfd wake_fd;
    memset(&wake_fd, 0, sizeof(wake_fd));
    wake_fd.fd = runtime->wake_read_fd;
    wake_fd.events = POLLIN;
    int poll_timeout =
        wait_timeout > (uint32_t)INT_MAX ? INT_MAX : (int)wait_timeout;
    do {
      poll_result = poll(&wake_fd, 1, poll_timeout);
    } while (poll_result < 0 && errno == EINTR);
    if (poll_result > 0 && (wake_fd.revents & POLLIN) != 0) {
      proton_engine_drain_wake_pipe(runtime);
    }
  } else if (wait_timeout > 0) {
    g_usleep((gulong)wait_timeout * 1000);
  }
  if (poll_result < 0) {
    proton_engine_set_message(error, error_len, "runtime wait failed");
    return PROTON_ERR_PLATFORM;
  }

  uint32_t signaled_mask = atomic_exchange_explicit(
      &g_wait_source_ready_mask, PROTON_WAIT_NONE, memory_order_acquire);
  ready_mask |= signaled_mask & interest_mask;
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      waiting_for_scheduled_pump && poll_result == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  ready_mask |= proton_engine_runtime_ready_mask(runtime, interest_mask);
  ready_mask &= interest_mask;
  if (ready_mask != PROTON_WAIT_NONE) {
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
  }
  *out_ready_mask = ready_mask;
  return PROTON_OK;
}

// TODO: Route the existing Linux engine wake pipe through the public async
// event-source contract.
int32_t proton_engine_runtime_set_wakeup_fd(proton_engine_runtime_t *runtime,
                                            int32_t wakeup_fd,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)wakeup_fd;
  proton_engine_set_message(error, error_len,
                            "runtime wakeup fd is not supported on Linux");
  return PROTON_ERR_UNSUPPORTED;
}

// TODO: Expose scheduled pump deadlines with the Linux async event source.
int32_t proton_engine_runtime_next_wakeup_delay_ms(
    proton_engine_runtime_t *runtime,
    int64_t *out_delay_ms,
    char *error,
    size_t error_len) {
  (void)runtime;
  if (out_delay_ms != NULL) {
    *out_delay_ms = -1;
  }
  proton_engine_set_message(error, error_len,
                            "runtime wakeup delay is not supported on Linux");
  return PROTON_ERR_UNSUPPORTED;
}

// TODO: Implement app menu rendering and command events on Linux.
int32_t proton_engine_runtime_set_menu_json(proton_engine_runtime_t *runtime,
                                            const char *menu_json,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)menu_json;
  proton_engine_set_message(error, error_len,
                            "native app menus are not implemented on Linux");
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
  if (window == NULL || window->browser_host == NULL ||
      gtk_widget_get_window(window->browser_host) == NULL) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  GdkWindow *top_gdk_window = gtk_widget_get_window(window->browser_host);
  window_info.parent_window =
      (cef_window_handle_t)GDK_WINDOW_XID(top_gdk_window);
  XWindowAttributes parent_attributes;
  memset(&parent_attributes, 0, sizeof(parent_attributes));
  Display *display = GDK_WINDOW_XDISPLAY(top_gdk_window);
  if (display != NULL) {
    (void)XGetWindowAttributes(
        display, GDK_WINDOW_XID(gtk_widget_get_window(window->browser_host)),
        &parent_attributes);
  }
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width =
      parent_attributes.width > 0 ? parent_attributes.width : window->width;
  window_info.bounds.height =
      parent_attributes.height > 0 ? parent_attributes.height : window->height;
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
      &window_info, &window->client->client, &url, &browser_settings,
      extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  proton_engine_debug_log("create_browser_returned browser=%p", window->browser);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  window->browser->base.add_ref((cef_base_ref_counted_t *)window->browser);
  window->browser_id = window->browser->get_identifier(window->browser);
  proton_engine_window_list_add(window);
  proton_engine_debug_log("create_browser id=%d initial_url=%s size=%dx%d",
                          window->browser_id,
                          initial_url != NULL ? initial_url : "",
                          window->width, window->height);
  proton_engine_sync_browser_bounds(window);
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
  window->width = config.width;
  window->height = config.height;
  window->titlebar_overlay = config.titlebar_overlay;
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

  window->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  if (window->window == NULL) {
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "window creation failed");
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_use_default_x11_visual(window->window);
  gtk_window_set_title(GTK_WINDOW(window->window),
                       config.title[0] != '\0' ? config.title : "Proton");
  gtk_window_set_default_size(GTK_WINDOW(window->window), config.width,
                              config.height);
  if (window->titlebar_overlay) {
    gtk_window_set_decorated(GTK_WINDOW(window->window), FALSE);
    gtk_window_set_resizable(GTK_WINDOW(window->window), TRUE);
    window->overlay = gtk_overlay_new();
    if (window->overlay == NULL) {
      gtk_widget_destroy(window->window);
      free(window->client);
      free(window);
      proton_engine_set_message(error, error_len,
                                "overlay container creation failed");
      return PROTON_ERR_PLATFORM;
    }
  }
  window->browser_host = gtk_drawing_area_new();
  if (window->browser_host == NULL) {
    gtk_widget_destroy(window->window);
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "browser host widget creation failed");
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_use_default_x11_visual(window->browser_host);
  if (window->titlebar_overlay) {
    gtk_container_add(GTK_CONTAINER(window->overlay), window->browser_host);
    if (!proton_engine_overlay_create_controls(window)) {
      gtk_widget_destroy(window->window);
      free(window->client);
      free(window);
      proton_engine_set_message(error, error_len,
                                "overlay window controls creation failed");
      return PROTON_ERR_PLATFORM;
    }
    gtk_container_add(GTK_CONTAINER(window->window), window->overlay);
  } else {
    gtk_container_add(GTK_CONTAINER(window->window), window->browser_host);
  }
  g_signal_connect(window->window, "delete-event",
                   G_CALLBACK(proton_engine_on_window_delete), window);
  g_signal_connect(window->window, "destroy",
                   G_CALLBACK(proton_engine_on_window_destroy), window);
  g_signal_connect(window->window, "configure-event",
                   G_CALLBACK(proton_engine_window_configure), window);
  g_signal_connect(window->browser_host, "size-allocate",
                   G_CALLBACK(proton_engine_browser_host_size_allocate),
                   window);
  if (window->titlebar_overlay) {
    g_signal_connect(window->window, "window-state-event",
                     G_CALLBACK(proton_engine_overlay_window_state), window);
  }
  gtk_widget_realize(window->window);
  gtk_widget_realize(window->browser_host);
  gtk_widget_show_all(window->window);
  if (window->titlebar_overlay) {
    proton_engine_overlay_update_maximize_button(window);
    proton_engine_overlay_update_input_shape(window);
    const int resize_handle = proton_engine_overlay_resize_handle(window);
    proton_engine_debug_log(
        "overlay_ready controls=%dx%d resize_handle=%d content=%dx%d",
        window->overlay_controls != NULL
            ? gtk_widget_get_allocated_width(window->overlay_controls)
            : 0,
        window->overlay_controls != NULL
            ? gtk_widget_get_allocated_height(window->overlay_controls)
            : 0,
        resize_handle,
        gtk_widget_get_allocated_width(window->browser_host),
        gtk_widget_get_allocated_height(window->browser_host));
  }
  proton_engine_debug_log("window_create title=%s size=%dx%d initial_url=%s",
                          config.title, config.width, config.height,
                          config.initial_url);

  status = proton_engine_window_create_browser(window, config.initial_url, error,
                                               error_len);
  if (status != PROTON_OK) {
    gtk_widget_destroy(window->window);
    free(window->client);
    free(window->bridge_config_json);
    free(window);
    return status;
  }
  *out_window = window;
  return PROTON_OK;
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  (void)error;
  (void)error_len;
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->closed && window->browser == NULL) {
    proton_engine_debug_log("window_destroy_defer_closed browser=%d",
                            window->browser_id);
    if (window->window != NULL) {
      g_signal_handlers_disconnect_by_data(window->window, window);
      gtk_widget_destroy(window->window);
      window->window = NULL;
      window->browser_host = NULL;
    }
    proton_engine_window_defer_free(window);
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    window->destroy_requested = 1;
    window->closing = 1;
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return PROTON_OK;
  }
  proton_engine_window_list_remove(window);
  window->closed = 1;
  if (window->window != NULL) {
    g_signal_handlers_disconnect_by_data(window->window, window);
    gtk_widget_destroy(window->window);
    window->window = NULL;
    window->browser_host = NULL;
  }
  proton_engine_window_free_storage(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  gtk_widget_show_all(window->window);
  gtk_window_present(GTK_WINDOW(window->window));
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  gtk_widget_hide(window->window);
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->close_browser(host, 0);
      host->base.release((cef_base_ref_counted_t *)host);
    }
  } else {
    gtk_widget_destroy(window->window);
    window->window = NULL;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  gtk_window_present(GTK_WINDOW(window->window));
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->set_focus(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  gtk_window_set_title(GTK_WINDOW(window->window), title != NULL ? title : "");
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  gtk_window_resize(GTK_WINDOW(window->window), width, height);
  window->width = width;
  window->height = height;
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      host->was_resized(host);
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
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
  cef_string_t cef_url = {0};
  proton_engine_set_string(&cef_url, url != NULL ? url : "about:blank");
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
  if (!proton_engine_url_is_proton(base_url)) {
    proton_engine_set_message(error, error_len,
                              "base_url must use the proton:// scheme");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (html == NULL) {
    html = "";
  }
  char *copy = proton_engine_strdup(html);
  char *url_copy = proton_engine_strdup(base_url);
  if (copy == NULL || url_copy == NULL) {
    free(copy);
    free(url_copy);
    proton_engine_set_message(error, error_len, "failed to copy html");
    return PROTON_ERR_ENGINE;
  }
  free(window->html_url);
  free(window->html);
  window->html_url = url_copy;
  window->html = copy;
  window->html_len = strlen(copy);
  int32_t status = proton_engine_window_load_url(
      window, base_url != NULL && base_url[0] != '\0' ? base_url
                                                      : "proton://app/",
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

// TODO: Implement non-blocking Linux dialogs. These exports are ABI stubs so
// that Linux builds can link the async-only dialog ABI while macOS remains the
// only supported async dialog backend for now.
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
                            "runtime dialogs are not implemented on Linux");
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
                            "async native dialog extension is not implemented on Linux");
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
                            "async native dialog extension is not implemented on Linux");
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
                            "async native dialog extension is not implemented on Linux");
  return PROTON_ERR_UNSUPPORTED;
}
// TODO: Drain Linux menu commands once the native menu backend is implemented.
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
