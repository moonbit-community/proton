#include "proton_state.h"

#include "proton_internal.h"

#include <stdlib.h>
#include <string.h>

static proton_runtime_slot_t *g_active_runtime = NULL;

static bool proton_runtime_event_sink(void *user_data, proton_event_t *event) {
  proton_runtime_slot_t *runtime = (proton_runtime_slot_t *)user_data;
  if (runtime == NULL || runtime->lifecycle != PROTON_RUNTIME_ACTIVE ||
      !proton_event_queue_push(&runtime->events, event)) {
    return false;
  }
  if (runtime->engine_runtime != NULL) {
    proton_engine_runtime_signal_external_event(runtime->engine_runtime);
  }
  return true;
}

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

int32_t proton_require_runtime_owner_thread(
    const proton_runtime_slot_t *runtime) {
  if (runtime != NULL &&
      !proton_thread_equal(runtime->owner_thread, proton_current_thread_id())) {
    return proton_set_error(PROTON_ERR_WRONG_THREAD,
                            "runtime API called from non-owner thread");
  }
  return PROTON_OK;
}

int32_t proton_runtime_slot_create(proton_engine_runtime_t *engine_runtime,
                                   proton_runtime_slot_t **out_runtime) {
  if (out_runtime == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_runtime is required");
  }
  *out_runtime = NULL;
  if (g_active_runtime != NULL &&
      g_active_runtime->lifecycle != PROTON_RUNTIME_DESTROYED) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "runtime is already initialized");
  }
  proton_runtime_slot_t *runtime =
      (proton_runtime_slot_t *)calloc(1, sizeof(*runtime));
  if (runtime == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate runtime state");
  }
  runtime->engine_runtime = engine_runtime;
  runtime->lifecycle = PROTON_RUNTIME_ACTIVE;
  runtime->app_instance = PROTON_INVALID_HANDLE;
  runtime->owner_thread = proton_current_thread_id();
  runtime->next_bridge_request_id = 1;
  runtime->next_window_id = 1;
  runtime->next_view_id = 1;
  if (!proton_event_queue_init(&runtime->events)) {
    free(runtime);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to initialize runtime event queue");
  }
  g_active_runtime = runtime;
  proton_event_bind_sink(proton_runtime_event_sink, runtime);
  *out_runtime = runtime;
  return PROTON_OK;
}

void proton_runtime_slot_destroy(proton_runtime_slot_t *runtime) {
  if (runtime == NULL) {
    return;
  }
  proton_event_unbind_sink(runtime);
  proton_event_queue_destroy(&runtime->events);
  proton_view_slot_t *view = runtime->views;
  while (view != NULL) {
    proton_view_slot_t *next = view->next;
    free(view);
    view = next;
  }
  proton_window_slot_t *window = runtime->windows;
  while (window != NULL) {
    proton_window_slot_t *next = window->next;
    free(window);
    window = next;
  }
  runtime->lifecycle = PROTON_RUNTIME_DESTROYED;
  if (g_active_runtime == runtime) {
    g_active_runtime = NULL;
  }
  free(runtime);
}

int32_t proton_get_runtime(proton_runtime_slot_t *runtime,
                           proton_runtime_slot_t **out_runtime) {
  int32_t status = proton_get_runtime_for_destroy(runtime, out_runtime);
  if (status != PROTON_OK) {
    return status;
  }
  if (runtime->lifecycle != PROTON_RUNTIME_ACTIVE) {
    return proton_set_error(PROTON_ERR_DESTROYED,
                            "runtime is being destroyed");
  }
  return PROTON_OK;
}

int32_t proton_get_runtime_for_destroy(proton_runtime_slot_t *runtime,
                                       proton_runtime_slot_t **out_runtime) {
  if (runtime == NULL || out_runtime == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid runtime handle");
  }
  if (runtime->lifecycle == PROTON_RUNTIME_DESTROYED) {
    return proton_set_error(PROTON_ERR_DESTROYED, "runtime is destroyed");
  }
  int32_t status = proton_require_runtime_owner_thread(runtime);
  if (status != PROTON_OK) {
    return status;
  }
  *out_runtime = runtime;
  return PROTON_OK;
}

void proton_runtime_slot_begin_destroy(proton_runtime_slot_t *runtime) {
  if (runtime != NULL && runtime->lifecycle == PROTON_RUNTIME_ACTIVE) {
    runtime->lifecycle = PROTON_RUNTIME_DESTROYING;
  }
}

