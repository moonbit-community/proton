#include "proton_bridge_config.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
  PROTON_BRIDGE_MAX_PAYLOAD_BYTES = 1048576,
  PROTON_BRIDGE_MAX_GRANTS = 32,
  PROTON_BRIDGE_MAX_ITEMS = 256,
};

typedef struct {
  char **values;
  size_t count;
} proton_bridge_strings_t;

typedef struct {
  char *js_namespace;
  proton_bridge_strings_t apis;
} proton_bridge_extension_t;

typedef struct {
  char *owner;
  char *name;
  char *source;
} proton_bridge_initialization_unit_t;

typedef struct {
  char *source_origin;
  proton_bridge_strings_t ops;
  proton_bridge_extension_t *extensions;
  size_t extension_count;
  proton_bridge_initialization_unit_t *initialization_units;
  size_t initialization_unit_count;
} proton_bridge_grant_t;

struct proton_bridge_config {
  size_t ref_count;
  int32_t max_payload_bytes;
  proton_bridge_grant_t *grants;
  size_t grant_count;
};

static char *proton_bridge_copy(const char *value) {
  if (value == NULL) {
    return NULL;
  }
  size_t len = strlen(value);
  char *copy = (char *)malloc(len + 1);
  if (copy != NULL) {
    memcpy(copy, value, len + 1);
  }
  return copy;
}

static int proton_bridge_name_valid(const char *value) {
  if (value == NULL || value[0] == '\0') {
    return 0;
  }
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor;
       cursor++) {
    if (*cursor <= 0x20 || *cursor >= 0x7f || *cursor == '"' ||
        *cursor == '\\') {
      return 0;
    }
  }
  return 1;
}

static int proton_bridge_source_origin_valid(const char *origin) {
  if (origin == NULL) {
    return 0;
  }
  if (strcmp(origin, "app") == 0) {
    return 1;
  }
  const char *authority = NULL;
  if (strncmp(origin, "http://", 7) == 0) {
    authority = origin + 7;
  } else if (strncmp(origin, "https://", 8) == 0) {
    authority = origin + 8;
  }
  if (authority == NULL || authority[0] == '\0') {
    return 0;
  }
  return strpbrk(authority, "/?#") == NULL;
}

static int32_t proton_bridge_strings_add(proton_bridge_strings_t *strings,
                                         const char *value,
                                         const char *description) {
  if (!proton_bridge_name_valid(value)) {
    char message[128];
    snprintf(message, sizeof(message), "%s is invalid", description);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  if (strings->count >= PROTON_BRIDGE_MAX_ITEMS) {
    char message[128];
    snprintf(message, sizeof(message), "%s list is too large", description);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  for (size_t index = 0; index < strings->count; index++) {
    if (strcmp(strings->values[index], value) == 0) {
      char message[128];
      snprintf(message, sizeof(message), "%s is duplicated", description);
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
    }
  }
  char *copy = proton_bridge_copy(value);
  char **values = (char **)realloc(
      strings->values, (strings->count + 1) * sizeof(*values));
  if (copy == NULL || values == NULL) {
    free(copy);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate bridge configuration");
  }
  strings->values = values;
  strings->values[strings->count++] = copy;
  return PROTON_OK;
}

static proton_bridge_grant_t *proton_bridge_get_grant(
    proton_bridge_config_t *config, int32_t grant_index) {
  if (config == NULL || grant_index < 0 ||
      (size_t)grant_index >= config->grant_count) {
    return NULL;
  }
  return &config->grants[grant_index];
}

static const proton_bridge_grant_t *proton_bridge_get_const_grant(
    const proton_bridge_config_t *config, size_t grant_index) {
  if (config == NULL || grant_index >= config->grant_count) {
    return NULL;
  }
  return &config->grants[grant_index];
}

static const proton_bridge_extension_t *proton_bridge_get_const_extension(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  if (grant == NULL || extension_index >= grant->extension_count) {
    return NULL;
  }
  return &grant->extensions[extension_index];
}

proton_bridge_config_t *proton_internal_bridge_config_null(void) {
  return NULL;
}

int32_t proton_internal_bridge_config_create(
    int32_t max_payload_bytes, proton_bridge_config_t **out_config) {
  if (out_config == NULL || max_payload_bytes <= 0 ||
      max_payload_bytes > PROTON_BRIDGE_MAX_PAYLOAD_BYTES) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge max_payload_bytes is invalid");
  }
  proton_bridge_config_t *config =
      (proton_bridge_config_t *)calloc(1, sizeof(*config));
  if (config == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate bridge configuration");
  }
  config->max_payload_bytes = max_payload_bytes;
  config->ref_count = 1;
  *out_config = config;
  return PROTON_OK;
}

int32_t proton_internal_bridge_config_add_grant(
    proton_bridge_config_t *config, const char *source_origin,
    int32_t *out_grant_index) {
  if (config == NULL || out_grant_index == NULL ||
      !proton_bridge_source_origin_valid(source_origin)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge source_origin is invalid");
  }
  if (config->grant_count >= PROTON_BRIDGE_MAX_GRANTS) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge grants array is too large");
  }
  for (size_t index = 0; index < config->grant_count; index++) {
    if (strcmp(config->grants[index].source_origin, source_origin) == 0) {
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge config contains duplicate source origins");
    }
  }
  proton_bridge_grant_t *grants = (proton_bridge_grant_t *)realloc(
      config->grants, (config->grant_count + 1) * sizeof(*grants));
  char *origin_copy = proton_bridge_copy(source_origin);
  if (grants == NULL || origin_copy == NULL) {
    free(origin_copy);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate bridge grant");
  }
  config->grants = grants;
  proton_bridge_grant_t *grant = &config->grants[config->grant_count];
  memset(grant, 0, sizeof(*grant));
  grant->source_origin = origin_copy;
  *out_grant_index = (int32_t)config->grant_count;
  config->grant_count++;
  return PROTON_OK;
}

