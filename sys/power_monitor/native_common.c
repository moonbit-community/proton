#include "native_stub.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

static void power_monitor_set_error(power_monitor_state_t *state,
                                    const char *message) {
  if (state != NULL && message != NULL) {
    snprintf(state->last_error, sizeof(state->last_error), "%s", message);
  }
}

/* GC finalizer: no platform resources to release beyond what the platform
   helpers already manage, but keep the hook for future use. */
static void power_monitor_finalize(void *payload) {
  (void)payload;
}

MOONBIT_FFI_EXPORT
void *moonbit_power_monitor_create(void) {
  power_monitor_state_t *state =
      (power_monitor_state_t *)moonbit_make_external_object(
          power_monitor_finalize, (uint32_t)sizeof(power_monitor_state_t));
  if (state == NULL) {
    return NULL;
  }
  memset(state, 0, sizeof(*state));
  state->source = power_monitor_SOURCE_UNKNOWN;
  power_monitor_platform_init(state);
  return state;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_idle_seconds(void *handle,
                                           int64_t *out_seconds) {
  if (handle == NULL || out_seconds == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  state->status = power_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t platform_status = power_monitor_platform_query_idle(state);
  if (platform_status != power_monitor_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      power_monitor_set_error(state, "querying idle time failed");
    }
    state->status = platform_status;
    return platform_status;
  }
  *out_seconds = state->idle_seconds;
  return power_monitor_STATUS_OK;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_source(void *handle,
                                     int32_t *out_source,
                                     int32_t *out_percent,
                                     int32_t *out_has_percent) {
  if (handle == NULL || out_source == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  state->status = power_monitor_STATUS_OK;
  state->last_error[0] = '\0';
  int32_t platform_status = power_monitor_platform_query_source(state);
  if (platform_status != power_monitor_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      power_monitor_set_error(state, "querying power source failed");
    }
    state->status = platform_status;
    return platform_status;
  }
  *out_source = state->source;
  if (out_percent != NULL) {
    *out_percent = state->battery_percent;
  }
  if (out_has_percent != NULL) {
    *out_has_percent = state->has_battery_percent;
  }
  return power_monitor_STATUS_OK;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_power_monitor_status(void *handle) {
  if (handle == NULL) {
    return power_monitor_STATUS_OPERATION_FAILED;
  }
  return ((power_monitor_state_t *)handle)->status;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_power_monitor_last_error(void *handle) {
  if (handle == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  power_monitor_state_t *state = (power_monitor_state_t *)handle;
  const char *text = state->last_error;
  if (text[0] == '\0') {
    return moonbit_make_bytes(0, 0);
  }
  int32_t len = (int32_t)strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, (size_t)len);
  return bytes;
}

MOONBIT_FFI_EXPORT
void moonbit_power_monitor_destroy(void *handle) {
  if (handle == NULL) {
    return;
  }
}
