#include "scheme.h"

#include "include/capi/cef_callback_capi.h"
#include "include/internal/cef_string.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <stdatomic.h>
#endif

#include "../../proton_event.h"
#include "app_origin.h"
#include "strings.h"

/* scheme.c is a standalone translation unit, so it supplies the reference
   count primitives expected by ref_count.h. */
#ifdef _WIN32
typedef struct {
  volatile LONG refs;
} proton_engine_ref_counted_t;
#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) ((refs)->refs)
#define PROTON_ENGINE_REF_STORE(refs, value) ((refs)->refs = (value))
#else
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

typedef enum {
  PROTON_RESOURCE_CREATED = 0,
  PROTON_RESOURCE_PENDING = 1,
  PROTON_RESOURCE_READY = 2,
  PROTON_RESOURCE_CANCELLED = 3,
} proton_engine_resource_state_t;

typedef struct proton_engine_resource_handler {
  cef_resource_handler_t handler;
  proton_engine_ref_counted_t refs;
  int64_t request_id;
  proton_window_id_t window;
  proton_view_id_t view;
  char *url;
  char *data;
  size_t len;
  char *mime_type;
  int status;
  size_t offset;
  proton_engine_resource_state_t state;
  cef_callback_t *open_callback;
  struct proton_engine_resource_handler *next;
} proton_engine_resource_handler_t;

#ifdef _WIN32
static SRWLOCK g_resource_lock = SRWLOCK_INIT;
static volatile LONG64 g_next_resource_request_id = 0;
#else
static pthread_mutex_t g_resource_lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_int_fast64_t g_next_resource_request_id = 0;
#endif
static proton_engine_resource_handler_t *g_pending_resources = NULL;

static void proton_engine_resource_lock(void) {
#ifdef _WIN32
  AcquireSRWLockExclusive(&g_resource_lock);
#else
  (void)pthread_mutex_lock(&g_resource_lock);
#endif
}

static void proton_engine_resource_unlock(void) {
#ifdef _WIN32
  ReleaseSRWLockExclusive(&g_resource_lock);
#else
  (void)pthread_mutex_unlock(&g_resource_lock);
#endif
}

static int64_t proton_engine_next_resource_request_id(void) {
#ifdef _WIN32
  int64_t id = (int64_t)InterlockedIncrement64(&g_next_resource_request_id);
#else
  int64_t id = atomic_fetch_add_explicit(&g_next_resource_request_id, 1,
                                         memory_order_relaxed) +
               1;
#endif
  if (id > 0) {
    return id;
  }
#ifdef _WIN32
  InterlockedExchange64(&g_next_resource_request_id, 1);
#else
  atomic_store_explicit(&g_next_resource_request_id, 1,
                        memory_order_relaxed);
#endif
  return 1;
}

static int proton_engine_resource_ref_release(
    proton_engine_ref_counted_t *refs) {
#ifdef _WIN32
  return (int)InterlockedDecrement(&refs->refs);
#else
  return atomic_fetch_sub_explicit(&refs->refs, 1, memory_order_acq_rel) - 1;
#endif
}

static void proton_engine_resource_registry_add_locked(
    proton_engine_resource_handler_t *handler) {
  handler->handler.base.add_ref(&handler->handler.base);
  handler->next = g_pending_resources;
  g_pending_resources = handler;
}

static int proton_engine_resource_registry_remove_locked(
    proton_engine_resource_handler_t *handler) {
  proton_engine_resource_handler_t **cursor = &g_pending_resources;
  while (*cursor != NULL) {
    if (*cursor == handler) {
      *cursor = handler->next;
      handler->next = NULL;
      return 1;
    }
    cursor = &(*cursor)->next;
  }
  return 0;
}

static proton_engine_resource_handler_t *
proton_engine_resource_registry_take_locked(int64_t request_id) {
  proton_engine_resource_handler_t **cursor = &g_pending_resources;
  while (*cursor != NULL) {
    proton_engine_resource_handler_t *handler = *cursor;
    if (handler->request_id == request_id) {
      *cursor = handler->next;
      handler->next = NULL;
      return handler;
    }
    cursor = &handler->next;
  }
  return NULL;
}

