#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_POLICY_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_POLICY_H

int proton_engine_bridge_config_allows_page(const char *bridge_config_json,
                                            const char *url);
int proton_engine_url_is_bridge_candidate(const char *url);

#endif
