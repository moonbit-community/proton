#include "../../proton_engine.h"
#include "message.h"
#include "window_state.h"

#include "include/capi/cef_browser_capi.h"
#include "include/internal/cef_string.h"

#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "strings.h"

#include "ref_count.h"

/* Navigation history and inserted page styles are page-level operations, so
   both the window's main browser and a view's browser run through the helpers
   below. Chromium's transition flags are folded into the same two fields
   Electron exposes: a page-transition type and its qualifiers. */

enum {
  PROTON_PAGE_QUALIFIER_CLIENT_REDIRECT = 1 << 0,
  PROTON_PAGE_QUALIFIER_SERVER_REDIRECT = 1 << 1,
  PROTON_PAGE_QUALIFIER_FORWARD_BACK = 1 << 2,
  PROTON_PAGE_QUALIFIER_FROM_ADDRESS_BAR = 1 << 3,
};

typedef struct {
  char *data;
  size_t length;
  size_t capacity;
  bool failed;
} proton_page_text_t;

static bool proton_page_text_reserve(proton_page_text_t *text,
                                     size_t extra) {
  if (text->failed) {
    return false;
  }
  size_t required = text->length + extra + 1;
  if (required <= text->capacity) {
    return true;
  }
  size_t capacity = text->capacity == 0 ? 256 : text->capacity;
  while (capacity < required) {
    if (capacity > (size_t)INT32_MAX / 2) {
      text->failed = true;
      return false;
    }
    capacity *= 2;
  }
  char *data = (char *)realloc(text->data, capacity);
  if (data == NULL) {
    text->failed = true;
    return false;
  }
  text->data = data;
  text->capacity = capacity;
  return true;
}

static void proton_page_text_append_length(proton_page_text_t *text,
                                          const char *value, size_t length) {
  if (!proton_page_text_reserve(text, length)) {
    return;
  }
  if (length > 0 && value != NULL) {
    memcpy(text->data + text->length, value, length);
  }
  text->length += length;
  text->data[text->length] = '\0';
}

static void proton_page_text_append(proton_page_text_t *text,
                                   const char *value) {
  proton_page_text_append_length(text, value != NULL ? value : "",
                                 value != NULL ? strlen(value) : 0);
}

static void proton_page_text_append_int(proton_page_text_t *text,
                                       int64_t value) {
  char buffer[32] = {0};
  int written = snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
  if (written < 0 || (size_t)written >= sizeof(buffer)) {
    text->failed = true;
    return;
  }
  proton_page_text_append_length(text, buffer, (size_t)written);
}

/* Escapes a UTF-8 value as a JSON string literal. The payload crosses the
   private FFI as JSON, so both the navigation history and the generated page
   script need the same escaping. */
