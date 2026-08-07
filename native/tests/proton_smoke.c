#include "proton_native.h"
#include "../src/engine/cef_common/bridge_lifecycle.h"
#include "../src/engine/cef_common/bridge_response.h"
#include "../src/proton_app_instance.h"
#include "../src/proton_json.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The engines define these per translation unit; mirror them so the shared
   bridge_json.h validators can be exercised here. */
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128
#include "../src/engine/cef_common/bridge_json.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <direct.h>
#define mkdir_one(path) _mkdir(path)
#define PATH_SEP "\\"
#define PROTON_ENGINE_PATH_SEPARATOR '\\'
#define EXPECTED_PLATFORM "\"platform\":\"windows\""
#elif defined(__APPLE__)
#include <pthread.h>
#include <poll.h>
#include <sys/stat.h>
#include <unistd.h>
#define mkdir_one(path) mkdir(path, 0777)
#define PATH_SEP "/"
#define PROTON_ENGINE_PATH_SEPARATOR '/'
#define EXPECTED_PLATFORM "\"platform\":\"macos\""
#else
#include <pthread.h>
#include <poll.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#define mkdir_one(path) mkdir(path, 0777)
#define PATH_SEP "/"
#define PROTON_ENGINE_PATH_SEPARATOR '/'
#define EXPECTED_PLATFORM "\"platform\":\"linux\""
#endif

#include "../src/engine/cef_common/assets.h"

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

static int fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  const char *log_path = getenv("PROTON_TEST_NATIVE_LOG");
  if (log_path != NULL) {
    char *log = read_log(log_path);
    if (log != NULL) {
      long len = (long)strlen(log);
      long start = len > 4000 ? len - 4000 : 0;
      fprintf(stderr, "--- native log tail ---\n%.*s\n", (int)(len - start),
              log + start);
      free(log);
    }
  }
  return 1;
}

static int g_runtime_available = 0;
static int expect_status(const char *label, int32_t actual, int32_t expected);

void proton_engine_runtime_signal_external_event(
    proton_engine_runtime_t *runtime) {
  (void)runtime;
}

static int app_instance_secondary_main(const char *identifier,
                                       const char *activation_kind) {
  const char *activation =
      strcmp(activation_kind, "data") == 0
          ? "{\"abi_version\":1,\"urls\":[\"proton-test://open\"],"
            "\"files\":[\"/tmp/proton-test.txt\"],\"reopen\":false}"
          : "{\"abi_version\":1,\"urls\":[],\"files\":[],"
            "\"reopen\":false}";
  proton_app_instance_id_t instance = PROTON_INVALID_HANDLE;
  int32_t is_primary = 1;
  char error[256] = {0};
  int32_t status = proton_app_instance_acquire_impl(
      identifier, activation, &instance, &is_primary, error, sizeof(error));
  if (status != PROTON_OK || is_primary ||
      instance != PROTON_INVALID_HANDLE) {
    fprintf(stderr, "secondary activation failed: status=%d primary=%d %s\n",
            status, is_primary, error);
    if (instance != PROTON_INVALID_HANDLE) {
      (void)proton_app_instance_destroy_impl(instance, error, sizeof(error));
    }
    return 1;
  }
  return 0;
}

