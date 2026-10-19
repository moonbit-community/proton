#include "../../src/engine/cef_common/browser_session.h"
#include "../../src/proton_web_request_config.h"
#include "../../src/proton_event.h"

#include "moonbit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  cef_before_download_callback_t callback;
  int refs;
  int continue_calls;
  int release_calls;
} proton_test_before_download_callback_t;

typedef struct {
  cef_download_item_callback_t callback;
  int refs;
  int cancel_calls;
  int release_calls;
} proton_test_download_item_callback_t;

typedef struct {
  cef_download_item_t item;
  uint32_t id;
  int in_progress;
} proton_test_download_item_t;

static proton_test_before_download_callback_t *proton_test_before_from_base(
    cef_base_ref_counted_t *base) {
  return (proton_test_before_download_callback_t *)base;
}

static void CEF_CALLBACK proton_test_before_add_ref(
    cef_base_ref_counted_t *base) {
  proton_test_before_from_base(base)->refs++;
}

static int CEF_CALLBACK proton_test_before_release(
    cef_base_ref_counted_t *base) {
  proton_test_before_download_callback_t *callback =
      proton_test_before_from_base(base);
  callback->release_calls++;
  callback->refs--;
  return callback->refs == 0;
}

static void CEF_CALLBACK proton_test_before_continue(
    cef_before_download_callback_t *self, const cef_string_t *path,
    int show_dialog) {
  proton_test_before_download_callback_t *callback =
      (proton_test_before_download_callback_t *)self;
  (void)path;
  (void)show_dialog;
  callback->continue_calls++;
}

static proton_test_download_item_callback_t *proton_test_item_from_base(
    cef_base_ref_counted_t *base) {
  return (proton_test_download_item_callback_t *)base;
}

static void CEF_CALLBACK proton_test_item_add_ref(
    cef_base_ref_counted_t *base) {
  proton_test_item_from_base(base)->refs++;
}

static int CEF_CALLBACK proton_test_item_release(
    cef_base_ref_counted_t *base) {
  proton_test_download_item_callback_t *callback =
      proton_test_item_from_base(base);
  callback->release_calls++;
  callback->refs--;
  return callback->refs == 0;
}

static void CEF_CALLBACK proton_test_item_cancel(
    cef_download_item_callback_t *self) {
  proton_test_download_item_callback_t *callback =
      (proton_test_download_item_callback_t *)self;
  callback->cancel_calls++;
}

static uint32_t CEF_CALLBACK proton_test_download_id(
    cef_download_item_t *self) {
  return ((proton_test_download_item_t *)self)->id;
}

static int CEF_CALLBACK proton_test_download_is_in_progress(
    cef_download_item_t *self) {
  return ((proton_test_download_item_t *)self)->in_progress;
}

static int CEF_CALLBACK proton_test_download_is_false(
    cef_download_item_t *self) {
  (void)self;
  return 0;
}

static int64_t CEF_CALLBACK proton_test_download_bytes(
    cef_download_item_t *self) {
  (void)self;
  return 0;
}

static int CEF_CALLBACK proton_test_download_percent(
    cef_download_item_t *self) {
  (void)self;
  return -1;
}

static void proton_test_before_init(
    proton_test_before_download_callback_t *callback) {
  memset(callback, 0, sizeof(*callback));
  callback->callback.base.size = sizeof(callback->callback);
  callback->callback.base.add_ref = proton_test_before_add_ref;
  callback->callback.base.release = proton_test_before_release;
  callback->callback.cont = proton_test_before_continue;
  callback->refs = 1;
}

static void proton_test_item_callback_init(
    proton_test_download_item_callback_t *callback) {
  memset(callback, 0, sizeof(*callback));
  callback->callback.base.size = sizeof(callback->callback);
  callback->callback.base.add_ref = proton_test_item_add_ref;
  callback->callback.base.release = proton_test_item_release;
  callback->callback.cancel = proton_test_item_cancel;
  callback->refs = 1;
}

static void proton_test_download_init(proton_test_download_item_t *download,
                                      uint32_t id) {
  memset(download, 0, sizeof(*download));
  download->item.base.size = sizeof(download->item);
  download->item.is_in_progress = proton_test_download_is_in_progress;
  download->item.is_complete = proton_test_download_is_false;
  download->item.is_canceled = proton_test_download_is_false;
  download->item.is_interrupted = proton_test_download_is_false;
  download->item.get_percent_complete = proton_test_download_percent;
  download->item.get_total_bytes = proton_test_download_bytes;
  download->item.get_received_bytes = proton_test_download_bytes;
  download->item.get_id = proton_test_download_id;
  download->id = id;
  download->in_progress = 1;
}

