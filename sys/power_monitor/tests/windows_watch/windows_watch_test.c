#ifdef _WIN32
#include "../../native_stub.h"
#include <wtsapi32.h>
#include <string.h>

static int failure_stage;
static int session_unregistered;
static int power_attempted;
static HWND registered_window;
static ULONGLONG current_tick;
static DWORD last_input_tick;
static BOOL last_input_succeeds;

static ULONGLONG WINAPI test_tick_count(void) {
  return current_tick;
}

static BOOL WINAPI test_last_input(PLASTINPUTINFO info) {
  info->dwTime = last_input_tick;
  return last_input_succeeds;
}

static BOOL WINAPI fail_session_registration(HWND hwnd, DWORD flags) {
  (void)flags;
  registered_window = hwnd;
  if (failure_stage == 1) {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return TRUE;
}

static BOOL WINAPI record_session_unregistration(HWND hwnd) {
  (void)hwnd;
  session_unregistered++;
  return TRUE;
}

static HPOWERNOTIFY WINAPI fail_power_registration(HANDLE handle,
                                                   LPCGUID guid, DWORD flags) {
  (void)handle;
  (void)guid;
  (void)flags;
  power_attempted++;
  SetLastError(ERROR_NOT_SUPPORTED);
  return NULL;
}

/* Control registration failures and input timestamps; retain production
   notification handling, queries, thread/window cleanup, and event queues. */
#define WTSRegisterSessionNotification fail_session_registration
#define WTSUnRegisterSessionNotification record_session_unregistration
#define RegisterPowerSettingNotification fail_power_registration
#define GetTickCount64 test_tick_count
#define GetLastInputInfo test_last_input
#include "../../native_windows.c"
#include "../../native_common.c"

int32_t proton_test_power_registration_failure(int32_t stage) {
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  failure_stage = stage;
  int result = 0;
  /* The same handle must be retryable after a failed registration. */
  for (int attempt = 0; attempt < 2; attempt++) {
    session_unregistered = 0;
    power_attempted = 0;
    registered_window = NULL;
    int32_t status = moonbit_power_monitor_start_watching(&state, -1);
    const char *operation = stage == 1 ? "WTSRegisterSessionNotification"
                                       : "RegisterPowerSettingNotification";
    const char *code = stage == 1 ? "Win32 error 5" : "Win32 error 50";
    if (status == power_monitor_STATUS_OK || state.watch_started ||
        state.watch_thread != NULL || state.ready_event != NULL ||
        state.message_window != NULL || registered_window == NULL ||
        IsWindow(registered_window) ||
        strstr(state.last_error, operation) == NULL ||
        strstr(state.last_error, code) == NULL ||
        session_unregistered != (stage == 2 ? 1 : 0) ||
        power_attempted != (stage == 2 ? 1 : 0)) {
      result = __LINE__;
      break;
    }
  }
  power_monitor_platform_stop_watching(&state);
  power_monitor_release_events(&state);
  power_monitor_lock_destroy(&state);
  return result;
}

int32_t proton_test_power_source_notifications(void) {
  const struct {
    DWORD source;
    int32_t event;
  } cases[] = {
    {PoAc, power_monitor_EVENT_ON_AC},
    {PoDc, power_monitor_EVENT_ON_BATTERY},
    {PoHot, -1},
    {PoConditionMaximum, -1},
    {MAXDWORD, -1},
  };
  union {
    POWERBROADCAST_SETTING setting;
    BYTE storage[sizeof(POWERBROADCAST_SETTING) + sizeof(DWORD)];
  } message = {0};
  message.setting.PowerSetting = k_power_source_guid;
  message.setting.DataLength = sizeof(DWORD);
  power_monitor_state_t state = {0};
  power_monitor_lock_init(&state);
  g_watch_state = &state;
  int result = 0;
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    memcpy(message.setting.Data, &cases[i].source, sizeof(DWORD));
    power_monitor_wnd_proc(NULL, WM_POWERBROADCAST, PBT_POWERSETTINGCHANGE,
                          (LPARAM)&message.setting);
    int32_t event = -1;
    int32_t status = power_monitor_take_event(&state, &event);
    int32_t expected_status = cases[i].event == -1
        ? power_monitor_STATUS_EMPTY : power_monitor_STATUS_OK;
    if (status != expected_status || event != cases[i].event ||
        state.event_queue_size != 0) {
      result = (int32_t)i + 1;
      break;
    }
  }
  g_watch_state = NULL;
  power_monitor_release_events(&state);
  power_monitor_lock_destroy(&state);
  return result;
}

int32_t proton_test_idle_tick_wraparound(void) {
  const struct {
    ULONGLONG now;
    DWORD last;
    int64_t seconds;
  } cases[] = {
    {5000, 4000, 1},
    {4999, 4000, 0},
    {5000, 5000, 0},
    {0xfffffff0ULL, 0xfffff820UL, 2},
    {0x100001388ULL, 4000, 1},
    {0x1000003e8ULL, 0xfffffc18UL, 2},
    {0x200001388ULL, 4000, 1},
    {0xffffffffULL, 0, 4294967},
  };
  power_monitor_state_t state = {0};
  last_input_succeeds = TRUE;
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    current_tick = cases[i].now;
    last_input_tick = cases[i].last;
    if (power_monitor_platform_query_idle(&state) != power_monitor_STATUS_OK ||
        state.idle_seconds != cases[i].seconds) {
      return (int32_t)i + 1;
    }
  }
  last_input_succeeds = FALSE;
  if (power_monitor_platform_query_idle(&state) !=
          power_monitor_STATUS_OPERATION_FAILED ||
      strstr(state.last_error, "GetLastInputInfo failed") == NULL) {
    return -1;
  }
  return 0;
}
#endif
