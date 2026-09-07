#include "../../src/engine/cef_common/browser_session.h"
#include "../../src/proton_web_request_config.h"
#include "../../src/proton_event.h"

#include "moonbit.h"

#include <stdio.h>
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
  cef_browser_t browser = {0};
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
  int32_t command = proton_browser_session_command(
      session, &browser, "cancel_download", 45, error, sizeof(error));
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
  proton_web_request_config_t *config = NULL;
  int32_t create = proton_internal_web_request_config_create(&config);
  int32_t add = proton_internal_web_request_config_add_cancel_prefix(
      config, "https://blocked.example/assets/");
  int32_t duplicate = proton_internal_web_request_config_add_cancel_prefix(
      config, "https://blocked.example/assets/");
  int32_t empty =
      proton_internal_web_request_config_add_cancel_prefix(config, "");
  int matching = proton_web_request_config_should_cancel(
      config, "https://blocked.example/assets/app.js");
  int nonmatching = proton_web_request_config_should_cancel(
      config, "https://allowed.example/app.js");
  int case_sensitive = proton_web_request_config_should_cancel(
      config, "https://BLOCKED.example/assets/app.js");
  char trace[160];
  int written = snprintf(trace, sizeof(trace),
                         "matching=%d,nonmatching=%d,case_sensitive=%d,empty=%d,duplicate=%d",
                         matching, nonmatching, case_sensitive, empty,
                         duplicate);
  proton_internal_web_request_config_destroy(config);
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
  proton_web_request_config_t *config = NULL;
  proton_browser_policy_t policy = {0};
  if (proton_internal_web_request_config_create(&config) != PROTON_OK ||
      proton_internal_web_request_config_add_cancel_prefix(
          config, "https://blocked.example/") != PROTON_OK) {
    proton_internal_web_request_config_destroy(config);
    return proton_test_copy_trace("setup-error");
  }
  proton_browser_session_t *session =
      proton_browser_session_create(&policy, config, NULL, NULL);
  cef_resource_request_handler_t *handler =
      proton_browser_resource_handler_create(config);
  proton_internal_web_request_config_destroy(config);
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
