#include "native_stub.h"

#ifdef _WIN32
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0600
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0600 /* SRWLOCK requires Vista+ */
#endif
#include <windows.h>

// SetThreadExecutionState manages per-thread flags while guards are a
// process-level concept, so transitions are serialized through a
// process-wide refcount: the union of all live guards' scopes is applied on
// every transition, and the bare ES_CONTINUOUS clear only happens when the
// last guard releases. This keeps same-thread multi-guard use correct —
// releasing one guard no longer disarms the others.
//
// The flags still live on whichever thread applies them: releasing from a
// different thread (notably the GC finalizer) keeps the counts correct but
// may leave the applying thread's flags set until that thread exits.
// Releasing a guard explicitly from the acquiring thread is the recommended
// path.
static SRWLOCK g_keepawake_lock = SRWLOCK_INIT;
static LONG g_keepawake_system_count = 0;
static LONG g_keepawake_display_count = 0;

static uint32_t keepawake_windows_union_state(
  LONG system_count,
  LONG display_count
) {
  uint32_t state = ES_CONTINUOUS;
  if (system_count > 0) {
    state |= ES_SYSTEM_REQUIRED;
  }
  if (display_count > 0) {
    state |= ES_DISPLAY_REQUIRED;
  }
  return state;
}

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
  AcquireSRWLockExclusive(&g_keepawake_lock);
  if (!guard->active) {
    ReleaseSRWLockExclusive(&g_keepawake_lock);
    return;
  }
  // Commit the decrement only after a successful API call so a failed
  // release leaves the counters consistent with the still-active guard.
  LONG system_count = g_keepawake_system_count;
  LONG display_count = g_keepawake_display_count;
  if (guard->scope == keepawake_SCOPE_SYSTEM ||
      guard->scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    if (system_count > 0) {
      system_count--;
    }
  }
  if (guard->scope == keepawake_SCOPE_DISPLAY ||
      guard->scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    if (display_count > 0) {
      display_count--;
    }
  }
  if (SetThreadExecutionState(
        keepawake_windows_union_state(system_count, display_count)
      ) == 0) {
    keepawake_set_windows_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to release SetThreadExecutionState"
    );
    ReleaseSRWLockExclusive(&g_keepawake_lock);
    return;
  }
  g_keepawake_system_count = system_count;
  g_keepawake_display_count = display_count;
  guard->active = 0;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
  ReleaseSRWLockExclusive(&g_keepawake_lock);
}

void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
) {
  (void)reason;
  uint32_t requested_state = keepawake_windows_state_for_scope(scope);
  AcquireSRWLockExclusive(&g_keepawake_lock);
  // Commit the increment only after a successful API call so a failed start
  // leaves the counters consistent with the still-inactive guard.
  LONG system_count = g_keepawake_system_count;
  LONG display_count = g_keepawake_display_count;
  if (scope == keepawake_SCOPE_SYSTEM ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    system_count++;
  }
  if (scope == keepawake_SCOPE_DISPLAY ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    display_count++;
  }
  if (SetThreadExecutionState(
        keepawake_windows_union_state(system_count, display_count)
      ) == 0) {
    keepawake_set_windows_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to activate SetThreadExecutionState"
    );
    ReleaseSRWLockExclusive(&g_keepawake_lock);
    return;
  }
  g_keepawake_system_count = system_count;
  g_keepawake_display_count = display_count;
  guard->requested_state = requested_state;
  guard->active = 1;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
  ReleaseSRWLockExclusive(&g_keepawake_lock);
}

#endif
