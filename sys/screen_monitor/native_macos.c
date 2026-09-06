#include "native_stub.h"

#ifdef __APPLE__
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Screen enumeration, cursor location, and hot-plug reconfiguration arrive
   through CoreGraphics, which exposes a plain C API and can be dlopen'd like
   the other optional system frameworks the backend touches. All coordinates
   are logical points; the scale factor converts to physical pixels. */

typedef const void *proton_cf_type_ref;
typedef uint32_t proton_cg_direct_display_id;
typedef uint32_t proton_cg_display_count;
typedef int32_t proton_cg_error;
typedef double proton_cg_float;

typedef struct {
  proton_cg_float x;
  proton_cg_float y;
  proton_cg_float width;
  proton_cg_float height;
} proton_cg_rect;

typedef struct {
  proton_cg_float x;
  proton_cg_float y;
} proton_cg_point_t;

typedef proton_cg_error (*proton_cg_get_active_display_list_fn)(
    proton_cg_display_count, proton_cg_direct_display_id *,
    proton_cg_display_count *);
typedef proton_cg_rect (*proton_cg_display_bounds_fn)(
    proton_cg_direct_display_id);
typedef int32_t (*proton_cg_display_is_main_fn)(proton_cg_direct_display_id);
typedef size_t (*proton_cg_display_pixels_wide_fn)(
    proton_cg_direct_display_id);
typedef size_t (*proton_cg_display_pixels_high_fn)(
    proton_cg_direct_display_id);
typedef void (*proton_cg_display_reconfiguration_callback_fn)(
    proton_cg_direct_display_id, proton_cg_error, void *);
typedef proton_cg_error (*proton_cg_display_register_reconfiguration_fn)(
    proton_cg_display_reconfiguration_callback_fn, void *);
typedef proton_cg_error (*proton_cg_display_remove_reconfiguration_fn)(
    proton_cg_display_reconfiguration_callback_fn, void *);
typedef proton_cf_type_ref (*proton_cg_event_create_fn)(uint32_t);
typedef proton_cg_point_t (*proton_cg_event_get_location_fn)(proton_cf_type_ref);
typedef void (*proton_cf_release_fn)(proton_cf_type_ref);
typedef proton_cf_type_ref (*proton_cg_display_create_image_fn)(
    proton_cg_direct_display_id);
typedef proton_cf_type_ref (*proton_cg_color_space_create_device_rgb_fn)(void);
typedef proton_cf_type_ref (*proton_cg_bitmap_context_create_fn)(
    void *, size_t, size_t, size_t, size_t, proton_cf_type_ref, uint32_t);
typedef void (*proton_cg_context_draw_image_fn)(proton_cf_type_ref,
                                                proton_cg_rect,
                                                proton_cf_type_ref);

static struct {
  proton_cg_get_active_display_list_fn get_active_display_list;
  proton_cg_display_bounds_fn display_bounds;
  proton_cg_display_is_main_fn display_is_main;
  proton_cg_display_pixels_wide_fn pixels_wide;
  proton_cg_display_pixels_high_fn pixels_high;
  proton_cg_display_register_reconfiguration_fn register_reconfiguration;
  proton_cg_display_remove_reconfiguration_fn remove_reconfiguration;
  proton_cg_event_create_fn event_create;
  proton_cg_event_get_location_fn event_get_location;
  proton_cf_release_fn release;
  proton_cg_display_create_image_fn display_create_image;
  proton_cg_color_space_create_device_rgb_fn color_space_create_device_rgb;
  proton_cg_bitmap_context_create_fn bitmap_context_create;
  proton_cg_context_draw_image_fn context_draw_image;
  int32_t loaded;
  int32_t ready;
} g_mac;

