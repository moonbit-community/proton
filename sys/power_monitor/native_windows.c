#include "native_stub.h"

#ifdef _WIN32

#include <stdio.h>
#include <stdlib.h>

#define UNICODE 1
#define _UNICODE 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wtsapi32.h>

#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "wtsapi32.lib")
#endif

/* GUID_ACDC_POWER_SOURCE (declared in poclass.h) spelled out so the watch
   backend does not depend on the full Windows SDK power headers. */
static const GUID k_power_source_guid = {
    0x5D3E9A59,
    0xE9D5,
    0x4B00,
    {0xA6, 0xBD, 0xFF, 0x34, 0xFF, 0x51, 0x65, 0x48},
};

#if defined(_MSC_VER)
#define POWER_MONITOR_THREAD_LOCAL __declspec(thread)
#elif defined(__GNUC__)
#define POWER_MONITOR_THREAD_LOCAL __thread
#else
#define POWER_MONITOR_THREAD_LOCAL
#endif

/* The message window and every notification it handles run on the watch thread,
   so a thread-local state pointer is enough to reach the shared queue. */
static POWER_MONITOR_THREAD_LOCAL power_monitor_state_t *g_watch_state = NULL;

void power_monitor_platform_init(power_monitor_state_t *state) {
  (void)state;
}

