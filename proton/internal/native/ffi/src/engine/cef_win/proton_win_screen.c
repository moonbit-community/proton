#if defined(_WIN32)

#include "internal.h"

#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) InterlockedCompareExchange(&(refs)->refs, 0, 0)
#define PROTON_ENGINE_REF_STORE(refs, value) InterlockedExchange(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  proton_engine_screen_info_t *screens;
  int32_t max_screens;
  int32_t count;
} proton_screen_enum_context_t;

static BOOL CALLBACK proton_screen_enum_callback(HMONITOR monitor, HDC hdc,
                                                  LPRECT clip_rect,
                                                  LPARAM param) {
  (void)hdc;
  (void)clip_rect;
  proton_screen_enum_context_t *ctx = (proton_screen_enum_context_t *)param;
  if (ctx->count >= ctx->max_screens) {
    return FALSE;
  }
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }
  proton_engine_screen_info_t *screen = &ctx->screens[ctx->count];
  screen->id = ctx->count;
  screen->x = info.rcMonitor.left;
  screen->y = info.rcMonitor.top;
  screen->width = info.rcMonitor.right - info.rcMonitor.left;
  screen->height = info.rcMonitor.bottom - info.rcMonitor.top;
  screen->work_x = info.rcWork.left;
  screen->work_y = info.rcWork.top;
  screen->work_width = info.rcWork.right - info.rcWork.left;
  screen->work_height = info.rcWork.bottom - info.rcWork.top;
  screen->is_primary = (info.dwFlags & MONITORINFOF_PRIMARY) ? 1 : 0;

  /* GetDpiForMonitor lives in shcore.dll; load it dynamically so the build
     does not require linking shcore.lib and stays compatible with older
     Windows where the export may be absent. */
  UINT dpi_x = 96;
  UINT dpi_y = 96;
  HMODULE shcore = LoadLibraryW(L"shcore.dll");
  if (shcore != NULL) {
    typedef HRESULT(WINAPI *proton_get_dpi_for_monitor_proc)(HMONITOR, int,
                                                              UINT *, UINT *);
    proton_get_dpi_for_monitor_proc get_dpi =
        (proton_get_dpi_for_monitor_proc)GetProcAddress(shcore,
                                                        "GetDpiForMonitor");
    if (get_dpi != NULL) {
      get_dpi(monitor, 0, &dpi_x, &dpi_y);
    }
    FreeLibrary(shcore);
  }
  screen->scale_factor_percent = (int32_t)((dpi_x * 100 + 48) / 96);

  ctx->count++;
  return TRUE;
}


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
  proton_screen_enum_context_t ctx = {
      .screens = out_screens,
      .max_screens = max_screens,
      .count = 0,
  };
  /* EnumDisplayMonitors is safe to call from any thread; it snapshots the
     current monitor configuration without entering the UI message loop. */
  if (!EnumDisplayMonitors(NULL, NULL, proton_screen_enum_callback,
                           (LPARAM)&ctx)) {
    proton_engine_set_message(error, error_len,
                              "EnumDisplayMonitors failed");
    return PROTON_ERR_PLATFORM;
  }
  *out_count = ctx.count;
  return PROTON_OK;
}

#endif
