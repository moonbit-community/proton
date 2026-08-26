#include "native_stub.h"

#ifdef _WIN32

#include <stdio.h>
#include <stdlib.h>

#define UNICODE 1
#define _UNICODE 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dbt.h>

/* Scale factor query lives in shcore.dll (Windows 8.1+). Load it lazily so the
   backend also runs on downlevel systems, falling back to 100%. */
typedef HRESULT(WINAPI *proton_get_dpi_for_monitor_fn)(HMONITOR, int *,
                                                       UINT *, UINT *);

static proton_get_dpi_for_monitor_fn g_get_dpi_for_monitor = NULL;
static int32_t g_dpi_loaded = 0;

/* Interface class GUID for display adapters
   (GUID_DEVINTERFACE_DISPLAY_ADAPTER = {1CA05180-A699-450A-9A0C-DE4FBE3DDD89}).
   Carried as a local constant so device notifications route to the message-only
   window without dragging in setupapi/devguid link dependencies. */
static const GUID screen_monitor_display_interface_guid = { 0x1CA05180, 0xA699,
                                                            0x450A, { 0x9A, 0x0C,
                                                                      0xDE, 0x4F,
                                                                      0xBE, 0x3D,
                                                                      0xD8,
                                                                      0x89 } };

static void screen_monitor_ensure_dpi_loaded(void) {
  if (g_dpi_loaded) {
    return;
  }
  g_dpi_loaded = 1;
  HMODULE shcore = LoadLibraryW(L"shcore.dll");
  if (shcore != NULL) {
    g_get_dpi_for_monitor = (proton_get_dpi_for_monitor_fn)GetProcAddress(
        shcore, "GetDpiForMonitor");
  }
}

void screen_monitor_platform_init(screen_monitor_state_t *state) {
  (void)state;
  screen_monitor_ensure_dpi_loaded();
}

static BOOL CALLBACK screen_monitor_enum_monitor_proc(HMONITOR hmonitor,
                                                      HDC hdc,
                                                      LPRECT rect,
                                                      LPARAM lparam) {
  (void)hdc;
  (void)rect;
  screen_monitor_state_t *state = (screen_monitor_state_t *)lparam;
  if (state == NULL || state->display_count >= SCREEN_MONITOR_MAX_DISPLAYS) {
    return FALSE;
  }
  MONITORINFOEXW info;
  memset(&info, 0, sizeof(info));
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(hmonitor, (LPMONITORINFO)&info)) {
    return TRUE;
  }
  screen_monitor_display_t *d = &state->displays[state->display_count];
  memset(d, 0, sizeof(*d));
  d->x = (int32_t)info.rcMonitor.left;
  d->y = (int32_t)info.rcMonitor.top;
  d->width = (int32_t)(info.rcMonitor.right - info.rcMonitor.left);
  d->height = (int32_t)(info.rcMonitor.bottom - info.rcMonitor.top);
  d->work_x = (int32_t)info.rcWork.left;
  d->work_y = (int32_t)info.rcWork.top;
  d->work_width = (int32_t)(info.rcWork.right - info.rcWork.left);
  d->work_height = (int32_t)(info.rcWork.bottom - info.rcWork.top);
  d->is_primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  d->scale_factor_percent = 100;
  if (g_get_dpi_for_monitor != NULL) {
    UINT dpi_x = 0;
    UINT dpi_y = 0;
    if (g_get_dpi_for_monitor(hmonitor, 0 /* MDT_EFFECTIVE_DPI */, &dpi_x,
                              &dpi_y) == S_OK &&
        dpi_x != 0) {
      d->scale_factor_percent = (int32_t)((dpi_x * 100) / 96);
    }
  }
  d->id = state->display_count;
  d->present = 1;
  state->display_count++;
  return TRUE;
}

int32_t screen_monitor_platform_enumerate(screen_monitor_state_t *state) {
  state->display_count = 0;
  if (!EnumDisplayMonitors(NULL, NULL, screen_monitor_enum_monitor_proc,
                           (LPARAM)state)) {
    return -screen_monitor_STATUS_OPERATION_FAILED;
  }
  return state->display_count;
}

