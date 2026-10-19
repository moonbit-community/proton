#ifndef PROTON_EVENT_H
#define PROTON_EVENT_H

#include "proton_internal.h"
#include "proton_native.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
typedef CRITICAL_SECTION proton_event_mutex_t;
#else
#include <pthread.h>
typedef pthread_mutex_t proton_event_mutex_t;
#endif

/* The event ABI contract. Numeric tags and named payload fields live here.
 * MoonBit mirrors these enums; the native contract test checks their names/tags. */
#define PROTON_EVENT_KINDS(X) \
  X(WINDOW_CREATED, 1, WindowCreated) \
  X(WINDOW_CLOSED, 2, WindowClosed) \
  X(WINDOW_STATE_CHANGED, 3, WindowStateChanged) \
  X(WINDOW_CLOSE_REQUESTED, 4, WindowCloseRequested) \
  X(BRIDGE_LIFECYCLE_CHANGED, 5, BridgeLifecycleChanged) \
  X(BRIDGE_REQUEST_CANCELLED, 6, BridgeRequestCancelled) \
  X(MENU_COMMAND, 7, MenuCommand) \
  X(OPEN_URLS, 8, OpenUrls) \
  X(OPEN_FILES, 9, OpenFiles) \
  X(REOPEN, 10, Reopen) \
  X(NOTIFICATION_RESULT, 11, NotificationResult) \
  X(BROWSER_NEW_WINDOW_REQUESTED, 13, BrowserNewWindowRequested) \
  X(BROWSER_DOWNLOAD_REQUESTED, 14, BrowserDownloadRequested) \
  X(BROWSER_CERTIFICATE_ERROR, 15, BrowserCertificateError) \
  X(BROWSER_MEDIA_PERMISSION_REQUESTED, 16, BrowserMediaPermissionRequested) \
  X(BROWSER_DOWNLOAD_UPDATED, 17, BrowserDownloadUpdated) \
  X(BRIDGE_REQUEST, 22, BridgeRequest) \
  X(DIALOG_COMPLETED, 23, DialogCompleted) \
  X(COOKIE_GET_COMPLETED, 24, CookieGetCompleted) \
  X(RESOURCE_REQUESTED, 25, ResourceRequested) \
  X(RESOURCE_REQUEST_CANCELLED, 26, ResourceRequestCancelled) \
  X(NOTIFICATION_CLICKED, 27, NotificationClicked) \
  X(QUIT_REQUESTED, 28, QuitRequested) \
  X(VIEW_CLOSED, 29, ViewClosed) \
  X(BROWSER_LOADING_CHANGED, 30, BrowserLoadingChanged) \
  X(BROWSER_NAVIGATED, 31, BrowserNavigated) \
  X(BROWSER_TITLE_UPDATED, 32, BrowserTitleUpdated) \
  X(BROWSER_LOAD_FAILED, 33, BrowserLoadFailed) \
  X(BROWSER_FIND_RESULT, 34, BrowserFindResult) \
  X(BROWSER_PDF_PRINT_FINISHED, 36, BrowserPdfPrintFinished) \
  X(APP_ACTIVATION, 37, AppActivation) \
  X(BROWSER_RESOURCE_RESPONSE, 38, BrowserResourceResponse) \
  X(BROWSER_RESOURCE_COMPLETED, 39, BrowserResourceCompleted) \
  X(BROWSER_RENDERER_TERMINATED, 40, BrowserRendererTerminated) \
  X(BROWSER_RESOURCE_REQUESTED, 42, BrowserResourceRequested) \
  X(NATIVE_THEME_CHANGED, 43, NativeThemeChanged) \
  X(TASKBAR_BUTTON_CLICKED, 44, TaskbarButtonClicked)

typedef enum proton_event_kind {
#define PROTON_EVENT_KIND(name, tag, mb_name) PROTON_EVENT_##name = tag,
  PROTON_EVENT_KINDS(PROTON_EVENT_KIND)
#undef PROTON_EVENT_KIND
} proton_event_kind_t;

#define PROTON_EVENT_INT64_FIELDS(X) \
  X(window, Window) \
  X(view, View) \
  X(request_id, RequestId) \
  X(revision, Revision) \
  X(received_bytes, ReceivedBytes) \
  X(total_bytes, TotalBytes)

typedef enum proton_event_int64_field {
#define PROTON_EVENT_FIELD(name, mb_name) PROTON_EVENT_INT64_##name,
  PROTON_EVENT_INT64_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
} proton_event_int64_field_t;

