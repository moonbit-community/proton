#if defined(_WIN32)

#include "win_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"

#include "../cef_common/bridge_client.h"
#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) ((refs)->refs)
#define PROTON_ENGINE_REF_STORE(refs, value) ((refs)->refs = (value))
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_find_handler_capi.h"
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

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_proton_engine_app_initialized = 0;
static int g_proton_engine_factory_initialized = 0;
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
typedef struct {
  cef_find_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_find_handler_t;
static proton_engine_find_handler_t g_proton_engine_find_handler;
static proton_engine_permission_handler_t g_proton_engine_permission_handler;
static proton_engine_render_handler_t g_proton_engine_render_handler;
static proton_engine_scheme_factory_t g_proton_engine_scheme_factory;
static proton_engine_window_t *g_proton_engine_closed_windows;
static char g_proton_engine_resources_dir[PROTON_ENGINE_MAX_PATH_BYTES];
static char g_proton_engine_locales_dir[PROTON_ENGINE_MAX_PATH_BYTES];

int proton_engine_bridge_resolve_host(cef_browser_t *browser,
                                      proton_engine_bridge_host_t *out_host) {
  proton_engine_window_t *window = proton_engine_window_lookup_browser(browser);
  if (window == NULL || window->runtime == NULL || out_host == NULL) {
    return 0;
  }
  memset(out_host, 0, sizeof(*out_host));
  out_host->runtime = window->runtime;
  out_host->public_window = window->public_window_id;
  out_host->bridge_config = window->bridge_config;
  out_host->max_payload_bytes = window->max_bridge_payload_bytes;
  out_host->next_request_id = &window->runtime->next_bridge_request_id;
  out_host->lifecycle = &window->bridge_lifecycle;
  return 1;
}

void proton_engine_bridge_signal(proton_engine_runtime_t *runtime) {
  proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
}

void proton_engine_bridge_response_sent(proton_engine_runtime_t *runtime) {
  (void)runtime;
}

static void CEF_CALLBACK proton_engine_osr_get_view_rect(
    cef_render_handler_t *self, cef_browser_t *browser, cef_rect_t *rect);
static int CEF_CALLBACK proton_engine_osr_get_screen_info(
    cef_render_handler_t *self, cef_browser_t *browser,
    cef_screen_info_t *screen_info);
static void CEF_CALLBACK proton_engine_osr_on_popup_show(
    cef_render_handler_t *self, cef_browser_t *browser, int show);
static void CEF_CALLBACK proton_engine_osr_on_popup_size(
    cef_render_handler_t *self, cef_browser_t *browser,
    const cef_rect_t *rect);
static void CEF_CALLBACK proton_engine_osr_on_paint(
    cef_render_handler_t *self, cef_browser_t *browser,
    cef_paint_element_type_t type, size_t dirty_rects_count,
    const cef_rect_t *dirty_rects, const void *buffer, int width, int height);
static int CEF_CALLBACK proton_engine_on_before_popup(
    cef_life_span_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    int popup_id, const cef_string_t *target_url,
    const cef_string_t *target_frame_name,
    cef_window_open_disposition_t target_disposition, int user_gesture,
    const cef_popup_features_t *popup_features, cef_window_info_t *window_info,
    cef_client_t **client, cef_browser_settings_t *settings,
    cef_dictionary_value_t **extra_info, int *no_javascript_access);
static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self, cef_browser_t *browser);
static void CEF_CALLBACK proton_engine_on_after_created(
    cef_life_span_handler_t *self, cef_browser_t *browser);
static void CEF_CALLBACK proton_engine_on_draggable_regions_changed(
    cef_drag_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    size_t regions_count, const cef_draggable_region_t *regions);
static void CEF_CALLBACK proton_engine_on_loading_state_change(
    cef_load_handler_t *self, cef_browser_t *browser, int isLoading,
    int canGoBack, int canGoForward);
static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_transition_type_t transition_type);
static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    int httpStatusCode);
static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_errorcode_t errorCode, const cef_string_t *errorText,
    const cef_string_t *failedUrl);
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
static void CEF_CALLBACK proton_engine_on_find_result(
    cef_find_handler_t *self, cef_browser_t *browser, int identifier,
    int count, const cef_rect_t *selection_rect, int active_match_ordinal,
    int final_update);
