#include "native_stub.h"

static char *keepawake_duplicate_string(const char *text) {
  size_t len = strlen(text);
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, text, len + 1);
  return copy;
}

void keepawake_clear_error(keepawake_guard_t *guard) {
  if (guard->last_error != NULL) {
    free(guard->last_error);
    guard->last_error = NULL;
  }
}

void keepawake_set_error(
  keepawake_guard_t *guard,
  int32_t status,
  const char *format,
  ...
) {
  char stack_buffer[1024];
  va_list args;
  keepawake_clear_error(guard);
  va_start(args, format);
  vsnprintf(stack_buffer, sizeof(stack_buffer), format, args);
  va_end(args);
  guard->last_error = keepawake_duplicate_string(stack_buffer);
  guard->status = status;
}

moonbit_bytes_t keepawake_make_error_bytes(const char *text) {
  if (text == NULL || text[0] == '\0') {
    return moonbit_make_bytes(0, 0);
  }
  int32_t len = (int32_t)strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, (size_t)len);
  return bytes;
}

static void keepawake_guard_finalize(void *payload) {
  keepawake_guard_t *guard = (keepawake_guard_t *)payload;
  keepawake_platform_release(guard);
  keepawake_clear_error(guard);
}

MOONBIT_FFI_EXPORT
keepawake_guard_t *moonbit_keepawake_guard_create(
  moonbit_bytes_t reason,
  int32_t scope
) {
  keepawake_guard_t *guard =
    (keepawake_guard_t *)moonbit_make_external_object(
      keepawake_guard_finalize,
      (uint32_t)sizeof(keepawake_guard_t)
    );
  memset(guard, 0, sizeof(*guard));
  guard->scope = scope;
  keepawake_platform_start(guard, (const char *)reason, scope);
  return guard;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_keepawake_guard_is_active(keepawake_guard_t *guard) {
  return guard->active;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_keepawake_guard_status(keepawake_guard_t *guard) {
  return guard->status;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_keepawake_guard_scope_code(keepawake_guard_t *guard) {
  return guard->scope;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_keepawake_guard_last_error(keepawake_guard_t *guard) {
  return keepawake_make_error_bytes(guard->last_error);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_keepawake_guard_release(keepawake_guard_t *guard) {
  keepawake_platform_release(guard);
  return guard->status;
}
