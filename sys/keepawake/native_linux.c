#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)
/* Linux inhibition is owned by the MoonBit async process scope. */
void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
) {
  (void)reason;
  (void)scope;
  keepawake_set_error(guard, keepawake_STATUS_BACKEND_UNAVAILABLE,
                      "Linux keep-awake uses the async process backend");
}

void keepawake_platform_release(keepawake_guard_t *guard) {
  (void)guard;
}
#endif
