#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_POLICY_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_POLICY_H

#include "../../proton_bridge_config.h"

int proton_engine_bridge_config_allows_page(
    const proton_bridge_config_t *bridge_config, const char *url);
int proton_engine_url_is_bridge_candidate(const char *url);
char *proton_engine_bridge_source_origin(const char *url);
int proton_engine_bridge_config_allows_op(
    const proton_bridge_config_t *bridge_config, const char *url,
    const char *op);

#endif
