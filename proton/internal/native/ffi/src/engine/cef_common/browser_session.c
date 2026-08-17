#include "browser_session.h"

#include "../../proton_json.h"

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
#define PROTON_BROWSER_MAX_EVENT_BYTES 65536

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
  char *events[PROTON_BROWSER_MAX_EVENTS];
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

static int proton_browser_json_escape(const char *value, char *out,
                                      size_t out_len) {
  size_t used = 0;
  if (out == NULL || out_len == 0) {
    return 0;
  }
  for (const unsigned char *cursor =
           (const unsigned char *)(value != NULL ? value : "");
       *cursor != '\0'; cursor++) {
    const char *escape = NULL;
    char unicode[7] = {0};
    switch (*cursor) {
    case '"':
      escape = "\\\"";
      break;
    case '\\':
      escape = "\\\\";
      break;
    case '\b':
      escape = "\\b";
      break;
    case '\f':
      escape = "\\f";
      break;
    case '\n':
      escape = "\\n";
      break;
    case '\r':
      escape = "\\r";
      break;
    case '\t':
      escape = "\\t";
      break;
    default:
      if (*cursor < 0x20) {
        snprintf(unicode, sizeof(unicode), "\\u%04x", *cursor);
        escape = unicode;
      }
      break;
    }
    if (escape != NULL) {
      size_t length = strlen(escape);
      if (used + length >= out_len) {
        return 0;
      }
      memcpy(out + used, escape, length);
      used += length;
    } else {
      if (used + 1 >= out_len) {
        return 0;
      }
      out[used++] = (char)*cursor;
    }
  }
  out[used] = '\0';
  return 1;
}

static int proton_browser_enqueue_event(proton_browser_session_t *session,
                                        const char *event_json) {
  if (session == NULL || event_json == NULL ||
      strlen(event_json) >= PROTON_BROWSER_MAX_EVENT_BYTES) {
    return 0;
  }
  char *owned = proton_browser_copy_string(event_json);
  if (owned == NULL) {
    return 0;
  }
  proton_browser_mutex_lock(&session->event_lock);
  if (session->event_count >= PROTON_BROWSER_MAX_EVENTS) {
    proton_browser_mutex_unlock(&session->event_lock);
    free(owned);
    return 0;
  }
  size_t index =
      (session->event_head + session->event_count) % PROTON_BROWSER_MAX_EVENTS;
  session->events[index] = owned;
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
    free(session->events[i]);
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

int32_t proton_browser_session_poll_event_json(
    proton_browser_session_t *session, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (session == NULL || out_required_len == NULL) {
    proton_browser_set_message(error, error_len,
                               "browser session and output length are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_browser_mutex_lock(&session->event_lock);
  if (session->event_count == 0) {
    *out_required_len = 0;
    proton_browser_mutex_unlock(&session->event_lock);
    return PROTON_EVENT_NONE;
  }
  char *event = session->events[session->event_head];
  int32_t required = (int32_t)strlen(event);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    proton_browser_mutex_unlock(&session->event_lock);
    proton_browser_set_message(error, error_len,
                               "browser event buffer is too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, event, (size_t)required + 1);
  free(event);
  session->events[session->event_head] = NULL;
  session->event_head =
      (session->event_head + 1) % PROTON_BROWSER_MAX_EVENTS;
  session->event_count--;
  proton_browser_mutex_unlock(&session->event_lock);
  return PROTON_OK;
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

static int proton_browser_enqueue_request(
    proton_browser_session_t *session, proton_browser_pending_t *pending,
    const char *type, const char *extra_json) {
  char escaped_url[PROTON_BROWSER_MAX_EVENT_BYTES / 2];
  char event[PROTON_BROWSER_MAX_EVENT_BYTES];
  if (!proton_browser_json_escape(pending->url, escaped_url,
                                  sizeof(escaped_url))) {
    return 0;
  }
  int written = snprintf(
      event, sizeof(event),
      "{\"type\":\"%s\",\"window\":\"%lld\",\"request_id\":\"%llu\","
      "\"url\":\"%s\"%s%s}",
      type, (long long)session->window, (unsigned long long)pending->id,
      escaped_url, extra_json != NULL && extra_json[0] != '\0' ? "," : "",
      extra_json != NULL ? extra_json : "");
  return written > 0 && written < (int)sizeof(event) &&
         proton_browser_enqueue_event(session, event);
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
  char escaped_method[64];
  char extra[192];
  int method_valid =
      proton_browser_json_escape(method, escaped_method, sizeof(escaped_method));
  free(method);
  if (!method_valid) {
    proton_browser_pending_remove(session, pending);
    proton_browser_pending_release(pending);
    return 1;
  }
  snprintf(extra, sizeof(extra),
           "\"method\":\"%s\",\"user_gesture\":%s,\"redirect\":%s",
           escaped_method,
           user_gesture ? "true" : "false",
           is_redirect ? "true" : "false");
  if (!proton_browser_enqueue_request(
          session, pending, "browser_navigation_requested", extra)) {
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
  char extra[96];
  snprintf(extra, sizeof(extra),
           "\"disposition\":%d,\"user_gesture\":%s",
           (int)target_disposition, user_gesture ? "true" : "false");
  if (!proton_browser_enqueue_request(
          session, pending, "browser_popup_requested", extra)) {
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
  char escaped_name[4096];
  char extra[4600];
  uint32_t download_id =
      download_item != NULL && download_item->get_id != NULL
          ? download_item->get_id(download_item)
          : 0;
  int valid = proton_browser_json_escape(name, escaped_name,
                                         sizeof(escaped_name));
  free(name);
  if (valid) {
    snprintf(extra, sizeof(extra),
             "\"download_id\":%u,\"suggested_name\":\"%s\"",
             download_id, escaped_name);
  }
  if (!valid ||
      !proton_browser_enqueue_request(
          session, pending, "browser_download_requested", extra)) {
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
  char event[1024];
  int written = snprintf(
      event, sizeof(event),
      "{\"type\":\"browser_download_updated\",\"window\":\"%lld\","
      "\"download_id\":%u,\"download_state\":\"%s\",\"received_bytes\":\"%lld\","
      "\"total_bytes\":\"%lld\",\"percent\":%d}",
      (long long)session->window, id, state,
      (long long)download_item->get_received_bytes(download_item),
      (long long)download_item->get_total_bytes(download_item),
      download_item->get_percent_complete(download_item));
  if (written > 0 && written < (int)sizeof(event)) {
    (void)proton_browser_enqueue_event(session, event);
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
  char extra[64];
  snprintf(extra, sizeof(extra), "\"error\":%d", (int)cert_error);
  if (!proton_browser_enqueue_request(
          session, pending, "browser_certificate_error", extra)) {
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
  char extra[64];
  snprintf(extra, sizeof(extra), "\"permissions\":%u",
           requested_permissions);
  if (!proton_browser_enqueue_request(
          session, pending, "browser_media_permission_requested", extra)) {
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
