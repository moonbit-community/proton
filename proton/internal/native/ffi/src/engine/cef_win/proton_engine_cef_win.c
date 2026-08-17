#if defined(_WIN32)

#include "../../proton_engine.h"
#include "../../proton_config.h"
#include "../../proton_event.h"
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
#include "../cef_common/bridge_response.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/document.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"
#include "../cef_common/view_events.h"

#include <ctype.h>
#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_PATH_SEPARATOR '\\'
#define PROTON_ENGINE_WINDOW_CLASS L"ProtonNativeWindow"
#define PROTON_ENGINE_DIALOG_CLASS L"ProtonNativeMessageDialog"
#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
// Posted to a frame window when its destruction must be deferred out of a
// CEF callback: tearing the frame down inline during OnBeforeClose can
// invalidate browser teardown state on the external message pump route.
#define PROTON_ENGINE_WM_DESTROY_SELF (WM_USER + 0x31)
typedef struct proton_engine_client proton_engine_client_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  /* Set once by the first asset document and never changed, so every window
     in a runtime resolves application resources against the same root. */
  char *asset_root;
  int64_t next_bridge_request_id;
  CRITICAL_SECTION wakeup_lock;
  int wakeup_lock_initialized;
  HANDLE wakeup_write;
  int wakeup_active;
  char wakeup_path[256];
  char dialog_ok_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char dialog_cancel_label[PROTON_ENGINE_MAX_LABEL_BYTES];
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
  int headless;
  int headless_hidden;
  int osr_paint_seen;
  int osr_paint_width;
  int osr_paint_height;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int size_hint;
  int titlebar_overlay;
  int fullscreen;
  int always_on_top;
  int zoom_percent;
  DWORD windowed_style;
  WINDOWPLACEMENT windowed_placement;
  proton_win_titlebar_region_t *draggable_regions;
  size_t draggable_region_count;
  int draggable_regions_reported;
  int browser_close_requested;
  int close_interception_enabled;
  int close_interception_bypass;
  int close_request_pending;
  uint64_t close_request_id;
  proton_browser_session_t *browser_session;
  int destroy_requested;
  int closed;
  struct proton_engine_view *views;
  struct proton_engine_window *next;
};

static void proton_engine_dialog_cancel_runtime(
    proton_engine_runtime_t *runtime);
static void proton_engine_dialog_cancel_window(proton_engine_window_t *window);

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
  cef_life_span_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_life_span_handler_t;

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

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_engine_window_t *window;
  proton_engine_view_t *view;
};

/* A web contents view: an extra child browser hosted inside a window's client
   area, positioned in top-left client coordinates. The struct is owned by the
   window's view list and freed only from proton_engine_window_free, so native
   ABI view slots can never hold a dangling pointer regardless of how the view
   was closed. */
struct proton_engine_view {
  proton_engine_window_t *window;
  proton_engine_client_t *client;
  cef_browser_t *browser;
  int browser_id;
  HWND hwnd;
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

typedef struct proton_engine_bridge_pending {
  int64_t request_id;
  int browser_id;
  int renderer_pending_id;
  char *page_instance;
  cef_frame_t *frame;
  struct proton_engine_bridge_pending *next;
} proton_engine_bridge_pending_t;

static int g_proton_cef_initialized = 0;
static int g_proton_cef_shutdown_registered = 0;
static int g_proton_cef_runtime_active = 0;
static char g_proton_temporary_profile_path[PROTON_ENGINE_MAX_PATH_BYTES];
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
static proton_engine_life_span_handler_t g_proton_engine_life_span_handler;
static proton_engine_drag_handler_t g_proton_engine_drag_handler;
static proton_engine_request_handler_t g_proton_engine_request_handler;
static proton_engine_download_handler_t g_proton_engine_download_handler;
static proton_engine_permission_handler_t g_proton_engine_permission_handler;
static proton_engine_render_handler_t g_proton_engine_render_handler;
static proton_engine_display_handler_t g_proton_engine_display_handler;
static uint64_t g_proton_engine_next_view_native_id = 1;
static proton_engine_scheme_factory_t g_proton_engine_scheme_factory;
static CRITICAL_SECTION g_proton_engine_window_lock;
static proton_engine_window_t *g_proton_engine_windows;
static proton_engine_bridge_pending_t *g_proton_engine_bridge_pending;
static char g_proton_engine_resources_dir[PROTON_ENGINE_MAX_PATH_BYTES];
static char g_proton_engine_locales_dir[PROTON_ENGINE_MAX_PATH_BYTES];
static volatile LONG64 g_proton_engine_scheduled_pump_delay_ms = -1;
static volatile LONG g_proton_engine_runtime_wait_log_count = 0;
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
static volatile LONG g_proton_engine_wakeup_source_id = 0;

static void CEF_CALLBACK proton_engine_osr_get_view_rect(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_rect_t *rect);
static int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser);
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
    cef_dictionary_value_t **extra_info,
    int *no_javascript_access);
static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser);
static void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title);
static cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self);
static proton_engine_view_t *proton_engine_find_view_by_browser_id(
    int browser_id);
static void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window);
static void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);
static void proton_engine_window_close_views(
    proton_engine_window_t *window);
static void proton_engine_window_free_views(
    proton_engine_window_t *window);
static int CEF_CALLBACK proton_engine_osr_get_screen_info(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_screen_info_t *screen_info);
static void CEF_CALLBACK proton_engine_osr_on_popup_show(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    int show);
static void CEF_CALLBACK proton_engine_osr_on_popup_size(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    const cef_rect_t *rect);
static void CEF_CALLBACK proton_engine_osr_on_paint(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_paint_element_type_t type,
    size_t dirty_rects_count,
    const cef_rect_t *dirty_rects,
    const void *buffer,
    int width,
    int height);

static void proton_engine_signal_wakeup_source(
    proton_engine_runtime_t *runtime, unsigned char wakeup_byte) {
  if (runtime == NULL || !runtime->wakeup_lock_initialized) {
    return;
  }
  EnterCriticalSection(&runtime->wakeup_lock);
  if (runtime->wakeup_write != NULL && runtime->wakeup_active) {
    DWORD written = 0;
    if (!WriteFile(runtime->wakeup_write, &wakeup_byte, 1, &written, NULL)) {
      DWORD error = GetLastError();
      if (error == ERROR_BROKEN_PIPE) {
        runtime->wakeup_active = 0;
      }
      // Any other failure is transient: ERROR_NO_DATA means the NOWAIT pipe
      // is full, and the buffered bytes already guarantee a wakeup. Keep the
      // pipe active instead of disabling wakeups permanently.
    }
  }
  LeaveCriticalSection(&runtime->wakeup_lock);
}

static void proton_engine_signal_wait_source(
    proton_engine_runtime_t *runtime, uint32_t ready_mask) {
  if (g_proton_engine_pump_event != NULL) {
    SetEvent(g_proton_engine_pump_event);
  }
  proton_engine_signal_wakeup_source(runtime, (unsigned char)ready_mask);
}

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
}

static void proton_engine_browser_signal(void *user_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)user_data;
  proton_engine_signal_wait_source(
      window != NULL ? window->runtime : NULL, PROTON_WAIT_EVENT);
}

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