static int run_app_instance_secondary(const char *executable,
                                      const char *identifier,
                                      const char *activation_kind) {
#ifdef _WIN32
  wchar_t wide_executable_path[MAX_PATH];
  if (GetModuleFileNameW(NULL, wide_executable_path, MAX_PATH) == 0) {
    return fail("failed to locate app instance test executable");
  }
  char executable_path[MAX_PATH * 3];
  if (WideCharToMultiByte(CP_UTF8, 0, wide_executable_path, -1,
                          executable_path, (int)sizeof(executable_path), NULL,
                          NULL) <= 0) {
    return fail("failed to locate app instance test executable");
  }
  char command[2048];
  snprintf(command, sizeof(command), "\"%s\" --app-instance-secondary %s %s",
           executable_path, identifier, activation_kind);
  wchar_t wide_command[2048];
  if (MultiByteToWideChar(CP_UTF8, 0, command, -1, wide_command,
                          (int)(sizeof(wide_command) /
                                sizeof(wide_command[0]))) <= 0) {
    return fail("failed to start secondary app instance process");
  }
  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  memset(&startup, 0, sizeof(startup));
  memset(&process, 0, sizeof(process));
  startup.cb = sizeof(startup);
  if (!CreateProcessW(NULL, wide_command, NULL, NULL, FALSE, 0, NULL, NULL,
                      &startup, &process)) {
    return fail("failed to start secondary app instance process");
  }
  DWORD wait_status = WaitForSingleObject(process.hProcess, 10000);
  DWORD exit_code = 1;
  if (wait_status == WAIT_OBJECT_0) {
    (void)GetExitCodeProcess(process.hProcess, &exit_code);
  } else {
    TerminateProcess(process.hProcess, 1);
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return wait_status == WAIT_OBJECT_0 && exit_code == 0
             ? 0
             : fail("secondary app instance process failed");
#else
  pid_t child = fork();
  if (child < 0) {
    return fail("failed to fork secondary app instance process");
  }
  if (child == 0) {
    execl(executable, executable, "--app-instance-secondary", identifier,
          activation_kind, (char *)NULL);
    _exit(127);
  }
  int status = 0;
  if (waitpid(child, &status, 0) != child || !WIFEXITED(status) ||
      WEXITSTATUS(status) != 0) {
    return fail("secondary app instance process failed");
  }
  return 0;
#endif
}

static int expect_app_instance_forwarding(void) {
  char identifier[96];
#ifdef _WIN32
  unsigned long process_id = (unsigned long)GetCurrentProcessId();
#else
  unsigned long process_id = (unsigned long)getpid();
#endif
  snprintf(identifier, sizeof(identifier), "dev.proton.instance-smoke.%lu",
           process_id);
  proton_app_instance_id_t primary = PROTON_INVALID_HANDLE;
  int32_t is_primary = 0;
  char error[256] = {0};
  if (expect_status(
          "app instance rejects invalid activation",
          proton_app_instance_acquire_impl(
              identifier, "{}bogus", &primary, &is_primary, error,
              sizeof(error)),
          PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_status(
          "app instance rejects incomplete activation",
          proton_app_instance_acquire_impl(
              identifier, "{\"abi_version\":1,\"urls\":[],\"files\":[]}",
              &primary, &is_primary, error, sizeof(error)),
          PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_status(
          "app instance rejects duplicate activation fields",
          proton_app_instance_acquire_impl(
              identifier,
              "{\"abi_version\":1,\"urls\":[],\"urls\":[],\"files\":[],"
              "\"reopen\":false}",
              &primary, &is_primary, error, sizeof(error)),
          PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (expect_status(
          "acquire primary app instance",
          proton_app_instance_acquire_impl(
              identifier,
              "{\"abi_version\":1,\"urls\":[],\"files\":[],"
              "\"reopen\":false}",
              &primary, &is_primary, error, sizeof(error)),
          PROTON_OK) ||
      !is_primary || primary == PROTON_INVALID_HANDLE) {
    return fail("first app instance was not primary");
  }
  int runtime_sentinel = 0;
  if (expect_status(
          "attach app instance runtime",
          proton_app_instance_attach_runtime_impl(
              primary, (proton_engine_runtime_t *)&runtime_sentinel, error,
              sizeof(error)),
          PROTON_OK) ||
      expect_status(
          "reject attached app instance destroy",
          proton_app_instance_destroy_impl(primary, error, sizeof(error)),
          PROTON_ERR_ALREADY_INITIALIZED)) {
    proton_app_instance_detach_runtime_impl(primary);
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return 1;
  }
  proton_app_instance_detach_runtime_impl(primary);

  proton_app_instance_id_t secondary = PROTON_INVALID_HANDLE;
  is_primary = 1;
  if (expect_status(
          "forward secondary app activation",
          proton_app_instance_acquire_impl(
              identifier,
              "{\"abi_version\":1,\"urls\":[\"proton-test://open\"],"
              "\"files\":[\"/tmp/proton-test.txt\"],\"reopen\":false}",
              &secondary, &is_primary, error, sizeof(error)),
          PROTON_OK) ||
      is_primary || secondary != PROTON_INVALID_HANDLE) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return fail("second app instance was not forwarded");
  }

  const char *expected[] = {"\"type\":\"open_urls\"",
                            "\"type\":\"open_files\""};
  for (size_t i = 0; i < 2; i++) {
    char event[512];
    int32_t present = 0;
    if (expect_status(
            "take forwarded app activation",
            proton_app_instance_take_event_impl(
                primary, event, sizeof(event), &present, error, sizeof(error)),
            PROTON_OK) ||
        !present || strstr(event, expected[i]) == NULL) {
      proton_app_instance_destroy_impl(primary, error, sizeof(error));
      return fail("forwarded app activation event was not preserved");
    }
  }

  secondary = PROTON_INVALID_HANDLE;
  is_primary = 1;
  if (expect_status(
          "forward secondary reopen",
          proton_app_instance_acquire_impl(
              identifier,
              "{\"abi_version\":1,\"urls\":[],\"files\":[],"
              "\"reopen\":false}",
              &secondary, &is_primary, error, sizeof(error)),
          PROTON_OK) ||
      is_primary) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return fail("empty secondary activation was not forwarded");
  }
  char event[128];
  int32_t present = 0;
  if (expect_status(
          "take forwarded reopen",
          proton_app_instance_take_event_impl(
              primary, event, sizeof(event), &present, error, sizeof(error)),
          PROTON_OK) ||
      !present || strstr(event, "\"type\":\"reopen\"") == NULL) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return fail("secondary reopen event was not synthesized");
  }
  return expect_status("destroy primary app instance",
                       proton_app_instance_destroy_impl(
                           primary, error, sizeof(error)),
                       PROTON_OK);
}

static int expect_app_instance_cross_process_forwarding(
    const char *executable) {
  char identifier[96];
#ifdef _WIN32
  unsigned long process_id = (unsigned long)GetCurrentProcessId();
#else
  unsigned long process_id = (unsigned long)getpid();
#endif
  snprintf(identifier, sizeof(identifier),
           "dev.proton.instance-process-smoke.%lu", process_id);
  const char *empty_activation =
      "{\"abi_version\":1,\"urls\":[],\"files\":[],\"reopen\":false}";
  proton_app_instance_id_t primary = PROTON_INVALID_HANDLE;
  int32_t is_primary = 0;
  char error[256] = {0};
  if (expect_status(
          "acquire cross-process primary app instance",
          proton_app_instance_acquire_impl(
              identifier, empty_activation, &primary, &is_primary, error,
              sizeof(error)),
          PROTON_OK) ||
      !is_primary || primary == PROTON_INVALID_HANDLE) {
    return fail("cross-process app instance was not primary");
  }
  if (run_app_instance_secondary(executable, identifier, "data")) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return 1;
  }
  const char *expected[] = {"\"type\":\"open_urls\"",
                            "\"type\":\"open_files\""};
  for (size_t i = 0; i < 2; i++) {
    char event[512];
    int32_t present = 0;
    if (expect_status(
            "take cross-process app activation",
            proton_app_instance_take_event_impl(
                primary, event, sizeof(event), &present, error, sizeof(error)),
            PROTON_OK) ||
        !present || strstr(event, expected[i]) == NULL) {
      proton_app_instance_destroy_impl(primary, error, sizeof(error));
      return fail("cross-process app activation event was not preserved");
    }
  }
  if (run_app_instance_secondary(executable, identifier, "reopen")) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return 1;
  }
  char event[128];
  int32_t present = 0;
  if (expect_status(
          "take cross-process reopen",
          proton_app_instance_take_event_impl(
              primary, event, sizeof(event), &present, error, sizeof(error)),
          PROTON_OK) ||
      !present || strstr(event, "\"type\":\"reopen\"") == NULL) {
    proton_app_instance_destroy_impl(primary, error, sizeof(error));
    return fail("cross-process reopen event was not synthesized");
  }
  return expect_status("destroy cross-process primary app instance",
                       proton_app_instance_destroy_impl(
                           primary, error, sizeof(error)),
                       PROTON_OK);
}

