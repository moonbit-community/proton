#include "proton_native.h"

#include "proton_internal.h"

#include <stddef.h>

int32_t proton_app_run(proton_app_entry_t entry) {
  if (entry == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "application entry is required");
  }
  // TODO: Give Windows and Linux platform-owned UI runners. Until then, keep
  // their existing single-thread event-loop architecture behind the same ABI.
  entry();
  return proton_set_error(PROTON_OK, NULL);
}
