#include "../../native_stub.h"
#include <string.h>

/* Exercise the production queue without requiring physical display hot-plug. */
int32_t proton_test_screen_event_snapshots(void) {
  screen_monitor_state_t state = {0};
  screen_monitor_lock_init(&state);
  screen_monitor_display_t secondary = {0};
  secondary.id = 42;
  secondary.x = 1920;
  secondary.width = 1280;
  secondary.present = 1;
  screen_monitor_push_event(&state, screen_monitor_EVENT_REMOVED, &secondary);
  secondary.id = 43;
  secondary.width = 2560;
  screen_monitor_push_event(&state, screen_monitor_EVENT_ADDED, &secondary);
  secondary.width = 3840;
  screen_monitor_push_event(&state, screen_monitor_EVENT_METRICS_CHANGED, &secondary);
  memset(&secondary, 0, sizeof(secondary));
  /* No current primary display is available when the events are consumed. */
  state.display_count = 0;
  int32_t kind = -1;
  screen_monitor_display_t display = {0};
  int32_t valid =
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_REMOVED && display.id == 42 && display.width == 1280;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_ADDED && display.id == 43 && display.width == 2560;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK &&
      kind == screen_monitor_EVENT_METRICS_CHANGED && display.id == 43 && display.width == 3840;
  valid = valid &&
      screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_EMPTY;
  screen_monitor_release_events(&state);
  screen_monitor_lock_destroy(&state);
  return valid;
}

#if defined(__linux__)
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>

static screen_monitor_state_t *watch_state;
static int fail_display_open;
static int invalid_publication;
static int ready_notifications;

/* No X server or physical display changes are needed for the startup path. */
static Display *test_open_display(const char *name) {
  (void)name;
  return fail_display_open ? NULL : (Display *)watch_state;
}

static int test_close_display(Display *display) {
  (void)display;
  return 0;
}

static Bool test_query_extension(Display *display, int *event, int *error) {
  (void)display;
  *event = *error = 0;
  return False;
}

static int test_select_input(Display *display, Window window, long mask) {
  (void)display;
  (void)window;
  (void)mask;
  return 0;
}

static int test_display_noop(Display *display) {
  (void)display;
  return 0;
}

static XRRMonitorInfo *test_get_monitors(Display *display, Window window,
                                       Bool active, int *count) {
  (void)display;
  (void)window;
  (void)active;
  *count = 0;
  return NULL;
}

static int test_signal_ready(pthread_cond_t *condition) {
  if (condition == &watch_state->ready_cond) {
    ready_notifications++;
    if (!watch_state->ready ||
        watch_state->watch_started != !fail_display_open) {
      invalid_publication = 1;
      /* Let the broken implementation exit instead of hanging this test in
         its erroneous failure-path join. The invariant still fails below. */
      watch_state->watch_stop = 1;
    }
  }
  return pthread_cond_signal(condition);
}

/* Compile the production worker and startup/wait code, substituting only X11
   availability and an observation at the readiness notification. Rename the
   entry points so the imported package keeps its normal platform backend. */
#define screen_monitor_platform_init test_platform_init
#define screen_monitor_platform_enumerate test_platform_enumerate
#define screen_monitor_platform_query_cursor test_platform_query_cursor
#define screen_monitor_platform_nearest_display test_platform_nearest_display
#define screen_monitor_platform_start_watching test_start_watching
#define screen_monitor_platform_stop_watching test_stop_watching
#define XOpenDisplay test_open_display
#define XCloseDisplay test_close_display
#define XRRQueryExtension test_query_extension
#define XSelectInput test_select_input
#define XFlush test_display_noop
#define XPending test_display_noop
#define XRRGetMonitors test_get_monitors
#undef DefaultRootWindow
#define DefaultRootWindow(display) ((Window)1)
#define pthread_cond_signal test_signal_ready
#include "../../native_linux.c"
#undef pthread_cond_signal
#undef screen_monitor_platform_init
#undef screen_monitor_platform_enumerate
#undef screen_monitor_platform_query_cursor
#undef screen_monitor_platform_nearest_display
#undef screen_monitor_platform_start_watching
#undef screen_monitor_platform_stop_watching