static int expect_valid_json(const char *label, const char *json) {
  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, json)) {
    fprintf(stderr, "%s: invalid JSON\n", label);
    return 1;
  }
  proton_json_dispose(&doc);
  return 0;
}

static int expect_root_json_values(void) {
  static const char *values[] = {
      "null",
      "true",
      "false",
      "42",
      "-1.5e+2",
      "\"text\"",
  };
  for (size_t index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
    proton_json_doc_t doc;
    if (!proton_json_parse(&doc, values[index])) {
      fprintf(stderr, "root JSON value rejected: %s\n", values[index]);
      return 1;
    }
    if (!proton_json_is_single_value(&doc)) {
      fprintf(stderr, "root JSON value is not singular: %s\n", values[index]);
      proton_json_dispose(&doc);
      return 1;
    }
    proton_json_dispose(&doc);
  }
  return 0;
}

static int expect_bridge_response_payloads(void) {
  proton_engine_bridge_response_t response;
  int status = proton_engine_bridge_response_parse(
      "{\"abi_version\":1,\"request_id\":\"42\",\"ok\":true,"
      "\"payload\":{\"value\":\"pong\"}}",
      &response);
  if (status != PROTON_ENGINE_BRIDGE_RESPONSE_OK ||
      response.request_id != 42 || !response.ok ||
      response.payload_json == NULL ||
      strcmp(response.payload_json, "{\"value\":\"pong\"}") != 0 ||
      response.error_json != NULL) {
    proton_engine_bridge_response_dispose(&response);
    return fail("successful bridge response payload was not preserved");
  }
  proton_engine_bridge_response_dispose(&response);

  status = proton_engine_bridge_response_parse(
      "{\"abi_version\":1,\"request_id\":43,\"ok\":false,"
      "\"error\":{\"code\":\"backend_failed\","
      "\"message\":\"command failed\","
      "\"detail\":\"validation\"}}",
      &response);
  if (status != PROTON_ENGINE_BRIDGE_RESPONSE_OK ||
      response.request_id != 43 || response.ok ||
      response.payload_json != NULL || response.error_json == NULL ||
      strcmp(response.error_json,
             "{\"code\":\"backend_failed\","
             "\"message\":\"command failed\","
             "\"detail\":\"validation\"}") != 0) {
    proton_engine_bridge_response_dispose(&response);
    return fail("failed bridge response error JSON was not preserved");
  }
  proton_engine_bridge_response_dispose(&response);

  status = proton_engine_bridge_response_parse(
      "{\"abi_version\":1,\"request_id\":44,\"ok\":false}", &response);
  if (status != PROTON_ENGINE_BRIDGE_RESPONSE_INVALID) {
    proton_engine_bridge_response_dispose(&response);
    return fail("failed bridge response without error should be invalid");
  }
  return 0;
}

