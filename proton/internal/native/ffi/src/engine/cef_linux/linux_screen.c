#if defined(__linux__)

#include "linux_internal.h"

#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#include <gdk/gdkx.h>
#include <X11/Xlib.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int32_t proton_engine_screen_enumerate(
    proton_engine_screen_info_t *out_screens,
    int32_t max_screens,
    int32_t *out_count,
    char *error,
    size_t error_len) {
  if (out_screens == NULL || out_count == NULL || max_screens <= 0) {
    proton_engine_set_message(error, error_len,
                              "out_screens, out_count are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = 0;

  /* gdk/gdk.h is pulled in transitively via gtk/gtk.h above. */
  GdkDisplay *display = gdk_display_get_default();
  if (display == NULL) {
    proton_engine_set_message(error, error_len,
                              "no GDK display available");
    return PROTON_ERR_PLATFORM;
  }

  int n_monitors = gdk_display_get_n_monitors(display);
  if (n_monitors <= 0) {
    return PROTON_OK;
  }

  int32_t idx = 0;
  for (int i = 0; i < n_monitors && idx < max_screens; i++) {
    GdkMonitor *monitor = gdk_display_get_monitor(display, i);
    if (monitor == NULL) {
      continue;
    }
    GdkRectangle geom;
    gdk_monitor_get_geometry(monitor, &geom);
    GdkRectangle work_geom;
    gdk_monitor_get_workarea(monitor, &work_geom);

    int scale = gdk_monitor_get_scale_factor(monitor);

    proton_engine_screen_info_t *info = &out_screens[idx];
    info->id = idx;
    info->x = geom.x;
    info->y = geom.y;
    info->width = geom.width;
    info->height = geom.height;
    info->work_x = work_geom.x;
    info->work_y = work_geom.y;
    info->work_width = work_geom.width;
    info->work_height = work_geom.height;
    info->scale_factor_percent = scale * 100;
    info->is_primary = (i == 0) ? 1 : 0;
    idx++;
  }
  *out_count = idx;
  return PROTON_OK;
}

#endif
