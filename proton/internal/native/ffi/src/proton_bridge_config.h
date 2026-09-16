#ifndef PROTON_BRIDGE_CONFIG_H
#define PROTON_BRIDGE_CONFIG_H

#include "proton_internal.h"

#include <stddef.h>
#include <stdint.h>

typedef struct proton_bridge_config proton_bridge_config_t;

/* MoonBit owns one native reference; CEF retains only the native value. */
typedef struct {
  proton_bridge_config_t *value;
} proton_bridge_config_owner_t;

PROTON_INTERNAL proton_bridge_config_owner_t *
proton_internal_bridge_config_empty(void);
PROTON_INTERNAL proton_bridge_config_owner_t *
proton_internal_bridge_config_create(
    int32_t max_payload_bytes, int32_t *out_status);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_grant(
    proton_bridge_config_owner_t *handle, const char *source_origin,
    const char *const *ops, int32_t *out_grant_index);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_extension(
    proton_bridge_config_owner_t *handle, int32_t grant_index,
    const char *js_namespace, const char *const *apis);
PROTON_INTERNAL int32_t proton_internal_bridge_config_add_initialization_unit(
    proton_bridge_config_owner_t *handle, int32_t grant_index, const char *owner,
    const char *name, const char *source);
PROTON_INTERNAL void proton_bridge_config_retain(proton_bridge_config_t *config);
PROTON_INTERNAL int32_t proton_bridge_config_max_payload_bytes(
    const proton_bridge_config_t *config);
PROTON_INTERNAL int proton_bridge_config_has_grant(
    const proton_bridge_config_t *config, const char *source_origin);
PROTON_INTERNAL int proton_bridge_config_grant_allows_op(
    const proton_bridge_config_t *config, const char *source_origin,
    const char *op);
PROTON_INTERNAL int proton_bridge_config_declares_op(
    const proton_bridge_config_t *config, const char *op);
PROTON_INTERNAL size_t proton_bridge_config_grant_count(
    const proton_bridge_config_t *config);
PROTON_INTERNAL const char *proton_bridge_config_grant_source_origin(
    const proton_bridge_config_t *config, size_t grant_index);
PROTON_INTERNAL size_t proton_bridge_config_grant_op_count(
    const proton_bridge_config_t *config, size_t grant_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_op(
    const proton_bridge_config_t *config, size_t grant_index, size_t op_index);
PROTON_INTERNAL size_t proton_bridge_config_grant_extension_count(
    const proton_bridge_config_t *config, size_t grant_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_extension_namespace(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index);
PROTON_INTERNAL size_t proton_bridge_config_grant_extension_api_count(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_extension_api(
    const proton_bridge_config_t *config, size_t grant_index,
    size_t extension_index, size_t api_index);
PROTON_INTERNAL size_t proton_bridge_config_grant_initialization_unit_count(
    const proton_bridge_config_t *config, size_t grant_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_initialization_owner(
    const proton_bridge_config_t *config, size_t grant_index, size_t unit_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_initialization_name(
    const proton_bridge_config_t *config, size_t grant_index, size_t unit_index);
PROTON_INTERNAL const char *proton_bridge_config_grant_initialization_source(
    const proton_bridge_config_t *config, size_t grant_index, size_t unit_index);
PROTON_INTERNAL void proton_internal_bridge_config_destroy(
    proton_bridge_config_t *config);

#endif
