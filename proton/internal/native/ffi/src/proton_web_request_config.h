#ifndef PROTON_WEB_REQUEST_CONFIG_H
#define PROTON_WEB_REQUEST_CONFIG_H

#include "proton_internal.h"

#include <stddef.h>
#include <stdint.h>

typedef struct proton_web_request_config proton_web_request_config_t;

PROTON_INTERNAL proton_web_request_config_t *
proton_internal_web_request_config_null(void);
PROTON_INTERNAL int32_t proton_internal_web_request_config_create(
    proton_web_request_config_t **out_config);
PROTON_INTERNAL int32_t proton_internal_web_request_config_add_cancel_prefix(
    proton_web_request_config_t *config, const char *url_prefix);
PROTON_INTERNAL int32_t proton_internal_web_request_config_add_redirect_prefix(
    proton_web_request_config_t *config, const char *url_prefix,
    const char *target_url);
PROTON_INTERNAL void proton_web_request_config_retain(
    proton_web_request_config_t *config);
PROTON_INTERNAL int proton_web_request_config_should_cancel(
    const proton_web_request_config_t *config, const char *url);
PROTON_INTERNAL const char *proton_web_request_config_redirect_url(
    const proton_web_request_config_t *config, const char *url);
PROTON_INTERNAL void proton_internal_web_request_config_destroy(
    proton_web_request_config_t *config);

#endif
