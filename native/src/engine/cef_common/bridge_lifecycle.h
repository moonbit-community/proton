#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_LIFECYCLE_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_LIFECYCLE_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint64_t revision;
  char *outcome;
  char *page_instance;
  char *url;
  char *failure_json;
  uint32_t additional_failure_count;
} proton_engine_bridge_lifecycle_t;

void proton_engine_bridge_lifecycle_init(
    proton_engine_bridge_lifecycle_t *lifecycle);
void proton_engine_bridge_lifecycle_dispose(
    proton_engine_bridge_lifecycle_t *lifecycle);
int proton_engine_bridge_lifecycle_update(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *outcome,
    const char *page_instance, const char *url, const char *failure_json);
int proton_engine_bridge_lifecycle_report_browser_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *code, const char *message, int only_if_no_outcome);
uint64_t proton_engine_bridge_lifecycle_revision(
    const proton_engine_bridge_lifecycle_t *lifecycle);
int32_t proton_engine_bridge_lifecycle_state_json(
    const proton_engine_bridge_lifecycle_t *lifecycle, char *buffer,
    int32_t buffer_len, int32_t *out_required_len);
int32_t proton_engine_bridge_lifecycle_take_failure_json(
    proton_engine_bridge_lifecycle_t *lifecycle, char *buffer,
    int32_t buffer_len, int32_t *out_required_len);

#endif
