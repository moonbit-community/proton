#include "proton_engine.h"
#include "proton_internal.h"
#include "proton_state.h"

#include <stddef.h>
#include <stdint.h>

/* Application process metrics describe the runtime's own processes, so this
   surface resolves the active runtime instead of taking a window or view
   handle. Chromium owns the measurement; everything below is state checking
   and status translation. */
static int32_t proton_app_metrics_require_runtime(void) {
  proton_runtime_slot_t *runtime = proton_get_active_runtime();
  if (runtime == NULL || runtime->lifecycle != PROTON_RUNTIME_ACTIVE) {
    return proton_set_error(PROTON_ERR_NOT_INITIALIZED,
                            "application runtime is not running");
  }
  return proton_require_runtime_owner_thread(runtime);
}

int32_t proton_app_metrics_count(int32_t *out_count) {
  int32_t status = proton_app_metrics_require_runtime();
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_process_metrics_count(
      out_count, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_app_metric_at(
    int32_t index, int64_t *out_task_id, int32_t *out_process_type,
    double *out_cpu_percent, int64_t *out_memory_bytes, char *name_buffer,
    int32_t name_buffer_len, int32_t *out_name_required) {
  int32_t status = proton_app_metrics_require_runtime();
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_process_metric_at(
      index, out_task_id, out_process_type, out_cpu_percent, out_memory_bytes,
      name_buffer, name_buffer_len, out_name_required, engine_error,
      sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}