int32_t proton_test_screen_watch_startup(void) {
  screen_monitor_state_t state = {0};
  screen_monitor_lock_init(&state);
  test_platform_init(&state);
  watch_state = &state;
  int result = 0;
  /* A failed start between successful starts also exercises stale readiness,
     diagnostics and reuse of the same synchronization objects. */
  for (int attempt = 0; attempt < 3; attempt++) {
    fail_display_open = attempt == 1;
    invalid_publication = 0;
    ready_notifications = 0;
    int expected = fail_display_open ? screen_monitor_STATUS_BACKEND_UNAVAILABLE
                                     : screen_monitor_STATUS_OK;
    int status = test_start_watching(&state);
    if (status != expected || invalid_publication || ready_notifications != 1 ||
        state.watch_started != !fail_display_open ||
        state.thread_started != !fail_display_open ||
        (fail_display_open
             ? strcmp(state.watch_error, "XOpenDisplay failed") != 0
             : state.watch_error[0] != '\0')) {
      result = __LINE__;
    }
    test_stop_watching(&state);
    if (state.thread_started || state.watch_started) result = __LINE__;
    if (result) break;
  }
  watch_state = NULL;
  screen_monitor_lock_destroy(&state);
  return result;
}
#endif

#if defined(_WIN32)
static screen_monitor_state_t *broadcast_state;
static HANDLE broadcast_event;
static volatile LONG broadcast_seen;

/* Run on the real watcher thread immediately before its production WndProc.
   Make the old snapshot differ without changing the machine's display mode.
   Neither the WndProc nor the event queue is invoked by the test directly. */
static LRESULT CALLBACK screen_broadcast_hook(int code, WPARAM wparam,
                                             LPARAM lparam) {
  if (code == HC_ACTION) {
    const CWPSTRUCT *message = (const CWPSTRUCT *)lparam;
    if (message->hwnd == broadcast_state->message_window &&
        message->message == WM_DISPLAYCHANGE &&
        InterlockedCompareExchange(&broadcast_seen, 1, 0) == 0 &&
        broadcast_state->display_count > 0) {
      broadcast_state->displays[0].width--;
    }
  }
  return CallNextHookEx(NULL, code, wparam, lparam);
}

static void screen_broadcast_wakeup(void) {
  if (InterlockedCompareExchange(&broadcast_seen, 0, 0)) {
    SetEvent(broadcast_event);
  }
}

int32_t proton_test_screen_watch_broadcast(void) {
  screen_monitor_state_t state = {0};
  int32_t result = 0;
  screen_monitor_lock_init(&state);
  screen_monitor_platform_init(&state);
  broadcast_state = &state;
  broadcast_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (broadcast_event == NULL) {
    screen_monitor_lock_destroy(&state);
    broadcast_state = NULL;
    return __LINE__;
  }
  screen_monitor_set_event_wakeup(&state, screen_broadcast_wakeup);
  for (int attempt = 0; attempt < 2; attempt++) {
    HHOOK hook = NULL;
    HWND hwnd = NULL;
    InterlockedExchange(&broadcast_seen, 0);
    ResetEvent(broadcast_event);
    if (screen_monitor_platform_start_watching(&state) != screen_monitor_STATUS_OK) {
      result = __LINE__;
      goto stop;
    }
    hwnd = state.message_window;
    if (hwnd == NULL || IsWindowVisible(hwnd)) {
      result = __LINE__;
      goto stop;
    }
    hook = SetWindowsHookExW(WH_CALLWNDPROC, screen_broadcast_hook, NULL,
                            state.watch_thread_id);
    if (hook == NULL) {
      result = __LINE__;
      goto stop;
    }
    /* Broadcast through Windows, including invisible top-level windows.
       Keep the actual display dimensions; no resolution change is performed. */
    if (!SendNotifyMessageW(HWND_BROADCAST, WM_DISPLAYCHANGE, 32,
                            MAKELPARAM(GetSystemMetrics(SM_CXSCREEN),
                                       GetSystemMetrics(SM_CYSCREEN))) ||
        WaitForSingleObject(broadcast_event, 5000) != WAIT_OBJECT_0) {
      result = __LINE__;
      goto stop;
    }
    {
      int32_t kind;
      screen_monitor_display_t display;
      int found = 0;
      while (screen_monitor_take_event(&state, &kind, &display) == screen_monitor_STATUS_OK) {
        if (kind == screen_monitor_EVENT_METRICS_CHANGED && display.width > 0) {
          found = 1;
        }
      }
      if (!InterlockedCompareExchange(&broadcast_seen, 0, 0) || !found) {
        result = __LINE__;
      }
    }
  stop:
    if (hook != NULL) UnhookWindowsHookEx(hook);
    screen_monitor_platform_stop_watching(&state);
    if (hwnd != NULL && IsWindow(hwnd)) result = __LINE__;
    if (state.message_window != NULL || state.device_handle != NULL ||
        state.watch_thread != NULL || state.ready_event != NULL || state.watch_started) {
      result = __LINE__;
    }
    screen_monitor_release_events(&state);
    if (result) break;
  }
  broadcast_state = NULL;
  CloseHandle(broadcast_event);
  broadcast_event = NULL;
  screen_monitor_lock_destroy(&state);
  return result;
}
#endif
