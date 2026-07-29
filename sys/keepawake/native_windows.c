#include "native_stub.h"

#ifdef _WIN32
#include <windows.h>

static void keepawake_set_windows_error(
  keepawake_guard_t *guard,
  int32_t status,
  const char *prefix
) {
  DWORD error_code = GetLastError();
  char *system_message = NULL;
  DWORD message_len = FormatMessageA(
    FORMAT_MESSAGE_ALLOCATE_BUFFER |
      FORMAT_MESSAGE_FROM_SYSTEM |
      FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL,
    error_code,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    (LPSTR)&system_message,
    0,
    NULL
  );
  if (message_len == 0 || system_message == NULL) {
    keepawake_set_error(
      guard,
      status,
      "%s (GetLastError=%lu)",
      prefix,
      (unsigned long)error_code
    );
    return;
  }
  keepawake_set_error(
    guard,
    status,
    "%s: %s",
    prefix,
    system_message
  );
  LocalFree(system_message);
}

static uint32_t keepawake_windows_state_for_scope(int32_t scope) {
  uint32_t state = ES_CONTINUOUS;
  if (scope == keepawake_SCOPE_SYSTEM ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    state |= ES_SYSTEM_REQUIRED;
  }
  if (scope == keepawake_SCOPE_DISPLAY ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    state |= ES_DISPLAY_REQUIRED;
  }
  return state;
}

void keepawake_platform_release(keepawake_guard_t *guard) {
  if (!guard->active) {
    return;
  }
  if (SetThreadExecutionState(ES_CONTINUOUS) == 0) {
    keepawake_set_windows_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to release SetThreadExecutionState"
    );
    return;
  }
  guard->active = 0;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
}

void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
) {
  (void)reason;
  uint32_t requested_state = keepawake_windows_state_for_scope(scope);
  if (SetThreadExecutionState(requested_state) == 0) {
    keepawake_set_windows_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to activate SetThreadExecutionState"
    );
    return;
  }
  guard->requested_state = requested_state;
  guard->active = 1;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
}

#endif
