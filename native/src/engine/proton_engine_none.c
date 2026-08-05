#include "../proton_engine.h"

#include <stdio.h>

static int32_t proton_engine_set_error(char *error,
                                       size_t error_len,
                                       const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
  return PROTON_ERR_UNSUPPORTED;
}

const char *proton_engine_name(void) {
  return "none";
}

static const char *proton_engine_unavailable_message(void) {
#if PROTON_WITH_ENGINE
  return "native engine is not wired yet";
#else
  return "native engine support is not compiled into this library";
#endif
}

int32_t proton_engine_prepare_app(char *error, size_t error_len) {
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_run_app_loop(char *error, size_t error_len) {
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

void proton_engine_quit_app_loop(void) {}

int32_t proton_engine_finish_app(char *error, size_t error_len) {
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_execute_process_json(const char *config_json,
                                           int32_t *out_exit_code,
                                           char *error,
                                           size_t error_len) {
  (void)config_json;
  if (out_exit_code != NULL) {
    *out_exit_code = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_create_json(const char *config_json,
                                          proton_engine_runtime_t **out_runtime,
                                          char *error,
                                          size_t error_len) {
  (void)config_json;
  if (out_runtime != NULL) {
    *out_runtime = NULL;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_destroy(proton_engine_runtime_t *runtime,
                                      char *error,
                                      size_t error_len) {
  (void)runtime;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_run(proton_engine_runtime_t *runtime,
                                  char *error,
                                  size_t error_len) {
  (void)runtime;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_quit(proton_engine_runtime_t *runtime,
                                   char *error,
                                   size_t error_len) {
  (void)runtime;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_do_message_loop_work(
    proton_engine_runtime_t *runtime,
    char *error,
    size_t error_len) {
  (void)runtime;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_wait(proton_engine_runtime_t *runtime,
                                   uint32_t interest_mask,
                                   uint32_t timeout_ms,
                                   uint32_t *out_ready_mask,
                                   char *error,
                                   size_t error_len) {
  (void)runtime;
  (void)interest_mask;
  (void)timeout_ms;
  if (out_ready_mask != NULL) {
    *out_ready_mask = PROTON_WAIT_NONE;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_set_wakeup_fd(proton_engine_runtime_t *runtime,
                                            int32_t wakeup_fd,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)wakeup_fd;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_prepare_wakeup_source(
    proton_engine_runtime_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_activate_wakeup_source(
    proton_engine_runtime_t *runtime, char *error, size_t error_len) {
  (void)runtime;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_next_wakeup_delay_ms(
    proton_engine_runtime_t *runtime,
    int64_t *out_delay_ms,
    char *error,
    size_t error_len) {
  (void)runtime;
  if (out_delay_ms != NULL) {
    *out_delay_ms = -1;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  (void)runtime;
}

int32_t proton_engine_runtime_set_menu_json(proton_engine_runtime_t *runtime,
                                            const char *menu_json,
                                            char *error,
                                            size_t error_len) {
  (void)runtime;
  (void)menu_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_runtime_poll_bridge_request_json(
    proton_engine_runtime_t *runtime,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    char *error,
    size_t error_len) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  (void)error;
  (void)error_len;
  return PROTON_EVENT_NONE;
}

int32_t proton_engine_runtime_poll_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t *out_request_id,
    int32_t *out_present,
    char *error,
    size_t error_len) {
  (void)runtime;
  if (out_request_id != NULL) {
    *out_request_id = 0;
  }
  if (out_present != NULL) {
    *out_present = 0;
  }
  (void)error;
  (void)error_len;
  return PROTON_EVENT_NONE;
}

int32_t proton_engine_runtime_respond_bridge_request_json(
    proton_engine_runtime_t *runtime,
    const char *response_json,
    char *error,
    size_t error_len) {
  (void)runtime;
  (void)response_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_create_json(proton_engine_runtime_t *runtime,
                                         const char *config_json,
                                         proton_engine_window_t **out_window,
                                         char *error,
                                         size_t error_len) {
  (void)runtime;
  (void)config_json;
  if (out_window != NULL) {
    *out_window = NULL;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  (void)window;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  (void)window;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  (void)window;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  (void)window;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  (void)window;
  return 0;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  (void)window;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  (void)window;
  (void)title;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  (void)window;
  (void)width;
  (void)height;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {
  (void)window;
  (void)action;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state,
    char *error,
    size_t error_len) {
  (void)window;
  (void)out_state;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_set_close_interception(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  (void)window;
  (void)enabled;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len) {
  (void)window;
  if (out_request_id != NULL) {
    *out_request_id = 0;
  }
  if (out_pending != NULL) {
    *out_pending = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len) {
  (void)window;
  (void)request_id;
  (void)allow;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  (void)window;
  (void)url;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_load_html(proton_engine_window_t *window,
                                       const char *html,
                                       const char *base_url,
                                       char *error,
                                       size_t error_len) {
  (void)window;
  (void)html;
  (void)base_url;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_load_asset(proton_engine_window_t *window,
                                        const char *html,
                                        const char *document_url,
                                        const char *asset_root,
                                        char *error,
                                        size_t error_len) {
  (void)window;
  (void)html;
  (void)document_url;
  (void)asset_root;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len) {
  (void)window;
  (void)script;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_poll_browser_event_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)window;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len) {
  (void)window;
  (void)command_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len) {
  (void)window;
  (void)response_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len) {
  (void)window;
  (void)event_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

void proton_engine_window_bind_public_id(proton_engine_window_t *window,
                                         proton_window_id_t public_window) {
  (void)window;
  (void)public_window;
}

uint64_t proton_engine_window_bridge_revision(proton_engine_window_t *window) {
  (void)window;
  return 0;
}

int32_t proton_engine_window_bridge_state_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  (void)window;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_take_bridge_failure_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  return proton_engine_window_bridge_state_json(
      window, buffer, buffer_len, out_required_len, error, error_len);
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
  return proton_engine_set_error(
      error, error_len, "async native dialogs require the CEF engine");
}

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
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
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
  return proton_engine_set_error(
      error, error_len, "async native dialogs require the CEF engine");
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
  return proton_engine_set_error(
      error, error_len, "async native dialogs require the CEF engine");
}
// TODO: Drain menu commands when this engine grows a native menu backend.
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

int32_t proton_engine_view_create_json(proton_engine_window_t *window,
                                       const char *config_json,
                                       proton_engine_view_t **out_view,
                                       char *error,
                                       size_t error_len) {
  (void)window;
  (void)config_json;
  if (out_view != NULL) {
    *out_view = NULL;
  }
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_destroy(proton_engine_view_t *view,
                                   char *error,
                                   size_t error_len) {
  (void)view;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_set_bounds(proton_engine_view_t *view,
                                      int32_t x,
                                      int32_t y,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  (void)view;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_set_visible(proton_engine_view_t *view,
                                       int32_t visible,
                                       char *error,
                                       size_t error_len) {
  (void)view;
  (void)visible;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_set_z_order(proton_engine_view_t *view,
                                       int32_t z_order,
                                       char *error,
                                       size_t error_len) {
  (void)view;
  (void)z_order;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_load_url(proton_engine_view_t *view,
                                    const char *url,
                                    char *error,
                                    size_t error_len) {
  (void)view;
  (void)url;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_eval(proton_engine_view_t *view,
                                const char *script,
                                char *error,
                                size_t error_len) {
  (void)view;
  (void)script;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_load_html(proton_engine_view_t *view,
                                     const char *html,
                                     const char *base_url,
                                     char *error,
                                     size_t error_len) {
  (void)view;
  (void)html;
  (void)base_url;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_browser_command_json(proton_engine_view_t *view,
                                                const char *command_json,
                                                char *error,
                                                size_t error_len) {
  (void)view;
  (void)command_json;
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

int32_t proton_engine_view_poll_event_json(proton_engine_view_t *view,
                                           char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len,
                                           char *error,
                                           size_t error_len) {
  (void)view;
  (void)buffer;
  (void)buffer_len;
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  return proton_engine_set_error(error, error_len,
                                 "web contents views require the CEF engine");
}

void proton_engine_view_bind_public_id(proton_engine_view_t *view,
                                       proton_view_id_t public_view) {
  (void)view;
  (void)public_view;
}