static char *make_nested_array_json(size_t depth) {
  char *json = (char *)malloc(depth * 2 + 1);
  if (json == NULL) {
    return NULL;
  }
  memset(json, '[', depth);
  memset(json + depth, ']', depth);
  json[depth * 2] = '\0';
  return json;
}

static int expect_json_depth_limit(void) {
  // Nesting exactly at the cap parses; one level beyond is rejected.
  char *json = make_nested_array_json(PROTON_JSON_MAX_DEPTH);
  if (json == NULL) {
    return fail("depth-limit allocation failed");
  }
  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, json) || !proton_json_is_single_value(&doc)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("JSON at the nesting depth limit should parse");
  }
  proton_json_dispose(&doc);
  free(json);

  json = make_nested_array_json((size_t)PROTON_JSON_MAX_DEPTH + 1);
  if (json == NULL) {
    return fail("depth-limit allocation failed");
  }
  if (proton_json_parse(&doc, json)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("JSON beyond the nesting depth limit should be rejected");
  }
  free(json);

  // Regression: renderer-sized deep nesting must be rejected after jsmn
  // tokenization, before any recursive accessor can walk it.
  json = make_nested_array_json(500000);
  if (json == NULL) {
    return fail("deep nesting allocation failed");
  }
  if (proton_json_parse(&doc, json)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("deeply nested JSON should be rejected");
  }
  if (proton_json_is_single_value(&doc)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("rejected JSON must not be a single value");
  }
  proton_json_dispose(&doc);
  free(json);

  // Regression: a quote inside a jsmn primitive must not desync depth
  // accounting — jsmn absorbs the quote into the primitive, so the brackets
  // after 1" are real structure, not string content.
  size_t deep = 500000;
  json = (char *)malloc(deep * 2 + 10);
  if (json == NULL) {
    return fail("bypass payload allocation failed");
  }
  memcpy(json, "[1\",", 4);
  memset(json + 4, '[', deep);
  memset(json + 4 + deep, ']', deep);
  memcpy(json + 4 + deep * 2, ",\"x\"]", 6);
  if (proton_json_parse(&doc, json)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("primitive-quote deep nesting should be rejected");
  }
  if (proton_json_is_single_value(&doc)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("rejected bypass JSON must not be a single value");
  }
  proton_json_dispose(&doc);
  free(json);

  // Brackets inside strings and escaped quotes must not count as nesting.
  size_t bracket_count = (size_t)PROTON_JSON_MAX_DEPTH + 100;
  char *brackets = (char *)malloc(bracket_count + 5);
  if (brackets == NULL) {
    return fail("bracket string allocation failed");
  }
  brackets[0] = '[';
  brackets[1] = '"';
  memset(brackets + 2, '[', bracket_count);
  brackets[bracket_count + 2] = '"';
  brackets[bracket_count + 3] = ']';
  brackets[bracket_count + 4] = '\0';
  if (expect_valid_json("brackets inside strings", brackets)) {
    free(brackets);
    return 1;
  }
  free(brackets);

  // A string holding an escaped quote plus brackets up to the cap parses;
  // the same string followed by real over-cap structure is rejected.
  char *escaped = (char *)malloc((size_t)PROTON_JSON_MAX_DEPTH + 8);
  if (escaped == NULL) {
    return fail("escaped-quote allocation failed");
  }
  escaped[0] = '[';
  escaped[1] = '"';
  escaped[2] = '\\';
  escaped[3] = '"';
  memset(escaped + 4, '[', PROTON_JSON_MAX_DEPTH);
  escaped[PROTON_JSON_MAX_DEPTH + 4] = '"';
  escaped[PROTON_JSON_MAX_DEPTH + 5] = ']';
  escaped[PROTON_JSON_MAX_DEPTH + 6] = '\0';
  if (expect_valid_json("escaped quote then brackets", escaped)) {
    free(escaped);
    return 1;
  }
  free(escaped);

  size_t over = (size_t)PROTON_JSON_MAX_DEPTH + 1;
  json = (char *)malloc(over * 2 + 8);
  if (json == NULL) {
    return fail("escaped-quote deep allocation failed");
  }
  memcpy(json, "[\"\\\"\",", 6);
  memset(json + 6, '[', over);
  memset(json + 6 + over, ']', over);
  json[6 + over * 2] = ']';
  json[6 + over * 2 + 1] = '\0';
  if (proton_json_parse(&doc, json)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("structure after an escaped-quote string should be rejected");
  }
  free(json);

  // Regression: ':' is not a primitive delimiter in strict jsmn, so the
  // quote after 1: is absorbed into the primitive and the brackets are real
  // structure; a naive string-state scanner would hide them.
  json = (char *)malloc(deep * 2 + 7);
  if (json == NULL) {
    return fail("colon bypass allocation failed");
  }
  memcpy(json, "[1:\",", 5);
  memset(json + 5, '[', deep);
  memset(json + 5 + deep, ']', deep);
  json[5 + deep * 2] = ']';
  json[5 + deep * 2 + 1] = '\0';
  if (proton_json_parse(&doc, json)) {
    proton_json_dispose(&doc);
    free(json);
    return fail("colon-primitive deep nesting should be rejected");
  }
  free(json);

  // A primitive ends at whitespace; a string starting after it must be
  // tracked as a string — its brackets are not structure.
  if (expect_valid_json("string after primitive", "[1 \"[[[[[[[[\"]")) {
    return 1;
  }

  // Brackets absorbed into a primitive are not structure either; use enough
  // of them that a scanner without a primitive state would over-reject.
  size_t absorbed = PROTON_JSON_MAX_DEPTH;
  json = (char *)malloc(absorbed + 8);
  if (json == NULL) {
    return fail("primitive bracket allocation failed");
  }
  json[0] = '[';
  json[1] = '1';
  memset(json + 2, '[', absorbed);
  memcpy(json + 2 + absorbed, ",\"x\"]", 5);
  json[2 + absorbed + 5] = '\0';
  if (expect_valid_json("brackets absorbed by primitive", json)) {
    free(json);
    return 1;
  }
  free(json);
  return 0;
}

