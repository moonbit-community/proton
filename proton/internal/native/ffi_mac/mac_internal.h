#ifndef PROTON_ENGINE_CEF_MAC_INTERNAL_H
#define PROTON_ENGINE_CEF_MAC_INTERNAL_H

/* Private contracts shared by the macOS engine translation units. */
#include "../ffi/src/proton_engine.h"
#include "../ffi/src/proton_event.h"

#include "../ffi/src/engine/cef_common/bridge_client.h"
#include "../ffi/src/engine/cef_common/bridge_lifecycle.h"
#include "../ffi/src/engine/cef_common/bridge_renderer.h"
#include "../ffi/src/engine/cef_common/browser_lifecycle.h"
#include "../ffi/src/engine/cef_common/browser_session.h"
#include "../ffi/src/engine/cef_common/view_events.h"
#include "../ffi/src/engine/cef_common/window_state.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_v8_capi.h"

#import <Cocoa/Cocoa.h>

#include <dispatch/dispatch.h>
#include <stdatomic.h>
#include <stdint.h>

/* AppKit operations invoked from a worker are marshalled to the main queue. */
#define PROTON_ENGINE_RETURN_ON_MAIN(body)                     \
  if (![NSThread isMainThread]) {                              \
    __block int32_t proton_engine_main_status = PROTON_OK;     \
    dispatch_sync(dispatch_get_main_queue(), ^{                \
      proton_engine_main_status = (body);                      \
    });                                                        \
    return proton_engine_main_status;                          \
  }

typedef struct proton_engine_client proton_engine_client_t;

typedef struct {
  atomic_int refs;
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

struct proton_engine_runtime {
  int owns_cef_runtime;
  int headless;
  id accessibility_observer;
  int64_t next_bridge_request_id;
  char dialog_ok_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char dialog_cancel_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  proton_browser_registry_t *browsers;
};

int32_t proton_engine_runtime_start_accessibility(
    proton_engine_runtime_t *runtime, int32_t mode, char *error,
    size_t error_len);
void proton_engine_runtime_stop_accessibility(proton_engine_runtime_t *runtime);
void proton_engine_accessibility_set_enhanced_user_interface(int enabled);

struct proton_engine_window {
  proton_engine_runtime_t *runtime;
  NSWindow *window;
  NSView *content_view;
  NSView *browser_view;
  id delegate;
  int appkit_closing;
  int cef_allows_appkit_close;
  int close_interception_enabled;
  int close_authorized;
  int close_request_pending;
  int closable;
  int programmatic_close_pending;
  uint64_t close_request_id;
  proton_browser_session_t *browser_session;
  proton_browser_lifecycle_t *browser_lifecycle;
  proton_window_id_t public_window_id;
  proton_bridge_config_t *bridge_config;
  int32_t max_bridge_payload_bytes;
  proton_engine_bridge_lifecycle_t bridge_lifecycle;
  char *initial_url;
  int initial_navigation_pending;
  int browser_create_pending;
  int browser_create_scheduled;
  int window_listed;
  int finalize_after_browser_close;
  uint64_t native_id;
  int width;
  int height;
  int min_width;
  int min_height;
  int max_width;
  int max_height;
  double aspect_ratio;
  int zoom_percent;
  int titlebar_overlay;
  int window_button_visible;
  int window_controls_overlay_geometry_initialized;
  proton_engine_window_controls_overlay_geometry_t
      window_controls_overlay_geometry;
  proton_window_theme_preference_t theme_preference;
  NSInteger attention_request_id;
  int headless;
  int maximizable;
  int fullscreenable;
  int ignore_mouse_events;
  int ignore_mouse_forward;
  int enabled;
  int headless_hidden;
  int headless_focused;
  int osr_popup_visible;
  cef_rect_t osr_popup_rect;
  int closed;
  int closing;
  struct proton_engine_view *views;
  struct proton_engine_window *next;
};

struct proton_engine_client {
  cef_client_t client;
  proton_engine_ref_counted_t refs;
  proton_browser_lifecycle_t *browser_lifecycle;
};

struct proton_engine_view {
  proton_engine_window_t *window;
  proton_browser_lifecycle_t *browser_lifecycle;
  NSView *browser_view;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int32_t zoom_percent;
  int audio_muted;
  int visible;
  uint64_t native_id;
  char *initial_url;
  int initial_navigation_pending;
  int browser_create_pending;
  int browser_create_scheduled;
  int finalize_after_browser_close;
  int finalized;
  int closed;
  proton_browser_session_t *browser_session;
  proton_view_events_t *events;
  int has_background_color;
  uint32_t background_color;
  struct proton_engine_view *next;
};

int proton_engine_load_cef_library(const proton_engine_runtime_config_t *config,
                                   char *error,
                                   size_t error_len);
void proton_engine_unload_cef_library(void);
void proton_engine_init_handlers(void);
cef_app_t *proton_engine_cef_app(void);
int proton_engine_register_scheme_factory(void);
proton_engine_client_t *proton_engine_client_create(
    proton_browser_lifecycle_t *browser_lifecycle);
int CEF_CALLBACK proton_engine_client_release(
    cef_base_ref_counted_t *base);
cef_client_t *proton_engine_browser_client_factory(
    void *context, proton_browser_lifecycle_t *browser_lifecycle);
void proton_engine_window_mark_closed(proton_engine_window_t *window);
int proton_engine_window_request_browser_close(proton_engine_window_t *window,
                                               int force_close);
proton_engine_window_t *proton_engine_window_from_native_id(uint64_t native_id);
int proton_engine_runtime_has_pending_platform_work(
    proton_engine_runtime_t *runtime);
void proton_engine_runtime_create_pending_browsers(
    proton_engine_runtime_t *runtime);
int proton_engine_runtime_has_windows(proton_engine_runtime_t *runtime);
proton_engine_client_t *proton_engine_client_from_base(cef_client_t *client);
void CEF_CALLBACK proton_engine_on_register_custom_schemes(
    cef_app_t *self,
    cef_scheme_registrar_t *registrar);
void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line);
void CEF_CALLBACK proton_engine_on_schedule_message_pump_work(
    cef_browser_process_handler_t *self,
    int64_t delay_ms);
