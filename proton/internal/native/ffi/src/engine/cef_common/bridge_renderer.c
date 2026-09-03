#include "bridge_renderer.h"

#include "bridge_lifecycle.h"
#include "bridge_policy.h"

#include <stddef.h>
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
  cef_dictionary_value_t *config;
  char *lifecycle_outcome;
  char *lifecycle_page_instance;
  char *lifecycle_url;
  proton_engine_bridge_diagnostic_t lifecycle_diagnostic;
  int has_lifecycle_diagnostic;
  struct proton_engine_bridge_browser_config *next;
} proton_engine_bridge_browser_config_t;

typedef struct proton_engine_bridge_context {
  int browser_id;
  cef_v8_context_t *context;
  cef_v8_value_t *dispatcher;
  char *page_instance;
  struct proton_engine_bridge_context *next;
} proton_engine_bridge_context_t;

typedef struct proton_engine_window_controls_overlay_browser {
  int browser_id;
  size_t instance_count;
  proton_engine_window_controls_overlay_geometry_t geometry;
  struct proton_engine_window_controls_overlay_browser *next;
} proton_engine_window_controls_overlay_browser_t;

typedef struct proton_engine_window_controls_overlay_context {
  int browser_id;
  cef_v8_context_t *context;
  cef_v8_value_t *dispatcher;
  struct proton_engine_window_controls_overlay_context *next;
} proton_engine_window_controls_overlay_context_t;

static proton_engine_bridge_browser_config_t *g_browser_configs = NULL;
static proton_engine_bridge_context_t *g_contexts = NULL;
static proton_engine_window_controls_overlay_browser_t *g_overlay_browsers =
    NULL;
static proton_engine_window_controls_overlay_context_t *g_overlay_contexts =
    NULL;
static uint64_t g_next_page_instance = 1;

static char *proton_engine_bridge_dictionary_string(
    cef_dictionary_value_t *dictionary, const char *key);

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

static int proton_engine_bridge_is_default_context(
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  if (frame == NULL || context == NULL || !frame->is_main(frame)) {
    return 0;
  }
  cef_v8_context_t *default_context = frame->get_v8_context(frame);
  int is_default = 0;
  if (default_context != NULL && context->is_same != NULL) {
    /* CEF's C API consumes refptr parameters. Keep the getter reference while
       transferring a temporary reference to is_same. */
    default_context->base.add_ref(
        (cef_base_ref_counted_t *)default_context);
    is_default = context->is_same(context, default_context);
  }
  if (default_context != NULL) {
    default_context->base.release(
        (cef_base_ref_counted_t *)default_context);
  }
  return is_default;
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

static char *proton_engine_bridge_exception_string(
    cef_v8_exception_t *exception,
    cef_string_userfree_t(CEF_CALLBACK *getter)(cef_v8_exception_t *)) {
  return exception != NULL && getter != NULL
             ? proton_engine_bridge_userfree_to_utf8(getter(exception))
             : NULL;
}

static int proton_engine_bridge_diagnostic_from_exception(
    proton_engine_bridge_diagnostic_t *diagnostic, const char *stage,
    const char *code, const char *message, const char *owner,
    const char *source_url, cef_v8_exception_t *exception) {
  char *exception_message = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_message : NULL);
  char *source_line = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_source_line : NULL);
  char *resource = proton_engine_bridge_exception_string(
      exception, exception != NULL ? exception->get_script_resource_name
                                   : NULL);
  proton_engine_bridge_diagnostic_input_t input = {
      .stage = stage,
      .code = code,
      .message = exception_message != NULL ? exception_message : message,
      .owner = owner,
      .source_url = resource != NULL && resource[0] != '\0' ? resource
                                                               : source_url,
      .source_line = source_line,
      .line = exception != NULL ? exception->get_line_number(exception) : 0,
      .column = exception != NULL ? exception->get_start_column(exception) : 0,
      .has_line = exception != NULL,
      .has_column = exception != NULL,
  };
  int recorded = proton_engine_bridge_diagnostic_set(diagnostic, &input);
  free(exception_message);
  free(source_line);
  free(resource);
  return recorded;
}

