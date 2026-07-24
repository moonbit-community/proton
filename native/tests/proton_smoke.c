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
#include <poll.h>
#include <sys/stat.h>
#include <unistd.h>
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

#if defined(__APPLE__) || defined(_WIN32)
static int g_app_entry_called = 0;
static int g_app_entry_on_main_thread = 0;
static int32_t g_app_entry_invalid_create_status = PROTON_OK;
static int32_t g_app_entry_create_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_run_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_quit_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_loop_work_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_wait_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_wakeup_delay_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_wakeup_status = PROTON_ERR_NOT_INITIALIZED;
static int g_app_entry_first_wakeup = 0;
static int g_app_entry_second_wakeup = 0;
static int32_t g_app_entry_window_create_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_window_show_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_window_close_status = PROTON_ERR_NOT_INITIALIZED;
static int32_t g_app_entry_window_destroy_status =
    PROTON_ERR_NOT_INITIALIZED;
static int g_app_entry_browser_ready = 0;
static int g_app_entry_window_closed = 0;
static int32_t g_app_entry_destroy_status = PROTON_ERR_NOT_INITIALIZED;
static char g_app_runtime_config[1024];
static char g_app_entry_error[512];

#ifdef _WIN32
static DWORD g_app_ui_thread_id = 0;

static int consume_wakeup_byte(HANDLE pipe) {
  for (int attempt = 0; attempt < 100; attempt++) {
    DWORD available = 0;
    if (!PeekNamedPipe(pipe, NULL, 0, NULL, &available, NULL)) {
      return 0;
    }
    if (available > 0) {
      unsigned char byte = 0;
      DWORD read = 0;
      return ReadFile(pipe, &byte, sizeof(byte), &read, NULL) &&
             read == (DWORD)sizeof(byte);
    }
    Sleep(10);
  }
  return 0;
}
#else
static int consume_wakeup_byte(int fd) {
  struct pollfd ready = {.fd = fd, .events = POLLIN, .revents = 0};
  if (poll(&ready, 1, 1000) <= 0 || (ready.revents & POLLIN) == 0) {
    return 0;
  }
  unsigned char byte = 0;
  return read(fd, &byte, sizeof(byte)) == (ssize_t)sizeof(byte);
}
#endif

static char *read_log(const char *path) {
  FILE *file = fopen(path, "rb");
  if (file == NULL) {
    return NULL;
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    return NULL;
  }
  long size = ftell(file);
  if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
    fclose(file);
    return NULL;
  }
  char *buffer = (char *)malloc((size_t)size + 1);
  if (buffer == NULL) {
    fclose(file);
    return NULL;
  }
  size_t length = fread(buffer, 1, (size_t)size, file);
  fclose(file);
  buffer[length] = '\0';
  return buffer;
}

static int log_contains(const char *path, const char *needle) {
  char *log = read_log(path);
  if (log == NULL) {
    return 0;
  }
  int found = strstr(log, needle) != NULL;
  free(log);
  return found;
}

static int log_contains_in_order(const char *path,
                                 const char *first,
                                 const char *second) {
  char *log = read_log(path);
  if (log == NULL) {
    return 0;
  }
  const char *first_match = strstr(log, first);
  const char *second_match = strstr(log, second);
  int ordered = first_match != NULL && second_match != NULL &&
                first_match < second_match;
  free(log);
  return ordered;
}

static int escape_json_string(const char *value,
                              char *buffer,
                              size_t buffer_len) {
  size_t written = 0;
  for (const unsigned char *cursor = (const unsigned char *)value;
       *cursor != '\0'; cursor++) {
    const char *escaped = NULL;
    if (*cursor == '\\') {
      escaped = "\\\\";
    } else if (*cursor == '"') {
      escaped = "\\\"";
    }
    if (escaped != NULL) {
      if (written + 2 >= buffer_len) {
        return 0;
      }
      buffer[written++] = escaped[0];
      buffer[written++] = escaped[1];
    } else {
      if (written + 1 >= buffer_len) {
        return 0;
      }
      buffer[written++] = (char)*cursor;
    }
  }
  buffer[written] = '\0';
  return 1;
}