static char *proton_engine_request_url(cef_request_t *request) {
  if (request == NULL) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(request->get_url(request));
}

static int proton_engine_resource_set_response(
    proton_engine_resource_handler_t *handler, int status,
    char *mime_type, char *data, size_t data_len) {
  if (handler == NULL || mime_type == NULL ||
      (data == NULL && data_len > 0)) {
    return 0;
  }
  handler->status = status;
  handler->mime_type = mime_type;
  handler->data = data;
  handler->len = data_len;
  handler->offset = 0;
  handler->state = PROTON_RESOURCE_READY;
  return 1;
}

static int proton_engine_resource_set_failure(
    proton_engine_resource_handler_t *handler) {
  static const char message[] = "Application resource request failed";
  char *mime_type = proton_engine_strdup("text/plain");
  char *data = (char *)malloc(sizeof(message) - 1);
  if (mime_type == NULL || data == NULL) {
    free(mime_type);
    free(data);
    return 0;
  }
  memcpy(data, message, sizeof(message) - 1);
  return proton_engine_resource_set_response(
      handler, 500, mime_type, data, sizeof(message) - 1);
}

static int proton_engine_publish_resource_request(
    proton_engine_resource_handler_t *handler) {
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_RESOURCE_REQUESTED);
  if (event == NULL ||
      !proton_event_set_text(&event->text_a, handler->url)) {
    proton_event_destroy(event);
    return 0;
  }
  event->window = handler->window;
  event->view = handler->view;
  event->request_id = handler->request_id;
  return proton_event_publish(event);
}

static void proton_engine_publish_resource_cancellation(int64_t request_id) {
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_RESOURCE_REQUEST_CANCELLED);
  if (event == NULL) {
    return;
  }
  event->request_id = request_id;
  (void)proton_event_publish(event);
}

static int CEF_CALLBACK proton_engine_resource_open(
    cef_resource_handler_t *self,
    cef_request_t *request,
    int *handle_request,
    cef_callback_t *callback) {
  (void)request;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (handler == NULL || handle_request == NULL || callback == NULL) {
    return 0;
  }

  handler->request_id = proton_engine_next_resource_request_id();
  callback->base.add_ref(&callback->base);
  proton_engine_resource_lock();
  handler->state = PROTON_RESOURCE_PENDING;
  handler->open_callback = callback;
  proton_engine_resource_registry_add_locked(handler);
  proton_engine_resource_unlock();

  *handle_request = 0;
  if (proton_engine_publish_resource_request(handler)) {
    return 1;
  }

  proton_engine_resource_lock();
  int registered = proton_engine_resource_registry_remove_locked(handler);
  cef_callback_t *continuation = handler->open_callback;
  handler->open_callback = NULL;
  int prepared = proton_engine_resource_set_failure(handler);
  proton_engine_resource_unlock();
  if (continuation != NULL) {
    if (prepared) {
      continuation->cont(continuation);
    } else {
      continuation->cancel(continuation);
    }
    continuation->base.release(&continuation->base);
  }
  if (registered) {
    handler->handler.base.release(&handler->handler.base);
  }
  return 1;
}

static void CEF_CALLBACK proton_engine_resource_get_response_headers(
    cef_resource_handler_t *self,
    cef_response_t *response,
    int64_t *response_length,
    cef_string_t *redirect_url) {
  (void)redirect_url;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (handler == NULL) {
    return;
  }
  if (response != NULL) {
    cef_string_t mime = {0};
    cef_string_t charset = {0};
    proton_engine_set_string(
        &mime, handler->mime_type != NULL ? handler->mime_type : "text/plain");
    proton_engine_set_string(&charset, "utf-8");
    response->set_status(response, handler->status);
    response->set_mime_type(response, &mime);
    response->set_charset(response, &charset);
    cef_string_clear(&mime);
    cef_string_clear(&charset);
  }
  if (response_length != NULL) {
    *response_length = (int64_t)handler->len;
  }
}

