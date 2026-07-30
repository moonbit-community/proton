#include "bridge_response.h"

#include "../../proton_json.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static char *proton_engine_bridge_response_copy_literal(const char *value) {
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy != NULL) {
    memcpy(copy, value, length + 1);
  }
  return copy;
}

void proton_engine_bridge_response_dispose(
    proton_engine_bridge_response_t *response) {
  if (response == NULL) {
    return;
  }
  free(response->payload_json);
  free(response->error_json);
  memset(response, 0, sizeof(*response));
}

int proton_engine_bridge_response_parse(
    const char *response_json,
    proton_engine_bridge_response_t *out_response) {
  if (response_json == NULL || out_response == NULL) {
    return PROTON_ENGINE_BRIDGE_RESPONSE_INVALID;
  }
  memset(out_response, 0, sizeof(*out_response));

  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t request_id;
  proton_json_value_t ok;
  if (!proton_json_parse(&doc, response_json)) {
    return PROTON_ENGINE_BRIDGE_RESPONSE_INVALID;
  }
  bool ok_value = false;
  int valid =
      proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "request_id", &request_id) &&
      proton_json_read_int64_string_or_number(
          &doc, request_id, &out_response->request_id) &&
      out_response->request_id > 0 &&
      proton_json_object_get(&doc, root, "ok", &ok) &&
      proton_json_read_bool(&doc, ok, &ok_value);
  if (!valid) {
    proton_json_dispose(&doc);
    return PROTON_ENGINE_BRIDGE_RESPONSE_INVALID;
  }
  out_response->ok = ok_value ? 1 : 0;

  proton_json_value_t body;
  if (out_response->ok) {
    if (proton_json_object_get(&doc, root, "payload", &body)) {
      out_response->payload_json = proton_json_copy_raw(&doc, body);
    } else {
      out_response->payload_json =
          proton_engine_bridge_response_copy_literal("null");
    }
  } else if (proton_json_object_get(&doc, root, "error", &body) &&
             proton_json_is_object(&doc, body)) {
    out_response->error_json = proton_json_copy_raw(&doc, body);
  } else {
    proton_json_dispose(&doc);
    proton_engine_bridge_response_dispose(out_response);
    return PROTON_ENGINE_BRIDGE_RESPONSE_INVALID;
  }
  proton_json_dispose(&doc);

  if ((out_response->ok && out_response->payload_json == NULL) ||
      (!out_response->ok && out_response->error_json == NULL)) {
    proton_engine_bridge_response_dispose(out_response);
    return PROTON_ENGINE_BRIDGE_RESPONSE_NO_MEMORY;
  }
  return PROTON_ENGINE_BRIDGE_RESPONSE_OK;
}