static void proton_engine_log_to_env(const char *env_name,
                                     const char *format,
                                     va_list args) {
  wchar_t wide_env_name[128] = {0};
  if (MultiByteToWideChar(CP_UTF8, 0, env_name, -1, wide_env_name,
                          (int)(sizeof(wide_env_name) /
                                sizeof(wide_env_name[0]))) <= 0) {
    return;
  }
  wchar_t wide_path[4096] = {0};
  DWORD written = GetEnvironmentVariableW(
      wide_env_name, wide_path,
      (DWORD)(sizeof(wide_path) / sizeof(wide_path[0])));
  if (written == 0 ||
      written >= sizeof(wide_path) / sizeof(wide_path[0])) {
    return;
  }
  FILE *file = _wfopen(wide_path, L"ab");
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

static void proton_engine_log_runtime_wait_ready(uint32_t ready_mask,
                                                 uint32_t interest_mask) {
  LONG count = InterlockedIncrement(&g_proton_engine_runtime_wait_log_count);
  if (count <= 16) {
    proton_engine_debug_log("runtime_wait ready mask=%u interest=%u",
                            ready_mask, interest_mask);
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

static int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime,
    char *request_json) {
  if (runtime == NULL || request_json == NULL) {
    return 0;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_BRIDGE_REQUEST);
  if (event == NULL) {
    return 0;
  }
  event->text_a = request_json;
  if (proton_event_try_publish(event)) {
    return 1;
  }
  event->text_a = NULL;
  proton_event_destroy(event);
  return 0;
}

static int proton_engine_runtime_enqueue_bridge_cancellation(
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

static int proton_engine_browser_id(cef_browser_t *browser) {
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
  int browser_id = proton_engine_browser_id(browser);
  if (browser_id == 0) {
    return NULL;
  }
  for (proton_engine_window_t *window = g_proton_engine_windows;
       window != NULL; window = window->next) {
    if (window->browser_id == browser_id) {
      return window;
    }
  }
  return NULL;
}

cef_browser_t *proton_engine_window_browser(proton_engine_window_t *window) {
  return window != NULL ? window->browser : NULL;
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
  return proton_engine_find_view_by_browser_id(
      proton_engine_browser_id(browser));
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
  if (runtime == NULL && g_proton_engine_windows != NULL) {
    runtime = g_proton_engine_windows->runtime;
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
  if (runtime == NULL && g_proton_engine_windows != NULL) {
    runtime = g_proton_engine_windows->runtime;
  }
  if (runtime == NULL) {
    free(root);
    return;
  }
  runtime->asset_root = root;
}

static proton_engine_view_t *proton_engine_find_view_by_browser_id(
    int browser_id) {
  if (browser_id == 0 || !g_proton_engine_window_lock_initialized) {
    return NULL;
  }
  proton_engine_view_t *found = NULL;
  EnterCriticalSection(&g_proton_engine_window_lock);
  for (proton_engine_window_t *window = g_proton_engine_windows;
       window != NULL && found == NULL; window = window->next) {
    for (proton_engine_view_t *view = window->views; view != NULL;
         view = view->next) {
      if (view->browser_id == browser_id) {
        found = view;
        break;
      }
    }
  }
  LeaveCriticalSection(&g_proton_engine_window_lock);
  return found;
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

static int proton_engine_bridge_pending_cancel(
    proton_engine_runtime_t *runtime,
    int browser_id,
    int renderer_pending_id,
    const char *page_instance) {
  if (page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  proton_engine_bridge_pending_t **cursor = &g_proton_engine_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        pending->renderer_pending_id == renderer_pending_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      if (!proton_engine_runtime_enqueue_bridge_cancellation(runtime,
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
  proton_engine_bridge_pending_t **cursor =
      &g_proton_engine_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      if (!proton_engine_runtime_enqueue_bridge_cancellation(runtime,
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
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id) {
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(
          runtime, pending->request_id);
      proton_engine_bridge_pending_free(pending);
      removed_pending++;
      continue;
    }
    cursor = &pending->next;
  }
  proton_engine_debug_log(
      "bridge_pending_remove_browser browser=%d pending=%llu",
      browser_id, (unsigned long long)removed_pending);
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

static void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar) {
  (void)self;
  proton_engine_register_app_custom_schemes(registrar);
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
  return proton_engine_register_app_scheme_factory(
      &g_proton_engine_scheme_factory.factory);
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
  int browser_id = proton_engine_browser_id(browser);
  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  proton_engine_verbose_log("v8_invoke_frame browser=%d url=%s", browser_id,
                            proton_engine_log_url(frame_url));
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
  int ok = proton_engine_send_bridge_request_to_browser(
      frame, action, pending_id, op, payload_json, page_instance);
  proton_engine_verbose_log("v8_invoke pending=%d browser=%d ok=%d op=%s",
                            pending_id, browser_id, ok, op != NULL ? op : "");
  if (!ok) {
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
  proton_engine_verbose_log("browser_bridge_request browser=%d pending=%d op=%s",
                            proton_engine_browser_id(browser),
                            renderer_pending_id, op != NULL ? op : "");

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
  // A bare --disable-gpu still launches a GPU process for SwiftShader, and
  // that process dies on display-limited CI runners (no usable D3D device),
  // which FATALs the browser. Disabling GPU compositing keeps presentation
  // on the CPU in the browser process, so no GPU process is needed for
  // window display.
  proton_engine_append_switch(command_line, "disable-gpu-compositing");
  // Keep the GPU service out of the browser process. With CEF 147,
  // --in-process-gpu can intermittently block cef_shutdown; CI selects
  // SwiftShader through ANGLE_DEFAULT_PLATFORM when hardware GPU is absent.
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
      (cef_base_ref_counted_t *)
          &g_proton_engine_life_span_handler.handler.base,
      sizeof(g_proton_engine_life_span_handler.handler),
      &g_proton_engine_life_span_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_drag_handler.handler.base,
      sizeof(g_proton_engine_drag_handler.handler),
      &g_proton_engine_drag_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_request_handler.handler.base,
      sizeof(g_proton_engine_request_handler.handler),
      &g_proton_engine_request_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_download_handler.handler.base,
      sizeof(g_proton_engine_download_handler.handler),
      &g_proton_engine_download_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_permission_handler.handler.base,
      sizeof(g_proton_engine_permission_handler.handler),
      &g_proton_engine_permission_handler.refs);
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_render_handler.handler.base,
      sizeof(g_proton_engine_render_handler.handler),
      &g_proton_engine_render_handler.refs);
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
  g_proton_engine_life_span_handler.handler.on_before_popup =
      proton_engine_on_before_popup;
  g_proton_engine_life_span_handler.handler.on_before_close =
      proton_engine_on_before_close;
  g_proton_engine_life_span_handler.handler.do_close = proton_engine_do_close;
  g_proton_engine_drag_handler.handler.on_draggable_regions_changed =
      proton_engine_on_draggable_regions_changed;
  g_proton_engine_request_handler.handler.on_render_process_terminated =
      proton_engine_on_render_process_terminated;
  g_proton_engine_request_handler.handler.on_before_browse =
      proton_engine_on_before_browse;
  g_proton_engine_request_handler.handler.on_certificate_error =
      proton_engine_on_certificate_error;
  g_proton_engine_download_handler.handler.can_download =
      proton_engine_can_download;
  g_proton_engine_download_handler.handler.on_before_download =
      proton_engine_on_before_download;
  g_proton_engine_download_handler.handler.on_download_updated =
      proton_engine_on_download_updated;
  g_proton_engine_permission_handler.handler.on_request_media_access_permission =
      proton_engine_on_media_permission;
  g_proton_engine_render_handler.handler.get_view_rect =
      proton_engine_osr_get_view_rect;
  g_proton_engine_render_handler.handler.get_screen_info =
      proton_engine_osr_get_screen_info;
  g_proton_engine_render_handler.handler.on_popup_show =
      proton_engine_osr_on_popup_show;
  g_proton_engine_render_handler.handler.on_popup_size =
      proton_engine_osr_on_popup_size;
  g_proton_engine_render_handler.handler.on_paint = proton_engine_osr_on_paint;
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_proton_engine_display_handler.handler.base,
      sizeof(g_proton_engine_display_handler.handler),
      &g_proton_engine_display_handler.refs);
  g_proton_engine_display_handler.handler.on_title_change =
      proton_engine_on_title_change;
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
  if (window->headless) {
    if (host->was_resized != NULL) {
      host->was_resized(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
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
  case PROTON_ENGINE_WM_DESTROY_SELF:
    // Self-destruction deferred from OnBeforeClose; the owning engine window
    // may already be freed, so only the HWND is touched here.
    DestroyWindow(hwnd);
    return 0;
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
    if (window != NULL) {
      bool handled = false;
      MINMAXINFO *minmax = (MINMAXINFO *)lparam;
      if (window->titlebar_overlay) {
      HMONITOR monitor =
          MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info;
      memset(&monitor_info, 0, sizeof(monitor_info));
      monitor_info.cbSize = sizeof(monitor_info);
      if (monitor != NULL && GetMonitorInfoW(monitor, &monitor_info)) {
        minmax->ptMaxPosition.x =
            monitor_info.rcWork.left - monitor_info.rcMonitor.left;
        minmax->ptMaxPosition.y =
            monitor_info.rcWork.top - monitor_info.rcMonitor.top;
        minmax->ptMaxSize.x =
            monitor_info.rcWork.right - monitor_info.rcWork.left;
        minmax->ptMaxSize.y =
            monitor_info.rcWork.bottom - monitor_info.rcWork.top;
          handled = true;
        }
      }
      if (window->size_hint == 1 || window->size_hint == 2) {
        minmax->ptMinTrackSize.x = window->width;
        minmax->ptMinTrackSize.y = window->height;
        handled = true;
      }
      if (window->size_hint == 1 || window->size_hint == 3) {
        minmax->ptMaxTrackSize.x = window->width;
        minmax->ptMaxTrackSize.y = window->height;
        handled = true;
      }
      if (handled) {
        return 0;
      }
    }
    break;
  case WM_DPICHANGED:
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
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
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
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
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    return 0;
  case WM_MOVE:
  case WM_DISPLAYCHANGE:
  case WM_THEMECHANGED:
  case WM_SETTINGCHANGE:
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    break;
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
      if (window->close_interception_enabled &&
          !window->close_interception_bypass) {
        if (!window->close_request_pending) {
          window->close_request_id++;
          if (window->close_request_id == 0) {
            window->close_request_id = 1;
          }
          window->close_request_pending = 1;
          proton_engine_signal_wait_source(window->runtime,
                                           PROTON_WAIT_PLATFORM);
        }
        return 0;
      }
      window->close_interception_bypass = 0;
      if (window->browser != NULL) {
        cef_browser_host_t *host = window->browser->get_host(window->browser);
        if (host != NULL) {
          int allow_close = 0;
          if (host->is_ready_to_be_closed != NULL &&
              host->is_ready_to_be_closed(host)) {
            allow_close = 1;
          } else if (host->try_close_browser != NULL) {
            allow_close = host->try_close_browser(host);
          } else if (!window->browser_close_requested) {
            host->close_browser(host, 0);
          }
          window->browser_close_requested = 1;
          proton_engine_debug_log(
              "window_wm_close_browser browser=%d allow=%d",
              window->browser_id, allow_close);
          host->base.release((cef_base_ref_counted_t *)host);
          if (!allow_close) {
            return 0;
          }
        }
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
static cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self);
static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self);
static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self);
static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self);
static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self);
static cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self);

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
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
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
  (void)self;
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
    proton_engine_view_t *view = proton_engine_find_view_by_browser_id(
        proton_engine_browser_id(browser));
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

static int CEF_CALLBACK proton_engine_client_release(
    cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  LONG value = InterlockedDecrement(&refs->refs);
  if (value <= 0) {
    free(base);
    return 1;
  }
  return 0;
}

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
  // The client must outlive the browser: CEF releases its own reference only
  // after OnBeforeClose returns, so ownership is tracked by the refcount and
  // the final release frees the allocation instead of an eager free().
  client->client.base.release = proton_engine_client_release;
  client->client.on_process_message_received =
      proton_engine_client_on_process_message_received;
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
  return client;
}

static void proton_engine_window_free(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_window_list_remove(window);
  proton_engine_window_free_views(window);
  if (window->hwnd != NULL) {
    // A deferred destroy may still be queued for this frame; detach the
    // window pointer so the message never dereferences the freed struct.
    SetWindowLongPtrW(window->hwnd, GWLP_USERDATA, 0);
  }
  if (window->client != NULL) {
    // Drop only the engine's reference. CEF releases its client reference
    // after OnBeforeClose, and the last release frees the client.
    cef_base_ref_counted_t *client_base =
        (cef_base_ref_counted_t *)window->client;
    ((proton_engine_client_t *)window->client)->window = NULL;
    window->client = NULL;
    client_base->release(client_base);
  }
  free(window->html_url);
  free(window->html);
  free(window->bridge_config_json);
  proton_browser_session_destroy(window->browser_session);
  free(window->draggable_regions);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
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
    const cef_popup_features_t *popup_features,
    cef_window_info_t *window_info,
    cef_client_t **client,
    cef_browser_settings_t *settings,
    cef_dictionary_value_t **extra_info,
    int *no_javascript_access) {
  (void)self;
  (void)frame;
  (void)popup_id;
  (void)target_frame_name;
  (void)popup_features;
  (void)window_info;
  (void)client;
  (void)settings;
  (void)extra_info;
  (void)no_javascript_access;
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  return proton_browser_session_before_popup(
      window != NULL ? window->browser_session : NULL, target_url,
      target_disposition, user_gesture);
}

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view != NULL) {
    proton_engine_runtime_t *runtime = view->window->runtime;
    proton_engine_debug_log("view_browser_before_close browser=%d",
                            view->browser_id);
    view->browser_before_close_seen = 1;
    view->closed = 1;
    view->hwnd = NULL;
    if (view->browser != NULL) {
      proton_engine_browser_release(view->browser);
      view->browser = NULL;
    }
    // A page-initiated close (JS window.close) reaches here without a prior
    // engine destroy; let the cleanup state machine finish so the struct can
    // be reclaimed with its owning window.
    view->finalize_after_browser_close = 1;
    proton_engine_view_finalize_if_ready(view);
    proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
    return;
  }
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  if (window == NULL) {
    return;
  }
  proton_engine_debug_log("browser_before_close browser=%d",
                          window->browser_id);
  proton_engine_bridge_pending_remove_browser(window->runtime,
                                              window->browser_id);
  if (window->browser != NULL) {
    proton_engine_browser_release(window->browser);
    window->browser = NULL;
  }
  if (!window->closed) {
    proton_engine_debug_log("window_closed browser=%d", window->browser_id);
  }
  window->closed = 1;
  window->browser_close_requested = 1;
  if (window->hwnd != NULL) {
    // CEF keeps unwinding the browser teardown after this callback returns,
    // and on the external message pump route it can still touch frame-window
    // state. Defer the frame destruction to a later pump instead of tearing
    // it down inline here.
    PostMessageW(window->hwnd, PROTON_ENGINE_WM_DESTROY_SELF, 0, 0);
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  proton_engine_window_finalize_if_ready(window);
}

static cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_life_span_handler.handler;
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
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame) && url != NULL &&
        strcmp(url, "about:blank") != 0) {
      proton_view_events_navigated(view->events, url);
      proton_view_events_loading_changed(view->events, 1);
      proton_engine_signal_wait_source(view->window->runtime,
                                       PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
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
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame)) {
      proton_view_events_loading_changed(view->events, 0);
      proton_engine_signal_wait_source(view->window->runtime,
                                       PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
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
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame)) {
      proton_view_events_load_failed(view->events, url, (int32_t)errorCode,
                                     text);
      proton_engine_signal_wait_source(view->window->runtime,
                                       PROTON_WAIT_EVENT);
    }
    free(text);
    free(url);
    return;
  }
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

