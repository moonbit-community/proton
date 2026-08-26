#ifndef PROTON_NATIVE_H
#define PROTON_NATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PROTON_ABI_VERSION 1
#define PROTON_INVALID_HANDLE 0

#define PROTON_WAIT_NONE 0u
#define PROTON_WAIT_EVENT (1u << 0)
#define PROTON_WAIT_PLATFORM (1u << 2)
#define PROTON_WAIT_ALL (PROTON_WAIT_EVENT | PROTON_WAIT_PLATFORM)

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
  PROTON_ERR_STALE_RESOURCE_REQUEST = -18,
  PROTON_ERR_BUSY = -19
};

enum {
  PROTON_UPDATE_INSTALLED = 0,
  PROTON_UPDATE_ALREADY_INSTALLED = 1
};

int32_t proton_abi_version(void);
proton_runtime_handle_t proton_runtime_null(void);
proton_window_handle_t proton_window_null(void);
proton_view_handle_t proton_view_null(void);
proton_image_handle_t proton_image_null(void);
int64_t proton_window_logical_id(proton_window_handle_t window);
int64_t proton_view_logical_id(proton_view_handle_t view);
int32_t proton_runtime_platform_id(char *buffer,
                                   int32_t buffer_len,
                                   int32_t *out_required_len);
int32_t proton_system_preferred_languages_json(
    char *buffer, int32_t buffer_len, int32_t *out_required_len);
int32_t proton_app_instance_acquire(
    const char *identifier, const char *activation_json,
    proton_app_instance_id_t *out_instance, int32_t *out_primary);
int32_t proton_app_instance_attach_runtime(
    proton_app_instance_id_t instance, proton_runtime_handle_t runtime);
int32_t
proton_app_instance_destroy(proton_app_instance_id_t instance);

int32_t proton_runtime_destroy(proton_runtime_handle_t runtime);
int32_t proton_runtime_complete_resource_request(
    proton_runtime_handle_t runtime, int64_t request_id, int32_t status,
    const char *mime_type, const uint8_t *data, int32_t data_len);
/* Wakes a blocked host-loop poll, or makes the next one return immediately.
 * Takes no handle because the foreign waiting thread owns none. */
void proton_runtime_signal_wakeup(void);

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
 * loop is running, so the host must keep calling it. */
int32_t proton_host_loop_begin(void);
int32_t proton_host_loop_poll(int32_t timeout_ms,
                                         uint32_t *out_ready_mask);
void proton_host_loop_end(void);
int32_t proton_runtime_respond_bridge_request(
    proton_runtime_handle_t runtime, int64_t request_id, int32_t ok,
    const char *body_json);
int32_t proton_runtime_begin_message_dialog(
    proton_runtime_handle_t runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);

int32_t proton_notification_is_supported(int32_t *out_supported);
int32_t proton_notification_show(const char *title,
                                            const char *body,
                                            const char *payload,
                                            int32_t has_payload);
int32_t proton_notification_cleanup(void);

int32_t proton_window_destroy(proton_window_handle_t window);
int32_t proton_window_show(proton_window_handle_t window);
int32_t proton_window_hide(proton_window_handle_t window);
int32_t proton_window_close(proton_window_handle_t window);
int32_t proton_window_focus(proton_window_handle_t window);
int32_t proton_window_set_title(proton_window_handle_t window,
                                           const char *title);
int32_t proton_window_set_size(proton_window_handle_t window,
                                          int32_t width, int32_t height);
int32_t proton_window_minimize(proton_window_handle_t window);
int32_t proton_window_maximize(proton_window_handle_t window);
int32_t proton_window_restore(proton_window_handle_t window);
int32_t proton_window_set_fullscreen(proton_window_handle_t window,
                                                int32_t fullscreen);
int32_t proton_window_set_position(proton_window_handle_t window,
                                              int32_t x, int32_t y);
int32_t proton_window_set_always_on_top(proton_window_handle_t window,
                                                   int32_t always_on_top);
int32_t proton_window_set_resizable(proton_window_handle_t window,
                                    int32_t resizable);
int32_t proton_window_set_minimum_size(proton_window_handle_t window,
                                       int32_t width, int32_t height);
int32_t proton_window_set_maximum_size(proton_window_handle_t window,
                                       int32_t width, int32_t height);
int32_t proton_window_set_movable(proton_window_handle_t window,
                                  int32_t movable);
int32_t proton_window_set_zoom_percent(proton_window_handle_t window,
                                                  int32_t zoom_percent);
/* Matches Electron's progress value semantics: negative clears the indicator,
   [0, 1] is determinate, and values above 1 are indeterminate. */
int32_t proton_window_set_progress_bar(proton_window_handle_t window,
                                       double progress);
/* Matches Electron's flashFrame flag semantics. */
int32_t proton_window_flash_frame(proton_window_handle_t window,
                                  int32_t flash);
