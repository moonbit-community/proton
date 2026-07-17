#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_JSON_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_JSON_H

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

static int proton_engine_url_is_proton_app(const char *url) {
  return url != NULL && strncmp(url, "proton://", 9) == 0;
}

static int proton_engine_url_is_bridge_candidate(const char *url) {
  return proton_engine_url_is_proton_app(url) ||
         (url != NULL &&
          (strncmp(url, "http://", 7) == 0 ||
           strncmp(url, "https://", 8) == 0));
}

static char *proton_engine_url_origin(const char *url) {
  size_t prefix_len = 0;
  if (url == NULL) {
    return NULL;
  }
  if (strncmp(url, "http://", 7) == 0) {
    prefix_len = 7;
  } else if (strncmp(url, "https://", 8) == 0) {
    prefix_len = 8;
  } else {
    return NULL;
  }
  const char *authority = url + prefix_len;
  if (*authority == '\0') {
    return NULL;
  }
  const char *end = authority;
  while (*end != '\0' && *end != '/' && *end != '?' && *end != '#') {
    end++;
  }
  if (end == authority) {
    return NULL;
  }
  return proton_engine_strdup_len(url, (size_t)(end - url));
}

typedef struct {
  const proton_json_doc_t *doc;
  const char *origin;
  int matched;
} proton_engine_bridge_origin_match_t;

static bool proton_engine_bridge_origin_match_item(proton_json_value_t value,
                                                   void *user_data) {
  proton_engine_bridge_origin_match_t *match =
      (proton_engine_bridge_origin_match_t *)user_data;
  char candidate[PROTON_ENGINE_MAX_PATH_BYTES];
  if (proton_json_read_string(match->doc, value, candidate,
                              sizeof(candidate)) &&
      strcmp(candidate, match->origin) == 0) {
    match->matched = 1;
    return false;
  }
  return true;
}

static int proton_engine_bridge_origin_policy_allows_origin(
    const proton_json_doc_t *doc,
    proton_json_value_t policy,
    const char *origin) {
  proton_json_value_t mode_value;
  proton_json_value_t origins_value;
  char mode[32];
  if (doc == NULL || origin == NULL ||
      !proton_json_object_get(doc, policy, "mode", &mode_value) ||
      !proton_json_read_string(doc, mode_value, mode, sizeof(mode))) {
    return 0;
  }
  if (strcmp(mode, "app_and_dev_origins") != 0) {
    return 0;
  }
  if (!proton_json_object_get(doc, policy, "dev_origins", &origins_value) ||
      !proton_json_is_array(doc, origins_value)) {
    return 0;
  }
  proton_engine_bridge_origin_match_t match = {doc, origin, 0};
  proton_json_array_each(doc, origins_value,
                         proton_engine_bridge_origin_match_item, &match);
  return match.matched;
}

static int proton_engine_bridge_config_allows_dev_origin(
    const char *bridge_config_json,
    const char *origin) {
  if (bridge_config_json == NULL || origin == NULL) {
    return 0;
  }
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t policy;
  if (!proton_json_parse(&doc, bridge_config_json)) {
    return 0;
  }
  int allowed = 0;
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "origin_policy", &policy) &&
      proton_json_is_object(&doc, policy)) {
    allowed =
        proton_engine_bridge_origin_policy_allows_origin(&doc, policy, origin);
  }
  proton_json_dispose(&doc);
  return allowed;
}

static int proton_engine_bridge_config_allows_page(
    const char *bridge_config_json,
    const char *url) {
  if (proton_engine_url_is_proton_app(url)) {
    return 1;
  }
  char *origin = proton_engine_url_origin(url);
  if (origin == NULL) {
    return 0;
  }
  int allowed =
      proton_engine_bridge_config_allows_dev_origin(bridge_config_json, origin);
  free(origin);
  return allowed;
}

static int proton_engine_bridge_config_is_dev_page(
    const char *bridge_config_json,
    const char *url) {
  if (proton_engine_url_is_proton_app(url)) {
    return 0;
  }
  return proton_engine_bridge_config_allows_page(bridge_config_json, url);
}

static char *proton_engine_bridge_config_copy_dev_bootstrap_script(
    const char *bridge_config_json) {
  return proton_engine_json_copy_string_field(bridge_config_json,
                                              "dev_bootstrap_script");
}

static char *proton_engine_bridge_wrap_dev_bootstrap_script(
    const char *script) {
  if (script == NULL) {
    return NULL;
  }
  const char *prefix =
      "if(window.__protonBridgeInstalled&&"
      "!window.__protonDevBootstrapInstalled){"
      "window.__protonDevBootstrapInstalled=true;\n";
  const char *suffix = "\n}";
  size_t prefix_len = strlen(prefix);
  size_t script_len = strlen(script);
  size_t suffix_len = strlen(suffix);
  if (script_len > SIZE_MAX - prefix_len - suffix_len - 1) {
    return NULL;
  }
  char *wrapped = (char *)malloc(prefix_len + script_len + suffix_len + 1);
  if (wrapped == NULL) {
    return NULL;
  }
  memcpy(wrapped, prefix, prefix_len);
  memcpy(wrapped + prefix_len, script, script_len);
  memcpy(wrapped + prefix_len + script_len, suffix, suffix_len);
  wrapped[prefix_len + script_len + suffix_len] = '\0';
  return wrapped;
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

static char *proton_engine_js_quote_string(const char *value) {
  if (value == NULL) {
    value = "";
  }
  size_t len = strlen(value);
  size_t cap = len * 2 + 3;
  char *quoted = (char *)malloc(cap);
  if (quoted == NULL) {
    return NULL;
  }
  size_t out = 0;
  quoted[out++] = '"';
  for (size_t i = 0; i < len; i++) {
    unsigned char ch = (unsigned char)value[i];
    if (out + 7 >= cap) {
      size_t next_cap = cap * 2;
      char *next = (char *)realloc(quoted, next_cap);
      if (next == NULL) {
        free(quoted);
        return NULL;
      }
      quoted = next;
      cap = next_cap;
    }
    switch (ch) {
    case '\\':
      quoted[out++] = '\\';
      quoted[out++] = '\\';
      break;
    case '"':
      quoted[out++] = '\\';
      quoted[out++] = '"';
      break;
    case '\b':
      quoted[out++] = '\\';
      quoted[out++] = 'b';
      break;
    case '\f':
      quoted[out++] = '\\';
      quoted[out++] = 'f';
      break;
    case '\n':
      quoted[out++] = '\\';
      quoted[out++] = 'n';
      break;
    case '\r':
      quoted[out++] = '\\';
      quoted[out++] = 'r';
      break;
    case '\t':
      quoted[out++] = '\\';
      quoted[out++] = 't';
      break;
    default:
      if (ch < 0x20) {
        static const char hex[] = "0123456789abcdef";
        quoted[out++] = '\\';
        quoted[out++] = 'u';
        quoted[out++] = '0';
        quoted[out++] = '0';
        quoted[out++] = hex[(ch >> 4) & 0xf];
        quoted[out++] = hex[ch & 0xf];
      } else {
        quoted[out++] = (char)ch;
      }
      break;
    }
  }
  quoted[out++] = '"';
  quoted[out] = '\0';
  return quoted;
}

#endif
