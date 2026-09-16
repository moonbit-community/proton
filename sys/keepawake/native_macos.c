#include "native_stub.h"

#ifdef __APPLE__
#include <IOKit/pwr_mgt/IOPMLib.h>

void keepawake_platform_release(keepawake_guard_t *guard) {
  if (guard->has_system_assertion) {
    if (IOPMAssertionRelease(guard->system_assertion_id) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to release the macOS system sleep assertion"
      );
      return;
    }
    guard->has_system_assertion = 0;
  }
  if (guard->has_display_assertion) {
    if (IOPMAssertionRelease(guard->display_assertion_id) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to release the macOS display sleep assertion"
      );
      return;
    }
    guard->has_display_assertion = 0;
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
  CFStringRef reason_string = NULL;
  CFStringRef system_type = NULL;
  CFStringRef display_type = NULL;

  reason_string = CFStringCreateWithCString(
    NULL,
    reason,
    kCFStringEncodingUTF8
  );
  if (reason_string == NULL) {
    keepawake_set_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to create the macOS reason string"
    );
    goto cleanup;
  }

  if (scope == keepawake_SCOPE_SYSTEM ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    system_type = CFStringCreateWithCString(
      NULL,
      "PreventUserIdleSystemSleep",
      kCFStringEncodingUTF8
    );
    if (system_type == NULL ||
        IOPMAssertionCreateWithName(
          system_type,
          255,
          reason_string,
          &guard->system_assertion_id
        ) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to create the macOS system sleep assertion"
      );
      goto cleanup;
    }
    guard->has_system_assertion = 1;
  }

  if (scope == keepawake_SCOPE_DISPLAY ||
      scope == keepawake_SCOPE_SYSTEM_AND_DISPLAY) {
    display_type = CFStringCreateWithCString(
      NULL,
      "PreventUserIdleDisplaySleep",
      kCFStringEncodingUTF8
    );
    if (display_type == NULL ||
        IOPMAssertionCreateWithName(
          display_type,
          255,
          reason_string,
          &guard->display_assertion_id
        ) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to create the macOS display sleep assertion"
      );
      if (guard->has_system_assertion) {
        keepawake_platform_release(guard);
      }
      goto cleanup;
    }
    guard->has_display_assertion = 1;
  }

  guard->active = 1;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);

cleanup:
  if (reason_string != NULL) {
    CFRelease(reason_string);
  }
  if (system_type != NULL) {
    CFRelease(system_type);
  }
  if (display_type != NULL) {
    CFRelease(display_type);
  }
}

#endif
