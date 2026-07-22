#include "bridge_lifecycle.h"

#include "../../proton_json.h"
#include "proton_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES 65536

typedef struct {
  char *buffer;
  size_t capacity;
  size_t length;
  int truncated;
  int overflowed;
} proton_engine_json_writer_t;

static char *proton_engine_bridge_strdup(const char *value) {
  const char *source = value != NULL ? value : "";
  size_t len = strlen(source);
  char *copy = (char *)malloc(len + 1);
  if (copy != NULL) {
    memcpy(copy, source, len + 1);
  }
  return copy;
}

static void proton_engine_json_write_raw(proton_engine_json_writer_t *writer,
                                         const char *value, size_t len) {
  if (writer->length + len >= writer->capacity) {
    writer->truncated = 1;
    writer->overflowed = 1;
    return;
  }
  memcpy(writer->buffer + writer->length, value, len);
  writer->length += len;
  writer->buffer[writer->length] = '\0';
}

static void proton_engine_json_write_string(
    proton_engine_json_writer_t *writer, const char *value) {
  proton_engine_json_write_raw(writer, "\"", 1);
  const unsigned char *cursor =
      (const unsigned char *)(value != NULL ? value : "");
  while (*cursor != '\0') {
    char escaped[7];
    size_t escaped_len = 0;
    switch (*cursor) {
    case '\"':
      memcpy(escaped, "\\\"", 2);
      escaped_len = 2;
      break;
    case '\\':
      memcpy(escaped, "\\\\", 2);
      escaped_len = 2;
      break;
    case '\b':
      memcpy(escaped, "\\b", 2);
      escaped_len = 2;
      break;
    case '\f':
      memcpy(escaped, "\\f", 2);
      escaped_len = 2;
      break;
    case '\n':
      memcpy(escaped, "\\n", 2);
      escaped_len = 2;
      break;
    case '\r':
      memcpy(escaped, "\\r", 2);
      escaped_len = 2;
      break;
    case '\t':
      memcpy(escaped, "\\t", 2);
      escaped_len = 2;
      break;
    default:
      if (*cursor < 0x20) {
        snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
        escaped_len = 6;
      } else {
        escaped[0] = (char)*cursor;
        escaped_len = 1;
      }
      break;
    }
    if (writer->length + escaped_len + 2 >= writer->capacity) {
      writer->truncated = 1;
      break;
    }
    proton_engine_json_write_raw(writer, escaped, escaped_len);
    cursor++;
  }
  proton_engine_json_write_raw(writer, "\"", 1);
}

static void proton_engine_json_write_limited_string(
    proton_engine_json_writer_t *writer, const char *value, size_t max_bytes) {
  const char *source = value != NULL ? value : "";
  size_t len = strlen(source);
  if (len <= max_bytes) {
    proton_engine_json_write_string(writer, source);
    return;
  }
  size_t prefix_len = max_bytes;
  while (prefix_len > 0 &&
         (((const unsigned char *)source)[prefix_len] & 0xc0) == 0x80) {
    prefix_len--;
  }
  char *prefix = (char *)malloc(prefix_len + 1);
  if (prefix == NULL) {
    writer->truncated = 1;
    proton_engine_json_write_string(writer, "");
    return;
  }
  memcpy(prefix, source, prefix_len);
  prefix[prefix_len] = '\0';
  writer->truncated = 1;
  proton_engine_json_write_string(writer, prefix);
  free(prefix);
}

static void proton_engine_json_write_optional_limited_string(
    proton_engine_json_writer_t *writer, const char *field_name,
    const char *value, size_t max_bytes) {
  if (value == NULL || value[0] == '\0') {
    return;
  }
  size_t checkpoint = writer->length;
  int was_truncated = writer->truncated;
  int was_overflowed = writer->overflowed;
  writer->overflowed = 0;
  proton_engine_json_write_raw(writer, ",\"", 2);
  proton_engine_json_write_raw(writer, field_name, strlen(field_name));
  proton_engine_json_write_raw(writer, "\":", 2);
  proton_engine_json_write_limited_string(writer, value, max_bytes);
  int field_overflowed = writer->overflowed;
  if (field_overflowed) {
    writer->length = checkpoint;
    writer->buffer[checkpoint] = '\0';
  }
  writer->truncated = was_truncated || writer->truncated;
  writer->overflowed = was_overflowed || field_overflowed;
}

static char *proton_engine_bridge_copy_json_string(
    const proton_json_doc_t *doc, proton_json_value_t root,
    const char *field_name) {
  proton_json_value_t value;
  return proton_json_object_get(doc, root, field_name, &value)
             ? proton_json_copy_string(doc, value)
             : NULL;
}

