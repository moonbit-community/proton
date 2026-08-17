#include "../proton_engine.h"

int32_t proton_engine_take_platform_event(proton_engine_runtime_t *runtime,
                                          char *buffer,
                                          size_t buffer_len,
                                          int32_t *out_present) {
  (void)runtime;
  (void)buffer;
  (void)buffer_len;
  if (out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_present = 0;
  return PROTON_OK;
}