static void proton_page_text_append_json_string(proton_page_text_t *text,
                                               const char *value) {
  static const char *hex = "0123456789abcdef";
  const unsigned char *cursor =
      (const unsigned char *)(value != NULL ? value : "");
  proton_page_text_append_length(text, "\"", 1);
  for (; *cursor != '\0'; cursor++) {
    unsigned char byte = *cursor;
    switch (byte) {
    case '"':
      proton_page_text_append_length(text, "\\\"", 2);
      break;
    case '\\':
      proton_page_text_append_length(text, "\\\\", 2);
      break;
    case '\n':
      proton_page_text_append_length(text, "\\n", 2);
      break;
    case '\r':
      proton_page_text_append_length(text, "\\r", 2);
      break;
    case '\t':
      proton_page_text_append_length(text, "\\t", 2);
      break;
    case '\b':
      proton_page_text_append_length(text, "\\b", 2);
      break;
    case '\f':
      proton_page_text_append_length(text, "\\f", 2);
      break;
    default:
      if (byte < 0x20) {
        char escape[6] = {'\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0xf]};
        proton_page_text_append_length(text, escape, sizeof(escape));
      } else {
        proton_page_text_append_length(text, (const char *)cursor, 1);
      }
    }
  }
  proton_page_text_append_length(text, "\"", 1);
}

typedef struct {
  cef_navigation_entry_visitor_t visitor;
  proton_engine_ref_counted_t refs;
  proton_page_text_t text;
  int32_t active_index;
  int32_t status;
} proton_page_history_visitor_t;

/* Chromium reports no title until the document sets one, so a missing value
   becomes an empty string instead of an error. */
static char *proton_page_entry_text(cef_string_userfree_t value) {
  char *text = proton_engine_userfree_to_utf8(value);
  return text != NULL ? text : proton_engine_strdup("");
}

static int CEF_CALLBACK proton_page_history_visit(
    cef_navigation_entry_visitor_t *self, cef_navigation_entry_t *entry,
    int current, int index, int total) {
  (void)total;
  proton_page_history_visitor_t *impl =
      (proton_page_history_visitor_t *)self;
  if (impl->status != PROTON_OK || entry == NULL) {
    return 0;
  }
  int32_t transition = (int32_t)entry->get_transition_type(entry);
  int32_t qualifiers = 0;
  if ((transition & TT_CLIENT_REDIRECT_FLAG) != 0) {
    qualifiers |= PROTON_PAGE_QUALIFIER_CLIENT_REDIRECT;
  }
  if ((transition & TT_SERVER_REDIRECT_FLAG) != 0) {
    qualifiers |= PROTON_PAGE_QUALIFIER_SERVER_REDIRECT;
  }
  if ((transition & TT_FORWARD_BACK_FLAG) != 0) {
    qualifiers |= PROTON_PAGE_QUALIFIER_FORWARD_BACK;
  }
  if ((transition & TT_DIRECT_LOAD_FLAG) != 0) {
    qualifiers |= PROTON_PAGE_QUALIFIER_FROM_ADDRESS_BAR;
  }
  char *url = proton_page_entry_text(entry->get_url(entry));
  char *display_url = proton_page_entry_text(entry->get_display_url(entry));
  char *original_url = proton_page_entry_text(entry->get_original_url(entry));
  char *title = proton_page_entry_text(entry->get_title(entry));
  if (url == NULL || display_url == NULL || original_url == NULL ||
      title == NULL) {
    free(url);
    free(display_url);
    free(original_url);
    free(title);
    impl->status = PROTON_ERR_ENGINE;
    return 0;
  }
  if (index > 0) {
    proton_page_text_append(&impl->text, ",");
  }
  proton_page_text_append(&impl->text, "{\"url\":");
  proton_page_text_append_json_string(&impl->text, url);
  proton_page_text_append(&impl->text, ",\"display_url\":");
  proton_page_text_append_json_string(&impl->text, display_url);
  proton_page_text_append(&impl->text, ",\"original_url\":");
  proton_page_text_append_json_string(&impl->text, original_url);
  proton_page_text_append(&impl->text, ",\"title\":");
  proton_page_text_append_json_string(&impl->text, title);
  proton_page_text_append(&impl->text, ",\"transition\":");
  proton_page_text_append_int(&impl->text, transition & TT_SOURCE_MASK);
  proton_page_text_append(&impl->text, ",\"qualifiers\":");
  proton_page_text_append_int(&impl->text, qualifiers);
  proton_page_text_append(&impl->text, ",\"has_post_data\":");
  proton_page_text_append(&impl->text,
                          entry->has_post_data(entry) != 0 ? "true" : "false");
  proton_page_text_append(&impl->text, ",\"http_status_code\":");
  proton_page_text_append_int(&impl->text,
                              entry->get_http_status_code(entry));
  proton_page_text_append(&impl->text, "}");
  free(url);
  free(display_url);
  free(original_url);
  free(title);
  if (current != 0) {
    impl->active_index = index;
  }
  if (impl->text.failed) {
    impl->status = PROTON_ERR_ENGINE;
    return 0;
  }
  return 1;
}

static int32_t proton_page_copy_text(const proton_page_text_t *text,
                                    char *buffer, int32_t buffer_len,
                                    int32_t *out_required_len, char *error,
                                    size_t error_len) {
  if (text->failed || text->data == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to build the page payload");
    return PROTON_ERR_ENGINE;
  }
  if (text->length > (size_t)INT32_MAX) {
    proton_engine_set_message(error, error_len,
                              "page payload exceeds the supported range");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  *out_required_len = (int32_t)text->length;
  if (buffer == NULL || buffer_len <= (int32_t)text->length) {
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, text->data, text->length + 1);
  return PROTON_OK;
}

static int32_t proton_page_navigation_history_json(
    cef_browser_t *browser, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (out_required_len == NULL) {
    proton_engine_set_message(error, error_len,
                              "history output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_required_len = 0;
  if (buffer_len < 0 || (buffer_len > 0 && buffer == NULL)) {
    proton_engine_set_message(error, error_len,
                              "history buffer is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_page_history_visitor_t impl;
  memset(&impl, 0, sizeof(impl));
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&impl.visitor.base,
      sizeof(impl.visitor), &impl.refs);
  impl.visitor.visit = proton_page_history_visit;
  impl.active_index = -1;
  impl.status = PROTON_OK;
  proton_page_text_append(&impl.text, "{\"entries\":[");
  host->get_navigation_entries(host, &impl.visitor, 0);
  proton_page_text_append(&impl.text, "],\"active_index\":");
  proton_page_text_append_int(&impl.text, impl.active_index);
  proton_page_text_append(&impl.text, "}");
  host->base.release((cef_base_ref_counted_t *)host);
  int32_t status = impl.status;
  if (status == PROTON_OK) {
    status = proton_page_copy_text(&impl.text, buffer, buffer_len,
                                   out_required_len, error, error_len);
  } else {
    proton_engine_set_message(error, error_len,
                              "failed to read the navigation history");
  }
  free(impl.text.data);
  return status;
}

static int32_t proton_page_execute_script(cef_browser_t *browser,
                                         const char *script, char *error,
                                         size_t error_len) {
  if (browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = browser->get_main_frame(browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len,
                              "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t code = {0};
  cef_string_t url = {0};
  proton_engine_set_string(&code, script);
  proton_engine_set_string(&url, "proton://page-css.js");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

/* Inserted styles live in the current document only, exactly like Electron's
   insertCSS: the key identifies a style element that a later navigation drops.
   The counter is only touched on the owner thread. */
static int64_t g_page_css_next_key = 1;

static void proton_page_css_append_key(proton_page_text_t *script,
                                      int64_t key) {
  proton_page_text_append(script, "var key=\"proton-css-");
  proton_page_text_append_int(script, key);
  proton_page_text_append(script, "\";");
}

static int32_t proton_page_insert_css(cef_browser_t *browser, const char *css,
                                     int64_t *out_key, char *error,
                                     size_t error_len) {
  if (out_key == NULL || css == NULL) {
    proton_engine_set_message(error, error_len,
                              "inserted CSS needs a stylesheet and a key");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_key = 0;
  int64_t key = g_page_css_next_key++;
  proton_page_text_t script = {0};
  proton_page_text_append(&script, "(function(){");
  proton_page_css_append_key(&script, key);
  proton_page_text_append(
      &script,
      "var head=document.head||document.documentElement;if(!head){return;}"
      "var style=document.querySelector('style[data-proton-css-key=\"'+key+"
      "'\"]');if(!style){style=document.createElement(\"style\");"
      "style.setAttribute(\"data-proton-css-key\",key);head.appendChild("
      "style);}style.textContent=");
  proton_page_text_append_json_string(&script, css);
  proton_page_text_append(&script, ";})();");
  int32_t status = PROTON_OK;
  if (script.failed || script.data == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to build the style script");
    status = PROTON_ERR_ENGINE;
  } else {
    status = proton_page_execute_script(browser, script.data, error, error_len);
  }
  free(script.data);
  if (status != PROTON_OK) {
    return status;
  }
  *out_key = key;
  return PROTON_OK;
}

static int32_t proton_page_remove_css(cef_browser_t *browser, int64_t key,
                                     char *error, size_t error_len) {
  if (key <= 0) {
    proton_engine_set_message(error, error_len,
                              "inserted CSS key is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_page_text_t script = {0};
  proton_page_text_append(&script, "(function(){");
  proton_page_css_append_key(&script, key);
  proton_page_text_append(
      &script,
      "var style=document.querySelector('style[data-proton-css-key=\"'+key+"
      "'\"]');if(style&&style.parentNode){style.parentNode.removeChild("
      "style);}})();");
  int32_t status = PROTON_OK;
  if (script.failed || script.data == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to build the style script");
    status = PROTON_ERR_ENGINE;
  } else {
    status = proton_page_execute_script(browser, script.data, error, error_len);
  }
  free(script.data);
  return status;
}

int32_t proton_engine_window_navigation_history_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  return proton_page_navigation_history_json(
      proton_engine_window_browser(window), buffer, buffer_len,
      out_required_len, error, error_len);
}

int32_t proton_engine_view_navigation_history_json(
    proton_engine_view_t *view, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  return proton_page_navigation_history_json(
      proton_engine_view_browser(view), buffer, buffer_len, out_required_len,
      error, error_len);
}

int32_t proton_engine_window_insert_page_css(proton_engine_window_t *window,
                                            const char *css, int64_t *out_key,
                                            char *error, size_t error_len) {
  return proton_page_insert_css(proton_engine_window_browser(window), css,
                                out_key, error, error_len);
}

int32_t proton_engine_view_insert_page_css(proton_engine_view_t *view,
                                           const char *css, int64_t *out_key,
                                           char *error, size_t error_len) {
  return proton_page_insert_css(proton_engine_view_browser(view), css, out_key,
                                error, error_len);
}

int32_t proton_engine_window_remove_page_css(proton_engine_window_t *window,
                                             int64_t key, char *error,
                                             size_t error_len) {
  return proton_page_remove_css(proton_engine_window_browser(window), key,
                                error, error_len);
}

int32_t proton_engine_view_remove_page_css(proton_engine_view_t *view,
                                           int64_t key, char *error,
                                           size_t error_len) {
  return proton_page_remove_css(proton_engine_view_browser(view), key, error,
                                error_len);
}
