#if defined(__APPLE__)

#include "platform_events.h"

#include "../../proton_event.h"
#include "../../proton_engine.h"

#include <pthread.h>
#include <stdint.h>

#define PROTON_PLATFORM_EVENT_CAPACITY 32

static proton_event_t *g_platform_events[PROTON_PLATFORM_EVENT_CAPACITY];
static uint32_t g_platform_event_head = 0;
static uint32_t g_platform_event_count = 0;
static pthread_mutex_t g_platform_event_lock = PTHREAD_MUTEX_INITIALIZER;
static proton_engine_platform_event_signal_callback_t
    g_platform_event_signal_callback = NULL;

void proton_engine_platform_event_enqueue(proton_event_t *event) {
  if (event == NULL) {
    return;
  }
  pthread_mutex_lock(&g_platform_event_lock);
  if (g_platform_event_count == PROTON_PLATFORM_EVENT_CAPACITY) {
    proton_event_destroy(g_platform_events[g_platform_event_head]);
    g_platform_events[g_platform_event_head] = NULL;
    g_platform_event_head =
        (g_platform_event_head + 1) % PROTON_PLATFORM_EVENT_CAPACITY;
    g_platform_event_count--;
  }
  uint32_t index =
      (g_platform_event_head + g_platform_event_count) %
      PROTON_PLATFORM_EVENT_CAPACITY;
  g_platform_events[index] = event;
  g_platform_event_count++;
  pthread_mutex_unlock(&g_platform_event_lock);

  if (g_platform_event_signal_callback != NULL) {
    g_platform_event_signal_callback(PROTON_WAIT_PLATFORM);
  }
}

void proton_engine_platform_event_set_signal_callback(
    proton_engine_platform_event_signal_callback_t callback) {
  g_platform_event_signal_callback = callback;
}

proton_event_t *proton_engine_take_platform_event(
    proton_engine_runtime_t *runtime) {
  (void)runtime;
  pthread_mutex_lock(&g_platform_event_lock);
  if (g_platform_event_count == 0) {
    pthread_mutex_unlock(&g_platform_event_lock);
    return NULL;
  }
  proton_event_t *event = g_platform_events[g_platform_event_head];
  g_platform_events[g_platform_event_head] = NULL;
  g_platform_event_head =
      (g_platform_event_head + 1) % PROTON_PLATFORM_EVENT_CAPACITY;
  g_platform_event_count--;
  pthread_mutex_unlock(&g_platform_event_lock);
  return event;
}

#endif
