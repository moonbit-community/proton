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

static int proton_engine_bridge_config_read_max_payload(
    const char *bridge_config_json,
    int32_t *out_value) {
  if (bridge_config_json == NULL || out_value == NULL) {
    return 0;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, bridge_config_json)) {
    return 0;
  }
  int ok = proton_json_root_object(&doc, &root) &&
           proton_json_object_get(&doc, root, "max_payload_bytes", &value) &&
           proton_json_read_int32(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok;
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

static int proton_engine_json_read_bool_field(const char *json,
                                              const char *field_name,
                                              int *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  bool bool_value = false;
  if (out_value == NULL || !proton_json_parse(&doc, json)) {
    return 0;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_bool(&doc, value, &bool_value);
  if (ok) {
    *out_value = bool_value ? 1 : 0;
  }
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

static char *proton_engine_json_copy_string_field(const char *json,
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
    copy = proton_json_copy_string(&doc, value);
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

static int proton_engine_bridge_config_allows_op(const char *bridge_config_json,
                                                 const char *op) {
  if (!proton_engine_bridge_op_is_valid(op) || bridge_config_json == NULL) {
    return 0;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t ops;
  if (!proton_json_parse(&doc, bridge_config_json)) {
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
  return match.allowed;
}

#endif
