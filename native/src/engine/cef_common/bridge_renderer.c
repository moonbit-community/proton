#include "bridge_renderer.h"

#include "../../proton_json.h"
#include "bridge_policy.h"

#include <stddef.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "bridge_bootstrap.generated.h"

typedef struct proton_engine_bridge_browser_config {
  int browser_id;
  size_t instance_count;
  char *config_json;
  char *lifecycle_outcome;
  char *lifecycle_page_instance;
  char *lifecycle_url;
  char *lifecycle_diagnostic_json;
  struct proton_engine_bridge_browser_config *next;
} proton_engine_bridge_browser_config_t;

typedef struct proton_engine_bridge_context {
  int browser_id;
  cef_v8_context_t *context;
  cef_v8_value_t *dispatcher;
  char *page_instance;
  struct proton_engine_bridge_context *next;
} proton_engine_bridge_context_t;

static proton_engine_bridge_browser_config_t *g_browser_configs = NULL;
static proton_engine_bridge_context_t *g_contexts = NULL;
static uint64_t g_next_page_instance = 1;

static char *proton_engine_bridge_strdup(const char *value) {
  const char *source = value != NULL ? value : "";
  size_t len = strlen(source);
  char *copy = (char *)malloc(len + 1);
  if (copy != NULL) {
    memcpy(copy, source, len + 1);
  }
  return copy;
}

static unsigned long proton_engine_bridge_process_id(void) {
#if defined(_WIN32)
  return (unsigned long)GetCurrentProcessId();
#else
  return (unsigned long)getpid();
#endif
}

static void proton_engine_bridge_log(const char *format, ...) {
  const char *path = getenv("PROTON_NATIVE_LOG");
  if (path == NULL || path[0] == '\0' || format == NULL) {
    return;
  }
  FILE *file = fopen(path, "ab");
  if (file == NULL) {
    return;
  }
  va_list args;
  va_start(args, format);
  fprintf(file, "renderer pid=%lu ", proton_engine_bridge_process_id());
  vfprintf(file, format, args);
  va_end(args);
  fputc('\n', file);
  fclose(file);
}

static void proton_engine_bridge_set_string(cef_string_t *out,
                                            const char *value) {
  if (out == NULL) {
    return;
  }
  memset(out, 0, sizeof(*out));
  (void)cef_string_utf8_to_utf16(value != NULL ? value : "",
                                 value != NULL ? strlen(value) : 0, out);
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

static proton_engine_bridge_browser_config_t *
proton_engine_bridge_find_browser_config(cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_bridge_browser_config_t *entry = g_browser_configs;
       entry != NULL; entry = entry->next) {
    if (entry->browser_id == browser_id) {
      return entry;
    }
  }
  return NULL;
}

static char *proton_engine_bridge_frame_url(cef_frame_t *frame) {
  return frame != NULL
             ? proton_engine_bridge_userfree_to_utf8(frame->get_url(frame))
             : NULL;
}

static char *proton_engine_bridge_new_page_instance(void) {
  char value[96];
  uint64_t sequence = g_next_page_instance++;
  if (g_next_page_instance == 0) {
    g_next_page_instance = 1;
  }
  int written = snprintf(value, sizeof(value), "%lu-%llu",
                         proton_engine_bridge_process_id(),
                         (unsigned long long)sequence);
  if (written <= 0 || (size_t)written >= sizeof(value)) {
    return NULL;
  }
  char *copy = (char *)malloc((size_t)written + 1);
  if (copy != NULL) {
    memcpy(copy, value, (size_t)written + 1);
  }
  return copy;
}

typedef struct {
  char *buffer;
  size_t capacity;
  size_t length;
  int truncated;
  int overflowed;
} proton_engine_bridge_json_writer_t;

static void proton_engine_bridge_json_raw(
    proton_engine_bridge_json_writer_t *writer, const char *value) {
  size_t len = strlen(value);
  if (writer->length + len >= writer->capacity) {
    writer->truncated = 1;
    writer->overflowed = 1;
    return;
  }
  memcpy(writer->buffer + writer->length, value, len);
  writer->length += len;
  writer->buffer[writer->length] = '\0';
}

static void proton_engine_bridge_json_string(
    proton_engine_bridge_json_writer_t *writer, const char *value) {
  proton_engine_bridge_json_raw(writer, "\"");
  const unsigned char *cursor =
      (const unsigned char *)(value != NULL ? value : "");
  while (*cursor != '\0') {
    char escaped[7] = {0};
    switch (*cursor) {
    case '\"':
      memcpy(escaped, "\\\"", 3);
      break;
    case '\\':
      memcpy(escaped, "\\\\", 3);
      break;
    case '\n':
      memcpy(escaped, "\\n", 3);
      break;
    case '\r':
      memcpy(escaped, "\\r", 3);
      break;
    case '\t':
      memcpy(escaped, "\\t", 3);
      break;
    default:
      if (*cursor < 0x20) {
        snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
      } else {
        escaped[0] = (char)*cursor;
      }
      break;
    }
    size_t escaped_len = strlen(escaped);
    if (writer->length + escaped_len + 2 >= writer->capacity) {
      writer->truncated = 1;
      break;
    }
    proton_engine_bridge_json_raw(writer, escaped);
    cursor++;
  }
  proton_engine_bridge_json_raw(writer, "\"");
}

