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

/* Application resources are served by one factory shared by every engine. It
   is bound to two names: the proton:// transport scheme and the host-scoped
   HTTPS application origin. See app_origin.h for why the application itself
   lives on the HTTPS origin.

   The factory runs on CEF's IO thread while the main thread may be replacing
   or freeing a window's html state, so it snapshots everything through the
   window_state.h accessors under the engine's window lock and copies it before
   doing any disk-bound work. */

cef_resource_handler_t *CEF_CALLBACK proton_engine_scheme_create(
    cef_scheme_handler_factory_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    const cef_string_t *scheme_name,
    cef_request_t *request);

/* Declares proton:// to Chromium. Call from on_register_custom_schemes; the
   HTTPS origin needs no declaration because https is already standard. */
void proton_engine_register_app_custom_schemes(
    cef_scheme_registrar_t *registrar);

/* Binds `factory` to proton:// and to the HTTPS application origin. Returns 0
   if either registration is refused. */
int proton_engine_register_app_scheme_factory(
    cef_scheme_handler_factory_t *factory);

#endif
