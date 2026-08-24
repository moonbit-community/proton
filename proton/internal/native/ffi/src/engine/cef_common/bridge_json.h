#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_JSON_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_JSON_H

#include "bridge_policy.h"

static int proton_engine_bridge_op_is_valid(const char *op) {
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

/* Page instances are renderer-supplied but interpolated into bridge-request
   JSON by the browser process, so they must stay within the charset the
   renderer generator emits ("<pid>-<sequence>", i.e. digits and '-'). */
static int proton_engine_bridge_page_instance_is_valid(
    const char *page_instance) {
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

static int proton_engine_bridge_payload_is_valid(const char *payload_json,
                                                  size_t max_bytes) {
  if (payload_json == NULL || strlen(payload_json) > max_bytes) {
    return 0;
  }
  proton_json_doc_t doc;
  int valid = proton_json_parse(&doc, payload_json) &&
              proton_json_is_single_value(&doc);
  proton_json_dispose(&doc);
  return valid;
}

static int proton_engine_json_read_int64_field(const char *json,
                                               const char *field_name,
                                               int64_t *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, json)) {
    return 0;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_int64_string_or_number(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok ? 1 : 0;
}

static char *proton_engine_json_copy_raw_field(const char *json,
                                               const char *field_name) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, json)) {
    return NULL;
  }
  char *copy = NULL;
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, field_name, &value)) {
    copy = proton_json_copy_raw(&doc, value);
  }
  proton_json_dispose(&doc);
  return copy;
}

typedef struct {
  const proton_json_doc_t *doc;
  const char *op;
  int allowed;
} proton_engine_bridge_op_match_t;

static bool proton_engine_bridge_op_match_item(proton_json_value_t value,
                                               void *user_data) {
  proton_engine_bridge_op_match_t *match =
      (proton_engine_bridge_op_match_t *)user_data;
  proton_json_value_t name_value;
  char candidate[PROTON_ENGINE_MAX_BRIDGE_OP_BYTES];
  if (proton_json_is_object(match->doc, value) &&
      proton_json_object_get(match->doc, value, "name", &name_value) &&
      proton_json_read_string(match->doc, name_value, candidate,
                              sizeof(candidate)) &&
      strcmp(candidate, match->op) == 0) {
    match->allowed = 1;
    return false;
  }
  return true;
}

static int proton_engine_bridge_config_allows_op(
    const char *bridge_config_json, const char *url, const char *op) {
  if (!proton_engine_bridge_op_is_valid(op) || bridge_config_json == NULL ||
      url == NULL) {
    return 0;
  }
  char *grant_json =
      proton_engine_bridge_config_copy_grant(bridge_config_json, url);
  if (grant_json == NULL) {
    return 0;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t ops;
  if (!proton_json_parse(&doc, grant_json)) {
    free(grant_json);
    return 0;
  }
  proton_engine_bridge_op_match_t match = {&doc, op, 0};
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "ops", &ops) &&
      proton_json_is_array(&doc, ops)) {
    proton_json_array_each(&doc, ops, proton_engine_bridge_op_match_item,
                           &match);
  }
  proton_json_dispose(&doc);
  free(grant_json);
  return match.allowed;
}

typedef struct {
  const proton_json_doc_t *doc;
  const char *op;
  int declared;
} proton_engine_bridge_op_scan_t;

static bool proton_engine_bridge_grant_declares_op(proton_json_value_t value,
                                                   void *user_data) {
  proton_engine_bridge_op_scan_t *scan =
      (proton_engine_bridge_op_scan_t *)user_data;
  proton_json_value_t ops;
  if (!proton_json_is_object(scan->doc, value) ||
      !proton_json_object_get(scan->doc, value, "ops", &ops) ||
      !proton_json_is_array(scan->doc, ops)) {
    return true;
  }
  proton_engine_bridge_op_match_t match = {scan->doc, scan->op, 0};
  proton_json_array_each(scan->doc, ops, proton_engine_bridge_op_match_item,
                         &match);
  scan->declared = match.allowed;
  return scan->declared == 0;
}

/* Reports whether any grant in the configuration declares this op, regardless
   of which origin holds it. A request for an op that no grant declares is a
   different mistake from a request the page's own grant does not cover, and the
   two are worth separating in diagnostics: the first usually means the caller
   assembled the transport name by hand. */
