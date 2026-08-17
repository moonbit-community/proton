#include "../../proton_engine.h"
#include "../../proton_event.h"
#include "../../proton_json.h"
#include "cookie_state_lifetime.h"
#include "message.h"
#include "window_state.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_cookie_capi.h"
#include "include/capi/cef_request_context_capi.h"
#include "include/internal/cef_string.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Ref-count primitives for the cookie visitor.  Mirrors the pattern in
   scheme.c: the four macros feed ref_count.h, which is included next.
   ref_count.h references proton_engine_ref_counted_t directly, so the local
   typedef must use that exact name. */
#ifdef _WIN32
typedef struct {
  volatile LONG refs;
} proton_engine_ref_counted_t;
#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) ((refs)->refs)
#define PROTON_ENGINE_REF_STORE(refs, value) ((refs)->refs = (value))
#else
#include <stdatomic.h>
typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;
#define PROTON_ENGINE_REF_INCREMENT(refs) \
  atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) \
  (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) \
  atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#endif

#include "ref_count.h"

/* ------------------------------------------------------------------ */
/* Per-window cookie-get state                                        */
/* ------------------------------------------------------------------ */

typedef struct proton_cookie_get_state {
  proton_engine_window_t *window;
  proton_cookie_state_ref_count_t refs; /* list owner plus visitor refs */
  proton_cookie_state_detached_t detached; /* no longer visible to callers */
  int64_t request_id;
  int64_t event_window;
  int accepted;
  int completion_emitted;
  int32_t status;
  char error[256];
  char *json;               /* accumulated JSON array body                */
  size_t json_len;          /* bytes used in json                         */
  size_t json_cap;          /* allocated capacity of json                 */
  struct proton_cookie_get_state *next;
} proton_cookie_get_state_t;

static proton_cookie_get_state_t *g_cookie_get_states = NULL;
static int64_t g_next_cookie_request_id = 1;

static void proton_cookie_get_state_destroy(proton_cookie_get_state_t *state) {
  if (state == NULL) {
    return;
  }
  free(state->json);
  free(state);
}

static void proton_cookie_get_state_release(proton_cookie_get_state_t *state) {
  if (state != NULL &&
      proton_cookie_state_lifetime_release(&state->refs)) {
    proton_cookie_get_state_destroy(state);
  }
}

static proton_cookie_get_state_t *
proton_cookie_get_state_find(proton_engine_window_t *window) {
  for (proton_cookie_get_state_t *state = g_cookie_get_states;
       state != NULL; state = state->next) {
    if (state->window == window) {
      return state;
    }
  }
  return NULL;
}

static proton_cookie_get_state_t *proton_cookie_get_state_create(
    proton_engine_window_t *window) {
  if (proton_cookie_get_state_find(window) != NULL) {
    return NULL;
  }
  proton_cookie_get_state_t *state =
      (proton_cookie_get_state_t *)calloc(1, sizeof(*state));
  if (state == NULL) {
    return NULL;
  }
  proton_cookie_state_lifetime_init(&state->refs, &state->detached);
  state->window = window;
  state->request_id = g_next_cookie_request_id++;
  if (g_next_cookie_request_id <= 0) {
    g_next_cookie_request_id = 1;
  }
  state->event_window = proton_engine_window_public_id(window);
  state->status = PROTON_OK;
  state->next = g_cookie_get_states;
  g_cookie_get_states = state;
  return state;
}

