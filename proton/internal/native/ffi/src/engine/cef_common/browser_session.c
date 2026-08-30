#include "browser_session.h"

#include "../../proton_json.h"
#include "../../proton_event.h"

#include "include/capi/cef_download_item_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/internal/cef_string.h"

#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <stdatomic.h>
#endif

typedef enum {
  PROTON_BROWSER_REQUEST_NAVIGATION = 1,
  PROTON_BROWSER_REQUEST_POPUP = 2,
  PROTON_BROWSER_REQUEST_DOWNLOAD = 3,
  PROTON_BROWSER_REQUEST_CERTIFICATE = 4,
  PROTON_BROWSER_REQUEST_MEDIA = 5,
} proton_browser_request_kind_t;

typedef struct proton_browser_pending {
  uint64_t id;
  proton_browser_request_kind_t kind;
  char *url;
  uint32_t permissions;
  cef_frame_t *frame;
  cef_request_t *request;
  cef_before_download_callback_t *download;
  cef_callback_t *certificate;
  cef_media_access_callback_t *media;
  struct proton_browser_pending *next;
} proton_browser_pending_t;

typedef struct proton_browser_download {
  uint32_t id;
  cef_download_item_callback_t *callback;
  struct proton_browser_download *next;
} proton_browser_download_t;

typedef struct proton_pdf_print_callback {
  cef_pdf_print_callback_t callback;
#ifdef _WIN32
  volatile LONG refs;
#else
  atomic_int refs;
#endif
  proton_window_id_t window;
  int32_t request_id;
} proton_pdf_print_callback_t;

typedef struct proton_browser_navigation_bypass {
  char *url;
  char *method;
  struct proton_browser_navigation_bypass *next;
} proton_browser_navigation_bypass_t;

struct proton_browser_session {
  proton_browser_policy_t policy;
  proton_window_id_t window;
  uint64_t next_request_id;
  proton_browser_pending_t *pending;
  proton_browser_download_t *downloads;
  proton_browser_navigation_bypass_t *navigation_bypasses;
  proton_browser_signal_fn signal;
  void *signal_user_data;
  char *url;
  char *title;
  int32_t is_loading;
  int32_t next_find_request_id;
  int32_t active_find_request_id;
  int32_t next_pdf_request_id;
};

static char *proton_browser_cef_string_to_utf8(const cef_string_t *value);

static proton_pdf_print_callback_t *proton_pdf_print_callback_from_base(
    cef_base_ref_counted_t *base) {
  return (proton_pdf_print_callback_t *)base;
}

static void CEF_CALLBACK proton_pdf_print_add_ref(
    cef_base_ref_counted_t *base) {
  proton_pdf_print_callback_t *callback =
      proton_pdf_print_callback_from_base(base);
#ifdef _WIN32
  (void)InterlockedIncrement(&callback->refs);
#else
  (void)atomic_fetch_add_explicit(&callback->refs, 1, memory_order_relaxed);
#endif
}

