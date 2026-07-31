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
typedef int64_t proton_app_instance_id_t;
typedef void (*proton_app_entry_t)(void);

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
  PROTON_ERR_BUFFER_TOO_SMALL = -11,
  PROTON_ERR_STALE_BRIDGE_RESPONSE = -12,
  PROTON_ERR_STALE_WINDOW_REQUEST = -13,
  PROTON_ERR_STALE_BROWSER_REQUEST = -14
};

PROTON_API int32_t proton_abi_version(void);
PROTON_API int32_t proton_runtime_info_json(char *buffer,
                                            int32_t buffer_len,
                                            int32_t *out_required_len);
PROTON_API int32_t proton_app_instance_acquire(
    const char *identifier, const char *activation_json,
    proton_app_instance_id_t *out_instance, int32_t *out_primary);
PROTON_API int32_t proton_app_instance_attach_runtime(
    proton_app_instance_id_t instance, proton_runtime_id_t runtime);
PROTON_API int32_t
proton_app_instance_destroy(proton_app_instance_id_t instance);

PROTON_API int32_t proton_app_run(proton_app_entry_t entry);

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
PROTON_API int32_t proton_runtime_set_wakeup_fd(proton_runtime_id_t runtime,
                                                int32_t wakeup_fd);
PROTON_API int32_t proton_runtime_prepare_wakeup_source(
    proton_runtime_id_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t
proton_runtime_activate_wakeup_source(proton_runtime_id_t runtime);
PROTON_API int32_t proton_runtime_next_wakeup_delay_ms(
    proton_runtime_id_t runtime, int64_t *out_delay_ms);
PROTON_API int32_t proton_runtime_set_menu_json(proton_runtime_id_t runtime,
                                                const char *menu_json);
PROTON_API int32_t proton_runtime_poll_event_json(
    proton_runtime_id_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_poll_bridge_request_json(
    proton_runtime_id_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_respond_bridge_request_json(
    proton_runtime_id_t runtime, const char *response_json);
PROTON_API int32_t proton_runtime_begin_message_dialog(
    proton_runtime_id_t runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_runtime_poll_dialog_result(
    proton_runtime_id_t runtime, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len);

PROTON_API int32_t proton_notification_is_supported(int32_t *out_supported);
PROTON_API int32_t proton_notification_show(const char *title,
                                            const char *body,
                                            const char *payload,
                                            int32_t has_payload);
PROTON_API int32_t proton_notification_poll_click(
    char *buffer, int32_t buffer_len, int32_t *out_required_len,
    int32_t *out_has_payload, int32_t *out_available);
PROTON_API int32_t proton_notification_cleanup(void);

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
PROTON_API int32_t proton_window_minimize(proton_window_id_t window);
PROTON_API int32_t proton_window_maximize(proton_window_id_t window);
PROTON_API int32_t proton_window_restore(proton_window_id_t window);
PROTON_API int32_t proton_window_set_fullscreen(proton_window_id_t window,
                                                int32_t fullscreen);
PROTON_API int32_t proton_window_set_position(proton_window_id_t window,
                                              int32_t x, int32_t y);
PROTON_API int32_t proton_window_set_always_on_top(proton_window_id_t window,
                                                   int32_t always_on_top);
PROTON_API int32_t proton_window_set_zoom_percent(proton_window_id_t window,
                                                  int32_t zoom_percent);
PROTON_API int32_t proton_window_state_json(proton_window_id_t window,
                                            char *buffer, int32_t buffer_len,
                                            int32_t *out_required_len);
PROTON_API int32_t proton_window_set_close_interception(
    proton_window_id_t window, int32_t enabled);
PROTON_API int32_t proton_window_respond_close_request(
    proton_window_id_t window, int64_t request_id, int32_t allow);
PROTON_API int32_t proton_window_load_url(proton_window_id_t window,
                                          const char *url);
PROTON_API int32_t proton_window_load_html(proton_window_id_t window,
                                           const char *html,
                                           const char *base_url);
PROTON_API int32_t proton_window_eval(proton_window_id_t window,
                                      const char *script);
PROTON_API int32_t proton_window_browser_command_json(
    proton_window_id_t window, const char *command_json);
PROTON_API int32_t proton_window_respond_browser_request_json(
    proton_window_id_t window, const char *response_json);
PROTON_API int32_t proton_window_emit_bridge_event_json(
    proton_window_id_t window, const char *event_json);
PROTON_API int32_t proton_window_bridge_state_json(
    proton_window_id_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_window_take_bridge_failure_json(
    proton_window_id_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_window_begin_message_dialog(
    proton_window_id_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_confirm_dialog(
    proton_window_id_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_open_file_dialog(
    proton_window_id_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_save_file_dialog(
    proton_window_id_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_choose_directory_dialog(
    proton_window_id_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_poll_dialog_result(
    proton_window_id_t window, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len);

/* Expands a downloaded update archive into a directory and reports the `.app`
   it contains.

   The archive is expected to be authenticated already: this expands, it does
   not decide whether expanding is safe. Implemented on macOS; other platforms
   report PROTON_ERR_UNSUPPORTED rather than pretending to have installed
   anything. */
PROTON_API int32_t proton_update_expand(const char *archive_path,
                                        const char *destination_dir,
                                        char *bundle_buffer,
                                        int32_t bundle_buffer_len, char *error,
                                        int32_t error_len);

/* Records a staged application bundle after checking that installing it would
   be safe. Nothing is modified. */
PROTON_API int32_t proton_update_stage(const char *staged_bundle_path,
                                       char *error, int32_t error_len);

/* Replaces the running application with the staged bundle.

   This is the only irreversible step in the updater, which is why it is
   separate from staging and from the relaunch. */
PROTON_API int32_t proton_update_apply(char *error, int32_t error_len);

/* Starts the replaced application. The caller exits afterwards. */
PROTON_API int32_t proton_update_relaunch(char *error, int32_t error_len);

PROTON_API int32_t proton_last_error_message(char *buffer,
                                             int32_t buffer_len);

#ifdef __cplusplus
}
#endif

#endif
