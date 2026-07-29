#include "native_stub.h"

#ifdef __APPLE__
#include <dlfcn.h>

typedef int32_t IOReturn;
typedef uint32_t IOPMAssertionID;
typedef const void *CFStringRef;
typedef const void *CFAllocatorRef;
typedef uint32_t CFStringEncoding;

typedef IOReturn (*keepawake_iopm_assertion_create_with_name_fn)(
  CFStringRef,
  uint32_t,
  CFStringRef,
  IOPMAssertionID *
);
typedef IOReturn (*keepawake_iopm_assertion_release_fn)(IOPMAssertionID);
typedef CFStringRef (*keepawake_cfstring_create_with_cstring_fn)(
  CFAllocatorRef,
  const char *,
  CFStringEncoding
);
typedef void (*keepawake_cfrelease_fn)(const void *);

static const CFStringEncoding keepawake_k_cfstring_encoding_utf8 = 0x08000100U;

void keepawake_platform_release(keepawake_guard_t *guard) {
  void *core_foundation = dlopen(
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    RTLD_LAZY | RTLD_LOCAL
  );
  void *iokit = dlopen(
    "/System/Library/Frameworks/IOKit.framework/IOKit",
    RTLD_LAZY | RTLD_LOCAL
  );
  keepawake_iopm_assertion_release_fn release_assertion =
    iokit == NULL ? NULL :
    (keepawake_iopm_assertion_release_fn)dlsym(iokit, "IOPMAssertionRelease");
  if (release_assertion == NULL) {
    if (core_foundation != NULL) {
      dlclose(core_foundation);
    }
    if (iokit != NULL) {
      dlclose(iokit);
    }
    keepawake_set_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to load macOS power management release symbols"
    );
    return;
  }

  if (guard->has_system_assertion) {
    if (release_assertion(guard->system_assertion_id) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to release the macOS system sleep assertion"
      );
      goto cleanup;
    }
    guard->has_system_assertion = 0;
  }
  if (guard->has_display_assertion) {
    if (release_assertion(guard->display_assertion_id) != 0) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to release the macOS display sleep assertion"
      );
      goto cleanup;
    }
    guard->has_display_assertion = 0;
  }

  guard->active = 0;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);

cleanup:
  if (core_foundation != NULL) {
    dlclose(core_foundation);
  }
  if (iokit != NULL) {
    dlclose(iokit);
  }
}

void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
) {
  void *core_foundation = dlopen(
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    RTLD_LAZY | RTLD_LOCAL
  );
  void *iokit = dlopen(
    "/System/Library/Frameworks/IOKit.framework/IOKit",
    RTLD_LAZY | RTLD_LOCAL
  );
  keepawake_cfstring_create_with_cstring_fn make_cfstring =
    core_foundation == NULL ? NULL :
    (keepawake_cfstring_create_with_cstring_fn)dlsym(
      core_foundation,
      "CFStringCreateWithCString"
    );
  keepawake_cfrelease_fn cfrelease =
    core_foundation == NULL ? NULL :
    (keepawake_cfrelease_fn)dlsym(core_foundation, "CFRelease");
  keepawake_iopm_assertion_create_with_name_fn create_assertion =
    iokit == NULL ? NULL :
    (keepawake_iopm_assertion_create_with_name_fn)dlsym(
      iokit,
      "IOPMAssertionCreateWithName"
    );
  CFStringRef reason_string = NULL;
  CFStringRef system_type = NULL;
  CFStringRef display_type = NULL;

  if (make_cfstring == NULL || cfrelease == NULL || create_assertion == NULL) {
    keepawake_set_error(
      guard,
      keepawake_STATUS_BACKEND_UNAVAILABLE,
      "Failed to load macOS power management frameworks"
    );
    goto cleanup;
  }

  reason_string = make_cfstring(
    NULL,
    reason,
    keepawake_k_cfstring_encoding_utf8
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
    system_type = make_cfstring(
      NULL,
      "PreventUserIdleSystemSleep",
      keepawake_k_cfstring_encoding_utf8
    );
    if (system_type == NULL ||
        create_assertion(
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
    display_type = make_cfstring(
      NULL,
      "PreventUserIdleDisplaySleep",
      keepawake_k_cfstring_encoding_utf8
    );
    if (display_type == NULL ||
        create_assertion(
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
  if (reason_string != NULL && cfrelease != NULL) {
    cfrelease(reason_string);
  }
  if (system_type != NULL && cfrelease != NULL) {
    cfrelease(system_type);
  }
  if (display_type != NULL && cfrelease != NULL) {
    cfrelease(display_type);
  }
  if (core_foundation != NULL) {
    dlclose(core_foundation);
  }
  if (iokit != NULL) {
    dlclose(iokit);
  }
}

#endif