static int CEF_CALLBACK proton_pdf_print_release(
    cef_base_ref_counted_t *base) {
  proton_pdf_print_callback_t *callback =
      proton_pdf_print_callback_from_base(base);
#ifdef _WIN32
  LONG refs = InterlockedDecrement(&callback->refs);
#else
  int refs = atomic_fetch_sub_explicit(
                 &callback->refs, 1, memory_order_acq_rel) -
             1;
#endif
  if (refs == 0) {
    free(callback);
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK proton_pdf_print_has_one_ref(
    cef_base_ref_counted_t *base) {
  proton_pdf_print_callback_t *callback =
      proton_pdf_print_callback_from_base(base);
#ifdef _WIN32
  return callback->refs == 1;
#else
  return atomic_load_explicit(&callback->refs, memory_order_acquire) == 1;
#endif
}

static int CEF_CALLBACK proton_pdf_print_has_at_least_one_ref(
    cef_base_ref_counted_t *base) {
  proton_pdf_print_callback_t *callback =
      proton_pdf_print_callback_from_base(base);
#ifdef _WIN32
  return callback->refs > 0;
#else
  return atomic_load_explicit(&callback->refs, memory_order_acquire) > 0;
#endif
}

static void CEF_CALLBACK proton_pdf_print_finished(
    cef_pdf_print_callback_t *self, const cef_string_t *path, int ok) {
  proton_pdf_print_callback_t *callback =
      (proton_pdf_print_callback_t *)self;
  char *result_path = proton_browser_cef_string_to_utf8(path);
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_PDF_PRINT_FINISHED, callback->window);
  if (event != NULL && result_path != NULL &&
      proton_event_set_text(&event->text_a, result_path)) {
    event->request_id = callback->request_id;
    event->bool_a = ok != 0 ? 1 : 0;
    (void)proton_event_publish(event);
  } else {
    proton_event_destroy(event);
  }
  free(result_path);
}

static void proton_browser_set_message(char *error, size_t error_len,
                                       const char *message) {
  if (error == NULL || error_len == 0) {
    return;
  }
  snprintf(error, error_len, "%s", message != NULL ? message : "");
}

static char *proton_browser_copy_string(const char *value) {
  if (value == NULL) {
    return NULL;
  }
  size_t length = strlen(value);
  char *copy = (char *)malloc(length + 1);
  if (copy != NULL) {
    memcpy(copy, value, length + 1);
  }
  return copy;
}

static char *proton_browser_cef_string_to_utf8(const cef_string_t *value) {
  if (value == NULL || value->str == NULL || value->length == 0) {
    return proton_browser_copy_string("");
  }
  cef_string_utf8_t utf8 = {0};
  if (!cef_string_utf16_to_utf8(value->str, value->length, &utf8)) {
    return NULL;
  }
  char *copy = (char *)malloc(utf8.length + 1);
  if (copy != NULL) {
    memcpy(copy, utf8.str, utf8.length);
    copy[utf8.length] = '\0';
  }
  cef_string_utf8_clear(&utf8);
  return copy;
}

static char *proton_browser_userfree_to_utf8(cef_string_userfree_t value) {
  char *copy = proton_browser_cef_string_to_utf8(value);
  if (value != NULL) {
    cef_string_userfree_free(value);
  }
  return copy;
}

static int proton_browser_enqueue_event(proton_browser_session_t *session,
                                        proton_event_t *event) {
  if (session == NULL || event == NULL) {
    proton_event_destroy(event);
    return 0;
  }
  return proton_event_publish(event);
}

proton_browser_session_t *proton_browser_session_create(
    const proton_browser_policy_t *policy, proton_browser_signal_fn signal,
    void *signal_user_data) {
  proton_browser_session_t *session =
      (proton_browser_session_t *)calloc(1, sizeof(*session));
  if (session == NULL) {
    return NULL;
  }
  session->policy = *policy;
  session->next_request_id = 1;
  session->next_pdf_request_id = 1;
  session->signal = signal;
  session->signal_user_data = signal_user_data;
  return session;
}

static void proton_browser_pending_release(proton_browser_pending_t *pending) {
  if (pending == NULL) {
    return;
  }
  if (pending->frame != NULL) {
    pending->frame->base.release((cef_base_ref_counted_t *)pending->frame);
  }
  if (pending->request != NULL) {
    pending->request->base.release(
        (cef_base_ref_counted_t *)pending->request);
  }
  if (pending->download != NULL) {
    pending->download->base.release(
        (cef_base_ref_counted_t *)pending->download);
  }
  if (pending->certificate != NULL) {
    pending->certificate->base.release(
        (cef_base_ref_counted_t *)pending->certificate);
  }
  if (pending->media != NULL) {
    pending->media->base.release((cef_base_ref_counted_t *)pending->media);
  }
  free(pending->url);
  free(pending);
}

void proton_browser_session_destroy(proton_browser_session_t *session) {
  if (session == NULL) {
    return;
  }
  proton_browser_pending_t *pending = session->pending;
  while (pending != NULL) {
    proton_browser_pending_t *next = pending->next;
    if (pending->certificate != NULL) {
      pending->certificate->cancel(pending->certificate);
    }
    if (pending->media != NULL) {
      pending->media->cancel(pending->media);
    }
    proton_browser_pending_release(pending);
    pending = next;
  }
  proton_browser_download_t *download = session->downloads;
  while (download != NULL) {
    proton_browser_download_t *next = download->next;
    download->callback->cancel(download->callback);
    download->callback->base.release(
        (cef_base_ref_counted_t *)download->callback);
    free(download);
    download = next;
  }
  proton_browser_navigation_bypass_t *bypass =
      session->navigation_bypasses;
  while (bypass != NULL) {
    proton_browser_navigation_bypass_t *next = bypass->next;
    free(bypass->url);
    free(bypass->method);
    free(bypass);
    bypass = next;
  }
  free(session->url);
  free(session->title);
  free(session);
}

void proton_browser_session_bind_window(proton_browser_session_t *session,
                                         proton_window_id_t window) {
  if (session != NULL) {
    session->window = window;
  }
}

static void proton_browser_session_set_text(char **target, const char *value) {
  char *copy = proton_browser_copy_string(value != NULL ? value : "");
  if (copy == NULL) {
    return;
  }
  free(*target);
  *target = copy;
}

void proton_browser_session_loading_changed(proton_browser_session_t *session,
                                             const char *url,
                                             int32_t is_loading) {
  if (session == NULL) {
    return;
  }
  if (url != NULL && url[0] != '\0') {
    proton_browser_session_set_text(&session->url, url);
  }
  session->is_loading = is_loading != 0 ? 1 : 0;
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_LOADING_CHANGED, session->window);
  if (event != NULL) {
    event->bool_a = session->is_loading;
  }
  (void)proton_browser_enqueue_event(session, event);
}

void proton_browser_session_navigated(proton_browser_session_t *session,
                                      const char *url) {
  if (session == NULL) {
    return;
  }
  proton_browser_session_set_text(&session->url, url);
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_NAVIGATED, session->window);
  if (event != NULL && !proton_event_set_text(&event->text_a, url)) {
    proton_event_destroy(event);
    event = NULL;
  }
  (void)proton_browser_enqueue_event(session, event);
}

void proton_browser_session_title_updated(proton_browser_session_t *session,
                                           const char *title) {
  if (session == NULL) {
    return;
  }
  proton_browser_session_set_text(&session->title, title);
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_TITLE_UPDATED, session->window);
  if (event != NULL && !proton_event_set_text(&event->text_a, title)) {
    proton_event_destroy(event);
    event = NULL;
  }
  (void)proton_browser_enqueue_event(session, event);
}

