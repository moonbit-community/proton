#ifndef PROTON_SCREEN_MONITOR_STUB_H
#define PROTON_SCREEN_MONITOR_STUB_H

#include "moonbit.h"

#include <stdint.h>

enum screen_monitor_status {
  screen_monitor_STATUS_OK = 0,
  screen_monitor_STATUS_BACKEND_UNAVAILABLE = 1,
  screen_monitor_STATUS_OPERATION_FAILED = 2,
  screen_monitor_STATUS_EMPTY = 3,
};

enum screen_monitor_event {
  screen_monitor_EVENT_ADDED = 0,
  screen_monitor_EVENT_REMOVED = 1,
  screen_monitor_EVENT_METRICS_CHANGED = 2,
};

#define SCREEN_MONITOR_MAX_DISPLAYS 16
#define SCREEN_MONITOR_EVENT_QUEUE_CAPACITY 64

/* A connected display captured by the platform enumeration backend. The fields
   mirror Electron's `Display` geometry, scaled so one unit is one physical
   pixel (matching the top-left coordinate system used across the facade). */
typedef struct screen_monitor_display {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t work_x;
  int32_t work_y;
  int32_t work_width;
  int32_t work_height;
  int32_t scale_factor_percent;
  int32_t is_primary;
  /* Stable-enough identity for hot-plug diffing. On Windows this is the
     monitor handle-derived index; on macOS/Linux it is the bounds-derived
     digest. Uses the *earlier* snapshot's index when a display persists, so
     ADDED/REMOVED fire only on real topology changes. */
  int32_t id;
  int32_t present;
} screen_monitor_display_t;

typedef struct screen_monitor_event_node {
  int32_t event;
  struct screen_monitor_event_node *next;
} screen_monitor_event_node_t;

typedef void (*screen_monitor_event_wakeup_fn)(void);

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <pthread.h>
#endif

typedef struct screen_monitor_state {
  int32_t status;
  char last_error[512];
  /* Latest display snapshot used by query and hot-plug diff backends. */
  screen_monitor_display_t displays[SCREEN_MONITOR_MAX_DISPLAYS];
  int32_t display_count;
  /* Thread-safe bounded event queue populated by the platform watch backend. */
  screen_monitor_event_node_t *event_head;
  screen_monitor_event_node_t *event_tail;
  int32_t event_queue_size;
  int32_t event_queue_overflow;
  screen_monitor_event_wakeup_fn event_wakeup;
  /* Watch backend state. `watch_started` is best-effort: a backend that is
     unavailable records the failure on `watch_error` and returns a non-OK
     status while leaving query APIs fully usable. */
  volatile int32_t watch_started;
  int32_t watch_available;
  char watch_error[512];
  /* Set by create() and by destroy paths so an explicit destroy and the GC
     finalizer cannot both tear the backend down twice. */
  int32_t destroyed;
#if defined(_WIN32)
  CRITICAL_SECTION event_lock;
  HANDLE device_handle;
  HANDLE ready_event;
  HANDLE watch_thread;
  DWORD watch_thread_id;
  HWND message_window;
  int32_t registered;
#elif defined(__APPLE__)
  pthread_mutex_t event_lock;
  pthread_cond_t ready_cond;
  pthread_t watch_thread;
  int ready;
  volatile int32_t thread_started;
  void *observer_token;
  void *notification_observer;
  int32_t frame_timer_started;
#else
  pthread_mutex_t event_lock;
  pthread_cond_t ready_cond;
  pthread_t watch_thread;
  int ready;
  volatile int32_t thread_started;
  /* Set by stop_watching and observed by the GDK event loop so the watch
     thread can exit promptly without a second global wake channel. */
  volatile int32_t watch_stop;
#endif
} screen_monitor_state_t;

void screen_monitor_platform_init(screen_monitor_state_t *state);

/* Refreshes `state->displays` from the current platform topology, filling the
   geometry fields. Returns the number of displays enumerated (>= 0) or a
   negative status code on failure. The `id` field is assigned per-platform for
   stable hot-plug diffing. */
int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state);

/* Fills `*out_x`/`*out_y` with the current cursor position in physical pixels. */
int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y);

/* Returns the index into `state->displays` of the display nearest to (x, y),
   preferring a display that actually contains the point. Returns -1 when no
   display is available. */
int32_t screen_monitor_platform_nearest_display(screen_monitor_state_t *state,
                                                int32_t x, int32_t y);

/* Starts or stops the platform event watch backend. Each implementation is
   best-effort: failure is recorded on `watch_error` and returns a non-OK
   status, leaving the query APIs usable. */
int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state);
int32_t screen_monitor_platform_stop_watching(screen_monitor_state_t *state);

/* Thread-safe bounded event queue shared by all platforms. */
void screen_monitor_lock_init(screen_monitor_state_t *state);
void screen_monitor_lock_destroy(screen_monitor_state_t *state);
void screen_monitor_push_event(screen_monitor_state_t *state, int32_t event);
int32_t screen_monitor_take_event(screen_monitor_state_t *state,
                                  int32_t *out_event);
void screen_monitor_set_event_wakeup(
    screen_monitor_state_t *state,
    screen_monitor_event_wakeup_fn wakeup);
void screen_monitor_release_events(screen_monitor_state_t *state);

#endif
