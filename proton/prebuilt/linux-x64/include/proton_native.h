#ifndef PROTON_NATIVE_H
#define PROTON_NATIVE_H

#include <stdint.h>

#ifdef _WIN32
#ifdef PROTON_BUILD
#define PROTON_API __declspec(dllexport)
#else
#define PROTON_API __declspec(dllimport)
#endif
#else
#define PROTON_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define PROTON_ABI_VERSION 1
#define PROTON_INVALID_HANDLE 0

#define PROTON_WAIT_NONE 0u
#define PROTON_WAIT_EVENT (1u << 0)
#define PROTON_WAIT_BRIDGE (1u << 1)
#define PROTON_WAIT_PLATFORM (1u << 2)
#define PROTON_WAIT_ALL \
  (PROTON_WAIT_EVENT | PROTON_WAIT_BRIDGE | PROTON_WAIT_PLATFORM)

typedef int64_t proton_runtime_id_t;
typedef int64_t proton_window_id_t;

enum {
  PROTON_OK = 0,
  PROTON_PROCESS_HANDLED = 1,
  PROTON_EVENT_NONE = 2,

  PROTON_ERR_INVALID_ARGUMENT = -1,
  PROTON_ERR_INVALID_HANDLE = -2,
  PROTON_ERR_DESTROYED = -3,
  PROTON_ERR_NOT_INITIALIZED = -4,
  PROTON_ERR_ALREADY_INITIALIZED = -5,
  PROTON_ERR_PLATFORM = -6,
  PROTON_ERR_ENGINE = -7,
  PROTON_ERR_UNSUPPORTED = -8,
  PROTON_ERR_WRONG_THREAD = -9,
  PROTON_ERR_QUEUE_FAILED = -10,
  PROTON_ERR_BUFFER_TOO_SMALL = -11
};

PROTON_API int32_t proton_abi_version(void);
PROTON_API int32_t proton_runtime_info_json(char *buffer,
                                            int32_t buffer_len,
                                            int32_t *out_required_len);

PROTON_API int32_t proton_execute_process(const char *config_json,
                                          int32_t *out_exit_code);

PROTON_API int32_t proton_runtime_probe_json(const char *config_json);

PROTON_API int32_t proton_runtime_create_json(
    const char *config_json, proton_runtime_id_t *out_runtime);

PROTON_API int32_t proton_runtime_destroy(proton_runtime_id_t runtime);
PROTON_API int32_t proton_runtime_run(proton_runtime_id_t runtime);
PROTON_API int32_t proton_runtime_quit(proton_runtime_id_t runtime);
PROTON_API int32_t proton_runtime_do_message_loop_work(
    proton_runtime_id_t runtime);
PROTON_API int32_t proton_runtime_wait(proton_runtime_id_t runtime,
                                       uint32_t interest_mask,
                                       uint32_t timeout_ms,
                                       uint32_t *out_ready_mask);
PROTON_API int32_t proton_runtime_poll_event_json(
    proton_runtime_id_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_poll_bridge_request_json(
    proton_runtime_id_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_respond_bridge_request_json(
    proton_runtime_id_t runtime, const char *response_json);

PROTON_API int32_t proton_window_create_json(proton_runtime_id_t runtime,
                                             const char *config_json,
                                             proton_window_id_t *out_window);

PROTON_API int32_t proton_window_destroy(proton_window_id_t window);
PROTON_API int32_t proton_window_show(proton_window_id_t window);
PROTON_API int32_t proton_window_hide(proton_window_id_t window);
PROTON_API int32_t proton_window_close(proton_window_id_t window);
PROTON_API int32_t proton_window_focus(proton_window_id_t window);
PROTON_API int32_t proton_window_set_title(proton_window_id_t window,
                                           const char *title);
PROTON_API int32_t proton_window_set_size(proton_window_id_t window,
                                          int32_t width, int32_t height);
PROTON_API int32_t proton_window_load_url(proton_window_id_t window,
                                          const char *url);
PROTON_API int32_t proton_window_load_html(proton_window_id_t window,
                                           const char *html,
                                           const char *base_url);
PROTON_API int32_t proton_window_eval(proton_window_id_t window,
                                      const char *script);
PROTON_API int32_t proton_window_install_bridge_json(
    proton_window_id_t window, const char *bridge_json);

PROTON_API int32_t proton_last_error_message(char *buffer,
                                             int32_t buffer_len);

#ifdef __cplusplus
}
#endif

#endif