static void smoke_app_entry(void) {
  g_app_entry_called = 1;
#ifdef _WIN32
  g_app_entry_on_main_thread =
      GetCurrentThreadId() == g_app_ui_thread_id;
#else
  g_app_entry_on_main_thread = pthread_main_np() != 0;
#endif
  proton_runtime_id_t runtime = PROTON_INVALID_HANDLE;
  g_app_entry_invalid_create_status =
      proton_runtime_create_json("{\"abi_version\":0}", &runtime);
  g_app_entry_create_status =
      proton_runtime_create_json(g_app_runtime_config, &runtime);
  if (g_app_entry_create_status != PROTON_OK) {
    proton_last_error_message(g_app_entry_error,
                              (int32_t)sizeof(g_app_entry_error));
  }
  if (g_app_entry_create_status == PROTON_OK) {
    uint32_t ready_mask = PROTON_WAIT_NONE;
    int64_t wakeup_delay_ms = -1;
    g_app_entry_run_status = proton_runtime_run(runtime);
    g_app_entry_quit_status = proton_runtime_quit(runtime);
    g_app_entry_loop_work_status =
        proton_runtime_do_message_loop_work(runtime);
    g_app_entry_wait_status =
        proton_runtime_wait(runtime, PROTON_WAIT_PLATFORM, 0, &ready_mask);
    g_app_entry_wakeup_delay_status =
        proton_runtime_next_wakeup_delay_ms(runtime, &wakeup_delay_ms);
#ifdef _WIN32
    char wakeup_source[256] = {0};
    int32_t required = 0;
    g_app_entry_wakeup_status =
        proton_runtime_prepare_wakeup_source(runtime, NULL, 0, &required);
    HANDLE wakeup_reader = INVALID_HANDLE_VALUE;
    if (g_app_entry_wakeup_status == PROTON_ERR_BUFFER_TOO_SMALL &&
        required > 0 && required < (int32_t)sizeof(wakeup_source)) {
      g_app_entry_wakeup_status = proton_runtime_prepare_wakeup_source(
          runtime, wakeup_source, (int32_t)sizeof(wakeup_source), &required);
    }
    if (g_app_entry_wakeup_status == PROTON_OK) {
      wakeup_reader =
          CreateFileA(wakeup_source, GENERIC_READ, 0, NULL, OPEN_EXISTING,
                      FILE_ATTRIBUTE_NORMAL, NULL);
      if (wakeup_reader == INVALID_HANDLE_VALUE) {
        g_app_entry_wakeup_status = PROTON_ERR_PLATFORM;
      }
    }
    if (g_app_entry_wakeup_status == PROTON_OK) {
      g_app_entry_wakeup_status =
          proton_runtime_activate_wakeup_source(runtime);
    }
    if (g_app_entry_wakeup_status == PROTON_OK) {
      g_app_entry_first_wakeup = consume_wakeup_byte(wakeup_reader);
    }
#else
    int wakeup_pipe[2] = {-1, -1};
    if (pipe(wakeup_pipe) == 0) {
      g_app_entry_wakeup_status =
          proton_runtime_set_wakeup_fd(runtime, wakeup_pipe[1]);
      if (g_app_entry_wakeup_status == PROTON_OK) {
        g_app_entry_first_wakeup = consume_wakeup_byte(wakeup_pipe[0]);
        g_app_entry_wakeup_status =
            proton_runtime_set_wakeup_fd(runtime, wakeup_pipe[1]);
        if (g_app_entry_wakeup_status == PROTON_OK) {
          g_app_entry_second_wakeup = consume_wakeup_byte(wakeup_pipe[0]);
        }
      }
      close(wakeup_pipe[0]);
      close(wakeup_pipe[1]);
    } else {
      g_app_entry_wakeup_status = PROTON_ERR_PLATFORM;
    }
#endif
    proton_window_id_t window = PROTON_INVALID_HANDLE;
    g_app_entry_window_create_status = proton_window_create_json(
        runtime,
        "{\"abi_version\":1,\"title\":\"Managed Destroy\","
        "\"width\":320,\"height\":240,\"initial_url\":\"about:blank\"}",
        &window);
    if (g_app_entry_window_create_status == PROTON_OK) {
      g_app_entry_window_show_status = proton_window_show(window);
#ifdef _WIN32
      g_app_entry_browser_ready = 1;
      g_app_entry_window_close_status = proton_window_close(window);
      if (g_app_entry_window_close_status == PROTON_OK) {
        g_app_entry_second_wakeup = consume_wakeup_byte(wakeup_reader);
        for (int attempt = 0; attempt < 100; attempt++) {
          char event_json[512] = {0};
          int32_t event_required = 0;
          int32_t event_status = proton_runtime_poll_event_json(
              runtime, event_json, (int32_t)sizeof(event_json),
              &event_required);
          if (event_status == PROTON_OK &&
              strstr(event_json, "\"type\":\"window_closed\"") != NULL) {
            g_app_entry_window_closed = 1;
            break;
          }
          Sleep(10);
        }
      }
      g_app_entry_window_destroy_status = proton_window_destroy(window);
#else
      for (int attempt = 0; attempt < 100; attempt++) {
        const char *native_log_path = getenv("PROTON_TEST_NATIVE_LOG");
        if (native_log_path != NULL &&
            log_contains(native_log_path, "create_browser id=")) {
          g_app_entry_browser_ready = 1;
          break;
        }
        usleep(10000);
      }
#endif
    }
    g_app_entry_destroy_status = proton_runtime_destroy(runtime);
#ifdef _WIN32
    if (wakeup_reader != INVALID_HANDLE_VALUE) {
      CloseHandle(wakeup_reader);
    }
#endif
  }
}
#endif

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
#ifdef _WIN32
  int has_managed_app_runner =
      strstr(buffer, "\"managed_app_runner\"") != NULL;
  int has_wakeup_source =
      strstr(buffer, "\"runtime_wakeup_source\"") != NULL;