static void proton_engine_bridge_record_lifecycle(
    cef_frame_t *frame, const char *outcome, const char *page_instance,
    const char *url, const proton_engine_bridge_diagnostic_t *diagnostic) {
  cef_browser_t *browser = frame->get_browser(frame);
  proton_engine_bridge_browser_config_t *config =
      proton_engine_bridge_find_browser_config(browser);
  if (config != NULL) {
    char *next_outcome = proton_engine_bridge_strdup(outcome);
    char *next_page_instance = proton_engine_bridge_strdup(page_instance);
    char *next_url = proton_engine_bridge_strdup(url);
    proton_engine_bridge_diagnostic_t next_diagnostic;
    proton_engine_bridge_diagnostic_init(&next_diagnostic);
    int copied_diagnostic =
        diagnostic == NULL ||
        proton_engine_bridge_diagnostic_copy(&next_diagnostic, diagnostic);
    if (next_outcome != NULL && next_page_instance != NULL &&
        next_url != NULL && copied_diagnostic) {
      free(config->lifecycle_outcome);
      free(config->lifecycle_page_instance);
      free(config->lifecycle_url);
      proton_engine_bridge_diagnostic_dispose(&config->lifecycle_diagnostic);
      config->lifecycle_outcome = next_outcome;
      config->lifecycle_page_instance = next_page_instance;
      config->lifecycle_url = next_url;
      config->lifecycle_diagnostic = next_diagnostic;
      config->has_lifecycle_diagnostic = diagnostic != NULL;
    } else {
      free(next_outcome);
      free(next_page_instance);
      free(next_url);
      proton_engine_bridge_diagnostic_dispose(&next_diagnostic);
    }
  }
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static void proton_engine_bridge_send_lifecycle(
    cef_frame_t *frame, const char *outcome, const char *page_instance,
    const char *url, const proton_engine_bridge_diagnostic_t *diagnostic) {
  if (frame == NULL || outcome == NULL || page_instance == NULL || url == NULL) {
    return;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(&message_name,
                                  PROTON_ENGINE_BRIDGE_LIFECYCLE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    proton_engine_bridge_record_lifecycle(frame, outcome, page_instance, url,
                                          diagnostic);
    return;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  int populated = args != NULL && args->set_size(args, 14);
  const char *values[] = {
      outcome,
      page_instance,
      url,
      diagnostic != NULL ? diagnostic->stage : "",
      diagnostic != NULL ? diagnostic->code : "",
      diagnostic != NULL ? diagnostic->message : "",
      diagnostic != NULL ? diagnostic->owner : "",
      diagnostic != NULL ? diagnostic->source_url : "",
      diagnostic != NULL ? diagnostic->source_line : "",
      diagnostic != NULL ? diagnostic->stack : "",
  };
  for (size_t index = 0; populated && index < 3; index++) {
    cef_string_t value = {0};
    proton_engine_bridge_set_string(&value, values[index]);
    populated = args->set_string(args, index, &value);
    cef_string_clear(&value);
  }
  populated = populated && args->set_bool(args, 3, diagnostic != NULL);
  for (size_t index = 3; populated && index < 10; index++) {
    cef_string_t value = {0};
    proton_engine_bridge_set_string(&value, values[index]);
    populated = args->set_string(args, index + 1, &value);
    cef_string_clear(&value);
  }
  populated = populated && args->set_int(args, 11, diagnostic != NULL && diagnostic->has_line
                                                       ? diagnostic->line
                                                       : 0);
  populated = populated && args->set_int(args, 12, diagnostic != NULL && diagnostic->has_column
                                                       ? diagnostic->column
                                                       : 0);
  populated = populated && args->set_bool(
                             args, 13,
                             diagnostic != NULL && diagnostic->details_truncated);
  if (args != NULL) {
    args->base.release((cef_base_ref_counted_t *)args);
  }
  if (populated) {
    frame->send_process_message(frame, PID_BROWSER, message);
  } else {
    message->base.release((cef_base_ref_counted_t *)message);
  }
  proton_engine_bridge_record_lifecycle(frame, outcome, page_instance, url,
                                        diagnostic);
}

static void proton_engine_bridge_send_failure(
    cef_frame_t *frame, const char *page_instance, const char *url,
    const char *stage, const char *code, const char *message,
    const char *owner, const char *source_url, cef_v8_exception_t *exception) {
  proton_engine_bridge_diagnostic_t diagnostic;
  proton_engine_bridge_diagnostic_init(&diagnostic);
  int recorded = proton_engine_bridge_diagnostic_from_exception(
      &diagnostic, stage, code, message, owner, source_url, exception);
  proton_engine_bridge_send_lifecycle(
      frame, "failed", page_instance, url, recorded ? &diagnostic : NULL);
  proton_engine_bridge_diagnostic_dispose(&diagnostic);
}

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

static int proton_engine_bridge_initialize_unit(
    cef_dictionary_value_t *unit, cef_v8_context_t *context,
    cef_frame_t *frame, const char *page_instance, const char *url,
    size_t index) {
  char *owner = proton_engine_bridge_dictionary_string(unit, "owner");
  char *name = proton_engine_bridge_dictionary_string(unit, "name");
  char *source = proton_engine_bridge_dictionary_string(unit, "source");
  if (owner == NULL || name == NULL || source == NULL) {
    free(owner);
    free(name);
    free(source);
    return 0;
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
           index, owner_component, name_component);
  cef_string_t code = {0};
  cef_string_t script_url = {0};
  proton_engine_bridge_set_string(&code, source);
  proton_engine_bridge_set_string(&script_url, source_url);
  cef_v8_value_t *result = NULL;
  cef_v8_exception_t *exception = NULL;
  int evaluated = context->eval(context, &code, &script_url, 1, &result,
                                &exception);
  cef_string_clear(&code);
  cef_string_clear(&script_url);
  if (result != NULL) {
    result->base.release((cef_base_ref_counted_t *)result);
  }
  if (!evaluated || exception != NULL) {
    proton_engine_bridge_send_failure(
        frame, page_instance, url, "initialization",
        "bridge_initialization_failed", "bridge initialization failed", owner,
        source_url, exception);
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
  free(owner);
  free(name);
  free(source);
  return evaluated && exception == NULL;
}

static int proton_engine_bridge_initialize_units(
    cef_dictionary_value_t *grant, cef_v8_context_t *context,
    cef_frame_t *frame,
    const char *page_instance, const char *url) {
  if (grant == NULL) {
    return 0;
  }
  cef_string_t units_key = {0};
  proton_engine_bridge_set_string(&units_key, "initialization_units");
  cef_list_value_t *units = grant->get_list(grant, &units_key);
  cef_string_clear(&units_key);
  if (units == NULL) {
    return 0;
  }
  int initialized = 1;
  size_t count = units->get_size(units);
  for (size_t index = 0; index < count; index++) {
    cef_dictionary_value_t *unit = units->get_dictionary(units, index);
    if (!proton_engine_bridge_initialize_unit(unit, context, frame,
                                              page_instance, url, index)) {
      initialized = 0;
    }
    if (unit != NULL) {
      unit->base.release((cef_base_ref_counted_t *)unit);
    }
    if (!initialized) {
      break;
    }
  }
  units->base.release((cef_base_ref_counted_t *)units);
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

static int proton_engine_bridge_dictionary_set_string(
    cef_dictionary_value_t *dictionary, const char *key, const char *value) {
  if (dictionary == NULL || key == NULL || value == NULL) {
    return 0;
  }
  cef_string_t key_string = {0};
  cef_string_t value_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  proton_engine_bridge_set_string(&value_string, value);
  int set = dictionary->set_string(dictionary, &key_string, &value_string);
  cef_string_clear(&key_string);
  cef_string_clear(&value_string);
  return set;
}

static int proton_engine_bridge_dictionary_set_int(
    cef_dictionary_value_t *dictionary, const char *key, int value) {
  if (dictionary == NULL || key == NULL) {
    return 0;
  }
  cef_string_t key_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  int set = dictionary->set_int(dictionary, &key_string, value);
  cef_string_clear(&key_string);
  return set;
}

static int proton_engine_bridge_dictionary_set_dictionary(
    cef_dictionary_value_t *dictionary, const char *key,
    cef_dictionary_value_t *value) {
  if (dictionary == NULL || key == NULL || value == NULL) {
    return 0;
  }
  cef_string_t key_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  int set = dictionary->set_dictionary(dictionary, &key_string, value);
  cef_string_clear(&key_string);
  return set;
}

static int proton_engine_bridge_dictionary_set_list(cef_dictionary_value_t *dictionary,
                                                     const char *key,
                                                     cef_list_value_t *value) {
  if (dictionary == NULL || key == NULL || value == NULL) {
    return 0;
  }
  cef_string_t key_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  int set = dictionary->set_list(dictionary, &key_string, value);
  cef_string_clear(&key_string);
  return set;
}

static cef_list_value_t *proton_engine_bridge_config_ops(
    const proton_bridge_config_t *config, size_t grant_index) {
  size_t count = proton_bridge_config_grant_op_count(config, grant_index);
  cef_list_value_t *ops = cef_list_value_create();
  if (ops == NULL || !ops->set_size(ops, count)) {
    if (ops != NULL) {
      ops->base.release((cef_base_ref_counted_t *)ops);
    }
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    const char *name = proton_bridge_config_grant_op(config, grant_index, index);
    cef_dictionary_value_t *op = cef_dictionary_value_create();
    if (op == NULL || name == NULL ||
        !proton_engine_bridge_dictionary_set_string(op, "name", name) ||
        !ops->set_dictionary(ops, index, op)) {
      if (op != NULL) {
        op->base.release((cef_base_ref_counted_t *)op);
      }
      ops->base.release((cef_base_ref_counted_t *)ops);
      return NULL;
    }
  }
  return ops;
}

static cef_list_value_t *proton_engine_bridge_config_extensions(
    const proton_bridge_config_t *config, size_t grant_index) {
  size_t count = proton_bridge_config_grant_extension_count(config, grant_index);
  cef_list_value_t *extensions = cef_list_value_create();
  if (extensions == NULL || !extensions->set_size(extensions, count)) {
    if (extensions != NULL) {
      extensions->base.release((cef_base_ref_counted_t *)extensions);
    }
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    const char *name = proton_bridge_config_grant_extension_namespace(
        config, grant_index, index);
    size_t api_count = proton_bridge_config_grant_extension_api_count(
        config, grant_index, index);
    cef_dictionary_value_t *extension = cef_dictionary_value_create();
    cef_list_value_t *apis = cef_list_value_create();
    if (extension == NULL || apis == NULL || name == NULL ||
        !apis->set_size(apis, api_count) ||
        !proton_engine_bridge_dictionary_set_string(extension, "namespace",
                                                     name)) {
      if (extension != NULL) {
        extension->base.release((cef_base_ref_counted_t *)extension);
      }
      if (apis != NULL) {
        apis->base.release((cef_base_ref_counted_t *)apis);
      }
      extensions->base.release((cef_base_ref_counted_t *)extensions);
      return NULL;
    }
    for (size_t api_index = 0; api_index < api_count; api_index++) {
      const char *api = proton_bridge_config_grant_extension_api(
          config, grant_index, index, api_index);
      cef_string_t api_string = {0};
      proton_engine_bridge_set_string(&api_string, api);
      int set = api != NULL && apis->set_string(apis, api_index, &api_string);
      cef_string_clear(&api_string);
      if (!set) {
        extension->base.release((cef_base_ref_counted_t *)extension);
        apis->base.release((cef_base_ref_counted_t *)apis);
        extensions->base.release((cef_base_ref_counted_t *)extensions);
        return NULL;
      }
    }
    if (!proton_engine_bridge_dictionary_set_list(extension, "apis", apis)) {
      extension->base.release((cef_base_ref_counted_t *)extension);
      apis->base.release((cef_base_ref_counted_t *)apis);
      extensions->base.release((cef_base_ref_counted_t *)extensions);
      return NULL;
    }
    apis = NULL;
    if (!extensions->set_dictionary(extensions, index, extension)) {
      extension->base.release((cef_base_ref_counted_t *)extension);
      extensions->base.release((cef_base_ref_counted_t *)extensions);
      return NULL;
    }
  }
  return extensions;
}

static cef_list_value_t *proton_engine_bridge_config_initialization_units(
    const proton_bridge_config_t *config, size_t grant_index) {
  size_t count = proton_bridge_config_grant_initialization_unit_count(
      config, grant_index);
  cef_list_value_t *units = cef_list_value_create();
  if (units == NULL || !units->set_size(units, count)) {
    if (units != NULL) {
      units->base.release((cef_base_ref_counted_t *)units);
    }
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    const char *owner = proton_bridge_config_grant_initialization_owner(
        config, grant_index, index);
    const char *name = proton_bridge_config_grant_initialization_name(
        config, grant_index, index);
    const char *source = proton_bridge_config_grant_initialization_source(
        config, grant_index, index);
    cef_dictionary_value_t *unit = cef_dictionary_value_create();
    if (unit == NULL || owner == NULL || name == NULL || source == NULL ||
        !proton_engine_bridge_dictionary_set_string(unit, "owner", owner) ||
        !proton_engine_bridge_dictionary_set_string(unit, "name", name) ||
        !proton_engine_bridge_dictionary_set_string(unit, "source", source) ||
        !units->set_dictionary(units, index, unit)) {
      if (unit != NULL) {
        unit->base.release((cef_base_ref_counted_t *)unit);
      }
      units->base.release((cef_base_ref_counted_t *)units);
      return NULL;
    }
  }
  return units;
}

static cef_dictionary_value_t *proton_engine_bridge_extra_info(
    const proton_bridge_config_t *config) {
  if (config == NULL) {
    return NULL;
  }
  size_t grant_count = proton_bridge_config_grant_count(config);
  cef_dictionary_value_t *root = cef_dictionary_value_create();
  cef_dictionary_value_t *bridge = cef_dictionary_value_create();
  cef_list_value_t *grants = cef_list_value_create();
  if (root == NULL || bridge == NULL || grants == NULL ||
      !grants->set_size(grants, grant_count)) {
    if (root != NULL) {
      root->base.release((cef_base_ref_counted_t *)root);
    }
    if (bridge != NULL) {
      bridge->base.release((cef_base_ref_counted_t *)bridge);
    }
    if (grants != NULL) {
      grants->base.release((cef_base_ref_counted_t *)grants);
    }
    return NULL;
  }
  for (size_t index = 0; index < grant_count; index++) {
    const char *source_origin =
        proton_bridge_config_grant_source_origin(config, index);
    cef_dictionary_value_t *grant = cef_dictionary_value_create();
    cef_list_value_t *ops = proton_engine_bridge_config_ops(config, index);
    cef_list_value_t *extensions =
        proton_engine_bridge_config_extensions(config, index);
    cef_list_value_t *units =
        proton_engine_bridge_config_initialization_units(config, index);
    if (grant == NULL || source_origin == NULL || ops == NULL ||
        extensions == NULL || units == NULL ||
        !proton_engine_bridge_dictionary_set_string(grant, "source_origin",
                                                     source_origin)) {
      if (grant != NULL) {
        grant->base.release((cef_base_ref_counted_t *)grant);
      }
      if (ops != NULL) {
        ops->base.release((cef_base_ref_counted_t *)ops);
      }
      if (extensions != NULL) {
        extensions->base.release((cef_base_ref_counted_t *)extensions);
      }
      if (units != NULL) {
        units->base.release((cef_base_ref_counted_t *)units);
      }
      root->base.release((cef_base_ref_counted_t *)root);
      bridge->base.release((cef_base_ref_counted_t *)bridge);
      grants->base.release((cef_base_ref_counted_t *)grants);
      return NULL;
    }
    if (!proton_engine_bridge_dictionary_set_list(grant, "ops", ops)) {
      grant->base.release((cef_base_ref_counted_t *)grant);
      ops->base.release((cef_base_ref_counted_t *)ops);
      extensions->base.release((cef_base_ref_counted_t *)extensions);
      units->base.release((cef_base_ref_counted_t *)units);
      root->base.release((cef_base_ref_counted_t *)root);
      bridge->base.release((cef_base_ref_counted_t *)bridge);
      grants->base.release((cef_base_ref_counted_t *)grants);
      return NULL;
    }
    ops = NULL;
    if (!proton_engine_bridge_dictionary_set_list(grant, "extensions",
                                                   extensions)) {
      grant->base.release((cef_base_ref_counted_t *)grant);
      extensions->base.release((cef_base_ref_counted_t *)extensions);
      units->base.release((cef_base_ref_counted_t *)units);
      root->base.release((cef_base_ref_counted_t *)root);
      bridge->base.release((cef_base_ref_counted_t *)bridge);
      grants->base.release((cef_base_ref_counted_t *)grants);
      return NULL;
    }
    extensions = NULL;
    if (!proton_engine_bridge_dictionary_set_list(grant, "initialization_units",
                                                   units)) {
      grant->base.release((cef_base_ref_counted_t *)grant);
      units->base.release((cef_base_ref_counted_t *)units);
      root->base.release((cef_base_ref_counted_t *)root);
      bridge->base.release((cef_base_ref_counted_t *)bridge);
      grants->base.release((cef_base_ref_counted_t *)grants);
      return NULL;
    }
    units = NULL;
    if (!grants->set_dictionary(grants, index, grant)) {
      grant->base.release((cef_base_ref_counted_t *)grant);
      root->base.release((cef_base_ref_counted_t *)root);
      bridge->base.release((cef_base_ref_counted_t *)bridge);
      grants->base.release((cef_base_ref_counted_t *)grants);
      return NULL;
    }
  }
  if (!proton_engine_bridge_dictionary_set_list(bridge, "grants", grants)) {
    root->base.release((cef_base_ref_counted_t *)root);
    bridge->base.release((cef_base_ref_counted_t *)bridge);
    grants->base.release((cef_base_ref_counted_t *)grants);
    return NULL;
  }
  grants = NULL;
  if (!proton_engine_bridge_dictionary_set_dictionary(root, "bridge", bridge)) {
    root->base.release((cef_base_ref_counted_t *)root);
    bridge->base.release((cef_base_ref_counted_t *)bridge);
    return NULL;
  }
  return root;
}

cef_dictionary_value_t *proton_engine_bridge_renderer_extra_info(
    const proton_bridge_config_t *config,
    const proton_engine_window_controls_overlay_geometry_t *geometry) {
  cef_dictionary_value_t *root = proton_engine_bridge_extra_info(config);
  if (geometry == NULL) {
    return root;
  }
  if (root == NULL) {
    root = cef_dictionary_value_create();
  }
  cef_dictionary_value_t *overlay = cef_dictionary_value_create();
  if (root == NULL || overlay == NULL ||
      !proton_engine_bridge_dictionary_set_int(overlay, "visible",
                                               geometry->visible) ||
      !proton_engine_bridge_dictionary_set_int(overlay, "x", geometry->x) ||
      !proton_engine_bridge_dictionary_set_int(overlay, "y", geometry->y) ||
      !proton_engine_bridge_dictionary_set_int(overlay, "width",
                                               geometry->width) ||
      !proton_engine_bridge_dictionary_set_int(overlay, "height",
                                               geometry->height) ||
      !proton_engine_bridge_dictionary_set_int(overlay, "zoom_percent",
                                               geometry->zoom_percent) ||
      !proton_engine_bridge_dictionary_set_dictionary(
          root, "window_controls_overlay", overlay)) {
    if (root != NULL) {
      root->base.release((cef_base_ref_counted_t *)root);
    }
    if (overlay != NULL) {
      overlay->base.release((cef_base_ref_counted_t *)overlay);
    }
    return NULL;
  }
  return root;
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

int proton_engine_window_controls_overlay_send(
    cef_browser_t *browser,
    const proton_engine_window_controls_overlay_geometry_t *geometry) {
  if (browser == NULL || geometry == NULL) {
    return 0;
  }
  cef_frame_t *frame = browser->get_main_frame(browser);
  if (frame == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_bridge_set_string(
      &message_name, PROTON_ENGINE_WINDOW_CONTROLS_OVERLAY_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  int sent = 0;
  if (args != NULL) {
    int populated = args->set_size(args, 6) &&
                    args->set_bool(args, 0, geometry->visible) &&
                    args->set_int(args, 1, geometry->x) &&
                    args->set_int(args, 2, geometry->y) &&
                    args->set_int(args, 3, geometry->width) &&
                    args->set_int(args, 4, geometry->height) &&
                    args->set_int(args, 5, geometry->zoom_percent);
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
    cef_dictionary_value_t *config) {
  if (browser == NULL || config == NULL) {
    if (config != NULL) {
      config->base.release((cef_base_ref_counted_t *)config);
    }
    return 0;
  }
  proton_engine_bridge_browser_config_t *existing =
      proton_engine_bridge_find_browser_config(browser);
  if (existing != NULL) {
    /* During cross-origin navigation CEF may create a replacement browser with
       the same identifier before destroying the old renderer incarnation. */
    existing->config->base.release((cef_base_ref_counted_t *)existing->config);
    existing->config = config;
    existing->instance_count++;
    return 1;
  }
  proton_engine_bridge_browser_config_t *entry =
      (proton_engine_bridge_browser_config_t *)calloc(1, sizeof(*entry));
  if (entry == NULL) {
    config->base.release((cef_base_ref_counted_t *)config);
    return 0;
  }
  entry->browser_id = browser->get_identifier(browser);
  entry->instance_count = 1;
  entry->config = config;
  entry->next = g_browser_configs;
  g_browser_configs = entry;
  return 1;
}

static proton_engine_window_controls_overlay_browser_t *
proton_engine_window_controls_overlay_find_browser(cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_controls_overlay_browser_t *entry =
           g_overlay_browsers;
       entry != NULL; entry = entry->next) {
    if (entry->browser_id == browser_id) {
      return entry;
    }
  }
  return NULL;
}

static proton_engine_window_controls_overlay_context_t *
proton_engine_window_controls_overlay_find_context(cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_controls_overlay_context_t *entry =
           g_overlay_contexts;
       entry != NULL; entry = entry->next) {
    if (entry->browser_id == browser_id) {
      return entry;
    }
  }
  return NULL;
}

static int proton_engine_window_controls_overlay_store_browser(
    cef_browser_t *browser,
    const proton_engine_window_controls_overlay_geometry_t *geometry) {
  if (browser == NULL || geometry == NULL) {
    return 0;
  }
  proton_engine_window_controls_overlay_browser_t *existing =
      proton_engine_window_controls_overlay_find_browser(browser);
  if (existing != NULL) {
    existing->geometry = *geometry;
    existing->instance_count++;
    return 1;
  }
  proton_engine_window_controls_overlay_browser_t *entry =
      (proton_engine_window_controls_overlay_browser_t *)calloc(
          1, sizeof(*entry));
  if (entry == NULL) {
    return 0;
  }
  entry->browser_id = browser->get_identifier(browser);
  entry->instance_count = 1;
  entry->geometry = *geometry;
  entry->next = g_overlay_browsers;
  g_overlay_browsers = entry;
  return 1;
}

static void proton_engine_window_controls_overlay_release_context(
    proton_engine_window_controls_overlay_context_t *entry) {
  if (entry == NULL) {
    return;
  }
  if (entry->context != NULL && entry->dispatcher != NULL &&
      entry->context->is_valid(entry->context) &&
      entry->context->enter(entry->context)) {
    cef_v8_value_t *dispose = proton_engine_bridge_get_property(
        entry->dispatcher, "dispose");
    if (dispose != NULL && dispose->is_function(dispose)) {
      cef_v8_value_t *result = proton_engine_bridge_execute(
          dispose, entry->context, entry->dispatcher, 0, NULL);
      if (result != NULL) {
        result->base.release((cef_base_ref_counted_t *)result);
      }
    }
    if (dispose != NULL) {
      dispose->base.release((cef_base_ref_counted_t *)dispose);
    }
    entry->context->exit(entry->context);
  }
  if (entry->dispatcher != NULL) {
    entry->dispatcher->base.release(
        (cef_base_ref_counted_t *)entry->dispatcher);
  }
  if (entry->context != NULL) {
    entry->context->base.release((cef_base_ref_counted_t *)entry->context);
  }
  free(entry);
}

static int proton_engine_window_controls_overlay_install(
    cef_browser_t *browser, cef_v8_context_t *context,
    const proton_engine_window_controls_overlay_geometry_t *geometry) {
  if (browser == NULL || context == NULL || geometry == NULL ||
      !context->enter(context)) {
    return 0;
  }
  cef_string_t source = {0};
  cef_string_t source_url = {0};
  proton_engine_bridge_set_string(
      &source, (const char *)proton_engine_window_controls_overlay_source);
  proton_engine_bridge_set_string(
      &source_url, "proton://window-controls-overlay/bootstrap.js");
  cef_v8_value_t *installer = NULL;
  cef_v8_exception_t *exception = NULL;
  int evaluated = context->eval(context, &source, &source_url, 1, &installer,
                                &exception);
  cef_string_clear(&source);
  cef_string_clear(&source_url);
  cef_v8_value_t *global = context->get_global(context);
  cef_v8_value_t *arguments[] = {
      cef_v8_value_create_bool(geometry->visible),
      cef_v8_value_create_int(geometry->x),
      cef_v8_value_create_int(geometry->y),
      cef_v8_value_create_int(geometry->width),
      cef_v8_value_create_int(geometry->height),
      cef_v8_value_create_int(geometry->zoom_percent),
  };
  cef_v8_value_t *dispatcher = NULL;
  if (evaluated && exception == NULL && installer != NULL &&
      installer->is_function(installer) && global != NULL) {
    dispatcher = proton_engine_bridge_execute(installer, context, global, 6,
                                               arguments);
    memset(arguments, 0, sizeof(arguments));
  }
  for (size_t index = 0; index < 6; index++) {
    if (arguments[index] != NULL) {
      arguments[index]->base.release(
          (cef_base_ref_counted_t *)arguments[index]);
    }
  }
  if (installer != NULL) {
    installer->base.release((cef_base_ref_counted_t *)installer);
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
  if (global != NULL) {
    global->base.release((cef_base_ref_counted_t *)global);
  }
  int installed = dispatcher != NULL && dispatcher->is_object(dispatcher);
  if (installed) {
    proton_engine_window_controls_overlay_context_t *entry =
        (proton_engine_window_controls_overlay_context_t *)calloc(
            1, sizeof(*entry));
    installed = entry != NULL;
    if (entry != NULL) {
      int browser_id = browser->get_identifier(browser);
      proton_engine_window_controls_overlay_context_t **cursor =
          &g_overlay_contexts;
      while (*cursor != NULL) {
        proton_engine_window_controls_overlay_context_t *existing = *cursor;
        if (existing->browser_id == browser_id) {
          *cursor = existing->next;
          proton_engine_window_controls_overlay_release_context(existing);
          break;
        }
        cursor = &existing->next;
      }
      context->base.add_ref((cef_base_ref_counted_t *)context);
      entry->browser_id = browser_id;
      entry->context = context;
      entry->dispatcher = dispatcher;
      entry->next = g_overlay_contexts;
      g_overlay_contexts = entry;
      dispatcher = NULL;
    }
  }
  if (dispatcher != NULL) {
    dispatcher->base.release((cef_base_ref_counted_t *)dispatcher);
  }
  context->exit(context);
  return installed;
}

static char *proton_engine_bridge_dictionary_string(
    cef_dictionary_value_t *dictionary, const char *key) {
  if (dictionary == NULL || key == NULL) {
    return NULL;
  }
  cef_string_t key_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  cef_string_userfree_t value = dictionary->get_string(dictionary, &key_string);
  cef_string_clear(&key_string);
  return proton_engine_bridge_userfree_to_utf8(value);
}

static cef_dictionary_value_t *proton_engine_bridge_renderer_find_grant(
    cef_dictionary_value_t *config, const char *url) {
  char *source_origin = proton_engine_bridge_source_origin(url);
  if (config == NULL || source_origin == NULL) {
    free(source_origin);
    return NULL;
  }
  cef_string_t grants_key = {0};
  proton_engine_bridge_set_string(&grants_key, "grants");
  cef_list_value_t *grants = config->get_list(config, &grants_key);
  cef_string_clear(&grants_key);
  if (grants == NULL) {
    free(source_origin);
    return NULL;
  }
  cef_dictionary_value_t *match = NULL;
  size_t count = grants->get_size(grants);
  for (size_t index = 0; index < count; index++) {
    cef_dictionary_value_t *grant = grants->get_dictionary(grants, index);
    char *candidate = proton_engine_bridge_dictionary_string(
        grant, "source_origin");
    if (candidate != NULL && strcmp(candidate, source_origin) == 0) {
      match = grant;
      grant = NULL;
    }
    free(candidate);
    if (grant != NULL) {
      grant->base.release((cef_base_ref_counted_t *)grant);
    }
    if (match != NULL) {
      break;
    }
  }
  grants->base.release((cef_base_ref_counted_t *)grants);
  free(source_origin);
  return match;
}

static int proton_engine_bridge_renderer_config_allows_page(
    cef_dictionary_value_t *config, const char *url) {
  cef_dictionary_value_t *grant =
      proton_engine_bridge_renderer_find_grant(config, url);
  int allowed = grant != NULL;
  if (grant != NULL) {
    grant->base.release((cef_base_ref_counted_t *)grant);
  }
  return allowed;
}

static cef_v8_value_t *proton_engine_bridge_v8_string(const char *value) {
  cef_string_t string = {0};
  proton_engine_bridge_set_string(&string, value);
  cef_v8_value_t *result = cef_v8_value_create_string(&string);
  cef_string_clear(&string);
  return result;
}

static int proton_engine_bridge_v8_set_key(cef_v8_value_t *object,
                                           const char *key,
                                           cef_v8_value_t *value) {
  if (object == NULL || key == NULL || value == NULL) {
    return 0;
  }
  cef_string_t key_string = {0};
  proton_engine_bridge_set_string(&key_string, key);
  int set = object->set_value_bykey(object, &key_string, value,
                                    V8_PROPERTY_ATTRIBUTE_NONE);
  cef_string_clear(&key_string);
  if (!set) {
    value->base.release((cef_base_ref_counted_t *)value);
  }
  return set;
}

static int proton_engine_bridge_v8_set_index(cef_v8_value_t *array, int index,
                                             cef_v8_value_t *value) {
  if (array == NULL || value == NULL) {
    return 0;
  }
  int set = array->set_value_byindex(array, index, value);
  if (!set) {
    value->base.release((cef_base_ref_counted_t *)value);
  }
  return set;
}

static cef_v8_value_t *proton_engine_bridge_v8_string_list(
    cef_list_value_t *values) {
  if (values == NULL || values->get_size(values) > INT32_MAX) {
    return NULL;
  }
  size_t count = values->get_size(values);
  cef_v8_value_t *array = cef_v8_value_create_array((int)count);
  if (array == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    char *item = proton_engine_bridge_userfree_to_utf8(
        values->get_string(values, index));
    cef_v8_value_t *value = proton_engine_bridge_v8_string(item);
    free(item);
    if (value == NULL ||
        !proton_engine_bridge_v8_set_index(array, (int)index, value)) {
      array->base.release((cef_base_ref_counted_t *)array);
      return NULL;
    }
  }
  return array;
}

static cef_v8_value_t *proton_engine_bridge_v8_unit(
    cef_dictionary_value_t *unit) {
  static const char *const keys[] = {"owner", "name", "source"};
  cef_v8_value_t *result = cef_v8_value_create_object(NULL, NULL);
  if (result == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); index++) {
    char *text = proton_engine_bridge_dictionary_string(unit, keys[index]);
    cef_v8_value_t *value = proton_engine_bridge_v8_string(text);
    free(text);
    if (value == NULL ||
        !proton_engine_bridge_v8_set_key(result, keys[index], value)) {
      result->base.release((cef_base_ref_counted_t *)result);
      return NULL;
    }
  }
  return result;
}

static cef_v8_value_t *proton_engine_bridge_v8_units(cef_list_value_t *units) {
  if (units == NULL || units->get_size(units) > INT32_MAX) {
    return NULL;
  }
  size_t count = units->get_size(units);
  cef_v8_value_t *array = cef_v8_value_create_array((int)count);
  if (array == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    cef_dictionary_value_t *unit = units->get_dictionary(units, index);
    cef_v8_value_t *value = proton_engine_bridge_v8_unit(unit);
    if (unit != NULL) {
      unit->base.release((cef_base_ref_counted_t *)unit);
    }
    if (value == NULL ||
        !proton_engine_bridge_v8_set_index(array, (int)index, value)) {
      array->base.release((cef_base_ref_counted_t *)array);
      return NULL;
    }
  }
  return array;
}

static cef_v8_value_t *proton_engine_bridge_v8_ops(cef_list_value_t *ops) {
  if (ops == NULL || ops->get_size(ops) > INT32_MAX) {
    return NULL;
  }
  size_t count = ops->get_size(ops);
  cef_v8_value_t *array = cef_v8_value_create_array((int)count);
  if (array == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    cef_dictionary_value_t *op = ops->get_dictionary(ops, index);
    char *name = proton_engine_bridge_dictionary_string(op, "name");
    cef_v8_value_t *object = cef_v8_value_create_object(NULL, NULL);
    cef_v8_value_t *value = proton_engine_bridge_v8_string(name);
    free(name);
    if (op != NULL) {
      op->base.release((cef_base_ref_counted_t *)op);
    }
    if (object == NULL || value == NULL ||
        !proton_engine_bridge_v8_set_key(object, "name", value) ||
        !proton_engine_bridge_v8_set_index(array, (int)index, object)) {
      if (object != NULL) {
        object->base.release((cef_base_ref_counted_t *)object);
      }
      array->base.release((cef_base_ref_counted_t *)array);
      return NULL;
    }
  }
  return array;
}

static cef_v8_value_t *proton_engine_bridge_v8_extensions(
    cef_list_value_t *extensions) {
  if (extensions == NULL || extensions->get_size(extensions) > INT32_MAX) {
    return NULL;
  }
  size_t count = extensions->get_size(extensions);
  cef_v8_value_t *array = cef_v8_value_create_array((int)count);
  if (array == NULL) {
    return NULL;
  }
  for (size_t index = 0; index < count; index++) {
    cef_dictionary_value_t *extension =
        extensions->get_dictionary(extensions, index);
    char *name = proton_engine_bridge_dictionary_string(extension, "namespace");
    cef_string_t apis_key = {0};
    proton_engine_bridge_set_string(&apis_key, "apis");
    cef_list_value_t *apis = extension != NULL
                                 ? extension->get_list(extension, &apis_key)
                                 : NULL;
    cef_string_clear(&apis_key);
    cef_v8_value_t *object = cef_v8_value_create_object(NULL, NULL);
    cef_v8_value_t *name_value = proton_engine_bridge_v8_string(name);
    cef_v8_value_t *apis_value = proton_engine_bridge_v8_string_list(apis);
    free(name);
    if (apis != NULL) {
      apis->base.release((cef_base_ref_counted_t *)apis);
    }
    if (extension != NULL) {
      extension->base.release((cef_base_ref_counted_t *)extension);
    }
    if (object == NULL || name_value == NULL || apis_value == NULL ||
        !proton_engine_bridge_v8_set_key(object, "namespace", name_value) ||
        !proton_engine_bridge_v8_set_key(object, "apis", apis_value) ||
        !proton_engine_bridge_v8_set_index(array, (int)index, object)) {
      if (object != NULL) {
        object->base.release((cef_base_ref_counted_t *)object);
      }
      array->base.release((cef_base_ref_counted_t *)array);
      return NULL;
    }
  }
  return array;
}

static cef_v8_value_t *proton_engine_bridge_v8_grant(
    cef_dictionary_value_t *grant) {
  cef_v8_value_t *result = cef_v8_value_create_object(NULL, NULL);
  char *source_origin = proton_engine_bridge_dictionary_string(
      grant, "source_origin");
  cef_string_t ops_key = {0};
  cef_string_t extensions_key = {0};
  cef_string_t units_key = {0};
  proton_engine_bridge_set_string(&ops_key, "ops");
  proton_engine_bridge_set_string(&extensions_key, "extensions");
  proton_engine_bridge_set_string(&units_key, "initialization_units");
  cef_list_value_t *ops = grant != NULL ? grant->get_list(grant, &ops_key) : NULL;
  cef_list_value_t *extensions =
      grant != NULL ? grant->get_list(grant, &extensions_key) : NULL;
  cef_list_value_t *units =
      grant != NULL ? grant->get_list(grant, &units_key) : NULL;
  cef_string_clear(&ops_key);
  cef_string_clear(&extensions_key);
  cef_string_clear(&units_key);
  cef_v8_value_t *origin_value = proton_engine_bridge_v8_string(source_origin);
  cef_v8_value_t *ops_value = proton_engine_bridge_v8_ops(ops);
  cef_v8_value_t *extensions_value = proton_engine_bridge_v8_extensions(extensions);
  cef_v8_value_t *units_value = proton_engine_bridge_v8_units(units);
  free(source_origin);
  if (ops != NULL) {
    ops->base.release((cef_base_ref_counted_t *)ops);
  }
  if (extensions != NULL) {
    extensions->base.release((cef_base_ref_counted_t *)extensions);
  }
  if (units != NULL) {
    units->base.release((cef_base_ref_counted_t *)units);
  }
  if (result == NULL || origin_value == NULL || ops_value == NULL ||
      extensions_value == NULL || units_value == NULL ||
      !proton_engine_bridge_v8_set_key(result, "source_origin", origin_value) ||
      !proton_engine_bridge_v8_set_key(result, "ops", ops_value) ||
      !proton_engine_bridge_v8_set_key(result, "extensions", extensions_value) ||
      !proton_engine_bridge_v8_set_key(result, "initialization_units",
                                        units_value)) {
    if (result != NULL) {
      result->base.release((cef_base_ref_counted_t *)result);
    }
    return NULL;
  }
  return result;
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
  proton_engine_bridge_set_string(&key, "window_controls_overlay");
  cef_dictionary_value_t *overlay =
      extra_info->get_dictionary(extra_info, &key);
  cef_string_clear(&key);
  if (overlay != NULL) {
    cef_string_t field = {0};
    proton_engine_window_controls_overlay_geometry_t geometry = {0};
    proton_engine_bridge_set_string(&field, "visible");
    geometry.visible = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    proton_engine_bridge_set_string(&field, "x");
    geometry.x = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    proton_engine_bridge_set_string(&field, "y");
    geometry.y = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    proton_engine_bridge_set_string(&field, "width");
    geometry.width = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    proton_engine_bridge_set_string(&field, "height");
    geometry.height = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    proton_engine_bridge_set_string(&field, "zoom_percent");
    geometry.zoom_percent = overlay->get_int(overlay, &field);
    cef_string_clear(&field);
    (void)proton_engine_window_controls_overlay_store_browser(browser,
                                                               &geometry);
    overlay->base.release((cef_base_ref_counted_t *)overlay);
  }

  proton_engine_bridge_set_string(&key, "bridge");
  cef_dictionary_value_t *bridge =
      extra_info->get_dictionary(extra_info, &key);
  cef_string_clear(&key);
  if (bridge != NULL) {
    cef_dictionary_value_t *config = bridge->copy(bridge, 0);
    bridge->base.release((cef_base_ref_counted_t *)bridge);
    (void)proton_engine_bridge_store_browser_config(browser, config);
  }
}

void CEF_CALLBACK proton_engine_bridge_renderer_on_browser_destroyed(
    cef_render_process_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  int browser_id = browser != NULL ? browser->get_identifier(browser) : 0;
  proton_engine_bridge_browser_config_t *bridge_state =
      proton_engine_bridge_find_browser_config(browser);
  proton_engine_window_controls_overlay_browser_t *overlay_state =
      proton_engine_window_controls_overlay_find_browser(browser);
  if ((bridge_state != NULL && bridge_state->instance_count > 1) ||
      (overlay_state != NULL && overlay_state->instance_count > 1)) {
    if (bridge_state != NULL && bridge_state->instance_count > 1) {
      bridge_state->instance_count--;
    }
    if (overlay_state != NULL && overlay_state->instance_count > 1) {
      overlay_state->instance_count--;
    }
    return;
  }
  proton_engine_bridge_browser_config_t **config_cursor = &g_browser_configs;
  while (*config_cursor != NULL) {
    proton_engine_bridge_browser_config_t *entry = *config_cursor;
    if (entry->browser_id == browser_id) {
      *config_cursor = entry->next;
      if (entry->config != NULL) {
        entry->config->base.release((cef_base_ref_counted_t *)entry->config);
      }
      free(entry->lifecycle_outcome);
      free(entry->lifecycle_page_instance);
      free(entry->lifecycle_url);
      proton_engine_bridge_diagnostic_dispose(&entry->lifecycle_diagnostic);
      free(entry);
      break;
    }
    config_cursor = &entry->next;
  }
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
  proton_engine_window_controls_overlay_browser_t **overlay_browser_cursor =
      &g_overlay_browsers;
  while (*overlay_browser_cursor != NULL) {
    proton_engine_window_controls_overlay_browser_t *entry =
        *overlay_browser_cursor;
    if (entry->browser_id == browser_id) {
      *overlay_browser_cursor = entry->next;
      free(entry);
      break;
    }
    overlay_browser_cursor = &entry->next;
  }
  proton_engine_window_controls_overlay_context_t **overlay_context_cursor =
      &g_overlay_contexts;
  while (*overlay_context_cursor != NULL) {
    proton_engine_window_controls_overlay_context_t *entry =
        *overlay_context_cursor;
    if (entry->browser_id == browser_id) {
      *overlay_context_cursor = entry->next;
      proton_engine_window_controls_overlay_release_context(entry);
      continue;
    }
    overlay_context_cursor = &entry->next;
  }
}

void proton_engine_bridge_renderer_on_context_created(
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context,
    cef_v8_handler_t *native_invoke_handler) {
  if (browser == NULL || frame == NULL || context == NULL ||
      !proton_engine_bridge_is_default_context(frame, context)) {
    return;
  }
  proton_engine_window_controls_overlay_browser_t *overlay =
      proton_engine_window_controls_overlay_find_browser(browser);
  if (overlay != NULL) {
    (void)proton_engine_window_controls_overlay_install(
        browser, context, &overlay->geometry);
  }
  proton_engine_bridge_browser_config_t *browser_config =
      proton_engine_bridge_find_browser_config(browser);
  if (native_invoke_handler == NULL || browser_config == NULL ||
      browser_config->config == NULL) {
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
  cef_dictionary_value_t *grant = proton_engine_bridge_renderer_find_grant(
      browser_config->config, url);
  if (grant == NULL) {
    proton_engine_bridge_send_lifecycle(frame, "ineligible", page_instance,
                                        url, NULL);
    free(url);
    free(page_instance);
    return;
  }
  if (!context->enter(context)) {
    proton_engine_bridge_send_failure(
        frame, page_instance, url, "prepare", "bridge_context_enter_failed",
        "failed to enter the main frame JavaScript context", NULL, NULL, NULL);
    free(url);
    free(page_instance);
    grant->base.release((cef_base_ref_counted_t *)grant);
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
  cef_string_t source = {0};
  cef_string_t source_url = {0};
  proton_engine_bridge_set_string(
      &source, (const char *)proton_engine_bridge_bootstrap_source);
  proton_engine_bridge_set_string(&source_url,
                                  "proton://bridge/bootstrap.js");
  cef_v8_value_t *installer = NULL;
  cef_v8_exception_t *exception = NULL;
  int evaluated = context->eval(context, &source, &source_url, 1, &installer,
                                &exception);
  cef_string_clear(&source);
  cef_string_clear(&source_url);
  cef_v8_value_t *grant_value = proton_engine_bridge_v8_grant(grant);
  cef_v8_value_t *page_instance_value =
      proton_engine_bridge_v8_string(page_instance);
  cef_v8_value_t *dispatcher = NULL;
  if (evaluated && exception == NULL && installer != NULL &&
      installer->is_function(installer) && global != NULL &&
      native_invoke != NULL && grant_value != NULL &&
      page_instance_value != NULL) {
    cef_v8_value_t *arguments[] = {native_invoke, grant_value,
                                   page_instance_value};
    native_invoke = NULL;
    grant_value = NULL;
    page_instance_value = NULL;
    dispatcher = proton_engine_bridge_execute(installer, context, global, 3,
                                               arguments);
  }
  if (installer != NULL) {
    installer->base.release((cef_base_ref_counted_t *)installer);
  }
  if (grant_value != NULL) {
    grant_value->base.release((cef_base_ref_counted_t *)grant_value);
  }
  if (page_instance_value != NULL) {
    page_instance_value->base.release(
        (cef_base_ref_counted_t *)page_instance_value);
  }
  if ((!evaluated || exception != NULL) && dispatcher != NULL) {
    dispatcher->base.release((cef_base_ref_counted_t *)dispatcher);
    dispatcher = NULL;
  }
  if (!evaluated || exception != NULL || dispatcher == NULL ||
      !dispatcher->is_object(dispatcher)) {
    proton_engine_bridge_send_failure(
        frame, page_instance, url, "bootstrap", "bridge_bootstrap_failed",
        dispatcher == NULL ? "bridge bootstrap returned no dispatcher"
                           : "bridge bootstrap returned an invalid dispatcher",
        NULL, "proton://bridge/bootstrap.js", exception);
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
      int initialized = proton_engine_bridge_initialize_units(
          grant, context, frame, entry->page_instance, url);
      if (initialized) {
        proton_engine_bridge_send_lifecycle(
            frame, "ready", entry->page_instance, url, NULL);
      }
    } else {
      proton_engine_bridge_send_failure(
          frame, page_instance, url, "prepare",
          "bridge_context_allocation_failed",
          "failed to allocate bridge context state", NULL, NULL, NULL);
    }
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
  free(page_instance);
  free(url);
  grant->base.release((cef_base_ref_counted_t *)grant);
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

  proton_engine_window_controls_overlay_context_t **overlay_cursor =
      &g_overlay_contexts;
  while (*overlay_cursor != NULL) {
    proton_engine_window_controls_overlay_context_t *entry = *overlay_cursor;
    if (entry->context == context) {
      *overlay_cursor = entry->next;
      proton_engine_window_controls_overlay_release_context(entry);
      break;
    }
    overlay_cursor = &entry->next;
  }
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

static int proton_engine_window_controls_overlay_dispatch(
    cef_browser_t *browser, cef_list_value_t *args) {
  if (browser == NULL || args == NULL || args->get_size(args) < 6) {
    return 1;
  }
  proton_engine_window_controls_overlay_geometry_t geometry = {
      .visible = args->get_bool(args, 0),
      .x = args->get_int(args, 1),
      .y = args->get_int(args, 2),
      .width = args->get_int(args, 3),
      .height = args->get_int(args, 4),
      .zoom_percent = args->get_int(args, 5),
  };
  proton_engine_window_controls_overlay_browser_t *browser_state =
      proton_engine_window_controls_overlay_find_browser(browser);
  if (browser_state != NULL) {
    browser_state->geometry = geometry;
  }
  proton_engine_window_controls_overlay_context_t *entry =
      proton_engine_window_controls_overlay_find_context(browser);
  if (entry == NULL || !entry->context->is_valid(entry->context) ||
      !entry->context->enter(entry->context)) {
    return 1;
  }
  cef_v8_value_t *update = proton_engine_bridge_get_property(
      entry->dispatcher, "update");
  if (update != NULL && update->is_function(update)) {
    cef_v8_value_t *arguments[] = {
        cef_v8_value_create_bool(geometry.visible),
        cef_v8_value_create_int(geometry.x),
        cef_v8_value_create_int(geometry.y),
        cef_v8_value_create_int(geometry.width),
        cef_v8_value_create_int(geometry.height),
        cef_v8_value_create_int(geometry.zoom_percent),
    };
    cef_v8_value_t *result = proton_engine_bridge_execute(
        update, entry->context, entry->dispatcher, 6, arguments);
    if (result != NULL) {
      result->base.release((cef_base_ref_counted_t *)result);
    }
  }
  if (update != NULL) {
    update->base.release((cef_base_ref_counted_t *)update);
  }
  entry->context->exit(entry->context);
  return 1;
}

static int proton_engine_bridge_handle_lifecycle_probe(
    cef_browser_t *browser, cef_frame_t *frame) {
  proton_engine_bridge_browser_config_t *config =
      proton_engine_bridge_find_browser_config(browser);
  if (config == NULL || config->config == NULL) {
    return 1;
  }
  char *url = proton_engine_bridge_frame_url(frame);
  if (url == NULL || strcmp(url, "about:blank") == 0) {
    free(url);
    return 1;
  }
  int same_page =
      proton_engine_urls_same_document(config->lifecycle_url, url) &&
      config->lifecycle_page_instance != NULL;
  if (same_page && config->lifecycle_outcome != NULL &&
      strcmp(config->lifecycle_outcome, "pending") != 0) {
    proton_engine_bridge_send_lifecycle(
        frame, config->lifecycle_outcome, config->lifecycle_page_instance, url,
        config->has_lifecycle_diagnostic ? &config->lifecycle_diagnostic
                                         : NULL);
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
  if (!proton_engine_bridge_renderer_config_allows_page(config->config, url)) {
    proton_engine_bridge_send_lifecycle(frame, "ineligible", page_instance,
                                        url, NULL);
  } else {
    proton_engine_bridge_send_failure(
        frame, page_instance, url, "prepare", "bridge_lifecycle_missing",
        "main frame finished loading without a terminal bridge lifecycle outcome",
        NULL, NULL, NULL);
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
  int is_window_controls_overlay =
      strcmp(message_name, PROTON_ENGINE_WINDOW_CONTROLS_OVERLAY_MESSAGE) == 0;
  free(message_name);
  if (is_lifecycle_probe) {
    return proton_engine_bridge_handle_lifecycle_probe(browser, frame);
  }
  if (!is_response && !is_event && !is_window_controls_overlay) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    return 1;
  }
  int handled;
  if (is_window_controls_overlay) {
    handled = proton_engine_window_controls_overlay_dispatch(browser, args);
  } else {
    proton_engine_bridge_context_t *entry =
        proton_engine_bridge_find_context(browser);
    handled = is_response
                  ? proton_engine_bridge_dispatch_response(entry, args)
                  : proton_engine_bridge_dispatch_event(entry, args);
  }
  args->base.release((cef_base_ref_counted_t *)args);
  return handled;
}
