#ifndef PROTON_BRIDGE_CONFIG_H
#define PROTON_BRIDGE_CONFIG_H

#include "proton_internal.h"

#include <stddef.h>
#include <stdint.h>

typedef struct proton_bridge_config proton_bridge_config_t;

PROTON_INTERNAL proton_bridge_config_t *proton_internal_bridge_config_null(void);
PROTON_INTERNAL int32_t proton_internal_bridge_config_create(
    int32_t max_payload_bytes, proton_bridge_config_t **out_config);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_grant(
    proton_bridge_config_t *config, const char *source_origin,
    int32_t *out_grant_index);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_op(
    proton_bridge_config_t *config, int32_t grant_index, const char *name);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_extension(
    proton_bridge_config_t *config, int32_t grant_index,
    const char *js_namespace, int32_t *out_extension_index);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_extension_api(
    proton_bridge_config_t *config, int32_t grant_index,
    int32_t extension_index, const char *api);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_initialization_unit(
    proton_bridge_config_t *config, int32_t grant_index, const char *owner,
    const char *name, const char *source);
PROTON_INTERNAL const char *proton_bridge_config_json(
    proton_bridge_config_t *config);
PROTON_INTERNAL int32_t proton_bridge_config_max_payload_bytes(
    const proton_bridge_config_t *config);
PROTON_INTERNAL void proton_internal_bridge_config_destroy(
    proton_bridge_config_t *config);

#endif
