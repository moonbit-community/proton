#include "bridge_policy.h"

#include "app_origin.h"

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
#ifdef __APPLE__
  if (proton_engine_url_is_app(url)) {
    return 1;
  }
#endif
  if (url == NULL || strncmp(url, "proton://app", 12) != 0) {
    return 0;
  }
  char boundary = url[12];
  return boundary == '\0' || boundary == '/' || boundary == '?' ||
         boundary == '#';
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
  const char *source_origin;
  int matched;
  char *grant_json;
} proton_engine_bridge_origin_match_t;

static bool proton_engine_bridge_grant_match_item(proton_json_value_t value,
                                                  void *user_data) {
  proton_engine_bridge_origin_match_t *match =
      (proton_engine_bridge_origin_match_t *)user_data;
  proton_json_value_t origin_value;
  char *candidate = NULL;
  if (proton_json_is_object(match->doc, value) &&
      proton_json_object_get(match->doc, value, "source_origin",
                             &origin_value)) {
    candidate = proton_json_copy_string(match->doc, origin_value);
  }
  if (candidate != NULL && strcmp(candidate, match->source_origin) == 0) {
    match->matched = 1;
    match->grant_json = proton_json_copy_raw(match->doc, value);
  }
  free(candidate);
  return match->matched == 0;
}

char *proton_engine_bridge_source_origin(const char *url) {
  if (proton_engine_url_is_proton_app(url)) {
    return proton_engine_bridge_copy_prefix("app", 3);
  }
  return proton_engine_url_origin(url);
}

char *proton_engine_bridge_config_copy_grant(const char *bridge_config_json,
                                             const char *url) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t grants;
  char *source_origin = proton_engine_bridge_source_origin(url);
  if (bridge_config_json == NULL || source_origin == NULL ||
      !proton_json_parse(&doc, bridge_config_json)) {
    free(source_origin);
    return NULL;
  }
  proton_engine_bridge_origin_match_t match = {
      &doc, source_origin, 0, NULL};
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "grants", &grants) &&
      proton_json_is_array(&doc, grants)) {
    proton_json_array_each(&doc, grants, proton_engine_bridge_grant_match_item,
                           &match);
  }
  proton_json_dispose(&doc);
  free(source_origin);
  return match.grant_json;
}

int proton_engine_bridge_config_allows_page(const char *bridge_config_json,
                                            const char *url) {
  char *grant =
      proton_engine_bridge_config_copy_grant(bridge_config_json, url);
  int allowed = grant != NULL;
  free(grant);
  return allowed;
}
