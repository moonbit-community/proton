#ifndef PROTON_ENGINE_CEF_COMMON_BRIDGE_LIFECYCLE_H
#define PROTON_ENGINE_CEF_COMMON_BRIDGE_LIFECYCLE_H

#include <stddef.h>
#include <stdint.h>

#include "include/capi/cef_values_capi.h"

typedef struct {
  const char *stage;
  const char *code;
  const char *message;
  const char *owner;
  const char *source_url;
  const char *source_line;
  const char *stack;
  int32_t line;
  int32_t column;
  int has_line;
  int has_column;
  int details_truncated;
} proton_engine_bridge_diagnostic_input_t;

typedef struct {
  char *stage;
  char *code;
  char *message;
  char *owner;
  char *source_url;
  char *source_line;
  char *stack;
  int32_t line;
  int32_t column;
  int has_line;
  int has_column;
  int details_truncated;
} proton_engine_bridge_diagnostic_t;

typedef struct {
  uint64_t revision;
  char *outcome;
  char *page_instance;
  char *url;
  proton_engine_bridge_diagnostic_t failure;
  int has_failure;
  uint32_t additional_failure_count;
  int has_been_ready;
} proton_engine_bridge_lifecycle_t;

int proton_engine_urls_same_document(const char *left, const char *right);
void proton_engine_bridge_diagnostic_init(
    proton_engine_bridge_diagnostic_t *diagnostic);
void proton_engine_bridge_diagnostic_dispose(
    proton_engine_bridge_diagnostic_t *diagnostic);
int proton_engine_bridge_diagnostic_set(
    proton_engine_bridge_diagnostic_t *diagnostic,
    const proton_engine_bridge_diagnostic_input_t *input);
int proton_engine_bridge_diagnostic_copy(
    proton_engine_bridge_diagnostic_t *destination,
    const proton_engine_bridge_diagnostic_t *source);
void proton_engine_bridge_lifecycle_init(
    proton_engine_bridge_lifecycle_t *lifecycle);
void proton_engine_bridge_lifecycle_dispose(
    proton_engine_bridge_lifecycle_t *lifecycle);
int proton_engine_bridge_lifecycle_update(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *outcome,
    const char *page_instance, const char *url,
    const proton_engine_bridge_diagnostic_input_t *failure);
int proton_engine_bridge_lifecycle_update_from_message(
    proton_engine_bridge_lifecycle_t *lifecycle, cef_list_value_t *arguments,
    const char *current_url);
int proton_engine_bridge_lifecycle_report_browser_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *code, const char *message, int only_if_no_outcome);
int proton_engine_bridge_lifecycle_report_load_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *message, int navigation_cancelled);
uint64_t proton_engine_bridge_lifecycle_revision(
    const proton_engine_bridge_lifecycle_t *lifecycle);
int32_t proton_engine_bridge_lifecycle_copy_state_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len);
int32_t proton_engine_bridge_lifecycle_failure_present(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t *out_present);
int32_t proton_engine_bridge_lifecycle_copy_failure_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len);
int32_t proton_engine_bridge_lifecycle_failure_int_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    int32_t *out_value, int32_t *out_present);
void proton_engine_bridge_lifecycle_clear_failure(
    proton_engine_bridge_lifecycle_t *lifecycle);

#endif
