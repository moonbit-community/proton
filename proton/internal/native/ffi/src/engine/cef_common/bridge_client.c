#include "bridge_client.h"

#include <stdlib.h>
#include <string.h>

#include "../../proton_event.h"
#include "bridge_policy.h"
#include "bridge_renderer.h"
#include "message.h"
#include "strings.h"

#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_values_capi.h"

typedef struct proton_engine_bridge_pending {
  int64_t request_id;
  int browser_id;
  int renderer_pending_id;
  char *page_instance;
  cef_frame_t *frame;
  struct proton_engine_bridge_pending *next;
} proton_engine_bridge_pending_t;

static proton_engine_bridge_pending_t *g_bridge_pending;

int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id,
    proton_window_id_t public_window, const char *op, const char *payload,
    const char *page_instance, const char *source_origin) {
  if (runtime == NULL || request_id <= 0 || public_window <= 0 || op == NULL ||
      payload == NULL || page_instance == NULL || source_origin == NULL) {
    return 0;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_BRIDGE_REQUEST);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  event->window = public_window;
  const char *items[] = {op, payload, page_instance, source_origin};
  if (!proton_event_set_items(event, items, 4) ||
      !proton_event_try_publish(event)) {
    proton_event_destroy(event);
    return 0;
  }
  return 1;
}

int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime, int64_t request_id) {
  if (runtime == NULL || request_id <= 0) {
    return 0;
  }
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_BRIDGE_REQUEST_CANCELLED);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  return proton_event_publish(event);
}

static size_t proton_engine_bridge_pending_count(void) {
  size_t count = 0;
  for (proton_engine_bridge_pending_t *pending = g_bridge_pending;
       pending != NULL; pending = pending->next) {
    count++;
  }
  return count;
}

static void
proton_engine_bridge_pending_free(proton_engine_bridge_pending_t *pending) {
  if (pending == NULL) {
    return;
  }
  if (pending->frame != NULL) {
    pending->frame->base.release((cef_base_ref_counted_t *)pending->frame);
  }
  free(pending->page_instance);
  free(pending);
}

static int proton_engine_bridge_pending_add(int64_t request_id, int browser_id,
                                            int renderer_pending_id,
                                            const char *page_instance,
                                            cef_frame_t *frame) {
  if (frame == NULL || page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  if (proton_engine_bridge_pending_count() >=
      PROTON_ENGINE_MAX_BRIDGE_PENDING) {
    return 0;
  }
  proton_engine_bridge_pending_t *pending =
      (proton_engine_bridge_pending_t *)calloc(1, sizeof(*pending));
  if (pending == NULL) {
    return 0;
  }
  pending->request_id = request_id;
  pending->browser_id = browser_id;
  pending->renderer_pending_id = renderer_pending_id;
  pending->page_instance = proton_engine_strdup(page_instance);
  if (pending->page_instance == NULL) {
    free(pending);
    return 0;
  }
  frame->base.add_ref((cef_base_ref_counted_t *)frame);
  pending->frame = frame;
  pending->next = g_bridge_pending;
  g_bridge_pending = pending;
  return 1;
}

static int proton_engine_bridge_pending_cancel(proton_engine_runtime_t *runtime,
                                               int browser_id,
                                               int renderer_pending_id,
                                               const char *page_instance) {
  if (page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        pending->renderer_pending_id == renderer_pending_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id);
      proton_engine_bridge_pending_free(pending);
      return 1;
    }
    cursor = &pending->next;
  }
  return 0;
}

static void
proton_engine_bridge_pending_remove_context(proton_engine_runtime_t *runtime,
                                            int browser_id,
                                            const char *page_instance) {
  /* A stale context release must not cancel requests from its replacement. */
  if (page_instance == NULL || page_instance[0] == '\0') {
    return;
  }
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id);
      proton_engine_bridge_pending_free(pending);
      continue;
    }
    cursor = &pending->next;
  }
}

static proton_engine_bridge_pending_t *
proton_engine_bridge_pending_take(int64_t request_id) {
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->request_id == request_id) {
      *cursor = pending->next;
      pending->next = NULL;
      return pending;
    }
    cursor = &pending->next;
  }
  return NULL;
}

void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime, int browser_id) {
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id) {
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(
          runtime, pending->request_id);
      proton_engine_bridge_pending_free(pending);
      continue;
    }
    cursor = &pending->next;
  }
}

void proton_engine_bridge_pending_clear_all(void) {
  proton_engine_bridge_pending_t *pending = g_bridge_pending;
  g_bridge_pending = NULL;
  while (pending != NULL) {
    proton_engine_bridge_pending_t *next = pending->next;
    proton_engine_bridge_pending_free(pending);
    pending = next;
  }
}

