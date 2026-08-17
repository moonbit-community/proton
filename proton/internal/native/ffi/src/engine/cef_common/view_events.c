#include "view_events.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

#define PROTON_VIEW_MAX_EVENTS 16
#define PROTON_VIEW_EVENT_BYTES 4096

struct proton_view_events {
  proton_view_id_t view;
  proton_window_id_t window;
  int bound;
  char *queue[PROTON_VIEW_MAX_EVENTS];
  size_t head;
  size_t count;
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

static int proton_view_json_escape(const char *value,
                                   char *out,
                                   size_t out_len) {
  size_t used = 0;
  if (out == NULL || out_len == 0) {
    return 0;
  }
  for (const unsigned char *cursor =
           (const unsigned char *)(value != NULL ? value : "");
       *cursor != '\0'; cursor++) {
    const char *escape = NULL;
    char unicode[7] = {0};
    switch (*cursor) {
    case '"':
      escape = "\\\"";
      break;
    case '\\':
      escape = "\\\\";
      break;
    case '\b':
      escape = "\\b";
      break;
    case '\f':
      escape = "\\f";
      break;
    case '\n':
      escape = "\\n";
      break;
    case '\r':
      escape = "\\r";
      break;
    case '\t':
      escape = "\\t";
      break;
    default:
      if (*cursor < 0x20) {
        snprintf(unicode, sizeof(unicode), "\\u%04x", *cursor);
        escape = unicode;
      }
      break;
    }
    if (escape != NULL) {
      size_t length = strlen(escape);
      if (used + length >= out_len) {
        return 0;
      }
      memcpy(out + used, escape, length);
      used += length;
    } else {
      if (used + 1 >= out_len) {
        return 0;
      }
      out[used++] = (char)*cursor;
    }
  }
  out[used] = '\0';
  return 1;
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
  for (size_t i = 0; i < PROTON_VIEW_MAX_EVENTS; i++) {
    free(events->queue[i]);
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

static void proton_view_events_enqueue(proton_view_events_t *events,
                                       const char *event_json) {
  if (events == NULL || event_json == NULL) {
    return;
  }
  proton_view_events_lock(events);
  if (!events->bound || events->count >= PROTON_VIEW_MAX_EVENTS) {
    proton_view_events_unlock(events);
    return;
  }
  char *owned = (char *)malloc(strlen(event_json) + 1);
  if (owned == NULL) {
    proton_view_events_unlock(events);
    return;
  }
  strcpy(owned, event_json);
  size_t index = (events->head + events->count) % PROTON_VIEW_MAX_EVENTS;
  events->queue[index] = owned;
  events->count++;
  proton_view_events_unlock(events);
}

void proton_view_events_loading_changed(proton_view_events_t *events,
                                        int32_t is_loading) {
  char json[256];
  snprintf(json, sizeof(json),
           "{\"type\":\"view_loading_changed\",\"view\":\"%lld\","
           "\"window\":\"%lld\",\"is_loading\":%s}",
           (long long)events->view, (long long)events->window,
           is_loading ? "true" : "false");
  proton_view_events_enqueue(events, json);
}

void proton_view_events_navigated(proton_view_events_t *events,
                                  const char *url) {
  char escaped[2048];
  if (!proton_view_json_escape(url, escaped, sizeof(escaped))) {
    return;
  }
  char json[PROTON_VIEW_EVENT_BYTES];
  snprintf(json, sizeof(json),
           "{\"type\":\"view_navigated\",\"view\":\"%lld\","
           "\"window\":\"%lld\",\"url\":\"%s\"}",
           (long long)events->view, (long long)events->window, escaped);
  proton_view_events_enqueue(events, json);
}

void proton_view_events_title_updated(proton_view_events_t *events,
                                      const char *title) {
  char escaped[2048];
  if (!proton_view_json_escape(title, escaped, sizeof(escaped))) {
    return;
  }
  char json[PROTON_VIEW_EVENT_BYTES];
  snprintf(json, sizeof(json),
           "{\"type\":\"view_title_updated\",\"view\":\"%lld\","
           "\"window\":\"%lld\",\"title\":\"%s\"}",
           (long long)events->view, (long long)events->window, escaped);
  proton_view_events_enqueue(events, json);
}

void proton_view_events_load_failed(proton_view_events_t *events,
                                    const char *url,
                                    int32_t error_code,
                                    const char *error_text) {
  char escaped_url[2048];
  char escaped_text[2048];
  if (!proton_view_json_escape(url, escaped_url, sizeof(escaped_url)) ||
      !proton_view_json_escape(error_text, escaped_text,
                               sizeof(escaped_text))) {
    return;
  }
  char json[PROTON_VIEW_EVENT_BYTES];
  snprintf(json, sizeof(json),
           "{\"type\":\"view_load_failed\",\"view\":\"%lld\","
           "\"window\":\"%lld\",\"url\":\"%s\",\"error\":%d,"
           "\"message\":\"%s\"}",
           (long long)events->view, (long long)events->window, escaped_url,
           (int)error_code, escaped_text);
  proton_view_events_enqueue(events, json);
}

int32_t proton_view_events_poll_json(proton_view_events_t *events,
                                     char *buffer,
                                     int32_t buffer_len,
                                     int32_t *out_required_len) {
  if (events == NULL || out_required_len == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_view_events_lock(events);
  if (events->count == 0) {
    proton_view_events_unlock(events);
    *out_required_len = 0;
    return PROTON_EVENT_NONE;
  }
  char *event_json = events->queue[events->head];
  int32_t required = (int32_t)strlen(event_json);
  if (buffer == NULL || buffer_len <= required) {
    proton_view_events_unlock(events);
    *out_required_len = required;
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, event_json, (size_t)required + 1);
  free(event_json);
  events->queue[events->head] = NULL;
  events->head = (events->head + 1) % PROTON_VIEW_MAX_EVENTS;
  events->count--;
  proton_view_events_unlock(events);
  *out_required_len = required;
  return PROTON_OK;
}
