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

typedef enum proton_event_kind {
  PROTON_EVENT_WINDOW_CREATED = 1,
  PROTON_EVENT_WINDOW_CLOSED = 2,
  PROTON_EVENT_WINDOW_STATE_CHANGED = 3,
  PROTON_EVENT_WINDOW_CLOSE_REQUESTED = 4,
  PROTON_EVENT_BRIDGE_LIFECYCLE_CHANGED = 5,
  PROTON_EVENT_BRIDGE_REQUEST_CANCELLED = 6,
  PROTON_EVENT_MENU_COMMAND = 7,
  PROTON_EVENT_OPEN_URLS = 8,
  PROTON_EVENT_OPEN_FILES = 9,
  PROTON_EVENT_REOPEN = 10,
  PROTON_EVENT_NOTIFICATION_RESULT = 11,
  PROTON_EVENT_BROWSER_NAVIGATION_REQUESTED = 12,
  PROTON_EVENT_BROWSER_POPUP_REQUESTED = 13,
  PROTON_EVENT_BROWSER_DOWNLOAD_REQUESTED = 14,
  PROTON_EVENT_BROWSER_CERTIFICATE_ERROR = 15,
  PROTON_EVENT_BROWSER_MEDIA_PERMISSION_REQUESTED = 16,
  PROTON_EVENT_BROWSER_DOWNLOAD_UPDATED = 17,
  PROTON_EVENT_VIEW_LOADING_CHANGED = 18,
  PROTON_EVENT_VIEW_NAVIGATED = 19,
  PROTON_EVENT_VIEW_TITLE_UPDATED = 20,
  PROTON_EVENT_VIEW_LOAD_FAILED = 21,
  PROTON_EVENT_BRIDGE_REQUEST = 22,
  PROTON_EVENT_DIALOG_COMPLETED = 23,
  PROTON_EVENT_COOKIE_GET_COMPLETED = 24,
  PROTON_EVENT_RESOURCE_REQUESTED = 25,
  PROTON_EVENT_RESOURCE_REQUEST_CANCELLED = 26,
} proton_event_kind_t;

typedef struct proton_event {
  proton_event_kind_t kind;
  int64_t window;
  int64_t view;
  int64_t request_id;
  int64_t revision;
  int64_t int64_a;
  int64_t int64_b;
  int32_t int_a;
  int32_t int_b;
  int32_t int_c;
  int32_t bool_a;
  int32_t bool_b;
  int32_t window_state[21];
  char *text_a;
  char *text_b;
  char *text_c;
  char **items;
  int32_t item_count;
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
PROTON_INTERNAL bool proton_event_try_publish(proton_event_t *event);
PROTON_INTERNAL bool proton_event_publish(proton_event_t *event);

#endif
