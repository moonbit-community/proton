#include "bridge_lifecycle.h"

#include "proton_native.h"

#include "include/internal/cef_string.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *proton_engine_bridge_copy_limited(const char *value,
                                                size_t max_bytes,
                                                int *out_truncated) {
  const char *source = value != NULL ? value : "";
  size_t length = strlen(source);
  size_t copied = length;
  if (copied > max_bytes) {
    copied = max_bytes;
    while (copied > 0 &&
           (((const unsigned char *)source)[copied] & 0xc0) == 0x80) {
      copied--;
    }
    if (out_truncated != NULL) {
      *out_truncated = 1;
    }
  }
  char *result = (char *)malloc(copied + 1);
  if (result == NULL) {
    return NULL;
  }
  memcpy(result, source, copied);
  result[copied] = '\0';
  return result;
}

static char *proton_engine_bridge_copy_optional(const char *value,
                                                 size_t max_bytes,
                                                 int *out_truncated) {
  if (value == NULL || value[0] == '\0') {
    return NULL;
  }
  return proton_engine_bridge_copy_limited(value, max_bytes, out_truncated);
}

int proton_engine_urls_same_document(const char *left, const char *right) {
  if (left == NULL || right == NULL) {
    return 0;
  }
  size_t left_len = strcspn(left, "#");
  size_t right_len = strcspn(right, "#");
  return left_len == right_len && strncmp(left, right, left_len) == 0;
}

void proton_engine_bridge_diagnostic_init(
    proton_engine_bridge_diagnostic_t *diagnostic) {
  if (diagnostic != NULL) {
    memset(diagnostic, 0, sizeof(*diagnostic));
  }
}

void proton_engine_bridge_diagnostic_dispose(
    proton_engine_bridge_diagnostic_t *diagnostic) {
  if (diagnostic == NULL) {
    return;
  }
  free(diagnostic->stage);
  free(diagnostic->code);
  free(diagnostic->message);
  free(diagnostic->owner);
  free(diagnostic->source_url);
  free(diagnostic->source_line);
  free(diagnostic->stack);
  proton_engine_bridge_diagnostic_init(diagnostic);
}

int proton_engine_bridge_diagnostic_set(
    proton_engine_bridge_diagnostic_t *diagnostic,
    const proton_engine_bridge_diagnostic_input_t *input) {
  if (diagnostic == NULL || input == NULL || input->stage == NULL ||
      input->code == NULL || input->message == NULL) {
    return 0;
  }
  proton_engine_bridge_diagnostic_t next;
  proton_engine_bridge_diagnostic_init(&next);
  int truncated = input->details_truncated;
  next.stage = proton_engine_bridge_copy_limited(input->stage, 64, &truncated);
  next.code = proton_engine_bridge_copy_limited(input->code, 128, &truncated);
  next.message =
      proton_engine_bridge_copy_limited(input->message, 4096, &truncated);
  next.owner = proton_engine_bridge_copy_optional(input->owner, 1024, &truncated);
  next.source_url =
      proton_engine_bridge_copy_optional(input->source_url, 4096, &truncated);
  next.source_line =
      proton_engine_bridge_copy_optional(input->source_line, 4096, &truncated);
  next.stack = proton_engine_bridge_copy_optional(input->stack, 16384, &truncated);
  if (next.stage == NULL || next.code == NULL || next.message == NULL ||
      (input->owner != NULL && input->owner[0] != '\0' && next.owner == NULL) ||
      (input->source_url != NULL && input->source_url[0] != '\0' &&
       next.source_url == NULL) ||
      (input->source_line != NULL && input->source_line[0] != '\0' &&
       next.source_line == NULL) ||
      (input->stack != NULL && input->stack[0] != '\0' && next.stack == NULL)) {
    proton_engine_bridge_diagnostic_dispose(&next);
    return 0;
  }
  next.line = input->line;
  next.column = input->column;
  next.has_line = input->has_line != 0;
  next.has_column = input->has_column != 0;
  next.details_truncated = truncated != 0;
  proton_engine_bridge_diagnostic_dispose(diagnostic);
  *diagnostic = next;
  return 1;
}