/* Writes the 21 integer fields of the current window state into out_fields.
   The field order is private to the matching MoonBit wrapper. */
int32_t proton_window_get_state(proton_window_handle_t window,
                                int32_t *out_fields,
                                int32_t field_capacity);
int32_t proton_window_set_close_interception(
    proton_window_handle_t window, int32_t enabled);
int32_t proton_window_respond_close_request(
    proton_window_handle_t window, int64_t request_id, int32_t allow);
int32_t proton_window_load_url(proton_window_handle_t window,
                                          const char *url);
int32_t proton_window_eval(proton_window_handle_t window,
                                      const char *script);
int32_t proton_window_browser_command_json(
    proton_window_handle_t window, const char *command_json);
int32_t proton_window_respond_browser_request_json(
    proton_window_handle_t window, const char *response_json);
int32_t proton_window_emit_bridge_event_json(
    proton_window_handle_t window, const char *event_json);
int32_t proton_window_bridge_state_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
int32_t proton_window_take_bridge_failure_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);
int32_t proton_window_begin_message_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
int32_t proton_window_begin_confirm_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog);
int32_t proton_window_begin_open_file_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
int32_t proton_window_begin_save_file_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
int32_t proton_window_begin_choose_directory_dialog(
    proton_window_handle_t window, const char *title_utf8,
    int32_t title_len, const char *path_utf8, int32_t path_len,
    int64_t *out_dialog);
int32_t proton_window_cancel_dialog(proton_window_handle_t window,
                                    int64_t dialog);
/* Session cookie and cache management.

   Cookie get completion is delivered through the runtime event queue. Cookie
   set, delete, flush, and cache clear are fire-and-forget: they return once
   the request has been accepted by the cookie manager or request context.

   All functions require a native engine window and return
   PROTON_ERR_UNSUPPORTED otherwise. */

/* Begin retrieving cookies. Completion is delivered through the runtime event
   queue with the returned request id. Returns PROTON_ERR_BUSY if a cookie get
   is already in progress for this window. */
int32_t proton_window_cookie_begin_get_json(
    proton_window_handle_t window, const char *url_utf8,
    int32_t include_http_only, int64_t *out_request_id);

/* Sets a cookie. Optional domain/path values are represented by empty strings;
   same_site uses 0=unspecified, 1=no_restriction, 2=lax, 3=strict. */
int32_t proton_window_cookie_set(
    proton_window_handle_t window, const char *url_utf8,
    const char *name_utf8, const char *value_utf8,
    const char *domain_utf8, const char *path_utf8,
    int32_t secure, int32_t http_only, int32_t same_site);

/* Delete cookies. If url_utf8 is NULL or empty, all cookies are deleted.
   If name_utf8 is non-NULL, only cookies with that name matching the URL
   are deleted. Fire-and-forget. */
int32_t proton_window_cookie_delete(
    proton_window_handle_t window, const char *url_utf8,
    const char *name_utf8);

/* Flush the cookie store to disk. Fire-and-forget. */
int32_t proton_window_cookie_flush(proton_window_handle_t window);

/* Clear the HTTP cache for the window's request context. Fire-and-forget. */
int32_t proton_window_clear_cache(proton_window_handle_t window);

/* Enumerates connected displays into caller-owned integer storage. Each
   display occupies 11 fields in the order consumed by the MoonBit wrapper. */
int32_t proton_screen_enumerate(int32_t *out_fields,
                                int32_t field_capacity,
                                int32_t *out_screen_count);

/* Creates a private artifact staging transaction for a streaming update.

   The artifact path never crosses the ABI. Chunks written to the returned
   handle are the exact bytes later consumed by proton_update_stage_install,
   so authenticating those chunks does not introduce a path-based TOCTOU
   window. The handle is owned by the calling thread.

   Application updates should pass NULL or an empty parent_dir. Proton then
   selects the platform's safe staging location: beside rename-based macOS and
   Linux artifacts, or in the per-user temporary directory for a Windows
   installer that later elevates. An explicit absolute parent is kept for
   low-level hosts and tests. */
int32_t proton_update_stage_begin(
    const char *parent_dir, int64_t expected_size,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len);
int32_t proton_update_stage_begin_revision(
    const char *parent_dir, int64_t expected_size, uint64_t target_revision,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len);
int32_t proton_update_stage_write(
    proton_update_stage_id_t stage, const char *chunk, int32_t chunk_len,
    char *error, int32_t error_len);
int32_t proton_update_stage_install(
    proton_update_stage_id_t stage, char *error, int32_t error_len);
int32_t proton_update_stage_install_outcome(
    proton_update_stage_id_t stage, int32_t *out_outcome, char *error,
    int32_t error_len);
int32_t proton_update_stage_abort(
    proton_update_stage_id_t stage, char *error, int32_t error_len);

