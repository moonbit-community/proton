#ifndef PROTON_STATE_H
#define PROTON_STATE_H

#include "proton_engine.h"
#include "proton_event.h"
#include "proton_internal.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
typedef DWORD proton_thread_id_t;
#else
#include <pthread.h>
typedef pthread_t proton_thread_id_t;
#endif

#define PROTON_MAX_EVENT_BYTES 65536

typedef struct proton_runtime_slot proton_runtime_slot_t;
typedef struct proton_window_slot proton_window_slot_t;
typedef struct proton_view_slot proton_view_slot_t;
typedef struct proton_image_slot proton_image_slot_t;

typedef enum proton_runtime_lifecycle {
  PROTON_RUNTIME_ACTIVE = 0,
  PROTON_RUNTIME_DESTROYING = 1,
  PROTON_RUNTIME_DESTROYED = 2,
} proton_runtime_lifecycle_t;

typedef enum proton_window_lifecycle {
  PROTON_WINDOW_LIVE = 0,
  PROTON_WINDOW_CLOSE_REQUESTED = 1,
  PROTON_WINDOW_CLOSED = 2,
  PROTON_WINDOW_DESTROYING = 3,
  PROTON_WINDOW_DESTROYED = 4,
} proton_window_lifecycle_t;

typedef enum proton_view_lifecycle {
  PROTON_VIEW_LIVE = 0,
  PROTON_VIEW_DESTROYING = 1,
  PROTON_VIEW_DESTROYED = 2,
} proton_view_lifecycle_t;

struct proton_runtime_slot {
  proton_runtime_lifecycle_t lifecycle;
  proton_engine_runtime_t *engine_runtime;
  int64_t app_instance;
  proton_thread_id_t owner_thread;
  proton_event_queue_t events;
  int64_t next_bridge_request_id;
  int64_t next_window_id;
  int64_t next_view_id;
  proton_window_slot_t *windows;
  proton_view_slot_t *views;
};

struct proton_window_slot {
  proton_window_lifecycle_t lifecycle;
  bool visible;
  bool closed_event_sent;
  bool state_valid;
  uint64_t bridge_notified_revision;
  uint64_t close_request_notified_revision;
  int64_t logical_id;
  proton_runtime_slot_t *runtime;
  proton_engine_window_t *engine_window;
  int32_t width;
  int32_t height;
  proton_engine_window_state_t state;
  proton_window_slot_t *next;
};

struct proton_view_slot {
  proton_view_lifecycle_t lifecycle;
  int64_t logical_id;
  proton_runtime_slot_t *runtime;
  proton_window_slot_t *window;
  proton_engine_view_t *engine_view;
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t z_order;
  bool visible;
  proton_view_slot_t *next;
};

struct proton_image_slot {
  bool destroyed;
  proton_engine_image_t *engine_image;
};

PROTON_INTERNAL int32_t proton_runtime_slot_create(
    proton_engine_runtime_t *engine_runtime,
    proton_runtime_slot_t **out_runtime);
PROTON_INTERNAL void proton_runtime_slot_destroy(proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_get_runtime(
    proton_runtime_slot_t *runtime, proton_runtime_slot_t **out_runtime);
PROTON_INTERNAL int32_t proton_get_runtime_for_destroy(
    proton_runtime_slot_t *runtime, proton_runtime_slot_t **out_runtime);
PROTON_INTERNAL void proton_runtime_slot_begin_destroy(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_require_runtime_owner_thread(
    const proton_runtime_slot_t *runtime);
PROTON_INTERNAL bool proton_has_active_runtime(void);

PROTON_INTERNAL bool proton_runtime_enqueue_event(
    proton_runtime_slot_t *runtime, proton_event_t *event);
PROTON_INTERNAL bool proton_runtime_enqueue_window_event(
    proton_runtime_slot_t *runtime, proton_event_kind_t kind,
    int64_t window_id);
PROTON_INTERNAL bool proton_runtime_has_events(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL proton_event_t *proton_runtime_poll_event(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int64_t proton_runtime_reserve_window_id(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int64_t proton_runtime_reserve_view_id(
    proton_runtime_slot_t *runtime);

PROTON_INTERNAL int32_t proton_window_slot_create(
    proton_runtime_slot_t *runtime, proton_engine_window_t *engine_window,
    int64_t logical_id, int32_t width, int32_t height,
    proton_window_slot_t **out_window);
PROTON_INTERNAL void proton_window_slot_destroy(proton_window_slot_t *window);
PROTON_INTERNAL void proton_window_slot_request_close(
    proton_window_slot_t *window);
PROTON_INTERNAL void proton_window_slot_cancel_close(
    proton_window_slot_t *window);
PROTON_INTERNAL void proton_window_slot_mark_closed(
    proton_window_slot_t *window);
PROTON_INTERNAL void proton_window_slot_begin_destroy(
    proton_window_slot_t *window);
PROTON_INTERNAL int32_t proton_get_window(
    proton_window_slot_t *window, proton_window_slot_t **out_window);
PROTON_INTERNAL int32_t proton_get_window_for_destroy(
    proton_window_slot_t *window, proton_window_slot_t **out_window);
PROTON_INTERNAL int32_t proton_window_enqueue_closed_once(
    proton_runtime_slot_t *runtime, proton_window_slot_t *window);
PROTON_INTERNAL void proton_runtime_sync_engine_closed_windows(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_runtime_sync_engine_window_states(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_runtime_sync_engine_close_requests(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL void proton_runtime_sync_engine_bridge_lifecycle(
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_destroy_windows_for_runtime(
    proton_runtime_slot_t *runtime);

PROTON_INTERNAL int32_t proton_view_slot_create(
    proton_window_slot_t *window, proton_engine_view_t *engine_view,
    int64_t logical_id, int32_t x, int32_t y, int32_t width, int32_t height,
    int32_t z_order, bool visible, proton_view_slot_t **out_view);
PROTON_INTERNAL void proton_view_slot_destroy(proton_view_slot_t *view);
PROTON_INTERNAL void proton_view_slot_begin_destroy(proton_view_slot_t *view);
PROTON_INTERNAL int32_t proton_get_view(
    proton_view_slot_t *view, proton_view_slot_t **out_view);
PROTON_INTERNAL int32_t proton_get_view_for_destroy(
    proton_view_slot_t *view, proton_view_slot_t **out_view);
PROTON_INTERNAL void proton_destroy_views_for_window(
    proton_window_slot_t *window);

PROTON_INTERNAL int32_t proton_image_slot_create(
    proton_engine_image_t *engine_image, proton_image_slot_t **out_image);
PROTON_INTERNAL void proton_image_slot_destroy(proton_image_slot_t *image);
PROTON_INTERNAL int32_t proton_get_image(
    proton_image_slot_t *image, proton_image_slot_t **out_image);

#endif
