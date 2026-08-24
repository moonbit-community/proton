#ifndef PROTON_ENGINE_CEF_COMMON_SCHEME_H
#define PROTON_ENGINE_CEF_COMMON_SCHEME_H

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_request_capi.h"
#include "include/capi/cef_resource_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"

#include "../../proton_engine.h"
#include "window_state.h"

#include <stddef.h>

/* Application resources are requested by CEF's IO thread and resolved by the
   MoonBit runtime. The handler retains CEF's continuation while the request is
   pending; native callbacks only enqueue events and never enter MoonBit. */

cef_resource_handler_t *CEF_CALLBACK proton_engine_scheme_create(
    cef_scheme_handler_factory_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    const cef_string_t *scheme_name,
    cef_request_t *request);

/* Completes one pending request. The handler copies `mime_type` and `data`
   before resuming CEF, so the caller retains ownership of both buffers. */
int32_t proton_engine_complete_resource_request(
    int64_t request_id, int32_t status, const char *mime_type,
    const void *data, size_t data_len);
void proton_engine_cancel_resource_requests(void);

/* Declares proton:// to Chromium. Call from on_register_custom_schemes; the
   HTTPS origin needs no declaration because https is already standard. */
void proton_engine_register_app_custom_schemes(
    cef_scheme_registrar_t *registrar);

/* Binds `factory` to proton:// and to the HTTPS application origin. Returns 0
   if either registration is refused. */
int proton_engine_register_app_scheme_factory(
    cef_scheme_handler_factory_t *factory);

#endif
