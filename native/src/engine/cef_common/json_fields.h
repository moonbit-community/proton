#ifndef PROTON_ENGINE_CEF_COMMON_JSON_FIELDS_H
#define PROTON_ENGINE_CEF_COMMON_JSON_FIELDS_H

static bool proton_engine_parse_json_int_field(const char *config_json,
                                               const char *field_name,
                                               int32_t *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_int32(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok;
}

static bool proton_engine_parse_json_bool_field(const char *config_json,
                                                const char *field_name,
                                                bool *out_value) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_bool(&doc, value, out_value);
  proton_json_dispose(&doc);
  return ok;
}

static bool proton_engine_parse_json_string_field(const char *config_json,
                                                  const char *field_name,
                                                  char *out_value,
                                                  size_t out_value_len) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_read_string(&doc, value, out_value, out_value_len);
  proton_json_dispose(&doc);
  return ok;
}

#endif
