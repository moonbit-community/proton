#include "../native_stub.h"

static char *keepawake_test_duplicate_string(const char *text) {
  size_t len = strlen(text);
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, text, len + 1);
  return copy;
}

/* Test-only finalizer: synthetic guards never own platform resources, so only
   the duplicated last_error string is released here. Unlike the shared
   finalizer it must not call keepawake_platform_release. */
static void keepawake_test_guard_finalize(void *payload) {
  keepawake_guard_t *guard = (keepawake_guard_t *)payload;
  if (guard->last_error != NULL) {
    free(guard->last_error);
    guard->last_error = NULL;
  }
}

// Test-only constructor for synthetic guards. Synthetic guards must be
// created with active=0: the shared finalizer runs keepawake_platform_release,
// which participates in the Windows process-wide refcount, and a synthetic
// active=1 guard would decrement counters it never incremented.
MOONBIT_FFI_EXPORT
keepawake_guard_t *moonbit_keepawake_test_guard_make(
  int32_t active,
  int32_t status,
  moonbit_bytes_t last_error,
  int32_t scope
) {
  keepawake_guard_t *guard =
    (keepawake_guard_t *)moonbit_make_external_object(
      keepawake_test_guard_finalize,
      (uint32_t)sizeof(keepawake_guard_t)
    );
  (void)active;
  memset(guard, 0, sizeof(*guard));
  guard->active = 0;
  guard->status = status;
  guard->scope = scope;
  if (last_error != NULL && last_error[0] != '\0') {
    guard->last_error =
      keepawake_test_duplicate_string((const char *)last_error);
  }
  return guard;
}
