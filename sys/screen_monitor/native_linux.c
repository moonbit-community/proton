#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* The Linux backend uses the X11 core protocol plus the RandR extension,
   resolved through dlopen so the module never hard-links against an X server
   it may not need. RandR's per-monitor API (`XRRGetMonitors`) reports one entry
   per logical monitor, which maps directly onto Electron's `Display`. All
   coordinates are already physical pixels in the X11 root coordinate space,
   matching the facade's top-left origin. */

typedef int proton_bool;
typedef unsigned long proton_atom;
typedef unsigned long proton_window;
typedef unsigned long proton_drawable;
typedef unsigned long proton_visual_id;
typedef int proton_screen_number;

struct proton_x_display_info {
  int screen;
  int depth;
  int width;
  int height;
  int mm_width;
  int mm_height;
};

typedef struct {
  proton_atom name;
  proton_bool primary;
  proton_bool automatic;
  int noutput;
  int x;
  int y;
  int width;
  int height;
  int mwidth;
  int mheight;
  void *outputs; /* RROutput*; never dereferenced */
} proton_rr_monitor_info;

typedef struct proton_x_error_event {
  int type;
  int serial;
  int error_code;
  int request_code;
  int minor_code;
  int resourceid;
} proton_x_error_event;

typedef struct proton_x_configure_event {
  int type;
  unsigned long serial;
  int send_event;
  void *display;
  proton_window event;
  proton_window window;
  int x;
  int y;
  int width;
  int height;
  int border_width;
  void *above;
  int override_redirect;
} proton_x_configure_event;

typedef struct proton_x_gen_event {
  int type;
  unsigned long serial;
  int send_event;
  void *display;
} proton_x_gen_event;

typedef struct proton_x_event {
  int type;
  char pad[120];
} proton_x_event;

enum {
  PROTON_X_CONFIGURE_NOTIFY = 22,
  PROTON_RR_SCREEN_CHANGE_NOTIFY = 1,
  PROTON_STRUCTURE_NOTIFY_MASK = (1L << 17),
  PROTON_RR_SCREEN_CHANGE_NOTIFY_MASK = (1L << 0),
};

typedef struct {
  void *(*open_display)(const char *);
  int (*close_display)(void *);
  int (*default_screen)(void *);
  void *(*default_root_window)(void *);
  proton_atom (*intern_atom)(void *, const char *, int);
  int (*select_input)(void *, proton_window, long);
  int (*query_pointer)(void *, proton_window, proton_window *, proton_window *,
                       int *, int *, int *, int *, unsigned int *);
  int (*pending)(void *);
  int (*next_event)(void *, proton_x_event *);
  int (*flush)(void *);
  int loaded;
  int ready;
} proton_xlib_t;

typedef struct {
  int (*rr_select_input)(void *, proton_window, int);
  void *(*rr_get_monitors)(void *, proton_window, int, int *);
  void (*rr_free_monitors)(proton_rr_monitor_info *);
  int loaded;
  int ready;
} proton_xrandr_t;

static proton_xlib_t g_xlib;
static proton_xrandr_t g_xrandr;