static void proton_cookie_get_state_remove(proton_cookie_get_state_t *state) {
  proton_cookie_get_state_t **cursor = &g_cookie_get_states;
  while (*cursor != NULL) {
    if (*cursor == state) {
      *cursor = state->next;
      state->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void proton_cookie_get_state_fail(proton_cookie_get_state_t *state,
                                         int32_t status,
                                         const char *message) {
  if (state == NULL || state->status != PROTON_OK) {
    return;
  }
  state->status = status;
  snprintf(state->error, sizeof(state->error), "%s",
           message != NULL ? message : "cookie request failed");
}

static void proton_cookie_get_state_emit(proton_cookie_get_state_t *state) {
  if (state == NULL || state->completion_emitted) {
    return;
  }
  state->completion_emitted = 1;
  proton_event_t *event = proton_event_create(PROTON_EVENT_COOKIE_GET_COMPLETED);
  if (event != NULL) {
    event->window = state->event_window;
    event->request_id = state->request_id;
    event->int_a = state->status;
    if (state->status == PROTON_OK) {
      size_t result_len = state->json_len + 3;
      char *result = (char *)malloc(result_len);
      if (result == NULL) {
        event->int_a = PROTON_ERR_ENGINE;
        (void)proton_event_set_text(&event->text_a, "");
        (void)proton_event_set_text(&event->text_b,
                                    "failed to allocate cookie result");
      } else {
        result[0] = '[';
        if (state->json_len > 0) {
          memcpy(result + 1, state->json, state->json_len);
        }
        result[state->json_len + 1] = ']';
        result[state->json_len + 2] = '\0';
        if (!proton_event_set_text(&event->text_a, result) ||
            !proton_event_set_text(&event->text_b, "")) {
          proton_event_destroy(event);
          event = NULL;
        }
        free(result);
      }
    } else if (!proton_event_set_text(&event->text_a, "") ||
               !proton_event_set_text(&event->text_b, state->error)) {
      proton_event_destroy(event);
      event = NULL;
    }
    if (event != NULL) {
      (void)proton_event_publish(event);
    }
  }
}

static int proton_cookie_json_reserve(proton_cookie_get_state_t *state,
                                      size_t extra) {
  if (state->status != PROTON_OK) {
    return 0;
  }
  if (state->json_len + extra + 1 <= state->json_cap) {
    return 1;
  }
  size_t need = state->json_cap == 0 ? 256 : state->json_cap;
  while (need < state->json_len + extra + 1) {
    need *= 2;
  }
  char *grown = (char *)realloc(state->json, need);
  if (grown == NULL) {
    proton_cookie_get_state_fail(state, PROTON_ERR_ENGINE,
                                 "failed to allocate cookie result");
    return 0;
  }
  state->json = grown;
  state->json_cap = need;
  return 1;
}

static int proton_cookie_json_append(proton_cookie_get_state_t *state,
                                     const char *text, size_t len) {
  if (state->status != PROTON_OK) {
    return 0;
  }
  if (!proton_cookie_json_reserve(state, len)) {
    return 0;
  }
  memcpy(state->json + state->json_len, text, len);
  state->json_len += len;
  state->json[state->json_len] = '\0';
  return 1;
}

static int proton_cookie_json_append_escaped(proton_cookie_get_state_t *state,
                                             const char *value) {
  if (value == NULL) {
    return proton_cookie_json_append(state, "\"\"", 2);
  }
  if (!proton_cookie_json_append(state, "\"", 1)) {
    return 0;
  }
  for (const unsigned char *cursor = (const unsigned char *)value;
       *cursor != '\0'; cursor++) {
    char buf[7];
    const char *esc = NULL;
    switch (*cursor) {
    case '"':  esc = "\\\""; break;
    case '\\': esc = "\\\\"; break;
    case '\b': esc = "\\b";  break;
    case '\f': esc = "\\f";  break;
    case '\n': esc = "\\n";  break;
    case '\r': esc = "\\r";  break;
    case '\t': esc = "\\t";  break;
    default:
      if (*cursor < 0x20) {
        snprintf(buf, sizeof(buf), "\\u%04x", *cursor);
        esc = buf;
      }
      break;
    }
    if (esc != NULL) {
      if (!proton_cookie_json_append(state, esc, strlen(esc))) {
        return 0;
      }
    } else {
      if (!proton_cookie_json_append(state, (const char *)cursor, 1)) {
        return 0;
      }
    }
  }
  return proton_cookie_json_append(state, "\"", 1);
}

/* ------------------------------------------------------------------ */
/* CEF cookie visitor                                                 */
/* ------------------------------------------------------------------ */

typedef struct {
  cef_cookie_visitor_t visitor;
  proton_engine_ref_counted_t refs;
  proton_cookie_get_state_t *state; /* visitor-owned state reference */
} proton_cookie_visitor_impl_t;

static const char *
proton_cookie_same_site_name(cef_cookie_same_site_t same_site) {
  switch (same_site) {
  case CEF_COOKIE_SAME_SITE_NO_RESTRICTION: return "no_restriction";
  case CEF_COOKIE_SAME_SITE_LAX_MODE:       return "lax";
  case CEF_COOKIE_SAME_SITE_STRICT_MODE:    return "strict";
  default:                                  return "unspecified";
  }
}

static char *proton_cookie_cef_string_to_utf8(const cef_string_t *value) {
  if (value == NULL) {
    return NULL;
  }
  cef_string_utf8_t utf8 = {0};
  char *copy = NULL;
  if (cef_string_to_utf8(value->str, value->length, &utf8) != 0 &&
      utf8.str != NULL) {
    copy = (char *)malloc(utf8.length + 1);
    if (copy != NULL) {
      memcpy(copy, utf8.str, utf8.length);
      copy[utf8.length] = '\0';
    }
  }
  cef_string_utf8_clear(&utf8);
  return copy;
}

static int CEF_CALLBACK proton_cookie_visitor_visit(
    cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int count,
    int total, int *delete_cookie) {
  (void)total;
  if (delete_cookie != NULL) {
    *delete_cookie = 0;
  }
  if (self == NULL || cookie == NULL) {
    return 0;
  }
  proton_cookie_visitor_impl_t *impl =
      (proton_cookie_visitor_impl_t *)self;
  proton_cookie_get_state_t *state = impl->state;
  if (state == NULL ||
      proton_cookie_state_lifetime_is_detached(&state->detached)) {
    return 0;
  }
  if (state->status != PROTON_OK) {
    return 0;
  }

  char *name = proton_cookie_cef_string_to_utf8(&cookie->name);
  char *value = proton_cookie_cef_string_to_utf8(&cookie->value);
  char *domain = proton_cookie_cef_string_to_utf8(&cookie->domain);
  char *path = proton_cookie_cef_string_to_utf8(&cookie->path);

  /* Prepend a comma for every cookie after the first. */
  if (count > 0) {
    proton_cookie_json_append(state, ",", 1);
  }

  char fragment[128];
  proton_cookie_json_append(state, "{", 1);
  proton_cookie_json_append_escaped(state, "name");
  proton_cookie_json_append(state, ":", 1);
  proton_cookie_json_append_escaped(state, name);
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "value");
  proton_cookie_json_append(state, ":", 1);
  proton_cookie_json_append_escaped(state, value);
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "domain");
  proton_cookie_json_append(state, ":", 1);
  proton_cookie_json_append_escaped(state, domain);
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "path");
  proton_cookie_json_append(state, ":", 1);
  proton_cookie_json_append_escaped(state, path);
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "secure");
  proton_cookie_json_append(state, ":", 1);
  snprintf(fragment, sizeof(fragment), "%s", cookie->secure ? "true" : "false");
  proton_cookie_json_append(state, fragment, strlen(fragment));
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "http_only");
  proton_cookie_json_append(state, ":", 1);
  snprintf(fragment, sizeof(fragment), "%s", cookie->httponly ? "true" : "false");
  proton_cookie_json_append(state, fragment, strlen(fragment));
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "same_site");
  proton_cookie_json_append(state, ":", 1);
  proton_cookie_json_append_escaped(state,
                                   proton_cookie_same_site_name(cookie->same_site));
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "has_expires");
  proton_cookie_json_append(state, ":", 1);
  snprintf(fragment, sizeof(fragment), "%s", cookie->has_expires ? "true" : "false");
  proton_cookie_json_append(state, fragment, strlen(fragment));
  if (cookie->has_expires) {
    proton_cookie_json_append(state, ",", 1);
    proton_cookie_json_append_escaped(state, "expires");
    proton_cookie_json_append(state, ":", 1);
    snprintf(fragment, sizeof(fragment), "%lld",
             (long long)cookie->expires.val);
    proton_cookie_json_append(state, fragment, strlen(fragment));
  }
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "creation");
  proton_cookie_json_append(state, ":", 1);
  snprintf(fragment, sizeof(fragment), "%lld", (long long)cookie->creation.val);
  proton_cookie_json_append(state, fragment, strlen(fragment));
  proton_cookie_json_append(state, ",", 1);
  proton_cookie_json_append_escaped(state, "last_access");
  proton_cookie_json_append(state, ":", 1);
  snprintf(fragment, sizeof(fragment), "%lld",
           (long long)cookie->last_access.val);
  proton_cookie_json_append(state, fragment, strlen(fragment));
  proton_cookie_json_append(state, "}", 1);

  free(name);
  free(value);
  free(domain);
  free(path);
  return state->status == PROTON_OK; /* continue visiting */
}

