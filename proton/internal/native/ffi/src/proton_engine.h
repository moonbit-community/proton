#ifndef PROTON_ENGINE_H
#define PROTON_ENGINE_H

#include "proton_native.h"
#include "engine/cef_common/browser_session.h"
#include "proton_menu.h"

#include <stddef.h>
#include <stdint.h>

typedef struct proton_engine_runtime proton_engine_runtime_t;
typedef struct proton_engine_window proton_engine_window_t;
typedef struct proton_engine_view proton_engine_view_t;

#define PROTON_ENGINE_MAX_PATH_BYTES 4096
#define PROTON_ENGINE_MAX_URL_BYTES 131072
#define PROTON_ENGINE_MAX_LABEL_BYTES 256

enum {
  PROTON_REMOTE_DEBUGGING_EPHEMERAL = -1,
  PROTON_REMOTE_DEBUGGING_DISABLED = 0,
};

typedef struct {
  char runtime_root[PROTON_ENGINE_MAX_PATH_BYTES];
  char helper_path[PROTON_ENGINE_MAX_PATH_BYTES];
  char resources_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char locales_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char cache_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char framework_dir[PROTON_ENGINE_MAX_PATH_BYTES];
  char locale[PROTON_ENGINE_MAX_PATH_BYTES];
  char accept_languages[PROTON_ENGINE_MAX_PATH_BYTES];
  char dialog_ok_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char dialog_cancel_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  int32_t remote_debugging_port;
  int32_t headless;
  int32_t persist_session_cookies;
} proton_engine_runtime_config_t;

typedef struct {
  proton_window_id_t public_window;
  char title[512];
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t width;
  int32_t height;
  int32_t size_hint;
  int32_t titlebar_overlay;
  char titlebar_minimize_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_maximize_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_restore_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  char titlebar_close_label[PROTON_ENGINE_MAX_LABEL_BYTES];
  proton_browser_policy_t browser_policy;
  const char *bridge_config_json;
  int32_t max_bridge_payload_bytes;
} proton_engine_window_config_t;

typedef struct {
  proton_window_id_t public_window;
  proton_view_id_t public_view;
  char initial_url[PROTON_ENGINE_MAX_URL_BYTES];
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  int32_t visible;
  int32_t has_background_color;
  uint32_t background_color;
} proton_engine_view_config_t;

/* CEF's external pump is not fully wake-driven. Match cefclient's maximum
   interval so browser work that emits no schedule callback cannot starve. */
enum { PROTON_ENGINE_MAX_MESSAGE_PUMP_DELAY_MS = 1000 / 30 };

typedef enum {
  PROTON_ENGINE_WINDOW_MINIMIZE = 1,
  PROTON_ENGINE_WINDOW_MAXIMIZE = 2,
  PROTON_ENGINE_WINDOW_RESTORE = 3,
  PROTON_ENGINE_WINDOW_SET_FULLSCREEN = 4,
  PROTON_ENGINE_WINDOW_SET_POSITION = 5,
  PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP = 6,
  PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT = 7,
  PROTON_ENGINE_WINDOW_SET_RESIZABLE = 8,
  PROTON_ENGINE_WINDOW_SET_KIOSK = 9,
} proton_engine_window_action_kind_t;

typedef struct {
  proton_engine_window_action_kind_t kind;
  int32_t value;
  int32_t x;
  int32_t y;
} proton_engine_window_action_t;

typedef struct {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t monitor_x;
  int32_t monitor_y;
  int32_t monitor_width;
  int32_t monitor_height;
  int32_t work_x;
  int32_t work_y;
  int32_t work_width;
  int32_t work_height;
  int32_t scale_factor_percent;
  int32_t zoom_percent;
  int32_t visible;
  int32_t focused;
  int32_t minimized;
  int32_t maximized;
  int32_t fullscreen;
  int32_t always_on_top;
  int32_t theme;
} proton_engine_window_state_t;

int32_t proton_engine_execute_process(
    const proton_engine_runtime_config_t *config, int32_t *out_exit_code,
    char *error, size_t error_len);

int32_t proton_engine_runtime_create(
    const proton_engine_runtime_config_t *config,
    proton_engine_runtime_t **out_runtime, char *error, size_t error_len);
int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_runtime_destroy_ready(proton_engine_runtime_t *runtime);
int32_t proton_engine_complete_resource_request(
    int64_t request_id, int32_t status, const char *mime_type,
    const void *data, size_t data_len);
void proton_engine_cancel_resource_requests(void);
int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len);
/* `runtime` may be NULL, which waits for host-loop wakeups alone. That is what
   the host loop uses before an engine runtime exists. */
