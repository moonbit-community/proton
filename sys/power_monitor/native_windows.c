#include "native_stub.h"

#ifdef _WIN32

#include <stdio.h>

#define UNICODE 1
#define _UNICODE 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

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

#endif