static int expect_bridge_lifecycle_resize_retry(void) {
  proton_engine_bridge_lifecycle_t lifecycle;
  proton_engine_bridge_lifecycle_init(&lifecycle);
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-short", "", NULL)) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle rejected the short resize state");
  }

  int32_t required = 0;
  if (expect_status("bridge lifecycle short length probe",
                    proton_engine_bridge_lifecycle_state_json(
                        &lifecycle, NULL, 0, &required),
                    PROTON_ERR_BUFFER_TOO_SMALL) ||
      required <= 0) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return 1;
  }
  int32_t short_required = required;
  char *state = (char *)calloc((size_t)short_required + 1, 1);
  if (state == NULL) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("failed to allocate short bridge lifecycle buffer");
  }

  char long_url[2048];
  static const char url_prefix[] = "proton://app/";
  memcpy(long_url, url_prefix, sizeof(url_prefix) - 1);
  memset(long_url + sizeof(url_prefix) - 1, 'x',
         sizeof(long_url) - sizeof(url_prefix));
  long_url[sizeof(long_url) - 1] = '\0';
  if (!proton_engine_bridge_lifecycle_update(
          &lifecycle, "pending", "page-long", long_url, NULL)) {
    free(state);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle rejected the long resize state");
  }
  if (expect_status("bridge lifecycle grown copy",
                    proton_engine_bridge_lifecycle_state_json(
                        &lifecycle, state, short_required + 1, &required),
                    PROTON_ERR_BUFFER_TOO_SMALL) ||
      required <= short_required) {
    free(state);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle did not report its grown payload");
  }

  char *grown_state = (char *)realloc(state, (size_t)required + 1);
  if (grown_state == NULL) {
    free(state);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("failed to grow bridge lifecycle buffer");
  }
  state = grown_state;
  if (expect_status("bridge lifecycle grown retry",
                    proton_engine_bridge_lifecycle_state_json(
                        &lifecycle, state, required + 1, &required),
                    PROTON_OK) ||
      strstr(state, "\"page_instance\":\"page-long\"") == NULL ||
      strstr(state, long_url) == NULL) {
    free(state);
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("bridge lifecycle retry did not return the grown state");
  }
  free(state);
  proton_engine_bridge_lifecycle_dispose(&lifecycle);
  return 0;
}