static int proton_engine_bridge_config_declares_op(
    const char *bridge_config_json, const char *op) {
  if (!proton_engine_bridge_op_is_valid(op) || bridge_config_json == NULL) {
    return 0;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t grants;
  if (!proton_json_parse(&doc, bridge_config_json)) {
    return 0;
  }
  proton_engine_bridge_op_scan_t scan = {&doc, op, 0};
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "grants", &grants) &&
      proton_json_is_array(&doc, grants)) {
    proton_json_array_each(&doc, grants,
                           proton_engine_bridge_grant_declares_op, &scan);
  }
  proton_json_dispose(&doc);
  return scan.declared;
}

typedef enum {
  PROTON_ENGINE_BRIDGE_REQUEST_OK = 0,
  PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED,
  PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN,
  PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED,
  PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED,
  PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED,
  PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED
} proton_engine_bridge_request_status_t;

static const char *proton_engine_bridge_request_reject_event(
    proton_engine_bridge_request_status_t status) {
  switch (status) {
  case PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED:
    return "bridge_reject_origin_not_allowed";
  case PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN:
    return "bridge_reject_op_not_registered";
  case PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED:
    return "bridge_reject_not_allowed";
  case PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED:
    return "bridge_reject_payload_too_large";
  case PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED:
    return "bridge_reject_invalid_page_instance";
  case PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED:
    return "bridge_reject_allocation_failed";
  case PROTON_ENGINE_BRIDGE_REQUEST_OK:
  default:
    return "bridge_accept";
  }
}

static const char *proton_engine_bridge_request_reject_message(
    proton_engine_bridge_request_status_t status) {
  switch (status) {
  case PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED:
    return "bridge origin is not allowed";
  case PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN:
    return "bridge op is not registered; application commands are invoked as "
           "\"app:<name>\" and extension commands as \"ext:<namespace>/<name>\"";
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

/* Validates one renderer-supplied bridge request and renders its envelope.

   Origin derivation, grant matching, payload and page-instance validation, and
   the request-id assignment all live here so the per-platform message handlers
   share a single allocation-ownership path. The derived source origin is
   interned in this function alone; callers own only *out_request_json, and only
   when the status is PROTON_ENGINE_BRIDGE_REQUEST_OK.

   *io_next_request_id advances only once the request is accepted, so rejected
   requests do not consume ids. */
static proton_engine_bridge_request_status_t
proton_engine_bridge_build_request_json(
    const char *bridge_config_json, const char *frame_url, const char *op,
    const char *payload_json, const char *page_instance,
    int32_t max_payload_bytes, int64_t public_window_id,
    int64_t *io_next_request_id, int64_t *out_request_id,
    char **out_request_json) {
  *out_request_id = 0;
  *out_request_json = NULL;
  if (bridge_config_json == NULL ||
      !proton_engine_bridge_config_allows_page(bridge_config_json, frame_url)) {
    return PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED;
  }
  char *source_origin = proton_engine_bridge_source_origin(frame_url);
  if (source_origin == NULL ||
      !proton_engine_bridge_config_allows_op(bridge_config_json, frame_url,
                                             op)) {
    free(source_origin);
    return proton_engine_bridge_config_declares_op(bridge_config_json, op)
               ? PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED
               : PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN;
  }
  proton_engine_bridge_request_status_t status = PROTON_ENGINE_BRIDGE_REQUEST_OK;
  if (!proton_engine_bridge_payload_is_valid(payload_json,
                                             (size_t)max_payload_bytes)) {
    status = PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED;
  } else if (!proton_engine_bridge_page_instance_is_valid(page_instance)) {
    status = PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED;
  }
  if (status != PROTON_ENGINE_BRIDGE_REQUEST_OK) {
    free(source_origin);
    return status;
  }
  int64_t request_id = (*io_next_request_id)++;
  if (*io_next_request_id <= 0) {
    *io_next_request_id = 1;
  }
  size_t request_len = strlen(op) + strlen(payload_json) +
                       strlen(page_instance) + strlen(source_origin) + 288;
  char *request_json = (char *)malloc(request_len);
  if (request_json == NULL) {
    free(source_origin);
    return PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED;
  }
  snprintf(request_json, request_len,
           "{\"abi_version\":1,\"request_id\":\"%lld\",\"window\":\"%lld\","
           "\"op\":\"%s\",\"payload\":%s,\"page_instance\":\"%s\","
           "\"source_origin\":\"%s\"}",
           (long long)request_id, (long long)public_window_id, op, payload_json,
           page_instance, source_origin);
  free(source_origin);
  *out_request_id = request_id;
  *out_request_json = request_json;
  return PROTON_ENGINE_BRIDGE_REQUEST_OK;
}

#endif