bool proton_has_active_runtime(void) {
  return g_active_runtime != NULL &&
         g_active_runtime->lifecycle != PROTON_RUNTIME_DESTROYED;
}

bool proton_runtime_enqueue_event(proton_runtime_slot_t *runtime,
                                  proton_event_t *event) {
  if (runtime == NULL || event == NULL ||
      !proton_event_queue_push(&runtime->events, event)) {
    proton_event_destroy(event);
    return false;
  }
  return true;
}

bool proton_runtime_enqueue_window_event(proton_runtime_slot_t *runtime,
                                         proton_event_kind_t kind,
                                         int64_t window_id) {
  return proton_runtime_enqueue_event(runtime,
                                      proton_event_create_window(kind,
                                                                 window_id));
}

bool proton_runtime_has_events(proton_runtime_slot_t *runtime) {
  return runtime != NULL && proton_event_queue_count(&runtime->events) > 0;
}

proton_event_t *proton_runtime_poll_event(proton_runtime_slot_t *runtime) {
  return runtime == NULL ? NULL : proton_event_queue_pop(&runtime->events);
}

int64_t proton_runtime_reserve_window_id(proton_runtime_slot_t *runtime) {
  int64_t id = runtime->next_window_id++;
  if (runtime->next_window_id <= 0) {
    runtime->next_window_id = 1;
  }
  return id;
}

int64_t proton_runtime_reserve_view_id(proton_runtime_slot_t *runtime) {
  int64_t id = runtime->next_view_id++;
  if (runtime->next_view_id <= 0) {
    runtime->next_view_id = 1;
  }
  return id;
}

int32_t proton_window_slot_create(proton_runtime_slot_t *runtime,
                                  proton_engine_window_t *engine_window,
                                  int64_t logical_id, int32_t width,
                                  int32_t height,
                                  proton_window_slot_t **out_window) {
  if (runtime == NULL || logical_id <= 0 || out_window == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "runtime and out_window are required");
  }
  proton_window_slot_t *window =
      (proton_window_slot_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate window state");
  }
  window->runtime = runtime;
  window->lifecycle = PROTON_WINDOW_LIVE;
  window->engine_window = engine_window;
  window->width = width;
  window->height = height;
  window->logical_id = logical_id;
  if (!proton_runtime_enqueue_window_event(runtime, PROTON_EVENT_WINDOW_CREATED,
                                           window->logical_id)) {
    free(window);
    return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                            "failed to queue window_created event");
  }
  window->next = runtime->windows;
  runtime->windows = window;
  *out_window = window;
  return PROTON_OK;
}

void proton_window_slot_destroy(proton_window_slot_t *window) {
  if (window != NULL) {
    window->lifecycle = PROTON_WINDOW_DESTROYED;
    window->visible = false;
    window->engine_window = NULL;
  }
}

void proton_window_slot_request_close(proton_window_slot_t *window) {
  if (window != NULL && window->lifecycle == PROTON_WINDOW_LIVE) {
    window->lifecycle = PROTON_WINDOW_CLOSE_REQUESTED;
  }
}

void proton_window_slot_mark_closed(proton_window_slot_t *window) {
  if (window != NULL && window->lifecycle != PROTON_WINDOW_DESTROYING &&
      window->lifecycle != PROTON_WINDOW_DESTROYED) {
    window->lifecycle = PROTON_WINDOW_CLOSED;
    window->visible = false;
  }
}

void proton_window_slot_begin_destroy(proton_window_slot_t *window) {
  if (window != NULL && window->lifecycle != PROTON_WINDOW_DESTROYED) {
    window->lifecycle = PROTON_WINDOW_DESTROYING;
  }
}

int32_t proton_get_window(proton_window_slot_t *window,
                          proton_window_slot_t **out_window) {
  int32_t status = proton_get_window_for_destroy(window, out_window);
  if (status != PROTON_OK) {
    return status;
  }
  if (window->lifecycle != PROTON_WINDOW_LIVE) {
    return proton_set_error(PROTON_ERR_DESTROYED,
                            "window is closing or closed");
  }
  return PROTON_OK;
}

int32_t proton_get_window_for_destroy(proton_window_slot_t *window,
                                      proton_window_slot_t **out_window) {
  if (window == NULL || out_window == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid window handle");
  }
  if (window->lifecycle == PROTON_WINDOW_DESTROYED) {
    return proton_set_error(PROTON_ERR_DESTROYED, "window is destroyed");
  }
  proton_runtime_slot_t *runtime = NULL;
  int32_t status =
      proton_get_runtime_for_destroy(window->runtime, &runtime);
  if (status != PROTON_OK) {
    return status;
  }
  *out_window = window;
  return PROTON_OK;
}

