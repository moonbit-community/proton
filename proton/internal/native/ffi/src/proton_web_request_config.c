#include "proton_web_request_config.h"

#include <stdlib.h>
#include <string.h>

enum { PROTON_WEB_REQUEST_MAX_CANCEL_PREFIXES = 128 };

typedef struct {
  char *prefix;
  char *target;
} proton_web_request_redirect_t;
typedef struct { char *prefix; char *name; char *value; } proton_web_request_header_t;

struct proton_web_request_config {
  size_t ref_count;
  char **cancel_prefixes;
  size_t cancel_prefix_count;
  proton_web_request_redirect_t *redirects;
  size_t redirect_count;
  proton_web_request_header_t *headers;
  size_t header_count;
};

static char *proton_web_request_copy(const char *value) {
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy != NULL) {
    memcpy(copy, value, length + 1);
  }
  return copy;
}

int32_t proton_internal_web_request_config_add_header_prefix(
    proton_web_request_config_t *config, const char *url_prefix,
    const char *header_name, const char *header_value) {
  if (config == NULL || url_prefix == NULL || header_name == NULL ||
      header_value == NULL || url_prefix[0] == '\0' || header_name[0] == '\0')
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request header values are invalid");
  for (size_t i = 0; i < config->header_count; i++)
    if (strcmp(config->headers[i].prefix, url_prefix) == 0 &&
        strcmp(config->headers[i].name, header_name) == 0)
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "web request header rule is duplicated");
  proton_web_request_header_t *headers = (proton_web_request_header_t *)realloc(
      config->headers, (config->header_count + 1) * sizeof(*headers));
  char *prefix = proton_web_request_copy(url_prefix);
  char *name = proton_web_request_copy(header_name);
  char *value = proton_web_request_copy(header_value);
  if (headers == NULL || prefix == NULL || name == NULL || value == NULL) {
    free(prefix); free(name); free(value);
    return proton_set_error(PROTON_ERR_ENGINE, "failed to allocate web request header rule");
  }
  config->headers = headers;
  config->headers[config->header_count].prefix = prefix;
  config->headers[config->header_count].name = name;
  config->headers[config->header_count++].value = value;
  return PROTON_OK;
}

int32_t proton_internal_web_request_config_add_redirect_prefix(
    proton_web_request_config_t *config, const char *url_prefix,
    const char *target_url) {
  if (config == NULL || url_prefix == NULL || target_url == NULL ||
      url_prefix[0] == '\0' || target_url[0] == '\0') {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request redirect values must not be empty");
  }
  if (config->redirect_count >= PROTON_WEB_REQUEST_MAX_CANCEL_PREFIXES) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "web request redirect prefix limit exceeded");
  }
  for (size_t index = 0; index < config->redirect_count; index++) {
    if (strcmp(config->redirects[index].prefix, url_prefix) == 0) {
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "web request redirect prefix is duplicated");
    }
  }
  proton_web_request_redirect_t *redirects = (proton_web_request_redirect_t *)realloc(
      config->redirects, (config->redirect_count + 1) * sizeof(*redirects));
  char *prefix = proton_web_request_copy(url_prefix);
  char *target = proton_web_request_copy(target_url);
  if (redirects == NULL || prefix == NULL || target == NULL) {
    free(prefix);
    free(target);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate web request redirect");
  }
  config->redirects = redirects;
  config->redirects[config->redirect_count].prefix = prefix;
  config->redirects[config->redirect_count++].target = target;
  return PROTON_OK;
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

const char *proton_web_request_config_redirect_url(
    const proton_web_request_config_t *config, const char *url) {
  if (config == NULL || url == NULL) return NULL;
  for (size_t index = 0; index < config->redirect_count; index++) {
    size_t length = strlen(config->redirects[index].prefix);
    if (strncmp(url, config->redirects[index].prefix, length) == 0)
      return config->redirects[index].target;
  }
  return NULL;
}

const char *proton_web_request_config_header_value(
    const proton_web_request_config_t *config, const char *url,
    const char *header_name) {
  if (config == NULL || url == NULL || header_name == NULL) return NULL;
  for (size_t i = 0; i < config->header_count; i++) {
    size_t length = strlen(config->headers[i].prefix);
    if (strncmp(url, config->headers[i].prefix, length) == 0 &&
        strcmp(header_name, config->headers[i].name) == 0)
      return config->headers[i].value;
  }
  return NULL;
}

size_t proton_web_request_config_header_count(
    const proton_web_request_config_t *config, const char *url) {
  size_t count = 0;
  if (config == NULL || url == NULL) return 0;
  for (size_t i = 0; i < config->header_count; i++) {
    size_t length = strlen(config->headers[i].prefix);
    if (strncmp(url, config->headers[i].prefix, length) == 0) count++;
  }
  return count;
}

static const proton_web_request_header_t *proton_web_request_config_header_at(
    const proton_web_request_config_t *config, const char *url, size_t index) {
  if (config == NULL || url == NULL) return NULL;
  for (size_t i = 0; i < config->header_count; i++) {
    size_t length = strlen(config->headers[i].prefix);
    if (strncmp(url, config->headers[i].prefix, length) == 0) {
      if (index == 0) return &config->headers[i];
      index--;
    }
  }
  return NULL;
}

const char *proton_web_request_config_header_name_at(
    const proton_web_request_config_t *config, const char *url, size_t index) {
  const proton_web_request_header_t *header =
      proton_web_request_config_header_at(config, url, index);
  return header != NULL ? header->name : NULL;
}

const char *proton_web_request_config_header_value_at(
    const proton_web_request_config_t *config, const char *url, size_t index) {
  const proton_web_request_header_t *header =
      proton_web_request_config_header_at(config, url, index);
  return header != NULL ? header->value : NULL;
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
  for (size_t index = 0; index < config->redirect_count; index++) {
    free(config->redirects[index].prefix);
    free(config->redirects[index].target);
  }
  free(config->redirects);
  for (size_t index = 0; index < config->header_count; index++) {
    free(config->headers[index].prefix);
    free(config->headers[index].name);
    free(config->headers[index].value);
  }
  free(config->headers);
  free(config);
}