static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback);
static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string);
static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self);
static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self);
static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self);
static cef_find_handler_t *CEF_CALLBACK
proton_engine_client_get_find_handler(cef_client_t *self);
static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self);

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

int proton_engine_register_scheme_factory(void) {
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

static void CEF_CALLBACK proton_engine_on_web_kit_initialized(
    cef_render_process_handler_t *self) {
  (void)self;
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

static void proton_engine_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  (void)process_type;
  if (command_line == NULL) {
    return;
  }
  if ((process_type == NULL || process_type->length == 0) &&
      proton_engine_runtime_remote_debugging_port() ==
          PROTON_REMOTE_DEBUGGING_EPHEMERAL) {
    proton_engine_append_switch_with_value(command_line,
                                           "remote-debugging-port", "0");
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

void proton_engine_init_app(void) {
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
      (cef_base_ref_counted_t *)&g_proton_engine_find_handler.handler.base,
      sizeof(g_proton_engine_find_handler.handler),
      &g_proton_engine_find_handler.refs);
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
  g_proton_engine_v8_handler.handler.execute = proton_engine_bridge_v8_execute;
  g_proton_engine_load_handler.handler.on_loading_state_change =
      proton_engine_on_loading_state_change;
  g_proton_engine_load_handler.handler.on_load_start =
      proton_engine_on_load_start;
  g_proton_engine_load_handler.handler.on_load_end = proton_engine_on_load_end;
  g_proton_engine_load_handler.handler.on_load_error =
      proton_engine_on_load_error;
  g_proton_engine_life_span_handler.handler.on_before_popup =
      proton_engine_on_before_popup;
  g_proton_engine_life_span_handler.handler.on_after_created =
      proton_engine_on_after_created;
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
  g_proton_engine_find_handler.handler.on_find_result =
      proton_engine_on_find_result;
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
  proton_engine_view_handlers_init();
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

cef_app_t *proton_engine_cef_app(void) {
  return &g_proton_engine_app.app;
}

void proton_engine_check_cef_api_hash(void) {
#ifdef CEF_API_VERSION
  (void)cef_api_hash(CEF_API_VERSION, 0);
#else
  (void)cef_api_hash(0);
#endif
}

void proton_engine_set_command_line_paths(
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

int proton_engine_utf8_to_wide(const char *value,
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

proton_browser_lifecycle_t *proton_engine_browser_lifecycle(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_browser_lifecycle_t *lifecycle = NULL;
  if (cef_client != NULL) {
    proton_engine_client_t *client = (proton_engine_client_t *)cef_client;
    lifecycle = client->browser_lifecycle;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return lifecycle;
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
      proton_engine_window_lookup_view_browser(browser);
  if (view == NULL) {
    // CEF can query the viewport while create_browser_sync is still running,
    // before the view records its browser id; resolve via the client then.
    view = proton_engine_window_lookup_view_browser(browser);
  }
  if (view != NULL) {
    rect->width = view->width > 0 ? view->width : 1;
    rect->height = view->height > 0 ? view->height : 1;
    return;
  }
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
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
  (void)browser;
  (void)type;
  (void)width;
  (void)height;
}

int CEF_CALLBACK proton_engine_client_release(
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

proton_engine_client_t *proton_engine_client_new(
    proton_browser_lifecycle_t *browser_lifecycle) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  client->browser_lifecycle = browser_lifecycle;
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  // The registry keeps the initial client reference until CEF shutdown; CEF
  // may hold additional references through and beyond OnBeforeClose.
  client->client.base.release = proton_engine_client_release;
  client->client.on_process_message_received =
      proton_engine_bridge_client_on_process_message_received;
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_display_handler =
      proton_engine_client_get_display_handler;
  client->client.get_drag_handler = proton_engine_client_get_drag_handler;
  client->client.get_request_handler =
      proton_engine_client_get_request_handler;
  client->client.get_download_handler =
      proton_engine_client_get_download_handler;
  client->client.get_find_handler = proton_engine_client_get_find_handler;
  client->client.get_permission_handler =
      proton_engine_client_get_permission_handler;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
  return client;
}

cef_client_t *proton_engine_browser_client_factory(
    void *context, proton_browser_lifecycle_t *browser_lifecycle) {
  (void)context;
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->client.base.release = proton_engine_client_release;
  client->browser_lifecycle = browser_lifecycle;
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  return &client->client;
}

void proton_engine_window_defer_free(proton_engine_window_t *window) {
  // Windowless CloseBrowser can synchronously finalize the last view before
  // the outer window destroy resumes, so queue insertion must be idempotent.
  if (window == NULL || window->finalize_queued) {
    return;
  }
  window->finalize_queued = 1;
  proton_engine_window_list_remove(window);
  window->next = g_proton_engine_closed_windows;
  g_proton_engine_closed_windows = window;
}

static void proton_engine_window_free_storage(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_engine_window_free_views(window);
  if (window->hwnd != NULL) {
    // A deferred destroy may still be queued for this frame; detach the
    // window pointer so the message never dereferences the freed struct.
    SetWindowLongPtrW(window->hwnd, GWLP_USERDATA, 0);
  }
  if (window->background_brush != NULL) {
    DeleteObject(window->background_brush);
    window->background_brush = NULL;
  }
  proton_browser_lifecycle_clear_owner(window->browser_lifecycle);
  proton_internal_bridge_config_destroy(window->bridge_config);
  proton_browser_session_destroy(window->browser_session);
  free(window->draggable_regions);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
}

void proton_engine_free_closed_windows(void) {
  proton_engine_window_t *window = g_proton_engine_closed_windows;
  g_proton_engine_closed_windows = NULL;
  while (window != NULL) {
    proton_engine_window_t *next = window->next;
    window->next = NULL;
    proton_engine_window_free_storage(window);
    window = next;
  }
}

int proton_engine_closed_windows_ready_for_shutdown(void) {
  for (proton_engine_window_t *window = g_proton_engine_closed_windows;
       window != NULL; window = window->next) {
    if (window->hwnd != NULL) {
      return 0;
    }
  }
  return 1;
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
      proton_engine_window_lookup_browser(browser);
  return proton_browser_session_before_popup(
      window != NULL ? window->browser_session : NULL, target_url,
      target_disposition, user_gesture);
}

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL) {
    return;
  }
  proton_browser_role_t role = proton_browser_lifecycle_role(lifecycle);
  if (role == PROTON_BROWSER_ROLE_VIEW) {
    proton_engine_view_t *view =
        (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
    if (view == NULL) {
      proton_browser_lifecycle_on_before_close(lifecycle, browser);
      return;
    }
    proton_engine_runtime_t *runtime = view->window->runtime;
    proton_browser_lifecycle_on_before_close(lifecycle, browser);
    view->closed = 1;
    proton_view_events_closed(view->events);
    view->hwnd = NULL;
    // A page-initiated close (JS window.close) reaches here without a prior
    // engine destroy; let the cleanup state machine finish so the struct can
    // be reclaimed with its owning window.
    view->finalize_after_browser_close = 1;
    proton_engine_view_finalize_if_ready(view);
    proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
    return;
  }
  if (role == PROTON_BROWSER_ROLE_DEVTOOLS) {
    proton_browser_lifecycle_on_before_close(lifecycle, browser);
    proton_engine_runtime_t *runtime =
        (proton_engine_runtime_t *)proton_browser_lifecycle_context(lifecycle);
    proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
    return;
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
  if (window != NULL) {
    proton_engine_bridge_pending_remove_browser(
        window->runtime, proton_browser_lifecycle_browser_id(lifecycle));
  }
  proton_browser_lifecycle_on_before_close(lifecycle, browser);
  if (window == NULL) {
    return;
  }
  window->closed = 1;
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

static void CEF_CALLBACK proton_engine_on_after_created(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL) {
    cef_browser_host_t *host = browser != NULL ? browser->get_host(browser)
                                                : NULL;
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
  }
  proton_browser_lifecycle_on_after_created(lifecycle, browser);
  proton_engine_runtime_t *runtime =
      (proton_engine_runtime_t *)proton_browser_lifecycle_context(lifecycle);
  proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
}

cef_life_span_handler_t *CEF_CALLBACK
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
      proton_engine_window_lookup_browser(browser);
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
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  if (!isLoading && window != NULL && window->headless) {
    // The resize notification sent during synchronous browser creation can
    // precede compositor readiness. Invalidate after loading settles so a
    // windowless browser reliably delivers its initial OnPaint callback.
    cef_browser_host_t *host = browser->get_host(browser);
    if (host != NULL) {
      if (host->invalidate != NULL) {
        host->invalidate(host, PET_VIEW);
      }
      host->base.release((cef_base_ref_counted_t *)host);
    }
  }
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
      proton_engine_window_lookup_view_browser(browser);
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
  if (frame != NULL && frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") != 0) {
    proton_engine_window_t *window =
        proton_engine_window_lookup_browser(browser);
    proton_browser_session_navigated(
        window != NULL ? window->browser_session : NULL, url);
    proton_browser_session_loading_changed(
        window != NULL ? window->browser_session : NULL, url, 1);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode) {
  (void)self;
  (void)httpStatusCode;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_view_t *view =
      proton_engine_window_lookup_view_browser(browser);
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame)) {
      proton_view_events_loading_changed(view->events, 0);
      proton_engine_signal_wait_source(view->window->runtime,
                                       PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  if (window != NULL && frame != NULL && frame->is_main(frame)) {
    proton_browser_session_loading_changed(window->browser_session, url, 0);
  }
  if (window != NULL && window->bridge_config != NULL && frame != NULL &&
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
  proton_engine_view_t *view =
      proton_engine_window_lookup_view_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
  if (frame != NULL && frame->is_main(frame)) {
    proton_browser_session_load_failed(
        window != NULL ? window->browser_session : NULL, url,
        (int32_t)errorCode, text);
  }
  if (window != NULL && window->bridge_config != NULL && frame != NULL &&
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
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
  return proton_browser_session_can_download(
      window != NULL ? window->browser_session : NULL);
}

static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
  proton_browser_session_download_updated(
      window != NULL ? window->browser_session : NULL, download_item,
      callback);
}

static void CEF_CALLBACK proton_engine_on_find_result(
    cef_find_handler_t *self, cef_browser_t *browser, int identifier,
    int count, const cef_rect_t *selection_rect, int active_match_ordinal,
    int final_update) {
  (void)self;
  int x = selection_rect != NULL ? selection_rect->x : 0;
  int y = selection_rect != NULL ? selection_rect->y : 0;
  int width = selection_rect != NULL ? selection_rect->width : 0;
  int height = selection_rect != NULL ? selection_rect->height : 0;
  int browser_id = proton_engine_browser_id(browser);
  proton_engine_view_t *view = proton_engine_window_lookup_view_browser(browser);
  if (view != NULL) {
    proton_view_events_find_result(
        view->events,
        proton_browser_session_find_request_id(view->browser_session,
                                               identifier),
        count, x, y, width, height, active_match_ordinal, final_update);
    return;
  }
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  proton_browser_session_find_result(
      window != NULL ? window->browser_session : NULL, identifier, count,
      x, y, width, height, active_match_ordinal, final_update);
}

static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback) {
  (void)self;
  (void)frame;
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
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
      proton_engine_window_lookup_browser(browser);
  if (window == NULL || window->bridge_config == NULL || window->closed) {
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
    proton_engine_signal_wait_source(NULL, PROTON_WAIT_PLATFORM);
  }
  free(detail);
  free(url);
  if (frame != NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
  }
}

cef_load_handler_t *CEF_CALLBACK
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

static cef_find_handler_t *CEF_CALLBACK
proton_engine_client_get_find_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_find_handler.handler;
}

static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self) {
  (void)self;
  return &g_proton_engine_permission_handler.handler;
}

cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self) {
  proton_engine_client_t *client = (proton_engine_client_t *)self;
  if (client == NULL) {
    return NULL;
  }
  proton_browser_lifecycle_t *lifecycle = client->browser_lifecycle;
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) == PROTON_BROWSER_ROLE_DEVTOOLS) {
    return NULL;
  }
  if (proton_browser_lifecycle_role(lifecycle) == PROTON_BROWSER_ROLE_VIEW) {
    proton_engine_view_t *view =
        (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
    if (view == NULL || view->window == NULL || !view->window->headless) {
      return NULL;
    }
  } else {
    proton_engine_window_t *window =
        (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
    if (window == NULL || !window->headless) {
      return NULL;
    }
  }
  g_proton_engine_render_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_proton_engine_render_handler.handler);
  return &g_proton_engine_render_handler.handler;
}





#endif
