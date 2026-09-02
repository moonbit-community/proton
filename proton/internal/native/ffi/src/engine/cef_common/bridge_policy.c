#include "bridge_policy.h"

#include "app_origin.h"

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
  if (proton_engine_url_is_app(url)) {
    return 1;
  }
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

char *proton_engine_bridge_source_origin(const char *url) {
  if (proton_engine_url_is_proton_app(url)) {
    return proton_engine_bridge_copy_prefix("app", 3);
  }
  return proton_engine_url_origin(url);
}

int proton_engine_bridge_config_allows_page(
    const proton_bridge_config_t *bridge_config, const char *url) {
  char *source_origin = proton_engine_bridge_source_origin(url);
  int allowed = proton_bridge_config_has_grant(bridge_config, source_origin);
  free(source_origin);
  return allowed;
}

int proton_engine_bridge_config_allows_op(
    const proton_bridge_config_t *bridge_config, const char *url,
    const char *op) {
  char *source_origin = proton_engine_bridge_source_origin(url);
  int allowed = proton_bridge_config_grant_allows_op(
      bridge_config, source_origin, op);
  free(source_origin);
  return allowed;
}
