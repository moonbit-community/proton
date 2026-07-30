#include "platform_events.h"

#include "../../proton_engine.h"

#include <pthread.h>
#include <stdint.h>
#include <string.h>

#define PROTON_PLATFORM_EVENT_CAPACITY 32
#define PROTON_PLATFORM_EVENT_MAX_BYTES 65536

static char g_platform_events[PROTON_PLATFORM_EVENT_CAPACITY]
                             [PROTON_PLATFORM_EVENT_MAX_BYTES];
static uint32_t g_platform_event_head = 0;
static uint32_t g_platform_event_count = 0;
static pthread_mutex_t g_platform_event_lock = PTHREAD_MUTEX_INITIALIZER;
static proton_engine_platform_event_signal_callback_t
    g_platform_event_signal_callback = NULL;

void proton_engine_platform_event_enqueue_json(const char *event_json) {
  if (event_json == NULL) {
    return;
  }
  size_t event_len = strlen(event_json);
  if (event_len >= PROTON_PLATFORM_EVENT_MAX_BYTES) {
    return;
  }
  pthread_mutex_lock(&g_platform_event_lock);
  if (g_platform_event_count == PROTON_PLATFORM_EVENT_CAPACITY) {
    g_platform_event_head =
        (g_platform_event_head + 1) % PROTON_PLATFORM_EVENT_CAPACITY;
    g_platform_event_count--;
  }
  uint32_t index =
      (g_platform_event_head + g_platform_event_count) %
      PROTON_PLATFORM_EVENT_CAPACITY;
  memcpy(g_platform_events[index], event_json, event_len + 1);
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

int32_t proton_engine_take_platform_event(proton_engine_runtime_t *runtime,
                                          char *buffer,
                                          size_t buffer_len,
                                          int32_t *out_present) {
  (void)runtime;
  if (out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_present = 0;
  pthread_mutex_lock(&g_platform_event_lock);
  if (g_platform_event_count == 0) {
    pthread_mutex_unlock(&g_platform_event_lock);
    return PROTON_OK;
  }
  const char *event = g_platform_events[g_platform_event_head];
  size_t event_len = strlen(event);
  if (buffer == NULL || buffer_len <= event_len) {
    pthread_mutex_unlock(&g_platform_event_lock);
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, event, event_len + 1);
  g_platform_event_head =
      (g_platform_event_head + 1) % PROTON_PLATFORM_EVENT_CAPACITY;
  g_platform_event_count--;
  *out_present = 1;
  pthread_mutex_unlock(&g_platform_event_lock);
  return PROTON_OK;
}
