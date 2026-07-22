#include "proton_native.h"
#include "../src/engine/cef_common/bridge_lifecycle.h"
#include "../src/proton_json.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <direct.h>
#define mkdir_one(path) _mkdir(path)
#define PATH_SEP "\\"
#define EXPECTED_PLATFORM "\"platform\":\"windows\""
#elif defined(__APPLE__)
#include <pthread.h>
#include <sys/stat.h>
#define mkdir_one(path) mkdir(path, 0777)
#define PATH_SEP "/"
#define EXPECTED_PLATFORM "\"platform\":\"macos\""
#else
#include <pthread.h>
#include <sys/stat.h>
#define mkdir_one(path) mkdir(path, 0777)
#define PATH_SEP "/"
#define EXPECTED_PLATFORM "\"platform\":\"linux\""
#endif

static int fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  return 1;
}

static int g_runtime_available = 0;
static int expect_status(const char *label, int32_t actual, int32_t expected);

static int expect_valid_json(const char *label, const char *json) {
  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, json)) {
    fprintf(stderr, "%s: invalid JSON\n", label);
    return 1;
  }
  proton_json_dispose(&doc);
  return 0;
}

static int expect_bridge_lifecycle_state(void) {
  static const char first_failure[] =
      "{\"abi_version\":1,\"stage\":\"bootstrap\","
      "\"code\":\"first_failure\",\"message\":\"first\","
      "\"page_instance\":\"page-1\",\"url\":\"proton://app/\","
      "\"details_truncated\":false}";
  static const char second_failure[] =
      "{\"abi_version\":1,\"stage\":\"initialization\","
      "\"code\":\"second_failure\",\"message\":\"second\","
      "\"page_instance\":\"page-1\",\"url\":\"proton://app/\","
      "\"details_truncated\":false}";
  proton_engine_bridge_lifecycle_t lifecycle;
  proton_engine_bridge_lifecycle_init(&lifecycle);
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-1", "proton://app/", NULL) ||
      !proton_engine_bridge_lifecycle_update(
          &lifecycle, "ready", "page-1", "proton://app/", NULL)) {
    return fail("bridge lifecycle rejected the ready transition");
  }
  char ready_state[512];
  int32_t required = 0;
  if (proton_engine_bridge_lifecycle_state_json(
          &lifecycle, ready_state, (int32_t)sizeof(ready_state), &required) !=
          PROTON_OK ||
      strstr(ready_state, "\"outcome\":\"ready\"") == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle did not expose the ready transition");
  }
  if (proton_engine_bridge_lifecycle_update(
          &lifecycle, "failed", "page-1", "proton://app/", first_failure)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle changed a terminal outcome");
  }
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-failure-1", "proton://app/", NULL) ||
      !proton_engine_bridge_lifecycle_update(
          &lifecycle, "failed", "page-failure-1", "proton://app/",
          first_failure)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle rejected the first failure");
  }
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-failure-2", "proton://app/", NULL) ||
      !proton_engine_bridge_lifecycle_update(
          &lifecycle, "failed", "page-failure-2", "proton://app/",
          second_failure)) {
    return fail("bridge lifecycle rejected a valid transition");
  }
  required = 0;
  if (expect_status("bridge failure length probe",
                    proton_engine_bridge_lifecycle_take_failure_json(
                        &lifecycle, NULL, 0, &required),
                    PROTON_ERR_BUFFER_TOO_SMALL) ||
      required <= 0) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return 1;
  }
  char *failure = (char *)calloc((size_t)required + 1, 1);
  if (failure == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("failed to allocate bridge failure test buffer");
  }
  if (expect_status("bridge failure consume",
                    proton_engine_bridge_lifecycle_take_failure_json(
                        &lifecycle, failure, required + 1, &required),
                    PROTON_OK) ||
      strstr(failure, "first_failure") == NULL ||
      strstr(failure, "second_failure") != NULL ||
      strstr(failure, "\"page_instance\":\"page-failure-1\"") == NULL ||
      strstr(failure, "\"additional_failure_count\":1") == NULL) {
    free(failure);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge failure latch did not preserve the first failure");
  }
  free(failure);
  if (expect_status("bridge failure consumed",
                    proton_engine_bridge_lifecycle_take_failure_json(
                        &lifecycle, NULL, 0, &required),
                    PROTON_EVENT_NONE)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return 1;
  }
  proton_engine_bridge_lifecycle_update(
      &lifecycle, "pending", "page-2", "proton://app/reload", NULL);
  if (proton_engine_bridge_lifecycle_update(
          &lifecycle, "ready", "page-1", "proton://app/", NULL)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle accepted a stale terminal outcome");
  }
  char state[512];
  if (expect_status("bridge lifecycle state",
                    proton_engine_bridge_lifecycle_state_json(
                        &lifecycle, state, (int32_t)sizeof(state), &required),
                    PROTON_OK) ||
      strstr(state, "\"outcome\":\"pending\"") == NULL ||
      strstr(state, "\"page_instance\":\"page-2\"") == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle state lost the current page");
  }
  proton_engine_bridge_lifecycle_dispose(&lifecycle);

  proton_engine_bridge_lifecycle_init(&lifecycle);
  if (proton_engine_bridge_lifecycle_report_load_failure(
          &lifecycle, "proton://app/replaced", "navigation aborted", 1) ||
      proton_engine_bridge_lifecycle_revision(&lifecycle) != 0 ||
      proton_engine_bridge_lifecycle_state_json(
          &lifecycle, state, (int32_t)sizeof(state), &required) != PROTON_OK ||
      strstr(state, "\"outcome\":\"none\"") == NULL ||
      proton_engine_bridge_lifecycle_take_failure_json(
          &lifecycle, NULL, 0, &required) != PROTON_EVENT_NONE) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("cancelled navigation changed bridge lifecycle state");
  }
  if (!proton_engine_bridge_lifecycle_report_load_failure(
          &lifecycle, "proton://app/missing", "not found", 0) ||
      proton_engine_bridge_lifecycle_state_json(
          &lifecycle, state, (int32_t)sizeof(state), &required) != PROTON_OK ||
      strstr(state, "\"outcome\":\"failed\"") == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("load failure did not change bridge lifecycle state");
  }
  proton_engine_bridge_lifecycle_dispose(&lifecycle);

  proton_engine_bridge_lifecycle_init(&lifecycle);
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-ready", "proton://app/", NULL) ||
      !proton_engine_bridge_lifecycle_update(
          &lifecycle, "ready", "page-ready", "proton://app/", NULL) ||
      !proton_engine_bridge_lifecycle_report_browser_failure(
          &lifecycle, "proton://app/", "renderer_process_terminated",
          "renderer process terminated", 0)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("browser failure did not replace a terminated ready context");
  }
  if (proton_engine_bridge_lifecycle_state_json(
          &lifecycle, state, (int32_t)sizeof(state), &required) != PROTON_OK ||
      strstr(state, "\"outcome\":\"failed\"") == NULL ||
      strstr(state, "\"page_instance\":\"browser-process-") == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("browser failure did not expose a synthetic failed attempt");
  }
  if (proton_engine_bridge_lifecycle_update(
          &lifecycle, "unknown", "page-invalid", "proton://app/", NULL)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle accepted an unknown outcome");
  }
  proton_engine_bridge_lifecycle_dispose(&lifecycle);

  size_t stack_len = 70000;
  char *large_failure = (char *)malloc(stack_len + 256);
  if (large_failure == NULL) {
    return fail("failed to allocate large bridge diagnostic");
  }
  int prefix = snprintf(
      large_failure, stack_len + 256,
      "{\"abi_version\":1,\"stage\":\"initialization\","
      "\"code\":\"large\",\"message\":\"large\","
      "\"page_instance\":\"page-large\",\"url\":\"proton://app/\","
      "\"stack\":\"");
  memset(large_failure + prefix, 'x', stack_len);
  static const char large_suffix[] = "\",\"details_truncated\":false}";
  memcpy(large_failure + prefix + stack_len, large_suffix,
         sizeof(large_suffix));
  proton_engine_bridge_lifecycle_init(&lifecycle);
  proton_engine_bridge_lifecycle_update(
      &lifecycle, "pending", "page-large", "proton://app/", NULL);
  proton_engine_bridge_lifecycle_update(
      &lifecycle, "failed", "page-large", "proton://app/", large_failure);
  free(large_failure);
  required = 0;
  if (expect_status("large bridge failure probe",
                    proton_engine_bridge_lifecycle_take_failure_json(
                        &lifecycle, NULL, 0, &required),
                    PROTON_ERR_BUFFER_TOO_SMALL) ||
      required <= 0 || required >= 65536) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("large bridge diagnostic was not bounded");
  }
  failure = (char *)calloc((size_t)required + 1, 1);
  if (failure == NULL ||
      proton_engine_bridge_lifecycle_take_failure_json(
          &lifecycle, failure, required + 1, &required) != PROTON_OK ||
      strstr(failure, "\"details_truncated\":true") == NULL ||
      strstr(failure, "\"stage\":\"initialization\"") == NULL ||
      strstr(failure, "\"code\":\"large\"") == NULL ||
      strstr(failure, "\"message\":\"large\"") == NULL ||
      expect_valid_json("large bridge diagnostic", failure)) {
    free(failure);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("large bridge diagnostic did not report truncation");
  }
  free(failure);
  proton_engine_bridge_lifecycle_dispose(&lifecycle);
  return 0;
}

