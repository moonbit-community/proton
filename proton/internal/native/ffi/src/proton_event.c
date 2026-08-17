#include "proton_event.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
static SRWLOCK g_event_sink_mutex = SRWLOCK_INIT;
#else
static pthread_mutex_t g_event_sink_mutex = PTHREAD_MUTEX_INITIALIZER;
#endif
static proton_event_sink_fn g_event_sink = NULL;
static void *g_event_sink_user_data = NULL;

static void proton_event_sink_lock(void) {
#ifdef _WIN32
  AcquireSRWLockExclusive(&g_event_sink_mutex);
#else
  (void)pthread_mutex_lock(&g_event_sink_mutex);
#endif
}

static void proton_event_sink_unlock(void) {
#ifdef _WIN32
  ReleaseSRWLockExclusive(&g_event_sink_mutex);
#else
  (void)pthread_mutex_unlock(&g_event_sink_mutex);
#endif
}

static void proton_event_mutex_init(proton_event_mutex_t *mutex) {
#ifdef _WIN32
  InitializeCriticalSection(mutex);
#else
  (void)pthread_mutex_init(mutex, NULL);
#endif
}

static void proton_event_mutex_lock(proton_event_mutex_t *mutex) {
#ifdef _WIN32
  EnterCriticalSection(mutex);
#else
  (void)pthread_mutex_lock(mutex);
#endif
}

static void proton_event_mutex_unlock(proton_event_mutex_t *mutex) {
#ifdef _WIN32
  LeaveCriticalSection(mutex);
#else
  (void)pthread_mutex_unlock(mutex);
#endif
}

static void proton_event_mutex_destroy(proton_event_mutex_t *mutex) {
#ifdef _WIN32
  DeleteCriticalSection(mutex);
#else
  (void)pthread_mutex_destroy(mutex);
#endif
}

proton_event_t *proton_event_create(proton_event_kind_t kind) {
  proton_event_t *event = (proton_event_t *)calloc(1, sizeof(*event));
  if (event != NULL) {
    event->kind = kind;
  }
  return event;
}

proton_event_t *proton_event_create_window(proton_event_kind_t kind,
                                           int64_t window) {
  proton_event_t *event = proton_event_create(kind);
  if (event != NULL) {
    event->window = window;
  }
  return event;
}

bool proton_event_set_text(char **field, const char *value) {
  if (field == NULL) {
    return false;
  }
  *field = NULL;
  if (value == NULL) {
    return true;
  }
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return false;
  }
  memcpy(copy, value, length + 1);
  *field = copy;
  return true;
}

bool proton_event_set_items(proton_event_t *event,
                            const char *const *items,
                            int32_t item_count) {
  if (event == NULL || item_count < 0 ||
      (item_count > 0 && items == NULL)) {
    return false;
  }
  if (item_count == 0) {
    return true;
  }
  event->items = (char **)calloc((size_t)item_count, sizeof(char *));
  if (event->items == NULL) {
    return false;
  }
  event->item_count = item_count;
  for (int32_t i = 0; i < item_count; i++) {
    if (!proton_event_set_text(&event->items[i], items[i])) {
      return false;
    }
  }
  return true;
}

void proton_event_destroy(proton_event_t *event) {
  if (event == NULL) {
    return;
  }
  free(event->text_a);
  free(event->text_b);
  free(event->text_c);
  for (int32_t i = 0; i < event->item_count; i++) {
    free(event->items[i]);
  }
  free(event->items);
  free(event);
}

bool proton_event_queue_init(proton_event_queue_t *queue) {
  if (queue == NULL) {
    return false;
  }
  memset(queue, 0, sizeof(*queue));
  proton_event_mutex_init(&queue->mutex);
  return true;
}

void proton_event_queue_destroy(proton_event_queue_t *queue) {
  if (queue == NULL) {
    return;
  }
  proton_event_mutex_lock(&queue->mutex);
  for (uint32_t i = 0; i < PROTON_EVENT_QUEUE_CAPACITY; i++) {
    proton_event_destroy(queue->items[i]);
    queue->items[i] = NULL;
  }
  queue->head = 0;
  queue->count = 0;
  proton_event_mutex_unlock(&queue->mutex);
  proton_event_mutex_destroy(&queue->mutex);
}

bool proton_event_queue_push(proton_event_queue_t *queue,
                             proton_event_t *event) {
  if (queue == NULL || event == NULL) {
    return false;
  }
  proton_event_mutex_lock(&queue->mutex);
  if (queue->count >= PROTON_EVENT_QUEUE_CAPACITY) {
    proton_event_mutex_unlock(&queue->mutex);
    return false;
  }
  uint32_t index = (queue->head + queue->count) % PROTON_EVENT_QUEUE_CAPACITY;
  queue->items[index] = event;
  queue->count++;
  proton_event_mutex_unlock(&queue->mutex);
  return true;
}

proton_event_t *proton_event_queue_pop(proton_event_queue_t *queue) {
  if (queue == NULL) {
    return NULL;
  }
  proton_event_mutex_lock(&queue->mutex);
  if (queue->count == 0) {
    proton_event_mutex_unlock(&queue->mutex);
    return NULL;
  }
  proton_event_t *event = queue->items[queue->head];
  queue->items[queue->head] = NULL;
  queue->head = (queue->head + 1) % PROTON_EVENT_QUEUE_CAPACITY;
  queue->count--;
  proton_event_mutex_unlock(&queue->mutex);
  return event;
}

uint32_t proton_event_queue_count(proton_event_queue_t *queue) {
  if (queue == NULL) {
    return 0;
  }
  proton_event_mutex_lock(&queue->mutex);
  uint32_t count = queue->count;
  proton_event_mutex_unlock(&queue->mutex);
  return count;
}

void proton_event_bind_sink(proton_event_sink_fn sink, void *user_data) {
  proton_event_sink_lock();
  g_event_sink = sink;
  g_event_sink_user_data = user_data;
  proton_event_sink_unlock();
}

void proton_event_unbind_sink(void *user_data) {
  proton_event_sink_lock();
  if (g_event_sink_user_data == user_data) {
    g_event_sink = NULL;
    g_event_sink_user_data = NULL;
  }
  proton_event_sink_unlock();
}

bool proton_event_publish(proton_event_t *event) {
  if (event == NULL) {
    return false;
  }
  proton_event_sink_lock();
  bool published = g_event_sink != NULL &&
                   g_event_sink(g_event_sink_user_data, event);
  proton_event_sink_unlock();
  if (!published) {
    proton_event_destroy(event);
  }
  return published;
}
