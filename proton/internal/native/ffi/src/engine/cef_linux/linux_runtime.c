#if defined(__linux__)

#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include "../../proton_engine.h"
#include "linux_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"
#include "linux_menu.h"
#include "linux_titlebar.h"

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
#include "../cef_common/browser_session.h"
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
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PROTON_ENGINE_PATH_SEPARATOR '/'
static int g_proton_cef_initialized = 0;
static int g_proton_cef_runtime_active = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
static char g_proton_engine_locale[PROTON_ENGINE_MAX_PATH_BYTES];
static int32_t g_proton_remote_debugging_port =
    PROTON_REMOTE_DEBUGGING_DISABLED;
static proton_engine_window_t *g_windows = NULL;
static atomic_llong g_scheduled_pump_delay_ms = -1;
static atomic_uint g_wait_source_ready_mask = PROTON_WAIT_NONE;
/* Set only while this process is inside cef_do_message_loop_work. */
static atomic_bool g_message_pump_active = false;
static proton_engine_runtime_t *g_active_runtime = NULL;

/* The host loop's wake pipe. Process-wide rather than per-runtime: the
   loop runs before the first runtime exists and outlives the last, and a
   wakeup arriving outside a runtime's lifetime must still land somewhere.
   Nonblocking, and drained rather than counted -- it carries the fact that
   something happened, never how much. */
static int g_host_wake_read_fd = -1;
static int g_host_wake_write_fd = -1;
static proton_engine_window_t *g_closed_windows = NULL;
/* Guards g_windows list membership read by CEF callback threads. Keep this
   lock leaf-only: never call back into engine or CEF code while held. */
static pthread_mutex_t g_window_lock = PTHREAD_MUTEX_INITIALIZER;

int proton_engine_runtime_initialized(void) {
  return g_proton_cef_initialized;
}

const char *proton_engine_runtime_locale(void) {
  return g_proton_engine_locale;
}

int32_t proton_engine_runtime_remote_debugging_port(void) {
  return g_proton_remote_debugging_port;
}

proton_engine_window_t *proton_engine_windows_head(void) {
  return g_windows;
}

GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                               GdkEvent *event,
                                               gpointer user_data);
int32_t proton_engine_window_install_menu(
    proton_engine_window_t *window,
    const proton_linux_menu_bar_t *menu_definition,
    char *error,
    size_t error_len);

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