int proton_engine_bridge_diagnostic_copy(
    proton_engine_bridge_diagnostic_t *destination,
    const proton_engine_bridge_diagnostic_t *source) {
  if (destination == NULL || source == NULL || source->stage == NULL ||
      source->code == NULL || source->message == NULL) {
    return 0;
  }
  proton_engine_bridge_diagnostic_input_t input = {
      .stage = source->stage,
      .code = source->code,
      .message = source->message,
      .owner = source->owner,
      .source_url = source->source_url,
      .source_line = source->source_line,
      .stack = source->stack,
      .line = source->line,
      .column = source->column,
      .has_line = source->has_line,
      .has_column = source->has_column,
      .details_truncated = source->details_truncated,
  };
  return proton_engine_bridge_diagnostic_set(destination, &input);
}

void proton_engine_bridge_lifecycle_init(
    proton_engine_bridge_lifecycle_t *lifecycle) {
  if (lifecycle != NULL) {
    memset(lifecycle, 0, sizeof(*lifecycle));
    proton_engine_bridge_diagnostic_init(&lifecycle->failure);
  }
}

void proton_engine_bridge_lifecycle_dispose(
    proton_engine_bridge_lifecycle_t *lifecycle) {
  if (lifecycle == NULL) {
    return;
  }
  free(lifecycle->outcome);
  free(lifecycle->page_instance);
  free(lifecycle->url);
  proton_engine_bridge_diagnostic_dispose(&lifecycle->failure);
  memset(lifecycle, 0, sizeof(*lifecycle));
}

void proton_engine_bridge_lifecycle_clear_failure(
    proton_engine_bridge_lifecycle_t *lifecycle) {
  if (lifecycle == NULL) {
    return;
  }
  proton_engine_bridge_diagnostic_dispose(&lifecycle->failure);
  lifecycle->has_failure = 0;
  lifecycle->additional_failure_count = 0;
}

int proton_engine_bridge_lifecycle_update(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *outcome,
    const char *page_instance, const char *url,
    const proton_engine_bridge_diagnostic_input_t *failure) {
  if (lifecycle == NULL || outcome == NULL || page_instance == NULL ||
      page_instance[0] == '\0' || url == NULL) {
    return 0;
  }
  if (strcmp(outcome, "pending") != 0 && strcmp(outcome, "ready") != 0 &&
      strcmp(outcome, "ineligible") != 0 && strcmp(outcome, "failed") != 0) {
    return 0;
  }
  int starts_attempt = strcmp(outcome, "pending") == 0;
  if (!starts_attempt && lifecycle->page_instance != NULL &&
      strcmp(lifecycle->page_instance, page_instance) != 0) {
    return 0;
  }
  int same_page = lifecycle->page_instance != NULL &&
                  strcmp(lifecycle->page_instance, page_instance) == 0;
  if (same_page && lifecycle->outcome != NULL &&
      strcmp(lifecycle->outcome, "pending") != 0) {
    return 0;
  }
  if (lifecycle->outcome != NULL && lifecycle->page_instance != NULL &&
      lifecycle->url != NULL && strcmp(lifecycle->outcome, outcome) == 0 &&
      strcmp(lifecycle->page_instance, page_instance) == 0 &&
      strcmp(lifecycle->url, url) == 0) {
    return 0;
  }
  char *next_outcome = proton_engine_bridge_copy_limited(outcome, 16, NULL);
  char *next_page_instance =
      proton_engine_bridge_copy_limited(page_instance, 128, NULL);
  char *next_url = proton_engine_bridge_copy_limited(url, 4096, NULL);
  if (next_outcome == NULL || next_page_instance == NULL || next_url == NULL) {
    free(next_outcome);
    free(next_page_instance);
    free(next_url);
    return 0;
  }
  free(lifecycle->outcome);
  free(lifecycle->page_instance);
  free(lifecycle->url);
  lifecycle->outcome = next_outcome;
  lifecycle->page_instance = next_page_instance;
  lifecycle->url = next_url;
  if (strcmp(outcome, "ready") == 0) {
    lifecycle->has_been_ready = 1;
  }
  lifecycle->revision++;
  if (lifecycle->revision == 0) {
    lifecycle->revision = 1;
  }
  if (strcmp(outcome, "failed") == 0 && failure != NULL) {
    if (!lifecycle->has_failure) {
      lifecycle->has_failure = proton_engine_bridge_diagnostic_set(
          &lifecycle->failure, failure);
    } else {
      lifecycle->additional_failure_count++;
    }
  }
  return 1;
}

