#ifndef PROTON_ENGINE_CEF_WIN_INTERNAL_H
#define PROTON_ENGINE_CEF_WIN_INTERNAL_H

/* Private contracts shared by the Windows engine translation units. */
#include "../../proton_engine.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/view_events.h"
#include "../cef_common/window_state.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "win_titlebar.h"

#define PROTON_ENGINE_WINDOW_CLASS L"ProtonNativeWindow"
#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
#define PROTON_ENGINE_WM_DESTROY_SELF (WM_USER + 0x31)
#define PROTON_ENGINE_WM_DESTROY_CHILD (WM_USER + 0x32)

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"

typedef struct proton_engine_client proton_engine_client_t;
typedef struct proton_engine_bridge_pending {
  int64_t request_id;
  int browser_id;
  int renderer_pending_id;
  char *page_instance;
  cef_frame_t *frame;
  struct proton_engine_bridge_pending *next;
} proton_engine_bridge_pending_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  /* Set once by the first asset document and never changed, so every window
     in a runtime resolves application resources against the same root. */
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
  char *bridge_config_json;
  int32_t max_bridge_payload_bytes;
  proton_engine_bridge_lifecycle_t bridge_lifecycle;
  int width;
  int height;
  int headless;
  int headless_hidden;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int size_hint;
  int resizable;
  int movable;
  int minimizable;
  int maximizable;
  int closable;
  int min_width;
  int min_height;
  int max_width;
  int max_height;
  double aspect_ratio;
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
  int finalize_queued;
  struct proton_engine_window *next;
};

void proton_engine_dialog_cancel_runtime(proton_engine_runtime_t *runtime);
void proton_engine_dialog_cancel_window(proton_engine_window_t *window);
void proton_engine_signal_wait_source(proton_engine_runtime_t *runtime,
                                      uint32_t ready_mask);
void proton_engine_browser_signal(void *user_data);
int proton_engine_browser_id(cef_browser_t *browser);
void proton_engine_browser_release(cef_browser_t *browser);
proton_engine_view_t *proton_engine_find_view_by_browser_id(int browser_id);
void proton_engine_window_defer_free(proton_engine_window_t *window);

cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self);
cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self);
cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self);

void proton_engine_view_handlers_init(void);
int CEF_CALLBACK proton_engine_do_close(cef_life_span_handler_t *self,
                                        cef_browser_t *browser);
void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title);
void proton_engine_window_finalize_if_ready(proton_engine_window_t *window);
void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);
void proton_engine_window_close_views(proton_engine_window_t *window);
void proton_engine_window_free_views(proton_engine_window_t *window);
void proton_engine_window_layout_views(proton_engine_window_t *window);

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
  proton_browser_session_t *browser_session;
  proton_view_events_t *events;
  int has_background_color;
  uint32_t background_color;
  int browser_close_requested;
  int browser_before_close_seen;
  int finalize_after_browser_close;
  int finalized;
  int closed;
  struct proton_engine_view *next;
};

void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms);
int proton_engine_runtime_initialized(void);
int32_t proton_engine_runtime_remote_debugging_port(void);
int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime,
    char *request_json);
int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t request_id);
proton_engine_window_t *proton_engine_find_window_by_browser_id(int browser_id);
proton_engine_window_t *proton_engine_windows_head(void);
void proton_engine_window_list_add(proton_engine_window_t *window);
void proton_engine_window_list_remove(proton_engine_window_t *window);
void proton_engine_init_app(void);
cef_app_t *proton_engine_cef_app(void);
void proton_engine_check_cef_api_hash(void);
void proton_engine_set_command_line_paths(
    const proton_engine_runtime_config_t *config);
int proton_engine_register_scheme_factory(void);
void proton_engine_bridge_pending_clear_all(void);
void proton_engine_free_closed_windows(void);
void proton_engine_overlay_subclass_browser(proton_engine_window_t *window,
                                            HWND browser_hwnd);
int proton_engine_overlay_frame_top_thickness(HWND hwnd);
void proton_engine_overlay_apply_frame(HWND hwnd);
LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam);
void proton_engine_resize_browser(proton_engine_window_t *window,
                                  int width,
                                  int height);
void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime,
    int browser_id);
proton_engine_client_t *proton_engine_client_new(
    proton_engine_window_t *window);
int CEF_CALLBACK proton_engine_client_release(cef_base_ref_counted_t *base);
int proton_engine_utf8_to_wide(const char *value,
                               wchar_t *buffer,
                               int buffer_len);

#endif
