#ifdef _WIN32
#include "../../native_stub.h"
#include <wtsapi32.h>
#include <string.h>

static int failure_stage;
static int session_unregistered;
static int power_attempted;
static HWND registered_window;

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

/* Replace only the registration calls; run the production thread, window,
   cleanup, and native error propagation with the real Windows APIs. */
#define WTSRegisterSessionNotification fail_session_registration
#define WTSUnRegisterSessionNotification record_session_unregistration
#define RegisterPowerSettingNotification fail_power_registration
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
    int32_t status = moonbit_power_monitor_start_watching(&state);
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
#endif