void proton_browser_session_load_failed(proton_browser_session_t *session,
                                        const char *url,
                                        int32_t error_code,
                                        const char *error_text) {
  if (session == NULL) {
    return;
  }
  proton_browser_session_set_text(&session->url, url);
  session->is_loading = 0;
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_LOAD_FAILED, session->window);
  if (event != NULL &&
      (!proton_event_set_text(&event->text_a, url) ||
       !proton_event_set_text(&event->text_b, error_text))) {
    proton_event_destroy(event);
    event = NULL;
  }
  if (event != NULL) {
    event->int_a = error_code;
  }
  (void)proton_browser_enqueue_event(session, event);
}

static int32_t proton_browser_session_copy_text(const char *text,
                                                char *buffer,
                                                int32_t buffer_len,
                                                int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int32_t required = text != NULL ? (int32_t)strlen(text) : 0;
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, text != NULL ? text : "", (size_t)required + 1);
  return PROTON_OK;
}

int32_t proton_browser_session_copy_url(proton_browser_session_t *session,
                                        char *buffer, int32_t buffer_len,
                                        int32_t *out_required_len) {
  return proton_browser_session_copy_text(
      session != NULL ? session->url : NULL, buffer, buffer_len,
      out_required_len);
}

int32_t proton_browser_session_copy_title(proton_browser_session_t *session,
                                          char *buffer, int32_t buffer_len,
                                          int32_t *out_required_len) {
  return proton_browser_session_copy_text(
      session != NULL ? session->title : NULL, buffer, buffer_len,
      out_required_len);
}

int32_t proton_browser_session_is_loading(
    proton_browser_session_t *session) {
  return session != NULL ? session->is_loading : 0;
}

static proton_browser_pending_t *proton_browser_pending_new(
    proton_browser_session_t *session, proton_browser_request_kind_t kind,
    const char *url) {
  proton_browser_pending_t *pending =
      (proton_browser_pending_t *)calloc(1, sizeof(*pending));
  if (pending == NULL) {
    return NULL;
  }
  pending->id = session->next_request_id++;
  if (session->next_request_id == 0) {
    session->next_request_id = 1;
  }
  pending->kind = kind;
  pending->url = proton_browser_copy_string(url);
  if (pending->url == NULL) {
    free(pending);
    return NULL;
  }
  pending->next = session->pending;
  session->pending = pending;
  return pending;
}

