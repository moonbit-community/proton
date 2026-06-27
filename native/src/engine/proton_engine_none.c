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

int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len) {
  (void)window;
  (void)script;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}

int32_t proton_engine_window_install_bridge_json(proton_engine_window_t *window,
                                                 proton_window_id_t public_window,
                                                 const char *bridge_json,
                                                 char *error,
                                                 size_t error_len) {
  (void)window;
  (void)public_window;
  (void)bridge_json;
  return proton_engine_set_error(error, error_len,
                                 proton_engine_unavailable_message());
}