static int proton_engine_send_bridge_response_to_frame(cef_frame_t *frame,
                                                       int renderer_pending_id,
                                                       int ok,
                                                       const char *payload_json,
                                                       const char *error_text) {
  if (frame == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name,
                           PROTON_ENGINE_BRIDGE_RESPONSE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 4);
  args->set_int(args, 0, renderer_pending_id);
  args->set_bool(args, 1, ok ? 1 : 0);
  cef_string_t payload = {0};
  cef_string_t error = {0};
  proton_engine_set_string(&payload,
                           payload_json != NULL ? payload_json : "null");
  proton_engine_set_string(&error, error_text != NULL ? error_text : "");
  args->set_string(args, 2, &payload);
  args->set_string(args, 3, &error);
  cef_string_clear(&payload);
  cef_string_clear(&error);
  frame->send_process_message(frame, PID_RENDERER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

static void proton_engine_reject_renderer_request(cef_frame_t *frame,
                                                  int renderer_pending_id,
                                                  const char *message) {
  (void)proton_engine_send_bridge_response_to_frame(
      frame, renderer_pending_id, 0, "null",
      message != NULL ? message : "bridge request rejected");
}

static char *proton_engine_v8_value_to_utf8(cef_v8_value_t *value) {
  if (value == NULL || !value->is_string(value)) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(value->get_string_value(value));
}

static int proton_engine_send_bridge_request_to_browser(
    cef_frame_t *frame, const char *action, int pending_id, const char *op,
    const char *payload_json, const char *page_instance) {
  if (frame == NULL || action == NULL || op == NULL || payload_json == NULL ||
      page_instance == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 5);
  cef_string_t action_value = {0};
  cef_string_t op_value = {0};
  cef_string_t payload_value = {0};
  cef_string_t page_instance_value = {0};
  proton_engine_set_string(&action_value, action);
  proton_engine_set_string(&op_value, op);
  proton_engine_set_string(&payload_value, payload_json);
  proton_engine_set_string(&page_instance_value, page_instance);
  args->set_string(args, 0, &action_value);
  args->set_int(args, 1, pending_id);
  args->set_string(args, 2, &op_value);
  args->set_string(args, 3, &payload_value);
  args->set_string(args, 4, &page_instance_value);
  cef_string_clear(&action_value);
  cef_string_clear(&op_value);
  cef_string_clear(&payload_value);
  cef_string_clear(&page_instance_value);
  frame->send_process_message(frame, PID_BROWSER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

int CEF_CALLBACK proton_engine_bridge_v8_execute(
    cef_v8_handler_t *self, const cef_string_t *name, cef_v8_value_t *object,
    size_t arguments_count, cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval, cef_string_t *exception) {
  (void)self;
  (void)object;
  char *function_name = proton_engine_cef_string_to_utf8(name);
  int handled =
      function_name != NULL &&
      strcmp(function_name, PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION) == 0;
  free(function_name);
  if (!handled) {
    return 0;
  }
  if (retval != NULL) {
    *retval = NULL;
  }
  if (arguments_count < 5 || arguments[0] == NULL ||
      !arguments[0]->is_string(arguments[0]) || arguments[1] == NULL ||
      !arguments[1]->is_int(arguments[1])) {
    proton_engine_set_string(exception, "invokeOp requires action, pending id, "
                                        "name, payload and page instance");
    return 1;
  }
  char *action = proton_engine_v8_value_to_utf8(arguments[0]);
  int pending_id = arguments[1]->get_int_value(arguments[1]);
  char *op = proton_engine_v8_value_to_utf8(arguments[2]);
  char *payload_json = proton_engine_v8_value_to_utf8(arguments[3]);
  char *page_instance = proton_engine_v8_value_to_utf8(arguments[4]);
  int is_request = action != NULL && strcmp(action, "request") == 0;
  int is_cancel = action != NULL && strcmp(action, "cancel") == 0;
  if ((!is_request && !is_cancel) ||
      (is_request && (!proton_engine_bridge_op_is_valid(op) ||
                      !proton_engine_bridge_payload_is_valid(
                          payload_json, PROTON_ENGINE_MAX_BRIDGE_BYTES))) ||
      !proton_engine_bridge_page_instance_is_valid(page_instance)) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "invalid bridge request");
    return 1;
  }
  cef_v8_context_t *context = cef_v8_context_get_current_context();
  if (context == NULL) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "no current V8 context");
    return 1;
  }
  cef_browser_t *browser = context->get_browser(context);
  cef_frame_t *frame = context->get_frame(context);
  if (browser == NULL || frame == NULL) {
    if (browser != NULL) {
      browser->base.release((cef_base_ref_counted_t *)browser);
    }
    if (frame != NULL) {
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
    context->base.release((cef_base_ref_counted_t *)context);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "bridge requires a browser frame");
    return 1;
  }
  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  if (!proton_engine_url_is_bridge_candidate(frame_url)) {
    browser->base.release((cef_base_ref_counted_t *)browser);
    frame->base.release((cef_base_ref_counted_t *)frame);
    context->base.release((cef_base_ref_counted_t *)context);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    free(frame_url);
    proton_engine_set_string(exception,
                             "bridge is not available for this page");
    return 1;
  }
  free(frame_url);
  int ok = proton_engine_send_bridge_request_to_browser(
      frame, action, pending_id, op, payload_json, page_instance);
  if (!ok) {
    proton_engine_set_string(exception, "failed to send bridge request");
  }
  browser->base.release((cef_base_ref_counted_t *)browser);
  frame->base.release((cef_base_ref_counted_t *)frame);
  context->base.release((cef_base_ref_counted_t *)context);
  free(action);
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
}