static char *proton_engine_bridge_userfree_to_utf8(
    cef_string_userfree_t value) {
  if (value == NULL) {
    return NULL;
  }
  cef_string_utf8_t utf8 = {0};
  char *result = NULL;
  if (cef_string_utf16_to_utf8(value->str, value->length, &utf8) != 0 &&
      utf8.str != NULL) {
    result = (char *)malloc(utf8.length + 1);
    if (result != NULL) {
      memcpy(result, utf8.str, utf8.length);
      result[utf8.length] = '\0';
    }
  }
  cef_string_utf8_clear(&utf8);
  cef_string_userfree_utf16_free(value);
  return result;
}

int proton_engine_bridge_lifecycle_update_from_message(
    proton_engine_bridge_lifecycle_t *lifecycle, cef_list_value_t *arguments,
    const char *current_url) {
  if (lifecycle == NULL || arguments == NULL || current_url == NULL ||
      arguments->get_size(arguments) < 14) {
    return 0;
  }
  char *outcome =
      proton_engine_bridge_userfree_to_utf8(arguments->get_string(arguments, 0));
  char *page_instance =
      proton_engine_bridge_userfree_to_utf8(arguments->get_string(arguments, 1));
  char *url =
      proton_engine_bridge_userfree_to_utf8(arguments->get_string(arguments, 2));
  int has_diagnostic = arguments->get_bool(arguments, 3);
  char *stage = NULL;
  char *code = NULL;
  char *message = NULL;
  char *owner = NULL;
  char *source_url = NULL;
  char *source_line = NULL;
  char *stack = NULL;
  if (has_diagnostic) {
    stage = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 4));
    code = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 5));
    message = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 6));
    owner = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 7));
    source_url = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 8));
    source_line = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 9));
    stack = proton_engine_bridge_userfree_to_utf8(
        arguments->get_string(arguments, 10));
  }
  proton_engine_bridge_diagnostic_input_t diagnostic = {
      .stage = stage,
      .code = code,
      .message = message,
      .owner = owner,
      .source_url = source_url,
      .source_line = source_line,
      .stack = stack,
      .line = arguments->get_int(arguments, 11),
      .column = arguments->get_int(arguments, 12),
      .has_line = has_diagnostic,
      .has_column = has_diagnostic,
      .details_truncated = arguments->get_bool(arguments, 13),
  };
  int updated = proton_engine_urls_same_document(url, current_url) &&
                proton_engine_bridge_lifecycle_update(
                    lifecycle, outcome, page_instance, current_url,
                    has_diagnostic ? &diagnostic : NULL);
  free(outcome);
  free(page_instance);
  free(url);
  free(stage);
  free(code);
  free(message);
  free(owner);
  free(source_url);
  free(source_line);
  free(stack);
  return updated;
}

int proton_engine_bridge_lifecycle_report_browser_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *code, const char *message, int only_if_no_outcome) {
  if (lifecycle == NULL || url == NULL || code == NULL || message == NULL) {
    return 0;
  }
  int same_navigation = proton_engine_urls_same_document(lifecycle->url, url);
  if (only_if_no_outcome && same_navigation && lifecycle->outcome != NULL &&
      strcmp(lifecycle->outcome, "pending") != 0) {
    return 0;
  }
  char page_instance_buffer[64];
  const char *page_instance =
      same_navigation && lifecycle->page_instance != NULL &&
              lifecycle->outcome != NULL &&
              strcmp(lifecycle->outcome, "pending") == 0
          ? lifecycle->page_instance
          : page_instance_buffer;
  snprintf(page_instance_buffer, sizeof(page_instance_buffer),
           "browser-process-%llu",
           (unsigned long long)(lifecycle->revision + 1));
  proton_engine_bridge_diagnostic_input_t diagnostic = {
      .stage = "prepare",
      .code = code,
      .message = message,
  };
  if (page_instance == page_instance_buffer) {
    (void)proton_engine_bridge_lifecycle_update(lifecycle, "pending",
                                                page_instance, url, NULL);
  }
  return proton_engine_bridge_lifecycle_update(lifecycle, "failed",
                                                page_instance, url, &diagnostic);
}

