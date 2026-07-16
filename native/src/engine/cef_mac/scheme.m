#include "scheme.h"

#include "window.h"

#include "include/internal/cef_string.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_MAX_PATH_BYTES 4096

#include "../cef_common/strings.h"

typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;

typedef struct {
  cef_resource_handler_t handler;
  proton_engine_ref_counted_t refs;
  char *data;
  char *mime;
  size_t len;
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

static void proton_engine_scheme_log_to_env(const char *env_name,
                                            const char *format,
                                            va_list args) {
  const char *path = getenv(env_name);
  if (path == NULL || path[0] == '\0') {
    return;
  }
  FILE *file = fopen(path, "ab");
  if (file == NULL) {
    return;
  }
  vfprintf(file, format, args);
  fputc('\n', file);
  fclose(file);
}

static void proton_engine_scheme_debug_log(const char *format, ...) {
  va_list args;
  va_start(args, format);
  proton_engine_scheme_log_to_env("PROTON_NATIVE_LOG", format, args);
  va_end(args);
}

static int proton_engine_scheme_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

static bool proton_engine_scheme_join_path(char *out,
                                           size_t out_len,
                                           const char *base,
                                           const char *child) {
  if (out == NULL || out_len == 0 || base == NULL || child == NULL ||
      base[0] == '\0' || child[0] == '\0') {
    return false;
  }
  const char *separator = base[strlen(base) - 1] == '/' ? "" : "/";
  int written = snprintf(out, out_len, "%s%s%s", base, separator, child);
  return written >= 0 && (size_t)written < out_len;
}

static const char *proton_engine_mime_type_for_path(const char *path) {
  const char *ext = path != NULL ? strrchr(path, '.') : NULL;
  if (ext == NULL) {
    return "application/octet-stream";
  }
  if (strcmp(ext, ".css") == 0) {
    return "text/css";
  }
  if (strcmp(ext, ".js") == 0 || strcmp(ext, ".mjs") == 0) {
    return "text/javascript";
  }
  if (strcmp(ext, ".html") == 0 || strcmp(ext, ".htm") == 0) {
    return "text/html";
  }
  if (strcmp(ext, ".json") == 0) {
    return "application/json";
  }
  if (strcmp(ext, ".svg") == 0) {
    return "image/svg+xml";
  }
  if (strcmp(ext, ".png") == 0) {
    return "image/png";
  }
  if (strcmp(ext, ".jpg") == 0 || strcmp(ext, ".jpeg") == 0) {
    return "image/jpeg";
  }
  if (strcmp(ext, ".gif") == 0) {
    return "image/gif";
  }
  if (strcmp(ext, ".webp") == 0) {
    return "image/webp";
  }
  if (strcmp(ext, ".woff") == 0) {
    return "font/woff";
  }
  if (strcmp(ext, ".woff2") == 0) {
    return "font/woff2";
  }
  if (strcmp(ext, ".ttf") == 0) {
    return "font/ttf";
  }
  if (strcmp(ext, ".otf") == 0) {
    return "font/otf";
  }
  return "application/octet-stream";
}

static bool proton_engine_relative_asset_path_is_safe(const char *path) {
  if (path == NULL || path[0] == '\0' || path[0] == '/') {
    return false;
  }
  const char *segment = path;
  for (const char *cursor = path;; cursor++) {
    char ch = *cursor;
    if (ch == '\\') {
      return false;
    }
    if (ch == '/' || ch == '\0') {
      size_t len = (size_t)(cursor - segment);
      if (len == 0 || (len == 1 && segment[0] == '.') ||
          (len == 2 && segment[0] == '.' && segment[1] == '.')) {
        return false;
      }
      if (ch == '\0') {
        return true;
      }
      segment = cursor + 1;
    }
  }
}

static int proton_engine_hex_value(char ch) {
  if (ch >= '0' && ch <= '9') {
    return ch - '0';
  }
  if (ch >= 'a' && ch <= 'f') {
    return ch - 'a' + 10;
  }
  if (ch >= 'A' && ch <= 'F') {
    return ch - 'A' + 10;
  }
  return -1;
}

static char *proton_engine_decode_relative_url_path(const char *path) {
  if (path == NULL) {
    return NULL;
  }
  size_t len = strcspn(path, "?#");
  char *decoded = (char *)malloc(len + 1);
  if (decoded == NULL) {
    return NULL;
  }
  size_t out = 0;
  for (size_t index = 0; index < len; index++) {
    if (path[index] == '%' && index + 2 < len) {
      int high = proton_engine_hex_value(path[index + 1]);
      int low = proton_engine_hex_value(path[index + 2]);
      if (high >= 0 && low >= 0) {
        decoded[out++] = (char)((high << 4) | low);
        index += 2;
        continue;
      }
    }
    decoded[out++] = path[index];
  }
  decoded[out] = '\0';
  return decoded;
}

static bool proton_engine_url_asset_relative_path(const char *base_url,
                                                  const char *url,
                                                  char **out_path) {
  if (out_path == NULL) {
    return false;
  }
  *out_path = NULL;
  if (base_url == NULL || url == NULL || strcmp(base_url, url) == 0) {
    return false;
  }
  const char *path_start = NULL;
  size_t base_len = strlen(base_url);
  if (base_len > 0 && base_url[base_len - 1] == '/') {
    if (strncmp(url, base_url, base_len) != 0) {
      return false;
    }
    path_start = url + base_len;
  } else {
    const char *slash = strrchr(base_url, '/');
    if (slash == NULL) {
      return false;
    }
    size_t prefix_len = (size_t)(slash - base_url) + 1;
    if (strncmp(url, base_url, prefix_len) != 0) {
      return false;
    }
    path_start = url + prefix_len;
  }
  char *decoded = proton_engine_decode_relative_url_path(path_start);
  if (decoded == NULL) {
    return false;
  }
  if (!proton_engine_relative_asset_path_is_safe(decoded)) {
    free(decoded);
    return false;
  }
  *out_path = decoded;
  return true;
}

static bool proton_engine_read_file_bytes(const char *path,
                                          char **out_data,
                                          size_t *out_len) {
  if (out_data == NULL || out_len == NULL) {
    return false;
  }
  *out_data = NULL;
  *out_len = 0;
  FILE *file = fopen(path, "rb");
  if (file == NULL) {
    return false;
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    return false;
  }
  long size = ftell(file);
  if (size < 0) {
    fclose(file);
    return false;
  }
  rewind(file);
  char *data = (char *)malloc((size_t)size + 1);
  if (data == NULL) {
    fclose(file);
    return false;
  }
  size_t read = fread(data, 1, (size_t)size, file);
  fclose(file);
  if (read != (size_t)size) {
    free(data);
    return false;
  }
  data[read] = '\0';
  *out_data = data;
  *out_len = read;
  return true;
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

static int CEF_CALLBACK proton_engine_resource_release(
    cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  int value =
      atomic_fetch_sub_explicit(&refs->refs, 1, memory_order_acq_rel) - 1;
  if (value <= 0) {
    proton_engine_resource_handler_t *handler =
        (proton_engine_resource_handler_t *)base;
    free(handler->data);
    free(handler->mime);
    free(handler);
    return 1;
  }
  return 0;
}

static void CEF_CALLBACK proton_engine_resource_get_response_headers(
    cef_resource_handler_t *self,
    cef_response_t *response,
    int64_t *response_length,
    cef_string_t *redirectUrl) {
  (void)redirectUrl;
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)self;
  if (response != NULL) {
    cef_string_t mime = {0};
    cef_string_t charset = {0};
    proton_engine_set_string(&mime,
                             handler->mime != NULL ? handler->mime
                                                   : "application/octet-stream");
    proton_engine_set_string(&charset, "utf-8");
    response->set_status(response, 200);
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

static cef_resource_handler_t *proton_engine_resource_handler_create(
    const char *data,
    size_t len,
    const char *mime) {
  proton_engine_resource_handler_t *handler =
      (proton_engine_resource_handler_t *)calloc(1, sizeof(*handler));
  if (handler == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&handler->handler.base,
      sizeof(handler->handler), &handler->refs);
  handler->handler.base.release = proton_engine_resource_release;
  handler->data = proton_engine_strdup_len(data, len);
  handler->mime = proton_engine_strdup(mime != NULL ? mime
                                                    : "application/octet-stream");
  if (handler->data == NULL || handler->mime == NULL) {
    free(handler->data);
    free(handler->mime);
    free(handler);
    return NULL;
  }
  handler->len = len;
  handler->handler.open = proton_engine_resource_open;
  handler->handler.get_response_headers =
      proton_engine_resource_get_response_headers;
  handler->handler.read = proton_engine_resource_read;
  handler->handler.cancel = proton_engine_resource_cancel;
  return &handler->handler;
}

static cef_resource_handler_t *proton_engine_resource_handler_for_window(
    proton_engine_window_t *window,
    const char *url) {
  size_t html_len = 0;
  const char *html_url = proton_engine_window_html_url(window);
  const char *html = proton_engine_window_html(window, &html_len);
  if (window == NULL || url == NULL || html_url == NULL) {
    return NULL;
  }
  if (strcmp(html_url, url) == 0 && html != NULL) {
    return proton_engine_resource_handler_create(html, html_len, "text/html");
  }
  const char *asset_root = proton_engine_window_asset_root(window);
  if (asset_root == NULL || asset_root[0] == '\0') {
    return NULL;
  }
  char *relative_path = NULL;
  if (!proton_engine_url_asset_relative_path(html_url, url, &relative_path)) {
    return NULL;
  }
  char path[PROTON_ENGINE_MAX_PATH_BYTES] = {0};
  bool joined = proton_engine_scheme_join_path(path, sizeof(path), asset_root,
                                               relative_path);
  const char *mime = proton_engine_mime_type_for_path(relative_path);
  free(relative_path);
  if (!joined) {
    return NULL;
  }
  char *data = NULL;
  size_t len = 0;
  if (!proton_engine_read_file_bytes(path, &data, &len)) {
    return NULL;
  }
  cef_resource_handler_t *handler =
      proton_engine_resource_handler_create(data, len, mime);
  free(data);
  return handler;
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
  char *url = NULL;
  if (request != NULL) {
    url = proton_engine_userfree_to_utf8(request->get_url(request));
  }
  proton_engine_window_t *window =
      proton_engine_window_lookup_browser(browser);
  cef_resource_handler_t *handler =
      proton_engine_resource_handler_for_window(window, url);
  if (handler == NULL) {
    proton_engine_scheme_debug_log("scheme_create miss browser=%d url=%s",
                                   proton_engine_scheme_browser_id(browser),
                                   url != NULL ? url : "");
    free(url);
    return NULL;
  }
  proton_engine_scheme_debug_log("scheme_create browser=%d url=%s handler=1",
                                 proton_engine_scheme_browser_id(browser),
                                 url != NULL ? url : "");
  free(url);
  return handler;
}