static char *proton_engine_bridge_normalize_failure(
    const char *failure_json, const char *page_instance, const char *url) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  if (failure_json == NULL || !proton_json_parse(&doc, failure_json)) {
    return NULL;
  }
  if (!proton_json_root_object(&doc, &root)) {
    proton_json_dispose(&doc);
    return NULL;
  }
  char *stage = proton_engine_bridge_copy_json_string(&doc, root, "stage");
  char *code = proton_engine_bridge_copy_json_string(&doc, root, "code");
  char *message = proton_engine_bridge_copy_json_string(&doc, root, "message");
  char *owner = proton_engine_bridge_copy_json_string(&doc, root, "owner");
  char *source_url =
      proton_engine_bridge_copy_json_string(&doc, root, "source_url");
  char *source_line =
      proton_engine_bridge_copy_json_string(&doc, root, "source_line");
  char *stack = proton_engine_bridge_copy_json_string(&doc, root, "stack");
  proton_json_value_t truncated_value;
  bool source_truncated = false;
  if (proton_json_object_get(&doc, root, "details_truncated",
                             &truncated_value)) {
    (void)proton_json_read_bool(&doc, truncated_value, &source_truncated);
  }
  if (stage == NULL || code == NULL || message == NULL ||
      page_instance == NULL || url == NULL) {
    free(stage);
    free(code);
    free(message);
    free(owner);
    free(source_url);
    free(source_line);
    free(stack);
    proton_json_dispose(&doc);
    return NULL;
  }
  char *result =
      (char *)calloc(PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES, 1);
  if (result == NULL) {
    free(stage);
    free(code);
    free(message);
    free(owner);
    free(source_url);
    free(source_line);
    free(stack);
    proton_json_dispose(&doc);
    return NULL;
  }
  proton_engine_json_writer_t writer = {
      result, PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES - 96, 0,
      source_truncated ||
          strlen(failure_json) >= PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES,
      0};
  proton_engine_json_write_raw(&writer, "{\"abi_version\":1,\"stage\":", 25);
  proton_engine_json_write_limited_string(&writer, stage, 64);
  proton_engine_json_write_raw(&writer, ",\"code\":", 8);
  proton_engine_json_write_limited_string(&writer, code, 128);
  proton_engine_json_write_raw(&writer, ",\"message\":", 11);
  proton_engine_json_write_limited_string(&writer, message, 4096);
  proton_engine_json_write_raw(&writer, ",\"page_instance\":", 17);
  proton_engine_json_write_limited_string(&writer, page_instance, 128);
  proton_engine_json_write_raw(&writer, ",\"url\":", 7);
  proton_engine_json_write_limited_string(&writer, url, 4096);
  proton_engine_json_write_optional_limited_string(&writer, "owner", owner,
                                                   1024);
  proton_engine_json_write_optional_limited_string(
      &writer, "source_url", source_url, 4096);
  proton_engine_json_write_optional_limited_string(
      &writer, "source_line", source_line, 4096);
  proton_engine_json_write_optional_limited_string(&writer, "stack", stack,
                                                   16384);
  const char *number_fields[] = {"line", "column"};
  for (size_t index = 0; index < 2; index++) {
    proton_json_value_t value;
    int32_t number = 0;
    if (proton_json_object_get(&doc, root, number_fields[index], &value) &&
        proton_json_read_int32(&doc, value, &number)) {
      char field[64];
      snprintf(field, sizeof(field), ",\"%s\":%d", number_fields[index],
               number);
      proton_engine_json_write_raw(&writer, field, strlen(field));
    }
  }
  writer.capacity = PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES;
  proton_engine_json_write_raw(
      &writer, writer.truncated ? ",\"details_truncated\":true}"
                                : ",\"details_truncated\":false}",
      writer.truncated ? 26 : 27);
  free(stage);
  free(code);
  free(message);
  free(owner);
  free(source_url);
  free(source_line);
  free(stack);
  proton_json_dispose(&doc);
  return result;
}

static int32_t proton_engine_copy_result(const char *value, char *buffer,
                                         int32_t buffer_len,
                                         int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  size_t len = strlen(value != NULL ? value : "");
  if (len > INT32_MAX) {
    return PROTON_ERR_ENGINE;
  }
  *out_required_len = (int32_t)len;
  if (buffer == NULL || buffer_len <= (int32_t)len) {
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, value, len + 1);
  return PROTON_OK;
}

