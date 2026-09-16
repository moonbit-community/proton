#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)

#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* RandR reports logical monitors in physical pixels in the X11 root
   coordinate space, matching the facade's top-left origin. */

static void screen_monitor_set_watch_error(screen_monitor_state_t *state,
                                           const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

void screen_monitor_platform_init(screen_monitor_state_t *state) {
  (void)state;
}

int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state) {
  state->display_count = 0;
  Display *dpy = XOpenDisplay(NULL);
  if (dpy == NULL) {
    return -screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  Window root = DefaultRootWindow(dpy);
  int nmonitors = 0;
  XRRMonitorInfo *monitors =
      XRRGetMonitors(dpy, root, True, &nmonitors);
  if (monitors == NULL || nmonitors <= 0) {
    XCloseDisplay(dpy);
    return state->display_count;
  }
  int n = nmonitors;
  if (n > SCREEN_MONITOR_MAX_DISPLAYS) {
    n = SCREEN_MONITOR_MAX_DISPLAYS;
  }
  int first_primary = -1;
  for (int32_t i = 0; i < n; i++) {
    const XRRMonitorInfo *m = &monitors[i];
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
  XRRFreeMonitors(monitors);
  XCloseDisplay(dpy);
  return state->display_count;
}

int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y) {
  Display *dpy = XOpenDisplay(NULL);
  if (dpy == NULL) {
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  Window root = DefaultRootWindow(dpy);
  Window root_ret;
  Window child_ret;
  int root_x = 0;
  int root_y = 0;
  int win_x = 0;
  int win_y = 0;
  unsigned int mask = 0;
  int ok = XQueryPointer(dpy, root, &root_ret, &child_ret, &root_x,
                         &root_y, &win_x, &win_y, &mask);
  XCloseDisplay(dpy);
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

static Display *g_linux_display = NULL; /* owned by the watch thread */
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
  Display *dpy = XOpenDisplay(NULL);
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
  int randr_event_base = 0;
  int randr_error_base = 0;
  int has_randr = XRRQueryExtension(dpy, &randr_event_base, &randr_error_base);
  Window root = DefaultRootWindow(dpy);
  /* RandR screen-change plus core structure changes both fire on hot-plug. */
  if (has_randr) {
    XRRSelectInput(dpy, root, RRScreenChangeNotifyMask);
  }
  XSelectInput(dpy, root, StructureNotifyMask);
  XFlush(dpy);
  /* Seed the snapshot so only real topology changes fire afterwards. */
  screen_monitor_platform_enumerate(state);

  pthread_mutex_lock(&state->event_lock);
  state->ready = 1;
  pthread_cond_signal(&state->ready_cond);
  pthread_mutex_unlock(&state->event_lock);
  state->watch_started = 1;

  XEvent ev;
  while (!state->watch_stop) {
    while (XPending(dpy) > 0) {
      XNextEvent(dpy, &ev);
      if (ev.type == ConfigureNotify ||
          (has_randr && ev.type == randr_event_base + RRScreenChangeNotify)) {
        screen_monitor_linux_handle_change(state);
      }
    }
    usleep(50000);
  }

  XCloseDisplay(dpy);
  g_linux_display = NULL;
  g_linux_state = NULL;
  state->watch_started = 0;
  return NULL;
}

int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state) {
  if (state->thread_started) {
    return screen_monitor_STATUS_OK;
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
