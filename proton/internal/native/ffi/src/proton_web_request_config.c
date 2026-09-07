#include "proton_web_request_config.h"

#include <stdlib.h>
#include <string.h>

enum { PROTON_WEB_REQUEST_MAX_CANCEL_PREFIXES = 128 };

struct proton_web_request_config {
  size_t ref_count;
  char **cancel_prefixes;
  size_t cancel_prefix_count;
};

static char *proton_web_request_copy(const char *value) {
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy != NULL) {
    memcpy(copy, value, length + 1);
  }
  return copy;
}

proton_web_request_config_t *proton_internal_web_request_config_null(void) {
  return NULL;
}

int32_t proton_internal_web_request_config_create(
    proton_web_request_config_t **out_config) {
  if (out_config == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request config output is required");
  }
  proton_web_request_config_t *config =
      (proton_web_request_config_t *)calloc(1, sizeof(*config));
  if (config == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate web request configuration");
  }
  config->ref_count = 1;
  *out_config = config;
  return PROTON_OK;
}

int32_t proton_internal_web_request_config_add_cancel_prefix(
    proton_web_request_config_t *config, const char *url_prefix) {
  if (config == NULL || url_prefix == NULL || url_prefix[0] == '\0') {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request URL prefix must not be empty");
  }
  if (config->cancel_prefix_count >= PROTON_WEB_REQUEST_MAX_CANCEL_PREFIXES) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request cancellation prefix limit exceeded");
  }
  for (size_t index = 0; index < config->cancel_prefix_count; index++) {
    if (strcmp(config->cancel_prefixes[index], url_prefix) == 0) {
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "web request URL prefix is duplicated");
    }
  }
  char **prefixes = (char **)realloc(
      config->cancel_prefixes,
      (config->cancel_prefix_count + 1) * sizeof(*prefixes));
  char *copy = proton_web_request_copy(url_prefix);
  if (prefixes == NULL || copy == NULL) {
    free(copy);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate web request URL prefix");
  }
  config->cancel_prefixes = prefixes;
  config->cancel_prefixes[config->cancel_prefix_count++] = copy;
  return PROTON_OK;
}

void proton_web_request_config_retain(proton_web_request_config_t *config) {
  if (config != NULL) {
    config->ref_count++;
  }
}

int proton_web_request_config_should_cancel(
    const proton_web_request_config_t *config, const char *url) {
  if (config == NULL || url == NULL) {
    return 0;
  }
  for (size_t index = 0; index < config->cancel_prefix_count; index++) {
    size_t length = strlen(config->cancel_prefixes[index]);
    if (strncmp(url, config->cancel_prefixes[index], length) == 0) {
      return 1;
    }
  }
  return 0;
}

void proton_internal_web_request_config_destroy(
    proton_web_request_config_t *config) {
  if (config == NULL || config->ref_count == 0 || --config->ref_count != 0) {
    return;
  }
  for (size_t index = 0; index < config->cancel_prefix_count; index++) {
    free(config->cancel_prefixes[index]);
  }
  free(config->cancel_prefixes);
  free(config);
}
