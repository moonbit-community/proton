#include "native_stub.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void screen_monitor_set_error(screen_monitor_state_t *state,
                                     const char *message) {
  if (state != NULL && message != NULL) {
    snprintf(state->last_error, sizeof(state->last_error), "%s", message);
  }
}

static void screen_monitor_lock_acquire(screen_monitor_state_t *state) {
#if defined(_WIN32)
  EnterCriticalSection(&state->event_lock);
#else
  pthread_mutex_lock(&state->event_lock);
#endif
}

static void screen_monitor_lock_release(screen_monitor_state_t *state) {
#if defined(_WIN32)
  LeaveCriticalSection(&state->event_lock);
#else
  pthread_mutex_unlock(&state->event_lock);
#endif
}

/* Shared lifecycle helper so an explicit destroy and the GC finalizer take the
   same path. All steps are idempotent through `destroyed`. */
static void screen_monitor_destroy_state(screen_monitor_state_t *state) {
  if (state->destroyed) {
    return;
  }
  state->destroyed = 1;
  screen_monitor_platform_stop_watching(state);
  screen_monitor_release_events(state);
  screen_monitor_lock_destroy(state);
}

void screen_monitor_lock_init(screen_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
#if defined(_WIN32)
  InitializeCriticalSection(&state->event_lock);
#else
  pthread_mutex_init(&state->event_lock, NULL);
#endif
}

void screen_monitor_lock_destroy(screen_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
#if defined(_WIN32)
  DeleteCriticalSection(&state->event_lock);
#else
  pthread_mutex_destroy(&state->event_lock);
#endif
}

void screen_monitor_push_event(screen_monitor_state_t *state, int32_t event) {
  if (state == NULL) {
    return;
  }
  screen_monitor_lock_acquire(state);
  if (state->event_queue_size >= SCREEN_MONITOR_EVENT_QUEUE_CAPACITY) {
    /* A full queue drops the oldest entry so the latest topology state is
       always preserved, matching the intent documented on the queue fields. */
    screen_monitor_event_node_t *oldest = state->event_head;
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
  screen_monitor_event_node_t *node =
      (screen_monitor_event_node_t *)calloc(1, sizeof(*node));
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
  }
  screen_monitor_lock_release(state);
}

