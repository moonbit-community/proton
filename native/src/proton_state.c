#include "proton_state.h"

#include "proton_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_MAX_RUNTIMES 64
#define PROTON_MAX_WINDOWS 256
#define PROTON_HANDLE_INDEX_MASK 0x00000000ffffffffULL
#define PROTON_HANDLE_GENERATION_SHIFT 32
#define PROTON_HANDLE_TYPE_SHIFT 60
#define PROTON_HANDLE_TYPE_RUNTIME 1ULL
#define PROTON_HANDLE_TYPE_WINDOW 2ULL

static proton_runtime_slot_t g_runtimes[PROTON_MAX_RUNTIMES];
static proton_window_slot_t g_windows[PROTON_MAX_WINDOWS];

static proton_thread_id_t proton_current_thread_id(void) {
#ifdef _WIN32
  return GetCurrentThreadId();
#else
  return pthread_self();
#endif
}

static bool proton_thread_equal(proton_thread_id_t left,
                                proton_thread_id_t right) {
#ifdef _WIN32
  return left == right;
#else
  return pthread_equal(left, right) != 0;
#endif
}

static uint64_t proton_make_handle(uint64_t type, uint32_t generation,
                                   uint32_t index) {
  return (type << PROTON_HANDLE_TYPE_SHIFT) |
         ((uint64_t)generation << PROTON_HANDLE_GENERATION_SHIFT) |
         (uint64_t)index;
}

static uint64_t proton_handle_type(uint64_t handle) {
  return handle >> PROTON_HANDLE_TYPE_SHIFT;
}

static uint32_t proton_handle_generation(uint64_t handle) {
  return (uint32_t)((handle >> PROTON_HANDLE_GENERATION_SHIFT) & 0x0fffffffU);
}

static uint32_t proton_handle_index(uint64_t handle) {
  return (uint32_t)(handle & PROTON_HANDLE_INDEX_MASK);
}

static proton_runtime_id_t proton_make_runtime_handle(uint32_t generation,
                                                       uint32_t index) {
  return (proton_runtime_id_t)proton_make_handle(PROTON_HANDLE_TYPE_RUNTIME,
                                                 generation, index);
}

static proton_window_id_t proton_make_window_handle(uint32_t generation,
                                                     uint32_t index) {
  return (proton_window_id_t)proton_make_handle(PROTON_HANDLE_TYPE_WINDOW,
                                                generation, index);
}

static uint32_t proton_next_generation(uint32_t generation) {
  generation++;
  if (generation == 0) {
    generation = 1;
  }
  return generation;
}

int32_t proton_require_runtime_owner_thread(
    const proton_runtime_slot_t *runtime) {
  if (runtime != NULL && runtime->owner_thread_set &&
      !proton_thread_equal(runtime->owner_thread, proton_current_thread_id())) {
    return proton_set_error(PROTON_ERR_WRONG_THREAD,
                            "runtime API called from non-owner thread");
  }
  return PROTON_OK;
}

