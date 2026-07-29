#ifndef KEEP_AWAKE_NATIVE_STUB_H
#define KEEP_AWAKE_NATIVE_STUB_H

#include "moonbit.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum keepawake_scope {
  keepawake_SCOPE_SYSTEM = 1,
  keepawake_SCOPE_DISPLAY = 2,
  keepawake_SCOPE_SYSTEM_AND_DISPLAY = 3
};

enum keepawake_status {
  keepawake_STATUS_OK = 0,
  keepawake_STATUS_BACKEND_UNAVAILABLE = 1,
  keepawake_STATUS_OPERATION_FAILED = 2
};

typedef struct keepawake_guard {
  int32_t status;
  int32_t scope;
  int32_t active;
  char *last_error;
#ifdef _WIN32
  uint32_t requested_state;
#elif defined(__APPLE__)
  uint32_t system_assertion_id;
  uint32_t display_assertion_id;
  int32_t has_system_assertion;
  int32_t has_display_assertion;
#else
  int32_t child_pid;
#endif
} keepawake_guard_t;

void keepawake_clear_error(keepawake_guard_t *guard);
void keepawake_set_error(
  keepawake_guard_t *guard,
  int32_t status,
  const char *format,
  ...
);
moonbit_bytes_t keepawake_make_error_bytes(const char *text);

void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
);
void keepawake_platform_release(keepawake_guard_t *guard);

#endif