static int screen_monitor_ensure_loaded(void) {
  if (g_xlib.loaded) {
    return g_xlib.ready && g_xrandr.ready;
  }
  g_xlib.loaded = 1;
  void *x11 = dlopen("libX11.so.6", RTLD_LAZY | RTLD_LOCAL);
  if (x11 != NULL) {
    g_xlib.open_display = (void *(*)(const char *))dlsym(x11, "XOpenDisplay");
    g_xlib.close_display = (int (*)(void *))dlsym(x11, "XCloseDisplay");
    g_xlib.default_screen = (int (*)(void *))dlsym(x11, "XDefaultScreen");
    g_xlib.default_root_window =
        (void *(*)(void *))dlsym(x11, "XDefaultRootWindow");
    g_xlib.intern_atom =
        (proton_atom(*)(void *, const char *, int))dlsym(x11, "XInternAtom");
    g_xlib.select_input =
        (int (*)(void *, proton_window, long))dlsym(x11, "XSelectInput");
    g_xlib.query_pointer =
        (int (*)(void *, proton_window, proton_window *, proton_window *,
                 int *, int *, int *, int *, unsigned int *))dlsym(x11,
                                                                   "XQueryPointer");
    g_xlib.pending = (int (*)(void *))dlsym(x11, "XPending");
    g_xlib.next_event = (int (*)(void *, proton_x_event *))dlsym(x11,
                                                                 "XNextEvent");
    g_xlib.flush = (int (*)(void *))dlsym(x11, "XFlush");
  }
  g_xlib.ready = g_xlib.open_display != NULL && g_xlib.close_display != NULL &&
                 g_xlib.default_root_window != NULL &&
                 g_xlib.select_input != NULL && g_xlib.query_pointer != NULL &&
                 g_xlib.pending != NULL && g_xlib.next_event != NULL;

  void *xrandr = dlopen("libXrandr.so.2", RTLD_LAZY | RTLD_LOCAL);
  if (xrandr != NULL) {
    g_xrandr.rr_select_input = (int (*)(void *, proton_window, int))dlsym(
        xrandr, "XRRSelectInput");
    g_xrandr.rr_get_monitors = (void *(*)(void *, proton_window, int, int *))dlsym(
        xrandr, "XRRGetMonitors");
    g_xrandr.rr_free_monitors =
        (void (*)(proton_rr_monitor_info *))dlsym(xrandr, "XRRFreeMonitors");
  }
  g_xrandr.ready = g_xrandr.rr_select_input != NULL &&
                   g_xrandr.rr_get_monitors != NULL &&
                   g_xrandr.rr_free_monitors != NULL;
  return g_xlib.ready && g_xrandr.ready;
}