int32_t proton_runtime_slot_create(bool engine_backed,
                                   proton_engine_runtime_t *engine_runtime,
                                   proton_runtime_id_t *out_runtime,
                                   proton_runtime_slot_t **out_slot) {
  for (uint32_t i = 0; i < PROTON_MAX_RUNTIMES; i++) {
    proton_runtime_slot_t *slot = &g_runtimes[i];
    if (slot->occupied && !slot->destroyed) {
      continue;
    }
    if (slot->generation == 0) {
      slot->generation = 1;
    } else if (slot->destroyed) {
      slot->generation = proton_next_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->engine_backed = engine_backed;
    slot->running = false;
    slot->quit_requested = false;
    slot->engine_runtime = engine_runtime;
    slot->owner_thread_set = true;
    slot->owner_thread = proton_current_thread_id();
    slot->event_head = 0;
    slot->event_count = 0;
    slot->next_bridge_request_id = 1;
    *out_runtime = proton_make_runtime_handle(slot->generation, i);
    if (out_slot != NULL) {
      *out_slot = slot;
    }
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_ENGINE, "runtime registry is full");
}

void proton_runtime_slot_destroy(proton_runtime_slot_t *slot) {
  slot->destroyed = true;
  slot->engine_backed = false;
  slot->running = false;
  slot->quit_requested = true;
  slot->owner_thread_set = false;
}

int32_t proton_get_runtime(proton_runtime_id_t handle,
                           proton_runtime_slot_t **out_slot) {
  uint64_t raw = (uint64_t)handle;
  if (handle == PROTON_INVALID_HANDLE ||
      proton_handle_type(raw) != PROTON_HANDLE_TYPE_RUNTIME) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid runtime handle");
  }

  uint32_t index = proton_handle_index(raw);
  if (index >= PROTON_MAX_RUNTIMES) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "runtime handle index is out of range");
  }

  proton_runtime_slot_t *slot = &g_runtimes[index];
  if (!slot->occupied || slot->generation != proton_handle_generation(raw)) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "runtime handle generation is invalid");
  }
  if (slot->destroyed) {
    return proton_set_error(PROTON_ERR_DESTROYED, "runtime is destroyed");
  }
  int32_t status = proton_require_runtime_owner_thread(slot);
  if (status != PROTON_OK) {
    return status;
  }

  *out_slot = slot;
  return PROTON_OK;
}

bool proton_has_active_runtime(void) {
  for (uint32_t i = 0; i < PROTON_MAX_RUNTIMES; i++) {
    if (g_runtimes[i].occupied && !g_runtimes[i].destroyed) {
      return true;
    }
  }
  return false;
}

bool proton_runtime_enqueue_event(proton_runtime_slot_t *runtime,
                                  const char *event_json) {
  if (runtime == NULL || event_json == NULL ||
      runtime->event_count >= PROTON_MAX_EVENTS) {
    return false;
  }

  size_t event_len = strlen(event_json);
  if (event_len >= PROTON_MAX_EVENT_BYTES) {
    return false;
  }

  uint32_t index = (runtime->event_head + runtime->event_count) %
                   PROTON_MAX_EVENTS;
  memcpy(runtime->events[index], event_json, event_len + 1);
  runtime->event_count++;
  return true;
}

bool proton_runtime_enqueue_window_event(proton_runtime_slot_t *runtime,
                                         const char *type,
                                         proton_window_id_t window) {
  char event_json[PROTON_MAX_EVENT_BYTES];
  int written = snprintf(event_json, sizeof(event_json),
                         "{\"type\":\"%s\",\"window\":\"%lld\"}", type,
                         (long long)window);
  if (written < 0 || written >= (int)sizeof(event_json)) {
    return false;
  }
  return proton_runtime_enqueue_event(runtime, event_json);
}

bool proton_runtime_has_events(const proton_runtime_slot_t *runtime) {
  return runtime != NULL && runtime->event_count > 0;
}

int32_t proton_runtime_poll_event(proton_runtime_slot_t *runtime,
                                  char *buffer,
                                  int32_t buffer_len,
                                  int32_t *out_required_len) {
  if (runtime->event_count == 0) {
    *out_required_len = 0;
    return PROTON_EVENT_NONE;
  }

  const char *event_json = runtime->events[runtime->event_head];
  int32_t required = (int32_t)strlen(event_json);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "event buffer is too small");
  }

  memcpy(buffer, event_json, (size_t)required + 1);
  runtime->event_head = (runtime->event_head + 1) % PROTON_MAX_EVENTS;
  runtime->event_count--;
  return PROTON_OK;
}