int proton_engine_bridge_lifecycle_report_load_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *message, int navigation_cancelled) {
  if (navigation_cancelled || (lifecycle != NULL && lifecycle->has_been_ready)) {
    return 0;
  }
  return proton_engine_bridge_lifecycle_report_browser_failure(
      lifecycle, url, "entry_load_failed", message, 0);
}

uint64_t proton_engine_bridge_lifecycle_revision(
    const proton_engine_bridge_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->revision : 0;
}

static int32_t proton_engine_bridge_copy_result(const char *value, char *buffer,
                                                int32_t buffer_len,
                                                int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  size_t length = strlen(value != NULL ? value : "");
  if (length > INT32_MAX) {
    return PROTON_ERR_ENGINE;
  }
  *out_required_len = (int32_t)length;
  if (buffer == NULL || buffer_len <= (int32_t)length) {
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, value != NULL ? value : "", length + 1);
  return PROTON_OK;
}

int32_t proton_engine_bridge_lifecycle_copy_state_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len) {
  if (field < 0 || field > 2) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  const char *value = field == 0 ? "none" : "";
  if (lifecycle != NULL) {
    if (field == 0 && lifecycle->outcome != NULL) {
      value = lifecycle->outcome;
    } else if (field == 1 && lifecycle->page_instance != NULL) {
      value = lifecycle->page_instance;
    } else if (field == 2 && lifecycle->url != NULL) {
      value = lifecycle->url;
    }
  }
  return proton_engine_bridge_copy_result(value, buffer, buffer_len,
                                          out_required_len);
}

int32_t proton_engine_bridge_lifecycle_failure_present(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t *out_present) {
  if (out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_present = lifecycle != NULL && lifecycle->has_failure;
  return PROTON_OK;
}

int32_t proton_engine_bridge_lifecycle_copy_failure_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len) {
  if (lifecycle == NULL || !lifecycle->has_failure) {
    return PROTON_ERR_ENGINE;
  }
  const char *value = NULL;
  switch (field) {
  case 0: value = lifecycle->failure.stage; break;
  case 1: value = lifecycle->failure.code; break;
  case 2: value = lifecycle->failure.message; break;
  case 3: value = lifecycle->page_instance; break;
  case 4: value = lifecycle->url; break;
  case 5: value = lifecycle->failure.owner; break;
  case 6: value = lifecycle->failure.source_url; break;
  case 7: value = lifecycle->failure.source_line; break;
  case 8: value = lifecycle->failure.stack; break;
  default: return PROTON_ERR_INVALID_ARGUMENT;
  }
  return proton_engine_bridge_copy_result(value, buffer, buffer_len,
                                          out_required_len);
}

int32_t proton_engine_bridge_lifecycle_failure_int_field(
    const proton_engine_bridge_lifecycle_t *lifecycle, int32_t field,
    int32_t *out_value, int32_t *out_present) {
  if (out_value == NULL || out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (lifecycle == NULL || !lifecycle->has_failure) {
    return PROTON_ERR_ENGINE;
  }
  switch (field) {
  case 0:
    *out_value = lifecycle->failure.line;
    *out_present = lifecycle->failure.has_line;
    break;
  case 1:
    *out_value = lifecycle->failure.column;
    *out_present = lifecycle->failure.has_column;
    break;
  case 2:
    *out_value = (int32_t)lifecycle->additional_failure_count;
    *out_present = 1;
    break;
  case 3:
    *out_value = lifecycle->failure.details_truncated;
    *out_present = 1;
    break;
  default:
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}
