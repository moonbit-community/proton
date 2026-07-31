#include <assert.h>
#include <stdint.h>
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

  return 0;
}