static int CEF_CALLBACK proton_engine_resource_read(
    cef_resource_handler_t *self,
    void *data_out,
    int bytes_to_read,
    int *bytes_read,
    cef_resource_read_callback_t *callback) {
  (void)callback;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (handler == NULL || data_out == NULL || bytes_read == NULL ||
      bytes_to_read <= 0) {
    return 0;
  }
  size_t remaining = handler->offset < handler->len
                         ? handler->len - handler->offset
                         : 0;
  if (remaining == 0) {
    *bytes_read = 0;
    return 0;
  }
  size_t to_copy = remaining < (size_t)bytes_to_read
                       ? remaining
                       : (size_t)bytes_to_read;
  memcpy(data_out, handler->data + handler->offset, to_copy);
  handler->offset += to_copy;
  *bytes_read = (int)to_copy;
  return 1;
}

static void CEF_CALLBACK proton_engine_resource_cancel(
    cef_resource_handler_t *self) {
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (handler == NULL) {
    return;
  }
  proton_engine_resource_lock();
  if (handler->state != PROTON_RESOURCE_PENDING) {
    proton_engine_resource_unlock();
    return;
  }
  int registered = proton_engine_resource_registry_remove_locked(handler);
  int64_t request_id = handler->request_id;
  cef_callback_t *continuation = handler->open_callback;
  handler->open_callback = NULL;
  handler->state = PROTON_RESOURCE_CANCELLED;
  proton_engine_resource_unlock();

  proton_engine_publish_resource_cancellation(request_id);
  if (continuation != NULL) {
    continuation->base.release(&continuation->base);
  }
  if (registered) {
    handler->handler.base.release(&handler->handler.base);
  }
}

static int CEF_CALLBACK proton_engine_resource_handler_release(
    cef_base_ref_counted_t *base) {
  if (base == NULL) {
    return 0;
  }
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)base;
  int value = proton_engine_resource_ref_release(&handler->refs);
  if (value <= 0) {
    free(handler->url);
    free(handler->data);
    free(handler->mime_type);
    free(handler);
    return 1;
  }
  return 0;
}

static cef_resource_handler_t *proton_engine_resource_handler_create(
    proton_window_id_t window, proton_view_id_t view, char *url) {
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)calloc(1, sizeof(*handler));
  if (handler == NULL) {
    free(url);
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&handler->handler.base,
      sizeof(handler->handler), &handler->refs);
  handler->handler.base.release = proton_engine_resource_handler_release;
  handler->window = window;
  handler->view = view;
  handler->url = url;
  handler->state = PROTON_RESOURCE_CREATED;
  handler->handler.open = proton_engine_resource_open;
  handler->handler.get_response_headers =
      proton_engine_resource_get_response_headers;
  handler->handler.read = proton_engine_resource_read;
  handler->handler.cancel = proton_engine_resource_cancel;
  return &handler->handler;
}

