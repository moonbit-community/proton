#include "native_stub.h"

#ifdef __APPLE__
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* CGDisplayCreateImage is unavailable in newer SDKs. Keep this optional legacy
   thumbnail path isolated until it is replaced with ScreenCaptureKit. */
static CGImageRef (*screen_monitor_capture_display)(CGDirectDisplayID);
static pthread_once_t screen_monitor_capture_once = PTHREAD_ONCE_INIT;

static void screen_monitor_load_capture(void) {
  screen_monitor_capture_display = (CGImageRef (*)(CGDirectDisplayID))
      dlsym(RTLD_DEFAULT, "CGDisplayCreateImage");
}

static void screen_monitor_set_watch_error(screen_monitor_state_t *state,
                                           const char *message) {
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

static const char screen_monitor_base64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_display_thumbnail(int32_t display_id,
                                                         int32_t width,
                                                         int32_t height) {
  pthread_once(&screen_monitor_capture_once, screen_monitor_load_capture);
  if (width <= 0 || height <= 0 || screen_monitor_capture_display == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t pixel_size = (size_t)width * (size_t)height * 4;
  if (pixel_size / 4 != (size_t)width * (size_t)height) {
    return moonbit_make_bytes(0, 0);
  }
  unsigned char *pixels = (unsigned char *)calloc(1, pixel_size);
  CGImageRef image =
      screen_monitor_capture_display((CGDirectDisplayID)display_id);
  CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = NULL;
  if (pixels != NULL && image != NULL && color_space != NULL) {
    context = CGBitmapContextCreate(pixels, (size_t)width,
                                          (size_t)height, 8,
                                          (size_t)width * 4, color_space,
                                          1u | 0x4000u);
  }
  if (context == NULL) {
    if (image != NULL) CFRelease(image);
    if (color_space != NULL) CFRelease(color_space);
    free(pixels);
    return moonbit_make_bytes(0, 0);
  }
  CGRect bounds = CGRectMake(0, 0, width, height);
  CGContextDrawImage(context, bounds, image);
  for (size_t i = 0; i < pixel_size; i += 4) {
    unsigned char red = pixels[i];
    pixels[i] = pixels[i + 2];
    pixels[i + 2] = red;
  }
  size_t raw_size = 54 + pixel_size;
  size_t encoded_size = ((raw_size + 2) / 3) * 4;
  unsigned char *raw = (unsigned char *)calloc(1, raw_size);
  moonbit_bytes_t result = moonbit_make_bytes(0, 0);
  if (raw != NULL && raw_size <= UINT32_MAX) {
    uint32_t file_size = (uint32_t)raw_size;
    uint32_t offset = 54;
    uint32_t header_size = 40;
    int32_t bitmap_height = -height;
    uint16_t planes = 1;
    uint16_t bits = 32;
    uint32_t image_size = (uint32_t)pixel_size;
    raw[0] = 'B'; raw[1] = 'M';
    memcpy(raw + 2, &file_size, 4); memcpy(raw + 10, &offset, 4);
    memcpy(raw + 14, &header_size, 4); memcpy(raw + 18, &width, 4);
    memcpy(raw + 22, &bitmap_height, 4); memcpy(raw + 26, &planes, 2);
    memcpy(raw + 28, &bits, 2); memcpy(raw + 34, &image_size, 4);
    memcpy(raw + 54, pixels, pixel_size);
    result = moonbit_make_bytes((int32_t)(22 + encoded_size), 0);
    memcpy(result, "data:image/bmp;base64,", 22);
    size_t out = 22;
    for (size_t i = 0; i < raw_size; i += 3) {
      uint32_t value = (uint32_t)raw[i] << 16;
      if (i + 1 < raw_size) value |= (uint32_t)raw[i + 1] << 8;
      if (i + 2 < raw_size) value |= raw[i + 2];
      result[out++] = screen_monitor_base64_table[(value >> 18) & 63];
      result[out++] = screen_monitor_base64_table[(value >> 12) & 63];
      result[out++] = i + 1 < raw_size
                          ? screen_monitor_base64_table[(value >> 6) & 63]
                          : '=';
      result[out++] = i + 2 < raw_size
                          ? screen_monitor_base64_table[value & 63]
                          : '=';
    }
  }
  free(raw);
  CFRelease(context);
  CFRelease(color_space);
  CFRelease(image);
  free(pixels);
  return result;
}

void screen_monitor_platform_init(screen_monitor_state_t *state) {
  (void)state;
}

int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state) {
  state->display_count = 0;
  CGDirectDisplayID ids[SCREEN_MONITOR_MAX_DISPLAYS];
  uint32_t count = 0;
  CGError err =
      CGGetActiveDisplayList(SCREEN_MONITOR_MAX_DISPLAYS, ids, &count);
  if (err != 0) {
    return -screen_monitor_STATUS_OPERATION_FAILED;
  }
  int32_t n = (int32_t)count;
  if (n > SCREEN_MONITOR_MAX_DISPLAYS) {
    n = SCREEN_MONITOR_MAX_DISPLAYS;
  }
  for (int32_t i = 0; i < n; i++) {
    CGRect b = CGDisplayBounds(ids[i]);
    screen_monitor_display_t *d = &state->displays[state->display_count];
    memset(d, 0, sizeof(*d));
    d->x = (int32_t)b.origin.x;
    d->y = (int32_t)b.origin.y;
    d->width = (int32_t)b.size.width;
    d->height = (int32_t)b.size.height;
    /* CoreGraphics uses top-left origin with y increasing downward, matching
       the facade; no flip is needed. Work area is approximated by the frame. */
    d->work_x = d->x;
    d->work_y = d->y;
    d->work_width = d->width;
    d->work_height = d->height;
    size_t px_wide = CGDisplayPixelsWide(ids[i]);
    if (px_wide > 0 && d->width > 0) {
      d->scale_factor_percent =
          (int32_t)((px_wide * 100) / (size_t)d->width);
    } else {
      d->scale_factor_percent = 100;
    }
    d->is_primary = CGDisplayIsMain(ids[i]) ? 1 : 0;
    d->id = (int32_t)ids[i];
    d->present = 1;
    state->display_count++;
  }
  return state->display_count;
}

int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y) {
  (void)state;
  CGEventRef event = CGEventCreate(NULL);
  if (event == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  CGPoint location = CGEventGetLocation(event);
  CFRelease(event);
  if (out_x != NULL) {
    *out_x = (int32_t)location.x;
  }
  if (out_y != NULL) {
    *out_y = (int32_t)location.y;
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

/* Called by CoreGraphics on its own thread whenever a display is added, removed,
   or reconfigured. Re-enumerates and diffs against the previous snapshot. */
static void screen_monitor_reconfiguration_callback(
    CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *info) {
  (void)display;
  if (flags & kCGDisplayBeginConfigurationFlag) {
    return;
  }
  screen_monitor_state_t *state = (screen_monitor_state_t *)info;
  if (state == NULL) {
    return;
  }
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
            previous[j].scale_factor_percent != cur->scale_factor_percent ||
            previous[j].is_primary != cur->is_primary) {
          screen_monitor_push_event(
              state, screen_monitor_EVENT_METRICS_CHANGED, cur);
        }
        break;
      }
    }
    if (!found) {
      screen_monitor_push_event(state, screen_monitor_EVENT_ADDED, cur);
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
      screen_monitor_push_event(
          state, screen_monitor_EVENT_REMOVED, &previous[j]);
    }
  }
}

int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state) {
  if (state->watch_started) {
    return screen_monitor_STATUS_OK;
  }
  if (screen_monitor_platform_enumerate(state) < 0) {
    screen_monitor_set_watch_error(state, "display enumeration failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  CGError err = CGDisplayRegisterReconfigurationCallback(
      screen_monitor_reconfiguration_callback, state);
  if (err != 0) {
    screen_monitor_set_watch_error(state, "reconfiguration registration failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  state->watch_started = 1;
  return screen_monitor_STATUS_OK;
}

int32_t screen_monitor_platform_stop_watching(screen_monitor_state_t *state) {
  if (state->watch_started) {
    CGDisplayRemoveReconfigurationCallback(
        screen_monitor_reconfiguration_callback, state);
    state->watch_started = 0;
  }
  return screen_monitor_STATUS_OK;
}

#endif
