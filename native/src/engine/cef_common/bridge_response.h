#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_RESPONSE_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_RESPONSE_H

#include <stdint.h>

typedef struct {
  int64_t request_id;
  int ok;
  char *payload_json;
  char *error_json;
} proton_engine_bridge_response_t;

enum {
  PROTON_ENGINE_BRIDGE_RESPONSE_INVALID = 0,
  PROTON_ENGINE_BRIDGE_RESPONSE_OK = 1,
  PROTON_ENGINE_BRIDGE_RESPONSE_NO_MEMORY = -1,
};

int proton_engine_bridge_response_parse(
    const char *response_json,
    proton_engine_bridge_response_t *out_response);
void proton_engine_bridge_response_dispose(
    proton_engine_bridge_response_t *response);

#endif
