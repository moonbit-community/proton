#ifndef PROTON_CONFIG_H
#define PROTON_CONFIG_H

#include "proton_internal.h"
#include "proton_engine.h"

#include <stdbool.h>
#include <stddef.h>

PROTON_INTERNAL int32_t proton_config_prepare_runtime(
    int32_t use_bundled, const char *runtime_root, const char *helper_path,
    const char *resources_dir, const char *locales_dir, const char *cache_dir,
    const char *locale, const char *accept_languages,
    const char *dialog_ok_label, const char *dialog_cancel_label,
    int32_t remote_debugging_port, int32_t headless,
    int32_t persist_session_cookies,
    proton_engine_runtime_config_t *out_config);
PROTON_INTERNAL int32_t proton_config_probe_runtime(
    const proton_engine_runtime_config_t *config);
PROTON_INTERNAL int32_t proton_config_prepare_window(
    const char *title, int32_t width, int32_t height, const char *initial_url,
    int32_t size_hint, int32_t titlebar_overlay, int32_t navigation_policy,
    const char *titlebar_minimize_label, const char *titlebar_maximize_label,
    const char *titlebar_restore_label, const char *titlebar_close_label,
    int32_t popup_policy, int32_t download_policy,
    int32_t certificate_policy, int32_t media_policy, int32_t devtools,
    const char *bridge_config_json,
    proton_engine_window_config_t *out_config);
PROTON_INTERNAL int32_t proton_config_prepare_view(
    int32_t x, int32_t y, int32_t width, int32_t height, int32_t visible,
    int32_t z_order, const char *initial_url, const char *background_color,
    proton_engine_view_config_t *out_config);
PROTON_INTERNAL bool
proton_config_default_helper_path(char *out, size_t out_len);
PROTON_INTERNAL bool
proton_config_default_runtime_root(char *out, size_t out_len);
#ifdef __APPLE__
PROTON_INTERNAL bool proton_config_macos_bundle_helper_path(
    const char *executable_path, char *out, size_t out_len);
#endif
PROTON_INTERNAL int32_t
proton_config_validate_bridge(const char *bridge_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_response(const char *response_json);
PROTON_INTERNAL int32_t
proton_config_validate_bridge_event(const char *event_json);

#endif
