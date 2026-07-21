#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_RENDERER_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_RENDERER_H

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_parser_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/capi/cef_values_capi.h"

#define PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE "proton.bridge.request"
#define PROTON_ENGINE_BRIDGE_RESPONSE_MESSAGE "proton.bridge.response"
#define PROTON_ENGINE_BRIDGE_EVENT_MESSAGE "proton.bridge.event"
#define PROTON_ENGINE_BRIDGE_CONTEXT_DISPOSED_MESSAGE \
  "proton.bridge.context_disposed"
#define PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION "__protonNativeInvokeOp"

cef_value_t *proton_engine_bridge_renderer_extra_info_value(
    const char *bridge_config_json);

int proton_engine_bridge_send_event(cef_browser_t *browser,
                                    const char *event_json);

void CEF_CALLBACK proton_engine_bridge_renderer_on_browser_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_dictionary_value_t *extra_info);

void CEF_CALLBACK proton_engine_bridge_renderer_on_browser_destroyed(
    cef_render_process_handler_t *self,
    cef_browser_t *browser);

void proton_engine_bridge_renderer_on_context_created(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context,
    cef_v8_handler_t *native_invoke_handler);

void proton_engine_bridge_renderer_on_context_released(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context);

int proton_engine_bridge_renderer_on_process_message_received(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message);

#endif
