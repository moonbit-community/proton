#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include "../../proton_engine.h"
#include "../../proton_json.h"
#include "proton_linux_menu.h"
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
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
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
#include "../cef_common/bridge_response.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/document.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"
#include "../cef_common/view_events.h"

#include <gdk/gdkx.h>
#include <gtk/gtk.h>

#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
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
#define PROTON_ENGINE_MAX_MENU_COMMANDS 32
#define PROTON_ENGINE_MAX_MENU_COMMAND_BYTES 256

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

typedef struct {
  char command_id[PROTON_ENGINE_MAX_MENU_COMMAND_BYTES];
  proton_window_id_t focused_window;
} proton_engine_menu_command_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  /* Set once by the first asset document and never changed, so every window
     in a runtime resolves application resources against the same root. */
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
  proton_linux_menu_bar_t *menu_definition;
  proton_engine_menu_command_t menu_commands[PROTON_ENGINE_MAX_MENU_COMMANDS];
  size_t menu_command_head;
  size_t menu_command_count;
  pthread_mutex_t menu_lock;
  int menu_lock_initialized;
};

struct proton_engine_window {
  proton_engine_runtime_t *runtime;
  GtkWidget *window;
  GtkWidget *root_box;
  GtkWidget *menu_bar;
  GtkAccelGroup *menu_accel_group;
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
  int headless;
  int headless_hidden;
  int osr_paint_seen;
  int osr_paint_width;
  int osr_paint_height;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int size_hint;
  int titlebar_overlay;
  int always_on_top;
  int zoom_percent;
  int close_interception_enabled;
  int close_interception_bypass;
  int close_request_pending;
  uint64_t close_request_id;
  proton_browser_session_t *browser_session;
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

/* A web contents view: an extra child browser hosted inside a window's
   browser host, positioned in top-left coordinates. The struct is owned by
   the window's view list and freed only from the window's storage teardown,
   so native ABI view slots can never hold a dangling pointer regardless of
   how the view was closed. */
struct proton_engine_view {
  proton_engine_window_t *window;
  proton_engine_client_t *client;
  cef_browser_t *browser;
  int browser_id;
  cef_window_handle_t xwindow;
  Display *display;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int visible;
  uint64_t native_id;
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  char *html_url;
  char *html;
  size_t html_len;
  proton_browser_session_t *browser_session;
  proton_view_events_t *events;
  int has_background_color;
  uint32_t background_color;
  int browser_close_requested;
  int browser_before_close_seen;
  int finalize_after_browser_close;
  int finalized;
  int closed;
  int osr_paint_seen;
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
  cef_drag_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_drag_handler_t;

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
static int g_proton_cef_runtime_active = 0;
static int g_proton_cef_shutdown_registered = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
static proton_engine_app_t g_app;
static proton_engine_browser_process_handler_t g_browser_process_handler;
static proton_engine_render_process_handler_t g_render_process_handler;
static proton_engine_v8_handler_t g_v8_handler;
static proton_engine_life_span_handler_t g_life_span_handler;
static proton_engine_load_handler_t g_load_handler;
static proton_engine_drag_handler_t g_drag_handler;
static proton_engine_request_handler_t g_request_handler;
static proton_engine_download_handler_t g_download_handler;
static proton_engine_permission_handler_t g_permission_handler;
static proton_engine_render_handler_t g_render_handler;
static proton_engine_display_handler_t g_display_handler;
static uint64_t g_next_view_native_id = 1;
static proton_engine_scheme_factory_t g_scheme_factory;
static proton_engine_window_t *g_windows = NULL;
static proton_engine_bridge_pending_t *g_bridge_pending = NULL;
static atomic_llong g_scheduled_pump_delay_ms = ATOMIC_VAR_INIT(-1);
static atomic_int g_runtime_wait_log_count = ATOMIC_VAR_INIT(0);
static atomic_uint g_wait_source_ready_mask = ATOMIC_VAR_INIT(PROTON_WAIT_NONE);
/* Set only while this process is inside cef_do_message_loop_work. */
static atomic_bool g_message_pump_active = ATOMIC_VAR_INIT(false);
static proton_engine_runtime_t *g_active_runtime = NULL;

/* The host loop's wake pipe. Process-wide rather than per-runtime: the
   loop runs before the first runtime exists and outlives the last, and a
   wakeup arriving outside a runtime's lifetime must still land somewhere.
   Nonblocking, and drained rather than counted -- it carries the fact that
   something happened, never how much. */
static int g_host_wake_read_fd = -1;
static int g_host_wake_write_fd = -1;
static proton_engine_window_t *g_closed_windows = NULL;
/* Guards g_windows list membership and the per-window html/html_url/html_len
   fields. Writers run on the main thread; the scheme handler factory reads
   them on CEF's IO thread, so both sides must take this lock. Keep critical
   sections leaf-only: never call back into engine or CEF code while held. */
static pthread_mutex_t g_window_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_wakeup_fd_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_wakeup_write_fd = -1;

static GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                                       GdkEvent *event,
                                                       gpointer user_data);
static int32_t proton_engine_window_install_menu(
    proton_engine_window_t *window,
    const proton_linux_menu_bar_t *menu_definition,
    char *error,
    size_t error_len);

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

static ssize_t proton_engine_write_no_sigpipe(int fd,
                                              const void *buffer,
                                              size_t length) {
  sigset_t sigpipe_mask;
  sigset_t previous_mask;
  sigset_t pending_mask;
  sigemptyset(&sigpipe_mask);
  sigaddset(&sigpipe_mask, SIGPIPE);
  int mask_status = pthread_sigmask(SIG_BLOCK, &sigpipe_mask, &previous_mask);
  if (mask_status != 0) {
    errno = mask_status;
    return -1;
  }
  if (sigpending(&pending_mask) != 0) {
    int pending_error = errno;
    (void)pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
    errno = pending_error;
    return -1;
  }
  int sigpipe_was_pending = sigismember(&pending_mask, SIGPIPE) == 1;

  ssize_t written;
  do {
    written = write(fd, buffer, length);
  } while (written < 0 && errno == EINTR);
  int write_error = written < 0 ? errno : 0;
  if (written < 0 && write_error == EPIPE && !sigpipe_was_pending) {
    struct timespec timeout = {.tv_sec = 0, .tv_nsec = 0};
    while (sigtimedwait(&sigpipe_mask, NULL, &timeout) < 0 && errno == EINTR) {
    }
  }
  (void)pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
  if (written < 0) {
    errno = write_error;
  }
  return written;
}

static void proton_engine_signal_wakeup_fd(unsigned char wakeup_byte) {
  pthread_mutex_lock(&g_wakeup_fd_lock);
  if (g_wakeup_write_fd >= 0) {
    (void)proton_engine_write_no_sigpipe(
        g_wakeup_write_fd, &wakeup_byte, sizeof(wakeup_byte));
  }
  pthread_mutex_unlock(&g_wakeup_fd_lock);
}

static void proton_engine_clear_wakeup_fd(void) {
  pthread_mutex_lock(&g_wakeup_fd_lock);
  int previous_fd = g_wakeup_write_fd;
  g_wakeup_write_fd = -1;
  pthread_mutex_unlock(&g_wakeup_fd_lock);
  if (previous_fd >= 0) {
    close(previous_fd);
  }
}

static int proton_engine_set_nonblocking(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) {
    return 0;
  }
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

static void proton_engine_drain_wake_pipe(void) {
  if (g_host_wake_read_fd < 0) {
    return;
  }
  char buffer[64];
  for (;;) {
    ssize_t read_count =
        read(g_host_wake_read_fd, buffer, sizeof(buffer));
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

static void proton_engine_close_wake_pipe(void) {
  if (g_host_wake_read_fd >= 0) {
    close(g_host_wake_read_fd);
    g_host_wake_read_fd = -1;
  }
  if (g_host_wake_write_fd >= 0) {
    close(g_host_wake_write_fd);
    g_host_wake_write_fd = -1;
  }
}

static int proton_engine_setup_wait_source(char *error, size_t error_len) {
  if (g_host_wake_read_fd >= 0) {
    return 1;
  }
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
  g_host_wake_read_fd = pipe_fds[0];
  g_host_wake_write_fd = pipe_fds[1];
  atomic_store_explicit(&g_wait_source_ready_mask, PROTON_WAIT_NONE,
                        memory_order_release);
  return 1;
}

static void proton_engine_signal_wait_source(uint32_t ready_mask) {
  if (ready_mask != PROTON_WAIT_NONE) {
    atomic_fetch_or_explicit(&g_wait_source_ready_mask, ready_mask,
                             memory_order_release);
  }
  if (g_host_wake_write_fd >= 0) {
    char byte = 1;
    (void)proton_engine_write_no_sigpipe(g_host_wake_write_fd, &byte, 1);
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

static int64_t proton_engine_get_scheduled_pump_delay_ms(void) {
  return atomic_load_explicit(&g_scheduled_pump_delay_ms, memory_order_acquire);
}

static void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
  atomic_store_explicit(&g_scheduled_pump_delay_ms, (long long)delay_ms,
                        memory_order_release);
  /* Every delay signals, not just an immediate one. A host blocked with no
     deadline of its own has nothing else to bring it back, and it reads the
     schedule only on its way into a wait -- one that arrives after that read
     would otherwise never be seen. The pump-active guard is what keeps this
     from spinning: the reschedule CEF makes while being pumped stays silent,
     so the loop settles onto the delay instead of the signal. */
  if (!atomic_load_explicit(&g_message_pump_active, memory_order_acquire)) {
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

static void proton_engine_append_switch_with_value(
    cef_command_line_t *command_line,
    const char *name,
    const char *value) {
  cef_string_t switch_name = {0};
  cef_string_t switch_value = {0};
  proton_engine_set_string(&switch_name, name);
  proton_engine_set_string(&switch_value, value);
  command_line->append_switch_with_value(command_line, &switch_name,
                                         &switch_value);
  cef_string_clear(&switch_name);
  cef_string_clear(&switch_value);
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

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  pthread_mutex_lock(&g_window_lock);
  window->next = g_windows;
  g_windows = window;
  pthread_mutex_unlock(&g_window_lock);
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
  pthread_mutex_lock(&g_window_lock);
  proton_engine_window_t **cursor = &g_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      break;
    }
    cursor = &(*cursor)->next;
  }
  pthread_mutex_unlock(&g_window_lock);
}

static int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser);
static void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title);
static cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self);
static proton_engine_view_t *proton_engine_view_from_browser(
    cef_browser_t *browser);
static void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window);
static void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);
static void proton_engine_window_close_views(
    proton_engine_window_t *window);
