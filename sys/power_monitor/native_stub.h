#ifndef PROTON_POWER_MONITOR_STUB_H
#define PROTON_POWER_MONITOR_STUB_H

#include "moonbit.h"

#include <stdint.h>

enum power_monitor_source {
  power_monitor_SOURCE_UNKNOWN = 0,
  power_monitor_SOURCE_AC = 1,
  power_monitor_SOURCE_BATTERY = 2,
};

enum power_monitor_status {
  power_monitor_STATUS_OK = 0,
  power_monitor_STATUS_BACKEND_UNAVAILABLE = 1,
  power_monitor_STATUS_OPERATION_FAILED = 2,
  power_monitor_STATUS_EMPTY = 3,
};

enum power_monitor_event {
  power_monitor_EVENT_SUSPEND = 0,
  power_monitor_EVENT_RESUME = 1,
  power_monitor_EVENT_ON_AC = 2,
  power_monitor_EVENT_ON_BATTERY = 3,
  power_monitor_EVENT_LOCK_SCREEN = 4,
  power_monitor_EVENT_UNLOCK_SCREEN = 5,
};

#define POWER_MONITOR_EVENT_QUEUE_CAPACITY 64

typedef struct power_monitor_event_node {
  int32_t event;
  struct power_monitor_event_node *next;
} power_monitor_event_node_t;

typedef void (*power_monitor_event_wakeup_fn)(void);

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <pthread.h>
#endif

typedef struct power_monitor_state {
  int32_t status;
  int32_t source;
  int32_t battery_percent;
  int32_t has_battery_percent;
  int64_t idle_seconds;
  char last_error[512];
  /* Thread-safe bounded event queue populated by the platform watch backend.
     The head is the oldest event; a full queue drops the oldest entry so the
     latest system state is always preserved. */
  power_monitor_event_node_t *event_head;
  power_monitor_event_node_t *event_tail;
  int32_t event_queue_size;
  int32_t event_queue_overflow;
  power_monitor_event_wakeup_fn event_wakeup;
  /* Watch backend state. `watch_started` is best-effort: a backend that is
     unavailable records the failure on `watch_error` and returns a non-OK
     status while leaving the state usable for polling queries. */
  volatile int32_t watch_started;
  int32_t watch_available;
  char watch_error[512];
  int32_t last_source;
  /* Set by create() and by destroy paths so an explicit destroy and the GC
     finalizer cannot both tear the backend down twice. */
  int32_t destroyed;
#if defined(_WIN32)
  CRITICAL_SECTION event_lock;
  HANDLE ready_event;
  HANDLE watch_thread;
  DWORD watch_thread_id;
  HWND message_window;
#elif defined(__APPLE__)
  pthread_mutex_t event_lock;
  pthread_t watch_thread;
  pthread_cond_t ready_cond;
  int ready;
  volatile int32_t thread_started;
  void *run_loop;
  void *observer_target;
  void *power_source;
  void *notify_port;
  uint32_t root_port;
  uint32_t notify_ref;
  int32_t lock_token;
  int32_t unlock_token;
#else
  pthread_mutex_t event_lock;
  pthread_t watch_thread;
  pthread_cond_t ready_cond;
  int ready;
  volatile int32_t thread_started;
  /* Set by stop_watching and observed by the D-Bus dispatch loop so the watch
     thread can exit promptly without a second global wake channel. */
  volatile int32_t watch_stop;
#endif
} power_monitor_state_t;

void power_monitor_platform_init(power_monitor_state_t *state);
int32_t power_monitor_platform_query_idle(power_monitor_state_t *state);
int32_t power_monitor_platform_query_source(power_monitor_state_t *state);

/* Starts or stops the platform event watch backend. Each implementation is
   best-effort: failure is recorded on `watch_error` and returns a non-OK
   status, leaving the state usable for polling queries. */
int32_t power_monitor_platform_start_watching(power_monitor_state_t *state);
int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state);

/* Thread-safe bounded event queue shared by all platforms. */
void power_monitor_lock_init(power_monitor_state_t *state);
void power_monitor_lock_destroy(power_monitor_state_t *state);
void power_monitor_push_event(power_monitor_state_t *state, int32_t event);
int32_t power_monitor_take_event(power_monitor_state_t *state,
                                 int32_t *out_event);
void power_monitor_set_event_wakeup(
    power_monitor_state_t *state,
    power_monitor_event_wakeup_fn wakeup);
void power_monitor_release_events(power_monitor_state_t *state);

#endif