static int CEF_CALLBACK
proton_cookie_visitor_release(cef_base_ref_counted_t *base) {
  if (base == NULL) {
    return 0;
  }
  proton_cookie_visitor_impl_t *impl =
      (proton_cookie_visitor_impl_t *)base;
#ifdef _WIN32
  int value = (int)InterlockedDecrement(&impl->refs.refs);
#else
  int value = (int)(atomic_fetch_sub_explicit(&impl->refs.refs, 1,
                       memory_order_acq_rel) - 1);
#endif
  if (value <= 0) {
    /* The final release is the only reliable completion signal. Cleanup may
       already have detached and removed the list-owned state reference. */
    if (impl->state != NULL) {
      proton_cookie_get_state_t *state = impl->state;
      impl->state = NULL;
      if (state->accepted &&
          !proton_cookie_state_lifetime_is_detached(&state->detached)) {
        proton_cookie_get_state_emit(state);
        proton_cookie_get_state_remove(state);
        proton_cookie_get_state_release(state); /* list owner */
      }
      proton_cookie_get_state_release(state);
    }
    free(impl);
    return 1;
  }
  /* CEF released its ref but the caller still holds one.  The visit is
     still in progress, so leave the state pending until the final release. */
  return 0;
}

static cef_cookie_visitor_t *
proton_cookie_visitor_create(proton_cookie_get_state_t *state) {
  proton_cookie_visitor_impl_t *impl =
      (proton_cookie_visitor_impl_t *)calloc(1, sizeof(*impl));
  if (impl == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&impl->visitor.base,
      sizeof(impl->visitor), &impl->refs);
  /* Override release with our custom implementation. */
  impl->visitor.base.release = proton_cookie_visitor_release;
  impl->visitor.visit = proton_cookie_visitor_visit;
  proton_cookie_state_lifetime_retain(&state->refs);
  impl->state = state;
  return &impl->visitor;
}

