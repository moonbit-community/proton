#include "native_stub.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void power_monitor_set_error(power_monitor_state_t *state,
                                    const char *message) {
  if (state != NULL && message != NULL) {
    snprintf(state->last_error, sizeof(state->last_error), "%s", message);
  }
}

static void power_monitor_lock_acquire(power_monitor_state_t *state) {
#if defined(_WIN32)
  EnterCriticalSection(&state->event_lock);
#else
  pthread_mutex_lock(&state->event_lock);
#endif
}

static void power_monitor_lock_release(power_monitor_state_t *state) {
#if defined(_WIN32)
  LeaveCriticalSection(&state->event_lock);
#else
  pthread_mutex_unlock(&state->event_lock);
#endif
}

/* Shared lifecycle helper so an explicit destroy and the GC finalizer take the
   same path. All steps are idempotent through `destroyed`. */
static void power_monitor_destroy_state(power_monitor_state_t *state) {
  if (state->destroyed) {
    return;
  }
  state->destroyed = 1;
  power_monitor_platform_stop_watching(state);
  power_monitor_release_events(state);
  power_monitor_lock_destroy(state);
}

void power_monitor_lock_init(power_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
#if defined(_WIN32)
  InitializeCriticalSection(&state->event_lock);
#else
  pthread_mutex_init(&state->event_lock, NULL);
#endif
}

void power_monitor_lock_destroy(power_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
#if defined(_WIN32)
  DeleteCriticalSection(&state->event_lock);
#else
  pthread_mutex_destroy(&state->event_lock);
#endif
}

void power_monitor_push_event(power_monitor_state_t *state, int32_t event) {
  if (state == NULL) {
    return;
  }
  power_monitor_event_wakeup_fn wakeup = NULL;
  power_monitor_lock_acquire(state);
  if (state->event_queue_size >= POWER_MONITOR_EVENT_QUEUE_CAPACITY) {
    /* A full queue drops the oldest entry so the latest system state is always
       preserved, matching the intent documented on the queue fields. */
    power_monitor_event_node_t *oldest = state->event_head;
    if (oldest != NULL) {
      state->event_head = oldest->next;
      if (state->event_head == NULL) {
        state->event_tail = NULL;
      }
      free(oldest);
      state->event_queue_size--;
    }
    state->event_queue_overflow = 1;
  }
  power_monitor_event_node_t *node =
      (power_monitor_event_node_t *)calloc(1, sizeof(*node));
  if (node != NULL) {
    node->event = event;
    if (state->event_tail == NULL) {
      state->event_head = node;
      state->event_tail = node;
    } else {
      state->event_tail->next = node;
      state->event_tail = node;
    }
    state->event_queue_size++;
    wakeup = state->event_wakeup;
  }
  power_monitor_lock_release(state);
  if (wakeup != NULL) {
    wakeup();
  }
}

void power_monitor_set_event_wakeup(
    power_monitor_state_t *state,
    power_monitor_event_wakeup_fn wakeup) {
  if (state == NULL) {
    return;
  }
  power_monitor_lock_acquire(state);
  state->event_wakeup = wakeup;
  power_monitor_lock_release(state);
}

int32_t power_monitor_take_event(power_monitor_state_t *state,
                                 int32_t *out_event) {
  if (state == NULL || out_event == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  int32_t status = power_monitor_STATUS_EMPTY;
  power_monitor_lock_acquire(state);
  power_monitor_event_node_t *node = state->event_head;
  if (node != NULL) {
    *out_event = node->event;
    state->event_head = node->next;
    if (state->event_head == NULL) {
      state->event_tail = NULL;
    }
    free(node);
    state->event_queue_size--;
    status = power_monitor_STATUS_OK;
  }
  power_monitor_lock_release(state);
  return status;
}

void power_monitor_release_events(power_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
  power_monitor_lock_acquire(state);
  power_monitor_event_node_t *node = state->event_head;
  while (node != NULL) {
    power_monitor_event_node_t *next = node->next;
    free(node);
    node = next;
  }
  state->event_head = NULL;
  state->event_tail = NULL;
  state->event_queue_size = 0;
  state->event_queue_overflow = 0;
  power_monitor_lock_release(state);
}

/* GC finalizer: tears the watch backend and the event queue down when the
   external object is collected without an explicit destroy(). */
static void power_monitor_finalize(void *payload) {
  power_monitor_state_t *state = (power_monitor_state_t *)payload;
  if (state == NULL) {
    return;
  }
  power_monitor_destroy_state(state);
}

MOONBIT_FFI_EXPORT
void *moonbit_power_monitor_create(void) {
  power_monitor_state_t *state =
      (power_monitor_state_t *)moonbit_make_external_object(
          power_monitor_finalize, (uint32_t)sizeof(power_monitor_state_t));
  if (state == NULL) {
    return NULL;
  }
  memset(state, 0, sizeof(*state));
  state->source = power_monitor_SOURCE_UNKNOWN;
  power_monitor_lock_init(state);
  power_monitor_platform_init(state);
  return state;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_idle_seconds(void *handle,
                                           int64_t *out_seconds) {
  if (handle == NULL || out_seconds == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  state->status = power_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t platform_status = power_monitor_platform_query_idle(state);
  if (platform_status != power_monitor_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      power_monitor_set_error(state, "querying idle time failed");
    }
    state->status = platform_status;
    return platform_status;
  }
  *out_seconds = state->idle_seconds;
  return power_monitor_STATUS_OK;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_source(void *handle,
                                     int32_t *out_source,
                                     int32_t *out_percent,
                                     int32_t *out_has_percent) {
  if (handle == NULL || out_source == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  state->status = power_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t platform_status = power_monitor_platform_query_source(state);
  if (platform_status != power_monitor_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      power_monitor_set_error(state, "querying power source failed");
    }
    state->status = platform_status;
    return platform_status;
  }
  *out_source = state->source;
  if (out_percent != NULL) {
    *out_percent = state->battery_percent;
  }
  if (out_has_percent != NULL) {
    *out_has_percent = state->has_battery_percent;
  }
  return power_monitor_STATUS_OK;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_status(void *handle) {
  if (handle == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return ((power_monitor_state_t *)handle)->status;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_power_monitor_last_error(void *handle) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  const char *text = state->last_error;
  if (text[0] == '\0') {
    return moonbit_make_bytes(0, 0);
  }
  int32_t len = (int32_t)strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, (size_t)len);
  return bytes;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_start_watching(void *handle) {
  if (handle == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_platform_start_watching(
      (power_monitor_state_t *)handle);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_stop_watching(void *handle) {
  if (handle == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_platform_stop_watching((power_monitor_state_t *)handle);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_take_event(void *handle, int32_t *out_event) {
  if (handle == NULL || out_event == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return power_monitor_take_event((power_monitor_state_t *)handle, out_event);
}

MOONBIT_FFI_EXPORT void moonbit_power_monitor_set_event_wakeup(
    void *handle,
    power_monitor_event_wakeup_fn wakeup) {
  power_monitor_set_event_wakeup((power_monitor_state_t *)handle, wakeup);
}

MOONBIT_FFI_EXPORT
void moonbit_power_monitor_destroy(void *handle) {
  if (handle == NULL) {
    return;
  }
  power_monitor_destroy_state((power_monitor_state_t *)handle);
}
