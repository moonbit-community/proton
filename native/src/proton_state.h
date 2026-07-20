#ifndef PROTON_STATE_H
#define PROTON_STATE_H

#include "proton_engine.h"
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

#define PROTON_MAX_EVENT_BYTES 512
#define PROTON_MAX_EVENTS 32

typedef struct {
  uint32_t generation;
  bool occupied;
  bool destroyed;
  bool engine_backed;
  bool running;
  bool quit_requested;
  proton_engine_runtime_t *engine_runtime;
  bool owner_thread_set;
  proton_thread_id_t owner_thread;
  char events[PROTON_MAX_EVENTS][PROTON_MAX_EVENT_BYTES];
  uint32_t event_head;
  uint32_t event_count;
  int64_t next_bridge_request_id;
} proton_runtime_slot_t;

typedef struct {
  uint32_t generation;
  bool occupied;
  bool destroyed;
  bool visible;
  bool closed_event_sent;
  proton_runtime_id_t runtime;
  proton_engine_window_t *engine_window;
  int32_t width;
  int32_t height;
  bool bridge_enabled;
  char *bridge_config_json;
} proton_window_slot_t;

PROTON_INTERNAL int32_t proton_runtime_slot_create(
    bool engine_backed, proton_engine_runtime_t *engine_runtime,
    proton_runtime_id_t *out_runtime, proton_runtime_slot_t **out_slot);
PROTON_INTERNAL void
proton_runtime_slot_destroy(proton_runtime_slot_t *slot);
PROTON_INTERNAL int32_t
proton_get_runtime(proton_runtime_id_t handle,
                   proton_runtime_slot_t **out_slot);
PROTON_INTERNAL int32_t proton_require_runtime_owner_thread(
    const proton_runtime_slot_t *runtime);
PROTON_INTERNAL bool proton_has_active_runtime(void);

PROTON_INTERNAL bool proton_runtime_enqueue_event(
    proton_runtime_slot_t *runtime, const char *event_json);
PROTON_INTERNAL bool proton_runtime_enqueue_window_event(
    proton_runtime_slot_t *runtime, const char *type,
    proton_window_id_t window);
PROTON_INTERNAL bool
proton_runtime_has_events(const proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t proton_runtime_poll_event(
    proton_runtime_slot_t *runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len);

PROTON_INTERNAL int32_t proton_window_slot_create(
    proton_runtime_slot_t *runtime, proton_runtime_id_t runtime_handle,
    proton_engine_window_t *engine_window, int32_t width, int32_t height,
    proton_window_id_t *out_window, proton_window_slot_t **out_slot);
PROTON_INTERNAL void
proton_window_slot_destroy(proton_window_slot_t *slot);
PROTON_INTERNAL void proton_window_slot_close(proton_window_slot_t *slot);
PROTON_INTERNAL int32_t
proton_get_window(proton_window_id_t handle, proton_window_slot_t **out_slot);
PROTON_INTERNAL void
proton_window_clear_bridge(proton_window_slot_t *window);
PROTON_INTERNAL int32_t proton_window_enqueue_closed_once(
    proton_runtime_slot_t *runtime, proton_window_slot_t *window,
    proton_window_id_t window_handle);
PROTON_INTERNAL int32_t proton_runtime_sync_engine_closed_windows(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime);
PROTON_INTERNAL int32_t
proton_destroy_windows_for_runtime(proton_runtime_id_t runtime);

#endif