int32_t proton_engine_complete_resource_request(
    int64_t request_id, int32_t status, const char *mime_type,
    const void *data, size_t data_len) {
  if (request_id <= 0 || status < 100 || status > 599 || mime_type == NULL ||
      mime_type[0] == '\0' || (data == NULL && data_len > 0)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  char *mime_copy = proton_engine_strdup(mime_type);
  char *data_copy = NULL;
  if (data_len > 0) {
    data_copy = (char *)malloc(data_len);
    if (data_copy != NULL) {
      memcpy(data_copy, data, data_len);
    }
  }
  if (mime_copy == NULL || (data_len > 0 && data_copy == NULL)) {
    free(mime_copy);
    free(data_copy);
    return PROTON_ERR_ENGINE;
  }

  proton_engine_resource_lock();
  proton_engine_resource_handler_t *handler =
      proton_engine_resource_registry_take_locked(request_id);
  if (handler == NULL) {
    proton_engine_resource_unlock();
    free(mime_copy);
    free(data_copy);
    return PROTON_ERR_STALE_RESOURCE_REQUEST;
  }
  if (handler->state != PROTON_RESOURCE_PENDING) {
    proton_engine_resource_unlock();
    free(mime_copy);
    free(data_copy);
    handler->handler.base.release(&handler->handler.base);
    return PROTON_ERR_STALE_RESOURCE_REQUEST;
  }
  cef_callback_t *continuation = handler->open_callback;
  handler->open_callback = NULL;
  (void)proton_engine_resource_set_response(
      handler, status, mime_copy, data_copy, data_len);
  proton_engine_resource_unlock();

  if (continuation != NULL) {
    continuation->cont(continuation);
    continuation->base.release(&continuation->base);
  }
  handler->handler.base.release(&handler->handler.base);
  return PROTON_OK;
}

void proton_engine_cancel_resource_requests(void) {
  proton_engine_resource_lock();
  proton_engine_resource_handler_t *pending = g_pending_resources;
  g_pending_resources = NULL;
  for (proton_engine_resource_handler_t *handler = pending;
       handler != NULL; handler = handler->next) {
    handler->state = PROTON_RESOURCE_CANCELLED;
  }
  proton_engine_resource_unlock();

  while (pending != NULL) {
    proton_engine_resource_handler_t *handler = pending;
    pending = handler->next;
    handler->next = NULL;
    cef_callback_t *continuation = handler->open_callback;
    handler->open_callback = NULL;
    if (continuation != NULL) {
      continuation->cancel(continuation);
      continuation->base.release(&continuation->base);
    }
    handler->handler.base.release(&handler->handler.base);
  }
}

cef_resource_handler_t *CEF_CALLBACK proton_engine_scheme_create(
    cef_scheme_handler_factory_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    const cef_string_t *scheme_name,
    cef_request_t *request) {
  (void)self;
  (void)frame;
  (void)scheme_name;
  char *url = proton_engine_request_url(request);
  if (!proton_engine_url_is_proton(url)) {
    free(url);
    return NULL;
  }

  proton_window_id_t window_id = PROTON_INVALID_HANDLE;
  proton_view_id_t view_id = PROTON_INVALID_HANDLE;
  proton_engine_window_lock();
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  proton_engine_view_t *view =
      window == NULL ? proton_engine_window_lookup_view_browser(browser)
                     : NULL;
  if (window != NULL) {
    window_id = proton_engine_window_public_id(window);
  } else if (view != NULL) {
    window_id = proton_engine_view_window_public_id(view);
    view_id = proton_engine_view_public_id(view);
  }
  proton_engine_window_unlock();
  if (window_id == PROTON_INVALID_HANDLE) {
    free(url);
    return NULL;
  }
  return proton_engine_resource_handler_create(window_id, view_id, url);
}

void proton_engine_register_app_custom_schemes(
    cef_scheme_registrar_t *registrar) {
  if (registrar == NULL) {
    return;
  }
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  registrar->add_custom_scheme(
      registrar, &scheme,
      CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE |
          CEF_SCHEME_OPTION_CORS_ENABLED | CEF_SCHEME_OPTION_FETCH_ENABLED);
  cef_string_clear(&scheme);
}

int proton_engine_register_app_scheme_factory(
    cef_scheme_handler_factory_t *factory) {
  if (factory == NULL) {
    return 0;
  }
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  int ok = cef_register_scheme_handler_factory(&scheme, NULL, factory);
  cef_string_clear(&scheme);
  if (!ok) {
    return 0;
  }
  cef_string_t https_scheme = {0};
  cef_string_t app_domain = {0};
  proton_engine_set_string(&https_scheme, PROTON_ENGINE_APP_SCHEME);
  proton_engine_set_string(&app_domain, PROTON_ENGINE_APP_DOMAIN);
  ok = cef_register_scheme_handler_factory(&https_scheme, &app_domain,
                                           factory);
  cef_string_clear(&https_scheme);
  cef_string_clear(&app_domain);
  return ok;
}
