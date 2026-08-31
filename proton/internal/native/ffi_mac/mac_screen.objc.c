#if defined(__APPLE__)

#include "mac_internal.h"

#include "../ffi/src/proton_config.h"
#include "../ffi/src/proton_event.h"
#include "../ffi/src/proton_json.h"
#include "../ffi/src/engine/cef_common/browser_session.h"
#include "../ffi/src/engine/cef_common/message.h"
#include "../ffi/src/engine/cef_common/scheme.h"
#include "../ffi/src/engine/cef_common/view_events.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#import <Cocoa/Cocoa.h>
#include <dispatch/dispatch.h>

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
  PROTON_ENGINE_RETURN_ON_MAIN(
      proton_engine_screen_enumerate(out_screens, max_screens, out_count,
                                     error, error_len));
  if (out_screens == NULL || out_count == NULL || max_screens <= 0) {
    proton_engine_set_message(error, error_len,
                              "out_screens, out_count are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = 0;

  @autoreleasepool {
    NSArray *screens = [NSScreen screens];
    NSUInteger count = [screens count];
    if (count == 0) {
      return PROTON_OK;
    }
    NSScreen *primary = [screens objectAtIndex:0];
    NSRect primaryFrame = [primary frame];

    int32_t idx = 0;
    for (NSUInteger i = 0; i < count && idx < max_screens; i++) {
      NSScreen *screen = [screens objectAtIndex:i];
      NSRect frame = [screen frame];
      NSRect visibleFrame = [screen visibleFrame];

      /* macOS uses a bottom-left origin; convert to top-left so the
         coordinates match Windows/Linux and the rest of the Proton API. */
      proton_engine_screen_info_t *info = &out_screens[idx];
      info->id = (int32_t)i;
      info->x = (int32_t)frame.origin.x;
      info->y = (int32_t)(primaryFrame.size.height - frame.origin.y -
                          frame.size.height);
      info->width = (int32_t)frame.size.width;
      info->height = (int32_t)frame.size.height;
      info->work_x = (int32_t)visibleFrame.origin.x;
      info->work_y = (int32_t)(primaryFrame.size.height -
                               visibleFrame.origin.y -
                               visibleFrame.size.height);
      info->work_width = (int32_t)visibleFrame.size.width;
      info->work_height = (int32_t)visibleFrame.size.height;

      CGFloat scaleFactor = [screen backingScaleFactor];
      info->scale_factor_percent = (int32_t)(scaleFactor * 100.0);
      info->is_primary = (i == 0) ? 1 : 0;

      idx++;
    }
    *out_count = idx;
  }
  return PROTON_OK;
}

#endif
