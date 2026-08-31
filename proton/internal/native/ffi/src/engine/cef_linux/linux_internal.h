#ifndef PROTON_ENGINE_CEF_LINUX_INTERNAL_H
#define PROTON_ENGINE_CEF_LINUX_INTERNAL_H

/* Private contracts shared by the Linux engine translation units. */
#include "../../proton_engine.h"
#include "../../proton_event.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/view_events.h"
#include "../cef_common/window_state.h"

#include <gtk/gtk.h>
#include <stdatomic.h>

#include <X11/Xlib.h>

#include "linux_menu.h"
#include "linux_titlebar.h"

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
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

#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128

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

typedef enum proton_engine_linux_dialog_kind {
  PROTON_ENGINE_LINUX_DIALOG_MESSAGE = 0,
  PROTON_ENGINE_LINUX_DIALOG_CONFIRM = 1,
  PROTON_ENGINE_LINUX_DIALOG_FILE = 2,
} proton_engine_linux_dialog_kind_t;

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  /* Set once by the first asset document and never changed, so every window
     in a runtime resolves application resources against the same root. */
  int64_t next_bridge_request_id;
  proton_linux_menu_bar_t *menu_definition;
  char dialog_ok_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char dialog_cancel_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  proton_browser_registry_t *browsers;
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
  char titlebar_minimize_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_maximize_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_restore_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_close_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  proton_browser_lifecycle_t *browser_lifecycle;
  proton_window_id_t public_window_id;
  char *bridge_config_json;
  int32_t max_bridge_payload_bytes;
  proton_engine_bridge_lifecycle_t bridge_lifecycle;
  int width;
  int height;
  int min_width;
  int min_height;
  int max_width;
  int max_height;
  double aspect_ratio;
  int headless;
  int headless_hidden;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int size_hint;
  int titlebar_overlay;
  int always_on_top;
  int fullscreenable;
  int enabled;
  int zoom_percent;
  int close_interception_enabled;
  int close_authorized;
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

void proton_engine_dialog_cancel_runtime(proton_engine_runtime_t *runtime);
void proton_engine_dialog_cancel_window(proton_engine_window_t *window);
void proton_engine_signal_wait_source(uint32_t ready_mask);
void proton_engine_browser_signal(void *user_data);
int proton_engine_browser_id(cef_browser_t *browser);
proton_browser_lifecycle_t *proton_engine_browser_lifecycle(
    cef_browser_t *browser);
proton_engine_view_t *proton_engine_view_from_browser(cef_browser_t *browser);
void proton_engine_window_defer_free(proton_engine_window_t *window);
int proton_engine_x11_window_is_focused(Display *display, Window browser_window);

cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self);
cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self);
cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self);
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
  atomic_int refs;
} proton_engine_ref_counted_t;

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_browser_lifecycle_t *browser_lifecycle;
};

/* A web contents view: an extra child browser hosted inside a window's
   browser host, positioned in top-left coordinates. The struct is owned by
   the window's view list and freed only from the window's storage teardown,
   so native ABI view slots can never hold a dangling pointer regardless of
   how the view was closed. */
struct proton_engine_view {
  proton_engine_window_t *window;
  proton_browser_lifecycle_t *browser_lifecycle;
  cef_window_handle_t xwindow;
  Display *display;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int32_t zoom_percent;
  int audio_muted;
  int visible;
  uint64_t native_id;
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  proton_browser_session_t *browser_session;
  proton_view_events_t *events;
  int has_background_color;
  uint32_t background_color;
  int finalize_after_browser_close;
  int finalized;
  int closed;
  struct proton_engine_view *next;
};

void proton_engine_init_handlers(void);
cef_app_t *proton_engine_cef_app(void);
int proton_engine_register_scheme_factory(void);
void proton_engine_bridge_pending_clear_all(void);
void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime,
    int browser_id);
proton_engine_client_t *proton_engine_client_create(
    proton_browser_lifecycle_t *browser_lifecycle);
int CEF_CALLBACK proton_engine_client_release(
    cef_base_ref_counted_t *base);
cef_client_t *proton_engine_browser_client_factory(
    void *context, proton_browser_lifecycle_t *browser_lifecycle);
void proton_engine_window_mark_closed(proton_engine_window_t *window);
void proton_engine_overlay_update_input_shape(proton_engine_window_t *window);
void proton_engine_overlay_update_maximize_button(
    proton_engine_window_t *window);
gboolean proton_engine_overlay_window_state(GtkWidget *widget,
                                             GdkEventWindowState *event,
                                             gpointer user_data);
int proton_engine_overlay_resize_handle(proton_engine_window_t *window);
int proton_engine_overlay_create_controls(proton_engine_window_t *window);
int proton_engine_runtime_initialized(void);
const char *proton_engine_runtime_locale(void);
int32_t proton_engine_runtime_remote_debugging_port(void);
proton_engine_window_t *proton_engine_windows_head(void);
void proton_engine_set_scheduled_pump_delay_ms(int64_t delay_ms);
void proton_engine_append_switch(cef_command_line_t *command_line,
                                 const char *name);
void proton_engine_append_switch_with_value(cef_command_line_t *command_line,
                                            const char *name,
                                            const char *value);
void proton_engine_window_list_add(proton_engine_window_t *window);
proton_engine_window_t *proton_engine_window_from_browser(
    cef_browser_t *browser);
void proton_engine_overlay_release_input_windows(
    proton_engine_window_t *window);
GdkFilterReturn proton_engine_x11_event_filter(GdkXEvent *xevent,
                                                GdkEvent *event,
                                                gpointer user_data);
int32_t proton_engine_window_install_menu(
    proton_engine_window_t *window,
    const proton_linux_menu_bar_t *menu_definition,
    char *error,
    size_t error_len);
int proton_engine_ensure_gtk(char *error, size_t error_len);
void proton_engine_overlay_toggle_maximize(proton_engine_window_t *window);
void proton_engine_sync_browser_bounds(proton_engine_window_t *window);

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

#endif
