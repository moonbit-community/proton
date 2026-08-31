#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_REQUEST_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_REQUEST_H

#include "bridge_policy.h"

#include <stddef.h>
#include <stdint.h>

#define PROTON_ENGINE_MAX_BRIDGE_PENDING 256
#define PROTON_ENGINE_MAX_BRIDGE_BYTES 1048576
#define PROTON_ENGINE_MAX_BRIDGE_OP_BYTES 128

typedef enum {
  PROTON_ENGINE_BRIDGE_REQUEST_OK = 0,
  PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED,
  PROTON_ENGINE_BRIDGE_REQUEST_OP_UNKNOWN,
  PROTON_ENGINE_BRIDGE_REQUEST_OP_DENIED,
  PROTON_ENGINE_BRIDGE_REQUEST_PAYLOAD_REJECTED,
  PROTON_ENGINE_BRIDGE_REQUEST_PAGE_INSTANCE_REJECTED,
  PROTON_ENGINE_BRIDGE_REQUEST_ALLOCATION_FAILED
} proton_engine_bridge_request_status_t;

int proton_engine_bridge_op_is_valid(const char *op);
int proton_engine_bridge_page_instance_is_valid(const char *page_instance);
int proton_engine_bridge_payload_is_valid(const char *payload,
                                          size_t max_bytes);
const char *proton_engine_bridge_request_reject_message(
    proton_engine_bridge_request_status_t status);

/* Validates one renderer request and assigns its browser-process request id.

   The payload remains opaque UTF-8 while it crosses native code. The caller
   owns the returned source origin and transfers the request fields to the
   native event queue individually, so C neither parses nor renders JSON. */
proton_engine_bridge_request_status_t proton_engine_bridge_build_request(
    const proton_bridge_config_t *bridge_config, const char *frame_url,
    const char *op, const char *payload, const char *page_instance,
    int32_t max_payload_bytes, int64_t *io_next_request_id,
    int64_t *out_request_id, char **out_source_origin);

#endif
