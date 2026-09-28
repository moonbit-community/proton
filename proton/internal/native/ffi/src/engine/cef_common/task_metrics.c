#include "../../proton_engine.h"
#include "message.h"

#include "include/capi/cef_task_manager_capi.h"
#include "include/internal/cef_string.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Browser task metrics come from CEF's task manager, the same source
   Chromium's own task manager page reads. The functions are UI-thread only,
   and Chromium samples CPU and memory only while an observer is attached, so
   the manager is created on the first query and kept until the runtime shuts
   down. Releasing it between queries would clear the sampled values, and every
   answer would come back empty. */
static cef_task_manager_t *g_task_metrics_manager = NULL;

static int32_t proton_task_metrics_manager(cef_task_manager_t **out_manager,
                                              char *error, size_t error_len) {
  *out_manager = NULL;
  if (g_task_metrics_manager == NULL) {
    g_task_metrics_manager = cef_task_manager_get();
  }
  if (g_task_metrics_manager == NULL) {
    proton_engine_set_message(error, error_len,
                              "process metrics require the UI thread");
    return PROTON_ERR_WRONG_THREAD;
  }
  *out_manager = g_task_metrics_manager;
  return PROTON_OK;
}

void proton_engine_task_metrics_stop(void) {
  if (g_task_metrics_manager != NULL) {
    g_task_metrics_manager->base.release(
        (cef_base_ref_counted_t *)g_task_metrics_manager);
    g_task_metrics_manager = NULL;
  }
}

/* CEF carries task titles as UTF-16, the string type its shipped builds
   select. Titles are optional, so an empty one stays empty. */