static void proton_engine_bridge_json_limited_string(
    proton_engine_bridge_json_writer_t *writer, const char *value,
    size_t max_bytes) {
  const char *source = value != NULL ? value : "";
  size_t source_len = strlen(source);
  if (source_len <= max_bytes) {
    proton_engine_bridge_json_string(writer, source);
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
    proton_engine_bridge_json_string(writer, "");
    return;
  }
  memcpy(prefix, source, prefix_len);
  prefix[prefix_len] = '\0';
  writer->truncated = 1;
  proton_engine_bridge_json_string(writer, prefix);
  free(prefix);
}

static void proton_engine_bridge_json_optional_string(
    proton_engine_bridge_json_writer_t *writer, const char *field_name,
    const char *value, size_t max_bytes) {
  if (value == NULL || value[0] == '\0') {
    return;
  }
  size_t checkpoint = writer->length;
  int was_truncated = writer->truncated;
  int was_overflowed = writer->overflowed;
  writer->overflowed = 0;
  proton_engine_bridge_json_raw(writer, ",\"");
  proton_engine_bridge_json_raw(writer, field_name);
  proton_engine_bridge_json_raw(writer, "\":");
  proton_engine_bridge_json_limited_string(writer, value, max_bytes);
  int field_overflowed = writer->overflowed;
  if (field_overflowed) {
    writer->length = checkpoint;
    writer->buffer[checkpoint] = '\0';
  }
  writer->truncated = was_truncated || writer->truncated;
  writer->overflowed = was_overflowed || field_overflowed;
}

static char *proton_engine_bridge_exception_string(
    cef_v8_exception_t *exception,
    cef_string_userfree_t(CEF_CALLBACK *getter)(cef_v8_exception_t *)) {
  return exception != NULL && getter != NULL
             ? proton_engine_bridge_userfree_to_utf8(getter(exception))
             : NULL;
}

static char *proton_engine_bridge_diagnostic_json(
    const char *stage, const char *code, const char *message,
    const char *page_instance, const char *url, const char *owner,
    const char *source_url, cef_v8_exception_t *exception) {
  enum { capacity = 65536 };
  char *json = (char *)calloc(capacity, 1);
  if (json == NULL) {
    return NULL;
  }
  char *exception_message = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_message : NULL);
  char *source_line = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_source_line : NULL);
  char *resource = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_script_resource_name
                                   : NULL);
  proton_engine_bridge_json_writer_t writer = {json, capacity - 64, 0, 0, 0};
  proton_engine_bridge_json_raw(&writer, "{\"abi_version\":1,\"stage\":");
  proton_engine_bridge_json_limited_string(&writer, stage, 64);
  proton_engine_bridge_json_raw(&writer, ",\"code\":");
  proton_engine_bridge_json_limited_string(&writer, code, 128);
  proton_engine_bridge_json_raw(&writer, ",\"message\":");
  proton_engine_bridge_json_limited_string(
      &writer, exception_message != NULL ? exception_message : message, 4096);
  proton_engine_bridge_json_raw(&writer, ",\"page_instance\":");
  proton_engine_bridge_json_limited_string(&writer, page_instance, 128);
  proton_engine_bridge_json_raw(&writer, ",\"url\":");
  proton_engine_bridge_json_limited_string(&writer, url, 4096);
  proton_engine_bridge_json_optional_string(&writer, "owner", owner, 1024);
  const char *resolved_source_url = resource != NULL && resource[0] != '\0'
                                        ? resource
                                        : source_url;
  proton_engine_bridge_json_optional_string(
      &writer, "source_url", resolved_source_url, 4096);
  proton_engine_bridge_json_optional_string(&writer, "source_line", source_line,
                                            4096);
  if (exception != NULL) {
    char location[96];
    snprintf(location, sizeof(location),
             ",\"line\":%d,\"column\":%d",
             exception->get_line_number(exception),
             exception->get_start_column(exception));
    proton_engine_bridge_json_raw(&writer, location);
  }
  writer.capacity = capacity;
  proton_engine_bridge_json_raw(
      &writer, writer.truncated ? ",\"details_truncated\":true}"
                                : ",\"details_truncated\":false}");
  free(exception_message);
  free(source_line);
  free(resource);
  return json;
}

