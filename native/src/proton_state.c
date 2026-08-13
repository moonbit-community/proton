#include "proton_state.h"

#include "proton_handle.h"
#include "proton_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_MAX_RUNTIMES 64
#define PROTON_MAX_WINDOWS 256
#define PROTON_MAX_VIEWS 256
#define PROTON_MAX_IMAGES 256
/* Type 3 is PROTON_HANDLE_TYPE_UPDATE_STAGE in proton_handle.h. */
#define PROTON_HANDLE_TYPE_VIEW 4ULL
#define PROTON_HANDLE_TYPE_IMAGE 5ULL

static proton_runtime_slot_t g_runtimes[PROTON_MAX_RUNTIMES];
static proton_window_slot_t g_windows[PROTON_MAX_WINDOWS];
static proton_view_slot_t g_views[PROTON_MAX_VIEWS];
static proton_image_slot_t g_images[PROTON_MAX_IMAGES];

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

static proton_view_id_t proton_make_view_handle(uint32_t generation,
                                                uint32_t index) {
  return (proton_view_id_t)proton_make_handle(PROTON_HANDLE_TYPE_VIEW,
                                              generation, index);
}

static proton_image_id_t proton_make_image_handle(uint32_t generation,
                                                  uint32_t index) {
  return (proton_image_id_t)proton_make_handle(PROTON_HANDLE_TYPE_IMAGE,
                                               generation, index);
}

static void proton_runtime_clear_events(proton_runtime_slot_t *slot) {
  for (uint32_t i = 0; i < PROTON_MAX_EVENTS; i++) {
    free(slot->events[i]);
    slot->events[i] = NULL;
  }
  slot->event_head = 0;
  slot->event_count = 0;
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
      slot->generation = proton_next_handle_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->engine_backed = engine_backed;
    slot->running = false;
    slot->quit_requested = false;
    slot->engine_runtime = engine_runtime;
    slot->app_instance = PROTON_INVALID_HANDLE;
    slot->owner_thread_set = true;
    slot->owner_thread = proton_current_thread_id();
    proton_runtime_clear_events(slot);
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
  proton_runtime_clear_events(slot);
  slot->destroyed = true;
  slot->engine_backed = false;
  slot->running = false;
  slot->quit_requested = true;
  slot->app_instance = PROTON_INVALID_HANDLE;
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

  char *owned_event = (char *)malloc(event_len + 1);
  if (owned_event == NULL) {
    return false;
  }
  memcpy(owned_event, event_json, event_len + 1);
  uint32_t index = (runtime->event_head + runtime->event_count) %
                   PROTON_MAX_EVENTS;
  runtime->events[index] = owned_event;
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

  char *event_json = runtime->events[runtime->event_head];
  int32_t required = (int32_t)strlen(event_json);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "event buffer is too small");
  }

  memcpy(buffer, event_json, (size_t)required + 1);
  free(event_json);
  runtime->events[runtime->event_head] = NULL;
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
      slot->generation = proton_next_handle_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->visible = false;
    slot->closed_event_sent = false;
    slot->state_valid = false;
    slot->bridge_notified_revision = 0;
    slot->close_request_notified_revision = 0;
    slot->runtime = runtime_handle;
    slot->engine_window = engine_window;
    slot->width = width;
    slot->height = height;
    memset(&slot->state, 0, sizeof(slot->state));
    *out_window = proton_make_window_handle(slot->generation, i);
    if (!proton_runtime_enqueue_window_event(runtime, "window_created",
                                             *out_window)) {
      slot->destroyed = true;
      slot->occupied = false;
      slot->engine_window = NULL;
      slot->generation = proton_next_handle_generation(slot->generation);
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

// A full event queue defers window_closed delivery: closed_event_sent stays
// false and visible stays true, so a later poll/wait retries after the
// consumer drains.
void proton_runtime_sync_engine_closed_windows(
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
      continue;
    }
    window->visible = false;
  }
}