int32_t proton_window_slot_create(proton_runtime_slot_t *runtime,
                                  proton_runtime_id_t runtime_handle,
                                  proton_engine_window_t *engine_window,
                                  int32_t width,
                                  int32_t height,
                                  proton_window_id_t *out_window,
                                  proton_window_slot_t **out_slot) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *slot = &g_windows[i];
    if (slot->occupied && !slot->destroyed) {
      continue;
    }
    if (slot->generation == 0) {
      slot->generation = 1;
    } else if (slot->destroyed) {
      slot->generation = proton_next_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->visible = false;
    slot->closed_event_sent = false;
    slot->runtime = runtime_handle;
    slot->engine_window = engine_window;
    slot->width = width;
    slot->height = height;
    *out_window = proton_make_window_handle(slot->generation, i);
    if (!proton_runtime_enqueue_window_event(runtime, "window_created",
                                             *out_window)) {
      slot->destroyed = true;
      slot->occupied = false;
      slot->engine_window = NULL;
      slot->generation = proton_next_generation(slot->generation);
      *out_window = PROTON_INVALID_HANDLE;
      return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                              "failed to queue window_created event");
    }
    if (out_slot != NULL) {
      *out_slot = slot;
    }
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_ENGINE, "window registry is full");
}

void proton_window_slot_destroy(proton_window_slot_t *slot) {
  proton_window_slot_close(slot);
}

void proton_window_slot_close(proton_window_slot_t *slot) {
  slot->destroyed = true;
  slot->visible = false;
}

int32_t proton_get_window(proton_window_id_t handle,
                          proton_window_slot_t **out_slot) {
  uint64_t raw = (uint64_t)handle;
  if (handle == PROTON_INVALID_HANDLE ||
      proton_handle_type(raw) != PROTON_HANDLE_TYPE_WINDOW) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid window handle");
  }

  uint32_t index = proton_handle_index(raw);
  if (index >= PROTON_MAX_WINDOWS) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "window handle index is out of range");
  }

  proton_window_slot_t *slot = &g_windows[index];
  if (!slot->occupied || slot->generation != proton_handle_generation(raw)) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "window handle generation is invalid");
  }
  if (slot->destroyed) {
    return proton_set_error(PROTON_ERR_DESTROYED, "window is destroyed");
  }
  proton_runtime_slot_t *runtime = NULL;
  int32_t status = proton_get_runtime(slot->runtime, &runtime);
  if (status != PROTON_OK) {
    return status;
  }

  *out_slot = slot;
  return PROTON_OK;
}

int32_t proton_window_enqueue_closed_once(
    proton_runtime_slot_t *runtime,
    proton_window_slot_t *window,
    proton_window_id_t window_handle) {
  if (window == NULL || window->closed_event_sent) {
    return PROTON_OK;
  }
  if (!proton_runtime_enqueue_window_event(runtime, "window_closed",
                                           window_handle)) {
    return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                            "failed to queue window_closed event");
  }
  window->closed_event_sent = true;
  return PROTON_OK;
}

int32_t proton_runtime_sync_engine_closed_windows(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (!window->occupied || window->destroyed ||
        window->runtime != runtime_handle || window->engine_window == NULL ||
        !proton_engine_window_is_closed(window->engine_window)) {
      continue;
    }

    proton_window_id_t window_handle =
        proton_make_window_handle(window->generation, i);
    int32_t status =
        proton_window_enqueue_closed_once(runtime, window, window_handle);
    if (status != PROTON_OK) {
      return status;
    }
    window->visible = false;
  }
  return PROTON_OK;
}

int32_t proton_destroy_windows_for_runtime(proton_runtime_id_t runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (window->occupied && !window->destroyed && window->runtime == runtime) {
      if (window->engine_window != NULL) {
        char engine_error[512] = {0};
        int32_t status = proton_engine_window_destroy(
            window->engine_window, engine_error, sizeof(engine_error));
        if (status != PROTON_OK) {
          return proton_set_engine_status(status, engine_error);
        }
        window->engine_window = NULL;
      }
      proton_window_slot_destroy(window);
    }
  }
  return PROTON_OK;
}