static void proton_browser_pending_remove(proton_browser_session_t *session,
                                          proton_browser_pending_t *pending) {
  proton_browser_pending_t **cursor = &session->pending;
  while (*cursor != NULL) {
    if (*cursor == pending) {
      *cursor = pending->next;
      pending->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static proton_browser_pending_t *proton_browser_pending_take(
    proton_browser_session_t *session, uint64_t request_id) {
  proton_browser_pending_t *pending = session->pending;
  while (pending != NULL && pending->id != request_id) {
    pending = pending->next;
  }
  if (pending != NULL) {
    proton_browser_pending_remove(session, pending);
  }
  return pending;
}

static proton_event_t *proton_browser_request_event(
    proton_browser_session_t *session, proton_browser_pending_t *pending,
    proton_event_kind_t kind) {
  proton_event_t *event = proton_event_create(kind);
  if (event == NULL || !proton_event_set_text(&event->text_a, pending->url)) {
    proton_event_destroy(event);
    return NULL;
  }
  event->window = session->window;
  event->request_id = (int64_t)pending->id;
  return event;
}

static char *proton_browser_request_url(cef_request_t *request) {
  if (request == NULL || request->get_url == NULL) {
    return proton_browser_copy_string("");
  }
  return proton_browser_userfree_to_utf8(request->get_url(request));
}

static char *proton_browser_request_method(cef_request_t *request) {
  if (request == NULL || request->get_method == NULL) {
    return proton_browser_copy_string("");
  }
  return proton_browser_userfree_to_utf8(request->get_method(request));
}

static int proton_browser_consume_navigation_bypass(
    proton_browser_session_t *session, const char *url, const char *method) {
  proton_browser_navigation_bypass_t **cursor =
      &session->navigation_bypasses;
  while (*cursor != NULL) {
    proton_browser_navigation_bypass_t *candidate = *cursor;
    if (strcmp(candidate->url, url) == 0 &&
        strcmp(candidate->method, method) == 0) {
      *cursor = candidate->next;
      free(candidate->url);
      free(candidate->method);
      free(candidate);
      return 1;
    }
    cursor = &candidate->next;
  }
  return 0;
}

static int proton_browser_add_navigation_bypass(
    proton_browser_session_t *session, const char *url, const char *method) {
  proton_browser_navigation_bypass_t *bypass =
      (proton_browser_navigation_bypass_t *)calloc(1, sizeof(*bypass));
  if (bypass == NULL) {
    return 0;
  }
  bypass->url = proton_browser_copy_string(url);
  bypass->method = proton_browser_copy_string(method);
  if (bypass->url == NULL || bypass->method == NULL) {
    free(bypass->url);
    free(bypass->method);
    free(bypass);
    return 0;
  }
  bypass->next = session->navigation_bypasses;
  session->navigation_bypasses = bypass;
  return 1;
}

int proton_browser_session_before_browse(
    proton_browser_session_t *session, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect) {
  if (session == NULL) {
    return 0;
  }
  if (frame == NULL || frame->is_main == NULL || !frame->is_main(frame)) {
    return 0;
  }
  char *url = proton_browser_request_url(request);
  char *method = proton_browser_request_method(request);
  if (url == NULL || method == NULL) {
    free(url);
    free(method);
    return 1;
  }
  if (proton_browser_consume_navigation_bypass(session, url, method)) {
    free(url);
    free(method);
    return 0;
  }
  if (session->policy.navigation == PROTON_BROWSER_POLICY_ALLOW) {
    free(url);
    free(method);
    return 0;
  }
  if (session->policy.navigation == PROTON_BROWSER_POLICY_DENY) {
    free(url);
    free(method);
    return 1;
  }
  proton_browser_pending_t *pending = proton_browser_pending_new(
      session, PROTON_BROWSER_REQUEST_NAVIGATION, url);
  free(url);
  if (pending == NULL) {
    free(method);
    return 1;
  }
  pending->frame = frame;
  if (frame != NULL) {
    frame->base.add_ref((cef_base_ref_counted_t *)frame);
  }
  pending->request = request;
  if (request != NULL) {
    request->base.add_ref((cef_base_ref_counted_t *)request);
  }
  proton_event_t *event = proton_browser_request_event(
      session, pending, PROTON_EVENT_BROWSER_NAVIGATION_REQUESTED);
  if (event == NULL || !proton_event_set_text(&event->text_b, method)) {
    proton_event_destroy(event);
    free(method);
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
    return 1;
  }
  free(method);
  event->bool_a = user_gesture;
  event->bool_b = is_redirect;
  if (!proton_browser_enqueue_event(session, event)) {
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
  }
  return 1;
}

int proton_browser_session_before_popup(
    proton_browser_session_t *session, const cef_string_t *target_url,
    cef_window_open_disposition_t target_disposition, int user_gesture) {
  if (session == NULL || session->policy.popup != PROTON_BROWSER_POLICY_ASK) {
    return 1;
  }
  char *url = proton_browser_cef_string_to_utf8(target_url);
  if (url == NULL) {
    return 1;
  }
  proton_browser_pending_t *pending =
      proton_browser_pending_new(session, PROTON_BROWSER_REQUEST_POPUP, url);
  free(url);
  if (pending == NULL) {
    return 1;
  }
  proton_event_t *event = proton_browser_request_event(
      session, pending, PROTON_EVENT_BROWSER_POPUP_REQUESTED);
  if (event != NULL) {
    event->int_a = (int32_t)target_disposition;
    event->bool_a = user_gesture;
  }
  if (!proton_browser_enqueue_event(session, event)) {
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
  }
  return 1;
}

int proton_browser_session_can_download(
    proton_browser_session_t *session) {
  return session != NULL &&
         session->policy.download != PROTON_BROWSER_POLICY_DENY;
}

int proton_browser_session_before_download(
    proton_browser_session_t *session, cef_download_item_t *download_item,
    const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback) {
  if (session == NULL || callback == NULL) {
    return 0;
  }
  if (session->policy.download == PROTON_BROWSER_POLICY_ALLOW) {
    cef_string_t empty = {0};
    callback->cont(callback, &empty, 1);
    return 1;
  }
  if (session->policy.download != PROTON_BROWSER_POLICY_ASK) {
    return 1;
  }
  char *url =
      download_item != NULL && download_item->get_url != NULL
          ? proton_browser_userfree_to_utf8(download_item->get_url(download_item))
          : proton_browser_copy_string("");
  char *name = proton_browser_cef_string_to_utf8(suggested_name);
  if (url == NULL || name == NULL) {
    free(url);
    free(name);
    return 1;
  }
  proton_browser_pending_t *pending =
      proton_browser_pending_new(session, PROTON_BROWSER_REQUEST_DOWNLOAD, url);
  free(url);
  if (pending == NULL) {
    free(name);
    return 1;
  }
  pending->download = callback;
  callback->base.add_ref((cef_base_ref_counted_t *)callback);
  uint32_t download_id =
      download_item != NULL && download_item->get_id != NULL
          ? download_item->get_id(download_item)
          : 0;
  proton_event_t *event = proton_browser_request_event(
      session, pending, PROTON_EVENT_BROWSER_DOWNLOAD_REQUESTED);
  int valid = event != NULL && proton_event_set_text(&event->text_b, name);
  free(name);
  if (valid) {
    event->int_a = (int32_t)download_id;
  }
  if (!valid || !proton_browser_enqueue_event(session, event)) {
    if (!valid) {
      proton_event_destroy(event);
    }
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
  }
  return 1;
}

static proton_browser_download_t *proton_browser_download_find(
    proton_browser_session_t *session, uint32_t id) {
  proton_browser_download_t *download = session->downloads;
  while (download != NULL && download->id != id) {
    download = download->next;
  }
  return download;
}

void proton_browser_session_download_updated(
    proton_browser_session_t *session, cef_download_item_t *download_item,
    cef_download_item_callback_t *callback) {
  if (session == NULL || download_item == NULL || callback == NULL) {
    return;
  }
  uint32_t id = download_item->get_id(download_item);
  proton_browser_download_t *download =
      proton_browser_download_find(session, id);
  if (download == NULL && download_item->is_in_progress(download_item)) {
    download =
        (proton_browser_download_t *)calloc(1, sizeof(*download));
    if (download != NULL) {
      download->id = id;
      download->callback = callback;
      callback->base.add_ref((cef_base_ref_counted_t *)callback);
      download->next = session->downloads;
      session->downloads = download;
    }
  }
  const char *state = download_item->is_complete(download_item)
                          ? "complete"
                          : download_item->is_canceled(download_item)
                                ? "cancelled"
                                : download_item->is_interrupted(download_item)
                                      ? "interrupted"
                                      : "progress";
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_BROWSER_DOWNLOAD_UPDATED);
  if (event != NULL && proton_event_set_text(&event->text_a, state)) {
    event->window = session->window;
    event->int_a = (int32_t)id;
    event->int64_a = download_item->get_received_bytes(download_item);
    event->int64_b = download_item->get_total_bytes(download_item);
    event->int_b = download_item->get_percent_complete(download_item);
    (void)proton_browser_enqueue_event(session, event);
  } else {
    proton_event_destroy(event);
  }
  if (download != NULL && !download_item->is_in_progress(download_item)) {
    proton_browser_download_t **cursor = &session->downloads;
    while (*cursor != NULL && *cursor != download) {
      cursor = &(*cursor)->next;
    }
    if (*cursor != NULL) {
      *cursor = download->next;
    }
    download->callback->base.release(
        (cef_base_ref_counted_t *)download->callback);
    free(download);
  }
}

int proton_browser_session_certificate_error(
    proton_browser_session_t *session, cef_errorcode_t cert_error,
    const cef_string_t *request_url, cef_callback_t *callback) {
  if (session == NULL ||
      session->policy.certificate != PROTON_BROWSER_POLICY_ASK ||
      callback == NULL) {
    return 0;
  }
  char *url = proton_browser_cef_string_to_utf8(request_url);
  if (url == NULL) {
    return 0;
  }
  proton_browser_pending_t *pending = proton_browser_pending_new(
      session, PROTON_BROWSER_REQUEST_CERTIFICATE, url);
  free(url);
  if (pending == NULL) {
    return 0;
  }
  pending->certificate = callback;
  callback->base.add_ref((cef_base_ref_counted_t *)callback);
  proton_event_t *event = proton_browser_request_event(
      session, pending, PROTON_EVENT_BROWSER_CERTIFICATE_ERROR);
  if (event != NULL) {
    event->int_a = (int32_t)cert_error;
  }
  if (!proton_browser_enqueue_event(session, event)) {
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
    return 0;
  }
  return 1;
}

int proton_browser_session_media_permission(
    proton_browser_session_t *session, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback) {
  if (session == NULL ||
      session->policy.media != PROTON_BROWSER_POLICY_ASK ||
      callback == NULL) {
    return 0;
  }
  char *origin = proton_browser_cef_string_to_utf8(requesting_origin);
  if (origin == NULL) {
    return 0;
  }
  proton_browser_pending_t *pending = proton_browser_pending_new(
      session, PROTON_BROWSER_REQUEST_MEDIA, origin);
  free(origin);
  if (pending == NULL) {
    return 0;
  }
  pending->permissions = requested_permissions;
  pending->media = callback;
  callback->base.add_ref((cef_base_ref_counted_t *)callback);
  proton_event_t *event = proton_browser_request_event(
      session, pending, PROTON_EVENT_BROWSER_MEDIA_PERMISSION_REQUESTED);
  if (event != NULL) {
    event->int_a = (int32_t)requested_permissions;
  }
  if (!proton_browser_enqueue_event(session, event)) {
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
    return 0;
  }
  return 1;
}

static int proton_browser_response_fields(
    const char *response_json, uint64_t *out_request_id, char *action,
    size_t action_len, char **out_path) {
  proton_json_doc_t doc = {0};
  proton_json_value_t root = {0};
  proton_json_value_t request_id = {0};
  proton_json_value_t action_value = {0};
  int64_t parsed_id = 0;
  if (!proton_json_parse(&doc, response_json) ||
      !proton_json_root_object(&doc, &root) ||
      !proton_json_object_get(&doc, root, "request_id", &request_id) ||
      !proton_json_read_int64_string_or_number(&doc, request_id, &parsed_id) ||
      parsed_id <= 0 ||
      !proton_json_object_get(&doc, root, "action", &action_value) ||
      !proton_json_read_string(&doc, action_value, action, action_len)) {
    proton_json_dispose(&doc);
    return 0;
  }
  proton_json_value_t path = {0};
  if (out_path != NULL &&
      proton_json_object_get(&doc, root, "path", &path)) {
    *out_path = proton_json_copy_string(&doc, path);
    if (*out_path == NULL) {
      proton_json_dispose(&doc);
      return 0;
    }
  }
  *out_request_id = (uint64_t)parsed_id;
  proton_json_dispose(&doc);
  return 1;
}

int32_t proton_browser_session_respond_json(
    proton_browser_session_t *session, const char *response_json,
    char *error, size_t error_len) {
  if (session == NULL || response_json == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser session and response are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  uint64_t request_id = 0;
  char action[32] = {0};
  char *path = NULL;
  if (!proton_browser_response_fields(response_json, &request_id, action,
                                      sizeof(action), &path)) {
    proton_browser_set_message(error, error_len,
                               "browser response JSON is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_browser_pending_t *pending =
      proton_browser_pending_take(session, request_id);
  if (pending == NULL) {
    free(path);
    proton_browser_set_message(error, error_len,
                               "browser request is no longer pending");
    return PROTON_ERR_STALE_BROWSER_REQUEST;
  }
  int32_t status = PROTON_OK;
  switch (pending->kind) {
  case PROTON_BROWSER_REQUEST_NAVIGATION:
    if (strcmp(action, "allow") == 0 && pending->frame != NULL &&
        pending->request != NULL) {
      char *method = proton_browser_request_method(pending->request);
      if (method == NULL ||
          !proton_browser_add_navigation_bypass(
              session, pending->url, method)) {
        status = PROTON_ERR_ENGINE;
      } else {
        pending->frame->load_request(pending->frame, pending->request);
      }
      free(method);
    } else if (strcmp(action, "deny") != 0) {
      status = PROTON_ERR_INVALID_ARGUMENT;
    }
    break;
  case PROTON_BROWSER_REQUEST_POPUP:
    if (strcmp(action, "current") == 0) {
      /* Popup callbacks do not provide a durable target frame. The caller
       * should use the normal window load API after acknowledging the request. */
    } else if (strcmp(action, "deny") != 0) {
      status = PROTON_ERR_INVALID_ARGUMENT;
    }
    break;
  case PROTON_BROWSER_REQUEST_DOWNLOAD:
    if (strcmp(action, "allow") == 0 && pending->download != NULL) {
      cef_string_t destination = {0};
      if (path != NULL && path[0] != '\0') {
        cef_string_utf8_to_utf16(path, strlen(path), &destination);
      }
      pending->download->cont(pending->download, &destination,
                              path == NULL || path[0] == '\0');
      cef_string_clear(&destination);
    } else if (strcmp(action, "deny") != 0) {
      status = PROTON_ERR_INVALID_ARGUMENT;
    }
    break;
  case PROTON_BROWSER_REQUEST_CERTIFICATE:
    if (strcmp(action, "allow") == 0 && pending->certificate != NULL) {
      pending->certificate->cont(pending->certificate);
    } else if (strcmp(action, "deny") == 0 &&
               pending->certificate != NULL) {
      pending->certificate->cancel(pending->certificate);
    } else {
      status = PROTON_ERR_INVALID_ARGUMENT;
    }
    break;
  case PROTON_BROWSER_REQUEST_MEDIA:
    if (strcmp(action, "allow") == 0 && pending->media != NULL) {
      pending->media->cont(pending->media, pending->permissions);
    } else if (strcmp(action, "deny") == 0 && pending->media != NULL) {
      pending->media->cancel(pending->media);
    } else {
      status = PROTON_ERR_INVALID_ARGUMENT;
    }
    break;
  }
  if (status != PROTON_OK) {
    proton_browser_set_message(error, error_len,
                               "browser response action is invalid");
  }
  free(path);
  proton_browser_pending_release(pending);
  return status;
}

static int proton_browser_read_command(const char *command_json,
                                       char *command, size_t command_len,
                                       uint32_t *out_download_id) {
  proton_json_doc_t doc = {0};
  proton_json_value_t root = {0};
  proton_json_value_t command_value = {0};
  if (!proton_json_parse(&doc, command_json) ||
      !proton_json_root_object(&doc, &root) ||
      !proton_json_object_get(&doc, root, "command", &command_value) ||
      !proton_json_read_string(&doc, command_value, command, command_len)) {
    proton_json_dispose(&doc);
    return 0;
  }
  proton_json_value_t id = {0};
  int32_t parsed_id = 0;
  if (proton_json_object_get(&doc, root, "download_id", &id)) {
    if (!proton_json_read_int32(&doc, id, &parsed_id) || parsed_id < 0) {
      proton_json_dispose(&doc);
      return 0;
    }
    *out_download_id = (uint32_t)parsed_id;
  }
  proton_json_dispose(&doc);
  return 1;
}

int32_t proton_browser_session_command_json(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *command_json, char *error, size_t error_len) {
  if (session == NULL || browser == NULL || command_json == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser session, browser, and command are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char command[40] = {0};
  uint32_t download_id = 0;
  if (!proton_browser_read_command(command_json, command, sizeof(command),
                                   &download_id)) {
    proton_browser_set_message(error, error_len,
                               "browser command JSON is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (strcmp(command, "back") == 0) {
    browser->go_back(browser);
  } else if (strcmp(command, "forward") == 0) {
    browser->go_forward(browser);
  } else if (strcmp(command, "reload") == 0) {
    browser->reload(browser);
  } else if (strcmp(command, "reload_ignore_cache") == 0) {
    browser->reload_ignore_cache(browser);
  } else if (strcmp(command, "stop") == 0) {
    browser->stop_load(browser);
  } else if (strcmp(command, "cancel_download") == 0) {
    proton_browser_download_t *download =
        proton_browser_download_find(session, download_id);
    if (download == NULL) {
      proton_browser_set_message(error, error_len,
                                 "download is no longer active");
      return PROTON_ERR_STALE_BROWSER_REQUEST;
    }
    download->callback->cancel(download->callback);
  } else if (strcmp(command, "open_devtools") == 0 ||
             strcmp(command, "close_devtools") == 0) {
    if (!session->policy.devtools) {
      proton_browser_set_message(error, error_len,
                                 "DevTools are disabled by browser policy");
      return PROTON_ERR_UNSUPPORTED;
    }
    cef_browser_host_t *host = browser->get_host(browser);
    if (host == NULL) {
      proton_browser_set_message(error, error_len,
                                 "browser host is unavailable");
      return PROTON_ERR_ENGINE;
    }
    if (strcmp(command, "close_devtools") == 0) {
      host->close_dev_tools(host);
    } else {
      cef_window_info_t window_info = {0};
      cef_browser_settings_t settings = {0};
      window_info.size = sizeof(window_info);
      settings.size = sizeof(settings);
      host->show_dev_tools(host, &window_info, NULL, &settings, NULL);
    }
    host->base.release((cef_base_ref_counted_t *)host);
  } else {
    proton_browser_set_message(error, error_len,
                               "unknown browser command");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

int32_t proton_browser_navigation_state(
    cef_browser_t *browser, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len) {
  if (browser == NULL || out_can_go_back == NULL ||
      out_can_go_forward == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser and navigation outputs are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_can_go_back = browser->can_go_back(browser) ? 1 : 0;
  *out_can_go_forward = browser->can_go_forward(browser) ? 1 : 0;
  return PROTON_OK;
}

int32_t proton_browser_set_zoom_percent(
    cef_browser_t *browser, int32_t zoom_percent,
    char *error, size_t error_len) {
  if (browser == NULL || zoom_percent < 25 || zoom_percent > 500) {
    proton_browser_set_message(error, error_len,
                               "browser and zoom from 25 to 500 are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser host is unavailable");
    return PROTON_ERR_ENGINE;
  }
  double factor = (double)zoom_percent / 100.0;
  host->set_zoom_level(host, log(factor) / log(1.2));
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_set_audio_muted(
    cef_browser_t *browser, int32_t muted, char *error, size_t error_len) {
  if (browser == NULL || (muted != 0 && muted != 1)) {
    proton_browser_set_message(error, error_len,
                               "browser and muted flag are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->set_audio_muted == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "browser audio control is unavailable");
    return PROTON_ERR_ENGINE;
  }
  host->set_audio_muted(host, muted);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_is_audio_muted(
    cef_browser_t *browser, int32_t *out_muted, char *error,
    size_t error_len) {
  if (browser == NULL || out_muted == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser and muted output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->is_audio_muted == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "browser audio state is unavailable");
    return PROTON_ERR_ENGINE;
  }
  *out_muted = host->is_audio_muted(host) ? 1 : 0;
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_download_url(
    cef_browser_t *browser, const char *url, char *error, size_t error_len) {
  if (browser == NULL || url == NULL || url[0] == '\0') {
    proton_browser_set_message(error, error_len,
                               "browser and non-empty URL are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->start_download == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "programmatic download is unavailable");
    return PROTON_ERR_UNSUPPORTED;
  }
  cef_string_t download_url = {0};
  if (!cef_string_utf8_to_utf16(url, strlen(url), &download_url)) {
    host->base.release((cef_base_ref_counted_t *)host);
    proton_browser_set_message(error, error_len,
                               "failed to encode download URL as UTF-16");
    return PROTON_ERR_ENGINE;
  }
  host->start_download(host, &download_url);
  cef_string_clear(&download_url);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_print(
    cef_browser_t *browser, char *error, size_t error_len) {
  if (browser == NULL) {
    proton_browser_set_message(error, error_len, "browser is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->print == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len, "browser printing is unavailable");
    return PROTON_ERR_UNSUPPORTED;
  }
  host->print(host);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_print_to_pdf(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *path, int32_t landscape, int32_t print_background,
    double scale, double paper_width, double paper_height,
    int32_t prefer_css_page_size, int32_t margin_type,
    double margin_top, double margin_right, double margin_bottom,
    double margin_left, const char *page_ranges,
    int32_t display_header_footer, const char *header_template,
    const char *footer_template, int32_t generate_tagged_pdf,
    int32_t generate_document_outline, int32_t *out_request_id,
    char *error, size_t error_len) {
  if (session == NULL || browser == NULL || path == NULL || path[0] == '\0' ||
      page_ranges == NULL || header_template == NULL || footer_template == NULL ||
      out_request_id == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser, session, path, settings, and request output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->print_to_pdf == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "browser PDF printing is unavailable");
    return PROTON_ERR_UNSUPPORTED;
  }
  proton_pdf_print_callback_t *callback =
      (proton_pdf_print_callback_t *)calloc(1, sizeof(*callback));
  if (callback == NULL) {
    host->base.release((cef_base_ref_counted_t *)host);
    proton_browser_set_message(error, error_len,
                               "failed to allocate PDF print callback");
    return PROTON_ERR_ENGINE;
  }
  callback->callback.base.size = sizeof(callback->callback);
  callback->callback.base.add_ref = proton_pdf_print_add_ref;
  callback->callback.base.release = proton_pdf_print_release;
  callback->callback.base.has_one_ref = proton_pdf_print_has_one_ref;
  callback->callback.base.has_at_least_one_ref =
      proton_pdf_print_has_at_least_one_ref;
#ifdef _WIN32
  callback->refs = 1;
#else
  atomic_init(&callback->refs, 1);
#endif
  callback->window = session->window;
  callback->request_id = session->next_pdf_request_id;
  if (session->next_pdf_request_id == INT32_MAX) {
    session->next_pdf_request_id = 1;
  } else {
    session->next_pdf_request_id++;
  }
  callback->callback.on_pdf_print_finished = proton_pdf_print_finished;

  cef_string_t output_path = {0};
  cef_pdf_print_settings_t settings = {0};
  settings.size = sizeof(settings);
  settings.landscape = landscape;
  settings.print_background = print_background;
  settings.scale = scale;
  settings.paper_width = paper_width;
  settings.paper_height = paper_height;
  settings.prefer_css_page_size = prefer_css_page_size;
  settings.margin_type = (cef_pdf_print_margin_type_t)margin_type;
  settings.margin_top = margin_top;
  settings.margin_right = margin_right;
  settings.margin_bottom = margin_bottom;
  settings.margin_left = margin_left;
  settings.display_header_footer = display_header_footer;
  settings.generate_tagged_pdf = generate_tagged_pdf;
  settings.generate_document_outline = generate_document_outline;
  if (!cef_string_utf8_to_utf16(path, strlen(path), &output_path) ||
      !cef_string_utf8_to_utf16(page_ranges, strlen(page_ranges), &settings.page_ranges) ||
      !cef_string_utf8_to_utf16(header_template, strlen(header_template), &settings.header_template) ||
      !cef_string_utf8_to_utf16(footer_template, strlen(footer_template), &settings.footer_template)) {
    cef_string_clear(&output_path);
    cef_string_clear(&settings.page_ranges);
    cef_string_clear(&settings.header_template);
    cef_string_clear(&settings.footer_template);
    callback->callback.base.release(&callback->callback.base);
    host->base.release((cef_base_ref_counted_t *)host);
    proton_browser_set_message(error, error_len,
                               "failed to encode PDF print settings as UTF-16");
    return PROTON_ERR_ENGINE;
  }
  *out_request_id = callback->request_id;
  host->print_to_pdf(host, &output_path, &settings, &callback->callback);
  cef_string_clear(&output_path);
  cef_string_clear(&settings.page_ranges);
  cef_string_clear(&settings.header_template);
  cef_string_clear(&settings.footer_template);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_find_in_page(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *text, int32_t forward, int32_t match_case,
    int32_t find_next, int32_t *out_request_id, char *error,
    size_t error_len) {
  if (session == NULL || browser == NULL || text == NULL || text[0] == '\0' ||
      out_request_id == NULL) {
    proton_browser_set_message(
        error, error_len,
        "browser session, browser, non-empty text, and request output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((forward != 0 && forward != 1) ||
      (match_case != 0 && match_case != 1) ||
      (find_next != 0 && find_next != 1)) {
    proton_browser_set_message(error, error_len,
                               "find flags must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->find == NULL ||
      (find_next && host->stop_finding == NULL)) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "browser find is unavailable");
    return PROTON_ERR_UNSUPPORTED;
  }
  cef_string_t search_text = {0};
  if (!cef_string_utf8_to_utf16(text, strlen(text), &search_text)) {
    host->base.release((cef_base_ref_counted_t *)host);
    proton_browser_set_message(error, error_len,
                               "failed to encode find text as UTF-16");
    return PROTON_ERR_ENGINE;
  }
  /* Electron uses findNext to start a new session. CEF infers sessions and
     uses its final flag to request an active match. */
  if (find_next) {
    host->stop_finding(host, 1);
  }
  if (session->next_find_request_id == INT32_MAX) {
    session->next_find_request_id = 1;
  } else {
    session->next_find_request_id++;
  }
  session->active_find_request_id = session->next_find_request_id;
  *out_request_id = session->active_find_request_id;
  host->find(host, &search_text, forward, match_case, 1);
  cef_string_clear(&search_text);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_stop_find_in_page(
    cef_browser_t *browser, int32_t clear_selection, char *error,
    size_t error_len) {
  if (browser == NULL ||
      (clear_selection != 0 && clear_selection != 1)) {
    proton_browser_set_message(
        error, error_len,
        "browser is required and clear_selection must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL || host->stop_finding == NULL) {
    if (host != NULL) {
      host->base.release((cef_base_ref_counted_t *)host);
    }
    proton_browser_set_message(error, error_len,
                               "browser find is unavailable");
    return PROTON_ERR_UNSUPPORTED;
  }
  host->stop_finding(host, clear_selection);
  host->base.release((cef_base_ref_counted_t *)host);
  return PROTON_OK;
}

int32_t proton_browser_session_find_request_id(
    proton_browser_session_t *session, int32_t cef_identifier) {
  if (session != NULL && session->active_find_request_id > 0) {
    return session->active_find_request_id;
  }
  return cef_identifier;
}

void proton_browser_session_find_result(
    proton_browser_session_t *session, int32_t cef_identifier,
    int32_t count, int32_t x, int32_t y, int32_t width,
    int32_t height, int32_t active_match_ordinal, int32_t final_update) {
  if (session == NULL) {
    return;
  }
  proton_event_t *event = proton_event_create_window(
      PROTON_EVENT_BROWSER_FIND_RESULT, session->window);
  if (event != NULL) {
    event->request_id =
        proton_browser_session_find_request_id(session, cef_identifier);
    event->int_a = count;
    event->int_b = active_match_ordinal;
    event->int_c = x;
    event->int64_a = y;
    event->int64_b = width;
    event->revision = height;
    event->bool_a = final_update != 0 ? 1 : 0;
  }
  (void)proton_browser_enqueue_event(session, event);
}