static moonbit_bytes_t proton_test_copy_trace(const char *trace) {
  size_t length = strlen(trace);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, trace, length);
  return result;
}

static moonbit_bytes_t proton_test_download_deny_trace(
    int update_before_response, const char *action) {
  proton_browser_policy_t policy = {0};
  proton_test_before_download_callback_t before;
  proton_test_download_item_callback_t item_callback;
  proton_test_download_item_t download;
  char error[128] = {0};
  char trace[192];

  policy.download = PROTON_BROWSER_POLICY_ASK;
  proton_test_before_init(&before);
  proton_test_item_callback_init(&item_callback);
  proton_test_download_init(&download, 41);

  proton_event_dispatch_begin();
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  cef_string_t suggested_name = {0};
  (void)proton_browser_session_before_download(
      session, &download.item, &suggested_name, &before.callback);
  if (update_before_response) {
    proton_browser_session_download_updated(
        session, &download.item, &item_callback.callback);
  }
  int32_t status = proton_browser_session_respond(
      session, 1, action, NULL, error, sizeof(error));
  if (!update_before_response) {
    proton_browser_session_download_updated(
        session, &download.item, &item_callback.callback);
  }

  int written = snprintf(
      trace, sizeof(trace),
      "before_continue=%d,before_release=%d,item_cancel=%d,item_release=%d,respond=%d",
      before.continue_calls, before.release_calls, item_callback.cancel_calls,
      item_callback.release_calls, status);
  proton_browser_session_destroy(session);
  proton_event_dispatch_end();
  if (written < 0 || (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_deny_after_update_trace(void) {
  return proton_test_download_deny_trace(1, "deny");
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_deny_before_update_trace(void) {
  return proton_test_download_deny_trace(0, "deny");
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_invalid_response_trace(void) {
  return proton_test_download_deny_trace(1, "invalid");
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_empty_response_trace(void) {
  return proton_test_download_deny_trace(1, "");
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_denied_download_policy_trace(void) {
  proton_browser_policy_t policy = {0};
  proton_test_before_download_callback_t before;
  proton_test_download_item_t download;
  char trace[128];

  policy.download = PROTON_BROWSER_POLICY_DENY;
  proton_test_before_init(&before);
  proton_test_download_init(&download, 42);
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  cef_string_t suggested_name = {0};
  int handled = proton_browser_session_before_download(
      session, &download.item, &suggested_name, &before.callback);
  int written = snprintf(
      trace, sizeof(trace),
      "handled=%d,before_continue=%d,before_release=%d", handled,
      before.continue_calls, before.release_calls);
  proton_browser_session_destroy(session);
  if (written < 0 || (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_unpublished_download_request_trace(void) {
  proton_browser_policy_t policy = {0};
  proton_test_before_download_callback_t before;
  proton_test_download_item_t download;
  char trace[128];

  policy.download = PROTON_BROWSER_POLICY_ASK;
  proton_test_before_init(&before);
  proton_test_download_init(&download, 43);
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  cef_string_t suggested_name = {0};
  int handled = proton_browser_session_before_download(
      session, &download.item, &suggested_name, &before.callback);
  int written = snprintf(
      trace, sizeof(trace),
      "handled=%d,before_continue=%d,before_release=%d", handled,
      before.continue_calls, before.release_calls);
  proton_browser_session_destroy(session);
  if (written < 0 || (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_single_completion_trace(void) {
  proton_browser_policy_t policy = {0};
  proton_test_before_download_callback_t before;
  proton_test_download_item_callback_t item_callback;
  proton_test_download_item_t download;
  char error[128] = {0};
  char trace[224];

  policy.download = PROTON_BROWSER_POLICY_ASK;
  proton_test_before_init(&before);
  proton_test_item_callback_init(&item_callback);
  proton_test_download_init(&download, 44);
  proton_event_dispatch_begin();
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  cef_string_t suggested_name = {0};
  (void)proton_browser_session_before_download(
      session, &download.item, &suggested_name, &before.callback);
  proton_browser_session_download_updated(
      session, &download.item, &item_callback.callback);
  int32_t status = proton_browser_session_respond(
      session, 1, "deny", NULL, error, sizeof(error));
  int32_t repeat = proton_browser_session_respond(
      session, 1, "deny", NULL, error, sizeof(error));
  proton_browser_session_destroy(session);
  proton_event_dispatch_end();

  int written = snprintf(
      trace, sizeof(trace),
      "before_continue=%d,before_release=%d,item_cancel=%d,item_release=%d,respond=%d,repeat=%d",
      before.continue_calls, before.release_calls, item_callback.cancel_calls,
      item_callback.release_calls, status, repeat);
  if (written < 0 || (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_download_command_beats_allow_trace(void) {
  proton_browser_policy_t policy = {0};
  proton_test_before_download_callback_t before;
  proton_test_download_item_callback_t item_callback;
  proton_test_download_item_t download;
  char error[128] = {0};
  char trace[224];

  policy.download = PROTON_BROWSER_POLICY_ASK;
  proton_test_before_init(&before);
  proton_test_item_callback_init(&item_callback);
  proton_test_download_init(&download, 45);
  proton_event_dispatch_begin();
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  cef_string_t suggested_name = {0};
  (void)proton_browser_session_before_download(
      session, &download.item, &suggested_name, &before.callback);
  proton_browser_session_download_updated(
      session, &download.item, &item_callback.callback);
  int32_t command = proton_browser_cancel_download(
      session, 45, error, sizeof(error));
  int32_t status = proton_browser_session_respond(
      session, 1, "allow", NULL, error, sizeof(error));
  proton_browser_session_destroy(session);
  proton_event_dispatch_end();

  int written = snprintf(
      trace, sizeof(trace),
      "before_continue=%d,before_release=%d,item_cancel=%d,item_release=%d,command=%d,respond=%d",
      before.continue_calls, before.release_calls, item_callback.cancel_calls,
      item_callback.release_calls, command, status);
  if (written < 0 || (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_test_web_request_cancel_trace(void) {
  int32_t create = 0;
  proton_web_request_config_owner_t *owner =
      proton_internal_web_request_config_create(&create);
  proton_web_request_config_t *config = owner->value;
  int32_t add = proton_internal_web_request_config_add_cancel_prefix(
      owner, "https://blocked.example/assets/");
  int matching = proton_web_request_config_should_cancel(
      config, "https://blocked.example/assets/app.js");
  int nonmatching = proton_web_request_config_should_cancel(
      config, "https://allowed.example/app.js");
  int case_sensitive = proton_web_request_config_should_cancel(
      config, "https://BLOCKED.example/assets/app.js");
  char trace[160];
  int written = snprintf(trace, sizeof(trace),
                         "matching=%d,nonmatching=%d,case_sensitive=%d",
                         matching, nonmatching, case_sensitive);
  moonbit_decref(owner);
  if (create != 0 || add != 0 || written < 0 ||
      (size_t)written >= sizeof(trace)) {
    return proton_test_copy_trace("trace-error");
  }
  return proton_test_copy_trace(trace);
}

static cef_string_userfree_t CEF_CALLBACK proton_test_empty_request_url(
    cef_request_t *self) {
  (void)self;
  return NULL;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_test_resource_handler_lifetime_trace(void) {
  int32_t create = 0;
  proton_web_request_config_owner_t *owner =
      proton_internal_web_request_config_create(&create);
  proton_web_request_config_t *config = owner->value;
  proton_browser_policy_t policy = {0};
  if (create != PROTON_OK ||
      proton_internal_web_request_config_add_cancel_prefix(
          owner, "https://blocked.example/") != PROTON_OK) {
    moonbit_decref(owner);
    return proton_test_copy_trace("setup-error");
  }
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, config, NULL, NULL);
  cef_resource_request_handler_t *handler =
      proton_browser_resource_handler_create(config, 0, 0);
  moonbit_decref(owner);
  proton_browser_session_destroy(session);
  if (handler == NULL) return proton_test_copy_trace("handler-error");

  // CEF may retain the handler after its UI-owned session is gone.
  cef_request_t request = {0};
  request.get_url = proton_test_empty_request_url;
  handler->base.add_ref(&handler->base);
  int first_release = handler->base.release(&handler->base);
  int continued = handler->on_before_resource_load(
      handler, NULL, NULL, &request, NULL) == RV_CONTINUE;
  int last_release = handler->base.release(&handler->base);
  char trace[100];
  snprintf(trace, sizeof(trace), "continued=%d,first_release=%d,last_release=%d",
           continued, first_release, last_release);
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_test_header_case_trace(void) {
  int32_t create = 0;
  proton_web_request_config_owner_t *owner =
      proton_internal_web_request_config_create(&create);
  proton_web_request_config_t *config = owner->value;
  if (create != PROTON_OK) {
    moonbit_decref(owner);
    return proton_test_copy_trace("setup-error");
  }
  int first = proton_internal_web_request_config_add_header_prefix(
      owner, "https://api.example/Path/", "Authorization", "Token AbC");
  int different_path = proton_internal_web_request_config_add_header_prefix(
      owner, "https://api.example/path/", "authorization", "second");
  const char *value = proton_web_request_config_header_value(
      config, "https://api.example/Path/data", "AUTHORIZATION");
  char trace[160];
  snprintf(trace, sizeof(trace),
           "first=%d,different_path=%d,value=%s",
           first, different_path, value != NULL ? value : "(null)");
  moonbit_decref(owner);
  return proton_test_copy_trace(trace);
}

/* Each edit must reach its own CEF method and release the acquired frame. */
static struct {
  cef_frame_t frame;
  char operations[9];
  int operation_count;
  int releases;
} proton_test_edit_frame;

static int CEF_CALLBACK proton_test_edit_release(cef_base_ref_counted_t *base) {
  (void)base;
  proton_test_edit_frame.releases++;
  return 1;
}

#define PROTON_TEST_EDIT(name, letter) \
  static void CEF_CALLBACK proton_test_edit_##name(cef_frame_t *frame) { \
    (void)frame; \
    proton_test_edit_frame.operations[proton_test_edit_frame.operation_count++] = letter; \
  }
PROTON_TEST_EDIT(undo, 'u')
PROTON_TEST_EDIT(redo, 'r')
PROTON_TEST_EDIT(cut, 'x')
PROTON_TEST_EDIT(copy, 'c')
PROTON_TEST_EDIT(paste, 'p')
PROTON_TEST_EDIT(paste_and_match_style, 'm')
PROTON_TEST_EDIT(del, 'd')
PROTON_TEST_EDIT(select_all, 'a')
#undef PROTON_TEST_EDIT

static cef_frame_t *CEF_CALLBACK proton_test_focused_frame(cef_browser_t *browser) {
  (void)browser;
  return &proton_test_edit_frame.frame;
}

static cef_frame_t *CEF_CALLBACK proton_test_missing_frame(cef_browser_t *browser) {
  (void)browser;
  return NULL;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_test_edit_operations_trace(void) {
  memset(&proton_test_edit_frame, 0, sizeof(proton_test_edit_frame));
  cef_frame_t *frame = &proton_test_edit_frame.frame;
  frame->base.release = proton_test_edit_release;
  frame->undo = proton_test_edit_undo;
  frame->redo = proton_test_edit_redo;
  frame->cut = proton_test_edit_cut;
  frame->copy = proton_test_edit_copy;
  frame->paste = proton_test_edit_paste;
  frame->paste_and_match_style = proton_test_edit_paste_and_match_style;
  frame->del = proton_test_edit_del;
  frame->select_all = proton_test_edit_select_all;
  cef_browser_t browser = {0};
  browser.get_focused_frame = proton_test_focused_frame;
  char error[128] = {0};
  int status = proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_UNDO, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_REDO, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_CUT, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_COPY, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_PASTE, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_PASTE_AND_MATCH_STYLE, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_DELETE, error, sizeof(error));
  status |= proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_SELECT_ALL, error, sizeof(error));
  browser.get_focused_frame = proton_test_missing_frame;
  int missing = proton_browser_perform_browser_operation(NULL, &browser, PROTON_BROWSER_UNDO, error, sizeof(error));
  int unknown = proton_browser_perform_browser_operation(NULL, &browser, -1, NULL, 0);
  if (unknown != PROTON_ERR_INVALID_ARGUMENT) return proton_test_copy_trace("unknown-operation-accepted");
  char trace[256];
  snprintf(trace, sizeof(trace), "operations=%s,releases=%d,status=%d,missing=%d,error=%s",
      proton_test_edit_frame.operations, proton_test_edit_frame.releases,
      status, missing, error);
  return proton_test_copy_trace(trace);
}

MOONBIT_FFI_EXPORT int32_t proton_test_browser_operation_abi(
    int32_t operation, int32_t index) {
  static const int32_t operations[] = {
    PROTON_BROWSER_BACK,
    PROTON_BROWSER_FORWARD,
    PROTON_BROWSER_RELOAD,
    PROTON_BROWSER_RELOAD_IGNORE_CACHE,
    PROTON_BROWSER_STOP,
    PROTON_BROWSER_FOCUS,
    PROTON_BROWSER_UNDO,
    PROTON_BROWSER_REDO,
    PROTON_BROWSER_CUT,
    PROTON_BROWSER_COPY,
    PROTON_BROWSER_PASTE,
    PROTON_BROWSER_PASTE_AND_MATCH_STYLE,
    PROTON_BROWSER_DELETE,
    PROTON_BROWSER_SELECT_ALL,
    PROTON_BROWSER_OPEN_DEVTOOLS,
    PROTON_BROWSER_CLOSE_DEVTOOLS,
    PROTON_BROWSER_TOGGLE_DEVTOOLS,
  };
  return index >= 0 && (size_t)index < sizeof(operations) / sizeof(operations[0])
      && operation == operations[index];
}

/* Compare MoonBit enum values with the authoritative C event contract. */
MOONBIT_FFI_EXPORT moonbit_bytes_t proton_test_event_contract_name(int32_t value,
                                                                 int32_t group) {
  switch (group) {
  case 0:
    switch (value) {
#define PROTON_EVENT_KIND(name, tag, mb_name) \
    case PROTON_EVENT_##name: return proton_test_copy_trace(#mb_name);
      PROTON_EVENT_KINDS(PROTON_EVENT_KIND)
#undef PROTON_EVENT_KIND
    }
    break;
  case 1:
    switch (value) {
#define PROTON_EVENT_FIELD(name, mb_name) \
    case PROTON_EVENT_INT64_##name: return proton_test_copy_trace(#mb_name);
      PROTON_EVENT_INT64_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
    }
    break;
  case 2:
    switch (value) {
#define PROTON_EVENT_FIELD(name, mb_name) \
    case PROTON_EVENT_INT_##name: return proton_test_copy_trace(#mb_name);
      PROTON_EVENT_INT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
    }
    break;
  case 3:
    switch (value) {
#define PROTON_EVENT_FIELD(name, mb_name) \
    case PROTON_EVENT_TEXT_##name: return proton_test_copy_trace(#mb_name);
      PROTON_EVENT_TEXT_FIELDS(PROTON_EVENT_FIELD)
#undef PROTON_EVENT_FIELD
    }
    break;
  }
  return proton_test_copy_trace("unknown");
}

MOONBIT_FFI_EXPORT int32_t proton_test_event_contract_count(int32_t group) {
  switch (group) {
#define PROTON_EVENT_KIND(name, tag, mb_name) + 1
  case 0: return 0 PROTON_EVENT_KINDS(PROTON_EVENT_KIND);
#undef PROTON_EVENT_KIND
#define PROTON_EVENT_FIELD(name, mb_name) + 1
  case 1: return 0 PROTON_EVENT_INT64_FIELDS(PROTON_EVENT_FIELD);
  case 2: return 0 PROTON_EVENT_INT_FIELDS(PROTON_EVENT_FIELD);
  case 3: return 0 PROTON_EVENT_TEXT_FIELDS(PROTON_EVENT_FIELD);
#undef PROTON_EVENT_FIELD
  default: return 0;
  }
}

static bool proton_test_capture_event(void *data, proton_event_t *event) {
  proton_event_t *out = data;
  proton_event_clear(out);
  *out = *event;
  free(event);
  return true;
}

static proton_browser_session_t *proton_test_event_session(proton_event_t *out) {
  proton_browser_policy_t policy = {0};
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, NULL, NULL, NULL);
  proton_browser_session_bind_contents(session, 7, 11);
  proton_event_bind_sink(proton_test_capture_event, out);
  proton_event_dispatch_begin();
  return session;
}

MOONBIT_FFI_EXPORT void proton_test_find_result_event(proton_event_t *out) {
  proton_browser_session_t *session = proton_test_event_session(out);
  proton_browser_session_find_result(session, 91, 13, -3, 17, 29, 41, 5, 1);
  proton_browser_session_destroy(session);
  proton_event_dispatch_end();
  proton_event_unbind_sink(out);
}

MOONBIT_FFI_EXPORT void proton_test_renderer_terminated_event(proton_event_t *out) {
  proton_browser_session_t *session = proton_test_event_session(out);
  proton_browser_session_renderer_terminated(
      session, 3, -107, "https://example.test/page", "renderer stopped");
  proton_browser_session_destroy(session);
  proton_event_dispatch_end();
  proton_event_unbind_sink(out);
}