static int CEF_CALLBACK proton_engine_on_before_browse(
    cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
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
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
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
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  return proton_browser_session_can_download(
      window != NULL ? window->browser_session : NULL);
}

static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  return proton_browser_session_before_download(
      window != NULL ? window->browser_session : NULL, download_item,
      suggested_name, callback);
}

static void CEF_CALLBACK proton_engine_on_download_updated(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
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
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  return proton_browser_session_media_permission(
      window != NULL ? window->browser_session : NULL, requesting_origin,
      requested_permissions, callback);
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

static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_download_handler.handler;
}

static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_permission_handler.handler;
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
  g_proton_engine_render_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_proton_engine_render_handler.handler);
  return &g_proton_engine_render_handler.handler;
}

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
  if (window == NULL || window->client == NULL ||
      (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  int browser_width = window->width;
  int browser_height = window->height;
  RECT rect = {0};
  if (!window->headless && GetClientRect(window->hwnd, &rect)) {
    browser_width = rect.right - rect.left;
    browser_height = rect.bottom - rect.top;
  }

  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    window_info.parent_window = window->hwnd;
    window_info.style =
        WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
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
  window->browser_id = proton_engine_browser_id(window->browser);
  proton_engine_verbose_log(
      "create_browser thread=%lu id=%d initial_url=%s size=%dx%d",
      GetCurrentThreadId(), window->browser_id,
      proton_engine_log_url(initial_url), browser_width, browser_height);
  proton_engine_resize_browser(window, browser_width, browser_height);
  return PROTON_OK;
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
  int exit_code = cef_execute_process(&args, &g_proton_engine_app.app, NULL);
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
  settings.remote_debugging_port = config.remote_debugging_port;
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

  if (!cef_initialize(&args, &settings, &g_proton_engine_app.app, NULL)) {
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
  if (!g_proton_cef_shutdown_registered) {
    atexit(proton_engine_cef_shutdown);
    g_proton_cef_shutdown_registered = 1;
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

static void proton_engine_close_wakeup_source(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL || !runtime->wakeup_lock_initialized) {
    return;
  }
  EnterCriticalSection(&runtime->wakeup_lock);
  HANDLE wakeup_write = runtime->wakeup_write;
  runtime->wakeup_write = NULL;
  runtime->wakeup_active = 0;
  runtime->wakeup_path[0] = '\0';
  LeaveCriticalSection(&runtime->wakeup_lock);
  if (wakeup_write != NULL) {
    DisconnectNamedPipe(wakeup_write);
    CloseHandle(wakeup_write);
  }
}

static void proton_engine_dispose_runtime_state(
    proton_engine_runtime_t *runtime) {
  proton_engine_close_wakeup_source(runtime);
  proton_engine_bridge_pending_clear_all();
  if (runtime->wakeup_lock_initialized) {
    DeleteCriticalSection(&runtime->wakeup_lock);
    runtime->wakeup_lock_initialized = 0;
  }
  proton_engine_release_pump_event();
  proton_engine_reset_scheduled_pump();
  if (g_proton_engine_active_runtime == runtime) {
    g_proton_engine_active_runtime = NULL;
  }
  g_proton_cef_runtime_active = 0;
  free(runtime->asset_root);
  free(runtime);
}

static int32_t proton_engine_drain_browser_closes(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len) {
  while (g_proton_engine_windows != NULL) {
    int32_t status = proton_engine_runtime_do_message_loop_work(
        runtime, error, error_len);
    if (status != PROTON_OK || g_proton_engine_windows == NULL) {
      return status;
    }
    uint32_t ready_mask = PROTON_WAIT_NONE;
    status = proton_engine_runtime_wait(
        runtime, PROTON_WAIT_PLATFORM, INFINITE, &ready_mask, error,
        error_len);
    if (status != PROTON_OK) {
      return status;
    }
  }
  return PROTON_OK;
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
    int32_t status =
        proton_engine_drain_browser_closes(runtime, error, error_len);
    if (status != PROTON_OK) {
      return status;
    }
    // Flush deferred frame destruction posted by OnBeforeClose so no frame
    // window outlives the browser teardown.
    status = proton_engine_runtime_do_message_loop_work(runtime, error,
                                                        error_len);
    if (status != PROTON_OK) {
      return status;
    }
    proton_engine_cef_shutdown();
    runtime->owns_cef_runtime = 0;
  }
  proton_engine_dispose_runtime_state(runtime);
  /* The e2e suite uses this as proof that native shutdown completed. */
  proton_engine_debug_log("runtime_destroy_complete");
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
  static int log_count = 0;
  if (log_count < 8) {
    proton_engine_verbose_log("do_message_loop_work thread=%lu",
                              GetCurrentThreadId());
    log_count++;
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
    proton_engine_log_runtime_wait_ready(ready_mask, interest_mask);
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

int32_t proton_engine_runtime_prepare_wakeup_source(
    proton_engine_runtime_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len,
                              "out_required_len is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  EnterCriticalSection(&runtime->wakeup_lock);
  if (runtime->wakeup_write == NULL) {
    LONG source_id = InterlockedIncrement(&g_proton_engine_wakeup_source_id);
    snprintf(runtime->wakeup_path, sizeof(runtime->wakeup_path),
             "\\\\.\\pipe\\proton.runtime.%lu.%ld",
             (unsigned long)GetCurrentProcessId(), (long)source_id);
    wchar_t wide_path[256] = {0};
    proton_engine_utf8_to_wide(
        runtime->wakeup_path, wide_path,
        (int)(sizeof(wide_path) / sizeof(wide_path[0])));
    runtime->wakeup_write = CreateNamedPipeW(
        wide_path, PIPE_ACCESS_OUTBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT, 1, 4096, 4096, 0,
        NULL);
    if (runtime->wakeup_write == INVALID_HANDLE_VALUE) {
      runtime->wakeup_write = NULL;
      runtime->wakeup_path[0] = '\0';
      LeaveCriticalSection(&runtime->wakeup_lock);
      proton_engine_set_message(error, error_len,
                                "failed to create runtime wakeup source");
      return PROTON_ERR_PLATFORM;
    }
  }
  size_t required = strlen(runtime->wakeup_path);
  *out_required_len = (int32_t)required;
  if (buffer == NULL || buffer_len <= (int32_t)required) {
    LeaveCriticalSection(&runtime->wakeup_lock);
    proton_engine_set_message(error, error_len,
                              "runtime wakeup source buffer is too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, runtime->wakeup_path, required + 1);
  LeaveCriticalSection(&runtime->wakeup_lock);
  return PROTON_OK;
}

int32_t proton_engine_runtime_activate_wakeup_source(
    proton_engine_runtime_t *runtime, char *error, size_t error_len) {
  if (runtime == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  EnterCriticalSection(&runtime->wakeup_lock);
  if (runtime->wakeup_write == NULL) {
    LeaveCriticalSection(&runtime->wakeup_lock);
    proton_engine_set_message(error, error_len,
                              "runtime wakeup source is not prepared");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  BOOL connected = ConnectNamedPipe(runtime->wakeup_write, NULL);
  DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
  if (!connected && connect_error != ERROR_PIPE_CONNECTED) {
    LeaveCriticalSection(&runtime->wakeup_lock);
    proton_engine_set_message(error, error_len,
                              "runtime wakeup source has no reader");
    return PROTON_ERR_PLATFORM;
  }
  runtime->wakeup_active = 1;
  LeaveCriticalSection(&runtime->wakeup_lock);
  proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
  return PROTON_OK;
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
int32_t proton_engine_runtime_set_menu(
    proton_engine_runtime_t *runtime, const proton_menu_bar_t *menu_bar,
    char *error, size_t error_len) {
  (void)runtime;
  (void)menu_bar;
  proton_engine_set_message(error, error_len,
                            "native app menus are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
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

int32_t proton_engine_window_create(
    proton_engine_runtime_t *runtime,
    const proton_engine_window_config_t *input_config,
    proton_engine_window_t **out_window, char *error, size_t error_len) {
  if (out_window == NULL) {
    proton_engine_set_message(error, error_len, "out_window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_window = NULL;
  if (runtime == NULL || input_config == NULL || !g_proton_cef_initialized) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }

  proton_engine_window_config_t config = *input_config;

  if (runtime->headless && config.titlebar_overlay) {
    proton_engine_set_message(
        error, error_len,
        "titlebar overlay is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (!runtime->headless) {
    proton_engine_register_window_class();
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "failed to allocate window");
    return PROTON_ERR_ENGINE;
  }
  window->width = config.width;
  window->height = config.height;
  window->headless = runtime->headless;
  window->size_hint = config.size_hint;
  window->titlebar_overlay = config.titlebar_overlay;
  window->zoom_percent = 100;
  window->windowed_placement.length = sizeof(WINDOWPLACEMENT);
  window->runtime = runtime;
  window->bridge_config_json =
      config.bridge_config_json != NULL
          ? proton_engine_strdup(config.bridge_config_json)
          : NULL;
  window->max_bridge_payload_bytes = config.max_bridge_payload_bytes;
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, window);
  if (window->browser_session == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser session");
    return PROTON_ERR_ENGINE;
  }
  window->client = (cef_client_t *)proton_engine_client_new(window);
  if (window->client == NULL) {
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  if (!window->headless) {
    wchar_t wide_title[512];
    proton_engine_utf8_to_wide(
        config.title, wide_title,
        (int)(sizeof(wide_title) / sizeof(wide_title[0])));
    DWORD window_style = WS_OVERLAPPEDWINDOW;
    if (window->size_hint == 1) {
      window_style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    if (window->titlebar_overlay) {
      window_style |= WS_CLIPCHILDREN;
    }
    window->hwnd = CreateWindowExW(
        0, PROTON_ENGINE_WINDOW_CLASS, wide_title, window_style, CW_USEDEFAULT,
        CW_USEDEFAULT, config.width, config.height, NULL, NULL,
        GetModuleHandleW(NULL), window);
    if (window->hwnd == NULL) {
      ((cef_base_ref_counted_t *)window->client)
          ->release((cef_base_ref_counted_t *)window->client);
      proton_browser_session_destroy(window->browser_session);
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
  }

  int32_t status =
      proton_engine_window_create_browser(window, config.initial_url, error,
                                          error_len);
  if (status != PROTON_OK) {
    if (window->hwnd != NULL) {
      DestroyWindow(window->hwnd);
    }
    ((cef_base_ref_counted_t *)window->client)
        ->release((cef_base_ref_counted_t *)window->client);
    free(window->html_url);
    free(window->html);
    free(window->bridge_config_json);
    proton_browser_session_destroy(window->browser_session);
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
  if (window == NULL) {
    return PROTON_OK;
  }
  proton_engine_dialog_cancel_window(window);
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    window->destroy_requested = 1;
    proton_engine_window_close_views(window);
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    window->browser_close_requested = 1;
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }
  window->destroy_requested = 1;
  proton_engine_window_close_views(window);
  if (window->hwnd != NULL) {
    DestroyWindow(window->hwnd);
    window->hwnd = NULL;
  }
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless && window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  window->close_interception_bypass = 0;
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
    ShowWindow(window->hwnd, SW_SHOW);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
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
    ShowWindow(window->hwnd, SW_HIDE);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host == NULL) {
        proton_engine_set_message(error, error_len,
                                  "browser host is not available for close");
        return PROTON_ERR_ENGINE;
      }
      window->browser_close_requested = 1;
      host->close_browser(host, 0);
      host->base.release((cef_base_ref_counted_t *)host);
    } else {
      window->closed = 1;
      proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
    }
  } else {
    PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->set_focus(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    SetForegroundWindow(window->hwnd);
    SetFocus(window->hwnd);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
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
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
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
  if (window->headless) {
    proton_engine_resize_browser(window, width, height);
  } else {
    SetWindowPos(window->hwnd, NULL, 0, 0, width, height,
                 SWP_NOMOVE | SWP_NOZORDER);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {
  if (window == NULL || action == NULL ||
      (!window->headless && window->hwnd == NULL)) {
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
    proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
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
    ShowWindow(window->hwnd, SW_MINIMIZE);
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    ShowWindow(window->hwnd, SW_MAXIMIZE);
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    if (window->fullscreen) {
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)window->windowed_style);
      SetWindowPlacement(window->hwnd, &window->windowed_placement);
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
      window->fullscreen = 0;
    }
    ShowWindow(window->hwnd, SW_RESTORE);
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN:
    if (action->value != 0 && !window->fullscreen) {
      window->windowed_style =
          (DWORD)GetWindowLongW(window->hwnd, GWL_STYLE);
      window->windowed_placement.length = sizeof(WINDOWPLACEMENT);
      GetWindowPlacement(window->hwnd, &window->windowed_placement);
      HMONITOR monitor =
          MonitorFromWindow(window->hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
      if (monitor == NULL || !GetMonitorInfoW(monitor, &info)) {
        proton_engine_set_message(error, error_len,
                                  "failed to read monitor geometry");
        return PROTON_ERR_PLATFORM;
      }
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)(window->windowed_style &
                            ~WS_OVERLAPPEDWINDOW));
      SetWindowPos(window->hwnd, HWND_TOP, info.rcMonitor.left,
                   info.rcMonitor.top,
                   info.rcMonitor.right - info.rcMonitor.left,
                   info.rcMonitor.bottom - info.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      window->fullscreen = 1;
    } else if (action->value == 0 && window->fullscreen) {
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)window->windowed_style);
      SetWindowPlacement(window->hwnd, &window->windowed_placement);
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
      window->fullscreen = 0;
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_POSITION:
    SetWindowPos(window->hwnd, NULL, action->x, action->y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    break;
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    SetWindowPos(window->hwnd,
                 action->value != 0 ? HWND_TOPMOST : HWND_NOTOPMOST,
                 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    window->always_on_top = action->value != 0;
    break;
  default:
    proton_engine_set_message(error, error_len, "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

static int proton_engine_windows_theme(void) {
  DWORD light = 1;
  DWORD size = sizeof(light);
  LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light, &size);
  if (status != ERROR_SUCCESS) {
    return 0;
  }
  return light != 0 ? 1 : 2;
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
  if (window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  RECT frame = {0};
  GetWindowRect(window->hwnd, &frame);
  HMONITOR monitor =
      MonitorFromWindow(window->hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  if (monitor != NULL) {
    GetMonitorInfoW(monitor, &info);
  }
  out_state->x = frame.left;
  out_state->y = frame.top;
  out_state->width = frame.right - frame.left;
  out_state->height = frame.bottom - frame.top;
  out_state->monitor_x = info.rcMonitor.left;
  out_state->monitor_y = info.rcMonitor.top;
  out_state->monitor_width = info.rcMonitor.right - info.rcMonitor.left;
  out_state->monitor_height = info.rcMonitor.bottom - info.rcMonitor.top;
  out_state->work_x = info.rcWork.left;
  out_state->work_y = info.rcWork.top;
  out_state->work_width = info.rcWork.right - info.rcWork.left;
  out_state->work_height = info.rcWork.bottom - info.rcWork.top;
  UINT dpi = GetDpiForWindow(window->hwnd);
  out_state->scale_factor_percent =
      dpi > 0 ? (int32_t)((dpi * 100 + 48) / 96) : 100;
  out_state->visible = IsWindowVisible(window->hwnd) ? 1 : 0;
  out_state->focused = GetForegroundWindow() == window->hwnd ? 1 : 0;
  out_state->minimized = IsIconic(window->hwnd) ? 1 : 0;
  out_state->maximized = IsZoomed(window->hwnd) ? 1 : 0;
  out_state->fullscreen = window->fullscreen;
  out_state->always_on_top = window->always_on_top;
  out_state->theme = proton_engine_windows_theme();
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
    if (window->hwnd != NULL) {
      PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
    }
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
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

/* Installs `html` as the document served for `document_url` and, when an
   asset root is supplied, binds that root to the runtime's application
   origin. The document is not handed to CEF inline: the scheme factory reads
   it back out of the window when the navigation asks for it, which is what
   lets relative URLs resolve against the same origin. */
static int32_t proton_engine_window_load_document(
    proton_engine_window_t *window, const char *html,
    const char *document_url, const char *asset_root, char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  /* Held across the install so a document is never published without a frame
     to navigate with it. */
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  char *url = NULL;
  size_t html_len = 0;
  int32_t status = proton_engine_window_install_document(
      window, html, document_url, asset_root, &url, &html_len, error,
      error_len);
  if (status != PROTON_OK) {
    frame->base.release((cef_base_ref_counted_t *)frame);
    return status;
  }

  cef_string_t url_value = {0};
  proton_engine_set_string(&url_value, url);
  proton_engine_verbose_log(
      "load_document thread=%lu browser=%d document_url=%s bytes=%llu",
      GetCurrentThreadId(), window->browser_id, proton_engine_log_url(url),
      (unsigned long long)html_len);
  frame->load_url(frame, &url_value);
  cef_string_clear(&url_value);
  frame->base.release((cef_base_ref_counted_t *)frame);
  free(url);
  return PROTON_OK;
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
  cef_string_t url = {0};
  proton_engine_set_string(&code, script);
  proton_engine_set_string(&url, "proton://eval/");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
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

proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window) {
  return window != NULL ? window->public_window_id : PROTON_INVALID_HANDLE;
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

/* Dialog HWNDs stay on the runtime owner thread. The host loop dispatches
   their messages, and completion crosses into MoonBit through the wake source. */
typedef struct proton_engine_win_dialog_request {
  int64_t id;
  proton_engine_runtime_t *runtime;
  proton_engine_window_t *window;
  wchar_t *title;
  wchar_t *message;
  wchar_t *ok_label;
  HWND dialog;
  HWND icon_control;
  HWND message_control;
  HWND ok_button;
  HWND parent;
  int parent_was_enabled;
  int completed;
  int32_t level;
  struct proton_engine_win_dialog_request *next;
} proton_engine_win_dialog_request_t;

static int64_t g_next_dialog_id = 1;
static proton_engine_win_dialog_request_t *g_dialog_requests = NULL;

static wchar_t *proton_engine_dialog_text(const char *text, int32_t text_len) {
  if (text == NULL || text_len <= 0) {
    return (wchar_t *)calloc(1, sizeof(wchar_t));
  }
  int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text,
                                     text_len, NULL, 0);
  if (required <= 0) {
    return NULL;
  }
  wchar_t *result =
      (wchar_t *)calloc((size_t)required + 1, sizeof(wchar_t));
  if (result == NULL ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, text_len,
                          result, required) != required) {
    free(result);
    return NULL;
  }
  return result;
}

static proton_engine_win_dialog_request_t *proton_engine_dialog_find(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    int64_t id) {
  for (proton_engine_win_dialog_request_t *request = g_dialog_requests;
       request != NULL; request = request->next) {
    if (request->id == id && request->runtime == runtime &&
        request->window == window) {
      return request;
    }
  }
  return NULL;
}

static void proton_engine_dialog_free(
    proton_engine_win_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  free(request->title);
  free(request->message);
  free(request->ok_label);
  free(request);
}

static void proton_engine_dialog_remove(
    proton_engine_win_dialog_request_t *request) {
  proton_engine_win_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    if (*cursor == request) {
      *cursor = request->next;
      request->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void proton_engine_dialog_release_parent(
    proton_engine_win_dialog_request_t *request) {
  if (request->parent == NULL || !request->parent_was_enabled) {
    return;
  }
  for (proton_engine_win_dialog_request_t *other = g_dialog_requests;
       other != NULL; other = other->next) {
    if (other != request && other->parent == request->parent &&
        other->dialog != NULL && !other->completed) {
      other->parent_was_enabled = 1;
      request->parent_was_enabled = 0;
      return;
    }
  }
  if (IsWindow(request->parent)) {
    EnableWindow(request->parent, TRUE);
    SetForegroundWindow(request->parent);
  }
  request->parent_was_enabled = 0;
}

static int proton_engine_dialog_scale(HWND hwnd, int value) {
  HDC dc = GetDC(hwnd);
  int dpi = dc != NULL ? GetDeviceCaps(dc, LOGPIXELSX) : 96;
  if (dc != NULL) {
    ReleaseDC(hwnd, dc);
  }
  return MulDiv(value, dpi > 0 ? dpi : 96, 96);
}

static void proton_engine_dialog_layout(
    proton_engine_win_dialog_request_t *request) {
  if (request == NULL || request->dialog == NULL) {
    return;
  }
  RECT client;
  GetClientRect(request->dialog, &client);
  int margin = proton_engine_dialog_scale(request->dialog, 20);
  int icon_size = proton_engine_dialog_scale(request->dialog, 32);
  int gap = proton_engine_dialog_scale(request->dialog, 16);
  int button_width = proton_engine_dialog_scale(request->dialog, 88);
  int button_height = proton_engine_dialog_scale(request->dialog, 28);
  int button_y = client.bottom - margin - button_height;
  int message_x = margin + icon_size + gap;
  int message_width = client.right - message_x - margin;
  int message_height = button_y - margin - gap;
  MoveWindow(request->icon_control, margin, margin, icon_size, icon_size, TRUE);
  MoveWindow(request->message_control, message_x, margin, message_width,
             message_height, TRUE);
  MoveWindow(request->ok_button, client.right - margin - button_width,
             button_y, button_width, button_height, TRUE);
}

static LRESULT CALLBACK proton_engine_dialog_window_proc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  proton_engine_win_dialog_request_t *request =
      (proton_engine_win_dialog_request_t *)GetWindowLongPtrW(
          hwnd, GWLP_USERDATA);
  if (message == WM_NCCREATE) {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    request = (proton_engine_win_dialog_request_t *)create->lpCreateParams;
    if (request == NULL) {
      return FALSE;
    }
    request->dialog = hwnd;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)request);
  }
  if (request == NULL) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  switch (message) {
  case WM_CREATE: {
    HINSTANCE instance = GetModuleHandleW(NULL);
    request->icon_control = CreateWindowExW(
        0, L"STATIC", NULL, WS_CHILD | WS_VISIBLE | SS_ICON, 0, 0, 0, 0,
        hwnd, NULL, instance, NULL);
    request->message_control = CreateWindowExW(
        0, L"STATIC", request->message,
        WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, hwnd, NULL, instance,
        NULL);
    request->ok_button = CreateWindowExW(
        0, L"BUTTON", request->ok_label,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 0, 0, 0, 0,
        hwnd, (HMENU)(INT_PTR)IDOK, instance, NULL);
    if (request->icon_control == NULL || request->message_control == NULL ||
        request->ok_button == NULL) {
      return -1;
    }
    HICON icon = LoadIconW(
        NULL, request->level == 2
                  ? IDI_ERROR
                  : (request->level == 1 ? IDI_WARNING : IDI_INFORMATION));
    SendMessageW(request->icon_control, STM_SETICON, (WPARAM)icon, 0);
    HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
    SendMessageW(request->message_control, WM_SETFONT, (WPARAM)font, TRUE);
    SendMessageW(request->ok_button, WM_SETFONT, (WPARAM)font, TRUE);
    return 0;
  }
  case WM_SIZE:
    proton_engine_dialog_layout(request);
    return 0;
  case WM_COMMAND:
    if (LOWORD(wparam) == IDOK && HIWORD(wparam) == BN_CLICKED) {
      DestroyWindow(hwnd);
      return 0;
    }
    break;
  case WM_CLOSE:
    DestroyWindow(hwnd);
    return 0;
  case WM_DESTROY:
    request->dialog = NULL;
    request->completed = 1;
    proton_engine_dialog_release_parent(request);
    proton_engine_signal_wait_source(request->runtime, PROTON_WAIT_PLATFORM);
    return 0;
  case WM_NCDESTROY:
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    return DefWindowProcW(hwnd, message, wparam, lparam);
  default:
    break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static int proton_engine_register_dialog_class(void) {
  HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSEXW existing;
  memset(&existing, 0, sizeof(existing));
  existing.cbSize = sizeof(existing);
  if (GetClassInfoExW(instance, PROTON_ENGINE_DIALOG_CLASS, &existing)) {
    return 1;
  }
  WNDCLASSEXW window_class;
  memset(&window_class, 0, sizeof(window_class));
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = proton_engine_dialog_window_proc;
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursorW(NULL, IDC_ARROW);
  window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
  window_class.lpszClassName = PROTON_ENGINE_DIALOG_CLASS;
  return RegisterClassExW(&window_class) != 0;
}

static void proton_engine_center_dialog(HWND dialog, HWND parent) {
  RECT dialog_rect;
  RECT bounds;
  GetWindowRect(dialog, &dialog_rect);
  if (parent == NULL || !GetWindowRect(parent, &bounds)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &bounds, 0);
  }
  int width = dialog_rect.right - dialog_rect.left;
  int height = dialog_rect.bottom - dialog_rect.top;
  int x = bounds.left + ((bounds.right - bounds.left) - width) / 2;
  int y = bounds.top + ((bounds.bottom - bounds.top) - height) / 2;
  SetWindowPos(dialog, NULL, x, y, 0, 0,
               SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

static int32_t proton_engine_begin_message_dialog(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    const char *title_utf8, int32_t title_len, const char *message_utf8,
    int32_t message_len, int32_t level, int64_t *out_dialog, char *error,
    size_t error_len) {
  if (runtime == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog runtime and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  if (runtime->headless || (window != NULL && window->headless)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window != NULL && window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime->dialog_ok_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog label is not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_win_dialog_request_t *request =
      (proton_engine_win_dialog_request_t *)calloc(1, sizeof(*request));
  if (request == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }
  request->title = proton_engine_dialog_text(title_utf8, title_len);
  request->message = proton_engine_dialog_text(message_utf8, message_len);
  request->ok_label = proton_engine_dialog_text(
      runtime->dialog_ok_label, (int32_t)strlen(runtime->dialog_ok_label));
  if (request->title == NULL || request->message == NULL ||
      request->ok_label == NULL) {
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len, "dialog text is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  request->runtime = runtime;
  request->window = window;
  request->level = level;
  request->parent = window != NULL ? window->hwnd : NULL;
  request->parent_was_enabled =
      request->parent != NULL && IsWindowEnabled(request->parent);
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id <= 0) {
    g_next_dialog_id = 1;
  }
  request->next = g_dialog_requests;
  g_dialog_requests = request;
  if (!proton_engine_register_dialog_class()) {
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to register native dialog class");
    return PROTON_ERR_PLATFORM;
  }
  UINT dpi = request->parent != NULL ? GetDpiForWindow(request->parent) : 96;
  int width = MulDiv(460, dpi > 0 ? (int)dpi : 96, 96);
  int height = MulDiv(210, dpi > 0 ? (int)dpi : 96, 96);
  if (request->parent_was_enabled) {
    EnableWindow(request->parent, FALSE);
  }
  HWND dialog_window = CreateWindowExW(
      WS_EX_DLGMODALFRAME, PROTON_ENGINE_DIALOG_CLASS, request->title,
      WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, CW_USEDEFAULT,
      CW_USEDEFAULT, width, height, request->parent, NULL, GetModuleHandleW(NULL),
      request);
  if (dialog_window == NULL) {
    if (request->parent_was_enabled) {
      EnableWindow(request->parent, TRUE);
    }
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to create native message dialog");
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_center_dialog(dialog_window, request->parent);
  ShowWindow(dialog_window, SW_SHOW);
  SetForegroundWindow(dialog_window);
  SetFocus(request->ok_button);
  *out_dialog = request->id;
  return PROTON_OK;
}

static int32_t proton_engine_poll_message_dialog(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    int64_t dialog, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len, "out_required_len is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_required_len = 0;
  proton_engine_win_dialog_request_t *request =
      proton_engine_dialog_find(runtime, window, dialog);
  if (request == NULL) {
    proton_engine_set_message(error, error_len, "dialog request is unknown");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (!request->completed) {
    return PROTON_EVENT_NONE;
  }
  *out_required_len = 1;
  if (buffer == NULL || buffer_len < 1) {
    proton_engine_set_message(error, error_len, "dialog result buffer too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  buffer[0] = '\0';
  proton_engine_dialog_remove(request);
  proton_engine_dialog_free(request);
  return PROTON_OK;
}

static void proton_engine_dialog_cancel_matching(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    int match_window) {
  for (;;) {
    proton_engine_win_dialog_request_t *request = g_dialog_requests;
    while (request != NULL &&
           (request->runtime != runtime ||
            (match_window && request->window != window))) {
      request = request->next;
    }
    if (request == NULL) {
      return;
    }
    if (request->dialog != NULL) {
      DestroyWindow(request->dialog);
    }
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
  }
}

static void proton_engine_dialog_cancel_runtime(
    proton_engine_runtime_t *runtime) {
  proton_engine_dialog_cancel_matching(runtime, NULL, 0);
}

static void proton_engine_dialog_cancel_window(proton_engine_window_t *window) {
  if (window != NULL) {
    proton_engine_dialog_cancel_matching(window->runtime, window, 1);
  }
}

int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len) {
  return proton_engine_begin_message_dialog(
      runtime, NULL, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len);
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
  return proton_engine_begin_message_dialog(
      window != NULL ? window->runtime : NULL, window, title_utf8, title_len,
      message_utf8, message_len, level, out_dialog, error, error_len);
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
  // TODO: Implement the remaining Windows dialog kinds on the same async
  // request lifecycle instead of reintroducing synchronous native APIs.
  (void)window;
  (void)title_utf8;
  (void)title_len;
  (void)message_utf8;
  (void)message_len;
  (void)level;
  if (out_dialog != NULL) {
    *out_dialog = PROTON_INVALID_HANDLE;
  }
  proton_engine_set_message(
      error, error_len,
      "async confirm dialogs are not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
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

// MARK: - Web contents views
//
// A view is an extra child browser hosted inside a window's client area,
// following the Electron WebContentsView model: explicit top-left bounds,
// visibility, z-order, and an independent load target. Struct lifetime is
// owned by the window: views are only freed from proton_engine_window_free
// once every view has finalized, so native ABI view slots stay valid for the
// whole window lifetime. Close semantics mirror the macOS engine: do_close
// takes over from CEF's default (which would post WM_CLOSE to the frame
// window) and tears down the browser's child HWND instead.

static void proton_engine_view_list_add(proton_engine_window_t *window,
                                        proton_engine_view_t *view) {
  if (g_proton_engine_window_lock_initialized) {
    EnterCriticalSection(&g_proton_engine_window_lock);
  }
  view->next = window->views;
  window->views = view;
  if (g_proton_engine_window_lock_initialized) {
    LeaveCriticalSection(&g_proton_engine_window_lock);
  }
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
    if (view->client != NULL) {
      // Drop only the engine's reference; CEF's final release after
      // OnBeforeClose frees the client (guaranteed by the finalize gate).
      cef_base_ref_counted_t *client_base =
          (cef_base_ref_counted_t *)view->client;
      view->client->view = NULL;
      view->client = NULL;
      client_base->release(client_base);
    }
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
  view->hwnd = NULL;
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
  proton_engine_window_free(window);
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

// Re-stacks view browser windows above the window's main browser view by
// ascending (z_order, native_id).
static void proton_engine_window_layout_views(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->hwnd != NULL && !view->closed) {
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
    if (view->hwnd != NULL && !view->closed) {
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
    SetWindowPos(order[i]->hwnd, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  free(order);
}

static int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view == NULL) {
    // Frame windows keep CEF's default close behavior (WM_CLOSE to the frame).
    return 0;
  }
  proton_engine_debug_log("view_browser_do_close browser=%d",
                          view->browser_id);
  // A view browser owns no top-level window; CEF's default would post
  // WM_CLOSE to the frame window and cancel the view close. Take over and
  // destroy the browser's child window, which completes the teardown via
  // WindowDestroyed.
  if (view->hwnd != NULL) {
    DestroyWindow(view->hwnd);
    view->hwnd = NULL;
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
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  if (view == NULL) {
    return;
  }
  char *title_utf8 = proton_engine_cef_string_to_utf8(title);
  proton_view_events_title_updated(view->events, title_utf8);
  free(title_utf8);
  proton_engine_signal_wait_source(view->window->runtime, PROTON_WAIT_EVENT);
}

static cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self) {
  (void)self;
  g_proton_engine_display_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_proton_engine_display_handler.handler);
  return &g_proton_engine_display_handler.handler;
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
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    window_info.parent_window = window->hwnd;
    window_info.style =
        WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
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
      view->hwnd = host->get_window_handle(host);
      if (!view->visible && view->hwnd != NULL) {
        ShowWindow(view->hwnd, SW_HIDE);
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

int32_t proton_engine_view_create(
    proton_engine_window_t *window,
    const proton_engine_view_config_t *input_config,
    proton_engine_view_t **out_view, char *error, size_t error_len) {
  if (out_view == NULL) {
    proton_engine_set_message(error, error_len, "out_view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_view = NULL;
  if (window == NULL || input_config == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and view config are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->closed) {
    proton_engine_set_message(error, error_len, "window is closed");
    return PROTON_ERR_DESTROYED;
  }
  proton_engine_view_config_t config = *input_config;
  int32_t status = PROTON_OK;

  proton_engine_view_t *view =
      (proton_engine_view_t *)calloc(1, sizeof(*view));
  if (view == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  view->window = window;
  view->native_id = g_proton_engine_next_view_native_id++;
  if (g_proton_engine_next_view_native_id == 0) {
    g_proton_engine_next_view_native_id = 1;
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
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
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
  } else if (view->hwnd != NULL) {
    SetWindowPos(view->hwnd, NULL, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
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
  } else if (view->hwnd != NULL) {
    ShowWindow(view->hwnd, view->visible ? SW_SHOW : SW_HIDE);
  }
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
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
  if (g_proton_engine_window_lock_initialized) {
    EnterCriticalSection(&g_proton_engine_window_lock);
  }
  free(view->html_url);
  free(view->html);
  view->html_url = url_copy;
  view->html = html_copy;
  view->html_len = strlen(html_copy);
  if (g_proton_engine_window_lock_initialized) {
    LeaveCriticalSection(&g_proton_engine_window_lock);
  }
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

void proton_engine_view_bind_public_id(proton_engine_view_t *view,
                                       proton_view_id_t public_view) {
  if (view != NULL && view->window != NULL) {
    proton_view_events_bind(view->events, public_view,
                            view->window->public_window_id);
  }
}

typedef struct {
  proton_engine_screen_info_t *screens;
  int32_t max_screens;
  int32_t count;
} proton_screen_enum_context_t;

static BOOL CALLBACK proton_screen_enum_callback(HMONITOR monitor, HDC hdc,
                                                  LPRECT clip_rect,
                                                  LPARAM param) {
  (void)hdc;
  (void)clip_rect;
  proton_screen_enum_context_t *ctx = (proton_screen_enum_context_t *)param;
  if (ctx->count >= ctx->max_screens) {
    return FALSE;
  }
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }
  proton_engine_screen_info_t *screen = &ctx->screens[ctx->count];
  screen->id = ctx->count;
  screen->x = info.rcMonitor.left;
  screen->y = info.rcMonitor.top;
  screen->width = info.rcMonitor.right - info.rcMonitor.left;
  screen->height = info.rcMonitor.bottom - info.rcMonitor.top;
  screen->work_x = info.rcWork.left;
  screen->work_y = info.rcWork.top;
  screen->work_width = info.rcWork.right - info.rcWork.left;
  screen->work_height = info.rcWork.bottom - info.rcWork.top;
  screen->is_primary = (info.dwFlags & MONITORINFOF_PRIMARY) ? 1 : 0;

  /* GetDpiForMonitor lives in shcore.dll; load it dynamically so the build
     does not require linking shcore.lib and stays compatible with older
     Windows where the export may be absent. */
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  HMODULE shcore = LoadLibraryW(L"shcore.dll");
  if (shcore != NULL) {
    typedef HRESULT(WINAPI *proton_get_dpi_for_monitor_proc)(HMONITOR, int,
                                                              UINT *, UINT *);
    proton_get_dpi_for_monitor_proc get_dpi =
        (proton_get_dpi_for_monitor_proc)GetProcAddress(shcore,
                                                        "GetDpiForMonitor");
    if (get_dpi != NULL) {
      get_dpi(monitor, 0, &dpi_x, &dpi_y);
    }
    FreeLibrary(shcore);
  }
  screen->scale_factor_percent = (int32_t)((dpi_x * 100 + 48) / 96);

  ctx->count++;
  return TRUE;
}

int32_t proton_engine_screen_enumerate(
    proton_engine_screen_info_t *out_screens,
    int32_t max_screens,
    int32_t *out_count,
    char *error,
    size_t error_len) {
  if (out_screens == NULL || out_count == NULL || max_screens <= 0) {
    proton_engine_set_message(error, error_len,
                              "out_screens, out_count are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = 0;
  proton_screen_enum_context_t ctx = {
      .screens = out_screens,
      .max_screens = max_screens,
      .count = 0,
  };
  /* EnumDisplayMonitors is safe to call from any thread; it snapshots the
     current monitor configuration without entering the UI message loop. */
  if (!EnumDisplayMonitors(NULL, NULL, proton_screen_enum_callback,
                           (LPARAM)&ctx)) {
    proton_engine_set_message(error, error_len,
                              "EnumDisplayMonitors failed");
    return PROTON_ERR_PLATFORM;
  }
  *out_count = ctx.count;
  return PROTON_OK;
}

#endif