static int expect_bridge_lifecycle_state(void) {
  if (!proton_engine_urls_same_document(
          "proton://app/index.html", "proton://app/index.html#ready") ||
      !proton_engine_urls_same_document(
          "proton://app/index.html#first",
          "proton://app/index.html#second") ||
      proton_engine_urls_same_document(
          "proton://app/index.html?mode=one",
          "proton://app/index.html?mode=two") ||
      proton_engine_urls_same_document(NULL, "proton://app/index.html")) {
    return fail("same-document URL matching should ignore only fragments");
  }
  if (expect_bridge_lifecycle_resize_retry()) {
    return 1;
  }
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
      proton_engine_bridge_lifecycle_report_load_failure(
          &lifecycle, "proton://app/missing.html", "not found", 0) ||
      proton_engine_bridge_lifecycle_take_failure_json(
          &lifecycle, NULL, 0, &required) != PROTON_EVENT_NONE) {
    proton_engine_bridge_lifecycle_dispose(&lifecycle);
    return fail("post-startup load failure became a fatal bridge failure");
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

static int expect_bridge_page_instance_validation(void) {
  static const struct {
    const char *value;
    int expected;
  } cases[] = {
      {"12345-7", 1},
      {"1-1", 1},
      {"0-18446744073709551615", 1},
      {"-", 1},
      {NULL, 0},
      {"", 0},
      {"abc-1", 0},
      {"12345_7", 0},
      {"12345\"-7", 0},
      {"12345\\-7", 0},
      {"12345 -7", 0},
      {"12345\n-7", 0},
  };
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    if (proton_engine_bridge_page_instance_is_valid(cases[i].value) !=
        cases[i].expected) {
      fprintf(stderr, "page instance validation mismatch at case %zu\n", i);
      return 1;
    }
  }
  char long_instance[PROTON_ENGINE_MAX_BRIDGE_OP_BYTES + 1];
  memset(long_instance, '1', PROTON_ENGINE_MAX_BRIDGE_OP_BYTES);
  long_instance[PROTON_ENGINE_MAX_BRIDGE_OP_BYTES] = '\0';
  if (proton_engine_bridge_page_instance_is_valid(long_instance)) {
    return fail("page instance validation accepted an overlong instance");
  }
  long_instance[PROTON_ENGINE_MAX_BRIDGE_OP_BYTES - 1] = '\0';
  if (!proton_engine_bridge_page_instance_is_valid(long_instance)) {
    return fail("page instance validation rejected a boundary-length instance");
  }
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
  char buffer[512];
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
  int has_headless_osr = strstr(buffer, "\"headless_osr\"") != NULL;
  int has_window_size_hints =
      strstr(buffer, "\"window_size_hints\"") != NULL;
  int has_window_session = strstr(buffer, "\"window_session\"") != NULL;
  int has_managed_app_runner =
      strstr(buffer, "\"managed_app_runner\"") != NULL;
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
  if (has_headless_osr != has_runtime) {
    fprintf(stderr, "unexpected headless OSR capability: %s\n", buffer);
    return 1;
  }
  if (has_window_size_hints != has_runtime) {
    fprintf(stderr, "unexpected window size hint capability: %s\n", buffer);
    return 1;
  }
  if (has_window_session != has_runtime) {
    fprintf(stderr, "unexpected window session capability: %s\n", buffer);
    return 1;
  }
#else
  if (has_titlebar_overlay) {
    fprintf(stderr, "unsupported titlebar overlay capability: %s\n", buffer);
    return 1;
  }
  if (has_headless_osr) {
    fprintf(stderr, "unsupported headless OSR capability: %s\n", buffer);
    return 1;
  }
  if (has_window_session) {
    fprintf(stderr, "unsupported window session capability: %s\n", buffer);
    return 1;
  }
#endif
  if (has_managed_app_runner) {
    fprintf(stderr, "removed managed runner capability is still advertised: "
                    "%s\n",
            buffer);
    return 1;
  }
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

static int expect_asset_document_root_resolution(void) {
  mkdir_one("asset-root");
  mkdir_one("asset-root" PATH_SEP "scripts");
  mkdir_one("asset-outside");
  if (write_empty_file("asset-root" PATH_SEP "scripts" PATH_SEP "app.js") ||
      write_empty_file("asset-outside" PATH_SEP "secret.txt")) {
    return 1;
  }
  char *path = proton_engine_url_to_rooted_asset_path(
      PROTON_ENGINE_APP_URL_PREFIX "scripts/app.js?cache=1", "asset-root");
  if (path == NULL ||
      strstr(path, "asset-root" PATH_SEP "scripts" PATH_SEP "app.js") ==
          NULL) {
    free(path);
    return fail("asset URL did not resolve below its document root");
  }
  free(path);
  if (proton_engine_url_to_rooted_asset_path(
          PROTON_ENGINE_APP_URL_PREFIX "../asset-outside/secret.txt",
          "asset-root") != NULL ||
      proton_engine_url_to_rooted_asset_path(
          PROTON_ENGINE_APP_URL_PREFIX "%2e%2e/asset-outside/secret.txt",
          "asset-root") !=
          NULL ||
      proton_engine_url_to_rooted_asset_path(
          PROTON_ENGINE_APP_URL_PREFIX "/absolute/path", "asset-root") !=
          NULL) {
    return fail("asset URL escaped or replaced its document root");
  }
#ifndef _WIN32
  unlink("asset-root" PATH_SEP "outside-link");
  if (symlink(".." PATH_SEP "asset-outside" PATH_SEP "secret.txt",
              "asset-root" PATH_SEP "outside-link") == 0 &&
      proton_engine_url_to_rooted_asset_path(
          PROTON_ENGINE_APP_URL_PREFIX "outside-link", "asset-root") != NULL) {
    return fail("asset URL followed a symlink outside its document root");
  }
#endif
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

int main(int argc, char **argv) {
  if (argc == 4 && strcmp(argv[1], "--app-instance-secondary") == 0) {
    return app_instance_secondary_main(argv[2], argv[3]);
  }
  char probe_config[256];
  char installed_probe_config[256];
  char missing_helper_config[256];
  int32_t status = PROTON_OK;

  if (expect_bridge_lifecycle_state()) {
    return 1;
  }
  if (expect_bridge_page_instance_validation()) {
    return 1;
  }
  if (expect_root_json_values()) {
    return 1;
  }
  if (expect_bridge_response_payloads()) {
    return 1;
  }
  if (expect_json_depth_limit()) {
    return 1;
  }
  if (expect_asset_document_root_resolution()) {
    return 1;
  }

  if (expect_status("abi_version", proton_abi_version(), PROTON_ABI_VERSION)) {
    return 1;
  }
  if (expect_runtime_info()) {
    return 1;
  }
  if (expect_app_instance_forwarding()) {
    return 1;
  }
  if (expect_app_instance_cross_process_forwarding(argv[0])) {
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
                                 "\"bridge\":{\"abi_version\":2,"
                                 "\"namespace\":\"__MoonBit__\","
                                 "\"grants\":[{\"source_origin\":\"app\","
                                 "\"ops\":[{\"name\":\"ext:app/ping\"}],"
                                 "\"extensions\":[],"
                                 "\"initialization_units\":[]}],"
                                 "\"max_payload_bytes\":1048576}}",
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

  proton_window_id_t queued_windows[32];
  for (int i = 0; i < 32; i++) {
    queued_windows[i] = PROTON_INVALID_HANDLE;
    if (expect_status(
            "window_create while filling event queue",
            proton_window_create_json(
                runtime, "{\"abi_version\":1,\"title\":\"Queued\","
                         "\"width\":320,\"height\":240}",
                &queued_windows[i]),
            PROTON_OK)) {
      return 1;
    }
  }
  if (expect_status("window_destroy with full event queue",
                    proton_window_destroy(queued_windows[0]),
                    PROTON_ERR_QUEUE_FAILED) ||
      expect_status("window remains live after destroy backpressure",
                    proton_window_show(queued_windows[0]), PROTON_OK) ||
      expect_event(runtime, "window_created") ||
      expect_status("window_destroy after draining queue",
                    proton_window_destroy(queued_windows[0]), PROTON_OK)) {
    return 1;
  }
  for (int i = 1; i < 32; i++) {
    if (expect_event(runtime, "window_created")) {
      return 1;
    }
  }
  if (expect_event(runtime, "window_closed") ||
      expect_status("window_destroy after queue retry is idempotent",
                    proton_window_destroy(queued_windows[0]), PROTON_OK)) {
    return 1;
  }
  for (int i = 1; i < 32; i++) {
    if (expect_status("queued window_destroy",
                      proton_window_destroy(queued_windows[i]), PROTON_OK)) {
      return 1;
    }
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
  if (expect_status("runtime_create for close backpressure",
                    proton_runtime_create_json("{\"abi_version\":1}", &runtime),
                    PROTON_OK)) {
    return 1;
  }
  proton_window_id_t close_queued_windows[32];
  for (int i = 0; i < 32; i++) {
    close_queued_windows[i] = PROTON_INVALID_HANDLE;
    if (expect_status(
            "window_create while filling event queue for close",
            proton_window_create_json(
                runtime, "{\"abi_version\":1,\"title\":\"Queued\","
                         "\"width\":320,\"height\":240}",
                &close_queued_windows[i]),
            PROTON_OK)) {
      return 1;
    }
  }
  if (expect_status("window_close with full event queue",
                    proton_window_close(close_queued_windows[0]),
                    PROTON_ERR_QUEUE_FAILED) ||
      expect_status("window remains live after close backpressure",
                    proton_window_show(close_queued_windows[0]), PROTON_OK) ||
      expect_runtime_wait_ready(runtime, PROTON_WAIT_EVENT,
                                PROTON_WAIT_EVENT)) {
    return 1;
  }
  for (int i = 0; i < 32; i++) {
    if (expect_event(runtime, "window_created")) {
      return 1;
    }
  }
  if (expect_status("window_close after draining queue",
                    proton_window_close(close_queued_windows[0]), PROTON_OK)) {
    return 1;
  }
  char close_buffer[512];
  int32_t close_required = 0;
  status = proton_runtime_poll_event_json(runtime, close_buffer,
                                          (int32_t)sizeof(close_buffer),
                                          &close_required);
  if (expect_status("poll_event after close retry", status, PROTON_OK)) {
    return 1;
  }
  char expected_closed[96];
  snprintf(expected_closed, sizeof(expected_closed),
           "\"type\":\"window_closed\",\"window\":\"%lld\"",
           (long long)close_queued_windows[0]);
  if (strstr(close_buffer, expected_closed) == NULL) {
    fprintf(stderr, "expected closed event '%s', got '%s'\n", expected_closed,
            close_buffer);
    return 1;
  }
  for (int i = 1; i < 32; i++) {
    if (expect_status("close backpressure window_destroy",
                      proton_window_destroy(close_queued_windows[i]),
                      PROTON_OK)) {
      return 1;
    }
  }
  if (expect_status("runtime_destroy after close backpressure",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  if (expect_status(
          "runtime_create accepts boolean headless",
          proton_runtime_create_json(
              "{\"abi_version\":1,\"headless\":true}", &runtime),
          PROTON_OK)) {
    return 1;
  }
  if (expect_status("runtime_destroy after headless config",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }

  runtime = PROTON_INVALID_HANDLE;
  status = proton_runtime_create_json(
      "{\"abi_version\":1,\"headless\":\"true\"}", &runtime);
  if (expect_status("runtime_create rejects non-boolean headless", status,
                    PROTON_ERR_INVALID_ARGUMENT)) {
    return 1;
  }
  if (runtime != PROTON_INVALID_HANDLE) {
    return fail("invalid headless config should leave out handle invalid");
  }
  if (expect_last_error_contains("headless")) {
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