static int expect_status(const char *label, int32_t actual, int32_t expected) {
  if (actual != expected) {
    fprintf(stderr, "%s: expected %d, got %d\n", label, expected, actual);
    return 1;
  }
  return 0;
}

static int expect_last_error_contains(const char *needle) {
  char buffer[256];
  int32_t required = proton_last_error_message(buffer, (int32_t)sizeof(buffer));
  if (required <= 0) {
    return fail("expected last_error to be non-empty");
  }
  if (strstr(buffer, needle) == NULL) {
    fprintf(stderr, "expected last_error to contain '%s', got '%s'\n", needle,
            buffer);
    return 1;
  }
  return 0;
}

static int expect_runtime_info(void) {
  char tiny[1];
  int32_t required = 0;
  int32_t status = proton_runtime_info_json(tiny, 1, &required);
  if (expect_status("runtime_info small buffer", status,
                    PROTON_ERR_BUFFER_TOO_SMALL)) {
    return 1;
  }
  if (required <= 0) {
    return fail("runtime_info did not report required length");
  }
  char buffer[256];
  status = proton_runtime_info_json(buffer, (int32_t)sizeof(buffer), &required);
  if (expect_status("runtime_info", status, PROTON_OK)) {
    return 1;
  }
  int has_abi_only = strstr(buffer, "\"runtime_available\":false") != NULL &&
                     strstr(buffer, "\"build_mode\":\"abi-only\"") != NULL;
  int has_runtime = strstr(buffer, "\"runtime_available\":true") != NULL &&
                    strstr(buffer, "\"build_mode\":\"runtime\"") != NULL;
  int has_titlebar_overlay =
      strstr(buffer, "\"titlebar_overlay\"") != NULL;
  if (strstr(buffer, "\"abi_version\":1") == NULL ||
      (!has_abi_only && !has_runtime) ||
      strstr(buffer, "\"base_abi\"") == NULL ||
      strstr(buffer, "\"event_polling\"") == NULL ||
      strstr(buffer, "\"bridge_polling\"") == NULL ||
      strstr(buffer, EXPECTED_PLATFORM) == NULL) {
    fprintf(stderr, "unexpected runtime info: %s\n", buffer);
    return 1;
  }
#if defined(_WIN32) || defined(__APPLE__) || defined(__linux__)
  if (has_titlebar_overlay != has_runtime) {
    fprintf(stderr, "unexpected titlebar overlay capability: %s\n", buffer);
    return 1;
  }
#else
  if (has_titlebar_overlay) {
    fprintf(stderr, "unsupported titlebar overlay capability: %s\n", buffer);
    return 1;
  }
#endif
  g_runtime_available = has_runtime;
  return 0;
}

