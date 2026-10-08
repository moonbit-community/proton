#include "../../proton_engine.h"
#include "../../proton_event.h"
#include "cookie_state_lifetime.h"
#include "cookie_cache.h"
#include "message.h"

#include "include/capi/cef_cookie_capi.h"
#include "include/capi/cef_request_context_capi.h"
#include "include/internal/cef_string.h"

#include <limits.h>
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

typedef struct {
  char *name;
  char *value;
  char *domain;
  char *path;
  int32_t secure;
  int32_t http_only;
  int32_t same_site;
  int32_t has_expires;
  int64_t expires;
} proton_cookie_record_t;

struct proton_cookie_snapshot {
  proton_cookie_record_t *records;
  int32_t count;
  int32_t capacity;
};

void proton_cookie_snapshot_destroy(void *raw_snapshot) {
  proton_cookie_snapshot_t *snapshot =
      (proton_cookie_snapshot_t *)raw_snapshot;
  if (snapshot == NULL) {
    return;
  }
  for (int32_t index = 0; index < snapshot->count; index++) {
    proton_cookie_record_t *record = &snapshot->records[index];
    free(record->name);
    free(record->value);
    free(record->domain);
    free(record->path);
  }
  free(snapshot->records);
  free(snapshot);
}

static int proton_cookie_snapshot_reserve(proton_cookie_snapshot_t *snapshot,
                                          int32_t capacity) {
  if (capacity <= snapshot->capacity) {
    return 1;
  }
  int32_t next_capacity = snapshot->capacity == 0 ? 8 : snapshot->capacity;
  while (next_capacity < capacity) {
    if (next_capacity > INT32_MAX / 2) {
      return 0;
    }
    next_capacity *= 2;
  }
  proton_cookie_record_t *records = (proton_cookie_record_t *)realloc(
      snapshot->records, (size_t)next_capacity * sizeof(*records));
  if (records == NULL) {
    return 0;
  }
  snapshot->records = records;
  snapshot->capacity = next_capacity;
  return 1;
}

static int proton_cookie_snapshot_append(proton_cookie_snapshot_t *snapshot,
                                         proton_cookie_record_t record) {
  if (snapshot == NULL || snapshot->count == INT32_MAX ||
      !proton_cookie_snapshot_reserve(snapshot, snapshot->count + 1)) {
    return 0;
  }
  snapshot->records[snapshot->count++] = record;
  return 1;
}

/* ------------------------------------------------------------------ */
/* Application-session cookie-get state                                        */
/* ------------------------------------------------------------------ */

typedef struct proton_cookie_get_state {
  void *runtime;
  proton_cookie_state_ref_count_t refs; /* list owner plus visitor refs */
  proton_cookie_state_detached_t detached; /* no longer visible to callers */
  int64_t request_id;
  int include_http_only;
  int accepted;
  int completion_emitted;
  int32_t status;
  char error[256];
  proton_cookie_snapshot_t *snapshot;
  struct proton_cookie_get_state *next;
} proton_cookie_get_state_t;

static proton_cookie_get_state_t *g_cookie_get_states = NULL;
static int64_t g_next_cookie_request_id = 1;

static void proton_cookie_get_state_destroy(proton_cookie_get_state_t *state) {
  if (state == NULL) {
    return;
  }
  proton_cookie_snapshot_destroy(state->snapshot);
  free(state);
}

static void proton_cookie_get_state_release(proton_cookie_get_state_t *state) {
  if (state != NULL &&
      proton_cookie_state_lifetime_release(&state->refs)) {
    proton_cookie_get_state_destroy(state);
  }
}

