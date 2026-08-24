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

typedef struct {
  const proton_json_doc_t *doc;
  char *output;
  size_t output_len;
  size_t used;
  bool valid;
} proton_engine_json_string_array_t;

static bool proton_engine_join_json_string(
    proton_json_value_t value, void *user_data) {
  proton_engine_json_string_array_t *array =
      (proton_engine_json_string_array_t *)user_data;
  char *item = proton_json_copy_string(array->doc, value);
  if (item == NULL || item[0] == '\0') {
    free(item);
    array->valid = false;
    return false;
  }
  size_t item_len = strlen(item);
  size_t separator_len = array->used == 0 ? 0 : 1;
  if (array->used + separator_len + item_len >= array->output_len) {
    free(item);
    array->valid = false;
    return false;
  }
  if (separator_len != 0) {
    array->output[array->used++] = ',';
  }
  memcpy(array->output + array->used, item, item_len);
  array->used += item_len;
  array->output[array->used] = '\0';
  free(item);
  return true;
}

static bool proton_engine_parse_json_string_array_field(
    const char *config_json, const char *field_name, char *out_value,
    size_t out_value_len) {
  if (out_value == NULL || out_value_len == 0) {
    return false;
  }
  out_value[0] = '\0';
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t value;
  if (!proton_json_parse(&doc, config_json)) {
    return false;
  }
  proton_engine_json_string_array_t array = {
      .doc = &doc,
      .output = out_value,
      .output_len = out_value_len,
      .used = 0,
      .valid = true,
  };
  bool ok = proton_json_root_object(&doc, &root) &&
            proton_json_object_get(&doc, root, field_name, &value) &&
            proton_json_is_array(&doc, value) &&
            proton_json_array_each(&doc, value,
                                   proton_engine_join_json_string, &array) &&
            array.valid;
  proton_json_dispose(&doc);
  if (!ok) {
    out_value[0] = '\0';
  }
  return ok;
}

#endif