int32_t proton_engine_runtime_wait(proton_engine_runtime_t *runtime,
                                   uint32_t interest_mask,
                                   int32_t timeout_ms,
                                   uint32_t *out_ready_mask,
                                   char *error,
                                   size_t error_len);

/* The main thread's event loop, which outlives any single engine runtime and
   exists before the first one is created. `begin` must run on the main thread
   before any polling; `poll` runs one iteration there -- block, then advance
   the platform toolkit, because nothing else does while this loop owns the
   thread; `end` releases it. */
int32_t proton_engine_host_loop_begin(char *error, size_t error_len);
int32_t proton_engine_host_loop_poll(int32_t timeout_ms,
                                     uint32_t *out_ready_mask,
                                     char *error,
                                     size_t error_len);
void proton_engine_host_loop_end(void);
void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime);
int32_t proton_engine_runtime_set_menu(
    proton_engine_runtime_t *runtime, const proton_menu_bar_t *menu_bar,
    char *error, size_t error_len);
int32_t proton_engine_runtime_respond_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id, int32_t ok,
    const char *body_json, char *error, size_t error_len);
int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len);

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len);
int32_t proton_engine_notification_show(const char *title,
                                        const char *body,
                                        const char *payload,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len);
int32_t proton_engine_notification_set_badge_count(int32_t count,
                                                   char *error,
                                                   size_t error_len);
int32_t proton_engine_notification_cleanup(char *error, size_t error_len);

int32_t proton_engine_window_create(
    proton_engine_runtime_t *runtime,
    const proton_engine_window_config_t *config,
    proton_engine_window_t **out_window, char *error, size_t error_len);
int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len);
int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_show_inactive(proton_engine_window_t *window,
                                           char *error, size_t error_len);
int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_window_is_closed(proton_engine_window_t *window);
int32_t proton_engine_window_popup_menu(proton_engine_window_t *window,
                                       int32_t x, int32_t y,
                                       const proton_menu_bar_t *menu_bar,
                                       char *error, size_t error_len);
int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len);
int32_t proton_engine_window_set_icon(proton_engine_window_t *window,
                                      const char *path,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_window_set_parent(proton_engine_window_t *window,
                                        proton_engine_window_t *parent,
                                        int32_t modal, char *error,
                                        size_t error_len);
int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_window_set_content_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len);
int32_t proton_engine_window_get_content_size(
    proton_engine_window_t *window, int32_t *out_width, int32_t *out_height,
    char *error, size_t error_len);
int32_t proton_engine_window_set_minimum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len);
int32_t proton_engine_window_set_maximum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len);
int32_t proton_engine_window_set_aspect_ratio(
    proton_engine_window_t *window, double aspect_ratio, char *error,
    size_t error_len);
int32_t proton_engine_window_set_movable(proton_engine_window_t *window,
                                         int32_t movable, char *error,
                                         size_t error_len);
int32_t proton_engine_window_set_opacity(proton_engine_window_t *window,
                                         double opacity, char *error,
                                         size_t error_len);
int32_t proton_engine_window_set_skip_taskbar(proton_engine_window_t *window,
                                              int32_t skip, char *error,
                                              size_t error_len);
int32_t proton_engine_window_set_content_protection(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len);
int32_t proton_engine_window_set_minimizable(
    proton_engine_window_t *window, int32_t minimizable, char *error,
    size_t error_len);
int32_t proton_engine_window_set_maximizable(
    proton_engine_window_t *window, int32_t maximizable, char *error,
    size_t error_len);
int32_t proton_engine_window_set_closable(
    proton_engine_window_t *window, int32_t closable, char *error,
    size_t error_len);
int32_t proton_engine_window_set_button_visibility(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len);
int32_t proton_engine_window_set_focusable(
    proton_engine_window_t *window, int32_t focusable, char *error,
    size_t error_len);
int32_t proton_engine_window_set_fullscreenable(
    proton_engine_window_t *window, int32_t fullscreenable, char *error,
    size_t error_len);
int32_t proton_engine_window_set_has_shadow(
    proton_engine_window_t *window, int32_t has_shadow, char *error,
    size_t error_len);
int32_t proton_engine_window_set_ignore_mouse_events(
    proton_engine_window_t *window, int32_t ignore, int32_t forward,
    char *error, size_t error_len);
int32_t proton_engine_window_set_background_color(
    proton_engine_window_t *window, uint32_t color, char *error,
    size_t error_len);