int32_t proton_format_window_state_json(
    const proton_engine_window_state_t *state, char *buffer,
    size_t buffer_len) {
  if (state == NULL || buffer == NULL || buffer_len == 0) {
    return -1;
  }
  const char *theme =
      state->theme == 2 ? "dark" : state->theme == 1 ? "light" : "system";
  return snprintf(
      buffer, buffer_len,
      "{\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d,"
      "\"monitor\":{\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d,"
      "\"work_x\":%d,\"work_y\":%d,\"work_width\":%d,\"work_height\":%d,"
      "\"scale_factor_percent\":%d},"
      "\"zoom_percent\":%d,\"visible\":%s,\"focused\":%s,"
      "\"minimized\":%s,\"maximized\":%s,\"fullscreen\":%s,"
      "\"always_on_top\":%s,\"theme\":\"%s\"}",
      state->x, state->y, state->width, state->height, state->monitor_x,
      state->monitor_y, state->monitor_width, state->monitor_height,
      state->work_x, state->work_y, state->work_width, state->work_height,
      state->scale_factor_percent, state->zoom_percent,
      state->visible ? "true" : "false", state->focused ? "true" : "false",
      state->minimized ? "true" : "false",
      state->maximized ? "true" : "false",
      state->fullscreen ? "true" : "false",
      state->always_on_top ? "true" : "false", theme);
}

int32_t proton_format_screen_array_json(
    const proton_engine_screen_info_t *screens, int32_t count,
    char *buffer, size_t buffer_len) {
  if (screens == NULL || buffer == NULL || buffer_len == 0) {
    return -1;
  }
  if (count <= 0) {
    return snprintf(buffer, buffer_len, "[]");
  }
  size_t offset = 0;
  int written = snprintf(buffer, buffer_len, "[");
  if (written < 0 || (size_t)written >= buffer_len) {
    return -1;
  }
  offset += (size_t)written;
  for (int32_t i = 0; i < count; i++) {
    const proton_engine_screen_info_t *s = &screens[i];
    written = snprintf(
        buffer + offset, buffer_len - offset,
        "%s{\"id\":%d,\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d,"
        "\"work_x\":%d,\"work_y\":%d,\"work_width\":%d,\"work_height\":%d,"
        "\"scale_factor_percent\":%d,\"is_primary\":%s}",
        i == 0 ? "" : ",", s->id, s->x, s->y, s->width, s->height, s->work_x,
        s->work_y, s->work_width, s->work_height, s->scale_factor_percent,
        s->is_primary ? "true" : "false");
    if (written < 0 || (size_t)written >= buffer_len - offset) {
      return -1;
    }
    offset += (size_t)written;
  }
  written = snprintf(buffer + offset, buffer_len - offset, "]");
  if (written < 0 || (size_t)written >= buffer_len - offset) {
    return -1;
  }
  offset += (size_t)written;
  return (int32_t)offset;
}

int32_t proton_runtime_sync_engine_window_states(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (!window->occupied || window->destroyed ||
        window->runtime != runtime_handle || window->engine_window == NULL ||
        proton_engine_window_is_closed(window->engine_window)) {
      continue;
    }

    proton_engine_window_state_t state;
    char engine_error[512] = {0};
    int32_t status = proton_engine_window_get_state(
        window->engine_window, &state, engine_error, sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (window->state_valid &&
        memcmp(&window->state, &state, sizeof(state)) == 0) {
      continue;
    }

    char state_json[1024];
    int state_written =
        proton_format_window_state_json(&state, state_json, sizeof(state_json));
    if (state_written < 0 || state_written >= (int)sizeof(state_json)) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "window state payload is too large");
    }
    proton_window_id_t window_handle =
        proton_make_window_handle(window->generation, i);
    char event_json[PROTON_MAX_EVENT_BYTES];
    int event_written = snprintf(
        event_json, sizeof(event_json),
        "{\"type\":\"window_state_changed\",\"window\":\"%lld\","
        "\"state\":%s}",
        (long long)window_handle, state_json);
    if (event_written < 0 || event_written >= (int)sizeof(event_json)) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "window state event payload is too large");
    }
    if (!proton_runtime_enqueue_event(runtime, event_json)) {
      return PROTON_OK;
    }
    window->state = state;
    window->state_valid = true;
  }
  return PROTON_OK;
}