/* Reads the monotonic update revision embedded in the installed application.

   This is an optimistic process-local check used to avoid downloading an
   update another task already installed. The install transaction repeats the
   comparison while holding the cross-process commit lock. */
int32_t proton_update_current_revision(
    uint64_t *out_revision, char *error, int32_t error_len);

/* Removes older application artifacts retained by successful update swaps.

   Hosts call this only after the replacement has completed application
   startup. macOS validates a retained bundle's signing identity and revision;
   Linux removes the reserved previous AppImage. Windows leaves its
   administrator-owned previous tree for the next elevated update. A cleanup
   failure must not make an otherwise healthy application fail to start. */
int32_t proton_update_cleanup_previous(char *error,
                                                  int32_t error_len);

/* Consumes an authenticated update artifact for the running application.

   macOS validates and replaces an application bundle, Linux swaps an AppImage,
   and Windows locks an NSIS installer until proton_update_relaunch invokes it
   through UAC. Managed Linux installations and portable Windows directories
   report PROTON_ERR_UNSUPPORTED. */
int32_t proton_update_install(const char *archive,
                                         int32_t archive_len,
                                         const char *parent_dir, char *error,
                                         int32_t error_len);

/* Asks the system to finish the prepared replacement and start it. The caller
   exits afterwards. On Windows this starts the installer that performs both
   actions; macOS and Linux start the artifact already moved into place.

   Success means the request was accepted, not that the application is running:
   the platform decides that asynchronously and does not report back. */
int32_t proton_update_relaunch(char *error, int32_t error_len);
/* Web contents views: child web views hosted inside a window's content area,
   each backed by its own browser instance. Bounds use a top-left origin in
   the window's content coordinate space, matching the Electron
   WebContentsView model. Requires the "web_contents_view" runtime feature. */
int32_t proton_view_destroy(proton_view_handle_t view);
int32_t proton_view_set_bounds(proton_view_handle_t view, int32_t x,
                                          int32_t y, int32_t width,
                                          int32_t height);
int32_t proton_view_set_visible(proton_view_handle_t view,
                                           int32_t visible);
int32_t proton_view_set_z_order(proton_view_handle_t view,
                                           int32_t z_order);
int32_t proton_view_load_url(proton_view_handle_t view,
                                        const char *url);
int32_t proton_view_eval(proton_view_handle_t view, const char *script);
int32_t proton_view_browser_command_json(
    proton_view_handle_t view, const char *command_json);
/* Writes the six integer fields of the current view state into out_fields. */
int32_t proton_view_get_state(proton_view_handle_t view,
                              int32_t *out_fields,
                              int32_t field_capacity);

/* Native image management. Images are standalone objects backed by CEF's
   cef_image_t. They are not tied to a runtime or window and can be created
   on any thread. Use proton_image_create_empty to get a handle, add
   representations with add_png/add_jpeg/add_bitmap, query with is_empty and
   get_size, export with to_png/to_jpeg/to_bitmap, and release with
   proton_image_destroy. All functions return PROTON_ERR_UNSUPPORTED when
   the native engine is not available. */

int32_t proton_image_create_empty(proton_image_handle_t *out_image);
int32_t proton_image_destroy(proton_image_handle_t image);
int32_t proton_image_add_png(proton_image_handle_t image,
                                        const uint8_t *data,
                                        int32_t data_len,
                                        float scale_factor);
int32_t proton_image_add_jpeg(proton_image_handle_t image,
                                         const uint8_t *data,
                                         int32_t data_len,
                                         float scale_factor);
int32_t proton_image_add_bitmap(proton_image_handle_t image,
                                           const uint8_t *data,
                                           int32_t data_len,
                                           int32_t width, int32_t height,
                                           float scale_factor);
int32_t proton_image_is_empty(proton_image_handle_t image);
int32_t proton_image_get_size(proton_image_handle_t image,
                              int32_t *out_width,
                              int32_t *out_height);
int32_t proton_image_to_png(proton_image_handle_t image,
                                       float scale_factor,
                                       int32_t with_transparency,
                                       uint8_t *buffer,
                                       int32_t buffer_len,
                                       int32_t *out_required_len,
                                       int32_t *out_width,
                                       int32_t *out_height);
int32_t proton_image_to_jpeg(proton_image_handle_t image,
                                        float scale_factor,
                                        int32_t quality, uint8_t *buffer,
                                        int32_t buffer_len,
                                        int32_t *out_required_len,
                                        int32_t *out_width,
                                        int32_t *out_height);
int32_t proton_image_to_bitmap(proton_image_handle_t image,
                                          float scale_factor,
                                          uint8_t *buffer,
                                          int32_t buffer_len,
                                          int32_t *out_required_len,
                                          int32_t *out_width,
                                          int32_t *out_height);

int32_t proton_last_error_message(char *buffer,
                                             int32_t buffer_len);

#ifdef __cplusplus
}
#endif

#endif