int32_t power_monitor_platform_query_idle(power_monitor_state_t *state) {
  LASTINPUTINFO lii;
  lii.cbSize = sizeof(lii);
  if (!GetLastInputInfo(&lii)) {
    snprintf(state->last_error, sizeof(state->last_error),
             "GetLastInputInfo failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  ULONGLONG now = GetTickCount64();
  ULONGLONG last = lii.dwTime;
  if (now < last) {
    state->idle_seconds = 0;
  } else {
    state->idle_seconds = (int64_t)((now - last) / 1000);
  }
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_query_source(power_monitor_state_t *state) {
  SYSTEM_POWER_STATUS status;
  if (!GetSystemPowerStatus(&status)) {
    snprintf(state->last_error, sizeof(state->last_error),
             "GetSystemPowerStatus failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  switch (status.ACLineStatus) {
    case 0:
      state->source = power_monitor_SOURCE_BATTERY;
      break;
    case 1:
      state->source = power_monitor_SOURCE_AC;
      break;
    default:
      state->source = power_monitor_SOURCE_UNKNOWN;
      break;
  }
  if (status.BatteryFlag != 128 && status.BatteryLifePercent <= 100) {
    state->battery_percent = (int32_t)status.BatteryLifePercent;
    state->has_battery_percent = 1;
  } else {
    state->has_battery_percent = 0;
  }
  return power_monitor_STATUS_OK;
}

static void power_monitor_set_watch_error(power_monitor_state_t *state,
                                          const char *message) {
  if (state == NULL || message == NULL) {
    return;
  }
  snprintf(state->watch_error, sizeof(state->watch_error), "%s", message);
}

static LRESULT CALLBACK power_monitor_wnd_proc(HWND hwnd, UINT message,
                                               WPARAM wParam, LPARAM lParam) {
  if (message == WM_POWERBROADCAST) {
    switch (wParam) {
      case PBT_APMSUSPEND:
        power_monitor_push_event(g_watch_state, power_monitor_EVENT_SUSPEND);
        break;
      case PBT_APMRESUMEAUTOMATIC:
      case PBT_APMRESUMESUSPEND:
        power_monitor_push_event(g_watch_state, power_monitor_EVENT_RESUME);
        break;
      case PBT_POWERSETTINGCHANGE: {
        /* lParam points at POWERBROADCAST_SETTING when the change is for one of
           the registered power setting GUIDs. */
        POWERBROADCAST_SETTING *setting = (POWERBROADCAST_SETTING *)lParam;
        if (setting != NULL &&
            memcmp(&setting->PowerSetting, &k_power_source_guid,
                   sizeof(GUID)) == 0 &&
            setting->DataLength >= sizeof(DWORD)) {
          DWORD value = 0;
          memcpy(&value, setting->Data, sizeof(value));
          power_monitor_push_event(g_watch_state,
                                   value == 1
                                       ? power_monitor_EVENT_ON_AC
                                       : power_monitor_EVENT_ON_BATTERY);
        }
        break;
      }
      default:
        break;
    }
  } else if (message == WM_WTSSESSION_CHANGE) {
    switch (wParam) {
      case WTS_SESSION_LOCK:
        power_monitor_push_event(g_watch_state,
                                 power_monitor_EVENT_LOCK_SCREEN);
        break;
      case WTS_SESSION_UNLOCK:
        power_monitor_push_event(g_watch_state,
                                 power_monitor_EVENT_UNLOCK_SCREEN);
        break;
      default:
        break;
    }
  } else if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wParam, lParam);
}

static DWORD WINAPI power_monitor_watch_thread_main(LPVOID param) {
  power_monitor_state_t *state = (power_monitor_state_t *)param;
  g_watch_state = state;

  WNDCLASSW wc;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = power_monitor_wnd_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = L"ProtonPowerMonitorWatchWindow";
  if (RegisterClassW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    power_monitor_set_watch_error(state, "RegisterClassW failed");
    SetEvent(state->ready_event);
    return 1;
  }

  HWND hwnd = CreateWindowExW(0, wc.lpszClassName, L"ProtonPowerMonitor", 0, 0,
                              0, 0, 0, (HWND)HWND_MESSAGE, NULL, wc.hInstance,
                              NULL);
  if (hwnd == NULL) {
    power_monitor_set_watch_error(state, "CreateWindowExW failed");
    SetEvent(state->ready_event);
    return 1;
  }
  state->message_window = hwnd;

  /* Session lock/unlock notifications for the current interactive session. */
  WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
  /* AC/battery power source changes, delivered as WM_POWERBROADCAST. */
  RegisterPowerSettingNotification(hwnd, &k_power_source_guid,
                                   DEVICE_NOTIFY_WINDOW_HANDLE);

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

int32_t power_monitor_platform_start_watching(power_monitor_state_t *state) {
  if (state->watch_thread != NULL) {
    /* Already running or still starting. */
    return power_monitor_STATUS_OK;
  }
  if (state->ready_event == NULL) {
    state->ready_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (state->ready_event == NULL) {
      power_monitor_set_watch_error(state, "CreateEventW failed");
      return power_monitor_STATUS_OPERATION_FAILED;
    }
  }
  state->watch_thread =
      CreateThread(NULL, 0, power_monitor_watch_thread_main, state, 0,
                   &state->watch_thread_id);
  if (state->watch_thread == NULL) {
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
    power_monitor_set_watch_error(state, "CreateThread failed");
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  WaitForSingleObject(state->ready_event, 10000);
  if (!state->watch_started) {
    CloseHandle(state->watch_thread);
    state->watch_thread = NULL;
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
    if (state->watch_error[0] == '\0') {
      power_monitor_set_watch_error(state, "watch backend failed to start");
    }
    return power_monitor_STATUS_BACKEND_UNAVAILABLE;
  }
  return power_monitor_STATUS_OK;
}

int32_t power_monitor_platform_stop_watching(power_monitor_state_t *state) {
  if (state->watch_thread != NULL) {
    PostThreadMessageW(state->watch_thread_id, WM_QUIT, 0, 0);
    WaitForSingleObject(state->watch_thread, 10000);
    CloseHandle(state->watch_thread);
    state->watch_thread = NULL;
  }
  if (state->ready_event != NULL) {
    CloseHandle(state->ready_event);
    state->ready_event = NULL;
  }
  state->watch_started = 0;
  return power_monitor_STATUS_OK;
}

#endif