void proton_engine_signal_wait_source(uint32_t ready_mask) {
  if (ready_mask != PROTON_WAIT_NONE) {
    atomic_fetch_or_explicit(&g_wait_source_ready_mask, ready_mask,
                             memory_order_release);
  }
  if (g_host_wake_write_fd >= 0) {
    char byte = 1;
    (void)proton_engine_write_no_sigpipe(g_host_wake_write_fd, &byte, 1);
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

static int64_t proton_engine_get_scheduled_pump_delay_ms(void) {
  return atomic_load_explicit(&g_scheduled_pump_delay_ms, memory_order_acquire);
}

void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms) {
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

#include "../cef_common/strings.h"

void proton_engine_append_switch(cef_command_line_t *command_line,
                                 const char *name) {
  if (command_line == NULL || name == NULL || name[0] == '\0') {
    return;
  }
  cef_string_t switch_name = {0};
  proton_engine_set_string(&switch_name, name);
  command_line->append_switch(command_line, &switch_name);
  cef_string_clear(&switch_name);
}

void proton_engine_append_switch_with_value(
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
#include "../cef_common/bridge_request.h"

int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

void proton_engine_window_list_add(proton_engine_window_t *window) {
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

void proton_engine_window_defer_free(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_window_list_remove(window);
  window->next = g_closed_windows;
  g_closed_windows = window;
}

void proton_engine_overlay_release_input_windows(
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
  proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
  proton_internal_bridge_config_destroy(window->bridge_config);
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

proton_engine_window_t *proton_engine_window_from_browser(
    cef_browser_t *browser) {
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) != PROTON_BROWSER_ROLE_MAIN) {
    return NULL;
  }
  return (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
}

proton_engine_view_t *proton_engine_view_from_browser(cef_browser_t *browser) {
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) != PROTON_BROWSER_ROLE_VIEW) {
    return NULL;
  }
  return (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
}

static void proton_engine_runtime_dispose_menu(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return;
  }
  proton_linux_menu_bar_destroy(runtime->menu_definition);
  runtime->menu_definition = NULL;
}

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
  return proton_engine_view_from_browser(browser);
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

int32_t proton_engine_execute_process(
    const proton_engine_runtime_config_t *config, int32_t *out_exit_code,
    char *error, size_t error_len) {
  if (config == NULL) {
    proton_engine_set_message(error, error_len, "runtime config is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_check_cef_api_hash();
  cef_main_args_t args;
  proton_engine_main_args_t main_args;
  proton_engine_init_main_args(&args, &main_args);
  proton_engine_init_handlers();
  snprintf(g_proton_engine_locale, sizeof(g_proton_engine_locale), "%s",
           config->locale);
  int exit_code = cef_execute_process(&args, proton_engine_cef_app(), NULL);
  proton_engine_free_main_args(&main_args);
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

  proton_engine_init_handlers();
  snprintf(g_proton_engine_locale, sizeof(g_proton_engine_locale), "%s",
           config.locale);
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
  runtime->browsers = proton_browser_registry_create(
      proton_engine_browser_client_factory, runtime);
  if (runtime->browsers == NULL) {
    free(runtime);
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser registry");
    return PROTON_ERR_ENGINE;
  }
  snprintf(runtime->dialog_ok_label, sizeof(runtime->dialog_ok_label), "%s",
           config.dialog_ok_label);
  snprintf(runtime->dialog_cancel_label,
           sizeof(runtime->dialog_cancel_label), "%s",
           config.dialog_cancel_label);
  if (!proton_engine_setup_wait_source(error, error_len)) {
    proton_browser_registry_destroy(runtime->browsers);
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
  settings.remote_debugging_port = config.remote_debugging_port > 0
                                       ? config.remote_debugging_port
                                       : PROTON_REMOTE_DEBUGGING_DISABLED;
  settings.persist_session_cookies = config.persist_session_cookies;
  proton_engine_set_string(&settings.browser_subprocess_path,
                           config.helper_path);
  proton_engine_set_string(&settings.resources_dir_path, config.resources_dir);
  if (config.locales_dir[0] != '\0') {
    proton_engine_set_string(&settings.locales_dir_path, config.locales_dir);
  }
  proton_engine_set_string(&settings.accept_language_list,
                           config.accept_languages);
  proton_engine_set_string(&settings.root_cache_path, config.cache_dir);
  if (!temporary_profile) {
    proton_engine_set_string(&settings.cache_path, config.cache_dir);
  }

  int cef_initialized =
      cef_initialize(&args, &settings, proton_engine_cef_app(), NULL);
  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.accept_language_list);
  cef_string_clear(&settings.cache_path);
  cef_string_clear(&settings.root_cache_path);
  proton_engine_free_main_args(&main_args);
  if (!cef_initialized) {
    proton_browser_registry_destroy(runtime->browsers);
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    g_active_runtime = NULL;
    proton_engine_remove_temporary_profile();
    proton_engine_set_message(error, error_len, "cef_initialize failed");
    return PROTON_ERR_ENGINE;
  }
  g_proton_cef_initialized = 1;

  /* CEF's Linux browser process must initialize before GTK starts its
   * process-global state and helper threads. */
  if (!proton_engine_ensure_gtk(error, error_len)) {
    proton_engine_cef_shutdown();
    proton_browser_registry_destroy(runtime->browsers);
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    g_active_runtime = NULL;
    return PROTON_ERR_PLATFORM;
  }

  g_proton_cef_runtime_active = 1;
  if (!proton_engine_register_scheme_factory()) {
    proton_engine_cef_shutdown();
    proton_browser_registry_destroy(runtime->browsers);
    proton_engine_runtime_dispose_menu(runtime);
    free(runtime);
    g_active_runtime = NULL;
    g_proton_cef_runtime_active = 0;
    proton_engine_set_message(error, error_len,
                              "failed to register proton scheme handler");
    return PROTON_ERR_ENGINE;
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

int32_t proton_engine_runtime_destroy_ready(proton_engine_runtime_t *runtime) {
  if (runtime == NULL) {
    return 0;
  }
  proton_browser_registry_begin_shutdown(runtime->browsers);
  return !proton_engine_runtime_has_windows(runtime) &&
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
  if (runtime->owns_cef_runtime) {
    if (!proton_engine_runtime_destroy_ready(runtime)) {
      proton_engine_set_message(error, error_len,
                                "runtime still owns closing browser windows");
      return PROTON_ERR_BUSY;
    }
    proton_engine_bridge_pending_clear_all();
    proton_engine_cef_shutdown();
    proton_engine_free_closed_windows();
    runtime->owns_cef_runtime = 0;
  }
  proton_browser_registry_destroy(runtime->browsers);
  proton_engine_runtime_dispose_menu(runtime);
  if (g_active_runtime == runtime) {
    g_active_runtime = NULL;
  }
  g_proton_cef_runtime_active = 0;
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
  *out_ready_mask = ready_mask;
  return PROTON_OK;
}

#endif
