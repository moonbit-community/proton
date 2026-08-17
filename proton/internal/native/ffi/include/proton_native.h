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

/* Wait until an event arrives, however long that takes.
 *
 * A host with nothing scheduled has nothing to wake up for, and the runtime
 * already shortens a wait of its own accord when the engine has timed work
 * pending, so a finite ceiling here would only be a periodic wakeup with no
 * work to do.
 *
 * `timeout_ms` is signed for this. A deadline computed as `deadline - now`
 * goes negative once it has passed; in an unsigned type the same arithmetic
 * wraps to roughly 49 days, which is indistinguishable from waiting forever
 * and hangs with no diagnostic. Signed keeps the two apart, and only this
 * constant asks to wait forever -- every other negative value is rejected as
 * the arithmetic slip it almost certainly is. Callers that may compute an
 * elapsed deadline should clamp it to zero themselves. */
#define PROTON_WAIT_TIMEOUT_INFINITE (-1)

typedef int64_t proton_runtime_id_t;
typedef int64_t proton_window_id_t;
typedef int64_t proton_view_id_t;
typedef int64_t proton_app_instance_id_t;
typedef int64_t proton_update_stage_id_t;
typedef int64_t proton_image_id_t;

typedef struct proton_runtime_slot *proton_runtime_handle_t;
typedef struct proton_window_slot *proton_window_handle_t;
typedef struct proton_view_slot *proton_view_handle_t;
typedef struct proton_image_slot *proton_image_handle_t;

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
  PROTON_ERR_STALE_BROWSER_REQUEST = -14,
  PROTON_ERR_UPDATE_BUSY = -15,
  PROTON_ERR_UPDATE_ROLLBACK = -16,
  PROTON_ERR_UPDATE_REVISION_MISMATCH = -17,
  PROTON_ERR_PENDING = -18,
  PROTON_ERR_BUSY = -19
};

enum {
  PROTON_UPDATE_INSTALLED = 0,
  PROTON_UPDATE_ALREADY_INSTALLED = 1
};

PROTON_API int32_t proton_abi_version(void);
PROTON_API proton_runtime_handle_t proton_runtime_null(void);
PROTON_API proton_window_handle_t proton_window_null(void);
PROTON_API proton_view_handle_t proton_view_null(void);
PROTON_API proton_image_handle_t proton_image_null(void);
PROTON_API int64_t proton_window_logical_id(proton_window_handle_t window);
PROTON_API int64_t proton_view_logical_id(proton_view_handle_t view);
PROTON_API int32_t proton_runtime_info_json(char *buffer,
                                            int32_t buffer_len,
                                            int32_t *out_required_len);
PROTON_API int32_t proton_system_preferred_languages_json(
    char *buffer, int32_t buffer_len, int32_t *out_required_len);
PROTON_API int32_t proton_app_instance_acquire(
    const char *identifier, const char *activation_json,
    proton_app_instance_id_t *out_instance, int32_t *out_primary);
PROTON_API int32_t proton_app_instance_attach_runtime(
    proton_app_instance_id_t instance, proton_runtime_handle_t runtime);
PROTON_API int32_t
proton_app_instance_destroy(proton_app_instance_id_t instance);

PROTON_API int32_t proton_execute_process(const char *config_json,
                                          int32_t *out_exit_code);

PROTON_API int32_t proton_runtime_probe_json(const char *config_json);

PROTON_API int32_t proton_runtime_create_json(
    const char *config_json, proton_runtime_handle_t *out_runtime);

PROTON_API int32_t proton_runtime_destroy(proton_runtime_handle_t runtime);
PROTON_API int32_t proton_runtime_do_message_loop_work(
    proton_runtime_handle_t runtime);
PROTON_API int32_t proton_runtime_wait(proton_runtime_handle_t runtime,
                                       uint32_t interest_mask,
                                       int32_t timeout_ms,
                                       uint32_t *out_ready_mask);

/* Wakes a `proton_runtime_wait` blocked on any runtime, or makes the next one
 * return immediately if none is blocked yet. Losing a wakeup deadlocks the
 * host, so the two cases must behave the same.
 *
 * Takes no handle on purpose. It is called from a thread that owns none, and
 * handles validate thread ownership. It touches only atomics and the platform
 * run loop, so it is safe from any thread and from a foreign runtime. */
PROTON_API void proton_runtime_signal_wakeup(void);