static void proton_engine_bridge_record_lifecycle(
    cef_frame_t *frame, const char *outcome, const char *page_instance,
    const char *url, const char *diagnostic_json) {
  cef_browser_t *browser = frame->get_browser(frame);
  proton_engine_bridge_browser_config_t *config =
      proton_engine_bridge_find_browser_config(browser);
  if (config != NULL) {
    char *next_outcome = proton_engine_bridge_strdup(outcome);
    char *next_page_instance = proton_engine_bridge_strdup(page_instance);
    char *next_url = proton_engine_bridge_strdup(url);
    char *next_diagnostic = diagnostic_json != NULL
                                ? proton_engine_bridge_strdup(diagnostic_json)
                                : NULL;
    if (next_outcome != NULL && next_page_instance != NULL &&
        next_url != NULL &&
        (diagnostic_json == NULL || next_diagnostic != NULL)) {
      free(config->lifecycle_outcome);
      free(config->lifecycle_page_instance);
      free(config->lifecycle_url);
      free(config->lifecycle_diagnostic_json);
      config->lifecycle_outcome = next_outcome;
      config->lifecycle_page_instance = next_page_instance;
      config->lifecycle_url = next_url;
      config->lifecycle_diagnostic_json = next_diagnostic;
    } else {
      free(next_outcome);
      free(next_page_instance);
      free(next_url);
      free(next_diagnostic);
    }
  }
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static void proton_engine_bridge_send_lifecycle(
    cef_frame_t *frame, const char *outcome, const char *page_instance,
    const char *url, const char *diagnostic_json) {
  if (frame == NULL || outcome == NULL || page_instance == NULL || url == NULL) {
    return;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(&message_name,
                                  PROTON_ENGINE_BRIDGE_LIFECYCLE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    proton_engine_bridge_log("bridge_lifecycle_send outcome=%s created=0",
                             outcome);
    proton_engine_bridge_record_lifecycle(frame, outcome, page_instance, url,
                                          diagnostic_json);
    return;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  int populated = args != NULL && args->set_size(args, 4);
  const char *values[] = {outcome, page_instance, url,
                          diagnostic_json != NULL ? diagnostic_json : ""};
  for (size_t index = 0; populated && index < 4; index++) {
    cef_string_t value = {0};
    proton_engine_bridge_set_string(&value, values[index]);
    populated = args->set_string(args, index, &value);
    cef_string_clear(&value);
  }
  if (args != NULL) {
    args->base.release((cef_base_ref_counted_t *)args);
  }
  if (populated) {
    frame->send_process_message(frame, PID_BROWSER, message);
    proton_engine_bridge_log("bridge_lifecycle_send outcome=%s page=%s",
                             outcome, page_instance);
  } else {
    proton_engine_bridge_log(
        "bridge_lifecycle_send outcome=%s page=%s populated=0", outcome,
        page_instance);
    message->base.release((cef_base_ref_counted_t *)message);
  }
  proton_engine_bridge_record_lifecycle(frame, outcome, page_instance, url,
                                        diagnostic_json);
}

typedef struct {
  const proton_json_doc_t *doc;
  cef_v8_context_t *context;
  cef_frame_t *frame;
  const char *page_instance;
  const char *url;
  size_t index;
  int failed;
} proton_engine_bridge_initialization_t;

static void proton_engine_bridge_source_component(char *out, size_t out_len,
                                                  const char *value) {
  if (out == NULL || out_len == 0) {
    return;
  }
  size_t offset = 0;
  for (const unsigned char *cursor = (const unsigned char *)value;
       cursor != NULL && *cursor != '\0' && offset + 1 < out_len; cursor++) {
    unsigned char ch = *cursor;
    out[offset++] = (char)(((ch >= 'a' && ch <= 'z') ||
                            (ch >= 'A' && ch <= 'Z') ||
                            (ch >= '0' && ch <= '9') || ch == '-' ||
                            ch == '_' || ch == '.')
                               ? ch
                               : '_');
  }
  out[offset] = '\0';
}

static bool proton_engine_bridge_initialize_unit(proton_json_value_t value,
                                                 void *user_data) {
  proton_engine_bridge_initialization_t *initialization =
      (proton_engine_bridge_initialization_t *)user_data;
  proton_json_value_t owner_value;
  proton_json_value_t name_value;
  proton_json_value_t source_value;
  char *owner = NULL;
  char *name = NULL;
  char *source = NULL;
  const proton_json_doc_t *doc = initialization->doc;
  if (!proton_json_is_object(doc, value) ||
      !proton_json_object_get(doc, value, "owner", &owner_value) ||
      !proton_json_object_get(doc, value, "name", &name_value) ||
      !proton_json_object_get(doc, value, "source", &source_value)) {
    initialization->failed = 1;
    return false;
  }
  owner = proton_json_copy_string(doc, owner_value);
  name = proton_json_copy_string(doc, name_value);
  source = proton_json_copy_string(doc, source_value);
  if (owner == NULL || name == NULL || source == NULL) {
    free(owner);
    free(name);
    free(source);
    initialization->failed = 1;
    return false;
  }
  char owner_component[96];
  char name_component[96];
  proton_engine_bridge_source_component(owner_component,
                                        sizeof(owner_component), owner);
  proton_engine_bridge_source_component(name_component, sizeof(name_component),
                                        name);
  char source_url[256];
  snprintf(source_url, sizeof(source_url),
           "proton://bridge/initialization/%zu/%s/%s.js",
           initialization->index++, owner_component, name_component);
  cef_string_t code = {0};
  cef_string_t script_url = {0};
  proton_engine_bridge_set_string(&code, source);
  proton_engine_bridge_set_string(&script_url, source_url);
  cef_v8_value_t *result = NULL;
  cef_v8_exception_t *exception = NULL;
  int evaluated = initialization->context->eval(
      initialization->context, &code, &script_url, 1, &result, &exception);
  cef_string_clear(&code);
  cef_string_clear(&script_url);
  if (result != NULL) {
    result->base.release((cef_base_ref_counted_t *)result);
  }
  if (!evaluated || exception != NULL) {
    char *diagnostic = proton_engine_bridge_diagnostic_json(
        "initialization", "bridge_initialization_failed",
        "bridge initialization failed", initialization->page_instance,
        initialization->url, owner, source_url, exception);
    proton_engine_bridge_send_lifecycle(
        initialization->frame, "failed", initialization->page_instance,
        initialization->url, diagnostic);
    free(diagnostic);
    initialization->failed = 1;
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
  free(owner);
  free(name);
  free(source);
  return initialization->failed == 0;
}

static int proton_engine_bridge_initialize_units(
    const char *config_json, cef_v8_context_t *context, cef_frame_t *frame,
    const char *page_instance, const char *url) {
  proton_json_doc_t doc;
  proton_json_value_t root;
  proton_json_value_t units;
  if (!proton_json_parse(&doc, config_json)) {
    return 0;
  }
  int initialized = 1;
  if (proton_json_root_object(&doc, &root) &&
      proton_json_object_get(&doc, root, "initialization_units", &units)) {
    if (!proton_json_is_array(&doc, units)) {
      initialized = 0;
    } else {
      proton_engine_bridge_initialization_t initialization = {
          &doc, context, frame, page_instance, url, 0, 0};
      proton_json_array_each(&doc, units,
                             proton_engine_bridge_initialize_unit,
                             &initialization);
      initialized = !initialization.failed;
    }
  }
  proton_json_dispose(&doc);
  return initialized;
}

static cef_v8_value_t *proton_engine_bridge_get_property(
    cef_v8_value_t *object,
    const char *name) {
  if (object == NULL || name == NULL) {
    return NULL;
  }
  cef_string_t key = {0};
  proton_engine_bridge_set_string(&key, name);
  cef_v8_value_t *value = object->get_value_bykey(object, &key);
  cef_string_clear(&key);
  return value;
}

static cef_v8_value_t *proton_engine_bridge_execute(
    cef_v8_value_t *function,
    cef_v8_context_t *context,
    cef_v8_value_t *receiver,
    size_t argument_count,
    cef_v8_value_t **arguments) {
  int valid = function != NULL && context != NULL && receiver != NULL &&
              function->execute_function_with_context != NULL &&
              (argument_count == 0 || arguments != NULL);
  if (arguments != NULL) {
    for (size_t index = 0; index < argument_count; index++) {
      if (arguments[index] == NULL) {
        valid = 0;
      }
    }
  }
  if (!valid) {
    if (arguments != NULL) {
      for (size_t index = 0; index < argument_count; index++) {
        if (arguments[index] != NULL) {
          arguments[index]->base.release(
              (cef_base_ref_counted_t *)arguments[index]);
        }
      }
    }
    return NULL;
  }

  /* CEF's direct C API consumes refptr parameters. Keep the context and
     receiver references owned by the bridge while transferring arguments. */
  context->base.add_ref((cef_base_ref_counted_t *)context);
  receiver->base.add_ref((cef_base_ref_counted_t *)receiver);
  return function->execute_function_with_context(
      function, context, receiver, argument_count, arguments);
}

static void proton_engine_bridge_release_context_entry(
    proton_engine_bridge_context_t *entry,
    const char *reason) {
  if (entry == NULL) {
    return;
  }
  if (entry->context != NULL && entry->dispatcher != NULL &&
      entry->context->is_valid(entry->context) && entry->context->enter(entry->context)) {
    cef_v8_value_t *dispose = proton_engine_bridge_get_property(
        entry->dispatcher, "dispose");
    if (dispose != NULL && dispose->is_function(dispose)) {
      cef_string_t reason_string = {0};
      proton_engine_bridge_set_string(&reason_string, reason);
      cef_v8_value_t *argument = cef_v8_value_create_string(&reason_string);
      cef_string_clear(&reason_string);
      if (argument != NULL) {
        cef_v8_value_t *arguments[] = {argument};
        cef_v8_value_t *result = proton_engine_bridge_execute(
            dispose, entry->context, entry->dispatcher, 1, arguments);
        if (result != NULL) {
          result->base.release((cef_base_ref_counted_t *)result);
        }
      }
    }
    if (dispose != NULL) {
      dispose->base.release((cef_base_ref_counted_t *)dispose);
    }
    entry->context->exit(entry->context);
  }
  if (entry->dispatcher != NULL) {
    entry->dispatcher->base.release((cef_base_ref_counted_t *)entry->dispatcher);
  }
  if (entry->context != NULL) {
    entry->context->base.release((cef_base_ref_counted_t *)entry->context);
  }
  free(entry->page_instance);
  free(entry);
}

static void proton_engine_bridge_send_context_disposed(
    cef_frame_t *frame,
    const char *page_instance) {
  if (frame == NULL || page_instance == NULL || page_instance[0] == '\0') {
    return;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(
      &message_name, PROTON_ENGINE_BRIDGE_CONTEXT_DISPOSED_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  int sent = 0;
  if (args != NULL) {
    if (args->set_size(args, 1)) {
      cef_string_t value = {0};
      proton_engine_bridge_set_string(&value, page_instance);
      sent = args->set_string(args, 0, &value);
      cef_string_clear(&value);
    }
    args->base.release((cef_base_ref_counted_t *)args);
  }
  if (sent) {
    frame->send_process_message(frame, PID_BROWSER, message);
  } else {
    message->base.release((cef_base_ref_counted_t *)message);
  }
}

static proton_engine_bridge_context_t *proton_engine_bridge_find_context(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_bridge_context_t *entry = g_contexts; entry != NULL;
       entry = entry->next) {
    if (entry->browser_id == browser_id) {
      return entry;
    }
  }
  return NULL;
}

cef_value_t *proton_engine_bridge_renderer_extra_info_value(
    const char *bridge_config_json) {
  static const char prefix[] = "{\"bridge\":";
  static const char suffix[] = "}";
  if (bridge_config_json == NULL) {
    return NULL;
  }
  size_t config_len = strlen(bridge_config_json);
  size_t json_len = sizeof(prefix) - 1 + config_len + sizeof(suffix) - 1;
  if (json_len < config_len) {
    return NULL;
  }
  char *json = (char *)malloc(json_len + 1);
  if (json == NULL) {
    return NULL;
  }
  memcpy(json, prefix, sizeof(prefix) - 1);
  memcpy(json + sizeof(prefix) - 1, bridge_config_json, config_len);
  memcpy(json + sizeof(prefix) - 1 + config_len, suffix, sizeof(suffix));
  cef_string_t json_string = {0};
  (void)cef_string_utf8_to_utf16(json, json_len, &json_string);
  free(json);
  cef_value_t *value = cef_parse_json(&json_string, JSON_PARSER_RFC);
  cef_string_clear(&json_string);
  return value;
}

int proton_engine_bridge_send_event(cef_browser_t *browser,
                                    const char *event_json) {
  if (browser == NULL || event_json == NULL) {
    return 0;
  }
  cef_frame_t *frame = browser->get_main_frame(browser);
  if (frame == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(&message_name,
                                  PROTON_ENGINE_BRIDGE_EVENT_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  int sent = 0;
  if (args != NULL) {
    int populated = args->set_size(args, 1);
    if (populated) {
      cef_string_t event = {0};
      proton_engine_bridge_set_string(&event, event_json);
      populated = args->set_string(args, 0, &event);
      cef_string_clear(&event);
    }
    args->base.release((cef_base_ref_counted_t *)args);
    if (populated) {
      frame->send_process_message(frame, PID_RENDERER, message);
      sent = 1;
    }
  }
  if (!sent) {
    message->base.release((cef_base_ref_counted_t *)message);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
  return sent;
}

int proton_engine_bridge_send_lifecycle_probe(cef_frame_t *frame) {
  if (frame == NULL || !frame->is_main(frame)) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(
      &message_name, PROTON_ENGINE_BRIDGE_LIFECYCLE_PROBE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  frame->send_process_message(frame, PID_RENDERER, message);
  return 1;
}

static int proton_engine_bridge_store_browser_config(
    cef_browser_t *browser,
    char *config_json) {
  if (browser == NULL || config_json == NULL) {
    free(config_json);
    return 0;
  }
  proton_engine_bridge_browser_config_t *existing =
      proton_engine_bridge_find_browser_config(browser);
  if (existing != NULL) {
    /* During cross-origin navigation CEF may create a replacement browser with
       the same identifier before destroying the old renderer incarnation. */
    free(existing->config_json);
    existing->config_json = config_json;
    existing->instance_count++;
    return 1;
  }
  proton_engine_bridge_browser_config_t *entry =
      (proton_engine_bridge_browser_config_t *)calloc(1, sizeof(*entry));
  if (entry == NULL) {
    free(config_json);
    return 0;
  }
  entry->browser_id = browser->get_identifier(browser);
  entry->instance_count = 1;
  entry->config_json = config_json;
  entry->next = g_browser_configs;
  g_browser_configs = entry;
  return 1;
}

void CEF_CALLBACK proton_engine_bridge_renderer_on_browser_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_dictionary_value_t *extra_info) {
  (void)self;
  if (browser == NULL || extra_info == NULL) {
    return;
  }
  cef_string_t key = {0};
  proton_engine_bridge_set_string(&key, "bridge");
  cef_value_t *bridge_value = extra_info->get_value(extra_info, &key);
  cef_string_clear(&key);
  if (bridge_value == NULL) {
    return;
  }
  cef_string_userfree_t config =
      cef_write_json(bridge_value, JSON_WRITER_DEFAULT);
  char *config_json = proton_engine_bridge_userfree_to_utf8(config);
  int stored = proton_engine_bridge_store_browser_config(browser, config_json);
  proton_engine_bridge_log("renderer_bridge_config browser=%d stored=%d",
                           browser->get_identifier(browser), stored);
}

void CEF_CALLBACK proton_engine_bridge_renderer_on_browser_destroyed(
    cef_render_process_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  int browser_id = browser != NULL ? browser->get_identifier(browser) : 0;
  proton_engine_bridge_browser_config_t **config_cursor = &g_browser_configs;
  while (*config_cursor != NULL) {
    proton_engine_bridge_browser_config_t *entry = *config_cursor;
    if (entry->browser_id == browser_id) {
      if (entry->instance_count > 1) {
        entry->instance_count--;
        proton_engine_bridge_log(
            "bridge_browser_destroyed browser=%d remaining=%zu", browser_id,
            entry->instance_count);
        return;
      }
      *config_cursor = entry->next;
      free(entry->config_json);
      free(entry->lifecycle_outcome);
      free(entry->lifecycle_page_instance);
      free(entry->lifecycle_url);
      free(entry->lifecycle_diagnostic_json);
      free(entry);
      break;
    }
    config_cursor = &entry->next;
  }
  proton_engine_bridge_log("bridge_browser_destroyed browser=%d remaining=0",
                           browser_id);
  proton_engine_bridge_context_t **context_cursor = &g_contexts;
  while (*context_cursor != NULL) {
    proton_engine_bridge_context_t *entry = *context_cursor;
    if (entry->browser_id == browser_id) {
      *context_cursor = entry->next;
      proton_engine_bridge_release_context_entry(
          entry, "Proton bridge browser was destroyed");
      continue;
    }
    context_cursor = &entry->next;
  }
}

void proton_engine_bridge_renderer_on_context_created(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context,
    cef_v8_handler_t *native_invoke_handler) {
  if (browser == NULL || frame == NULL || context == NULL ||
      native_invoke_handler == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_bridge_browser_config_t *browser_config =
      proton_engine_bridge_find_browser_config(browser);
  if (browser_config == NULL || browser_config->config_json == NULL) {
    return;
  }

  char *url = proton_engine_bridge_frame_url(frame);
  char *page_instance = proton_engine_bridge_new_page_instance();
  if (url == NULL || page_instance == NULL) {
    free(url);
    free(page_instance);
    return;
  }
  proton_engine_bridge_send_lifecycle(frame, "pending", page_instance, url,
                                      NULL);
  if (!proton_engine_bridge_config_allows_page(browser_config->config_json,
                                                url)) {
    proton_engine_bridge_send_lifecycle(frame, "ineligible", page_instance,
                                        url, NULL);
    free(url);
    free(page_instance);
    return;
  }
  if (!context->enter(context)) {
    char *diagnostic = proton_engine_bridge_diagnostic_json(
        "prepare", "bridge_context_enter_failed",
        "failed to enter the main frame JavaScript context", page_instance,
        url, NULL, NULL, NULL);
    proton_engine_bridge_send_lifecycle(frame, "failed", page_instance, url,
                                        diagnostic);
    free(diagnostic);
    free(url);
    free(page_instance);
    return;
  }

  cef_string_t native_name = {0};
  proton_engine_bridge_set_string(&native_name,
                                  PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION);
  native_invoke_handler->base.add_ref(
      (cef_base_ref_counted_t *)native_invoke_handler);
  cef_v8_value_t *native_invoke =
      cef_v8_value_create_function(&native_name, native_invoke_handler);
  cef_string_clear(&native_name);

  cef_v8_value_t *global = context->get_global(context);
  cef_string_t native_key = {0};
  proton_engine_bridge_set_string(&native_key,
                                  PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION);
  int native_installed =
      global != NULL && native_invoke != NULL &&
      global->set_value_bykey(global, &native_key, native_invoke,
                              V8_PROPERTY_ATTRIBUTE_DONTENUM);
  if (native_installed) {
    native_invoke = NULL;
  }

  static const char invocation_separator[] =
      "(globalThis." PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION ",";
  static const char invocation_page_separator[] = ",\"";
  static const char invocation_suffix[] = "\")";
  size_t config_len = strlen(browser_config->config_json);
  size_t page_instance_len = strlen(page_instance);
  size_t invocation_len = proton_engine_bridge_bootstrap_source_len +
                          sizeof(invocation_separator) - 1 + config_len +
                          sizeof(invocation_page_separator) - 1 +
                          page_instance_len + sizeof(invocation_suffix) - 1;
  char *invocation = NULL;
  if (native_installed && invocation_len >= config_len) {
    invocation = (char *)malloc(invocation_len + 1);
  }
  if (invocation != NULL) {
    size_t offset = 0;
    memcpy(invocation + offset, proton_engine_bridge_bootstrap_source,
           proton_engine_bridge_bootstrap_source_len);
    offset += proton_engine_bridge_bootstrap_source_len;
    memcpy(invocation + offset, invocation_separator,
           sizeof(invocation_separator) - 1);
    offset += sizeof(invocation_separator) - 1;
    memcpy(invocation + offset, browser_config->config_json, config_len);
    offset += config_len;
    memcpy(invocation + offset, invocation_page_separator,
           sizeof(invocation_page_separator) - 1);
    offset += sizeof(invocation_page_separator) - 1;
    memcpy(invocation + offset, page_instance, page_instance_len);
    offset += page_instance_len;
    memcpy(invocation + offset, invocation_suffix,
           sizeof(invocation_suffix) - 1);
    offset += sizeof(invocation_suffix) - 1;
    invocation[offset] = '\0';
  }

  cef_string_t source = {0};
  cef_string_t source_url = {0};
  proton_engine_bridge_set_string(&source,
                                  invocation != NULL ? invocation : "");
  proton_engine_bridge_set_string(&source_url,
                                  "proton://bridge/bootstrap.js");
  cef_v8_value_t *dispatcher = NULL;
  cef_v8_exception_t *exception = NULL;
  int evaluated = context->eval(context, &source, &source_url, 1, &dispatcher,
                                &exception);
  cef_string_clear(&source);
  cef_string_clear(&source_url);
  free(invocation);
  if (global != NULL) {
    global->delete_value_bykey(global, &native_key);
  }
  cef_string_clear(&native_key);
  if ((!evaluated || exception != NULL) && dispatcher != NULL) {
    dispatcher->base.release((cef_base_ref_counted_t *)dispatcher);
    dispatcher = NULL;
  }
  if (!evaluated || exception != NULL || dispatcher == NULL ||
      !dispatcher->is_object(dispatcher)) {
    char *diagnostic = proton_engine_bridge_diagnostic_json(
        "bootstrap", "bridge_bootstrap_failed",
        dispatcher == NULL ? "bridge bootstrap returned no dispatcher"
                           : "bridge bootstrap returned an invalid dispatcher",
        page_instance, url, NULL, "proton://bridge/bootstrap.js", exception);
    proton_engine_bridge_send_lifecycle(frame, "failed", page_instance, url,
                                        diagnostic);
    free(diagnostic);
  } else {
    proton_engine_bridge_context_t *entry =
        (proton_engine_bridge_context_t *)calloc(1, sizeof(*entry));
    if (entry != NULL) {
      int browser_id = browser->get_identifier(browser);
      proton_engine_bridge_context_t **cursor = &g_contexts;
      while (*cursor != NULL) {
        proton_engine_bridge_context_t *existing = *cursor;
        if (existing->browser_id == browser_id) {
          *cursor = existing->next;
          proton_engine_bridge_send_context_disposed(
              frame, existing->page_instance);
          proton_engine_bridge_release_context_entry(
              existing, "Proton bridge context was replaced");
          break;
        }
        cursor = &existing->next;
      }
      context->base.add_ref((cef_base_ref_counted_t *)context);
      entry->browser_id = browser_id;
      entry->context = context;
      entry->dispatcher = dispatcher;
      entry->page_instance = page_instance;
      entry->next = g_contexts;
      g_contexts = entry;
      dispatcher = NULL;
      page_instance = NULL;
      proton_engine_bridge_log("renderer_bridge_context browser=%d installed=1",
                               entry->browser_id);
      int initialized = proton_engine_bridge_initialize_units(
          browser_config->config_json, context, frame, entry->page_instance,
          url);
      if (initialized) {
        proton_engine_bridge_send_lifecycle(
            frame, "ready", entry->page_instance, url, NULL);
      }
    } else {
      char *diagnostic = proton_engine_bridge_diagnostic_json(
          "prepare", "bridge_context_allocation_failed",
          "failed to allocate bridge context state", page_instance, url, NULL,
          NULL, NULL);
      proton_engine_bridge_send_lifecycle(frame, "failed", page_instance, url,
                                          diagnostic);
      free(diagnostic);
    }
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
  free(page_instance);
  free(url);
  if (dispatcher != NULL) {
    dispatcher->base.release((cef_base_ref_counted_t *)dispatcher);
  }
  if (global != NULL) {
    global->base.release((cef_base_ref_counted_t *)global);
  }
  if (native_invoke != NULL) {
    native_invoke->base.release((cef_base_ref_counted_t *)native_invoke);
  }
  context->exit(context);
}

void proton_engine_bridge_renderer_on_context_released(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  if (browser == NULL || frame == NULL || context == NULL ||
      !frame->is_main(frame)) {
    return;
  }
  proton_engine_bridge_log("bridge_context_released browser=%d",
                           browser->get_identifier(browser));
  proton_engine_bridge_context_t **cursor = &g_contexts;
  char *page_instance = NULL;
  while (*cursor != NULL) {
    proton_engine_bridge_context_t *entry = *cursor;
    if (entry->context == context) {
      *cursor = entry->next;
      if (entry->page_instance != NULL) {
        size_t page_instance_len = strlen(entry->page_instance);
        page_instance = (char *)malloc(page_instance_len + 1);
        if (page_instance != NULL) {
          memcpy(page_instance, entry->page_instance, page_instance_len + 1);
        }
      }
      proton_engine_bridge_release_context_entry(
          entry, "Proton bridge context was released");
      break;
    }
    cursor = &entry->next;
  }

  proton_engine_bridge_send_context_disposed(frame, page_instance);
  free(page_instance);
}

static int proton_engine_bridge_dispatch_response(
    proton_engine_bridge_context_t *entry,
    cef_list_value_t *args) {
  if (entry == NULL || args == NULL || args->get_size(args) < 4 ||
      !entry->context->is_valid(entry->context) ||
      !entry->context->enter(entry->context)) {
    return 1;
  }
  cef_v8_value_t *function = proton_engine_bridge_get_property(
      entry->dispatcher, "dispatchResponse");
  if (function != NULL && function->is_function(function)) {
    int pending_id = args->get_int(args, 0);
    int ok = args->get_bool(args, 1);
    char *payload_json = proton_engine_bridge_userfree_to_utf8(
        args->get_string(args, 2));
    char *error_message = proton_engine_bridge_userfree_to_utf8(
        args->get_string(args, 3));
    cef_string_t payload_string = {0};
    cef_string_t error_string = {0};
    proton_engine_bridge_set_string(
        &payload_string, payload_json != NULL ? payload_json : "null");
    proton_engine_bridge_set_string(
        &error_string, error_message != NULL ? error_message : "");
    cef_v8_value_t *values[] = {
        cef_v8_value_create_int(pending_id),
        cef_v8_value_create_bool(ok),
        cef_v8_value_create_string(&payload_string),
        cef_v8_value_create_string(&error_string),
    };
    cef_string_clear(&payload_string);
    cef_string_clear(&error_string);
    cef_v8_value_t *result = proton_engine_bridge_execute(
        function, entry->context, entry->dispatcher, 4, values);
    int dispatched = result != NULL && result->is_bool(result) &&
                     result->get_bool_value(result);
    proton_engine_bridge_log(
        "renderer_bridge_response browser=%d pending=%d dispatched=%d",
        entry->browser_id, pending_id, dispatched);
    if (result != NULL) {
      result->base.release((cef_base_ref_counted_t *)result);
    }
    free(payload_json);
    free(error_message);
  }
  if (function != NULL) {
    function->base.release((cef_base_ref_counted_t *)function);
  }
  entry->context->exit(entry->context);
  return 1;
}

static int proton_engine_bridge_dispatch_event(
    proton_engine_bridge_context_t *entry,
    cef_list_value_t *args) {
  if (entry == NULL || args == NULL || args->get_size(args) < 1 ||
      !entry->context->is_valid(entry->context) ||
      !entry->context->enter(entry->context)) {
    return 1;
  }
  cef_v8_value_t *function = proton_engine_bridge_get_property(
      entry->dispatcher, "dispatchEvent");
  if (function != NULL && function->is_function(function)) {
    char *event_json = proton_engine_bridge_userfree_to_utf8(
        args->get_string(args, 0));
    cef_string_t event_string = {0};
    proton_engine_bridge_set_string(
        &event_string, event_json != NULL ? event_json : "null");
    cef_v8_value_t *argument = cef_v8_value_create_string(&event_string);
    cef_string_clear(&event_string);
    if (argument != NULL) {
      cef_v8_value_t *arguments[] = {argument};
      cef_v8_value_t *result = proton_engine_bridge_execute(
          function, entry->context, entry->dispatcher, 1, arguments);
      if (result != NULL) {
        result->base.release((cef_base_ref_counted_t *)result);
      }
    }
    free(event_json);
  }
  if (function != NULL) {
    function->base.release((cef_base_ref_counted_t *)function);
  }
  entry->context->exit(entry->context);
  return 1;
}

static int proton_engine_bridge_handle_lifecycle_probe(
    cef_browser_t *browser, cef_frame_t *frame) {
  proton_engine_bridge_browser_config_t *config =
      proton_engine_bridge_find_browser_config(browser);
  if (config == NULL || config->config_json == NULL) {
    return 1;
  }
  char *url = proton_engine_bridge_frame_url(frame);
  if (url == NULL || strcmp(url, "about:blank") == 0) {
    free(url);
    return 1;
  }
  int same_page = config->lifecycle_url != NULL &&
                  strcmp(config->lifecycle_url, url) == 0 &&
                  config->lifecycle_page_instance != NULL;
  if (same_page && config->lifecycle_outcome != NULL &&
      strcmp(config->lifecycle_outcome, "pending") != 0) {
    proton_engine_bridge_send_lifecycle(
        frame, config->lifecycle_outcome, config->lifecycle_page_instance, url,
        config->lifecycle_diagnostic_json);
    free(url);
    return 1;
  }

  char *page_instance =
      same_page ? proton_engine_bridge_strdup(config->lifecycle_page_instance)
                : proton_engine_bridge_new_page_instance();
  if (page_instance == NULL) {
    free(url);
    return 1;
  }
  proton_engine_bridge_send_lifecycle(frame, "pending", page_instance, url,
                                      NULL);
  if (!proton_engine_bridge_config_allows_page(config->config_json, url)) {
    proton_engine_bridge_send_lifecycle(frame, "ineligible", page_instance,
                                        url, NULL);
  } else {
    char *diagnostic = proton_engine_bridge_diagnostic_json(
        "prepare", "bridge_lifecycle_missing",
        "main frame finished loading without a terminal bridge lifecycle outcome",
        page_instance, url, NULL, NULL, NULL);
    proton_engine_bridge_send_lifecycle(frame, "failed", page_instance, url,
                                        diagnostic);
    free(diagnostic);
  }
  free(page_instance);
  free(url);
  return 1;
}

int proton_engine_bridge_renderer_on_process_message_received(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  if (source_process != PID_BROWSER || browser == NULL || frame == NULL ||
      message == NULL || !frame->is_main(frame)) {
    return 0;
  }
  char *message_name = proton_engine_bridge_userfree_to_utf8(
      message->get_name(message));
  if (message_name == NULL) {
    return 0;
  }
  int is_response = strcmp(message_name,
                           PROTON_ENGINE_BRIDGE_RESPONSE_MESSAGE) == 0;
  int is_event = strcmp(message_name, PROTON_ENGINE_BRIDGE_EVENT_MESSAGE) == 0;
  int is_lifecycle_probe =
      strcmp(message_name, PROTON_ENGINE_BRIDGE_LIFECYCLE_PROBE_MESSAGE) == 0;
  proton_engine_bridge_log(
      "renderer_bridge_message browser=%d response=%d event=%d probe=%d",
      browser->get_identifier(browser), is_response, is_event,
      is_lifecycle_probe);
  free(message_name);
  if (is_lifecycle_probe) {
    return proton_engine_bridge_handle_lifecycle_probe(browser, frame);
  }
  if (!is_response && !is_event) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    return 1;
  }
  proton_engine_bridge_context_t *entry =
      proton_engine_bridge_find_context(browser);
  proton_engine_bridge_log("renderer_bridge_match browser=%d context=%d",
                           browser->get_identifier(browser), entry != NULL);
  int handled = is_response
                    ? proton_engine_bridge_dispatch_response(entry, args)
                    : proton_engine_bridge_dispatch_event(entry, args);
  args->base.release((cef_base_ref_counted_t *)args);
  return handled;
}