#define PROTON_EVENT_INT_FIELDS(X) \
  X(status, Status) \
  X(error_code, ErrorCode) \
  X(download_id, DownloadId) \
  X(permissions, Permissions) \
  X(percent, Percent) \
  X(matches, Matches) \
  X(active_match_ordinal, ActiveMatchOrdinal) \
  X(selection_x, SelectionX) \
  X(selection_y, SelectionY) \
  X(selection_width, SelectionWidth) \
  X(selection_height, SelectionHeight) \
  X(success, Success) \
  X(user_gesture, UserGesture) \
  X(has_payload, HasPayload) \
  X(is_loading, IsLoading) \
  X(final_update, FinalUpdate) \
  X(allowed, Allowed) \
  X(dark_colors, DarkColors) \
  X(high_contrast_colors, HighContrastColors) \
  X(reopen_when_empty, ReopenWhenEmpty)

typedef enum proton_event_int_field {
#define PROTON_EVENT_FIELD(name, mb_name) PROTON_EVENT_INT_##name,
  PROTON_EVENT_INT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
} proton_event_int_field_t;

#define PROTON_EVENT_TEXT_FIELDS(X) \
  X(url, Url) \
  X(title, Title) \
  X(message, Message) \
  X(result, Result) \
  X(path, Path) \
  X(command_id, CommandId) \
  X(suggested_name, SuggestedName) \
  X(state, State) \
  X(activation, Activation) \
  X(notification_payload, NotificationPayload) \
  X(method, Method)

typedef enum proton_event_text_field {
#define PROTON_EVENT_FIELD(name, mb_name) PROTON_EVENT_TEXT_##name,
  PROTON_EVENT_TEXT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
} proton_event_text_field_t;

typedef struct proton_event {
  proton_event_kind_t kind;
#define PROTON_EVENT_FIELD(name, mb_name) int64_t name;
  PROTON_EVENT_INT64_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
#define PROTON_EVENT_FIELD(name, mb_name) int32_t name;
  PROTON_EVENT_INT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
#define PROTON_EVENT_FIELD(name, mb_name) char *name;
  PROTON_EVENT_TEXT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
  int32_t window_state[21];
  char **items;
  int32_t item_count;
  void *payload;
  void (*destroy_payload)(void *payload);
  struct proton_event *next;
} proton_event_t;

typedef struct proton_event_queue {
  proton_event_t *head;
  proton_event_t *tail;
  uint32_t count;
  proton_event_mutex_t mutex;
} proton_event_queue_t;

typedef bool (*proton_event_sink_fn)(void *user_data, proton_event_t *event);

PROTON_INTERNAL proton_event_t *proton_event_create(proton_event_kind_t kind);
PROTON_INTERNAL proton_event_t *proton_event_create_window(
    proton_event_kind_t kind, int64_t window);
PROTON_INTERNAL bool proton_event_set_text(char **field, const char *value);
PROTON_INTERNAL bool proton_event_set_items(proton_event_t *event,
                                            const char *const *items,
                                            int32_t item_count);
PROTON_INTERNAL bool proton_event_set_payload(
    proton_event_t *event, void *payload, void (*destroy_payload)(void *));
PROTON_INTERNAL proton_event_t *proton_internal_event_create(void);
PROTON_INTERNAL void proton_event_clear(proton_event_t *event);
PROTON_INTERNAL void proton_event_destroy(proton_event_t *event);

PROTON_INTERNAL bool proton_event_queue_init(proton_event_queue_t *queue);
PROTON_INTERNAL void proton_event_queue_destroy(proton_event_queue_t *queue);
PROTON_INTERNAL bool proton_event_queue_push(proton_event_queue_t *queue,
                                             proton_event_t *event);
PROTON_INTERNAL proton_event_t *proton_event_queue_pop(
    proton_event_queue_t *queue);
PROTON_INTERNAL uint32_t proton_event_queue_count(
    proton_event_queue_t *queue);
PROTON_INTERNAL void proton_event_dispatch_begin(void);
PROTON_INTERNAL void proton_event_dispatch_end(void);
PROTON_INTERNAL void proton_event_bind_sink(proton_event_sink_fn sink,
                                            void *user_data);
PROTON_INTERNAL void proton_event_unbind_sink(void *user_data);
/* Transfers ownership on success; the caller retains ownership on failure. */
PROTON_INTERNAL bool proton_event_try_publish(proton_event_t *event);
/* Consumes event on both success and failure. */
PROTON_INTERNAL bool proton_event_publish(proton_event_t *event);
PROTON_INTERNAL bool proton_event_publish_window_close_requested(
    int64_t window, uint64_t request_id);

#endif
