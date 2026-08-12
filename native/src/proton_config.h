#ifndef PROTON_CONFIG_H
#define PROTON_CONFIG_H

#include "proton_internal.h"

#include <stdbool.h>
#include <stddef.h>

PROTON_INTERNAL int32_t
proton_config_validate_runtime(const char *config_json);
PROTON_INTERNAL int32_t
proton_config_probe_runtime_layout(const char *config_json);
PROTON_INTERNAL bool
proton_config_default_helper_path(char *out, size_t out_len);
#ifdef __APPLE__
PROTON_INTERNAL bool proton_config_macos_bundle_helper_path(
    const char *executable_path, char *out, size_t out_len);
#endif
PROTON_INTERNAL bool
proton_config_runtime_requests_engine(const char *config_json);
PROTON_INTERNAL int32_t proton_config_validate_window(
    const char *config_json, int32_t *out_width, int32_t *out_height);

typedef struct {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t visible;
  int32_t z_order;
} proton_view_config_values_t;

PROTON_INTERNAL int32_t proton_config_validate_view(
    const char *config_json, proton_view_config_values_t *out_values);
PROTON_INTERNAL int32_t
proton_config_validate_bridge(const char *bridge_json);
PROTON_INTERNAL int32_t proton_config_validate_menu(const char *menu_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_response(const char *response_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_event(const char *event_json);

#endif
