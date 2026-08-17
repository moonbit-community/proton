#include "browser_session.h"

#include "../../proton_json.h"
#include "../../proton_event.h"

#include "include/capi/cef_download_item_capi.h"
#include "include/internal/cef_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef CRITICAL_SECTION proton_browser_mutex_t;

static int proton_browser_mutex_init(proton_browser_mutex_t *mutex) {
  InitializeCriticalSection(mutex);
  return 1;
}

static void proton_browser_mutex_lock(proton_browser_mutex_t *mutex) {
  EnterCriticalSection(mutex);
}

static void proton_browser_mutex_unlock(proton_browser_mutex_t *mutex) {
  LeaveCriticalSection(mutex);
}

static void proton_browser_mutex_destroy(proton_browser_mutex_t *mutex) {
  DeleteCriticalSection(mutex);
}
#else
#include <pthread.h>
typedef pthread_mutex_t proton_browser_mutex_t;

static int proton_browser_mutex_init(proton_browser_mutex_t *mutex) {
  return pthread_mutex_init(mutex, NULL) == 0;
}

static void proton_browser_mutex_lock(proton_browser_mutex_t *mutex) {
  pthread_mutex_lock(mutex);
}

static void proton_browser_mutex_unlock(proton_browser_mutex_t *mutex) {
  pthread_mutex_unlock(mutex);
}

static void proton_browser_mutex_destroy(proton_browser_mutex_t *mutex) {
  pthread_mutex_destroy(mutex);
}
#endif

#define PROTON_BROWSER_MAX_EVENTS 128

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

typedef struct proton_browser_navigation_bypass {
  char *url;
  char *method;
  struct proton_browser_navigation_bypass *next;
} proton_browser_navigation_bypass_t;

struct proton_browser_session {
  proton_browser_policy_t policy;
  proton_window_id_t window;
  uint64_t next_request_id;
  proton_event_t *events[PROTON_BROWSER_MAX_EVENTS];
  size_t event_head;
  size_t event_count;
  proton_browser_mutex_t event_lock;
  proton_browser_pending_t *pending;
  proton_browser_download_t *downloads;
  proton_browser_navigation_bypass_t *navigation_bypasses;
  proton_browser_signal_fn signal;
  void *signal_user_data;
};

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
  proton_browser_mutex_lock(&session->event_lock);
  if (session->event_count >= PROTON_BROWSER_MAX_EVENTS) {
    proton_browser_mutex_unlock(&session->event_lock);
    proton_event_destroy(event);
    return 0;
  }
  size_t index =
      (session->event_head + session->event_count) % PROTON_BROWSER_MAX_EVENTS;
  session->events[index] = event;
  session->event_count++;
  proton_browser_mutex_unlock(&session->event_lock);
  if (session->signal != NULL) {
    session->signal(session->signal_user_data);
  }
  return 1;
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
  session->signal = signal;
  session->signal_user_data = signal_user_data;
  if (!proton_browser_mutex_init(&session->event_lock)) {
    free(session);
    return NULL;
  }
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
  for (size_t i = 0; i < PROTON_BROWSER_MAX_EVENTS; i++) {
    proton_event_destroy(session->events[i]);
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
  proton_browser_mutex_destroy(&session->event_lock);
  free(session);
}

void proton_browser_session_bind_window(proton_browser_session_t *session,
                                         proton_window_id_t window) {
  if (session != NULL) {
    session->window = window;
  }
}

proton_event_t *proton_browser_session_take_event(
    proton_browser_session_t *session) {
  if (session == NULL) {
    return NULL;
  }
  proton_browser_mutex_lock(&session->event_lock);
  if (session->event_count == 0) {
    proton_browser_mutex_unlock(&session->event_lock);
    return NULL;
  }
  proton_event_t *event = session->events[session->event_head];
  session->events[session->event_head] = NULL;
  session->event_head =
      (session->event_head + 1) % PROTON_BROWSER_MAX_EVENTS;
  session->event_count--;
  proton_browser_mutex_unlock(&session->event_lock);
  return event;
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
