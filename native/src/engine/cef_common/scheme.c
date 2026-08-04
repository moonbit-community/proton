#include "scheme.h"

#include "include/internal/cef_string.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <stdatomic.h>
#endif

#include "strings.h"
#include "assets.h"

/* Each engine keeps its own reference-count primitives; this factory is a
   separate translation unit, so it selects them here rather than inheriting
   the includer's macros the way the engines do.

   The four macros below are written for ref_count.h, which always names its
   argument `refs`. That makes the `(refs)->refs` member access survive
   parameter substitution — but only for that one spelling, so nothing else
   may call them. Direct users take proton_engine_ref_release instead. */
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

/* Returns the count after the release. */
static int proton_engine_ref_release(proton_engine_ref_counted_t *refs) {
#ifdef _WIN32
  return (int)InterlockedDecrement(&refs->refs);
#else
  return atomic_fetch_sub_explicit(&refs->refs, 1, memory_order_acq_rel) - 1;
#endif
}

typedef struct {
  cef_resource_handler_t handler;
  proton_engine_ref_counted_t refs;
  char *data;
  size_t len;
  char *mime_type;
  int status;
  size_t offset;
} proton_engine_resource_handler_t;

static char *proton_engine_request_url(cef_request_t *request) {
  if (request == NULL) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(request->get_url(request));
}

static int CEF_CALLBACK proton_engine_resource_open(
    cef_resource_handler_t *self,
    cef_request_t *request,
    int *handle_request,
    cef_callback_t *callback) {
  (void)request;
  (void)callback;
  if (self == NULL || handle_request == NULL) {
    return 0;
  }
  *handle_request = 1;
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
  if (response != NULL) {
    cef_string_t mime = {0};
    cef_string_t charset = {0};
    proton_engine_set_string(&mime, handler->mime_type != NULL
                                        ? handler->mime_type
                                        : "text/html");
    /* Everything served here is produced by the framework as UTF-8. Saying so
       keeps Chromium from falling back to a locale-dependent encoding for
       documents that carry no <meta charset>. */
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
  size_t to_copy = remaining < (size_t)bytes_to_read ? remaining
                                                     : (size_t)bytes_to_read;
  memcpy(data_out, handler->data + handler->offset, to_copy);
  handler->offset += to_copy;
  *bytes_read = (int)to_copy;
  return 1;
}

static void CEF_CALLBACK proton_engine_resource_cancel(
    cef_resource_handler_t *self) {
  (void)self;
}

static int CEF_CALLBACK proton_engine_resource_handler_release(
    cef_base_ref_counted_t *base) {
  if (base == NULL) {
    return 0;
  }
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)base;
  int value = proton_engine_ref_release(&handler->refs);
  if (value <= 0) {
    free(handler->data);
    free(handler->mime_type);
    free(handler);
    return 1;
  }
  return 0;
}

static cef_resource_handler_t *proton_engine_resource_handler_create(
    const char *data,
    size_t data_len,
    const char *mime_type,
    int status) {
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)calloc(1, sizeof(*handler));
  if (handler == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&handler->handler.base,
      sizeof(handler->handler), &handler->refs);
  handler->handler.base.release = proton_engine_resource_handler_release;
  handler->data = (char *)malloc(data_len + 1);
  if (handler->data == NULL) {
    free(handler);
    return NULL;
  }
  memcpy(handler->data, data != NULL ? data : "", data_len);
  handler->data[data_len] = '\0';
  handler->len = data_len;
  handler->status = status;
  handler->mime_type = proton_engine_strdup(mime_type != NULL ? mime_type
                                                              : "text/html");
  if (handler->mime_type == NULL) {
    free(handler->data);
    free(handler);
    return NULL;
  }
  handler->handler.open = proton_engine_resource_open;
  handler->handler.get_response_headers =
      proton_engine_resource_get_response_headers;
  handler->handler.read = proton_engine_resource_read;
  handler->handler.cancel = proton_engine_resource_cancel;
  return &handler->handler;
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
  /* Runs on CEF's IO thread while the main thread may replace or free the
     window's html state. Snapshot everything needed under the window lock,
     then do the (possibly disk-bound) work unlocked. */
  proton_engine_window_lock();
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  char *html_url = NULL;
  char *asset_root = NULL;
  char *html_copy = NULL;
  size_t html_len = 0;
  const char *root_value = proton_engine_runtime_asset_root(window);
  if (root_value != NULL) {
    asset_root = proton_engine_strdup(root_value);
  }
  if (window != NULL) {
    const char *url_value = proton_engine_window_html_url(window);
    if (url_value != NULL) {
      html_url = proton_engine_strdup(url_value);
    }
    size_t len = 0;
    const char *html = proton_engine_window_html(window, &len);
    if (html != NULL) {
      html_copy = (char *)malloc(len + 1);
      if (html_copy != NULL) {
        memcpy(html_copy, html, len);
        html_copy[len] = '\0';
        html_len = len;
      }
    }
  }
  proton_engine_window_unlock();
  if (window == NULL && asset_root == NULL) {
    return NULL;
  }

  char *url = proton_engine_request_url(request);
  cef_resource_handler_t *handler = NULL;
  if (url != NULL && html_url != NULL && strcmp(html_url, url) == 0 &&
      html_copy != NULL) {
    handler = proton_engine_resource_handler_create(html_copy, html_len,
                                                    "text/html", 200);
  } else {
    char *asset_path =
        proton_engine_url_to_rooted_asset_path(url, asset_root);
    if (asset_path != NULL) {
      char *data = NULL;
      size_t data_len = 0;
      if (proton_engine_read_asset_file(asset_path, &data, &data_len)) {
        handler = proton_engine_resource_handler_create(
            data, data_len, proton_engine_asset_mime_type(asset_path), 200);
        free(data);
      }
      free(asset_path);
    }
  }
  if (handler == NULL && proton_engine_url_is_app(url)) {
    static const char not_found[] = "Not Found";
    handler = proton_engine_resource_handler_create(
        not_found, sizeof(not_found) - 1, "text/plain", 404);
  }
  free(html_url);
  free(asset_root);
  free(html_copy);
  free(url);
  return handler;
}

void proton_engine_register_app_custom_schemes(
    cef_scheme_registrar_t *registrar) {
  if (registrar == NULL) {
    return;
  }
  cef_string_t scheme = {0};
  proton_engine_set_string(&scheme, "proton");
  /* Give proton:// documents a real origin and allow CORS-mode same-origin
     resources such as @font-face to reach the custom scheme handler. */
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
  /* Scoping the https factory to the application domain leaves every other
     https origin on the network stack. */
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