void CEF_CALLBACK proton_engine_osr_get_view_rect(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_rect_t *rect);
int CEF_CALLBACK proton_engine_osr_get_screen_info(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_screen_info_t *screen_info);
void CEF_CALLBACK proton_engine_osr_on_popup_show(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    int show);
void CEF_CALLBACK proton_engine_osr_on_popup_size(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    const cef_rect_t *rect);
void CEF_CALLBACK proton_engine_osr_on_paint(
    cef_render_handler_t *self,
    cef_browser_t *browser,
    cef_paint_element_type_t type,
    size_t dirty_rects_count,
    const cef_rect_t *dirty_rects,
    const void *buffer,
    int width,
    int height);

void proton_engine_view_on_after_created(proton_engine_view_t *view,
                                         cef_browser_t *browser);
void proton_engine_view_on_before_close(proton_engine_view_t *view,
                                        cef_browser_t *browser);
void proton_engine_window_close_views(proton_engine_window_t *window);
void proton_engine_window_layout_views(proton_engine_window_t *window);
void proton_engine_window_update_controls_overlay(
    proton_engine_window_t *window);
void proton_engine_window_free_views(proton_engine_window_t *window);
void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);
void proton_engine_signal_wait_source(uint32_t ready_mask);
void proton_engine_browser_signal(void *user_data);
void proton_engine_window_finalize_if_ready(proton_engine_window_t *window);
int proton_engine_browser_view_is_focused(NSView *browser_view);
proton_engine_view_t *proton_engine_view_from_native_id(uint64_t native_id);
proton_browser_lifecycle_t *proton_engine_browser_lifecycle(
    cef_browser_t *browser);
int proton_engine_runtime_initialized(void);
uint64_t proton_engine_allocate_view_native_id(void);

cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self);
cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self);
cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self);
cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self);

#endif
