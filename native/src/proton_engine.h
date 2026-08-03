#ifndef PROTON_ENGINE_H
#define PROTON_ENGINE_H

#include "proton_native.h"

#include <stddef.h>
#include <stdint.h>

typedef struct proton_engine_runtime proton_engine_runtime_t;
typedef struct proton_engine_window proton_engine_window_t;

typedef enum {
  PROTON_ENGINE_WINDOW_MINIMIZE = 1,
  PROTON_ENGINE_WINDOW_MAXIMIZE = 2,
  PROTON_ENGINE_WINDOW_RESTORE = 3,
  PROTON_ENGINE_WINDOW_SET_FULLSCREEN = 4,
  PROTON_ENGINE_WINDOW_SET_POSITION = 5,
  PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP = 6,
  PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT = 7,
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

int32_t proton_engine_prepare_app(char *error, size_t error_len);
int32_t proton_engine_run_app_loop(char *error, size_t error_len);
void proton_engine_quit_app_loop(void);
int32_t proton_engine_finish_app(char *error, size_t error_len);

int32_t proton_engine_execute_process_json(const char *config_json,
                                           int32_t *out_exit_code,
                                           char *error,
                                           size_t error_len);

int32_t proton_engine_runtime_create_json(const char *config_json,
                                           proton_engine_runtime_t **out_runtime,
                                           char *error,
                                           size_t error_len);
int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_runtime_run(proton_engine_runtime_t *runtime,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_runtime_quit(proton_engine_runtime_t *runtime,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len);
int32_t proton_engine_runtime_wait(proton_engine_runtime_t *runtime,
                                   uint32_t interest_mask,
                                   uint32_t timeout_ms,
                                   uint32_t *out_ready_mask,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_runtime_set_wakeup_fd(proton_engine_runtime_t *runtime,
                                            int32_t wakeup_fd,
                                            char *error,
                                            size_t error_len);
int32_t proton_engine_runtime_prepare_wakeup_source(
    proton_engine_runtime_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_runtime_activate_wakeup_source(
    proton_engine_runtime_t *runtime, char *error, size_t error_len);
int32_t proton_engine_runtime_next_wakeup_delay_ms(
    proton_engine_runtime_t *runtime,
    int64_t *out_delay_ms,
    char *error,
    size_t error_len);
void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime);
int32_t proton_engine_runtime_set_menu_json(proton_engine_runtime_t *runtime,
                                            const char *menu_json,
                                            char *error,
                                            size_t error_len);
int32_t proton_engine_runtime_poll_bridge_request_json(
    proton_engine_runtime_t *runtime,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len);
int32_t proton_engine_runtime_poll_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t *out_request_id,
    int32_t *out_present,
    char *error,
    size_t error_len);
int32_t proton_engine_runtime_respond_bridge_request_json(
    proton_engine_runtime_t *runtime,
    const char *response_json,
    char *error,
    size_t error_len);
int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len);
int32_t proton_engine_runtime_poll_dialog_result(
    proton_engine_runtime_t *runtime, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len, char *error,
    size_t error_len);

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len);
int32_t proton_engine_notification_show(const char *title,
                                        const char *body,
                                        const char *payload,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len);
/* On success with a click available, *out_required_len is the payload length
   including its NUL terminator (strlen + 1). */
int32_t proton_engine_notification_poll_click(
    char *buffer, int32_t buffer_len, int32_t *out_required_len,
    int32_t *out_has_payload, int32_t *out_available, char *error,
    size_t error_len);
int32_t proton_engine_notification_cleanup(char *error, size_t error_len);

int32_t proton_engine_window_create_json(proton_engine_runtime_t *runtime,
                                         const char *config_json,
                                         proton_engine_window_t **out_window,
                                         char *error,
                                         size_t error_len);
int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len);
int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_window_is_closed(proton_engine_window_t *window);
int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len);
int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len);
int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
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
int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len);
int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len);
int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len);
int32_t proton_engine_window_load_html(proton_engine_window_t *window,
                                       const char *html,
                                       const char *base_url,
                                       char *error,
                                       size_t error_len);
int32_t proton_engine_window_load_asset(proton_engine_window_t *window,
                                        const char *html,
                                        const char *document_url,
                                        const char *asset_root,
                                        char *error,
                                        size_t error_len);
int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len);
int32_t proton_engine_window_poll_browser_event_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len);
int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len);
int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len);
int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len);
void proton_engine_window_bind_public_id(proton_engine_window_t *window,
                                         proton_window_id_t public_window);
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
int32_t proton_engine_window_poll_dialog_result(
    proton_engine_window_t *window,
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len);

int32_t proton_engine_take_menu_command(proton_engine_runtime_t *runtime,
                                        char *buffer,
                                        size_t buffer_len,
                                        proton_window_id_t *out_focused_window,
                                        int32_t *out_present);
int32_t proton_engine_take_platform_event(proton_engine_runtime_t *runtime,
                                          char *buffer,
                                          size_t buffer_len,
                                          int32_t *out_present);
const char *proton_engine_name(void);

#endif