static int32_t proton_task_metrics_copy_title(const cef_string_t *title,
                                                 char *name_buffer,
                                                 int32_t name_buffer_len,
                                                 int32_t *out_required_len,
                                                 char *error,
                                                 size_t error_len) {
#if defined(CEF_STRING_TYPE_UTF16)
  cef_string_utf8_t utf8 = {0};
  if (title->str != NULL && title->length > 0 &&
      !cef_string_utf16_to_utf8(title->str, title->length, &utf8)) {
    proton_engine_set_message(error, error_len,
                              "failed to decode the task title");
    return PROTON_ERR_ENGINE;
  }
#elif defined(CEF_STRING_TYPE_WIDE)
  cef_string_utf8_t utf8 = {0};
  if (title->str != NULL && title->length > 0 &&
      !cef_string_wide_to_utf8(title->str, title->length, &utf8)) {
    proton_engine_set_message(error, error_len,
                              "failed to decode the task title");
    return PROTON_ERR_ENGINE;
  }
#else
  cef_string_utf8_t utf8 = {0};
  if (title->str != NULL && title->length > 0 &&
      !cef_string_utf8_set(title->str, title->length, &utf8, 1)) {
    proton_engine_set_message(error, error_len,
                              "failed to decode the task title");
    return PROTON_ERR_ENGINE;
  }
#endif
  if (utf8.length > (size_t)INT32_MAX) {
    cef_string_utf8_clear(&utf8);
    proton_engine_set_message(error, error_len,
                              "task title exceeds the supported range");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  *out_required_len = (int32_t)utf8.length;
  if (name_buffer != NULL && name_buffer_len > (int32_t)utf8.length) {
    memcpy(name_buffer, utf8.str, utf8.length);
    name_buffer[utf8.length] = '\0';
  }
  cef_string_utf8_clear(&utf8);
  return PROTON_OK;
}

int32_t proton_engine_task_metrics_count(int32_t *out_count, char *error,
                                            size_t error_len) {
  if (out_count == NULL) {
    proton_engine_set_message(error, error_len, "out_count is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = 0;
  cef_task_manager_t *manager = NULL;
  int32_t status = proton_task_metrics_manager(&manager, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  size_t count = manager->get_tasks_count(manager);
  if (count > (size_t)INT32_MAX) {
    proton_engine_set_message(error, error_len,
                              "task count exceeds the supported range");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  *out_count = (int32_t)count;
  return PROTON_OK;
}

/* Translate at the CEF boundary: its enum values may change with the API
   version selected by the headers. Never pass those ordinals to MoonBit. */
static proton_task_type_t proton_task_type(cef_task_type_t type) {
  switch (type) {
  case CEF_TASK_TYPE_BROWSER: return PROTON_TASK_BROWSER;
  case CEF_TASK_TYPE_GPU: return PROTON_TASK_GPU;
  case CEF_TASK_TYPE_ZYGOTE: return PROTON_TASK_ZYGOTE;
  case CEF_TASK_TYPE_UTILITY: return PROTON_TASK_UTILITY;
  case CEF_TASK_TYPE_RENDERER: return PROTON_TASK_RENDERER;
  case CEF_TASK_TYPE_EXTENSION: return PROTON_TASK_EXTENSION;
  case CEF_TASK_TYPE_GUEST: return PROTON_TASK_GUEST;
#if CEF_API_ADDED(14000)
  case CEF_TASK_TYPE_PLUGIN_DEPRECATED: return PROTON_TASK_PLUGIN;
#else
  case CEF_TASK_TYPE_PLUGIN: return PROTON_TASK_PLUGIN;
#endif
  case CEF_TASK_TYPE_SANDBOX_HELPER: return PROTON_TASK_SANDBOX_HELPER;
  case CEF_TASK_TYPE_DEDICATED_WORKER:
  case CEF_TASK_TYPE_SHARED_WORKER:
  case CEF_TASK_TYPE_SERVICE_WORKER: return PROTON_TASK_WORKER;
  default: return PROTON_TASK_UNKNOWN;
  }
}

int32_t proton_engine_task_metric_at(
    int32_t index, int64_t *out_task_id, int32_t *out_task_type,
    double *out_process_cpu_percent, int64_t *out_process_memory_bytes, char *name_buffer,
    int32_t name_buffer_len, int32_t *out_required_len, char *error,
    size_t error_len) {
  if (index < 0 || out_task_id == NULL || out_task_type == NULL ||
      out_process_cpu_percent == NULL || out_process_memory_bytes == NULL ||
      out_required_len == NULL || name_buffer_len < 0 ||
      (name_buffer == NULL && name_buffer_len != 0)) {
    proton_engine_set_message(error, error_len, "invalid process metric query");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_task_id = 0;
  *out_task_type = 0;
  *out_process_cpu_percent = 0;
  *out_process_memory_bytes = -1;
  *out_required_len = 0;
  if (name_buffer != NULL && name_buffer_len > 0) {
    name_buffer[0] = '\0';
  }
  cef_task_manager_t *manager = NULL;
  int32_t status = proton_task_metrics_manager(&manager, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  size_t count = manager->get_tasks_count(manager);
  if (count == 0 || (size_t)index >= count) {
    proton_engine_set_message(error, error_len,
                              "process metric index is out of range");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int64_t *task_ids = (int64_t *)calloc(count, sizeof(int64_t));
  if (task_ids == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate the task id buffer");
    return PROTON_ERR_QUEUE_FAILED;
  }
  size_t written = count;
  int listed = manager->get_task_ids_list(manager, &written, task_ids);
  if (!listed || (size_t)index >= written) {
    free(task_ids);
    proton_engine_set_message(error, error_len,
                              "failed to read the task id list");
    return PROTON_ERR_ENGINE;
  }
  cef_task_info_t info;
  memset(&info, 0, sizeof(info));
  info.size = sizeof(info);
  int described = manager->get_task_info(manager, task_ids[index], &info);
  free(task_ids);
  if (!described) {
    proton_engine_set_message(error, error_len,
                              "failed to read the task information");
    return PROTON_ERR_ENGINE;
  }
  *out_task_id = info.id;
  *out_task_type = (int32_t)proton_task_type(info.type);
  *out_process_cpu_percent = info.cpu_usage;
  /* CEF reports zero for a process it has not measured yet, while its own
     documentation reserves -1 for that state. Keep the documented contract so
     applications can tell a missing sample from a measured one. */
  *out_process_memory_bytes = info.memory > 0 ? info.memory : -1;
  status = proton_task_metrics_copy_title(
      &info.title, name_buffer, name_buffer_len, out_required_len, error,
      error_len);
  cef_string_clear(&info.title);
  return status;
}