int32_t proton_engine_window_set_visible_on_all_workspaces(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len);
int32_t proton_engine_window_set_enabled(proton_engine_window_t *window,
                                         int32_t enabled, char *error,
                                         size_t error_len);
int32_t proton_engine_window_set_progress_bar(
    proton_engine_window_t *window, double progress, char *error,
    size_t error_len);
int32_t proton_engine_window_flash_frame(
    proton_engine_window_t *window, int32_t flash, char *error,
    size_t error_len);
int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len);
int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state,
    char *error,
    size_t error_len);
int32_t proton_engine_window_set_close_interception(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len);
int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len);
int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len);
int32_t proton_engine_window_download_url(
    proton_engine_window_t *window, const char *url, char *error,
    size_t error_len);
int32_t proton_engine_window_print(
    proton_engine_window_t *window, char *error, size_t error_len);
int32_t proton_engine_window_print_to_pdf(
    proton_engine_window_t *window, const char *path, int32_t landscape,
    int32_t print_background, double scale, double paper_width,
    double paper_height, int32_t prefer_css_page_size, int32_t margin_type,
    double margin_top, double margin_right, double margin_bottom,
    double margin_left, const char *page_ranges,
    int32_t display_header_footer, const char *header_template,
    const char *footer_template, int32_t generate_tagged_pdf,
    int32_t generate_document_outline, int32_t *out_request_id,
    char *error, size_t error_len);
int32_t proton_engine_window_find_in_page(
    proton_engine_window_t *window, const char *text, int32_t forward,
    int32_t match_case, int32_t find_next, int32_t *out_request_id,
    char *error, size_t error_len);
int32_t proton_engine_window_stop_find_in_page(
    proton_engine_window_t *window, int32_t clear_selection, char *error,
    size_t error_len);
int32_t proton_engine_window_get_navigation_state(
    proton_engine_window_t *window, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len);
int32_t proton_engine_window_set_audio_muted(
    proton_engine_window_t *window, int32_t muted, char *error,
    size_t error_len);
int32_t proton_engine_window_is_audio_muted(
    proton_engine_window_t *window, int32_t *out_muted, char *error,
    size_t error_len);
int32_t proton_engine_window_get_browser_url(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_window_get_browser_title(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_window_get_browser_loading(
    proton_engine_window_t *window, int32_t *out_is_loading, char *error,
    size_t error_len);
int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len);
int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len);
uint64_t proton_engine_window_bridge_revision(
    proton_engine_window_t *window);
int32_t proton_engine_window_bridge_state_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_window_take_bridge_failure_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_window_begin_message_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len);
int32_t proton_engine_window_begin_confirm_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len);
int32_t proton_engine_window_begin_open_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len);
int32_t proton_engine_window_begin_save_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len);
int32_t proton_engine_window_begin_choose_directory_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len);
int32_t proton_engine_window_cancel_dialog(proton_engine_window_t *window,
                                           int64_t dialog,
                                           char *error,
                                           size_t error_len);
const char *proton_engine_name(void);

int32_t proton_engine_view_create(
    proton_engine_window_t *window, const proton_engine_view_config_t *config,
    proton_engine_view_t **out_view, char *error, size_t error_len);
