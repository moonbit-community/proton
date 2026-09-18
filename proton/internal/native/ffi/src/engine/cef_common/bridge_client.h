#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_CLIENT_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_CLIENT_H

#include "../../proton_engine.h"
#include "bridge_request.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_v8_capi.h"

#include <stddef.h>

/* Owned by one platform window, borrowed by callbacks on the CEF UI thread.
 * The host retains its immutable config and owns all bridge lifecycle state.
 * Its runtime and request-id source must outlive it. */
typedef struct proton_engine_bridge_host proton_engine_bridge_host_t;

proton_engine_bridge_host_t *proton_engine_bridge_host_create(
    proton_engine_runtime_t *runtime, proton_window_id_t public_window,
    proton_bridge_config_t *config, int64_t *next_request_id);
void proton_engine_bridge_host_destroy(proton_engine_bridge_host_t *host);
int proton_engine_bridge_host_enabled(const proton_engine_bridge_host_t *host);
cef_dictionary_value_t *proton_engine_bridge_host_renderer_info(
    const proton_engine_bridge_host_t *host);
void proton_engine_bridge_host_load_finished(proton_engine_bridge_host_t *host,
    cef_frame_t *frame, const char *url);
void proton_engine_bridge_host_load_failed(proton_engine_bridge_host_t *host,
    cef_frame_t *frame, const char *url, const char *message, int cancelled);
void proton_engine_bridge_host_renderer_terminated(proton_engine_bridge_host_t *host,
    const char *url, int status, int error_code, const char *detail);
int32_t proton_engine_bridge_host_emit(proton_engine_bridge_host_t *host,
    cef_browser_t *browser, const char *event_json, char *error, size_t error_len);

/* Platform adapters return a borrowed host and preserve platform wakeups. */
proton_engine_bridge_host_t *proton_engine_window_bridge_host(
    proton_engine_window_t *window);
void proton_engine_bridge_signal(proton_engine_runtime_t *runtime);
void proton_engine_bridge_message_sent(proton_engine_runtime_t *runtime);

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
