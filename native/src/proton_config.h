#ifndef PROTON_CONFIG_H
#define PROTON_CONFIG_H

#include "proton_internal.h"

#include <stdbool.h>

PROTON_INTERNAL int32_t
proton_config_validate_runtime(const char *config_json);
PROTON_INTERNAL int32_t
proton_config_probe_runtime_layout(const char *config_json);
PROTON_INTERNAL bool
proton_config_runtime_requests_engine(const char *config_json);
PROTON_INTERNAL int32_t proton_config_validate_window(
    const char *config_json, int32_t *out_width, int32_t *out_height);
PROTON_INTERNAL int32_t
proton_config_validate_bridge(const char *bridge_json);
PROTON_INTERNAL int32_t proton_config_validate_menu(const char *menu_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_response(const char *response_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_event(const char *event_json);

#endif