#endif
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
#ifdef _WIN32
  if (has_runtime &&
      (!has_managed_app_runner || !has_wakeup_source)) {
    fprintf(stderr, "missing Windows managed runner capability: %s\n", buffer);
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
  if (expect_status("app_run rejects null entry", proton_app_run(NULL),
                    PROTON_ERR_INVALID_ARGUMENT)) {
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

#if defined(__APPLE__) || defined(_WIN32)
  if (g_runtime_available &&
      getenv("PROTON_TEST_SKIP_MANAGED_APP_RUNNER") == NULL) {
    const char *runtime_root = getenv("PROTON_TEST_RUNTIME_ROOT");
    const char *helper_path = getenv("PROTON_TEST_HELPER_PATH");
    char escaped_runtime_root[384];
    char escaped_helper_path[384];
    if (runtime_root == NULL || helper_path == NULL ||
        !escape_json_string(runtime_root, escaped_runtime_root,
                            sizeof(escaped_runtime_root)) ||
        !escape_json_string(helper_path, escaped_helper_path,
                            sizeof(escaped_helper_path)) ||
        snprintf(g_app_runtime_config, sizeof(g_app_runtime_config),
                 "{\"abi_version\":1,\"runtime_root\":\"%s\","
                 "\"helper_path\":\"%s\"}",
                 escaped_runtime_root, escaped_helper_path) >=
            (int)sizeof(g_app_runtime_config)) {
      return fail("missing managed app runner test runtime");
    }
    const char *native_log_path = getenv("PROTON_TEST_NATIVE_LOG");
    if (native_log_path == NULL) {
      return fail("missing managed app runner native log path");
    }
    remove(native_log_path);
#ifdef _WIN32
    g_app_ui_thread_id = GetCurrentThreadId();
#endif
    if (expect_status("app_run", proton_app_run(smoke_app_entry), PROTON_OK)) {
      return 1;
    }
    if (!g_app_entry_called || g_app_entry_on_main_thread) {
      return fail("app_run did not execute entry on its application thread");
    }
    if (expect_status("app_run failed runtime create",
                      g_app_entry_invalid_create_status,
                      PROTON_ERR_INVALID_ARGUMENT)) {
      return 1;
    }
    if (expect_status("app_run runtime create", g_app_entry_create_status,
                      PROTON_OK)) {
      fprintf(stderr, "app_run runtime create error: %s\n", g_app_entry_error);
      return 1;
    }
    if (expect_status("managed runtime_run", g_app_entry_run_status,
                      PROTON_ERR_UNSUPPORTED) ||
        expect_status("managed runtime_quit", g_app_entry_quit_status,
                      PROTON_ERR_UNSUPPORTED) ||
        expect_status("managed do_message_loop_work",
                      g_app_entry_loop_work_status, PROTON_ERR_UNSUPPORTED) ||
        expect_status("managed runtime_wait", g_app_entry_wait_status,
                      PROTON_ERR_UNSUPPORTED) ||
        expect_status("managed next_wakeup_delay_ms",
                      g_app_entry_wakeup_delay_status,
                      PROTON_ERR_UNSUPPORTED)) {
      return 1;
    }
    if (expect_status("app_run wakeup source", g_app_entry_wakeup_status,
                      PROTON_OK)) {
      return 1;
    }
    if (!g_app_entry_first_wakeup || !g_app_entry_second_wakeup) {
      return fail("app_run wakeup source lost a consecutive notification");
    }
    if (expect_status("app_run window create",
                      g_app_entry_window_create_status, PROTON_OK) ||
        expect_status("app_run window show", g_app_entry_window_show_status,
                      PROTON_OK)) {
      return 1;
    }
    if (!g_app_entry_browser_ready) {
      return fail("app_run browser did not become ready");
    }
#ifdef _WIN32
    if (!g_app_entry_window_closed) {
      return fail("app_run window close did not finish through CEF");
    }
    if (expect_status("app_run window close", g_app_entry_window_close_status,
                      PROTON_OK) ||
        expect_status("app_run window destroy",
                      g_app_entry_window_destroy_status, PROTON_OK)) {
      return 1;
    }
#endif
    if (expect_status("app_run runtime destroy", g_app_entry_destroy_status,
                      PROTON_OK)) {
      return 1;
    }
    if (!log_contains_in_order(native_log_path,
                               "browser_before_close browser=",
                               "managed_runtime_destroy_complete")) {
      return fail(
          "managed runtime destroy completed before browser_before_close");
    }
    if (!log_contains_in_order(native_log_path,
                               "managed_runtime_destroy_complete",
                               "cef_shutdown")) {
      return fail("CEF shut down before managed runtime destroy completed");
    }
  }
#endif

  int32_t notification_supported = -1;
  int32_t notification_required = -1;
  int32_t notification_has_payload = -1;
  int32_t notification_available = -1;
  char notification_buffer[16];
  if (expect_status("notification support rejects null output",
                    proton_notification_is_supported(NULL),
                    PROTON_ERR_INVALID_ARGUMENT) ||
      expect_status("notification support query",
                    proton_notification_is_supported(&notification_supported),
                    PROTON_OK)) {
    return 1;
  }
  if (notification_supported != 0 && notification_supported != 1) {
    return fail("notification support query returned an invalid boolean");
  }
  if (expect_status("notification show rejects null text",
                    proton_notification_show(NULL, "", "", 0),
                    PROTON_ERR_INVALID_ARGUMENT) ||
      expect_status("notification show rejects invalid payload flag",
                    proton_notification_show("", "", "", 2),
                    PROTON_ERR_INVALID_ARGUMENT) ||
      expect_status("notification poll rejects negative buffer length",
                    proton_notification_poll_click(
                        notification_buffer, -1, &notification_required,
                        &notification_has_payload, &notification_available),
                    PROTON_ERR_INVALID_ARGUMENT) ||
      expect_status("notification poll empty queue",
                    proton_notification_poll_click(
                        notification_buffer, sizeof(notification_buffer),
                        &notification_required, &notification_has_payload,
                        &notification_available),
                    PROTON_OK)) {
    return 1;
  }
  if (notification_required != 0 || notification_has_payload != 0 ||
      notification_available != 0) {
    return fail("notification poll reported a click for an empty queue");
  }
  if (expect_status("notification cleanup", proton_notification_cleanup(),
                    PROTON_OK)) {
    return 1;
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
  status = proton_runtime_set_wakeup_fd(runtime, -2);
  if (expect_status("runtime_set_wakeup_fd rejects invalid descriptor", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  status = proton_runtime_prepare_wakeup_source(runtime, NULL, 0, NULL);
  if (expect_status("runtime_prepare_wakeup_source rejects null output",
                    status, PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  status = proton_runtime_next_wakeup_delay_ms(runtime, NULL);
  if (expect_status("runtime_next_wakeup_delay rejects null output", status,
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
