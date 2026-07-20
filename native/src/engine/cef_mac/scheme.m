#include "scheme.h"

#include "window.h"

#include "include/internal/cef_string.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_PATH_SEPARATOR '/'

#include "../cef_common/strings.h"
#include "../cef_common/assets.h"

typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;

typedef struct {
  cef_resource_handler_t handler;
  proton_engine_ref_counted_t refs;
  char *data;
  size_t len;
  char *mime_type;
  size_t offset;
} proton_engine_resource_handler_t;

#define PROTON_ENGINE_REF_INCREMENT(refs) \
  atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) \
  (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) \
  atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE

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
    proton_engine_set_string(&mime, handler->mime_type != NULL
                                        ? handler->mime_type
                                        : "text/html");
    response->set_status(response, 200);
    response->set_mime_type(response, &mime);
    cef_string_clear(&mime);
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
  int value = atomic_fetch_sub_explicit(&handler->refs.refs, 1,
                                        memory_order_acq_rel) -
              1;
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
    const char *mime_type) {
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
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  if (window == NULL) {
    return NULL;
  }

  char *url = proton_engine_request_url(request);
  const char *html_url = proton_engine_window_html_url(window);
  size_t html_len = 0;
  const char *html = proton_engine_window_html(window, &html_len);
  cef_resource_handler_t *handler = NULL;
  if (url != NULL && html_url != NULL && strcmp(html_url, url) == 0 &&
      html != NULL) {
    handler = proton_engine_resource_handler_create(html, html_len,
                                                    "text/html");
  } else {
    char *asset_path = proton_engine_url_to_asset_path(url);
    if (asset_path != NULL) {
      char *html_path = proton_engine_url_to_asset_path(html_url);
      char *asset_root = proton_engine_asset_path_dirname(html_path);
      if (proton_engine_asset_path_is_under_root(asset_path, asset_root)) {
        char *data = NULL;
        size_t data_len = 0;
        if (proton_engine_read_asset_file(asset_path, &data, &data_len)) {
          handler = proton_engine_resource_handler_create(
              data, data_len, proton_engine_asset_mime_type(asset_path));
          free(data);
        }
      }
      free(asset_root);
      free(html_path);
      free(asset_path);
    }
  }
  free(url);
  return handler;
}
