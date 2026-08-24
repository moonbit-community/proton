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
  int32_t max_payload_bytes;
  proton_bridge_grant_t *grants;
  size_t grant_count;
  char *json;
};

typedef struct {
  char *data;
  size_t len;
  size_t capacity;
} proton_bridge_json_builder_t;

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

static int proton_bridge_json_reserve(proton_bridge_json_builder_t *builder,
                                      size_t extra) {
  if (builder->len + extra + 1 <= builder->capacity) {
    return 1;
  }
  size_t capacity = builder->capacity == 0 ? 256 : builder->capacity;
  while (capacity < builder->len + extra + 1) {
    if (capacity > SIZE_MAX / 2) {
      return 0;
    }
    capacity *= 2;
  }
  char *data = (char *)realloc(builder->data, capacity);
  if (data == NULL) {
    return 0;
  }
  builder->data = data;
  builder->capacity = capacity;
  return 1;
}

static int proton_bridge_json_append(proton_bridge_json_builder_t *builder,
                                     const char *value) {
  size_t len = strlen(value);
  if (!proton_bridge_json_reserve(builder, len)) {
    return 0;
  }
  memcpy(builder->data + builder->len, value, len);
  builder->len += len;
  builder->data[builder->len] = '\0';
  return 1;
}

static int proton_bridge_json_append_string(
    proton_bridge_json_builder_t *builder, const char *value) {
  if (!proton_bridge_json_append(builder, "\"")) {
    return 0;
  }
  for (const unsigned char *cursor = (const unsigned char *)value; *cursor;
       cursor++) {
    char escaped[7] = {0};
    const char *fragment = escaped;
    if (*cursor == '"') {
      fragment = "\\\"";
    } else if (*cursor == '\\') {
      fragment = "\\\\";
    } else if (*cursor == '\n') {
      fragment = "\\n";
    } else if (*cursor == '\r') {
      fragment = "\\r";
    } else if (*cursor == '\t') {
      fragment = "\\t";
    } else if (*cursor < 0x20) {
      snprintf(escaped, sizeof(escaped), "\\u%04x", (unsigned)*cursor);
    } else {
      escaped[0] = (char)*cursor;
    }
    if (!proton_bridge_json_append(builder, fragment)) {
      return 0;
    }
  }
  return proton_bridge_json_append(builder, "\"");
}

static int proton_bridge_json_append_strings(
    proton_bridge_json_builder_t *builder,
    const proton_bridge_strings_t *strings, int object_items) {
  if (!proton_bridge_json_append(builder, "[")) {
    return 0;
  }
  for (size_t index = 0; index < strings->count; index++) {
    if ((index > 0 && !proton_bridge_json_append(builder, ",")) ||
        (object_items && !proton_bridge_json_append(builder, "{\"name\":")) ||
        !proton_bridge_json_append_string(builder, strings->values[index]) ||
        (object_items && !proton_bridge_json_append(builder, "}"))) {
      return 0;
    }
  }
  return proton_bridge_json_append(builder, "]");
}

static int proton_bridge_json_render(proton_bridge_config_t *config) {
  proton_bridge_json_builder_t builder = {0};
  char max_payload[32];
  snprintf(max_payload, sizeof(max_payload), "%d", config->max_payload_bytes);
  if (!proton_bridge_json_append(
          &builder,
          "{\"abi_version\":2,\"namespace\":\"__MoonBit__\",\"grants\":[")) {
    goto failed;
  }
  for (size_t grant_index = 0; grant_index < config->grant_count;
       grant_index++) {
    proton_bridge_grant_t *grant = &config->grants[grant_index];
    if ((grant_index > 0 && !proton_bridge_json_append(&builder, ",")) ||
        !proton_bridge_json_append(&builder, "{\"source_origin\":") ||
        !proton_bridge_json_append_string(&builder, grant->source_origin) ||
        !proton_bridge_json_append(&builder, ",\"ops\":") ||
        !proton_bridge_json_append_strings(&builder, &grant->ops, 1) ||
        !proton_bridge_json_append(&builder, ",\"extensions\":[")) {
      goto failed;
    }
    for (size_t extension_index = 0;
         extension_index < grant->extension_count; extension_index++) {
      proton_bridge_extension_t *extension =
          &grant->extensions[extension_index];
      if ((extension_index > 0 &&
           !proton_bridge_json_append(&builder, ",")) ||
          !proton_bridge_json_append(&builder, "{\"namespace\":") ||
          !proton_bridge_json_append_string(&builder,
                                            extension->js_namespace) ||
          !proton_bridge_json_append(&builder, ",\"apis\":") ||
          !proton_bridge_json_append_strings(&builder, &extension->apis, 0) ||
          !proton_bridge_json_append(&builder, "}")) {
        goto failed;
      }
    }
    if (!proton_bridge_json_append(&builder, "],\"initialization_units\":[")) {
      goto failed;
    }
    for (size_t unit_index = 0;
         unit_index < grant->initialization_unit_count; unit_index++) {
      proton_bridge_initialization_unit_t *unit =
          &grant->initialization_units[unit_index];
      if ((unit_index > 0 && !proton_bridge_json_append(&builder, ",")) ||
          !proton_bridge_json_append(&builder, "{\"owner\":") ||
          !proton_bridge_json_append_string(&builder, unit->owner) ||
          !proton_bridge_json_append(&builder, ",\"name\":") ||
          !proton_bridge_json_append_string(&builder, unit->name) ||
          !proton_bridge_json_append(&builder, ",\"source\":") ||
          !proton_bridge_json_append_string(&builder, unit->source) ||
          !proton_bridge_json_append(&builder, "}")) {
        goto failed;
      }
    }
    if (!proton_bridge_json_append(&builder, "]}")) {
      goto failed;
    }
  }
  if (!proton_bridge_json_append(&builder, "],\"max_payload_bytes\":") ||
      !proton_bridge_json_append(&builder, max_payload) ||
      !proton_bridge_json_append(&builder, "}")) {
    goto failed;
  }
  config->json = builder.data;
  return 1;

failed:
  free(builder.data);
  return 0;
}

const char *proton_bridge_config_json(proton_bridge_config_t *config) {
  if (config == NULL) {
    return NULL;
  }
  if (config->json == NULL && !proton_bridge_json_render(config)) {
    proton_set_error(PROTON_ERR_ENGINE,
                     "failed to render bridge configuration");
    return NULL;
  }
  return config->json;
}

int32_t proton_bridge_config_max_payload_bytes(
    const proton_bridge_config_t *config) {
  return config != NULL ? config->max_payload_bytes : 0;
}

void proton_internal_bridge_config_destroy(proton_bridge_config_t *config) {
  if (config == NULL) {
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
  free(config->json);
  free(config);
}