int32_t proton_internal_bridge_config_add_op(
    proton_bridge_config_t *config, int32_t grant_index, const char *name) {
  proton_bridge_grant_t *grant = proton_bridge_get_grant(config, grant_index);
  if (grant == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge grant index is invalid");
  }
  return proton_bridge_strings_add(&grant->ops, name, "bridge op name");
}

int32_t proton_internal_bridge_config_add_extension(
    proton_bridge_config_t *config, int32_t grant_index,
    const char *js_namespace, int32_t *out_extension_index) {
  proton_bridge_grant_t *grant = proton_bridge_get_grant(config, grant_index);
  if (grant == NULL || out_extension_index == NULL ||
      !proton_bridge_name_valid(js_namespace) ||
      grant->extension_count >= PROTON_BRIDGE_MAX_ITEMS) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge extension is invalid");
  }
  for (size_t index = 0; index < grant->extension_count; index++) {
    if (strcmp(grant->extensions[index].js_namespace, js_namespace) == 0) {
      return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                              "bridge extension namespace is duplicated");
    }
  }
  proton_bridge_extension_t *extensions =
      (proton_bridge_extension_t *)realloc(
          grant->extensions,
          (grant->extension_count + 1) * sizeof(*extensions));
  char *namespace_copy = proton_bridge_copy(js_namespace);
  if (extensions == NULL || namespace_copy == NULL) {
    free(namespace_copy);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate bridge extension");
  }
  grant->extensions = extensions;
  proton_bridge_extension_t *extension =
      &grant->extensions[grant->extension_count];
  memset(extension, 0, sizeof(*extension));
  extension->js_namespace = namespace_copy;
  *out_extension_index = (int32_t)grant->extension_count;
  grant->extension_count++;
  return PROTON_OK;
}

int32_t proton_internal_bridge_config_add_extension_api(
    proton_bridge_config_t *config, int32_t grant_index,
    int32_t extension_index, const char *api) {
  proton_bridge_grant_t *grant = proton_bridge_get_grant(config, grant_index);
  if (grant == NULL || extension_index < 0 ||
      (size_t)extension_index >= grant->extension_count) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge extension index is invalid");
  }
  return proton_bridge_strings_add(&grant->extensions[extension_index].apis,
                                   api, "bridge extension API");
}

int32_t proton_internal_bridge_config_add_initialization_unit(
    proton_bridge_config_t *config, int32_t grant_index, const char *owner,
    const char *name, const char *source) {
  proton_bridge_grant_t *grant = proton_bridge_get_grant(config, grant_index);
  if (grant == NULL || !proton_bridge_name_valid(owner) ||
      !proton_bridge_name_valid(name) || source == NULL ||
      grant->initialization_unit_count >= PROTON_BRIDGE_MAX_ITEMS) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge initialization unit is invalid");
  }
  proton_bridge_initialization_unit_t *units =
      (proton_bridge_initialization_unit_t *)realloc(
          grant->initialization_units,
          (grant->initialization_unit_count + 1) * sizeof(*units));
  proton_bridge_initialization_unit_t unit = {
      .owner = proton_bridge_copy(owner),
      .name = proton_bridge_copy(name),
      .source = proton_bridge_copy(source),
  };
  if (units == NULL || unit.owner == NULL || unit.name == NULL ||
      unit.source == NULL) {
    free(unit.owner);
    free(unit.name);
    free(unit.source);
    return proton_set_error(PROTON_ERR_ENGINE,
                            "failed to allocate bridge initialization unit");
  }
  grant->initialization_units = units;
  grant->initialization_units[grant->initialization_unit_count++] = unit;
  return PROTON_OK;
}

void proton_bridge_config_retain(proton_bridge_config_t *config) {
  if (config != NULL) {
    config->ref_count++;
  }
}

int32_t proton_bridge_config_max_payload_bytes(
    const proton_bridge_config_t *config) {
  return config != NULL ? config->max_payload_bytes : 0;
}

int proton_bridge_config_has_grant(const proton_bridge_config_t *config,
                                   const char *source_origin) {
  if (config == NULL || source_origin == NULL) {
    return 0;
  }
  for (size_t index = 0; index < config->grant_count; index++) {
    if (strcmp(config->grants[index].source_origin, source_origin) == 0) {
      return 1;
    }
  }
  return 0;
}