static void screen_monitor_set_watch_error(screen_monitor_state_t *state,
                                           const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

static int32_t screen_monitor_load_mac_symbols(void) {
  if (g_mac.loaded) {
    return g_mac.ready;
  }
  g_mac.loaded = 1;
  void *core_graphics =
      dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
             RTLD_LAZY | RTLD_LOCAL);
  void *core_foundation =
      dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
             RTLD_LAZY | RTLD_LOCAL);
  if (core_graphics == NULL || core_foundation == NULL) {
    if (core_graphics != NULL) {
      dlclose(core_graphics);
    }
    if (core_foundation != NULL) {
      dlclose(core_foundation);
    }
    return 0;
  }
  g_mac.get_active_display_list =
      (proton_cg_get_active_display_list_fn)dlsym(core_graphics,
                                                  "CGGetActiveDisplayList");
  g_mac.display_bounds =
      (proton_cg_display_bounds_fn)dlsym(core_graphics, "CGDisplayBounds");
  g_mac.display_is_main =
      (proton_cg_display_is_main_fn)dlsym(core_graphics, "CGDisplayIsMain");
  g_mac.pixels_wide =
      (proton_cg_display_pixels_wide_fn)dlsym(core_graphics,
                                              "CGDisplayPixelsWide");
  g_mac.pixels_high =
      (proton_cg_display_pixels_high_fn)dlsym(core_graphics,
                                              "CGDisplayPixelsHigh");
  g_mac.register_reconfiguration =
      (proton_cg_display_register_reconfiguration_fn)dlsym(
          core_graphics, "CGDisplayRegisterReconfigurationCallback");
  g_mac.remove_reconfiguration =
      (proton_cg_display_remove_reconfiguration_fn)dlsym(
          core_graphics, "CGDisplayRemoveReconfigurationCallback");
  g_mac.event_create = (proton_cg_event_create_fn)dlsym(core_graphics,
                                                        "CGEventCreate");
  g_mac.event_get_location =
      (proton_cg_event_get_location_fn)dlsym(core_graphics,
                                             "CGEventGetLocation");
  g_mac.release = (proton_cf_release_fn)dlsym(core_foundation, "CFRelease");
  g_mac.display_create_image = (proton_cg_display_create_image_fn)dlsym(
      core_graphics, "CGDisplayCreateImage");
  g_mac.color_space_create_device_rgb =
      (proton_cg_color_space_create_device_rgb_fn)dlsym(
          core_graphics, "CGColorSpaceCreateDeviceRGB");
  g_mac.bitmap_context_create =
      (proton_cg_bitmap_context_create_fn)dlsym(core_graphics,
                                                "CGBitmapContextCreate");
  g_mac.context_draw_image = (proton_cg_context_draw_image_fn)dlsym(
      core_graphics, "CGContextDrawImage");
  g_mac.ready = g_mac.get_active_display_list != NULL &&
                g_mac.display_bounds != NULL &&
                g_mac.display_is_main != NULL && g_mac.pixels_wide != NULL &&
                g_mac.pixels_high != NULL &&
                g_mac.register_reconfiguration != NULL &&
                g_mac.remove_reconfiguration != NULL &&
                g_mac.event_create != NULL && g_mac.event_get_location != NULL &&
                g_mac.release != NULL;
  return g_mac.ready;
}

