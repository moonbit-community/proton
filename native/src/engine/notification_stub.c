#include "../proton_engine.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

static void proton_notification_set_message(char *error,
                                            size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message);
  }
}

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len) {
  (void)error;
  (void)error_len;
  if (out_supported != NULL) {
    *out_supported = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_show(const char *title,
                                        const char *body,
                                        const char *payload,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len) {
  (void)title;
  (void)body;
  (void)payload;
  (void)has_payload;
  proton_notification_set_message(
      error, error_len,
      "native notifications are not implemented on this platform");
  // TODO: Implement native notifications on Windows and Linux.
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_notification_poll_click(
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required,
    int32_t *out_has_payload,
    int32_t *out_available,
    char *error,
    size_t error_len) {
  (void)buffer;
  (void)buffer_len;
  (void)error;
  (void)error_len;
  if (out_required != NULL) {
    *out_required = 0;
  }
  if (out_has_payload != NULL) {
    *out_has_payload = 0;
  }
  if (out_available != NULL) {
    *out_available = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_cleanup(char *error, size_t error_len) {
  (void)error;
  (void)error_len;
  return PROTON_OK;
}