int CEF_CALLBACK proton_engine_bridge_client_on_process_message_received(
    cef_client_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_process_id_t source_process, cef_process_message_t *message) {
  (void)self;
  if (source_process != PID_RENDERER || browser == NULL || frame == NULL ||
      message == NULL) {
    return 0;
  }
  char *message_name =
      proton_engine_userfree_to_utf8(message->get_name(message));
  int is_request =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE) == 0;
  int is_context_disposed =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_CONTEXT_DISPOSED_MESSAGE) == 0;
  int is_lifecycle =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_LIFECYCLE_MESSAGE) == 0;
  free(message_name);

  int browser_id = browser->get_identifier(browser);
  proton_engine_bridge_host_t host = {0};
  int has_host = proton_engine_bridge_resolve_host(browser, &host);
  if (is_lifecycle) {
    cef_list_value_t *args = message->get_argument_list(message);
    if (has_host && host.lifecycle != NULL && frame->is_main(frame) &&
        args != NULL && args->get_size(args) >= 14) {
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      char *current_url =
          main_frame != NULL
              ? proton_engine_userfree_to_utf8(main_frame->get_url(main_frame))
              : NULL;
      (void)proton_engine_bridge_lifecycle_update_from_message(
          host.lifecycle, args, current_url);
      free(current_url);
      if (main_frame != NULL) {
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
      proton_engine_bridge_signal(host.runtime);
    }
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  if (is_context_disposed) {
    cef_list_value_t *args = message->get_argument_list(message);
    char *page_instance =
        args != NULL && args->get_size(args) >= 1
            ? proton_engine_userfree_to_utf8(args->get_string(args, 0))
            : NULL;
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    proton_engine_bridge_pending_remove_context(has_host ? host.runtime : NULL,
                                                browser_id, page_instance);
    free(page_instance);
    return 1;
  }
  if (!is_request) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL || args->get_size(args) < 5) {
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  char *action = proton_engine_userfree_to_utf8(args->get_string(args, 0));
  int renderer_pending_id = args->get_int(args, 1);
  char *op = proton_engine_userfree_to_utf8(args->get_string(args, 2));
  char *payload_json =
      proton_engine_userfree_to_utf8(args->get_string(args, 3));
  char *page_instance =
      proton_engine_userfree_to_utf8(args->get_string(args, 4));
  args->base.release((cef_base_ref_counted_t *)args);
  if (action != NULL && strcmp(action, "cancel") == 0) {
    (void)proton_engine_bridge_pending_cancel(has_host ? host.runtime : NULL,
                                              browser_id, renderer_pending_id,
                                              page_instance);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  if (action == NULL || strcmp(action, "request") != 0) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(action);

  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  int64_t request_id = 0;
  char *source_origin = NULL;
  proton_engine_bridge_request_status_t build_status =
      !has_host || host.runtime == NULL
          ? PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED
          : proton_engine_bridge_build_request(
                host.bridge_config, frame_url, op, payload_json, page_instance,
                host.max_payload_bytes, host.next_request_id, &request_id,
                &source_origin);
  if (build_status != PROTON_ENGINE_BRIDGE_REQUEST_OK) {
    proton_engine_reject_renderer_request(
        frame, renderer_pending_id,
        proton_engine_bridge_request_reject_message(build_status));
    free(frame_url);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(frame_url);
  if (!proton_engine_bridge_pending_add(
          request_id, browser_id, renderer_pending_id, page_instance, frame) ||
      !proton_engine_runtime_enqueue_bridge_request(
          host.runtime, request_id, host.public_window, op, payload_json,
          page_instance, source_origin)) {
    proton_engine_bridge_pending_t *pending =
        proton_engine_bridge_pending_take(request_id);
    proton_engine_bridge_pending_free(pending);
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge request queue is full");
  }
  free(source_origin);
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
}

int32_t proton_engine_runtime_respond_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id, int32_t ok,
    const char *body_json, char *error, size_t error_len) {
  if (body_json == NULL) {
    proton_engine_set_message(error, error_len, "body_json is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_bridge_pending_t *pending =
      proton_engine_bridge_pending_take(request_id);
  if (pending == NULL) {
    proton_engine_set_message(error, error_len,
                              "bridge request is no longer pending");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }
  int sent = proton_engine_send_bridge_response_to_frame(
      pending->frame, pending->renderer_pending_id, ok, ok ? body_json : "null",
      ok ? "" : body_json);
  proton_engine_bridge_pending_free(pending);
  if (!sent) {
    proton_engine_set_message(error, error_len,
                              "failed to send bridge response to renderer");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }
  proton_engine_bridge_response_sent(runtime);
  return PROTON_OK;
}