static proton_cookie_get_state_t *proton_cookie_get_state_create(
    void *runtime, int include_http_only) {
  proton_cookie_get_state_t *state =
      (proton_cookie_get_state_t *)calloc(1, sizeof(*state));
  if (state == NULL) {
    return NULL;
  }
  state->snapshot =
      (proton_cookie_snapshot_t *)calloc(1, sizeof(*state->snapshot));
  if (state->snapshot == NULL) {
    free(state);
    return NULL;
  }
  proton_cookie_state_lifetime_init(&state->refs, &state->detached);
  state->runtime = runtime;
  state->include_http_only = include_http_only;
  state->request_id = g_next_cookie_request_id++;
  if (g_next_cookie_request_id <= 0) {
    g_next_cookie_request_id = 1;
  }
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
    event->request_id = state->request_id;
    event->int_a = state->status;
    if (state->status == PROTON_OK) {
      if (!proton_event_set_payload(event, state->snapshot,
                                    proton_cookie_snapshot_destroy)) {
        event->int_a = PROTON_ERR_ENGINE;
        proton_cookie_snapshot_destroy(state->snapshot);
        state->snapshot = NULL;
        (void)proton_event_set_text(&event->text_a, "");
        (void)proton_event_set_text(&event->text_b,
                                    "failed to allocate cookie result");
      } else {
        state->snapshot = NULL;
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

/* ------------------------------------------------------------------ */
/* CEF cookie visitor                                                 */
/* ------------------------------------------------------------------ */

typedef struct {
  cef_cookie_visitor_t visitor;
  proton_engine_ref_counted_t refs;
  proton_cookie_get_state_t *state; /* visitor-owned state reference */
} proton_cookie_visitor_impl_t;

static char *proton_cookie_cef_string_to_utf8(const cef_string_t *value) {
  if (value == NULL) {
    return NULL;
  }
  cef_string_utf8_t utf8 = {0};
  char *copy = NULL;
  if (cef_string_to_utf8(value->str, value->length, &utf8) != 0) {
    copy = (char *)malloc(utf8.length + 1);
    if (copy != NULL && (utf8.length == 0 || utf8.str != NULL)) {
      if (utf8.length > 0) {
        memcpy(copy, utf8.str, utf8.length);
      }
      copy[utf8.length] = '\0';
    } else {
      free(copy);
      copy = NULL;
    }
  }
  cef_string_utf8_clear(&utf8);
  return copy;
}

static int CEF_CALLBACK proton_cookie_visitor_visit(
    cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int count,
    int total, int *delete_cookie) {
  (void)count;
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
  if (!state->include_http_only && cookie->httponly != 0) {
    return 1;
  }

  char *name = proton_cookie_cef_string_to_utf8(&cookie->name);
  char *value = proton_cookie_cef_string_to_utf8(&cookie->value);
  char *domain = proton_cookie_cef_string_to_utf8(&cookie->domain);
  char *path = proton_cookie_cef_string_to_utf8(&cookie->path);

  proton_cookie_record_t record = {
      .name = name,
      .value = value,
      .domain = domain,
      .path = path,
      .secure = cookie->secure != 0,
      .http_only = cookie->httponly != 0,
      .same_site = (int32_t)cookie->same_site,
      .has_expires = cookie->has_expires != 0,
      .expires = cookie->expires.val,
  };
  if (name == NULL || value == NULL || domain == NULL || path == NULL ||
      !proton_cookie_snapshot_append(state->snapshot, record)) {
    free(name);
    free(value);
    free(domain);
    free(path);
    proton_cookie_get_state_fail(state, PROTON_ERR_ENGINE,
                                 "failed to allocate cookie result");
  }
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

static const proton_cookie_record_t *proton_cookie_snapshot_record(
    const proton_cookie_snapshot_t *snapshot, int32_t index) {
  return snapshot != NULL && index >= 0 && index < snapshot->count
             ? &snapshot->records[index]
             : NULL;
}

int32_t proton_cookie_snapshot_count(const proton_cookie_snapshot_t *snapshot,
                                     int32_t *out_count) {
  if (snapshot == NULL || out_count == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_count = snapshot->count;
  return PROTON_OK;
}

int32_t proton_cookie_snapshot_copy_string_field(
    const proton_cookie_snapshot_t *snapshot, int32_t index, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len) {
  const proton_cookie_record_t *record =
      proton_cookie_snapshot_record(snapshot, index);
  if (record == NULL || out_required_len == NULL || buffer_len < 0 ||
      (buffer == NULL && buffer_len != 0)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  const char *value = NULL;
  switch (field) {
  case 0: value = record->name; break;
  case 1: value = record->value; break;
  case 2: value = record->domain; break;
  case 3: value = record->path; break;
  default: return PROTON_ERR_INVALID_ARGUMENT;
  }
  size_t length = strlen(value != NULL ? value : "");
  if (length > INT32_MAX) {
    return PROTON_ERR_ENGINE;
  }
  *out_required_len = (int32_t)length;
  if (buffer == NULL || buffer_len <= (int32_t)length) {
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, value != NULL ? value : "", length + 1);
  return PROTON_OK;
}

int32_t proton_cookie_snapshot_int_field(const proton_cookie_snapshot_t *snapshot,
                                         int32_t index, int32_t field,
                                         int32_t *out_value) {
  const proton_cookie_record_t *record =
      proton_cookie_snapshot_record(snapshot, index);
  if (record == NULL || out_value == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  switch (field) {
  case 0: *out_value = record->secure; break;
  case 1: *out_value = record->http_only; break;
  case 2: *out_value = record->same_site; break;
  case 3: *out_value = record->has_expires; break;
  default: return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

int32_t proton_cookie_snapshot_int64_field(
    const proton_cookie_snapshot_t *snapshot, int32_t index, int32_t field,
    int64_t *out_value, int32_t *out_present) {
  const proton_cookie_record_t *record =
      proton_cookie_snapshot_record(snapshot, index);
  if (record == NULL || out_value == NULL || out_present == NULL || field != 0) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_value = record->expires;
  *out_present = record->has_expires;
  return PROTON_OK;
}

/* ------------------------------------------------------------------ */
/* Engine API                                                         */
/* ------------------------------------------------------------------ */

/* All Proton browsers use CEF's global request context. Acquire an owned
   reference for each operation; no browser or platform window is required. */
static cef_cookie_manager_t *
proton_session_cookie_manager(char *error, size_t error_len) {
  cef_request_context_t *context = cef_request_context_get_global_context();
  if (context == NULL) {
    proton_engine_set_message(error, error_len, "request context is not available");
    return NULL;
  }
  cef_cookie_manager_t *manager = context->get_cookie_manager(context, NULL);
  context->base.base.release((cef_base_ref_counted_t *)context);
  if (manager == NULL) {
    proton_engine_set_message(error, error_len, "cookie manager is not available");
  }
  return manager;
}

int32_t proton_engine_session_cookie_begin_get(
    void *runtime, const char *url_utf8,
    int32_t include_http_only, int64_t *out_request_id, char *error,
    size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (out_request_id == NULL) {
    proton_engine_set_message(error, error_len, "out_request_id is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request_id = PROTON_INVALID_HANDLE;

  cef_cookie_manager_t *manager =
      proton_session_cookie_manager(error, error_len);
  if (manager == NULL) {
    return PROTON_ERR_ENGINE;
  }

  proton_cookie_get_state_t *state =
      proton_cookie_get_state_create(runtime, include_http_only != 0);
  if (state == NULL) {
    manager->base.release((cef_base_ref_counted_t *)manager);
    proton_engine_set_message(error, error_len,
                              "failed to allocate cookie request");
    return PROTON_ERR_PLATFORM;
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

  // CEF consumes one visitor reference at the C ABI boundary. Keep a local
  // reference until acceptance is recorded, including synchronous rejection.
  visitor->base.add_ref((cef_base_ref_counted_t *)visitor);
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

int32_t proton_engine_session_cookie_set(
    void *runtime, const char *url_utf8,
    const char *name_utf8, const char *value_utf8,
    const char *domain_utf8, const char *path_utf8,
    int32_t secure, int32_t http_only, int32_t same_site,
    char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (url_utf8 == NULL || name_utf8 == NULL || value_utf8 == NULL ||
      domain_utf8 == NULL || path_utf8 == NULL) {
    proton_engine_set_message(error, error_len,
                              "cookie strings are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((secure != 0 && secure != 1) ||
      (http_only != 0 && http_only != 1) ||
      same_site < 0 || same_site > 3) {
    proton_engine_set_message(error, error_len, "invalid cookie flags");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  cef_cookie_t cookie = {0};
  cookie.size = sizeof(cookie);
  cef_string_from_utf8(name_utf8, strlen(name_utf8), &cookie.name);
  cef_string_from_utf8(value_utf8, strlen(value_utf8), &cookie.value);
  cef_string_from_utf8(domain_utf8, strlen(domain_utf8), &cookie.domain);
  cef_string_from_utf8(path_utf8, strlen(path_utf8), &cookie.path);
  cookie.secure = secure ? 1 : 0;
  cookie.httponly = http_only ? 1 : 0;
  switch (same_site) {
  case 1:
    cookie.same_site = CEF_COOKIE_SAME_SITE_NO_RESTRICTION;
    break;
  case 2:
    cookie.same_site = CEF_COOKIE_SAME_SITE_LAX_MODE;
    break;
  case 3:
    cookie.same_site = CEF_COOKIE_SAME_SITE_STRICT_MODE;
    break;
  default:
    cookie.same_site = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
    break;
  }

  cef_string_t url = {0};
  cef_string_from_utf8(url_utf8, strlen(url_utf8), &url);

  cef_cookie_manager_t *manager =
      proton_session_cookie_manager(error, error_len);
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

int32_t proton_engine_session_cookie_delete(void *runtime,
                                           const char *url_utf8,
                                           const char *name_utf8,
                                           char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  cef_cookie_manager_t *manager =
      proton_session_cookie_manager(error, error_len);
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

int32_t proton_engine_session_cookie_flush(void *runtime,
                                          char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_cookie_manager_t *manager =
      proton_session_cookie_manager(error, error_len);
  if (manager == NULL) {
    return PROTON_ERR_ENGINE;
  }
  /* Fire-and-forget: pass NULL callback. */
  manager->flush_store(manager, NULL);
  manager->base.release((cef_base_ref_counted_t *)manager);
  return PROTON_OK;
}

/* CEF 150 binds OnComplete unconditionally for cache/auth/connection
   cleanup, despite documenting a nullable callback. This process-lifetime
   no-op keeps one reference; each call transfers an additional ref to CEF. */
static void CEF_CALLBACK proton_session_cleanup_completed(
    cef_completion_callback_t *self) {
  (void)self;
}

static cef_completion_callback_t *proton_session_cleanup_callback(void) {
  static struct {
    cef_completion_callback_t callback;
    proton_engine_ref_counted_t refs;
  } completion;
  /* Session entry points run on the runtime's owner (CEF UI) thread. */
  if (completion.callback.base.size == 0) {
    proton_engine_init_ref_counted(&completion.callback.base,
                                   sizeof(completion.callback), &completion.refs);
    completion.callback.on_complete = proton_session_cleanup_completed;
  }
  completion.callback.base.add_ref(&completion.callback.base);
  return &completion.callback;
}

int32_t proton_engine_session_clear_cache(void *runtime,
                                         char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_request_context_t *context = cef_request_context_get_global_context();
  if (context == NULL) {
    proton_engine_set_message(error, error_len,
                              "request context is not available");
    return PROTON_ERR_ENGINE;
  }
  context->clear_http_cache(context, proton_session_cleanup_callback());
  context->base.base.release((cef_base_ref_counted_t *)context);
  return PROTON_OK;
}

int32_t proton_engine_session_clear_certificate_exceptions(
    void *runtime, char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_request_context_t *context = cef_request_context_get_global_context();
  if (context == NULL) {
    proton_engine_set_message(error, error_len, "request context is not available");
    return PROTON_ERR_ENGINE;
  }
  context->clear_certificate_exceptions(context, NULL);
  context->base.base.release((cef_base_ref_counted_t *)context);
  return PROTON_OK;
}

int32_t proton_engine_session_clear_auth_cache(void *runtime,
                                              char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_request_context_t *context = cef_request_context_get_global_context();
  if (context == NULL) {
    proton_engine_set_message(error, error_len, "request context is not available");
    return PROTON_ERR_ENGINE;
  }
  context->clear_http_auth_credentials(context, proton_session_cleanup_callback());
  context->base.base.release((cef_base_ref_counted_t *)context);
  return PROTON_OK;
}

int32_t proton_engine_session_close_all_connections(
    void *runtime, char *error, size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  cef_request_context_t *context = cef_request_context_get_global_context();
  if (context == NULL) {
    proton_engine_set_message(error, error_len, "request context is not available");
    return PROTON_ERR_ENGINE;
  }
  context->close_all_connections(context, proton_session_cleanup_callback());
  context->base.base.release((cef_base_ref_counted_t *)context);
  return PROTON_OK;
}

void proton_engine_session_cookie_cleanup(void *runtime) {
  if (runtime == NULL) {
    return;
  }
  proton_cookie_get_state_t **link = &g_cookie_get_states;
  while (*link != NULL) {
    proton_cookie_get_state_t *state = *link;
    if (state->runtime == runtime) {
      *link = state->next;
      state->next = NULL;
      state->runtime = NULL;
      proton_cookie_get_state_fail(state, PROTON_ERR_DESTROYED,
                                   "runtime closed before cookie request completed");
      if (state->accepted) {
        proton_cookie_get_state_emit(state);
      }
      proton_cookie_state_lifetime_detach(&state->detached);
      proton_cookie_get_state_release(state);
      continue;
    }
    link = &state->next;
  }
}