static char *proton_engine_bridge_failure_with_count(
    const char *failure_json, uint32_t additional_failure_count) {
  if (failure_json == NULL) {
    return NULL;
  }
  size_t len = strlen(failure_json);
  if (len < 2 || failure_json[len - 1] != '}') {
    return proton_engine_bridge_strdup(failure_json);
  }
  char suffix[96];
  int suffix_len = snprintf(suffix, sizeof(suffix),
                            ",\"additional_failure_count\":%u}",
                            additional_failure_count);
  if (suffix_len <= 0 || (size_t)suffix_len >= sizeof(suffix) ||
      len - 1 + (size_t)suffix_len >=
          PROTON_ENGINE_MAX_BRIDGE_DIAGNOSTIC_BYTES) {
    return proton_engine_bridge_strdup(failure_json);
  }
  char *result = (char *)malloc(len + (size_t)suffix_len);
  if (result == NULL) {
    return NULL;
  }
  memcpy(result, failure_json, len - 1);
  memcpy(result + len - 1, suffix, (size_t)suffix_len + 1);
  return result;
}

void proton_engine_bridge_lifecycle_init(
    proton_engine_bridge_lifecycle_t *lifecycle) {
  if (lifecycle != NULL) {
    memset(lifecycle, 0, sizeof(*lifecycle));
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
  free(lifecycle->failure_json);
  memset(lifecycle, 0, sizeof(*lifecycle));
}

int proton_engine_bridge_lifecycle_update(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *outcome,
    const char *page_instance, const char *url, const char *failure_json) {
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
      lifecycle->url != NULL &&
      strcmp(lifecycle->outcome, outcome) == 0 &&
      strcmp(lifecycle->page_instance, page_instance) == 0 &&
      strcmp(lifecycle->url, url) == 0) {
    return 0;
  }
  char *next_outcome = proton_engine_bridge_strdup(outcome);
  char *next_page_instance = proton_engine_bridge_strdup(page_instance);
  char *next_url = proton_engine_bridge_strdup(url);
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
  lifecycle->revision++;
  if (lifecycle->revision == 0) {
    lifecycle->revision = 1;
  }
  if (strcmp(outcome, "failed") == 0 && failure_json != NULL) {
    if (lifecycle->failure_json == NULL) {
      lifecycle->failure_json =
          proton_engine_bridge_normalize_failure(failure_json, page_instance,
                                                 url);
    } else {
      lifecycle->additional_failure_count++;
    }
  }
  return 1;
}

int proton_engine_bridge_lifecycle_report_browser_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *code, const char *message, int only_if_no_outcome) {
  if (lifecycle == NULL || url == NULL || code == NULL || message == NULL) {
    return 0;
  }
  int same_navigation = lifecycle->url != NULL && strcmp(lifecycle->url, url) == 0;
  if (only_if_no_outcome && same_navigation && lifecycle->outcome != NULL &&
      strcmp(lifecycle->outcome, "pending") != 0) {
    return 0;
  }
  char browser_page_instance[64];
  const char *page_instance =
      same_navigation && lifecycle->page_instance != NULL &&
              lifecycle->outcome != NULL &&
              strcmp(lifecycle->outcome, "pending") == 0
          ? lifecycle->page_instance
          : browser_page_instance;
  snprintf(browser_page_instance, sizeof(browser_page_instance),
           "browser-process-%llu",
           (unsigned long long)(lifecycle->revision + 1));
  char diagnostic[32768] = {0};
  proton_engine_json_writer_t writer = {
      diagnostic, sizeof(diagnostic) - 64, 0, 0, 0};
  proton_engine_json_write_raw(&writer, "{\"abi_version\":1,\"stage\":", 25);
  proton_engine_json_write_string(&writer, "prepare");
  proton_engine_json_write_raw(&writer, ",\"code\":", 8);
  proton_engine_json_write_limited_string(&writer, code, 128);
  proton_engine_json_write_raw(&writer, ",\"message\":", 11);
  proton_engine_json_write_limited_string(&writer, message, 4096);
  proton_engine_json_write_raw(&writer, ",\"page_instance\":", 17);
  proton_engine_json_write_limited_string(&writer, page_instance, 128);
  proton_engine_json_write_raw(&writer, ",\"url\":", 7);
  proton_engine_json_write_limited_string(&writer, url, 4096);
  writer.capacity = sizeof(diagnostic);
  proton_engine_json_write_raw(
      &writer, writer.truncated ? ",\"details_truncated\":true}"
                                : ",\"details_truncated\":false}",
      writer.truncated ? 26 : 27);
  if (page_instance == browser_page_instance) {
    proton_engine_bridge_lifecycle_update(lifecycle, "pending", page_instance,
                                          url, NULL);
  }
  return proton_engine_bridge_lifecycle_update(
      lifecycle, "failed", page_instance, url, diagnostic);
}