/* ------------------------------------------------------------------ */
/* Engine API                                                         */
/* ------------------------------------------------------------------ */

static cef_cookie_manager_t *
proton_cookie_manager_from_window(proton_engine_window_t *window,
                                  char *error, size_t error_len) {
  cef_browser_t *browser = proton_engine_window_browser(window);
  if (browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "window browser is not available");
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available");
    return NULL;
  }
  cef_request_context_t *context = host->get_request_context(host);
  if (context == NULL) {
    proton_engine_set_message(error, error_len,
                              "request context is not available");
    return NULL;
  }
  cef_cookie_manager_t *manager = context->get_cookie_manager(context, NULL);
  if (manager == NULL) {
    proton_engine_set_message(error, error_len,
                              "cookie manager is not available");
    return NULL;
  }
  return manager;
}

int32_t proton_engine_window_cookie_begin_get_json(
    proton_engine_window_t *window, const char *url_utf8,
    int32_t include_http_only, int64_t *out_request_id, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (out_request_id == NULL) {
    proton_engine_set_message(error, error_len, "out_request_id is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request_id = PROTON_INVALID_HANDLE;

  cef_cookie_manager_t *manager =
      proton_cookie_manager_from_window(window, error, error_len);
  if (manager == NULL) {
    return PROTON_ERR_ENGINE;
  }

  proton_cookie_get_state_t *state =
      proton_cookie_get_state_create(window);
  if (state == NULL) {
    manager->base.release((cef_base_ref_counted_t *)manager);
    proton_engine_set_message(error, error_len,
                              "a cookie get is already in progress");
    return PROTON_ERR_BUSY;
  }
  *out_request_id = state->request_id;

  cef_cookie_visitor_t *visitor = proton_cookie_visitor_create(state);
  if (visitor == NULL) {
    manager->base.release((cef_base_ref_counted_t *)manager);
    proton_cookie_get_state_remove(state);
    proton_cookie_state_lifetime_detach(&state->detached);
    proton_cookie_get_state_release(state);
    *out_request_id = PROTON_INVALID_HANDLE;
    proton_engine_set_message(error, error_len,
                              "failed to allocate cookie visitor");
    return PROTON_ERR_PLATFORM;
  }

  int ok;
  if (url_utf8 != NULL && url_utf8[0] != '\0') {
    cef_string_t url = {0};
    cef_string_from_utf8(url_utf8, strlen(url_utf8), &url);
    ok = manager->visit_url_cookies(manager, &url,
                                    include_http_only ? 1 : 0, visitor);
    cef_string_clear(&url);
  } else {
    ok = manager->visit_all_cookies(manager, visitor);
  }

  if (!ok) {
    visitor->base.release((cef_base_ref_counted_t *)visitor);
    manager->base.release((cef_base_ref_counted_t *)manager);
    proton_cookie_get_state_remove(state);
    proton_cookie_state_lifetime_detach(&state->detached);
    proton_cookie_get_state_release(state);
    *out_request_id = PROTON_INVALID_HANDLE;
    proton_engine_set_message(error, error_len,
                              "cookie manager rejected the visit request");
    return PROTON_ERR_ENGINE;
  }
  state->accepted = 1;
  /* CEF owns its visitor reference until traversal is complete. Dropping the
     caller reference here cannot complete the request while that CEF
     reference still exists. */
  visitor->base.release((cef_base_ref_counted_t *)visitor);
  manager->base.release((cef_base_ref_counted_t *)manager);
  return PROTON_OK;
}

int32_t proton_engine_window_cookie_set_json(
    proton_engine_window_t *window, const char *cookie_json, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (cookie_json == NULL) {
    proton_engine_set_message(error, error_len, "cookie JSON is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  proton_json_doc_t doc;
  if (!proton_json_parse(&doc, cookie_json)) {
    proton_engine_set_message(error, error_len, "failed to parse cookie JSON");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_json_value_t root;
  if (!proton_json_root_object(&doc, &root) ||
      !proton_json_is_object(&doc, root)) {
    proton_json_dispose(&doc);
    proton_engine_set_message(error, error_len,
                              "cookie JSON must be an object");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  proton_json_value_t url_val;
  proton_json_value_t name_val;
  proton_json_value_t value_val;
  proton_json_value_t domain_val;
  proton_json_value_t path_val;
  proton_json_value_t secure_val;
  proton_json_value_t http_only_val;
  proton_json_value_t same_site_val;
  bool has_url = proton_json_object_get(&doc, root, "url", &url_val);
  bool has_name = proton_json_object_get(&doc, root, "name", &name_val);
  bool has_value = proton_json_object_get(&doc, root, "value", &value_val);
  bool has_domain = proton_json_object_get(&doc, root, "domain", &domain_val);
  bool has_path = proton_json_object_get(&doc, root, "path", &path_val);
  bool has_secure = proton_json_object_get(&doc, root, "secure", &secure_val);
  bool has_http_only =
      proton_json_object_get(&doc, root, "http_only", &http_only_val);
  bool has_same_site =
      proton_json_object_get(&doc, root, "same_site", &same_site_val);

  if (!has_url || !has_name || !has_value) {
    proton_json_dispose(&doc);
    proton_engine_set_message(error, error_len,
                              "cookie JSON requires url, name, and value");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  char url_buf[1024] = {0};
  char name_buf[512] = {0};
  char value_buf[4096] = {0};
  char domain_buf[512] = {0};
  char path_buf[512] = {0};
  char same_site_buf[32] = {0};
  proton_json_read_string(&doc, url_val, url_buf, sizeof(url_buf));
  proton_json_read_string(&doc, name_val, name_buf, sizeof(name_buf));
  proton_json_read_string(&doc, value_val, value_buf, sizeof(value_buf));
  if (has_domain) {
    proton_json_read_string(&doc, domain_val, domain_buf, sizeof(domain_buf));
  }
  if (has_path) {
    proton_json_read_string(&doc, path_val, path_buf, sizeof(path_buf));
  }
  if (has_same_site) {
    proton_json_read_string(&doc, same_site_val, same_site_buf,
                            sizeof(same_site_buf));
  }
  bool secure = false;
  bool http_only = false;
  if (has_secure) {
    proton_json_read_bool(&doc, secure_val, &secure);
  }
  if (has_http_only) {
    proton_json_read_bool(&doc, http_only_val, &http_only);
  }

  cef_cookie_t cookie = {0};
  cookie.size = sizeof(cookie);
  cef_string_from_utf8(name_buf, strlen(name_buf), &cookie.name);
  cef_string_from_utf8(value_buf, strlen(value_buf), &cookie.value);
  cef_string_from_utf8(domain_buf, strlen(domain_buf), &cookie.domain);
  cef_string_from_utf8(path_buf, strlen(path_buf), &cookie.path);
  cookie.secure = secure ? 1 : 0;
  cookie.httponly = http_only ? 1 : 0;
  cookie.same_site = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
  if (has_same_site) {
    if (strcmp(same_site_buf, "no_restriction") == 0) {
      cookie.same_site = CEF_COOKIE_SAME_SITE_NO_RESTRICTION;
    } else if (strcmp(same_site_buf, "lax") == 0) {
      cookie.same_site = CEF_COOKIE_SAME_SITE_LAX_MODE;
    } else if (strcmp(same_site_buf, "strict") == 0) {
      cookie.same_site = CEF_COOKIE_SAME_SITE_STRICT_MODE;
    }
  }

  cef_string_t url = {0};
  cef_string_from_utf8(url_buf, strlen(url_buf), &url);

  proton_json_dispose(&doc);

  cef_cookie_manager_t *manager =
      proton_cookie_manager_from_window(window, error, error_len);
  if (manager == NULL) {
    cef_string_clear(&cookie.name);
    cef_string_clear(&cookie.value);
    cef_string_clear(&cookie.domain);
    cef_string_clear(&cookie.path);
    cef_string_clear(&url);
    return PROTON_ERR_ENGINE;
  }

  int ok = manager->set_cookie(manager, &url, &cookie, NULL);
  manager->base.release((cef_base_ref_counted_t *)manager);

  cef_string_clear(&cookie.name);
  cef_string_clear(&cookie.value);
  cef_string_clear(&cookie.domain);
  cef_string_clear(&cookie.path);
  cef_string_clear(&url);

  if (!ok) {
    proton_engine_set_message(error, error_len,
                              "cookie manager rejected the set request "
                              "(invalid URL or cookies unavailable)");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_cookie_delete(proton_engine_window_t *window,
                                           const char *url_utf8,
                                           const char *name_utf8,
                                           char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  cef_cookie_manager_t *manager =
      proton_cookie_manager_from_window(window, error, error_len);
  if (manager == NULL) {
    return PROTON_ERR_ENGINE;
  }

  cef_string_t url = {0};
  cef_string_t name = {0};
  if (url_utf8 != NULL && url_utf8[0] != '\0') {
    cef_string_from_utf8(url_utf8, strlen(url_utf8), &url);
  }
  if (name_utf8 != NULL && name_utf8[0] != '\0') {
    cef_string_from_utf8(name_utf8, strlen(name_utf8), &name);
  }

  int ok = manager->delete_cookies(
      manager,
      (url.str != NULL) ? &url : NULL,
      (name.str != NULL) ? &name : NULL,
      NULL);

  cef_string_clear(&url);
  cef_string_clear(&name);
  manager->base.release((cef_base_ref_counted_t *)manager);

  if (!ok) {
    proton_engine_set_message(error, error_len,
                              "cookie manager rejected the delete request");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_cookie_flush(proton_engine_window_t *window,
                                          char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_cookie_manager_t *manager =
      proton_cookie_manager_from_window(window, error, error_len);
  if (manager == NULL) {
    return PROTON_ERR_ENGINE;
  }
  /* Fire-and-forget: pass NULL callback. */
  manager->flush_store(manager, NULL);
  manager->base.release((cef_base_ref_counted_t *)manager);
  return PROTON_OK;
}

int32_t proton_engine_window_clear_cache(proton_engine_window_t *window,
                                         char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_browser_t *browser = proton_engine_window_browser(window);
  if (browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "window browser is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_request_context_t *context = host->get_request_context(host);
  if (context == NULL) {
    proton_engine_set_message(error, error_len,
                              "request context is not available");
    return PROTON_ERR_ENGINE;
  }
  /* clear_http_cache was added in CEF 144; Proton ships CEF 147. */
  context->clear_http_cache(context, NULL);
  return PROTON_OK;
}

void proton_engine_window_cookie_cleanup(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  proton_cookie_get_state_t **link = &g_cookie_get_states;
  while (*link != NULL) {
    proton_cookie_get_state_t *state = *link;
    if (state->window == window) {
      *link = state->next;
      state->next = NULL;
      state->window = NULL;
      proton_cookie_get_state_fail(state, PROTON_ERR_DESTROYED,
                                   "window closed before cookie request completed");
      if (state->accepted) {
        proton_cookie_get_state_emit(state);
      }
      proton_cookie_state_lifetime_detach(&state->detached);
      proton_cookie_get_state_release(state);
      return;
    }
    link = &state->next;
  }
}
