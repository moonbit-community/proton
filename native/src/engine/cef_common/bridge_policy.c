#include "bridge_policy.h"

#include "../../proton_json.h"

#include <stdlib.h>
#include <string.h>

static char *proton_engine_bridge_copy_prefix(const char *value, size_t len) {
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, len);
  copy[len] = '\0';
  return copy;
}

static int proton_engine_url_is_proton_app(const char *url) {
  return url != NULL && strncmp(url, "proton://", 9) == 0;
}

int proton_engine_url_is_bridge_candidate(const char *url) {
  return proton_engine_url_is_proton_app(url) ||
         (url != NULL && (strncmp(url, "http://", 7) == 0 ||
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
  const char *end = authority;
  while (*end != '\0' && *end != '/' && *end != '?' && *end != '#') {
    end++;
  }
  if (end == authority) {
    return NULL;
  }
  return proton_engine_bridge_copy_prefix(url, (size_t)(end - url));
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
  char *candidate = proton_json_copy_string(match->doc, value);
  if (candidate != NULL && strcmp(candidate, match->origin) == 0) {
    match->matched = 1;
  }
  free(candidate);
  return match->matched == 0;
}

static int proton_engine_bridge_config_allows_dev_origin(
    const char *bridge_config_json, const char *origin) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t policy;
  proton_json_value_t mode_value;
  proton_json_value_t origins_value;
  if (bridge_config_json == NULL || origin == NULL ||
      !proton_json_parse(&doc, bridge_config_json)) {
    return 0;
  }
  char *mode = NULL;
  int allowed = 0;
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "origin_policy", &policy) &&
      proton_json_is_object(&doc, policy) &&
      proton_json_object_get(&doc, policy, "mode", &mode_value) &&
      (mode = proton_json_copy_string(&doc, mode_value)) != NULL &&
      strcmp(mode, "app_and_dev_origins") == 0 &&
      proton_json_object_get(&doc, policy, "dev_origins", &origins_value) &&
      proton_json_is_array(&doc, origins_value)) {
    proton_engine_bridge_origin_match_t match = {&doc, origin, 0};
    proton_json_array_each(&doc, origins_value,
                           proton_engine_bridge_origin_match_item, &match);
    allowed = match.matched;
  }
  free(mode);
  proton_json_dispose(&doc);
  return allowed;
}

int proton_engine_bridge_config_allows_page(const char *bridge_config_json,
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