static const char screen_monitor_base64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_display_thumbnail(int32_t display_id,
                                                         int32_t width,
                                                         int32_t height) {
  if (width <= 0 || height <= 0 || !screen_monitor_load_mac_symbols() ||
      g_mac.display_create_image == NULL ||
      g_mac.color_space_create_device_rgb == NULL ||
      g_mac.bitmap_context_create == NULL || g_mac.context_draw_image == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t pixel_size = (size_t)width * (size_t)height * 4;
  if (pixel_size / 4 != (size_t)width * (size_t)height) {
    return moonbit_make_bytes(0, 0);
  }
  unsigned char *pixels = (unsigned char *)calloc(1, pixel_size);
  proton_cf_type_ref image =
      g_mac.display_create_image((proton_cg_direct_display_id)display_id);
  proton_cf_type_ref color_space = g_mac.color_space_create_device_rgb();
  proton_cf_type_ref context = NULL;
  if (pixels != NULL && image != NULL && color_space != NULL) {
    context = g_mac.bitmap_context_create(pixels, (size_t)width,
                                          (size_t)height, 8,
                                          (size_t)width * 4, color_space,
                                          1u | 0x4000u);
  }
  if (context == NULL) {
    if (image != NULL) g_mac.release(image);
    if (color_space != NULL) g_mac.release(color_space);
    free(pixels);
    return moonbit_make_bytes(0, 0);
  }
  proton_cg_rect bounds = {0, 0, (proton_cg_float)width,
                           (proton_cg_float)height};
  g_mac.context_draw_image(context, bounds, image);
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
  g_mac.release(context);
  g_mac.release(color_space);
  g_mac.release(image);
  free(pixels);
  return result;
}

void screen_monitor_platform_init(screen_monitor_state_t *state) {
  (void)state;
  screen_monitor_load_mac_symbols();
}

int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state) {
  state->display_count = 0;
  if (!screen_monitor_load_mac_symbols()) {
    return -screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  proton_cg_direct_display_id ids[SCREEN_MONITOR_MAX_DISPLAYS];
  proton_cg_display_count count = 0;
  proton_cg_error err =
      g_mac.get_active_display_list(SCREEN_MONITOR_MAX_DISPLAYS, ids, &count);
  if (err != 0) {
    return -screen_monitor_STATUS_OPERATION_FAILED;
  }
  int32_t n = (int32_t)count;
  if (n > SCREEN_MONITOR_MAX_DISPLAYS) {
    n = SCREEN_MONITOR_MAX_DISPLAYS;
  }
  for (int32_t i = 0; i < n; i++) {
    proton_cg_rect b = g_mac.display_bounds(ids[i]);
    screen_monitor_display_t *d = &state->displays[state->display_count];
    memset(d, 0, sizeof(*d));
    d->x = (int32_t)b.x;
    d->y = (int32_t)b.y;
    d->width = (int32_t)b.width;
    d->height = (int32_t)b.height;
    /* CoreGraphics uses top-left origin with y increasing downward, matching
       the facade; no flip is needed. Work area is approximated by the frame. */
    d->work_x = d->x;
    d->work_y = d->y;
    d->work_width = d->width;
    d->work_height = d->height;
    size_t px_wide = g_mac.pixels_wide(ids[i]);
    if (px_wide > 0 && d->width > 0) {
      d->scale_factor_percent =
          (int32_t)((px_wide * 100) / (size_t)d->width);
    } else {
      d->scale_factor_percent = 100;
    }
    d->is_primary = g_mac.display_is_main(ids[i]) ? 1 : 0;
    d->id = (int32_t)ids[i];
    d->present = 1;
    state->display_count++;
  }
  return state->display_count;
}

int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y) {
  (void)state;
  if (!screen_monitor_load_mac_symbols()) {
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  proton_cf_type_ref event = g_mac.event_create(0 /* kCGEventNull */);
  if (event == NULL) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  proton_cg_point_t location = g_mac.event_get_location(event);
  g_mac.release(event);
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

static screen_monitor_state_t *g_shared_state = NULL;

/* Called by CoreGraphics on its own thread whenever a display is added, removed,
   or reconfigured. Re-enumerates and diffs against the previous snapshot. */
static void screen_monitor_reconfiguration_callback(
    proton_cg_direct_display_id display, proton_cg_error status, void *info) {
  (void)display;
  (void)status;
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

int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state) {
  if (g_shared_state != NULL) {
    return screen_monitor_STATUS_OK;
  }
  if (!screen_monitor_load_mac_symbols()) {
    screen_monitor_set_watch_error(state, "CoreGraphics unavailable");
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  if (screen_monitor_platform_enumerate(state) < 0) {
    screen_monitor_set_watch_error(state, "display enumeration failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  g_shared_state = state;
  proton_cg_error err = g_mac.register_reconfiguration(
      screen_monitor_reconfiguration_callback, state);
  if (err != 0) {
    g_shared_state = NULL;
    screen_monitor_set_watch_error(state, "reconfiguration registration failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  state->watch_started = 1;
  return screen_monitor_STATUS_OK;
}

int32_t screen_monitor_platform_stop_watching(screen_monitor_state_t *state) {
  if (g_shared_state == state && g_mac.remove_reconfiguration != NULL) {
    g_mac.remove_reconfiguration(screen_monitor_reconfiguration_callback,
                                 state);
  }
  g_shared_state = NULL;
  state->watch_started = 0;
  return screen_monitor_STATUS_OK;
}

#endif