int32_t proton_window_enqueue_closed_once(proton_runtime_slot_t *runtime,
                                          proton_window_slot_t *window) {
  if (window == NULL || window->closed_event_sent) {
    return PROTON_OK;
  }
  if (!proton_runtime_enqueue_window_event(runtime, PROTON_EVENT_WINDOW_CLOSED,
                                           window->logical_id)) {
    return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                            "failed to queue window_closed event");
  }
  window->closed_event_sent = true;
  return PROTON_OK;
}

void proton_runtime_sync_engine_closed_windows(
    proton_runtime_slot_t *runtime) {
  for (proton_window_slot_t *window = runtime->windows; window != NULL;
       window = window->next) {
    if (window->lifecycle == PROTON_WINDOW_DESTROYED ||
        window->engine_window == NULL ||
        !proton_engine_window_is_closed(window->engine_window)) {
      continue;
    }
    proton_window_slot_mark_closed(window);
    if (proton_window_enqueue_closed_once(runtime, window) == PROTON_OK) {
      window->visible = false;
    }
  }
}

int32_t proton_runtime_sync_engine_window_states(
    proton_runtime_slot_t *runtime) {
  for (proton_window_slot_t *window = runtime->windows; window != NULL;
       window = window->next) {
    if (window->lifecycle != PROTON_WINDOW_LIVE ||
        window->engine_window == NULL ||
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
    proton_event_t *event = proton_event_create_window(
        PROTON_EVENT_WINDOW_STATE_CHANGED, window->logical_id);
    if (event == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "failed to allocate window state event");
    }
    int32_t fields[] = {
        state.x,
        state.y,
        state.width,
        state.height,
        state.monitor_x,
        state.monitor_y,
        state.monitor_width,
        state.monitor_height,
        state.work_x,
        state.work_y,
        state.work_width,
        state.work_height,
        state.scale_factor_percent,
        state.zoom_percent,
        state.visible,
        state.focused,
        state.minimized,
        state.maximized,
        state.fullscreen,
        state.always_on_top,
        state.theme,
    };
    memcpy(event->window_state, fields, sizeof(fields));
    if (!proton_runtime_enqueue_event(runtime, event)) {
      return PROTON_OK;
    }
    window->state = state;
    window->state_valid = true;
  }
  return PROTON_OK;
}

int32_t proton_runtime_sync_engine_close_requests(
    proton_runtime_slot_t *runtime) {
  for (proton_window_slot_t *window = runtime->windows; window != NULL;
       window = window->next) {
    if (window->lifecycle == PROTON_WINDOW_DESTROYING ||
        window->lifecycle == PROTON_WINDOW_DESTROYED ||
        window->engine_window == NULL) {
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
    proton_event_t *event = proton_event_create_window(
        PROTON_EVENT_WINDOW_CLOSE_REQUESTED, window->logical_id);
    if (event == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "failed to allocate window close event");
    }
    event->request_id = (int64_t)request_id;
    if (!proton_runtime_enqueue_event(runtime, event)) {
      return PROTON_OK;
    }
    window->close_request_notified_revision = request_id;
  }
  return PROTON_OK;
}

void proton_runtime_sync_engine_bridge_lifecycle(
    proton_runtime_slot_t *runtime) {
  for (proton_window_slot_t *window = runtime->windows; window != NULL;
       window = window->next) {
    if (window->lifecycle == PROTON_WINDOW_DESTROYING ||
        window->lifecycle == PROTON_WINDOW_DESTROYED ||
        window->engine_window == NULL) {
      continue;
    }
    uint64_t revision =
        proton_engine_window_bridge_revision(window->engine_window);
    if (revision == 0 || revision == window->bridge_notified_revision) {
      continue;
    }
    proton_event_t *event = proton_event_create_window(
        PROTON_EVENT_BRIDGE_LIFECYCLE_CHANGED, window->logical_id);
    if (event != NULL) {
      event->revision = (int64_t)revision;
    }
    if (event != NULL && proton_runtime_enqueue_event(runtime, event)) {
      window->bridge_notified_revision = revision;
    }
  }
}