static void screen_monitor_set_watch_error(screen_monitor_state_t *state,
                                           const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

void screen_monitor_platform_init(screen_monitor_state_t *state) {
  (void)state;
  screen_monitor_ensure_loaded();
}

int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state) {
  state->display_count = 0;
  if (!screen_monitor_ensure_loaded()) {
    return -screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  void *dpy = g_xlib.open_display(NULL);
  if (dpy == NULL) {
    return -screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  proton_window root = g_xlib.default_root_window(dpy);
  int nmonitors = 0;
  proton_rr_monitor_info *monitors =
      (proton_rr_monitor_info *)g_xrandr.rr_get_monitors(dpy, root, 1,
                                                         &nmonitors);
  if (monitors == NULL || nmonitors <= 0) {
    g_xlib.close_display(dpy);
    return state->display_count;
  }
  int n = nmonitors;
  if (n > SCREEN_MONITOR_MAX_DISPLAYS) {
    n = SCREEN_MONITOR_MAX_DISPLAYS;
  }
  int first_primary = -1;
  for (int32_t i = 0; i < n; i++) {
    const proton_rr_monitor_info *m = &monitors[i];
    screen_monitor_display_t *d = &state->displays[i];
    memset(d, 0, sizeof(*d));
    d->x = m->x;
    d->y = m->y;
    d->width = m->width;
    d->height = m->height;
    d->work_x = m->x;
    d->work_y = m->y;
    d->work_width = m->width;
    d->work_height = m->height;
    if (m->mwidth > 0 && m->width > 0) {
      /* Pixels per inch from the monitor's physical size, normalized to 96 DPI
         so a 96 DPI monitor reports 100%. */
      double dpi = (double)m->width * 25.4 / (double)m->mwidth;
      int32_t percent = (int32_t)((dpi / 96.0) * 100.0 + 0.5);
      d->scale_factor_percent = percent > 0 ? percent : 100;
    } else {
      d->scale_factor_percent = 100;
    }
    d->is_primary = m->primary ? 1 : 0;
    if (d->is_primary && first_primary < 0) {
      first_primary = (int32_t)i;
    }
    /* Bounds digest gives a stable-enough identity for hot-plug diffing. */
    d->id = m->x * 1000000 + m->y;
    d->present = 1;
  }
  if (first_primary >= 0 && first_primary != 0) {
    screen_monitor_display_t tmp = state->displays[0];
    state->displays[0] = state->displays[first_primary];
    state->displays[first_primary] = tmp;
  }
  state->display_count = n;
  g_xrandr.rr_free_monitors(monitors);
  g_xlib.close_display(dpy);
  return state->display_count;
}

int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y) {
  if (!screen_monitor_ensure_loaded()) {
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  void *dpy = g_xlib.open_display(NULL);
  if (dpy == NULL) {
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  proton_window root = g_xlib.default_root_window(dpy);
  proton_window root_ret;
  proton_window child_ret;
  int root_x = 0;
  int root_y = 0;
  int win_x = 0;
  int win_y = 0;
  unsigned int mask = 0;
  int ok = g_xlib.query_pointer(dpy, root, &root_ret, &child_ret, &root_x,
                                &root_y, &win_x, &win_y, &mask);
  g_xlib.close_display(dpy);
  (void)state;
  if (!ok) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  if (out_x != NULL) {
    *out_x = root_x;
  }
  if (out_y != NULL) {
    *out_y = root_y;
  }
  return screen_monitor_STATUS_OK;
}

static int64_t screen_monitor_distance_sq(int32_t rx, int32_t ry, int32_t x,
                                          int32_t y) {
  int64_t dx = (int64_t)rx - (int64_t)x;
  int64_t dy = (int64_t)ry - (int64_t)y;
  return dx * dx + dy * dy;
}

int32_t screen_monitor_platform_nearest_display(screen_monitor_state_t *state,
                                                int32_t x, int32_t y) {
  for (int32_t i = 0; i < state->display_count; i++) {
    const screen_monitor_display_t *d = &state->displays[i];
    if (x >= d->x && x < d->x + d->width && y >= d->y && y < d->y + d->height) {
      return i;
    }
  }
  int32_t best = -1;
  int64_t best_dist = INT64_MAX;
  for (int32_t i = 0; i < state->display_count; i++) {
    const screen_monitor_display_t *d = &state->displays[i];
    int32_t cx = d->x + d->width / 2;
    int32_t cy = d->y + d->height / 2;
    int64_t dist = screen_monitor_distance_sq(cx, cy, x, y);
    if (dist < best_dist) {
      best_dist = dist;
      best = i;
    }
  }
  return best;
}

/* --- Event watch backend ------------------------------------------------- */

static void *g_linux_display = NULL; /* owned by the watch thread */
static screen_monitor_state_t *g_linux_state = NULL;

static void screen_monitor_linux_handle_change(screen_monitor_state_t *state) {
  screen_monitor_display_t previous[SCREEN_MONITOR_MAX_DISPLAYS];
  int32_t previous_count = state->display_count;
  memcpy(previous, state->displays, sizeof(previous));
  memset(state->displays, 0, sizeof(state->displays));
  int32_t count = screen_monitor_platform_enumerate(state);
  if (count < 0) {
    memcpy(state->displays, previous, sizeof(previous));
    state->display_count = previous_count;
    return;
  }
  int32_t geometry_changed = 0;
  for (int32_t i = 0; i < state->display_count; i++) {
    screen_monitor_display_t *cur = &state->displays[i];
    int32_t found = 0;
    for (int32_t j = 0; j < previous_count; j++) {
      if (previous[j].present && previous[j].id == cur->id) {
        found = 1;
        if (previous[j].x != cur->x || previous[j].y != cur->y ||
            previous[j].width != cur->width ||
            previous[j].height != cur->height ||
            previous[j].work_x != cur->work_x ||
            previous[j].work_y != cur->work_y ||
            previous[j].work_width != cur->work_width ||
            previous[j].work_height != cur->work_height ||
            previous[j].scale_factor_percent != cur->scale_factor_percent) {
          geometry_changed = 1;
        }
        break;
      }
    }
    if (!found) {
      screen_monitor_push_event(state, screen_monitor_EVENT_ADDED);
    }
  }
  for (int32_t j = 0; j < previous_count; j++) {
    if (!previous[j].present) {
      continue;
    }
    int32_t found = 0;
    for (int32_t i = 0; i < state->display_count; i++) {
      if (state->displays[i].id == previous[j].id) {
        found = 1;
        break;
      }
    }
    if (!found) {
      screen_monitor_push_event(state, screen_monitor_EVENT_REMOVED);
    }
  }
  if (geometry_changed) {
    screen_monitor_push_event(state, screen_monitor_EVENT_METRICS_CHANGED);
  }
}

static void *screen_monitor_linux_watch_thread(void *param) {
  screen_monitor_state_t *state = (screen_monitor_state_t *)param;
  void *dpy = g_xlib.open_display(NULL);
  g_linux_display = dpy;
  if (dpy == NULL) {
    screen_monitor_set_watch_error(state, "XOpenDisplay failed");
    pthread_mutex_lock(&state->event_lock);
    state->ready = 1;
    pthread_cond_signal(&state->ready_cond);
    pthread_mutex_unlock(&state->event_lock);
    state->watch_started = 0;
    g_linux_state = NULL;
    return NULL;
  }
  proton_window root = g_xlib.default_root_window(dpy);
  /* RandR screen-change plus core structure changes both fire on hot-plug. */
  g_xrandr.rr_select_input(dpy, root, PROTON_RR_SCREEN_CHANGE_NOTIFY_MASK);
  g_xlib.select_input(dpy, root, PROTON_STRUCTURE_NOTIFY_MASK);
  g_xlib.flush(dpy);
  /* Seed the snapshot so only real topology changes fire afterwards. */
  screen_monitor_platform_enumerate(state);

  pthread_mutex_lock(&state->event_lock);
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);
  state->watch_started = 1;

  proton_x_event ev;
  while (!state->watch_stop) {
    while (g_xlib.pending(dpy) > 0) {
      g_xlib.next_event(dpy, &ev);
      if (ev.type == PROTON_X_CONFIGURE_NOTIFY ||
          ev.type == PROTON_RR_SCREEN_CHANGE_NOTIFY) {
        screen_monitor_linux_handle_change(state);
      }
    }
    usleep(50000);
  }

  g_xlib.close_display(dpy);
  g_linux_display = NULL;
  g_linux_state = NULL;
  state->watch_started = 0;
  return NULL;
}

int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state) {
  if (state->thread_started) {
    return screen_monitor_STATUS_OK;
  }
  if (!screen_monitor_ensure_loaded()) {
    screen_monitor_set_watch_error(state,
                                   "X11/RandR unavailable (no X display backend)");
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  /* Allow the mutation of `watch_stop` to be observed from the watch thread. */
  g_linux_state = state;
  pthread_mutex_lock(&state->event_lock);
  state->ready = 0;
  pthread_mutex_unlock(&state->event_lock);
  state->watch_stop = 0;
  state->thread_started = 1;
  if (pthread_create(&state->watch_thread, NULL,
                     screen_monitor_linux_watch_thread, state) != 0) {
    state->thread_started = 0;
    state->watch_stop = 0;
    screen_monitor_set_watch_error(state, "pthread_create failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  /* Wait for the backend thread to open a display and seed its snapshot. */
  pthread_mutex_lock(&state->event_lock);
  while (!state->ready) {
    pthread_cond_wait(&state->ready_cond, &state->event_lock);
  }
  pthread_mutex_unlock(&state->event_lock);
  if (!state->watch_started) {
    pthread_join(state->watch_thread, NULL);
    state->thread_started = 0;
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  return screen_monitor_STATUS_OK;
}

int32_t screen_monitor_platform_stop_watching(screen_monitor_state_t *state) {
  if (!state->thread_started) {
    return screen_monitor_STATUS_OK;
  }
  state->watch_stop = 1;
  pthread_join(state->watch_thread, NULL);
  state->thread_started = 0;
  state->watch_stop = 0;
  return screen_monitor_STATUS_OK;
}

#endif