static int write_empty_file(const char *path) {
  FILE *file = fopen(path, "wb");
  if (file == NULL) {
    fprintf(stderr, "failed to create file: %s\n", path);
    return 1;
  }
  fclose(file);
  return 0;
}

static int prepare_probe_layout(char *config,
                                size_t config_len,
                                char *installed_config,
                                size_t installed_config_len,
                                char *missing_helper_config,
                                size_t missing_helper_config_len) {
#ifdef __APPLE__
  const char *helper_path = "probe-helper";
  mkdir_one("probe-runtime");
  mkdir_one("probe-runtime" PATH_SEP "Frameworks");
  mkdir_one("probe-runtime" PATH_SEP "Frameworks" PATH_SEP
            "Chromium Embedded Framework.framework");
  mkdir_one("probe-runtime" PATH_SEP "Resources");
  mkdir_one("probe-app");
  mkdir_one("probe-app" PATH_SEP "bin");
  mkdir_one("probe-app" PATH_SEP "Frameworks");
  mkdir_one("probe-app" PATH_SEP "Frameworks" PATH_SEP
            "Chromium Embedded Framework.framework");
  mkdir_one("probe-app" PATH_SEP "Resources");
  if (write_empty_file("probe-runtime" PATH_SEP "Frameworks" PATH_SEP
                       "Chromium Embedded Framework.framework" PATH_SEP
                       "Chromium Embedded Framework") ||
      write_empty_file("probe-runtime" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file("probe-app" PATH_SEP "Frameworks" PATH_SEP
                       "Chromium Embedded Framework.framework" PATH_SEP
                       "Chromium Embedded Framework") ||
      write_empty_file("probe-app" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file(helper_path)) {
    return 1;
  }
#elif defined(_WIN32)
  const char *helper_path = "probe-helper.exe";
  mkdir_one("probe-runtime");
  mkdir_one("probe-runtime" PATH_SEP "Release");
  mkdir_one("probe-runtime" PATH_SEP "Resources");
  mkdir_one("probe-runtime" PATH_SEP "Resources" PATH_SEP "locales");
  mkdir_one("probe-app");
  mkdir_one("probe-app" PATH_SEP "bin");
  mkdir_one("probe-app" PATH_SEP "Resources");
  mkdir_one("probe-app" PATH_SEP "Resources" PATH_SEP "locales");
  if (write_empty_file("probe-runtime" PATH_SEP "Release" PATH_SEP
                       "libcef.dll") ||
      write_empty_file("probe-runtime" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file("probe-app" PATH_SEP "bin" PATH_SEP "libcef.dll") ||
      write_empty_file("probe-app" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file(helper_path)) {
    return 1;
  }
#else
  const char *helper_path = "probe-helper";
  mkdir_one("probe-runtime");
  mkdir_one("probe-runtime" PATH_SEP "Resources");
  mkdir_one("probe-runtime" PATH_SEP "Resources" PATH_SEP "locales");
  mkdir_one("probe-app");
  mkdir_one("probe-app" PATH_SEP "lib");
  mkdir_one("probe-app" PATH_SEP "Resources");
  mkdir_one("probe-app" PATH_SEP "Resources" PATH_SEP "locales");
  if (write_empty_file("probe-runtime" PATH_SEP "libcef.so") ||
      write_empty_file("probe-runtime" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file("probe-app" PATH_SEP "lib" PATH_SEP "libcef.so") ||
      write_empty_file("probe-app" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat") ||
      write_empty_file(helper_path)) {
    return 1;
  }
#endif
  snprintf(config, config_len,
           "{\"abi_version\":1,\"runtime_root\":\"probe-runtime\","
           "\"helper_path\":\"%s\"}",
           helper_path);
  snprintf(installed_config, installed_config_len,
           "{\"abi_version\":1,\"runtime_root\":\"probe-app\","
           "\"helper_path\":\"%s\"}",
           helper_path);
  snprintf(missing_helper_config, missing_helper_config_len,
           "{\"abi_version\":1,\"runtime_root\":\"probe-runtime\","
           "\"helper_path\":\"missing-helper\"}");
  return 0;
}

#ifdef _WIN32
static int expect_flat_windows_bundled_probe(void) {
  mkdir_one("probe-portable");
  mkdir_one("probe-portable" PATH_SEP "Resources");
  mkdir_one("probe-portable" PATH_SEP "Resources" PATH_SEP "locales");
  if (write_empty_file("probe-portable" PATH_SEP "libcef.dll") ||
      write_empty_file("probe-portable" PATH_SEP "cef_process.exe") ||
      write_empty_file("probe-portable" PATH_SEP "Resources" PATH_SEP
                       "icudtl.dat")) {
    return 1;
  }
  char previous[32768] = {0};
  const char *previous_value = getenv("PROTON_RUNTIME_ROOT");
  if (previous_value != NULL) {
    snprintf(previous, sizeof(previous), "%s", previous_value);
  }
  if (_putenv_s("PROTON_RUNTIME_ROOT", "probe-portable") != 0) {
    return fail("failed to set PROTON_RUNTIME_ROOT for flat layout probe");
  }
  int32_t status = proton_runtime_probe_json(
      "{\"abi_version\":1,\"use_bundled\":true}");
  if (previous[0] != '\0') {
    _putenv_s("PROTON_RUNTIME_ROOT", previous);
  } else {
    _putenv_s("PROTON_RUNTIME_ROOT", "");
  }
  if (status != PROTON_OK) {
    char error[512] = {0};
    proton_last_error_message(error, (int32_t)sizeof(error));
    fprintf(stderr, "flat Windows portable probe failed: %s\n", error);
  }
  return expect_status("runtime_probe flat Windows portable layout", status,
                       PROTON_OK);
}
#endif

static int expect_event(proton_runtime_id_t runtime, const char *type) {
  char tiny[1];
  int32_t required = 0;
  int32_t status = proton_runtime_poll_event_json(runtime, tiny, 1, &required);
  if (expect_status("poll_event small buffer", status,
                    PROTON_ERR_BUFFER_TOO_SMALL)) {
    return 1;
  }
  if (required <= 0) {
    return fail("poll_event did not report required length");
  }

  char buffer[512];
  status = proton_runtime_poll_event_json(runtime, buffer,
                                          (int32_t)sizeof(buffer), &required);
  if (expect_status("poll_event", status, PROTON_OK)) {
    return 1;
  }
  if (strstr(buffer, type) == NULL) {
    fprintf(stderr, "expected event type '%s', got '%s'\n", type, buffer);
    return 1;
  }
  return 0;
}

static int expect_event_none(proton_runtime_id_t runtime) {
  char buffer[8];
  int32_t required = -1;
  int32_t status = proton_runtime_poll_event_json(runtime, buffer,
                                                  (int32_t)sizeof(buffer),
                                                  &required);
  if (expect_status("poll_event none", status, PROTON_EVENT_NONE)) {
    return 1;
  }
  if (required != 0) {
    return fail("poll_event none should require zero bytes");
  }
  return 0;
}

static int expect_bridge_request_none(proton_runtime_id_t runtime) {
  char buffer[8];
  int32_t required = -1;
  int32_t status = proton_runtime_poll_bridge_request_json(
      runtime, buffer, (int32_t)sizeof(buffer), &required);
  if (expect_status("poll_bridge_request none", status, PROTON_EVENT_NONE)) {
    return 1;
  }
  if (required != 0) {
    return fail("poll_bridge_request none should require zero bytes");
  }
  return 0;
}

static int expect_runtime_wait_ready(proton_runtime_id_t runtime,
                                     uint32_t interest,
                                     uint32_t expected_ready) {
  uint32_t ready = 0xffffffffu;
  int32_t status = proton_runtime_wait(runtime, interest, 0, &ready);
  if (expect_status("runtime_wait", status, PROTON_OK)) {
    return 1;
  }
  if (ready != expected_ready) {
    fprintf(stderr, "runtime_wait: expected ready mask %u, got %u\n",
            expected_ready, ready);
    return 1;
  }
  return 0;
}

typedef struct {
  proton_runtime_id_t runtime;
  proton_window_id_t window;
  int32_t status;
  char error[256];
} wrong_thread_probe_t;

#ifdef _WIN32
static DWORD WINAPI wrong_thread_runtime_wait(void *raw_probe) {
#else
static void *wrong_thread_runtime_wait(void *raw_probe) {
#endif
  wrong_thread_probe_t *probe = (wrong_thread_probe_t *)raw_probe;
  uint32_t ready_mask = PROTON_WAIT_NONE;
  probe->status =
      proton_runtime_wait(probe->runtime, PROTON_WAIT_EVENT, 0, &ready_mask);
  proton_last_error_message(probe->error, (int32_t)sizeof(probe->error));
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}

#ifdef _WIN32
static DWORD WINAPI wrong_thread_window_show(void *raw_probe) {
#else
static void *wrong_thread_window_show(void *raw_probe) {
#endif
  wrong_thread_probe_t *probe = (wrong_thread_probe_t *)raw_probe;
  probe->status = proton_window_show(probe->window);
  proton_last_error_message(probe->error, (int32_t)sizeof(probe->error));
#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}

static int expect_wrong_thread_runtime_wait_rejected(
    proton_runtime_id_t runtime) {
  wrong_thread_probe_t probe;
  memset(&probe, 0, sizeof(probe));
  probe.runtime = runtime;

#ifdef _WIN32
  HANDLE thread = CreateThread(NULL, 0, wrong_thread_runtime_wait, &probe, 0,
                               NULL);
  if (thread == NULL) {
    return fail("failed to create wrong-thread runtime probe thread");
  }
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
#else
  pthread_t thread;
  if (pthread_create(&thread, NULL, wrong_thread_runtime_wait, &probe) != 0) {
    return fail("failed to create wrong-thread runtime probe thread");
  }
  pthread_join(thread, NULL);
#endif

  if (expect_status("runtime_wait from wrong thread", probe.status,
                    PROTON_ERR_WRONG_THREAD)) {
    return 1;
  }
  if (strstr(probe.error, "owner thread") == NULL) {
    fprintf(stderr, "expected wrong-thread error, got '%s'\n", probe.error);
    return 1;
  }
  return 0;
}

static int expect_wrong_thread_window_rejected(proton_window_id_t window) {
  wrong_thread_probe_t probe;
  memset(&probe, 0, sizeof(probe));
  probe.window = window;

#ifdef _WIN32
  HANDLE thread = CreateThread(NULL, 0, wrong_thread_window_show, &probe, 0,
                               NULL);
  if (thread == NULL) {
    return fail("failed to create wrong-thread probe thread");
  }
  WaitForSingleObject(thread, INFINITE);
  CloseHandle(thread);
#else
  pthread_t thread;
  if (pthread_create(&thread, NULL, wrong_thread_window_show, &probe) != 0) {
    return fail("failed to create wrong-thread probe thread");
  }
  pthread_join(thread, NULL);
#endif

  if (expect_status("window_show from wrong thread", probe.status,
                    PROTON_ERR_WRONG_THREAD)) {
    return 1;
  }
  if (strstr(probe.error, "owner thread") == NULL) {
    fprintf(stderr, "expected wrong-thread error, got '%s'\n", probe.error);
    return 1;
  }
  return 0;
}

int main(void) {
  char probe_config[256];
  char installed_probe_config[256];
  char missing_helper_config[256];
  int32_t status = PROTON_OK;

  if (expect_bridge_lifecycle_state()) {
    return 1;
  }

  if (expect_status("abi_version", proton_abi_version(), PROTON_ABI_VERSION)) {
    return 1;
  }
  if (expect_runtime_info()) {
    return 1;
  }
  if (prepare_probe_layout(probe_config, sizeof(probe_config),
                           installed_probe_config,
                           sizeof(installed_probe_config),
                           missing_helper_config,
                           sizeof(missing_helper_config))) {
    return 1;
  }
  if (expect_status("runtime_probe", proton_runtime_probe_json(probe_config),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("runtime_probe installed layout",
                    proton_runtime_probe_json(installed_probe_config),
                    PROTON_OK)) {
    return 1;
  }
#ifdef _WIN32
  if (expect_flat_windows_bundled_probe()) {
    return 1;
  }
#endif
  if (!g_runtime_available) {
    proton_runtime_id_t probed_runtime = PROTON_INVALID_HANDLE;
    int32_t probed_create_status =
        proton_runtime_create_json(probe_config, &probed_runtime);
    if (expect_status("runtime_create with probed engine config",
                      probed_create_status, PROTON_ERR_UNSUPPORTED)) {
      return 1;
    }
    if (probed_runtime != PROTON_INVALID_HANDLE) {
      return fail("runtime_create failure should leave out handle invalid");
    }
    if (expect_last_error_contains("engine")) {
      return 1;
    }
    int32_t probed_exit_code = -1;
    int32_t probed_execute_status =
        proton_execute_process(probe_config, &probed_exit_code);
    if (expect_status("execute_process with probed engine config",
                      probed_execute_status, PROTON_ERR_UNSUPPORTED)) {
      return 1;
    }
    if (expect_last_error_contains("engine")) {
      return 1;
    }
  }
  int32_t probe_status = proton_runtime_probe_json(missing_helper_config);
  if (expect_status("runtime_probe rejects missing helper", probe_status,
                    PROTON_ERR_ENGINE)) {
    return 1;
  }
  if (expect_last_error_contains("helper")) {
    return 1;
  }

  int32_t exit_code = -1;
  if (expect_status("execute_process",
                    proton_execute_process("{\"abi_version\":1}", &exit_code),
                    PROTON_OK)) {
    return 1;
  }
  if (exit_code != 0) {
    return fail("execute_process returned unexpected exit code");
  }

  proton_runtime_id_t runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create",
                    proton_runtime_create_json("{\"abi_version\":1}", &runtime),
                    PROTON_OK)) {
    return 1;
  }
  if (runtime == PROTON_INVALID_HANDLE) {
    return fail("runtime_create returned invalid handle");
  }
  proton_runtime_id_t second_runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create rejects second active runtime",
                    proton_runtime_create_json("{\"abi_version\":1}",
                                               &second_runtime),
                    PROTON_ERR_ALREADY_INITIALIZED)) {
    return 1;
  }
  if (second_runtime != PROTON_INVALID_HANDLE) {
    return fail("second active runtime should leave out handle invalid");
  }
  if (expect_last_error_contains("already initialized")) {
    return 1;
  }
  uint32_t ready_mask = 123u;
  status = proton_runtime_wait(runtime, PROTON_WAIT_EVENT, 0, NULL);
  if (expect_status("runtime_wait rejects null out mask", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  status = proton_runtime_wait(runtime, PROTON_WAIT_NONE, 0, &ready_mask);
  if (expect_status("runtime_wait rejects empty interest", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_runtime_wait_ready(runtime, PROTON_WAIT_EVENT,
                                PROTON_WAIT_NONE)) {
    return 1;
  }
  if (expect_wrong_thread_runtime_wait_rejected(runtime)) {
    return 1;
  }

  proton_window_id_t window = PROTON_INVALID_HANDLE;
  if (expect_status("window_create",
                    proton_window_create_json(
                        runtime, "{\"abi_version\":1,\"title\":\"Smoke\","
                                 "\"width\":320,\"height\":240,"
                                 "\"bridge\":{\"abi_version\":1,"
                                 "\"namespace\":\"__MoonBit__\","
                                 "\"origin_policy\":{\"mode\":\"app_only\"},"
                                 "\"ops\":[{\"name\":\"ext:app/ping\"}],"
                                 "\"max_payload_bytes\":1048576,"
                                 "\"request_timeout_ms\":30000,"
                                 "\"extensions\":[]}}",
                        &window),
                    PROTON_OK)) {
    return 1;
  }
  if (window == PROTON_INVALID_HANDLE) {
    return fail("window_create returned invalid handle");
  }
  if (expect_runtime_wait_ready(runtime, PROTON_WAIT_EVENT,
                                PROTON_WAIT_EVENT)) {
    return 1;
  }
  if (expect_event(runtime, "window_created")) {
    return 1;
  }
  if (expect_wrong_thread_window_rejected(window)) {
    return 1;
  }

  if (expect_status("runtime_do_message_loop_work",
                    proton_runtime_do_message_loop_work(runtime), PROTON_OK)) {
    return 1;
  }
  if (expect_bridge_request_none(runtime)) {
    return 1;
  }
  status = proton_runtime_wait(runtime, PROTON_WAIT_BRIDGE, 0, &ready_mask);
  if (expect_status("runtime_wait without engine", status,
                    PROTON_ERR_UNSUPPORTED)) {
    return 1;
  }
  if (expect_last_error_contains("native engine")) {
    return 1;
  }
  status = proton_window_emit_bridge_event_json(
      window,
      "{\"abi_version\":1,\"kind\":\"frontend\","
      "\"name\":\"smoke\",\"payload\":null}");
  if (expect_status("emit_bridge_event without engine", status, PROTON_OK)) {
    return 1;
  }
  status = proton_window_emit_bridge_event_json(
      window,
      "{\"abi_version\":1,\"kind\":\"unknown\","
      "\"name\":\"smoke\",\"payload\":null}");
  if (expect_status("emit_bridge_event rejects kind", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  status = proton_runtime_respond_bridge_request_json(
      runtime,
      "{\"abi_version\":1,\"request_id\":\"1\",\"ok\":false,"
      "\"error\":{\"code\":\"op_failed\",\"message\":\"no pending request\"}}");
  if (expect_status("respond_bridge_request accepts quoted request_id", status,
                    PROTON_ERR_UNSUPPORTED)) {
    return 1;
  }
  if (expect_last_error_contains("native engine")) {
    return 1;
  }
  status = proton_runtime_respond_bridge_request_json(
      runtime,
      "{\"abi_version\":1,\"request_id\":2147483648,\"ok\":false,"
      "\"error\":{\"code\":\"op_failed\",\"message\":\"no pending request\"}}");
  if (expect_status("respond_bridge_request accepts 64-bit request_id", status,
                    PROTON_ERR_UNSUPPORTED)) {
    return 1;
  }
  if (expect_last_error_contains("native engine")) {
    return 1;
  }
  status = proton_runtime_respond_bridge_request_json(
      runtime,
      "{\"abi_version\":1,\"request_id\":1,\"ok\":false,"
      "\"error\":{\"code\":\"op_failed\",\"message\":\"no pending request\"}}");
  if (expect_status("respond_bridge_request without engine", status,
                    PROTON_ERR_UNSUPPORTED)) {
    return 1;
  }
  if (expect_last_error_contains("native engine")) {
    return 1;
  }

  if (expect_status("window_set_size",
                    proton_window_set_size(window, 320, 240), PROTON_OK)) {
    return 1;
  }
  if (expect_status("window_destroy", proton_window_destroy(window),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("window_destroy is idempotent",
                    proton_window_destroy(window), PROTON_OK)) {
    return 1;
  }
  if (expect_event(runtime, "window_closed")) {
    return 1;
  }
  if (expect_event_none(runtime)) {
    return 1;
  }

  proton_window_id_t close_window = PROTON_INVALID_HANDLE;
  if (expect_status("window_create for close",
                    proton_window_create_json(
                        runtime, "{\"abi_version\":1,\"title\":\"Close\","
                                 "\"width\":320,\"height\":240}",
                        &close_window),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_event(runtime, "window_created")) {
    return 1;
  }
  if (expect_status("window_close", proton_window_close(close_window),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("window_close is idempotent",
                    proton_window_close(close_window), PROTON_OK)) {
    return 1;
  }
  if (expect_event(runtime, "window_closed")) {
    return 1;
  }
  if (expect_event_none(runtime)) {
    return 1;
  }

  if (expect_status("runtime_destroy", proton_runtime_destroy(runtime),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("runtime_destroy is idempotent",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }
  runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create after destroy",
                    proton_runtime_create_json("{\"abi_version\":1}", &runtime),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("runtime_destroy after recreate",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json("{\"abi_version\":2}", &runtime);
  if (expect_status("runtime_create rejects wrong abi_version", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("invalid runtime config should leave out handle invalid");
  }
  if (expect_last_error_contains("abi_version")) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json("{\"abi_version\":\"1\"}", &runtime);
  if (expect_status("runtime_create rejects quoted abi_version", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("quoted runtime abi_version should leave out handle invalid");
  }
  if (expect_last_error_contains("abi_version")) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json("{\"abi_version\":1,}", &runtime);
  if (expect_status("runtime_create rejects trailing comma", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("trailing comma config should leave out handle invalid");
  }
  if (expect_last_error_contains("trailing comma")) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json("{\"abi_version\":1,\"debug\":true}",
                                      &runtime);
  if (expect_status("runtime_create rejects unknown field", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("unknown runtime config should leave out handle invalid");
  }
  if (expect_last_error_contains("unknown field: debug")) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json("{\"cache_dir\":{\"abi_version\":1}}",
                                      &runtime);
  if (expect_status("runtime_create requires top-level abi_version", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("nested abi_version config should leave out handle invalid");
  }
  if (expect_last_error_contains("invalid type or range")) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create valid",
                    proton_runtime_create_json("{\"abi_version\":1}", &runtime),
                    PROTON_OK)) {
    return 1;
  }
  window = PROTON_INVALID_HANDLE;
  status = proton_window_create_json(
      runtime,
      "{\"abi_version\":1,\"title\":\"Bad\",\"width\":\"320\",\"height\":240}",
      &window);
  if (expect_status("window_create rejects quoted width", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (window != PROTON_INVALID_HANDLE) {
    return fail("quoted window width should leave out handle invalid");
  }
  if (expect_last_error_contains("invalid type or range")) {
    return 1;
  }
  status = proton_window_create_json(
      runtime, "{\"abi_version\":1,\"title\":\"Bad\"}", &window);
  if (expect_status("window_create rejects missing size", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (window != PROTON_INVALID_HANDLE) {
    return fail("invalid window config should leave out handle invalid");
  }
  if (expect_last_error_contains("width and height")) {
    return 1;
  }
  status = proton_window_create_json(
      runtime, "{\"title\":\"Bad\",\"width\":320,\"height\":240}", &window);
  if (expect_status("window_create rejects missing abi_version", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_last_error_contains("abi_version")) {
    return 1;
  }
  status = proton_window_create_json(
      runtime,
      "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,"
      "\"resizable\":true}",
      &window);
  if (expect_status("window_create rejects unknown field", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_last_error_contains("unknown field: resizable")) {
    return 1;
  }
  status = proton_window_create_json(
      runtime,
      "{\"abi_version\":1,\"title\":\"Bad\",\"width\":320,\"height\":240,"
      "\"titlebar_style\":\"hidden_inset\"}",
      &window);
  if (expect_status("window_create rejects unsupported titlebar style", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_last_error_contains("titlebar_style")) {
    return 1;
  }
  status = proton_window_create_json(
      runtime,
      "{\"abi_version\":1,\"title\":\"Default\",\"width\":320,"
      "\"height\":240,\"titlebar_style\":\"default\"}",
      &window);
  if (expect_status("window_create accepts default titlebar style", status,
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("default window_destroy", proton_window_destroy(window),
                    PROTON_OK)) {
    return 1;
  }
  status = proton_window_create_json(
      runtime,
      "{\"abi_version\":1,\"title\":\"Overlay\",\"width\":320,"
      "\"height\":240,\"titlebar_style\":\"overlay\"}",
      &window);
  if (expect_status("window_create accepts overlay titlebar style", status,
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("overlay window_destroy", proton_window_destroy(window),
                    PROTON_OK)) {
    return 1;
  }
  if (expect_status("runtime_destroy after invalid window",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }

  return 0;
}
