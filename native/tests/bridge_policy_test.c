#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128

#include "../src/proton_json.h"
#include "../src/engine/cef_common/bridge_json.h"

static const char *const bridge_config =
    "{"
    "\"abi_version\":2,"
    "\"namespace\":\"__MoonBit__\","
    "\"grants\":["
    "{"
    "\"source_origin\":\"app\","
    "\"ops\":[{\"name\":\"app:ping\"}],"
    "\"extensions\":[],"
    "\"initialization_units\":[]"
    "},"
    "{"
    "\"source_origin\":\"https://example.com\","
    "\"ops\":[{\"name\":\"ext:fs/read_file\"}],"
    "\"extensions\":[],"
    "\"initialization_units\":[]"
    "}"
    "],"
    "\"max_payload_bytes\":1048576,"
    "\"request_timeout_ms\":30000"
    "}";

int main(void) {
  assert(proton_engine_url_is_bridge_candidate("proton://app/index.html"));
  assert(!proton_engine_url_is_bridge_candidate("proton://app.evil/index.html"));
  assert(!proton_engine_url_is_bridge_candidate("proton://other/index.html"));

  assert(proton_engine_url_is_bridge_candidate(
      "https://proton.localhost/index.html"));
  char *secure_app_origin =
      proton_engine_bridge_source_origin("https://proton.localhost/index.html");
  assert(secure_app_origin != NULL);
  assert(strcmp(secure_app_origin, "app") == 0);
  free(secure_app_origin);
  assert(proton_engine_bridge_config_allows_page(
      bridge_config, "https://proton.localhost/index.html"));
  assert(!proton_engine_bridge_config_allows_page(
      bridge_config, "https://proton.localhost.evil/index.html"));

  char *app_origin =
      proton_engine_bridge_source_origin("proton://app/index.html");
  assert(app_origin != NULL);
  assert(strcmp(app_origin, "app") == 0);
  free(app_origin);

  assert(proton_engine_bridge_config_allows_page(
      bridge_config, "proton://app/index.html"));
  assert(!proton_engine_bridge_config_allows_page(
      bridge_config, "proton://app.evil/index.html"));
  assert(proton_engine_bridge_config_allows_page(
      bridge_config, "https://example.com/workspace"));
  assert(!proton_engine_bridge_config_allows_page(
      bridge_config, "https://other.example/workspace"));

  assert(proton_engine_bridge_config_allows_op(
      bridge_config, "proton://app/index.html", "app:ping"));
  assert(!proton_engine_bridge_config_allows_op(
      bridge_config, "proton://app/index.html", "ext:fs/read_file"));
  assert(proton_engine_bridge_config_allows_op(
      bridge_config, "https://example.com/workspace", "ext:fs/read_file"));
  assert(!proton_engine_bridge_config_allows_op(
      bridge_config, "https://example.com/workspace", "app:ping"));
  assert(!proton_engine_bridge_config_allows_op(
      bridge_config, "https://other.example/workspace", "ext:fs/read_file"));

  /* Request-envelope construction. Rejected requests must leave the id counter
     untouched and must not hand back an allocation. */
  int64_t next_request_id = 7;
  int64_t request_id = -1;
  char *request_json = NULL;

  assert(proton_engine_bridge_build_request_json(
             bridge_config, "proton://app/index.html", "app:ping", "{\"a\":1}",
             "1234-5", 1048576, 42, &next_request_id, &request_id,
             &request_json) == PROTON_ENGINE_BRIDGE_REQUEST_OK);
  assert(request_id == 7);
  assert(next_request_id == 8);
  assert(request_json != NULL);
  assert(strstr(request_json, "\"request_id\":\"7\"") != NULL);
  assert(strstr(request_json, "\"window\":\"42\"") != NULL);
  assert(strstr(request_json, "\"op\":\"app:ping\"") != NULL);
  assert(strstr(request_json, "\"payload\":{\"a\":1}") != NULL);
  assert(strstr(request_json, "\"page_instance\":\"1234-5\"") != NULL);
  assert(strstr(request_json, "\"source_origin\":\"app\"") != NULL);
  free(request_json);

  assert(proton_engine_bridge_build_request_json(
             bridge_config, "https://other.example/page", "app:ping",
             "{\"a\":1}", "1234-5", 1048576, 42, &next_request_id, &request_id,
             &request_json) == PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED);
  assert(request_json == NULL);
  assert(next_request_id == 8);

  /* Granted to another origin, but not to this page: denied. */
  assert(proton_engine_bridge_build_request_json(
             bridge_config, "proton://app/index.html", "ext:fs/read_file",
             "{\"a\":1}", "1234-5", 1048576, 42, &next_request_id, &request_id,
             &request_json) == PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED);
  assert(request_json == NULL);
  assert(next_request_id == 8);

  /* Declared by no grant at all: reported as unregistered rather than denied,
     which is what an unprefixed application command looks like. */
  assert(proton_engine_bridge_build_request_json(
             bridge_config, "proton://app/index.html", "ping", "{\"a\":1}",
             "1234-5", 1048576, 42, &next_request_id, &request_id,
             &request_json) == PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN);
  assert(request_json == NULL);
  assert(next_request_id == 8);

  assert(proton_engine_bridge_config_declares_op(bridge_config, "app:ping"));
  assert(proton_engine_bridge_config_declares_op(bridge_config,
                                                 "ext:fs/read_file"));
  assert(!proton_engine_bridge_config_declares_op(bridge_config, "ping"));
  assert(!proton_engine_bridge_config_declares_op(bridge_config,
                                                  "app:not_registered"));

  assert(proton_engine_bridge_build_request_json(
             bridge_config, "proton://app/index.html", "app:ping", "{\"a\":1}",
             "1234-5", 4, 42, &next_request_id, &request_id,
             &request_json) == PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED);
  assert(request_json == NULL);
  assert(next_request_id == 8);

  assert(proton_engine_bridge_build_request_json(
             bridge_config, "proton://app/index.html", "app:ping", "{\"a\":1}",
             "1234-5\",\"x\":\"", 1048576, 42, &next_request_id, &request_id,
             &request_json) ==
         PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED);
  assert(request_json == NULL);
  assert(next_request_id == 8);

  return 0;
}