int32_t screen_monitor_take_event(screen_monitor_state_t *state,
                                  int32_t *out_event) {
  if (state == NULL || out_event == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  int32_t status = screen_monitor_STATUS_EMPTY;
  screen_monitor_lock_acquire(state);
  screen_monitor_event_node_t *node = state->event_head;
  if (node != NULL) {
    *out_event = node->event;
    state->event_head = node->next;
    if (state->event_head == NULL) {
      state->event_tail = NULL;
    }
    free(node);
    state->event_queue_size--;
    status = screen_monitor_STATUS_OK;
  }
  screen_monitor_lock_release(state);
  return status;
}

void screen_monitor_release_events(screen_monitor_state_t *state) {
  if (state == NULL) {
    return;
  }
  screen_monitor_lock_acquire(state);
  screen_monitor_event_node_t *node = state->event_head;
  while (node != NULL) {
    screen_monitor_event_node_t *next = node->next;
    free(node);
    node = next;
  }
  state->event_head = NULL;
  state->event_tail = NULL;
  state->event_queue_size = 0;
  state->event_queue_overflow = 0;
  screen_monitor_lock_release(state);
}

/* GC finalizer: tears the watch backend and the event queue down when the
   external object is collected without an explicit destroy(). */
static void screen_monitor_finalize(void *payload) {
  screen_monitor_state_t *state = (screen_monitor_state_t *)payload;
  if (state == NULL) {
    return;
  }
  screen_monitor_destroy_state(state);
}

MOONBIT_FFI_EXPORT
void *moonbit_screen_monitor_create(void) {
  screen_monitor_state_t *state =
      (screen_monitor_state_t *)moonbit_make_external_object(
          screen_monitor_finalize, (uint32_t)sizeof(screen_monitor_state_t));
  if (state == NULL) {
    return NULL;
  }
  memset(state, 0, sizeof(*state));
  screen_monitor_lock_init(state);
  screen_monitor_platform_init(state);
  return state;
}

MOONBIT_FFI_EXPORT
void moonbit_screen_monitor_destroy(void *handle) {
  if (handle == NULL) {
    return;
  }
  screen_monitor_destroy_state((screen_monitor_state_t *)handle);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_screen_monitor_status(void *handle) {
  if (handle == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  return ((screen_monitor_state_t *)handle)->status;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_last_error(void *handle) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  screen_monitor_state_t *state = (screen_monitor_state_t *)handle;
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
int32_t moonbit_screen_monitor_start_watching(void *handle) {
  if (handle == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  return screen_monitor_platform_start_watching(
      (screen_monitor_state_t *)handle);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_screen_monitor_stop_watching(void *handle) {
  if (handle == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  return screen_monitor_platform_stop_watching((screen_monitor_state_t *)handle);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_screen_monitor_take_event(void *handle, int32_t *out_event) {
  if (handle == NULL || out_event == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  return screen_monitor_take_event((screen_monitor_state_t *)handle, out_event);
}

/* --- JSON query helpers -------------------------------------------------- */

/* Copies a UTF-8 C string into a fresh MoonBit bytes object. Returns empty
   bytes when `text` is NULL. */
static moonbit_bytes_t screen_monitor_bytes_from(const char *text) {
  if (text == NULL || text[0] == '\0') {
    return moonbit_make_bytes(0, 0);
  }
  int32_t len = (int32_t)strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, (size_t)len);
  return bytes;
}

static int32_t screen_monitor_refresh(screen_monitor_state_t *state) {
  int32_t count = screen_monitor_platform_enumerate(state);
  if (count < 0) {
    if (state->last_error[0] == '\0') {
      screen_monitor_set_error(state, "enumerating displays failed");
    }
    return -count;
  }
  return screen_monitor_STATUS_OK;
}

static void screen_monitor_format_display_json(const screen_monitor_display_t *d,
                                               int32_t first, char *out_buf,
                                               size_t out_buf_len) {
  snprintf(out_buf, out_buf_len, "%s{\"id\":%d,\"x\":%d,\"y\":%d,"
           "\"width\":%d,\"height\":%d,\"work_x\":%d,\"work_y\":%d,"
           "\"work_width\":%d,\"work_height\":%d,\"scale_factor_percent\":%d,"
           "\"is_primary\":%s}",
           first ? "" : ",", d->id, d->x, d->y, d->width, d->height, d->work_x,
           d->work_y, d->work_width, d->work_height, d->scale_factor_percent,
           d->is_primary ? "true" : "false");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_enumerate_json(void *handle) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  screen_monitor_state_t *state = (screen_monitor_state_t *)handle;
  state->status = screen_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t ref = screen_monitor_refresh(state);
  if (ref != screen_monitor_STATUS_OK) {
    state->status = ref;
    return moonbit_make_bytes(0, 0);
  }
  /* Build the JSON into a heap buffer, then hand the exact byte span to
     MoonBit. The payload is wrapped in an object so the MoonBit side can decode
     it with a single derived `FromJson` struct. */
  char item[512];
  size_t capacity = 64 + ((size_t)state->display_count * sizeof(item));
  char *buffer = (char *)malloc(capacity);
  if (buffer == NULL) {
    state->status = screen_monitor_STATUS_OPERATION_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  size_t used = (size_t)snprintf(buffer, capacity, "{\"displays\":[");
  for (int32_t i = 0; i < state->display_count; i++) {
    screen_monitor_format_display_json(&state->displays[i], i == 0, item,
                                       sizeof(item));
    size_t item_length = strlen(item);
    if (item_length + 3 > capacity - used) {
      free(buffer);
      state->status = screen_monitor_STATUS_OPERATION_FAILED;
      screen_monitor_set_error(state, "formatting display list failed");
      return moonbit_make_bytes(0, 0);
    }
    memcpy(buffer + used, item, item_length);
    used += item_length;
  }
  memcpy(buffer + used, "]}", 3);
  used += 2;
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)used, 0);
  memcpy(bytes, buffer, used);
  free(buffer);
  return bytes;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_cursor_point_json(void *handle) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  screen_monitor_state_t *state = (screen_monitor_state_t *)handle;
  state->status = screen_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t x = 0;
  int32_t y = 0;
  int32_t q = screen_monitor_platform_query_cursor(state, &x, &y);
  if (q != screen_monitor_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      screen_monitor_set_error(state, "querying cursor position failed");
    }
    state->status = q;
    return moonbit_make_bytes(0, 0);
  }
  char json[128];
  snprintf(json, sizeof(json), "{\"x\":%d,\"y\":%d}", x, y);
  return screen_monitor_bytes_from(json);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_nearest_display_json(void *handle,
                                                            int32_t x,
                                                            int32_t y) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  screen_monitor_state_t *state = (screen_monitor_state_t *)handle;
  state->status = screen_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t ref = screen_monitor_refresh(state);
  if (ref != screen_monitor_STATUS_OK) {
    state->status = ref;
    return moonbit_make_bytes(0, 0);
  }
  int32_t idx = screen_monitor_platform_nearest_display(state, x, y);
  if (idx < 0 || idx >= state->display_count) {
    state->status = screen_monitor_STATUS_EMPTY;
    return moonbit_make_bytes(0, 0);
  }
  char json[512];
  screen_monitor_format_display_json(&state->displays[idx], 1, json,
                                     sizeof(json));
  return screen_monitor_bytes_from(json);
}