/* The main thread's event loop.
 *
 * It belongs to the thread, not to a runtime: it starts before the first
 * runtime is created and outlives the last one, which is what lets a host run
 * its own async work while it is still deciding what runtime to build.
 *
 * `begin` must run on the main thread. `poll` runs one iteration of that loop
 * there: it blocks until work arrives or the timeout expires, taking
 * PROTON_WAIT_TIMEOUT_INFINITE to wait until something happens, then drives
 * the platform's own pending work before reporting which kinds of work are
 * ready for the host. Until a runtime exists it reports only wakeups. `end`
 * releases the loop.
 *
 * `poll` is the only thing that advances the platform toolkit once the host
 * loop is running, so the host must keep calling it. A host that owns a
 * runtime handle uses `proton_runtime_do_message_loop_work` instead and does
 * not run a host loop at all. */
PROTON_API int32_t proton_host_loop_begin(void);
PROTON_API int32_t proton_host_loop_poll(int32_t timeout_ms,
                                         uint32_t *out_ready_mask);
PROTON_API void proton_host_loop_end(void);
PROTON_API int32_t proton_runtime_set_wakeup_fd(proton_runtime_handle_t runtime,
                                                int32_t wakeup_fd);
PROTON_API int32_t proton_runtime_prepare_wakeup_source(
    proton_runtime_handle_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t
proton_runtime_activate_wakeup_source(proton_runtime_handle_t runtime);
PROTON_API int32_t proton_runtime_next_wakeup_delay_ms(
    proton_runtime_handle_t runtime, int64_t *out_delay_ms);
PROTON_API int32_t proton_runtime_set_menu_json(proton_runtime_handle_t runtime,
                                                const char *menu_json);
PROTON_API int32_t proton_runtime_poll_event_json(
    proton_runtime_handle_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_poll_bridge_request_json(
    proton_runtime_handle_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_runtime_respond_bridge_request_json(
    proton_runtime_handle_t runtime, const char *response_json);
PROTON_API int32_t proton_runtime_begin_message_dialog(
    proton_runtime_handle_t runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_runtime_poll_dialog_result(
    proton_runtime_handle_t runtime, int64_t dialog, char *buffer,
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

PROTON_API int32_t proton_window_create_json(proton_runtime_handle_t runtime,
                                             const char *config_json,
                                             proton_window_handle_t *out_window);

PROTON_API int32_t proton_window_destroy(proton_window_handle_t window);
PROTON_API int32_t proton_window_show(proton_window_handle_t window);
PROTON_API int32_t proton_window_hide(proton_window_handle_t window);
PROTON_API int32_t proton_window_close(proton_window_handle_t window);
PROTON_API int32_t proton_window_focus(proton_window_handle_t window);
PROTON_API int32_t proton_window_set_title(proton_window_handle_t window,
                                           const char *title);
PROTON_API int32_t proton_window_set_size(proton_window_handle_t window,
                                          int32_t width, int32_t height);
PROTON_API int32_t proton_window_minimize(proton_window_handle_t window);
PROTON_API int32_t proton_window_maximize(proton_window_handle_t window);
PROTON_API int32_t proton_window_restore(proton_window_handle_t window);
PROTON_API int32_t proton_window_set_fullscreen(proton_window_handle_t window,
                                                int32_t fullscreen);
PROTON_API int32_t proton_window_set_position(proton_window_handle_t window,
                                              int32_t x, int32_t y);
PROTON_API int32_t proton_window_set_always_on_top(proton_window_handle_t window,
                                                   int32_t always_on_top);
PROTON_API int32_t proton_window_set_zoom_percent(proton_window_handle_t window,
                                                  int32_t zoom_percent);
PROTON_API int32_t proton_window_state_json(proton_window_handle_t window,
                                            char *buffer, int32_t buffer_len,
                                            int32_t *out_required_len);
PROTON_API int32_t proton_window_set_close_interception(
    proton_window_handle_t window, int32_t enabled);
PROTON_API int32_t proton_window_respond_close_request(
    proton_window_handle_t window, int64_t request_id, int32_t allow);
PROTON_API int32_t proton_window_load_url(proton_window_handle_t window,
                                          const char *url);
PROTON_API int32_t proton_window_load_html(proton_window_handle_t window,
                                           const char *html,
                                           const char *base_url);
PROTON_API int32_t proton_window_load_asset(proton_window_handle_t window,
                                            const char *html,
                                            const char *document_url,
                                            const char *asset_root);
PROTON_API int32_t proton_window_eval(proton_window_handle_t window,
                                      const char *script);
PROTON_API int32_t proton_window_browser_command_json(
    proton_window_handle_t window, const char *command_json);
PROTON_API int32_t proton_window_respond_browser_request_json(
    proton_window_handle_t window, const char *response_json);
PROTON_API int32_t proton_window_emit_bridge_event_json(
    proton_window_handle_t window, const char *event_json);
PROTON_API int32_t proton_window_bridge_state_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_window_take_bridge_failure_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
PROTON_API int32_t proton_window_begin_message_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_confirm_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_open_file_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_save_file_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_begin_choose_directory_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
PROTON_API int32_t proton_window_poll_dialog_result(
    proton_window_handle_t window, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len);

/* Session cookie and cache management.

   Cookie get uses a begin/poll pattern because the CEF cookie visitor fires
   on the UI thread: call proton_window_cookie_begin_get_json to start the
   visit, then call proton_window_cookie_poll_get_json on each message loop
   iteration until it returns PROTON_OK. Cookie set, delete, flush, and cache
   clear are fire-and-forget: they return once the request has been accepted
   by the cookie manager or request context.

   All functions require a native engine window and return
   PROTON_ERR_UNSUPPORTED otherwise. */

/* Begin retrieving cookies. If url_utf8 is NULL or empty, all cookies are
   retrieved; otherwise only cookies matching the URL are returned. If
   include_http_only is 1, HTTP-only cookies are included. Returns
   PROTON_ERR_BUSY if a cookie get is already in progress for this window. */
PROTON_API int32_t proton_window_cookie_begin_get_json(
    proton_window_handle_t window, const char *url_utf8,
    int32_t include_http_only);

/* Poll for the result of a cookie get operation. Writes a JSON array of
   cookie objects to buffer. Each cookie object has: name, value, domain,
   path, secure, http_only, same_site, has_expires, expires (optional),
   creation, last_access.
   Returns PROTON_OK when the result is ready, PROTON_ERR_PENDING if the
   operation is still in progress. */
PROTON_API int32_t proton_window_cookie_poll_get_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);

/* Set a cookie from a JSON object. The JSON must contain "url", "name",
   and "value", and may contain "domain", "path", "secure", "http_only",
   "same_site", "expires". Fire-and-forget. */
PROTON_API int32_t proton_window_cookie_set_json(
    proton_window_handle_t window, const char *cookie_json);

/* Delete cookies. If url_utf8 is NULL or empty, all cookies are deleted.
   If name_utf8 is non-NULL, only cookies with that name matching the URL
   are deleted. Fire-and-forget. */
PROTON_API int32_t proton_window_cookie_delete(
    proton_window_handle_t window, const char *url_utf8,
    const char *name_utf8);

/* Flush the cookie store to disk. Fire-and-forget. */
PROTON_API int32_t proton_window_cookie_flush(proton_window_handle_t window);

/* Clear the HTTP cache for the window's request context. Fire-and-forget. */
PROTON_API int32_t proton_window_clear_cache(proton_window_handle_t window);

/* Enumerates all connected displays.
   Returns a JSON array of screen objects. Each screen has:
   id, x, y, width, height, work_x, work_y, work_width, work_height,
   scale_factor_percent, is_primary.
   Returns PROTON_ERR_UNSUPPORTED if the native engine is not available. */
PROTON_API int32_t proton_screen_enumerate_json(char *buffer,
                                                int32_t buffer_len,
                                                int32_t *out_required_len);

/* Creates a private artifact staging transaction for a streaming update.

   The archive path never crosses the ABI. Chunks written to the returned
   handle are the exact bytes later expanded by proton_update_stage_install,
   so authenticating those chunks does not introduce a path-based TOCTOU
   window. The handle is owned by the calling thread.

   Application updates should pass NULL or an empty parent_dir. Proton then
   creates the stage beside the running .app, guaranteeing that final bundle
   replacement stays on one filesystem. An explicit absolute parent is kept
   for low-level hosts and tests, but is rejected unless it is on that same
   filesystem. */
PROTON_API int32_t proton_update_stage_begin(
    const char *parent_dir, int64_t expected_size,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len);
PROTON_API int32_t proton_update_stage_begin_revision(
    const char *parent_dir, int64_t expected_size, uint64_t target_revision,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len);
PROTON_API int32_t proton_update_stage_write(
    proton_update_stage_id_t stage, const char *chunk, int32_t chunk_len,
    char *error, int32_t error_len);
PROTON_API int32_t proton_update_stage_install(
    proton_update_stage_id_t stage, char *error, int32_t error_len);
PROTON_API int32_t proton_update_stage_install_outcome(
    proton_update_stage_id_t stage, int32_t *out_outcome, char *error,
    int32_t error_len);
PROTON_API int32_t proton_update_stage_abort(
    proton_update_stage_id_t stage, char *error, int32_t error_len);

/* Reads the monotonic update revision embedded in the installed application.

   This is an optimistic process-local check used to avoid downloading an
   update another task already installed. The install transaction repeats the
   comparison while holding the cross-process commit lock. */
PROTON_API int32_t proton_update_current_revision(
    uint64_t *out_revision, char *error, int32_t error_len);

/* Removes older application bundles retained by successful update swaps.

   Hosts call this only after the replacement has completed application
   startup. Proton removes only its reserved sibling bundle names whose code
   signing identity matches the running application and whose update revision
   is older. A cleanup failure must not make an otherwise healthy application
   fail to start. */
PROTON_API int32_t proton_update_cleanup_previous(char *error,
                                                  int32_t error_len);

/* Installs an authenticated update archive over the running application.

   Expansion, bundle signature validation, and replacement happen in one
   native transaction. The expanded bundle path is never exposed between
   validation and use. Implemented on macOS; other platforms report
   PROTON_ERR_UNSUPPORTED rather than pretending to have installed anything. */
PROTON_API int32_t proton_update_install(const char *archive,
                                         int32_t archive_len,
                                         const char *parent_dir, char *error,
                                         int32_t error_len);

/* Asks the system to start the replaced application. The caller exits
   afterwards.

   Success means the request was accepted, not that the application is running:
   the platform decides that asynchronously and does not report back. */
PROTON_API int32_t proton_update_relaunch(char *error, int32_t error_len);
/* Web contents views: child web views hosted inside a window's content area,
   each backed by its own browser instance. Bounds use a top-left origin in
   the window's content coordinate space, matching the Electron
   WebContentsView model. Requires the "web_contents_view" runtime feature. */
PROTON_API int32_t proton_view_create_json(proton_window_handle_t window,
                                           const char *config_json,
                                           proton_view_handle_t *out_view);
PROTON_API int32_t proton_view_destroy(proton_view_handle_t view);
PROTON_API int32_t proton_view_set_bounds(proton_view_handle_t view, int32_t x,
                                          int32_t y, int32_t width,
                                          int32_t height);
PROTON_API int32_t proton_view_set_visible(proton_view_handle_t view,
                                           int32_t visible);
PROTON_API int32_t proton_view_set_z_order(proton_view_handle_t view,
                                           int32_t z_order);
PROTON_API int32_t proton_view_load_url(proton_view_handle_t view,
                                        const char *url);
PROTON_API int32_t proton_view_load_html(proton_view_handle_t view,
                                         const char *html,
                                         const char *base_url);
PROTON_API int32_t proton_view_eval(proton_view_handle_t view, const char *script);
PROTON_API int32_t proton_view_browser_command_json(
    proton_view_handle_t view, const char *command_json);
PROTON_API int32_t proton_view_state_json(proton_view_handle_t view, char *buffer,
                                          int32_t buffer_len,
                                          int32_t *out_required_len);

/* Native image management. Images are standalone objects backed by CEF's
   cef_image_t. They are not tied to a runtime or window and can be created
   on any thread. Use proton_image_create_empty to get a handle, add
   representations with add_png/add_jpeg/add_bitmap, query with is_empty and
   get_size_json, export with to_png/to_jpeg/to_bitmap, and release with
   proton_image_destroy. All functions return PROTON_ERR_UNSUPPORTED when
   the native engine is not available. */

PROTON_API int32_t proton_image_create_empty(proton_image_handle_t *out_image);
PROTON_API int32_t proton_image_destroy(proton_image_handle_t image);
PROTON_API int32_t proton_image_add_png(proton_image_handle_t image,
                                        const uint8_t *data,
                                        int32_t data_len,
                                        float scale_factor);
PROTON_API int32_t proton_image_add_jpeg(proton_image_handle_t image,
                                         const uint8_t *data,
                                         int32_t data_len,
                                         float scale_factor);
PROTON_API int32_t proton_image_add_bitmap(proton_image_handle_t image,
                                           const uint8_t *data,
                                           int32_t data_len,
                                           int32_t width, int32_t height,
                                           float scale_factor);
PROTON_API int32_t proton_image_is_empty(proton_image_handle_t image);
PROTON_API int32_t proton_image_get_size_json(proton_image_handle_t image,
                                              char *buffer,
                                              int32_t buffer_len,
                                              int32_t *out_required_len);
PROTON_API int32_t proton_image_to_png(proton_image_handle_t image,
                                       float scale_factor,
                                       int32_t with_transparency,
                                       uint8_t *buffer,
                                       int32_t buffer_len,
                                       int32_t *out_required_len,
                                       int32_t *out_width,
                                       int32_t *out_height);
PROTON_API int32_t proton_image_to_jpeg(proton_image_handle_t image,
                                        float scale_factor,
                                        int32_t quality, uint8_t *buffer,
                                        int32_t buffer_len,
                                        int32_t *out_required_len,
                                        int32_t *out_width,
                                        int32_t *out_height);
PROTON_API int32_t proton_image_to_bitmap(proton_image_handle_t image,
                                          float scale_factor,
                                          uint8_t *buffer,
                                          int32_t buffer_len,
                                          int32_t *out_required_len,
                                          int32_t *out_width,
                                          int32_t *out_height);

PROTON_API int32_t proton_last_error_message(char *buffer,
                                             int32_t buffer_len);

#ifdef __cplusplus
}
#endif

#endif