int32_t proton_runtime_sync_engine_close_requests(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (!window->occupied || window->destroyed ||
        window->runtime != runtime_handle || window->engine_window == NULL) {
      continue;
    }
    uint64_t request_id = 0;
    int32_t pending = 0;
    char engine_error[512] = {0};
    int32_t status = proton_engine_window_get_close_request(
        window->engine_window, &request_id, &pending, engine_error,
        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (!pending || request_id == 0 ||
        request_id == window->close_request_notified_revision) {
      continue;
    }
    proton_window_id_t window_handle =
        proton_make_window_handle(window->generation, i);
    char event_json[PROTON_MAX_EVENT_BYTES];
    int written = snprintf(
        event_json, sizeof(event_json),
        "{\"type\":\"window_close_requested\",\"window\":\"%lld\","
        "\"request_id\":\"%llu\"}",
        (long long)window_handle, (unsigned long long)request_id);
    if (written < 0 || written >= (int)sizeof(event_json)) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "window close request payload is too large");
    }
    if (!proton_runtime_enqueue_event(runtime, event_json)) {
      return PROTON_OK;
    }
    window->close_request_notified_revision = request_id;
  }
  return PROTON_OK;
}

int32_t proton_runtime_sync_engine_browser_events(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime) {
  char event_json[PROTON_MAX_EVENT_BYTES];
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (!window->occupied || window->destroyed ||
        window->runtime != runtime_handle || window->engine_window == NULL) {
      continue;
    }
    while (runtime->event_count < PROTON_MAX_EVENTS) {
      int32_t required = 0;
      char error[512] = {0};
      int32_t status = proton_engine_window_poll_browser_event_json(
          window->engine_window, event_json, sizeof(event_json), &required,
          error, sizeof(error));
      if (status == PROTON_EVENT_NONE) {
        break;
      }
      if (status != PROTON_OK) {
        return proton_set_engine_status(status, error);
      }
      if (!proton_runtime_enqueue_event(runtime, event_json)) {
        return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                                "failed to queue browser event");
      }
    }
    if (runtime->event_count >= PROTON_MAX_EVENTS) {
      break;
    }
  }
  return PROTON_OK;
}

int32_t proton_runtime_sync_engine_view_events(
    proton_runtime_id_t runtime_handle,
    proton_runtime_slot_t *runtime) {
  char event_json[PROTON_MAX_EVENT_BYTES];
  for (uint32_t i = 0; i < PROTON_MAX_VIEWS; i++) {
    proton_view_slot_t *view = &g_views[i];
    if (!view->occupied || view->destroyed ||
        view->runtime != runtime_handle || view->engine_view == NULL) {
      continue;
    }
    while (runtime->event_count < PROTON_MAX_EVENTS) {
      int32_t required = 0;
      char error[512] = {0};
      int32_t status = proton_engine_view_poll_event_json(
          view->engine_view, event_json, sizeof(event_json), &required, error,
          sizeof(error));
      if (status == PROTON_EVENT_NONE) {
        break;
      }
      if (status != PROTON_OK) {
        return proton_set_engine_status(status, error);
      }
      if (!proton_runtime_enqueue_event(runtime, event_json)) {
        return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                                "failed to queue view event");
      }
    }
    if (runtime->event_count >= PROTON_MAX_EVENTS) {
      break;
    }
  }
  return PROTON_OK;
}

void proton_runtime_sync_engine_bridge_lifecycle(
    proton_runtime_id_t runtime_handle, proton_runtime_slot_t *runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (!window->occupied || window->destroyed ||
        window->runtime != runtime_handle || window->engine_window == NULL) {
      continue;
    }
    uint64_t revision =
        proton_engine_window_bridge_revision(window->engine_window);
    if (revision == 0 || revision == window->bridge_notified_revision) {
      continue;
    }
    proton_window_id_t window_handle =
        proton_make_window_handle(window->generation, i);
    char event_json[PROTON_MAX_EVENT_BYTES];
    int written = snprintf(
        event_json, sizeof(event_json),
        "{\"type\":\"bridge_lifecycle_changed\",\"window\":\"%lld\","
        "\"revision\":\"%llu\"}",
        (long long)window_handle, (unsigned long long)revision);
    if (written > 0 && written < (int)sizeof(event_json) &&
        proton_runtime_enqueue_event(runtime, event_json)) {
      window->bridge_notified_revision = revision;
    }
  }
}