int proton_engine_bridge_lifecycle_report_load_failure(
    proton_engine_bridge_lifecycle_t *lifecycle, const char *url,
    const char *message, int navigation_cancelled) {
  // A cancelled navigation is normal browser control flow, not a bridge fault.
  if (navigation_cancelled) {
    return 0;
  }
  return proton_engine_bridge_lifecycle_report_browser_failure(
      lifecycle, url, "entry_load_failed", message, 0);
}

uint64_t proton_engine_bridge_lifecycle_revision(
    const proton_engine_bridge_lifecycle_t *lifecycle) {
  return lifecycle != NULL ? lifecycle->revision : 0;
}

int32_t proton_engine_bridge_lifecycle_state_json(
    const proton_engine_bridge_lifecycle_t *lifecycle, char *buffer,
    int32_t buffer_len, int32_t *out_required_len) {
  const char *outcome = lifecycle != NULL && lifecycle->outcome != NULL
                            ? lifecycle->outcome
                            : "none";
  const char *page_instance =
      lifecycle != NULL && lifecycle->page_instance != NULL
          ? lifecycle->page_instance
          : "";
  const char *url = lifecycle != NULL && lifecycle->url != NULL
                        ? lifecycle->url
                        : "";
  size_t source_bytes = strlen(outcome) + strlen(page_instance) + strlen(url);
  if (source_bytes > (SIZE_MAX - 512) / 6) {
    return PROTON_ERR_ENGINE;
  }
  size_t capacity = source_bytes * 6 + 512;
  char *json = (char *)calloc(capacity, 1);
  if (json == NULL) {
    return PROTON_ERR_ENGINE;
  }
  proton_engine_json_writer_t writer = {json, capacity, 0, 0, 0};
  static const char prefix[] = "{\"abi_version\":1,\"revision\":\"";
  static const char outcome_field[] = "\",\"outcome\":";
  static const char page_field[] = ",\"page_instance\":";
  static const char url_field[] = ",\"url\":";
  static const char failure_field[] = ",\"failure_pending\":";
  proton_engine_json_write_raw(&writer, prefix, sizeof(prefix) - 1);
  char revision[32];
  int revision_len = snprintf(revision, sizeof(revision), "%llu",
                              (unsigned long long)(lifecycle != NULL
                                                       ? lifecycle->revision
                                                       : 0));
  proton_engine_json_write_raw(&writer, revision, (size_t)revision_len);
  proton_engine_json_write_raw(&writer, outcome_field,
                               sizeof(outcome_field) - 1);
  proton_engine_json_write_string(&writer, outcome);
  proton_engine_json_write_raw(&writer, page_field, sizeof(page_field) - 1);
  proton_engine_json_write_string(&writer, page_instance);
  proton_engine_json_write_raw(&writer, url_field, sizeof(url_field) - 1);
  proton_engine_json_write_string(&writer, url);
  proton_engine_json_write_raw(&writer, failure_field,
                               sizeof(failure_field) - 1);
  proton_engine_json_write_raw(
      &writer,
      lifecycle != NULL && lifecycle->failure_json != NULL ? "true}" : "false}",
      lifecycle != NULL && lifecycle->failure_json != NULL ? 5 : 6);
  if (writer.truncated) {
    free(json);
    return PROTON_ERR_ENGINE;
  }
  int32_t status =
      proton_engine_copy_result(json, buffer, buffer_len, out_required_len);
  free(json);
  return status;
}

int32_t proton_engine_bridge_lifecycle_take_failure_json(
    proton_engine_bridge_lifecycle_t *lifecycle, char *buffer,
    int32_t buffer_len, int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (lifecycle == NULL || lifecycle->failure_json == NULL) {
    *out_required_len = 0;
    return PROTON_EVENT_NONE;
  }
  char *result = proton_engine_bridge_failure_with_count(
      lifecycle->failure_json, lifecycle->additional_failure_count);
  if (result == NULL) {
    return PROTON_ERR_ENGINE;
  }
  int32_t status =
      proton_engine_copy_result(result, buffer, buffer_len, out_required_len);
  free(result);
  if (status == PROTON_OK) {
    free(lifecycle->failure_json);
    lifecycle->failure_json = NULL;
    lifecycle->additional_failure_count = 0;
  }
  return status;
}