int32_t proton_engine_view_destroy(proton_engine_view_t *view,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_view_set_bounds(proton_engine_view_t *view,
                                      int32_t x,
                                      int32_t y,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_view_set_visible(proton_engine_view_t *view,
                                       int32_t visible,
                                       char *error,
                                       size_t error_len);
int32_t proton_engine_view_set_z_order(proton_engine_view_t *view,
                                       int32_t z_order,
                                       char *error,
                                       size_t error_len);
int32_t proton_engine_view_set_zoom_percent(proton_engine_view_t *view,
                                            int32_t zoom_percent,
                                            char *error,
                                            size_t error_len);
int32_t proton_engine_view_set_audio_muted(proton_engine_view_t *view,
                                           int32_t muted, char *error,
                                           size_t error_len);
int32_t proton_engine_view_is_audio_muted(proton_engine_view_t *view,
                                          int32_t *out_muted, char *error,
                                          size_t error_len);
int32_t proton_engine_view_load_url(proton_engine_view_t *view,
                                    const char *url,
                                    char *error,
                                    size_t error_len);
int32_t proton_engine_view_eval(proton_engine_view_t *view,
                                const char *script,
                                char *error,
                                size_t error_len);
int32_t proton_engine_view_browser_command_json(proton_engine_view_t *view,
                                                const char *command_json,
                                                char *error,
                                                size_t error_len);
int32_t proton_engine_view_find_in_page(
    proton_engine_view_t *view, const char *text, int32_t forward,
    int32_t match_case, int32_t find_next, int32_t *out_request_id,
    char *error, size_t error_len);
int32_t proton_engine_view_stop_find_in_page(
    proton_engine_view_t *view, int32_t clear_selection, char *error,
    size_t error_len);
int32_t proton_engine_view_get_navigation_state(
    proton_engine_view_t *view, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len);
/* Session cookie and cache management. The engine implementation reaches the
   CEF cookie manager through the window's browser host request context. Cookie
   get completion is published to the runtime event queue; set, delete, flush,
   and clear_cache are fire-and-forget. */
int32_t proton_engine_window_cookie_begin_get_json(
    proton_engine_window_t *window, const char *url_utf8,
    int32_t include_http_only, int64_t *out_request_id, char *error,
    size_t error_len);
int32_t proton_engine_window_cookie_set(
    proton_engine_window_t *window, const char *url_utf8,
    const char *name_utf8, const char *value_utf8,
    const char *domain_utf8, const char *path_utf8,
    int32_t secure, int32_t http_only, int32_t same_site,
    char *error, size_t error_len);
int32_t proton_engine_window_cookie_delete(proton_engine_window_t *window,
                                           const char *url_utf8,
                                           const char *name_utf8,
                                           char *error, size_t error_len);
int32_t proton_engine_window_cookie_flush(proton_engine_window_t *window,
                                          char *error, size_t error_len);
int32_t proton_engine_window_clear_cache(proton_engine_window_t *window,
                                         char *error, size_t error_len);

/* Releases any pending cookie-get state associated with the window. Called
   during window destruction so async cookie visits do not outlive their
   window. Safe to call with NULL. */
void proton_engine_window_cookie_cleanup(proton_engine_window_t *window);

/* Native image management. Images are standalone CEF image objects not tied
   to a runtime or window. The engine layer owns the cef_image_t reference
   count; the state layer stores the raw pointer and treats it as opaque. */
typedef struct proton_engine_image proton_engine_image_t;

int32_t proton_engine_image_create(proton_engine_image_t **out_image,
                                   char *error, size_t error_len);
void proton_engine_image_release(proton_engine_image_t *image);
int32_t proton_engine_image_add_png(proton_engine_image_t *image,
                                    const void *data, size_t data_len,
                                    float scale_factor, char *error,
                                    size_t error_len);
int32_t proton_engine_image_add_jpeg(proton_engine_image_t *image,
                                     const void *data, size_t data_len,
                                     float scale_factor, char *error,
                                     size_t error_len);
int32_t proton_engine_image_add_bitmap(proton_engine_image_t *image,
                                       const void *data, size_t data_len,
                                       int32_t width, int32_t height,
                                       float scale_factor, char *error,
                                       size_t error_len);
int32_t proton_engine_image_is_empty(proton_engine_image_t *image,
                                     int32_t *out_empty, char *error,
                                     size_t error_len);
int32_t proton_engine_image_get_size(proton_engine_image_t *image,
                                     int32_t *out_width, int32_t *out_height,
                                     char *error, size_t error_len);
int32_t proton_engine_image_to_png(proton_engine_image_t *image,
                                   float scale_factor, int32_t with_transparency,
                                   void *buffer, int32_t buffer_len,
                                   int32_t *out_required_len,
                                   int32_t *out_width, int32_t *out_height,
                                   char *error, size_t error_len);
int32_t proton_engine_image_to_jpeg(proton_engine_image_t *image,
                                    float scale_factor, int32_t quality,
                                    void *buffer, int32_t buffer_len,
                                    int32_t *out_required_len,
                                    int32_t *out_width, int32_t *out_height,
                                    char *error, size_t error_len);
int32_t proton_engine_image_to_bitmap(proton_engine_image_t *image,
                                      float scale_factor, void *buffer,
                                      int32_t buffer_len,
                                      int32_t *out_required_len,
                                      int32_t *out_width, int32_t *out_height,
                                      char *error, size_t error_len);

#define PROTON_ENGINE_MAX_SCREENS 16

typedef struct {
  int32_t id;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t work_x;
  int32_t work_y;
  int32_t work_width;
  int32_t work_height;
  int32_t scale_factor_percent;
  int32_t is_primary;
} proton_engine_screen_info_t;

int32_t proton_engine_screen_enumerate(
    proton_engine_screen_info_t *out_screens,
    int32_t max_screens,
    int32_t *out_count,
    char *error,
    size_t error_len);

#endif