int32_t proton_destroy_windows_for_runtime(proton_runtime_slot_t *runtime) {
  for (proton_window_slot_t *window = runtime->windows; window != NULL;
       window = window->next) {
    if (window->lifecycle == PROTON_WINDOW_DESTROYED) {
      continue;
    }
    proton_window_slot_begin_destroy(window);
    proton_destroy_views_for_window(window);
    if (window->engine_window != NULL) {
      char engine_error[512] = {0};
      int32_t status = proton_engine_window_destroy(
          window->engine_window, engine_error, sizeof(engine_error));
      if (status != PROTON_OK) {
        return proton_set_engine_status(status, engine_error);
      }
    }
    proton_window_slot_destroy(window);
  }
  return PROTON_OK;
}

int32_t proton_view_slot_create(proton_window_slot_t *window,
                                proton_engine_view_t *engine_view,
                                int64_t logical_id, int32_t x, int32_t y,
                                int32_t width, int32_t height, int32_t z_order,
                                bool visible,
                                proton_view_slot_t **out_view) {
  if (window == NULL || logical_id <= 0 || out_view == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window and out_view are required");
  }
  proton_view_slot_t *view =
      (proton_view_slot_t *)calloc(1, sizeof(*view));
  if (view == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate view state");
  }
  view->runtime = window->runtime;
  view->lifecycle = PROTON_VIEW_LIVE;
  view->window = window;
  view->engine_view = engine_view;
  view->x = x;
  view->y = y;
  view->width = width;
  view->height = height;
  view->z_order = z_order;
  view->visible = visible;
  view->logical_id = logical_id;
  view->next = window->runtime->views;
  window->runtime->views = view;
  *out_view = view;
  return PROTON_OK;
}

void proton_view_slot_destroy(proton_view_slot_t *view) {
  if (view != NULL) {
    view->lifecycle = PROTON_VIEW_DESTROYED;
    view->engine_view = NULL;
  }
}

void proton_view_slot_begin_destroy(proton_view_slot_t *view) {
  if (view != NULL && view->lifecycle == PROTON_VIEW_LIVE) {
    view->lifecycle = PROTON_VIEW_DESTROYING;
  }
}

int32_t proton_get_view(proton_view_slot_t *view,
                        proton_view_slot_t **out_view) {
  int32_t status = proton_get_view_for_destroy(view, out_view);
  if (status != PROTON_OK) {
    return status;
  }
  if (view->lifecycle != PROTON_VIEW_LIVE) {
    return proton_set_error(PROTON_ERR_DESTROYED,
                            "view is being destroyed");
  }
  return PROTON_OK;
}

int32_t proton_get_view_for_destroy(proton_view_slot_t *view,
                                    proton_view_slot_t **out_view) {
  if (view == NULL || out_view == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE, "invalid view handle");
  }
  if (view->lifecycle == PROTON_VIEW_DESTROYED) {
    return proton_set_error(PROTON_ERR_DESTROYED, "view is destroyed");
  }
  proton_runtime_slot_t *runtime = NULL;
  int32_t status =
      proton_get_runtime_for_destroy(view->runtime, &runtime);
  if (status != PROTON_OK) {
    return status;
  }
  *out_view = view;
  return PROTON_OK;
}

void proton_destroy_views_for_window(proton_window_slot_t *window) {
  for (proton_view_slot_t *view = window->runtime->views; view != NULL;
       view = view->next) {
    if (view->lifecycle != PROTON_VIEW_DESTROYED && view->window == window) {
      proton_view_slot_begin_destroy(view);
      proton_view_slot_destroy(view);
    }
  }
}

int32_t proton_image_slot_create(proton_engine_image_t *engine_image,
                                 proton_image_slot_t **out_image) {
  if (out_image == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_image is required");
  }
  proton_image_slot_t *image =
      (proton_image_slot_t *)calloc(1, sizeof(*image));
  if (image == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate image state");
  }
  image->engine_image = engine_image;
  *out_image = image;
  return PROTON_OK;
}

void proton_image_slot_destroy(proton_image_slot_t *image) {
  if (image != NULL) {
    image->destroyed = true;
    image->engine_image = NULL;
    free(image);
  }
}

int32_t proton_get_image(proton_image_slot_t *image,
                         proton_image_slot_t **out_image) {
  if (image == NULL || out_image == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid image handle");
  }
  if (image->destroyed) {
    return proton_set_error(PROTON_ERR_DESTROYED, "image is destroyed");
  }
  *out_image = image;
  return PROTON_OK;
}
