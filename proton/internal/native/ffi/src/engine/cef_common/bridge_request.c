#include "bridge_request.h"

#include <stdlib.h>
#include <string.h>

int proton_engine_bridge_op_is_valid(const char *op) {
  if (op == NULL || op[0] == '\0') {
    return 0;
  }
  size_t len = strlen(op);
  if (len >= PROTON_ENGINE_MAX_BRIDGE_OP_BYTES) {
    return 0;
  }
  for (size_t i = 0; i < len; i++) {
    unsigned char ch = (unsigned char)op[i];
    if (ch < 0x21 || ch > 0x7e || ch == '"' || ch == '\\') {
      return 0;
    }
  }
  return 1;
}

int proton_engine_bridge_page_instance_is_valid(const char *page_instance) {
  if (page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  size_t len = strlen(page_instance);
  if (len >= PROTON_ENGINE_MAX_BRIDGE_OP_BYTES) {
    return 0;
  }
  for (size_t i = 0; i < len; i++) {
    unsigned char ch = (unsigned char)page_instance[i];
    if ((ch < '0' || ch > '9') && ch != '-') {
      return 0;
    }
  }
  return 1;
}

int proton_engine_bridge_payload_is_valid(const char *payload,
                                          size_t max_bytes) {
  return payload != NULL && strlen(payload) <= max_bytes;
}

const char *proton_engine_bridge_request_reject_message(
    proton_engine_bridge_request_status_t status) {
  switch (status) {
  case PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED:
    return "bridge origin is not allowed";
  case PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN:
    return "bridge op is not registered; application commands are invoked as "
           "\"app:<name>\" and extension commands as "
           "\"ext:<namespace>/<name>\"";
  case PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED:
    return "bridge op is not allowed";
  case PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED:
    return "bridge payload is too large";
  case PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED:
    return "bridge page instance is invalid";
  case PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED:
    return "failed to allocate bridge request";
  case PROTON_ENGINE_BRIDGE_REQUEST_OK:
  default:
    return "";
  }
}

proton_engine_bridge_request_status_t proton_engine_bridge_build_request(
    const proton_bridge_config_t *bridge_config, const char *frame_url,
    const char *op, const char *payload, const char *page_instance,
    int32_t max_payload_bytes, int64_t *io_next_request_id,
    int64_t *out_request_id, char **out_source_origin) {
  if (out_request_id == NULL || out_source_origin == NULL) {
    return PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED;
  }
  *out_request_id = 0;
  *out_source_origin = NULL;
  if (bridge_config == NULL ||
      !proton_engine_bridge_config_allows_page(bridge_config, frame_url)) {
    return PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED;
  }
  char *source_origin = proton_engine_bridge_source_origin(frame_url);
  if (source_origin == NULL ||
      !proton_engine_bridge_config_allows_op(bridge_config, frame_url, op)) {
    free(source_origin);
    return proton_bridge_config_declares_op(bridge_config, op)
               ? PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED
               : PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN;
  }
  if (!proton_engine_bridge_payload_is_valid(payload,
                                             (size_t)max_payload_bytes)) {
    free(source_origin);
    return PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED;
  }
  if (!proton_engine_bridge_page_instance_is_valid(page_instance)) {
    free(source_origin);
    return PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED;
  }
  if (io_next_request_id == NULL) {
    free(source_origin);
    return PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED;
  }
  *out_request_id = (*io_next_request_id)++;
  if (*io_next_request_id <= 0) {
    *io_next_request_id = 1;
  }
  *out_source_origin = source_origin;
  return PROTON_ENGINE_BRIDGE_REQUEST_OK;
}
