#include "view_events.h"
#include "../../proton_event.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

struct proton_view_events {
  proton_view_id_t view;
  proton_window_id_t window;
  int bound;
  int closed;
#ifdef _WIN32
  CRITICAL_SECTION lock;
#else
  pthread_mutex_t lock;
#endif
};

static void proton_view_events_lock(proton_view_events_t *events) {
#ifdef _WIN32
  EnterCriticalSection(&events->lock);
#else
  pthread_mutex_lock(&events->lock);
#endif
}

static void proton_view_events_unlock(proton_view_events_t *events) {
#ifdef _WIN32
  LeaveCriticalSection(&events->lock);
#else
  pthread_mutex_unlock(&events->lock);
#endif
}

proton_view_events_t *proton_view_events_create(void) {
  proton_view_events_t *events =
      (proton_view_events_t *)calloc(1, sizeof(*events));
  if (events == NULL) {
    return NULL;
  }
#ifdef _WIN32
  InitializeCriticalSection(&events->lock);
#else
  pthread_mutex_init(&events->lock, NULL);
#endif
  return events;
}

void proton_view_events_destroy(proton_view_events_t *events) {
  if (events == NULL) {
    return;
  }
#ifdef _WIN32
  DeleteCriticalSection(&events->lock);
#else
  pthread_mutex_destroy(&events->lock);
#endif
  free(events);
}

void proton_view_events_bind(proton_view_events_t *events,
                             proton_view_id_t view,
                             proton_window_id_t window) {
  if (events == NULL) {
    return;
  }
  proton_view_events_lock(events);
  events->view = view;
  events->window = window;
  events->bound = 1;
  proton_view_events_unlock(events);
}

int proton_view_events_ids(proton_view_events_t *events,
                           proton_view_id_t *out_view,
                           proton_window_id_t *out_window) {
  if (events == NULL || out_view == NULL || out_window == NULL) {
    return 0;
  }
  proton_view_events_lock(events);
  int bound = events->bound;
  if (bound) {
    *out_view = events->view;
    *out_window = events->window;
  }
  proton_view_events_unlock(events);
  return bound;
}

static void proton_view_events_enqueue(proton_view_events_t *events,
                                       proton_event_t *event,
                                       int closes_view) {
  if (events == NULL || event == NULL) {
    proton_event_destroy(event);
    return;
  }
  proton_view_events_lock(events);
  if (!events->bound || events->closed) {
    proton_view_events_unlock(events);
    proton_event_destroy(event);
    return;
  }
  if (closes_view) {
    events->closed = 1;
  }
  event->view = events->view;
  event->window = events->window;
  proton_view_events_unlock(events);
  (void)proton_event_publish(event);
}

void proton_view_events_loading_changed(proton_view_events_t *events,
                                        int32_t is_loading) {
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_VIEW_LOADING_CHANGED);
  if (event != NULL) {
    event->bool_a = is_loading;
  }
  proton_view_events_enqueue(events, event, 0);
}

void proton_view_events_navigated(proton_view_events_t *events,
                                  const char *url) {
  proton_event_t *event = proton_event_create(PROTON_EVENT_VIEW_NAVIGATED);
  if (event != NULL && !proton_event_set_text(&event->text_a, url)) {
    proton_event_destroy(event);
    event = NULL;
  }
  proton_view_events_enqueue(events, event, 0);
}

void proton_view_events_title_updated(proton_view_events_t *events,
                                      const char *title) {
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_VIEW_TITLE_UPDATED);
  if (event != NULL && !proton_event_set_text(&event->text_a, title)) {
    proton_event_destroy(event);
    event = NULL;
  }
  proton_view_events_enqueue(events, event, 0);
}

void proton_view_events_load_failed(proton_view_events_t *events,
                                    const char *url,
                                    int32_t error_code,
                                    const char *error_text) {
  proton_event_t *event = proton_event_create(PROTON_EVENT_VIEW_LOAD_FAILED);
  if (event != NULL &&
      (!proton_event_set_text(&event->text_a, url) ||
       !proton_event_set_text(&event->text_b, error_text))) {
    proton_event_destroy(event);
    event = NULL;
  }
  if (event != NULL) {
    event->int_a = error_code;
  }
  proton_view_events_enqueue(events, event, 0);
}

void proton_view_events_closed(proton_view_events_t *events) {
  proton_view_events_enqueue(
      events, proton_event_create(PROTON_EVENT_VIEW_CLOSED), 1);
}