int32_t screen_monitor_platform_query_cursor(screen_monitor_state_t *state,
                                             int32_t *out_x, int32_t *out_y) {
  (void)state;
  POINT pt;
  if (!GetCursorPos(&pt)) {
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  if (out_x != NULL) {
    *out_x = (int32_t)pt.x;
  }
  if (out_y != NULL) {
    *out_y = (int32_t)pt.y;
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
  /* Prefer a display that actually contains the point. */
  for (int32_t i = 0; i < state->display_count; i++) {
    const screen_monitor_display_t *d = &state->displays[i];
    if (x >= d->x && x < d->x + d->width && y >= d->y && y < d->y + d->height) {
      return i;
    }
  }
  /* Otherwise fall back to the display whose center is nearest to (x, y). */
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

/* --- Event watch backend & hot-plug diffing ----------------------------- */

static void screen_monitor_set_watch_error(screen_monitor_state_t *state,
                                           const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

/* Compares the current `state->displays[i].present` snapshot against the
   previous ids and pushes ADDED/REMOVED events. Returns non-zero when any
   display's geometry changed since the last diff. */
static int screen_monitor_diff(screen_monitor_state_t *state,
                               screen_monitor_display_t *previous,
                               int32_t previous_count) {
  int32_t geometry_changed = 0;
  /* Any current display not present before was added. */
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
  /* Any previous display now gone was removed. */
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
  return geometry_changed;
}

/* The message window and every hot-plug notification it handles run on the
   watch thread, so a thread-local state pointer reaches the shared queue. */
static __declspec(thread) screen_monitor_state_t *g_watch_state = NULL;

static LRESULT CALLBACK screen_monitor_wnd_proc(HWND hwnd, UINT message,
                                                WPARAM wParam,
                                                LPARAM lParam) {
  screen_monitor_state_t *state = g_watch_state;
  if (state == NULL) {
    return DefWindowProcW(hwnd, message, wParam, lParam);
  }
  if ((message == WM_DISPLAYCHANGE || message == WM_DEVICECHANGE) &&
      state->display_count >= 0) {
    screen_monitor_display_t previous[SCREEN_MONITOR_MAX_DISPLAYS];
    int32_t previous_count = state->display_count;
    memcpy(previous, state->displays, sizeof(previous));
    memset(state->displays, 0, sizeof(state->displays));
    int32_t count = screen_monitor_platform_enumerate(state);
    if (count >= 0) {
      int32_t geometry_changed = screen_monitor_diff(state, previous,
                                                     previous_count);
      if (geometry_changed) {
        screen_monitor_push_event(state,
                                  screen_monitor_EVENT_METRICS_CHANGED);
      }
    } else {
      /* Restore the previous snapshot so a transient enum failure is not
         mistaken for a removal of every display. */
      memcpy(state->displays, previous, sizeof(previous));
      state->display_count = previous_count;
    }
  } else if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wParam, lParam);
}

static DWORD WINAPI screen_monitor_watch_thread_main(LPVOID param) {
  screen_monitor_state_t *state = (screen_monitor_state_t *)param;
  g_watch_state = state;

  WNDCLASSW wc;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = screen_monitor_wnd_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = L"ProtonScreenMonitorWatchWindow";
  if (RegisterClassW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    screen_monitor_set_watch_error(state, "RegisterClassW failed");
    state->watch_started = 0;
    SetEvent(state->ready_event);
    return 1;
  }

  HWND hwnd = CreateWindowExW(0, wc.lpszClassName, L"ProtonScreenMonitor", 0, 0,
                              0, 0, 0, (HWND)HWND_MESSAGE, NULL, wc.hInstance,
                              NULL);
  if (hwnd == NULL) {
    screen_monitor_set_watch_error(state, "CreateWindowExW failed");
    state->watch_started = 0;
    SetEvent(state->ready_event);
    return 1;
  }
  state->message_window = hwnd;

  /* Monitor hot-plug notifications (WM_DISPLAYCHANGE) plus device-arrival
     events for the display adapter GUID. */
  DEV_BROADCAST_DEVICEINTERFACE_W filter;
  memset(&filter, 0, sizeof(filter));
  filter.dbcc_size = sizeof(filter);
  filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
  filter.dbcc_classguid = screen_monitor_display_interface_guid;
  state->device_handle = RegisterDeviceNotificationW(
      hwnd, &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
  state->registered = 1;

  /* Seed the snapshot so only real topology changes are reported afterwards. */
  screen_monitor_platform_enumerate(state);

  state->watch_started = 1;
  SetEvent(state->ready_event);

  MSG msg;
  while (GetMessageW(&msg, NULL, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  state->watch_started = 0;
  state->message_window = NULL;
  return 0;
}

int32_t screen_monitor_platform_start_watching(screen_monitor_state_t *state) {
  if (state->watch_thread != NULL) {
    return screen_monitor_STATUS_OK;
  }
  state->watch_started = 0;
  if (state->ready_event == NULL) {
    state->ready_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (state->ready_event == NULL) {
      screen_monitor_set_watch_error(state, "CreateEventW failed");
      return screen_monitor_STATUS_OPERATION_FAILED;
    }
  }
  state->watch_thread =
      CreateThread(NULL, 0, screen_monitor_watch_thread_main, state, 0,
                   &state->watch_thread_id);
  if (state->watch_thread == NULL) {
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
    screen_monitor_set_watch_error(state, "CreateThread failed");
    return screen_monitor_STATUS_OPERATION_FAILED;
  }
  WaitForSingleObject(state->ready_event, INFINITE);
  if (!state->watch_started) {
    WaitForSingleObject(state->watch_thread, INFINITE);
    CloseHandle(state->watch_thread);
    state->watch_thread = NULL;
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
    if (state->watch_error[0] == '\0') {
      screen_monitor_set_watch_error(state, "watch backend failed to start");
    }
    return screen_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  return screen_monitor_STATUS_OK;
}

int32_t screen_monitor_platform_stop_watching(screen_monitor_state_t *state) {
  if (state->watch_thread != NULL) {
    PostThreadMessageW(state->watch_thread_id, WM_QUIT, 0, 0);
    WaitForSingleObject(state->watch_thread, INFINITE);
    CloseHandle(state->watch_thread);
    state->watch_thread = NULL;
  }
  if (state->ready_event != NULL) {
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
  }
  if (state->device_handle != NULL) {
    UnregisterDeviceNotification(state->device_handle);
    state->device_handle = NULL;
  }
  state->watch_started = 0;
  return screen_monitor_STATUS_OK;
}

#endif