int proton_bridge_config_grant_allows_op(
    const proton_bridge_config_t *config, const char *source_origin,
    const char *op) {
  if (config == NULL || source_origin == NULL || op == NULL) {
    return 0;
  }
  for (size_t grant_index = 0; grant_index < config->grant_count;
       grant_index++) {
    const proton_bridge_grant_t *grant = &config->grants[grant_index];
    if (strcmp(grant->source_origin, source_origin) != 0) {
      continue;
    }
    for (size_t op_index = 0; op_index < grant->ops.count; op_index++) {
      if (strcmp(grant->ops.values[op_index], op) == 0) {
        return 1;
      }
    }
    return 0;
  }
  return 0;
}

int proton_bridge_config_declares_op(const proton_bridge_config_t *config,
                                     const char *op) {
  if (config == NULL || op == NULL) {
    return 0;
  }
  for (size_t grant_index = 0; grant_index < config->grant_count;
       grant_index++) {
    const proton_bridge_grant_t *grant = &config->grants[grant_index];
    for (size_t op_index = 0; op_index < grant->ops.count; op_index++) {
      if (strcmp(grant->ops.values[op_index], op) == 0) {
        return 1;
      }
    }
  }
  return 0;
}

size_t proton_bridge_config_grant_count(const proton_bridge_config_t *config) {
  return config != NULL ? config->grant_count : 0;
}

const char *proton_bridge_config_grant_source_origin(
    const proton_bridge_config_t *config, size_t grant_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL ? grant->source_origin : NULL;
}

size_t proton_bridge_config_grant_op_count(const proton_bridge_config_t *config,
                                           size_t grant_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL ? grant->ops.count : 0;
}

const char *proton_bridge_config_grant_op(const proton_bridge_config_t *config,
                                          size_t grant_index,
                                          size_t op_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL && op_index < grant->ops.count
             ? grant->ops.values[op_index]
             : NULL;
}

size_t proton_bridge_config_grant_extension_count(
    const proton_bridge_config_t *config, size_t grant_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL ? grant->extension_count : 0;
}

const char *proton_bridge_config_grant_extension_namespace(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index) {
  const proton_bridge_extension_t *extension = proton_bridge_get_const_extension(
      config, grant_index, extension_index);
  return extension != NULL ? extension->js_namespace : NULL;
}

size_t proton_bridge_config_grant_extension_api_count(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index) {
  const proton_bridge_extension_t *extension = proton_bridge_get_const_extension(
      config, grant_index, extension_index);
  return extension != NULL ? extension->apis.count : 0;
}

const char *proton_bridge_config_grant_extension_api(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index, size_t api_index) {
  const proton_bridge_extension_t *extension = proton_bridge_get_const_extension(
      config, grant_index, extension_index);
  return extension != NULL && api_index < extension->apis.count
             ? extension->apis.values[api_index]
             : NULL;
}

size_t proton_bridge_config_grant_initialization_unit_count(
    const proton_bridge_config_t *config, size_t grant_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL ? grant->initialization_unit_count : 0;
}

const char *proton_bridge_config_grant_initialization_owner(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t unit_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL && unit_index < grant->initialization_unit_count
             ? grant->initialization_units[unit_index].owner
             : NULL;
}

const char *proton_bridge_config_grant_initialization_name(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t unit_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL && unit_index < grant->initialization_unit_count
             ? grant->initialization_units[unit_index].name
             : NULL;
}

const char *proton_bridge_config_grant_initialization_source(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t unit_index) {
  const proton_bridge_grant_t *grant =
      proton_bridge_get_const_grant(config, grant_index);
  return grant != NULL && unit_index < grant->initialization_unit_count
             ? grant->initialization_units[unit_index].source
             : NULL;
}

void proton_internal_bridge_config_destroy(proton_bridge_config_t *config) {
  if (config == NULL || config->ref_count == 0 || --config->ref_count != 0) {
    return;
  }
  for (size_t grant_index = 0; grant_index < config->grant_count;
       grant_index++) {
    proton_bridge_grant_t *grant = &config->grants[grant_index];
    free(grant->source_origin);
    for (size_t index = 0; index < grant->ops.count; index++) {
      free(grant->ops.values[index]);
    }
    free(grant->ops.values);
    for (size_t extension_index = 0;
         extension_index < grant->extension_count; extension_index++) {
      proton_bridge_extension_t *extension =
          &grant->extensions[extension_index];
      free(extension->js_namespace);
      for (size_t api_index = 0; api_index < extension->apis.count;
           api_index++) {
        free(extension->apis.values[api_index]);
      }
      free(extension->apis.values);
    }
    free(grant->extensions);
    for (size_t unit_index = 0;
         unit_index < grant->initialization_unit_count; unit_index++) {
      proton_bridge_initialization_unit_t *unit =
          &grant->initialization_units[unit_index];
      free(unit->owner);
      free(unit->name);
      free(unit->source);
    }
    free(grant->initialization_units);
  }
  free(config->grants);
  free(config);
}
