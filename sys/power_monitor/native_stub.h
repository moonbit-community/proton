#ifndef PROTON_POWER_MONITOR_STUB_H
#define PROTON_POWER_MONITOR_STUB_H

#include "moonbit.h"

#include <stdint.h>

enum power_monitor_source {
  power_monitor_SOURCE_UNKNOWN = 0,
  power_monitor_SOURCE_AC = 1,
  power_monitor_SOURCE_BATTERY = 2,
};

enum power_monitor_status {
  power_monitor_STATUS_OK = 0,
  power_monitor_STATUS_BACKEND_UNAVAILABLE = 1,
  power_monitor_STATUS_OPERATION_FAILED = 2,
};

typedef struct power_monitor_state {
  int32_t status;
  int32_t source;
  int32_t battery_percent;
  int32_t has_battery_percent;
  int64_t idle_seconds;
  char last_error[512];
} power_monitor_state_t;

void power_monitor_platform_init(power_monitor_state_t *state);
int32_t power_monitor_platform_query_idle(power_monitor_state_t *state);
int32_t power_monitor_platform_query_source(power_monitor_state_t *state);

#endif
