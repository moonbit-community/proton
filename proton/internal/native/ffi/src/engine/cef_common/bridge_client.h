#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_CLIENT_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_CLIENT_H

#include "../../proton_engine.h"
#include "bridge_lifecycle.h"
#include "bridge_request.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_v8_capi.h"

#include <stddef.h>

typedef struct {
  proton_engine_runtime_t *runtime;
  proton_window_id_t public_window;
  proton_bridge_config_t *bridge_config;
  int32_t max_payload_bytes;
  int64_t *next_request_id;
  proton_engine_bridge_lifecycle_t *lifecycle;
} proton_engine_bridge_host_t;

/* Platform engines implement these two narrow adapters. */
int proton_engine_bridge_resolve_host(cef_browser_t *browser,
                                      proton_engine_bridge_host_t *out_host);
void proton_engine_bridge_signal(proton_engine_runtime_t *runtime);
void proton_engine_bridge_response_sent(proton_engine_runtime_t *runtime);

int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id,
    proton_window_id_t public_window, const char *op, const char *payload,
    const char *page_instance, const char *source_origin);
int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime, int64_t request_id);

int CEF_CALLBACK proton_engine_bridge_v8_execute(
    cef_v8_handler_t *self, const cef_string_t *name, cef_v8_value_t *object,
    size_t arguments_count, cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval, cef_string_t *exception);

int CEF_CALLBACK proton_engine_bridge_client_on_process_message_received(
    cef_client_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_process_id_t source_process, cef_process_message_t *message);

void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime, int browser_id);
void proton_engine_bridge_pending_clear_all(void);

#endif