int32_t proton_destroy_windows_for_runtime(proton_runtime_id_t runtime) {
  for (uint32_t i = 0; i < PROTON_MAX_WINDOWS; i++) {
    proton_window_slot_t *window = &g_windows[i];
    if (window->occupied && !window->destroyed && window->runtime == runtime) {
      proton_window_id_t window_handle =
          proton_make_window_handle(window->generation, i);
      proton_destroy_views_for_window(window_handle);
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

int32_t proton_view_slot_create(proton_runtime_id_t runtime_handle,
                                proton_window_id_t window_handle,
                                proton_engine_view_t *engine_view, int32_t x,
                                int32_t y, int32_t width, int32_t height,
                                int32_t z_order, bool visible,
                                proton_view_id_t *out_view,
                                proton_view_slot_t **out_slot) {
  for (uint32_t i = 0; i < PROTON_MAX_VIEWS; i++) {
    proton_view_slot_t *slot = &g_views[i];
    if (slot->occupied && !slot->destroyed) {
      continue;
    }
    if (slot->generation == 0) {
      slot->generation = 1;
    } else if (slot->destroyed) {
      slot->generation = proton_next_handle_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->runtime = runtime_handle;
    slot->window = window_handle;
    slot->engine_view = engine_view;
    slot->x = x;
    slot->y = y;
    slot->width = width;
    slot->height = height;
    slot->z_order = z_order;
    slot->visible = visible;
    *out_view = proton_make_view_handle(slot->generation, i);
    if (out_slot != NULL) {
      *out_slot = slot;
    }
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_ENGINE, "view registry is full");
}

void proton_view_slot_destroy(proton_view_slot_t *slot) {
  slot->destroyed = true;
  slot->engine_view = NULL;
}

int32_t proton_get_view(proton_view_id_t handle,
                        proton_view_slot_t **out_slot) {
  uint64_t raw = (uint64_t)handle;
  if (handle == PROTON_INVALID_HANDLE ||
      proton_handle_type(raw) != PROTON_HANDLE_TYPE_VIEW) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE, "invalid view handle");
  }

  uint32_t index = proton_handle_index(raw);
  if (index >= PROTON_MAX_VIEWS) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "view handle index is out of range");
  }

  proton_view_slot_t *slot = &g_views[index];
  if (!slot->occupied || slot->generation != proton_handle_generation(raw)) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "view handle generation is invalid");
  }
  if (slot->destroyed) {
    return proton_set_error(PROTON_ERR_DESTROYED, "view is destroyed");
  }
  proton_runtime_slot_t *runtime = NULL;
  int32_t status = proton_get_runtime(slot->runtime, &runtime);
  if (status != PROTON_OK) {
    return status;
  }

  *out_slot = slot;
  return PROTON_OK;
}

void proton_destroy_views_for_window(proton_window_id_t window) {
  for (uint32_t i = 0; i < PROTON_MAX_VIEWS; i++) {
    proton_view_slot_t *view = &g_views[i];
    if (view->occupied && !view->destroyed && view->window == window) {
      proton_view_slot_destroy(view);
    }
  }
}

int32_t proton_image_slot_create(proton_engine_image_t *engine_image,
                                 proton_image_id_t *out_image,
                                 proton_image_slot_t **out_slot) {
  for (uint32_t i = 0; i < PROTON_MAX_IMAGES; i++) {
    proton_image_slot_t *slot = &g_images[i];
    if (slot->occupied && !slot->destroyed) {
      continue;
    }
    if (slot->generation == 0) {
      slot->generation = 1;
    } else if (slot->destroyed) {
      slot->generation = proton_next_handle_generation(slot->generation);
    }
    slot->occupied = true;
    slot->destroyed = false;
    slot->engine_image = engine_image;
    *out_image = proton_make_image_handle(slot->generation, i);
    if (out_slot != NULL) {
      *out_slot = slot;
    }
    return PROTON_OK;
  }
  return proton_set_error(PROTON_ERR_ENGINE, "image registry is full");
}

void proton_image_slot_destroy(proton_image_slot_t *slot) {
  slot->destroyed = true;
  slot->engine_image = NULL;
}

int32_t proton_get_image(proton_image_id_t handle,
                         proton_image_slot_t **out_slot) {
  uint64_t raw = (uint64_t)handle;
  if (handle == PROTON_INVALID_HANDLE ||
      proton_handle_type(raw) != PROTON_HANDLE_TYPE_IMAGE) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE, "invalid image handle");
  }

  uint32_t index = proton_handle_index(raw);
  if (index >= PROTON_MAX_IMAGES) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "image handle index is out of range");
  }

  proton_image_slot_t *slot = &g_images[index];
  if (!slot->occupied || slot->generation != proton_handle_generation(raw)) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "image handle generation is invalid");
  }
  if (slot->destroyed) {
    return proton_set_error(PROTON_ERR_DESTROYED, "image is destroyed");
  }

  *out_slot = slot;
  return PROTON_OK;
}