static void proton_engine_window_free_views(
    proton_engine_window_t *window);
static void proton_engine_browser_release(cef_browser_t *browser);

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
  pthread_mutex_lock(&g_window_lock);
  if (window->menu_accel_group != NULL) {
    g_object_unref(window->menu_accel_group);
    window->menu_accel_group = NULL;
  }
  proton_engine_window_free_views(window);
  free(window->client);
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  proton_browser_session_destroy(window->browser_session);
  free(window->draggable_regions);
  proton_engine_overlay_release_input_windows(window);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
  pthread_mutex_unlock(&g_window_lock);
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
    proton_engine_client_t *client = (proton_engine_client_t *)cef_client;
    window = client->window;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return window;
}

// Resolves a view through the browser's client. Unlike the browser-id list
// scan this also works while cef_browser_host_create_browser_sync is still
// running, before the view records its browser id.
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
    proton_engine_client_t *client = (proton_engine_client_t *)cef_client;
    view = client->view;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return view;
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

static void proton_engine_runtime_dispose_menu(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return;
  }
  proton_linux_menu_bar_destroy(runtime->menu_definition);
  runtime->menu_definition = NULL;
  if (runtime->menu_lock_initialized) {
    pthread_mutex_destroy(&runtime->menu_lock);
    runtime->menu_lock_initialized = 0;
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

/* The window state shared engine code reaches this engine through; see
   cef_common/window_state.h. */

void proton_engine_window_lock(void) {
  pthread_mutex_lock(&g_window_lock);
}

void proton_engine_window_unlock(void) {
  pthread_mutex_unlock(&g_window_lock);
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


const char *proton_engine_runtime_asset_root(proton_engine_window_t *window) {
  proton_engine_runtime_t *runtime = window != NULL ? window->runtime : NULL;
  if (runtime == NULL && g_windows != NULL) {
    runtime = g_windows->runtime;
  }
  return runtime != NULL ? runtime->asset_root : NULL;
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

static void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar) {
  (void)self;
  proton_engine_register_app_custom_schemes(registrar);
}

static int proton_engine_process_type_is_browser(
    const cef_string_t *process_type) {
  return process_type == NULL || process_type->length == 0;
}

static void CEF_CALLBACK proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  /* The Linux window host embeds CEF into GTK/X11. Keep Chromium's Ozone
   * backend on X11 as well; selecting Wayland here initializes GDK before
   * proton_engine_ensure_gtk can apply its X11-only constraint. */
  proton_engine_append_switch_with_value(command_line, "ozone-platform",
                                         "x11");
  proton_engine_append_switch(command_line, "disable-gpu");
  proton_engine_append_switch(command_line, "in-process-gpu");
  // On Xvfb-based CI displays Chromium's occlusion tracking can mark the
  // window hidden and throttle the renderer, which then never lays out and
  // never reports draggable regions. Keep the renderer active so region
  // computation proceeds regardless of window-manager occlusion state.
  proton_engine_append_switch(command_line,
                              "disable-backgrounding-occluded-windows");
  proton_engine_append_switch(command_line, "disable-renderer-backgrounding");
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
    // CEF can query the viewport while create_browser_sync is still running,
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
  if (!window->headless || type != PET_VIEW || width <= 0 || height <= 0) {
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

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    proton_engine_debug_log("view_browser_before_close browser=%d",
                            view->browser_id);
    view->browser_before_close_seen = 1;
    view->closed = 1;
    view->xwindow = 0;
    if (view->browser != NULL) {
      proton_engine_browser_release(view->browser);
      view->browser = NULL;
    }
    // A page-initiated close (JS window.close) reaches here without a prior
    // engine destroy; let the cleanup state machine finish so the struct can
    // be reclaimed with its owning window.
    view->finalize_after_browser_close = 1;
    proton_engine_view_finalize_if_ready(view);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL) {
    proton_engine_debug_log("browser_before_close browser=%d",
                            window->browser_id);
    proton_engine_window_close_views(window);
    proton_engine_window_mark_closed(window);
    if (window->window != NULL) {
      gtk_widget_destroy(window->window);
    }
    proton_engine_window_finalize_if_ready(window);
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

static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self) {
  (void)self;
  return &g_download_handler.handler;
}

static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self) {
  (void)self;
  return &g_permission_handler.handler;
}

static cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self) {
  proton_engine_client_t *client = (proton_engine_client_t *)self;
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
  g_life_span_handler.handler.on_before_close = proton_engine_on_before_close;
  g_life_span_handler.handler.do_close = proton_engine_do_close;

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
      if (proton_engine_urls_same_document(url, current_url)) {
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
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL || frame == NULL || !frame->is_main(frame)) {
    return;
  }
  char *url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  if (url != NULL && strcmp(url, "about:blank") != 0) {
    proton_view_events_navigated(view->events, url);
    proton_view_events_loading_changed(view->events, 1);
    proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode) {
  (void)self;
  if (frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    proton_view_events_loading_changed(view->events, 0);
    proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  char *url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  proton_engine_debug_log("load_end browser=%d status=%d url=%s",
                          window != NULL ? window->browser_id : -1,
                          httpStatusCode, url != NULL ? url : "(null)");
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
  proton_engine_debug_log(
      "render_terminated browser=%d status=%d code=%d",
      window != NULL ? window->browser_id : -1, (int)status, error_code);
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
  return proton_browser_policy_parse_window_json(
      config_json, &config->browser_policy, error, error_len);
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
    return TRUE;
  }
  window->close_interception_bypass = 0;
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
    window->root_box = NULL;
    window->menu_bar = NULL;
    window->browser_host = NULL;
    window->overlay_controls = NULL;
    if (window->menu_accel_group != NULL) {
      g_object_unref(window->menu_accel_group);
      window->menu_accel_group = NULL;
    }
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
  if (window == NULL || window->browser == NULL) {
    return;
  }
  if (window->headless) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host != NULL) {
      if (host->was_resized != NULL) {
        host->was_resized(host);
      }
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
  }
  if (window->browser_host == NULL) {
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

static void proton_engine_window_state_notify(GObject *object,
                                              GParamSpec *parameter,
                                              gpointer user_data) {
  (void)object;
  (void)parameter;
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window != NULL) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_window_screen_changed(GtkWidget *widget,
                                                GdkScreen *previous,
                                                gpointer user_data) {
  (void)widget;
  (void)previous;
  proton_engine_window_state_notify(NULL, NULL, user_data);
}

static void proton_engine_window_style_updated(GtkWidget *widget,
                                               gpointer user_data) {
  (void)widget;
  proton_engine_window_state_notify(NULL, NULL, user_data);
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

static void proton_engine_remove_temporary_profile(void) {
  if (g_proton_temporary_profile_path[0] != '\0') {
    proton_profile_storage_remove_temporary(g_proton_temporary_profile_path);
    g_proton_temporary_profile_path[0] = '\0';
  }
}

static void proton_engine_cef_shutdown(void) {
  if (g_proton_cef_initialized) {
    proton_engine_debug_log("cef_shutdown_start");
    cef_shutdown();
    g_proton_cef_initialized = 0;
    proton_engine_debug_log("cef_shutdown_done");
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

  proton_engine_init_handlers();
  proton_engine_check_cef_api_hash();

  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)calloc(1, sizeof(*runtime));
  if (runtime == NULL) {
    proton_engine_remove_temporary_profile();
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
  if (pthread_mutex_init(&runtime->menu_lock, NULL) == 0) {
    runtime->menu_lock_initialized = 1;
  }
  if (!proton_engine_setup_wait_source(error, error_len)) {
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
    }
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    proton_engine_remove_temporary_profile();
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
  settings.windowless_rendering_enabled = config.headless;
  settings.log_severity = proton_engine_cef_log_severity_from_env();
  settings.remote_debugging_port = config.remote_debugging_port;
  settings.persist_session_cookies = config.persist_session_cookies;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  if (!temporary_profile) {
    proton_engine_set_string(&settings.cache_path, config.cache_dir);
  }

  proton_engine_debug_log("cef_initialize_start");
  int cef_initialized = cef_initialize(&args, &settings, &g_app.app, NULL);
  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.cache_path);
  cef_string_clear(&settings.root_cache_path);
  proton_engine_free_main_args(&main_args);
  if (!cef_initialized) {
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
      runtime->bridge_lock_initialized = 0;
    }
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    g_active_runtime = NULL;
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  g_proton_cef_initialized = 1;
  proton_engine_debug_log("cef_initialize_done");

  /* CEF's Linux browser process must initialize before GTK starts its
   * process-global state and helper threads. */
  proton_engine_debug_log("gtk_initialize_start");
  if (!proton_engine_ensure_gtk(error, error_len)) {
    proton_engine_cef_shutdown();
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
      runtime->bridge_lock_initialized = 0;
    }
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    g_active_runtime = NULL;
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_debug_log("gtk_initialize_done");
  proton_engine_debug_log("runtime_create remote_debugging_port=%d",
                          config.remote_debugging_port);

  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_app_scheme_factory(&g_scheme_factory.factory)) {
    proton_engine_cef_shutdown();
    if (runtime->bridge_lock_initialized) {
      pthread_mutex_destroy(&runtime->bridge_lock);
      runtime->bridge_lock_initialized = 0;
    }
    proton_engine_runtime_dispose_menu(runtime);
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
    runtime->owns_cef_runtime = 0;
  }
  if (runtime->bridge_lock_initialized) {
    pthread_mutex_destroy(&runtime->bridge_lock);
    runtime->bridge_lock_initialized = 0;
  }
  proton_engine_runtime_dispose_menu(runtime);
  proton_engine_clear_wakeup_fd();
  if (g_active_runtime == runtime) {
    g_active_runtime = NULL;
  }
  g_proton_cef_runtime_active = 0;
  proton_engine_debug_log("runtime_destroy_done");
  /* The e2e suite uses this as proof that native shutdown completed. */
  proton_engine_debug_log("runtime_destroy_complete");
  free(runtime->asset_root);
  free(runtime);
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
  atomic_store_explicit(&g_message_pump_active, true, memory_order_release);
  proton_engine_reset_scheduled_pump();
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
  cef_do_message_loop_work();
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
      proton_engine_get_scheduled_pump_delay_ms() == 0) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  if ((interest_mask & PROTON_WAIT_PLATFORM) != 0 &&
      g_main_context_pending(NULL)) {
    ready_mask |= PROTON_WAIT_PLATFORM;
  }
  return ready_mask & interest_mask;
}

int32_t proton_engine_host_loop_begin(char *error, size_t error_len) {
  /* The wake pipe is plain POSIX and needs no CEF, so the loop can exist long
     before a runtime does. A pipe rather than a bare condition variable
     because poll(2) has to wait on it together with everything else, and
     because a byte written while nothing is waiting stays readable -- a wakeup
     that arrived early must still release the next wait. */
  if (!proton_engine_setup_wait_source(error, error_len)) {
    return PROTON_ERR_PLATFORM;
  }
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
  /* The wait above only blocks on descriptors; it dispatches nothing. This is
     where GTK's pending sources run and the only caller of
     cef_do_message_loop_work while the host loop owns the main thread. */
  atomic_store_explicit(&g_message_pump_active, true, memory_order_release);
  proton_engine_reset_scheduled_pump();
  while (g_main_context_pending(NULL)) {
    g_main_context_iteration(NULL, FALSE);
  }
  cef_do_message_loop_work();
  atomic_store_explicit(&g_message_pump_active, false, memory_order_release);
  return PROTON_OK;
}

void proton_engine_host_loop_end(void) {
  proton_engine_close_wake_pipe();
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
  if (g_host_wake_read_fd < 0) {
    proton_engine_set_message(error, error_len, "host loop is not running");
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

  // Negative means PROTON_WAIT_TIMEOUT_INFINITE; the ABI rejects every other
  // negative value first. Kept out of the arithmetic below so it is never
  // mistaken for a duration -- assigning it into an unsigned local would turn
  // "forever" into about 49 days without saying so.
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

  /* Nothing is cleared before waiting. Bits set while the host was running its
     own code -- not inside this wait -- are the ones that matter most, and
     clearing first would throw them away; the exchange below is what consumes
     them. Re-reporting a bit the host has already handled only costs it a
     spurious poll, while dropping one costs it the notification entirely. */
  int poll_result = 0;
  if (g_host_wake_read_fd >= 0) {
    struct pollfd wake_fd;
    memset(&wake_fd, 0, sizeof(wake_fd));
    wake_fd.fd = g_host_wake_read_fd;
    wake_fd.events = POLLIN;
    // poll(2) spells "no timeout" as -1, which is the same convention the ABI
    // uses, so waiting forever needs no special case here.
    int poll_timeout = wait_forever ? -1
                       : wait_timeout > (int64_t)INT_MAX
                           ? INT_MAX
                           : (int)wait_timeout;
    do {
      poll_result = poll(&wake_fd, 1, poll_timeout);
    } while (poll_result < 0 && errno == EINTR);
    if (poll_result > 0 && (wake_fd.revents & POLLIN) != 0) {
      proton_engine_drain_wake_pipe();
    }
  } else if (wait_forever) {
    // No wake descriptor means nothing can interrupt a sleep, so sleeping
    // forever would strand the caller with no way back. Refuse instead of
    // hanging: an infinite wait needs something that can wake it.
    proton_engine_set_message(
        error, error_len,
        "an infinite runtime wait requires a wakeup descriptor");
    return PROTON_ERR_UNSUPPORTED;
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
      waiting_for_platform_pump && poll_result == 0) {
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
    int status_flags = fcntl(owned_fd, F_GETFL, 0);
    int descriptor_flags = fcntl(owned_fd, F_GETFD, 0);
    if (status_flags < 0 || descriptor_flags < 0 ||
        fcntl(owned_fd, F_SETFL, status_flags | O_NONBLOCK) < 0 ||
        fcntl(owned_fd, F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) {
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

// TODO: Provide a Linux platform-owned wakeup source.
int32_t proton_engine_runtime_prepare_wakeup_source(
    proton_engine_runtime_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  proton_engine_set_message(error, error_len,
                            "runtime wakeup sources are not supported on Linux");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_runtime_activate_wakeup_source(
    proton_engine_runtime_t *runtime, char *error, size_t error_len) {
  (void)runtime;
  proton_engine_set_message(error, error_len,
                            "runtime wakeup sources are not supported on Linux");
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

static void proton_engine_menu_reset_commands(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL || !runtime->menu_lock_initialized) {
    return;
  }
  pthread_mutex_lock(&runtime->menu_lock);
  runtime->menu_command_head = 0;
  runtime->menu_command_count = 0;
  pthread_mutex_unlock(&runtime->menu_lock);
}

static void proton_engine_menu_enqueue_command(
    proton_engine_runtime_t *runtime,
    const char *command_id,
    proton_window_id_t focused_window) {
  if (runtime == NULL || !runtime->menu_lock_initialized ||
      command_id == NULL ||
      strlen(command_id) >= PROTON_ENGINE_MAX_MENU_COMMAND_BYTES) {
    return;
  }
  int inserted = 0;
  pthread_mutex_lock(&runtime->menu_lock);
  if (runtime->menu_command_count < PROTON_ENGINE_MAX_MENU_COMMANDS) {
    const size_t index =
        (runtime->menu_command_head + runtime->menu_command_count) %
        PROTON_ENGINE_MAX_MENU_COMMANDS;
    snprintf(runtime->menu_commands[index].command_id,
             sizeof(runtime->menu_commands[index].command_id), "%s",
             command_id);
    runtime->menu_commands[index].focused_window = focused_window;
    runtime->menu_command_count++;
    inserted = 1;
  }
  pthread_mutex_unlock(&runtime->menu_lock);
  if (inserted) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}

static void proton_engine_menu_command_activated(const char *command_id,
                                                 void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->runtime == NULL) {
    return;
  }
  proton_engine_menu_enqueue_command(window->runtime, command_id,
                                     window->public_window_id);
}

static void proton_engine_menu_apply_edit_role(
    proton_engine_window_t *window,
    const char *role) {
  if (window == NULL || window->browser == NULL || role == NULL) {
    return;
  }
  cef_frame_t *frame =
      window->browser->get_focused_frame != NULL
          ? window->browser->get_focused_frame(window->browser)
          : NULL;
  if (frame == NULL) {
    frame = window->browser->get_main_frame(window->browser);
  }
  if (frame == NULL) {
    return;
  }
  if (strcmp(role, "undo") == 0) {
    frame->undo(frame);
  } else if (strcmp(role, "redo") == 0) {
    frame->redo(frame);
  } else if (strcmp(role, "cut") == 0) {
    frame->cut(frame);
  } else if (strcmp(role, "copy") == 0) {
    frame->copy(frame);
  } else if (strcmp(role, "paste") == 0) {
    frame->paste(frame);
  } else if (strcmp(role, "select_all") == 0) {
    frame->select_all(frame);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_engine_menu_role_activated(const char *role,
                                              void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  if (window == NULL || window->runtime == NULL || role == NULL) {
    return;
  }
  if (strcmp(role, "quit") == 0) {
    for (proton_engine_window_t *candidate = g_windows; candidate != NULL;
         candidate = candidate->next) {
      if (candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_window_close(GTK_WINDOW(candidate->window));
      }
    }
  } else if (strcmp(role, "hide") == 0) {
    if (window->window != NULL) {
      gtk_widget_hide(window->window);
    }
  } else if (strcmp(role, "hide_others") == 0) {
    for (proton_engine_window_t *candidate = g_windows; candidate != NULL;
         candidate = candidate->next) {
      if (candidate != window && candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_widget_hide(candidate->window);
      }
    }
  } else if (strcmp(role, "show_all") == 0) {
    for (proton_engine_window_t *candidate = g_windows; candidate != NULL;
         candidate = candidate->next) {
      if (candidate->runtime == window->runtime &&
          candidate->window != NULL) {
        gtk_widget_show_all(candidate->window);
      }
    }
  } else if (strcmp(role, "close") == 0) {
    if (window->window != NULL) {
      gtk_window_close(GTK_WINDOW(window->window));
    }
  } else if (strcmp(role, "minimize") == 0) {
    if (window->window != NULL) {
      gtk_window_iconify(GTK_WINDOW(window->window));
    }
  } else if (strcmp(role, "zoom") == 0) {
    proton_engine_overlay_toggle_maximize(window);
  } else {
    proton_engine_menu_apply_edit_role(window, role);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static int32_t proton_engine_window_install_menu(
    proton_engine_window_t *window,
    const proton_linux_menu_bar_t *menu_definition,
    char *error,
    size_t error_len) {
  if (window == NULL || window->window == NULL || window->root_box == NULL ||
      menu_definition == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and menu definition are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  GtkAccelGroup *accelerators = gtk_accel_group_new();
  if (accelerators == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create menu accelerators");
    return PROTON_ERR_PLATFORM;
  }
  GtkWidget *menu_bar = proton_linux_menu_bar_create_widget(
      menu_definition, accelerators, proton_engine_menu_command_activated,
      proton_engine_menu_role_activated, window, error, error_len);
  if (menu_bar == NULL) {
    g_object_unref(accelerators);
    return PROTON_ERR_PLATFORM;
  }

  if (window->menu_accel_group != NULL) {
    gtk_window_remove_accel_group(GTK_WINDOW(window->window),
                                  window->menu_accel_group);
    g_object_unref(window->menu_accel_group);
  }
  if (window->menu_bar != NULL) {
    gtk_widget_destroy(window->menu_bar);
  }
  window->menu_bar = menu_bar;
  window->menu_accel_group = accelerators;
  gtk_window_add_accel_group(GTK_WINDOW(window->window), accelerators);
  gtk_box_pack_start(GTK_BOX(window->root_box), menu_bar, FALSE, FALSE, 0);
  gtk_box_reorder_child(GTK_BOX(window->root_box), menu_bar, 0);
  gtk_widget_show_all(menu_bar);
  proton_engine_sync_browser_bounds(window);
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
  proton_linux_menu_bar_t *menu_definition =
      proton_linux_menu_bar_parse(menu_json, error, error_len);
  if (menu_definition == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->runtime != runtime || window->window == NULL) {
      continue;
    }
    const int32_t status = proton_engine_window_install_menu(
        window, menu_definition, error, error_len);
    if (status != PROTON_OK) {
      proton_linux_menu_bar_destroy(menu_definition);
      return status;
    }
  }
  proton_linux_menu_bar_destroy(runtime->menu_definition);
  runtime->menu_definition = menu_definition;
  proton_engine_menu_reset_commands(runtime);
  return PROTON_OK;
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
  if (window == NULL || window->client == NULL ||
      (!window->headless &&
       (window->browser_host == NULL ||
        gtk_widget_get_window(window->browser_host) == NULL))) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int browser_width = window->width;
  int browser_height = window->height;
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
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
    browser_width =
        parent_attributes.width > 0 ? parent_attributes.width : window->width;
    browser_height = parent_attributes.height > 0 ? parent_attributes.height
                                                  : window->height;
  }
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = browser_width;
  window_info.bounds.height = browser_height;
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
  window->width = config.width;
  window->height = config.height;
  window->headless = runtime->headless;
  window->size_hint = config.size_hint;
  window->titlebar_overlay = config.titlebar_overlay;
  window->zoom_percent = 100;
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

  if (!window->headless) {
    window->window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    if (window->window == NULL) {
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    window->root_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    if (window->root_box == NULL) {
      gtk_widget_destroy(window->window);
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len,
                                "window root container creation failed");
      return PROTON_ERR_PLATFORM;
    }
    proton_engine_use_default_x11_visual(window->window);
    gtk_window_set_title(GTK_WINDOW(window->window),
                         config.title[0] != '\0' ? config.title : "Proton");
    gtk_window_set_default_size(GTK_WINDOW(window->window), config.width,
                                config.height);
    if (config.size_hint == 1) {
      gtk_window_set_resizable(GTK_WINDOW(window->window), FALSE);
    } else if (config.size_hint == 2 || config.size_hint == 3) {
      GdkGeometry geometry = {0};
      GdkWindowHints hints = config.size_hint == 2 ? GDK_HINT_MIN_SIZE
                                                   : GDK_HINT_MAX_SIZE;
      if (config.size_hint == 2) {
        geometry.min_width = config.width;
        geometry.min_height = config.height;
      } else {
        geometry.max_width = config.width;
        geometry.max_height = config.height;
      }
      gtk_window_set_geometry_hints(GTK_WINDOW(window->window), NULL,
                                    &geometry, hints);
    }
    if (window->titlebar_overlay) {
      gtk_window_set_decorated(GTK_WINDOW(window->window), FALSE);
      window->overlay = gtk_overlay_new();
      if (window->overlay == NULL) {
        gtk_widget_destroy(window->window);
        free(window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
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
      proton_browser_session_destroy(window->browser_session);
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
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        proton_engine_set_message(error, error_len,
                                  "overlay window controls creation failed");
        return PROTON_ERR_PLATFORM;
      }
      gtk_box_pack_end(GTK_BOX(window->root_box), window->overlay, TRUE, TRUE,
                       0);
    } else {
      gtk_box_pack_end(GTK_BOX(window->root_box), window->browser_host, TRUE,
                       TRUE, 0);
    }
    gtk_container_add(GTK_CONTAINER(window->window), window->root_box);
    if (runtime->menu_definition != NULL) {
      status = proton_engine_window_install_menu(
          window, runtime->menu_definition, error, error_len);
      if (status != PROTON_OK) {
        gtk_widget_destroy(window->window);
        free(window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        return status;
      }
    }
    g_signal_connect(window->window, "delete-event",
                     G_CALLBACK(proton_engine_on_window_delete), window);
    g_signal_connect(window->window, "destroy",
                     G_CALLBACK(proton_engine_on_window_destroy), window);
    g_signal_connect(window->window, "configure-event",
                     G_CALLBACK(proton_engine_window_configure), window);
    g_signal_connect(window->window, "notify::is-active",
                     G_CALLBACK(proton_engine_window_state_notify), window);
    g_signal_connect(window->window, "notify::scale-factor",
                     G_CALLBACK(proton_engine_window_state_notify), window);
    g_signal_connect(window->window, "screen-changed",
                     G_CALLBACK(proton_engine_window_screen_changed), window);
    g_signal_connect(window->window, "style-updated",
                     G_CALLBACK(proton_engine_window_style_updated), window);
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
  }
  proton_engine_debug_log("window_create title=%s size=%dx%d initial_url=%s",
                          config.title, config.width, config.height,
                          config.initial_url);

  status = proton_engine_window_create_browser(window, config.initial_url, error,
                                               error_len);
  if (status != PROTON_OK) {
    if (window->window != NULL) {
      gtk_widget_destroy(window->window);
    }
    free(window->client);
    proton_browser_session_destroy(window->browser_session);
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
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->closed && window->browser == NULL) {
    proton_engine_debug_log("window_destroy_defer_closed browser=%d",
                            window->browser_id);
    window->destroy_requested = 1;
    proton_engine_window_close_views(window);
    if (window->window != NULL) {
      g_signal_handlers_disconnect_by_data(window->window, window);
      gtk_widget_destroy(window->window);
      window->window = NULL;
      window->browser_host = NULL;
    }
    proton_engine_window_finalize_if_ready(window);
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    window->destroy_requested = 1;
    window->closing = 1;
    proton_engine_window_close_views(window);
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }
  window->closed = 1;
  window->destroy_requested = 1;
  proton_engine_window_close_views(window);
  if (window->window != NULL) {
    g_signal_handlers_disconnect_by_data(window->window, window);
    gtk_widget_destroy(window->window);
    window->window = NULL;
    window->browser_host = NULL;
  }
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
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
    gtk_widget_show_all(window->window);
    gtk_window_present(GTK_WINDOW(window->window));
  }
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
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
    gtk_widget_hide(window->window);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
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
    gtk_window_close(GTK_WINDOW(window->window));
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    host->close_browser(host, 0);
    host->base.release((cef_base_ref_counted_t *)host);
  } else {
    proton_engine_window_mark_closed(window);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!window->headless) {
    gtk_window_present(GTK_WINDOW(window->window));
  }
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
  if (window == NULL || (!window->headless && window->window == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  gtk_window_set_title(GTK_WINDOW(window->window), title != NULL ? title : "");
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->window == NULL)) {
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
    proton_engine_sync_browser_bounds(window);
  } else {
    gtk_window_resize(GTK_WINDOW(window->window), width, height);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {
  if (window == NULL || action == NULL ||
      (!window->headless && window->window == NULL)) {
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
    gtk_window_iconify(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    gtk_window_maximize(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    gtk_window_unfullscreen(GTK_WINDOW(window->window));
    gtk_window_unmaximize(GTK_WINDOW(window->window));
    gtk_window_deiconify(GTK_WINDOW(window->window));
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN:
    if (action->value != 0) {
      gtk_window_fullscreen(GTK_WINDOW(window->window));
    } else {
      gtk_window_unfullscreen(GTK_WINDOW(window->window));
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_POSITION:
    gtk_window_move(GTK_WINDOW(window->window), action->x, action->y);
    break;
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    gtk_window_set_keep_above(GTK_WINDOW(window->window),
                              action->value != 0);
    window->always_on_top = action->value != 0;
    break;
  default:
    proton_engine_set_message(error, error_len, "unknown window action");
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
    return PROTON_OK;
  }
  if (window->window == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  gtk_window_get_position(GTK_WINDOW(window->window), &out_state->x,
                          &out_state->y);
  gtk_window_get_size(GTK_WINDOW(window->window), &out_state->width,
                      &out_state->height);
  GdkWindow *gdk_window = gtk_widget_get_window(window->window);
  if (gdk_window != NULL) {
    GdkDisplay *display = gdk_window_get_display(gdk_window);
    GdkMonitor *monitor =
        gdk_display_get_monitor_at_window(display, gdk_window);
    if (monitor != NULL) {
      GdkRectangle geometry = {0};
      GdkRectangle work = {0};
      gdk_monitor_get_geometry(monitor, &geometry);
      gdk_monitor_get_workarea(monitor, &work);
      out_state->monitor_x = geometry.x;
      out_state->monitor_y = geometry.y;
      out_state->monitor_width = geometry.width;
      out_state->monitor_height = geometry.height;
      out_state->work_x = work.x;
      out_state->work_y = work.y;
      out_state->work_width = work.width;
      out_state->work_height = work.height;
    }
    out_state->scale_factor_percent =
        gdk_window_get_scale_factor(gdk_window) * 100;
    GdkWindowState state = gdk_window_get_state(gdk_window);
    out_state->minimized =
        (state & GDK_WINDOW_STATE_ICONIFIED) != 0 ? 1 : 0;
    out_state->maximized =
        (state & GDK_WINDOW_STATE_MAXIMIZED) != 0 ? 1 : 0;
    out_state->fullscreen =
        (state & GDK_WINDOW_STATE_FULLSCREEN) != 0 ? 1 : 0;
  }
  out_state->visible = gtk_widget_get_visible(window->window) ? 1 : 0;
  out_state->focused =
      gtk_window_has_toplevel_focus(GTK_WINDOW(window->window)) ? 1 : 0;
  out_state->always_on_top = window->always_on_top;
  gboolean dark = FALSE;
  GtkSettings *settings = gtk_settings_get_default();
  if (settings != NULL) {
    g_object_get(settings, "gtk-application-prefer-dark-theme", &dark, NULL);
    out_state->theme = dark ? 2 : 1;
  }
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
    if (window->window != NULL) {
      gtk_window_close(GTK_WINDOW(window->window));
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_debug_log("load_document browser=%d document_url=%s bytes=%llu",
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
  return proton_engine_window_load_document(window, html, document_url,
                                            asset_root, error, error_len);
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
    proton_engine_set_message(error, error_len, "browser is not initialized");
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
  return PROTON_OK;
}

void proton_engine_window_bind_public_id(proton_engine_window_t *window,
                                         proton_window_id_t public_window) {
  if (window != NULL) {
    window->public_window_id = public_window;
    proton_browser_session_bind_window(window->browser_session, public_window);
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
int32_t proton_engine_take_menu_command(
    proton_engine_runtime_t *runtime,
    char *buffer,
    size_t buffer_len,
    proton_window_id_t *out_focused_window,
    int32_t *out_present) {
  if (out_focused_window == NULL || out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_focused_window = PROTON_INVALID_HANDLE;
  *out_present = 0;
  if (runtime == NULL || !runtime->menu_lock_initialized) {
    return PROTON_OK;
  }
  pthread_mutex_lock(&runtime->menu_lock);
  if (runtime->menu_command_count > 0) {
    const proton_engine_menu_command_t *command =
        &runtime->menu_commands[runtime->menu_command_head];
    const size_t command_len = strlen(command->command_id);
    if (buffer == NULL || buffer_len <= command_len) {
      pthread_mutex_unlock(&runtime->menu_lock);
      return PROTON_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(buffer, command->command_id, command_len + 1);
    *out_focused_window = command->focused_window;
    runtime->menu_command_head =
        (runtime->menu_command_head + 1) % PROTON_ENGINE_MAX_MENU_COMMANDS;
    runtime->menu_command_count--;
    *out_present = 1;
  }
  pthread_mutex_unlock(&runtime->menu_lock);
  return PROTON_OK;
}


// MARK: - Web contents views
//
// A view is an extra child browser hosted inside a window's browser host,
// following the Electron WebContentsView model: explicit top-left bounds,
// visibility, z-order, and an independent load target. Struct lifetime is
// owned by the window: views are only freed from the window's storage
// teardown once every view has finalized, so native ABI view slots stay
// valid for the whole window lifetime. Close semantics mirror the macOS
// engine: do_close takes over from CEF's default (which would post a delete
// event to the frame window) and destroys the browser's X window instead.

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

static void proton_engine_view_list_add(proton_engine_window_t *window,
                                        proton_engine_view_t *view) {
  pthread_mutex_lock(&g_window_lock);
  view->next = window->views;
  window->views = view;
  pthread_mutex_unlock(&g_window_lock);
}

static void proton_engine_window_free_views(
    proton_engine_window_t *window) {
  proton_engine_view_t *view = window->views;
  window->views = NULL;
  while (view != NULL) {
    proton_engine_view_t *next = view->next;
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    free(view->html_url);
    free(view->html);
    free(view->client);
    free(view);
    view = next;
  }
}

static void proton_engine_view_finalize_if_ready(proton_engine_view_t *view) {
  if (view == NULL || view->finalized ||
      !view->finalize_after_browser_close) {
    return;
  }
  if (view->browser_id != 0 && !view->browser_before_close_seen) {
    return;
  }
  if (view->client != NULL) {
    view->client->view = NULL;
  }
  view->xwindow = 0;
  view->finalized = 1;
  // The window's own finalize is gated on every view being finalized; this
  // call is a no-op unless the window is waiting on exactly this view.
  proton_engine_window_finalize_if_ready(view->window);
}

static void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window) {
  if (window == NULL || !window->destroy_requested ||
      window->browser != NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->finalized) {
      return;
    }
  }
  proton_engine_window_defer_free(window);
}

static void proton_engine_window_close_views(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->closed) {
      view->closed = 1;
      view->finalize_after_browser_close = 1;
      if (view->browser != NULL) {
        cef_browser_host_t *host = view->browser->get_host(view->browser);
        if (host != NULL) {
          view->browser_close_requested = 1;
          host->close_browser(host, 1);
          host->base.release((cef_base_ref_counted_t *)host);
        } else {
          // A browser without a host can never deliver on_before_close.
          view->browser_before_close_seen = 1;
        }
        proton_engine_browser_release(view->browser);
        view->browser = NULL;
      }
    } else if (!view->finalize_after_browser_close) {
      // Already closed by the page (JS window.close): allow its cleanup to
      // complete so the window finalize gate can pass.
      view->finalize_after_browser_close = 1;
    }
    proton_engine_view_finalize_if_ready(view);
  }
}

// Re-stacks view browser X windows above the window's main browser by
// ascending (z_order, native_id).
static void proton_engine_window_layout_views(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->xwindow != 0 && view->display != NULL && !view->closed) {
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
    if (view->xwindow != 0 && view->display != NULL && !view->closed) {
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
    XRaiseWindow(order[i]->display, order[i]->xwindow);
  }
  free(order);
}

static int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL) {
    // Frame windows keep CEF's default close behavior (delete event on the
    // top-level window).
    return 0;
  }
  proton_engine_debug_log("view_browser_do_close browser=%d",
                          view->browser_id);
  // A view browser owns no top-level window; CEF's default would deliver a
  // delete event to the frame window and cancel the view close. Take over
  // and destroy the browser's X window, which completes the teardown via
  // WindowDestroyed.
  if (view->xwindow != 0 && view->display != NULL) {
    XDestroyWindow(view->display, view->xwindow);
    view->xwindow = 0;
    return 1;
  }
  // Windowless (headless) rendering has no child window; returning false lets
  // CEF destroy the browser object immediately.
  return 0;
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
  // policy, bridge, downloads, and permissions stay window-scoped for now.
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

static int32_t proton_engine_view_create_browser(
    proton_engine_view_t *view,
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
  if (!window->headless &&
      (window->browser_host == NULL ||
       gtk_widget_get_window(window->browser_host) == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for view browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    GdkWindow *host_gdk_window = gtk_widget_get_window(window->browser_host);
    view->display = GDK_WINDOW_XDISPLAY(host_gdk_window);
    window_info.parent_window =
        (cef_window_handle_t)GDK_WINDOW_XID(host_gdk_window);
  }
  window_info.bounds.x = view->x;
  window_info.bounds.y = view->y;
  window_info.bounds.width = view->width;
  window_info.bounds.height = view->height;
  if (view->has_background_color) {
    browser_settings.background_color = view->background_color;
  }
  proton_engine_set_string(&window_info.window_name, "ProtonView");
  proton_engine_set_string(&url, "about:blank");
  view->browser = cef_browser_host_create_browser_sync(
      &window_info, &view->client->client, &url, &browser_settings, NULL,
      NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (view->browser == NULL) {
    proton_engine_set_message(error, error_len, "view browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  view->browser_id = proton_engine_browser_id(view->browser);
  cef_browser_host_t *host = view->browser->get_host(view->browser);
  if (host != NULL) {
    if (window->headless) {
      if (!view->visible && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
    } else {
      view->xwindow = host->get_window_handle(host);
      if (!view->visible && view->xwindow != 0 && view->display != NULL) {
        XUnmapWindow(view->display, view->xwindow);
      }
    }
    host->base.release((cef_base_ref_counted_t *)host);
  }
  proton_engine_window_layout_views(window);
  proton_engine_debug_log("view_create_browser id=%d rect=%d,%d %dx%d",
                          view->browser_id, (int)view->x, (int)view->y,
                          (int)view->width, (int)view->height);
  if (view->initial_url[0] != '\0' &&
      strcmp(view->initial_url, "about:blank") != 0) {
    cef_frame_t *frame = view->browser->get_main_frame(view->browser);
    if (frame != NULL) {
      cef_string_t initial = {0};
      proton_engine_set_string(&initial, view->initial_url);
      frame->load_url(frame, &initial);
      cef_string_clear(&initial);
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
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
  view->has_background_color = config.has_background_color;
  view->background_color = config.background_color;
  snprintf(view->initial_url, sizeof(view->initial_url), "%s",
           config.initial_url);
  view->client = proton_engine_view_client_create(view);
  proton_browser_policy_t view_policy = {PROTON_BROWSER_POLICY_ALLOW,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         1};
  view->browser_session = proton_browser_session_create(
      &view_policy, proton_engine_browser_signal, NULL);
  view->events = proton_view_events_create();
  if (view->client == NULL || view->browser_session == NULL ||
      view->events == NULL) {
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    free(view->client);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_view_list_add(window, view);
  status = proton_engine_view_create_browser(view, error, error_len);
  if (status != PROTON_OK) {
    // The browser never started, so the view finalizes immediately; the
    // struct stays owned by the window list and is reclaimed with it.
    view->closed = 1;
    view->finalize_after_browser_close = 1;
    proton_engine_view_finalize_if_ready(view);
    return status;
  }
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
  cef_browser_host_t *host =
      view->browser != NULL ? view->browser->get_host(view->browser) : NULL;
  if (view->browser != NULL && host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available for close");
    return PROTON_ERR_ENGINE;
  }
  view->closed = 1;
  view->finalize_after_browser_close = 1;
  if (view->browser != NULL) {
    view->browser_close_requested = 1;
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    proton_engine_browser_release(view->browser);
    view->browser = NULL;
  }
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
  } else if (view->xwindow != 0 && view->display != NULL) {
    XMoveResizeWindow(view->display, view->xwindow, x, y, width, height);
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
  } else if (view->xwindow != 0 && view->display != NULL) {
    if (view->visible) {
      XMapWindow(view->display, view->xwindow);
    } else {
      XUnmapWindow(view->display, view->xwindow);
    }
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
                          proton_engine_log_url(url));
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
  if (url_copy == NULL || html_copy == NULL) {
    free(url_copy);
    free(html_copy);
    proton_engine_set_message(error, error_len, "failed to copy html");
    return PROTON_ERR_ENGINE;
  }
  pthread_mutex_lock(&g_window_lock);
  free(view->html_url);
  free(view->html);
  view->html_url = url_copy;
  view->html = html_copy;
  view->html_len = strlen(html_copy);
  pthread_mutex_unlock(&g_window_lock);
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
  // queue carries its own lock, so no UI-thread marshal here.
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
                            view->window->public_window_id);
  }
}
