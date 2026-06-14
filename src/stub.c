#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

#include "moonbit.h"

#define LEPUS_CEF_BACKEND_NAME "cef"

typedef void *webview_t;
typedef void (*moonbit_webview_bind_callback_t)(void *seq, void *req, void *arg);

struct moonbit_webview_binding {
  char *name;
  moonbit_webview_bind_callback_t callback;
  void *arg;
  struct moonbit_webview_binding *next;
};

static char *moonbit_webview_strdup(const char *value) {
  size_t len;
  char *copy;
  if (value == NULL) {
    value = "";
  }
  len = strlen(value) + 1;
  copy = (char *)malloc(len);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, len);
  return copy;
}

static void lepus_trace(const char *message) {
  if (getenv("LEPUS_CEF_TRACE") != NULL) {
    fprintf(stderr, "[lepus-cef] %s\n", message);
    fflush(stderr);
  }
}

static int lepus_trace_enabled(void) {
  return getenv("LEPUS_CEF_TRACE") != NULL;
}

static void moonbit_webview_free_binding(
    struct moonbit_webview_binding *binding) {
  if (binding == NULL) {
    return;
  }
  free(binding->name);
  if (binding->arg != NULL) {
    moonbit_decref(binding->arg);
  }
  free(binding);
}

static moonbit_bytes_t moonbit_webview_make_cstr(const char *value) {
  moonbit_bytes_t bytes;
  size_t len;
  if (value == NULL) {
    value = "";
  }
  len = strlen(value) + 1;
  if (len > INT32_MAX) {
    abort();
  }
  bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, value, len);
  return bytes;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_webview_backend_id(void) {
  return moonbit_webview_make_cstr(LEPUS_CEF_BACKEND_NAME);
}

#if defined(_WIN32) && defined(LEPUS_CEF_ENABLED) && LEPUS_CEF_ENABLED

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"
#include "include/cef_api_hash.h"

#define LEPUS_CEF_MESSAGE_INVOKE "lepus.invoke"
#define LEPUS_CEF_MESSAGE_RESPONSE "lepus.response"
#define LEPUS_CEF_MESSAGE_CONTEXT_READY "lepus.context_ready"
#define LEPUS_CEF_MESSAGE_INSTALL_BINDING "lepus.install_binding"
#define LEPUS_CEF_DEFAULT_URL "about:blank"
#define LEPUS_CEF_CLASS_NAME L"LepusCefWindow"
#define LEPUS_WM_FLUSH_OPS (WM_APP + 51)

struct moonbit_webview_op {
  int type;
  char *value;
  int width;
  int height;
  int hint;
  void (*dispatch_cb)(webview_t, void *);
  void *dispatch_arg;
  struct moonbit_webview_op *next;
};

struct moonbit_webview {
  int debug;
  int width;
  int height;
  int terminated;
  int destroyed;
  int running;
  HWND window;
  cef_browser_t *browser;
  cef_client_t *client;
  struct moonbit_webview_binding *bindings;
  struct moonbit_webview_op *op_head;
  struct moonbit_webview_op *op_tail;
  struct moonbit_webview *next;
};

struct lepus_ref_counted {
  long refs;
};

struct lepus_client {
  cef_client_t client;
  struct lepus_ref_counted refs;
  struct moonbit_webview *webview;
  cef_life_span_handler_t life_span;
  struct lepus_ref_counted life_span_refs;
  cef_load_handler_t load;
  struct lepus_ref_counted load_refs;
};

struct lepus_app {
  cef_app_t app;
  struct lepus_ref_counted refs;
  cef_render_process_handler_t render;
  struct lepus_ref_counted render_refs;
  cef_v8_handler_t v8;
  struct lepus_ref_counted v8_refs;
};

struct lepus_dispatch_task {
  cef_task_t task;
  struct lepus_ref_counted refs;
  webview_t webview;
  void (*callback)(webview_t, void *);
  void *arg;
};

static int lepus_cef_initialized = 0;
static int lepus_cef_shutdown_registered = 0;
static HMODULE lepus_cef_module = NULL;
static struct moonbit_webview *lepus_webviews = NULL;
static struct lepus_app lepus_app_instance;

static void CEF_CALLBACK lepus_add_ref(cef_base_ref_counted_t *base) {
  struct lepus_ref_counted *refs =
      (struct lepus_ref_counted *)((char *)base + base->size);
  InterlockedIncrement(&refs->refs);
}

static int CEF_CALLBACK lepus_release(cef_base_ref_counted_t *base) {
  struct lepus_ref_counted *refs =
      (struct lepus_ref_counted *)((char *)base + base->size);
  long value = InterlockedDecrement(&refs->refs);
  if (value <= 0) {
    refs->refs = 1;
  }
  return 0;
}

static int CEF_CALLBACK lepus_has_one_ref(cef_base_ref_counted_t *base) {
  struct lepus_ref_counted *refs =
      (struct lepus_ref_counted *)((char *)base + base->size);
  return refs->refs == 1;
}

static int CEF_CALLBACK lepus_has_at_least_one_ref(
    cef_base_ref_counted_t *base) {
  struct lepus_ref_counted *refs =
      (struct lepus_ref_counted *)((char *)base + base->size);
  return refs->refs > 0;
}

static void lepus_init_base(cef_base_ref_counted_t *base, size_t size) {
  struct lepus_ref_counted *refs =
      (struct lepus_ref_counted *)((char *)base + size);
  memset(base, 0, size + sizeof(*refs));
  base->size = size;
  base->add_ref = lepus_add_ref;
  base->release = lepus_release;
  base->has_one_ref = lepus_has_one_ref;
  base->has_at_least_one_ref = lepus_has_at_least_one_ref;
  refs->refs = 1;
}

static void CEF_CALLBACK lepus_task_add_ref(cef_base_ref_counted_t *base) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)((char *)base -
                                     offsetof(struct lepus_dispatch_task, task));
  InterlockedIncrement(&task->refs.refs);
}

static int CEF_CALLBACK lepus_task_release(cef_base_ref_counted_t *base) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)((char *)base -
                                     offsetof(struct lepus_dispatch_task, task));
  long value = InterlockedDecrement(&task->refs.refs);
  if (value == 0) {
    if (task->arg != NULL) {
      moonbit_decref(task->arg);
      task->arg = NULL;
    }
    free(task);
    return 1;
  }
  return 0;
}

static int CEF_CALLBACK lepus_task_has_one_ref(cef_base_ref_counted_t *base) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)((char *)base -
                                     offsetof(struct lepus_dispatch_task, task));
  return task->refs.refs == 1;
}

static int CEF_CALLBACK lepus_task_has_at_least_one_ref(
    cef_base_ref_counted_t *base) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)((char *)base -
                                     offsetof(struct lepus_dispatch_task, task));
  return task->refs.refs > 0;
}

static void CEF_CALLBACK lepus_dispatch_task_execute(cef_task_t *raw_task) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)((char *)raw_task -
                                     offsetof(struct lepus_dispatch_task, task));
  if (task->callback != NULL) {
    task->callback(task->webview, task->arg);
    task->arg = NULL;
  }
}

static struct lepus_dispatch_task *lepus_dispatch_task_new(
    webview_t webview,
    void (*callback)(webview_t, void *),
    void *arg) {
  struct lepus_dispatch_task *task =
      (struct lepus_dispatch_task *)calloc(1, sizeof(*task));
  if (task == NULL) {
    return NULL;
  }
  task->task.base.size = sizeof(task->task);
  task->task.base.add_ref = lepus_task_add_ref;
  task->task.base.release = lepus_task_release;
  task->task.base.has_one_ref = lepus_task_has_one_ref;
  task->task.base.has_at_least_one_ref = lepus_task_has_at_least_one_ref;
  task->task.execute = lepus_dispatch_task_execute;
  task->refs.refs = 1;
  task->webview = webview;
  task->callback = callback;
  task->arg = arg;
  return task;
}

static void lepus_set_string(cef_string_t *target, const char *value) {
  if (value == NULL) {
    value = "";
  }
  cef_string_from_utf8(value, strlen(value), target);
}

static char *lepus_userfree_to_utf8(cef_string_userfree_t value) {
  cef_string_utf8_t out = {0};
  char *copy = NULL;
  if (value == NULL) {
    return moonbit_webview_strdup("");
  }
  cef_string_to_utf8(value->str, value->length, &out);
  copy = moonbit_webview_strdup(out.str);
  cef_string_utf8_clear(&out);
  cef_string_userfree_free(value);
  return copy;
}

static char *lepus_v8_to_utf8(cef_v8_value_t *value) {
  if (value == NULL || !value->is_string(value)) {
    return moonbit_webview_strdup("");
  }
  return lepus_userfree_to_utf8(value->get_string_value(value));
}

static char *lepus_list_string(cef_list_value_t *list, int index) {
  if (list == NULL || list->get_size(list) <= (size_t)index) {
    return moonbit_webview_strdup("");
  }
  return lepus_userfree_to_utf8(list->get_string(list, index));
}

static int lepus_is_data_url_safe(unsigned char value) {
  return (value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z') ||
         (value >= '0' && value <= '9') || value == '-' || value == '_' ||
         value == '.' || value == '~';
}

static char *lepus_html_data_url(const char *html) {
  static const char hex[] = "0123456789ABCDEF";
  static const char prefix[] = "data:text/html;charset=utf-8,";
  size_t prefix_len = sizeof(prefix) - 1;
  size_t len = 0;
  size_t i;
  char *url;
  char *out;
  if (html == NULL) {
    html = "";
  }
  for (i = 0; html[i] != '\0'; ++i) {
    unsigned char ch = (unsigned char)html[i];
    len += lepus_is_data_url_safe(ch) ? 1 : 3;
  }
  url = (char *)malloc(prefix_len + len + 1);
  if (url == NULL) {
    return NULL;
  }
  memcpy(url, prefix, prefix_len);
  out = url + prefix_len;
  for (i = 0; html[i] != '\0'; ++i) {
    unsigned char ch = (unsigned char)html[i];
    if (lepus_is_data_url_safe(ch)) {
      *out++ = (char)ch;
    } else {
      *out++ = '%';
      *out++ = hex[ch >> 4];
      *out++ = hex[ch & 15];
    }
  }
  *out = '\0';
  return url;
}

static char *lepus_path_join(const char *left, const char *right) {
  size_t left_len;
  size_t right_len;
  int needs_separator;
  char *out;
  if (left == NULL || left[0] == '\0') {
    return moonbit_webview_strdup(right);
  }
  if (right == NULL || right[0] == '\0') {
    return moonbit_webview_strdup(left);
  }
  left_len = strlen(left);
  right_len = strlen(right);
  needs_separator =
      left[left_len - 1] != '\\' && left[left_len - 1] != '/';
  out = (char *)malloc(left_len + (needs_separator ? 1 : 0) + right_len + 1);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, left, left_len);
  if (needs_separator) {
    out[left_len++] = '\\';
  }
  memcpy(out + left_len, right, right_len + 1);
  return out;
}

static void lepus_prepare_cef_runtime(const char *cef_root) {
  char *release_dir = NULL;
  char *dll_path = NULL;
  const char *load_path = "libcef.dll";
  DWORD flags = 0;
  DWORD error;
  if (lepus_cef_module != NULL) {
    return;
  }
  if (cef_root != NULL && cef_root[0] != '\0') {
    release_dir = lepus_path_join(cef_root, "Release");
    if (release_dir != NULL) {
      SetDllDirectoryA(release_dir);
      dll_path = lepus_path_join(release_dir, "libcef.dll");
    }
    if (dll_path != NULL) {
      load_path = dll_path;
      flags = LOAD_WITH_ALTERED_SEARCH_PATH;
    }
  }
  lepus_trace("load libcef");
  lepus_cef_module = LoadLibraryExA(load_path, NULL, flags);
  if (lepus_cef_module == NULL) {
    error = GetLastError();
    if (cef_root != NULL && cef_root[0] != '\0') {
      fprintf(stderr,
              "Lepus CEF runtime DLL could not be loaded from %s "
              "(GetLastError=%lu).\n",
              load_path, (unsigned long)error);
    } else {
      fprintf(stderr,
              "Lepus CEF runtime DLL could not be loaded "
              "(GetLastError=%lu). Set LEPUS_CEF_ROOT to a Windows CEF "
              "binary distribution or put libcef.dll on PATH.\n",
              (unsigned long)error);
    }
    fflush(stderr);
    abort();
  }
  free(release_dir);
  free(dll_path);
}

static char *lepus_temp_path_join(const char *name) {
  DWORD len = GetTempPathA(0, NULL);
  char *tmp;
  char *out;
  if (len == 0) {
    return moonbit_webview_strdup(name);
  }
  tmp = (char *)malloc(len + 1);
  if (tmp == NULL) {
    return NULL;
  }
  if (GetTempPathA(len + 1, tmp) == 0) {
    free(tmp);
    return moonbit_webview_strdup(name);
  }
  out = lepus_path_join(tmp, name);
  free(tmp);
  return out;
}

static char *lepus_cache_path_for_process(void) {
  char name[64];
  snprintf(name, sizeof(name), "lepus-cef-cache-%lu", GetCurrentProcessId());
  return lepus_temp_path_join(name);
}

static void lepus_release_browser(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static void lepus_addref_browser(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.add_ref((cef_base_ref_counted_t *)browser);
  }
}

static void lepus_webview_list_add(struct moonbit_webview *w) {
  w->next = lepus_webviews;
  lepus_webviews = w;
}

static void lepus_webview_list_remove(struct moonbit_webview *w) {
  struct moonbit_webview **cursor = &lepus_webviews;
  while (*cursor != NULL) {
    if (*cursor == w) {
      *cursor = w->next;
      w->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static struct moonbit_webview *lepus_webview_from_browser(
    cef_browser_t *browser) {
  int identifier;
  struct moonbit_webview *cursor;
  if (browser == NULL) {
    return NULL;
  }
  identifier = browser->get_identifier(browser);
  for (cursor = lepus_webviews; cursor != NULL; cursor = cursor->next) {
    if (cursor->browser != NULL &&
        cursor->browser->get_identifier(cursor->browser) == identifier) {
      return cursor;
    }
  }
  return NULL;
}

static struct moonbit_webview_binding *lepus_find_binding(
    struct moonbit_webview *w,
    const char *name) {
  struct moonbit_webview_binding *binding;
  if (w == NULL || name == NULL) {
    return NULL;
  }
  for (binding = w->bindings; binding != NULL; binding = binding->next) {
    if (strcmp(binding->name, name) == 0) {
      return binding;
    }
  }
  return NULL;
}

static void lepus_frame_execute(cef_frame_t *frame, const char *script) {
  cef_string_t code = {0};
  cef_string_t url = {0};
  if (frame == NULL || script == NULL) {
    return;
  }
  lepus_set_string(&code, script);
  lepus_set_string(&url, "lepus://native");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
}

static char *lepus_js_quote(const char *value) {
  size_t len = 3;
  const char *p;
  char *out;
  char *cursor;
  if (value == NULL) {
    value = "";
  }
  for (p = value; *p != '\0'; ++p) {
    len += (*p == '\\' || *p == '"' || *p == '\n' || *p == '\r') ? 2 : 1;
  }
  out = (char *)malloc(len);
  if (out == NULL) {
    return NULL;
  }
  cursor = out;
  *cursor++ = '"';
  for (p = value; *p != '\0'; ++p) {
    if (*p == '\\' || *p == '"') {
      *cursor++ = '\\';
      *cursor++ = *p;
    } else if (*p == '\n') {
      *cursor++ = '\\';
      *cursor++ = 'n';
    } else if (*p == '\r') {
      *cursor++ = '\\';
      *cursor++ = 'r';
    } else {
      *cursor++ = *p;
    }
  }
  *cursor++ = '"';
  *cursor = '\0';
  return out;
}

static void lepus_install_binding_script_on_frame(
    cef_frame_t *frame,
    const char *name) {
  char *quoted;
  char *script;
  size_t len;
  if (frame == NULL || name == NULL) {
    return;
  }
  lepus_trace("install binding script");
  quoted = lepus_js_quote(name);
  if (quoted == NULL) {
    return;
  }
  len = strlen(quoted) + 1400;
  script = (char *)malloc(len);
  if (script != NULL) {
    snprintf(
        script,
        len,
        "(function(){"
        "var n=%s;"
        "var native=window.__lepusNativeInvoke;"
        "if(typeof native!=='function')return;"
        "if(!window.__lepusNativePending)window.__lepusNativePending=Object.create(null);"
        "if(!window.__lepusNativeResolve){window.__lepusNativeResolve=function(id,status,result){"
        "var p=window.__lepusNativePending[id];delete window.__lepusNativePending[id];"
        "if(!p)return;try{if(status===0){p.resolve(result===''?undefined:JSON.parse(result));}"
        "else{p.reject(new Error(result===''?'native binding failed':JSON.parse(result)));}}"
        "catch(e){p.reject(e);}};}"
        "window[n]=function(){var args=Array.prototype.slice.call(arguments);"
        "return new Promise(function(resolve,reject){"
        "try{var id=native(n,JSON.stringify(args));window.__lepusNativePending[id]={resolve:resolve,reject:reject};}"
        "catch(e){reject(e);}});};"
        "})();",
        quoted);
    lepus_frame_execute(frame, script);
    free(script);
  }
  free(quoted);
}

static void lepus_install_binding_script(
    struct moonbit_webview *w,
    const char *name) {
  cef_frame_t *frame;
  cef_process_message_t *message;
  cef_list_value_t *list;
  cef_string_t message_name = {0};
  cef_string_t binding_name = {0};
  if (w == NULL || w->browser == NULL || name == NULL) {
    return;
  }
  frame = w->browser->get_main_frame(w->browser);
  if (frame == NULL) {
    return;
  }
  lepus_trace("send install binding");
  lepus_set_string(&message_name, LEPUS_CEF_MESSAGE_INSTALL_BINDING);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message != NULL) {
    list = message->get_argument_list(message);
    list->set_size(list, 1);
    lepus_set_string(&binding_name, name);
    list->set_string(list, 0, &binding_name);
    cef_string_clear(&binding_name);
    frame->send_process_message(frame, PID_RENDERER, message);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void lepus_install_all_bindings(struct moonbit_webview *w) {
  struct moonbit_webview_binding *binding;
  for (binding = w->bindings; binding != NULL; binding = binding->next) {
    lepus_install_binding_script(w, binding->name);
  }
}

static void lepus_response_script_for_browser(
    cef_browser_t *browser,
    const char *seq,
    int status,
    const char *result) {
  cef_frame_t *frame;
  char *quoted_seq;
  char *quoted_result;
  char *script;
  size_t len;
  if (browser == NULL) {
    return;
  }
  frame = browser->get_main_frame(browser);
  if (frame == NULL) {
    return;
  }
  quoted_seq = lepus_js_quote(seq);
  quoted_result = lepus_js_quote(result);
  if (quoted_seq == NULL || quoted_result == NULL) {
    free(quoted_seq);
    free(quoted_result);
    return;
  }
  len = strlen(quoted_seq) + strlen(quoted_result) + 128;
  script = (char *)malloc(len);
  if (script != NULL) {
    snprintf(
        script,
        len,
        "if(window.__lepusNativeResolve)window.__lepusNativeResolve(%s,%d,%s);",
        quoted_seq,
        status,
        quoted_result);
    lepus_frame_execute(frame, script);
    free(script);
  }
  free(quoted_seq);
  free(quoted_result);
}

static void lepus_response_script(
    struct moonbit_webview *w,
    const char *seq,
    int status,
    const char *result) {
  if (w == NULL) {
    return;
  }
  lepus_response_script_for_browser(w->browser, seq, status, result);
}

static void lepus_send_response_to_renderer(
    struct moonbit_webview *w,
    const char *seq,
    int status,
    const char *result) {
  cef_frame_t *frame;
  cef_process_message_t *message;
  cef_list_value_t *list;
  cef_string_t message_name = {0};
  cef_string_t seq_string = {0};
  cef_string_t result_string = {0};
  if (w == NULL || w->browser == NULL) {
    return;
  }
  frame = w->browser->get_main_frame(w->browser);
  if (frame == NULL) {
    return;
  }
  lepus_set_string(&message_name, LEPUS_CEF_MESSAGE_RESPONSE);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
    return;
  }
  list = message->get_argument_list(message);
  list->set_size(list, 3);
  lepus_set_string(&seq_string, seq);
  lepus_set_string(&result_string, result != NULL ? result : "");
  list->set_string(list, 0, &seq_string);
  list->set_int(list, 1, status);
  list->set_string(list, 2, &result_string);
  frame->send_process_message(frame, PID_RENDERER, message);
  cef_string_clear(&seq_string);
  cef_string_clear(&result_string);
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void lepus_queue_op(
    struct moonbit_webview *w,
    int type,
    const char *value,
    int width,
    int height,
    int hint,
    void (*dispatch_cb)(webview_t, void *),
    void *dispatch_arg) {
  struct moonbit_webview_op *op =
      (struct moonbit_webview_op *)calloc(1, sizeof(*op));
  if (op == NULL) {
    if (dispatch_arg != NULL) {
      moonbit_decref(dispatch_arg);
    }
    return;
  }
  op->type = type;
  op->value = moonbit_webview_strdup(value);
  op->width = width;
  op->height = height;
  op->hint = hint;
  op->dispatch_cb = dispatch_cb;
  op->dispatch_arg = dispatch_arg;
  if (w->op_tail == NULL) {
    w->op_head = op;
    w->op_tail = op;
  } else {
    w->op_tail->next = op;
    w->op_tail = op;
  }
}

static void lepus_apply_op(struct moonbit_webview *w, struct moonbit_webview_op *op);

static void lepus_flush_ops(struct moonbit_webview *w) {
  struct moonbit_webview_op *op = w->op_head;
  w->op_head = NULL;
  w->op_tail = NULL;
  while (op != NULL) {
    struct moonbit_webview_op *next = op->next;
    lepus_apply_op(w, op);
    free(op->value);
    free(op);
    op = next;
  }
}

static void lepus_flush_dispatch(webview_t raw, void *arg) {
  (void)arg;
  lepus_flush_ops((struct moonbit_webview *)raw);
}

static void lepus_install_bindings_dispatch(webview_t raw, void *arg) {
  (void)arg;
  lepus_trace("delayed install bindings");
  lepus_install_all_bindings((struct moonbit_webview *)raw);
}

static LRESULT CALLBACK lepus_window_proc(
    HWND hwnd,
    UINT msg,
    WPARAM wparam,
    LPARAM lparam) {
  struct moonbit_webview *w =
      (struct moonbit_webview *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
  case LEPUS_WM_FLUSH_OPS:
    if (w != NULL) {
      lepus_trace("flush ops");
      lepus_flush_ops(w);
    }
    return 0;
  case WM_SIZE:
    if (w != NULL && w->browser != NULL) {
      cef_browser_host_t *host = w->browser->get_host(w->browser);
      if (host != NULL) {
        HWND child = host->get_window_handle(host);
        if (child != NULL) {
          SetWindowPos(
              child,
              NULL,
              0,
              0,
              LOWORD(lparam),
              HIWORD(lparam),
              SWP_NOZORDER);
        }
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
    return 0;
  case WM_CLOSE:
    if (w != NULL && w->browser != NULL) {
      cef_browser_host_t *host = w->browser->get_host(w->browser);
      if (host != NULL) {
        host->close_browser(host, 0);
        host->base.release((cef_base_ref_counted_t *)host);
        return 0;
      }
    }
    break;
  case WM_DESTROY:
    if (w != NULL) {
      w->terminated = 1;
      cef_quit_message_loop();
    }
    return 0;
  default:
    break;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static void lepus_register_window_class(void) {
  static int registered = 0;
  WNDCLASSW wc;
  if (registered) {
    return;
  }
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = lepus_window_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = LEPUS_CEF_CLASS_NAME;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassW(&wc);
  registered = 1;
}

static void lepus_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  (void)self;
  (void)process_type;
  if (command_line != NULL) {
    cef_string_t switch_name = {0};
    lepus_set_string(&switch_name, "disable-gpu");
    command_line->append_switch(command_line, &switch_name);
    cef_string_clear(&switch_name);
  }
}

static cef_render_process_handler_t *CEF_CALLBACK lepus_get_render_handler(
    cef_app_t *self) {
  (void)self;
  return &lepus_app_instance.render;
}

static int CEF_CALLBACK lepus_v8_execute(
    cef_v8_handler_t *self,
    const cef_string_t *name,
    cef_v8_value_t *object,
    size_t arguments_count,
    cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval,
    cef_string_t *exception) {
  static long request_id = 0;
  cef_v8_context_t *context;
  cef_browser_t *browser;
  cef_frame_t *frame;
  cef_process_message_t *message;
  cef_list_value_t *list;
  cef_string_t message_name = {0};
  cef_string_t seq_string = {0};
  cef_string_t binding_string = {0};
  cef_string_t request_string = {0};
  char seq[64];
  char *binding_name;
  char *request_json;
  (void)self;
  (void)name;
  (void)object;
  (void)exception;
  if (arguments_count < 2) {
    *retval = cef_v8_value_create_undefined();
    return 1;
  }
  lepus_trace("v8 invoke");
  context = cef_v8_context_get_current_context();
  if (context == NULL) {
    *retval = cef_v8_value_create_undefined();
    return 1;
  }
  browser = context->get_browser(context);
  frame = context->get_frame(context);
  if (browser == NULL || frame == NULL) {
    if (browser != NULL) {
      browser->base.release((cef_base_ref_counted_t *)browser);
    }
    if (frame != NULL) {
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
    context->base.release((cef_base_ref_counted_t *)context);
    *retval = cef_v8_value_create_undefined();
    return 1;
  }
  binding_name = lepus_v8_to_utf8(arguments[0]);
  request_json = lepus_v8_to_utf8(arguments[1]);
  snprintf(seq, sizeof(seq), "cef:%ld", InterlockedIncrement(&request_id));
  lepus_set_string(&message_name, LEPUS_CEF_MESSAGE_INVOKE);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message != NULL) {
    list = message->get_argument_list(message);
    list->set_size(list, 3);
    lepus_set_string(&seq_string, seq);
    lepus_set_string(&binding_string, binding_name);
    lepus_set_string(&request_string, request_json);
    list->set_string(list, 0, &seq_string);
    list->set_string(list, 1, &binding_string);
    list->set_string(list, 2, &request_string);
    frame->send_process_message(frame, PID_BROWSER, message);
    cef_string_clear(&seq_string);
    cef_string_clear(&binding_string);
    cef_string_clear(&request_string);
  }
  free(binding_name);
  free(request_json);
  lepus_set_string(&seq_string, seq);
  *retval = cef_v8_value_create_string(&seq_string);
  cef_string_clear(&seq_string);
  frame->base.release((cef_base_ref_counted_t *)frame);
  browser->base.release((cef_base_ref_counted_t *)browser);
  context->base.release((cef_base_ref_counted_t *)context);
  return 1;
}

static void CEF_CALLBACK lepus_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  cef_v8_value_t *global;
  cef_v8_value_t *function;
  cef_frame_t *message_frame = NULL;
  cef_process_message_t *message;
  cef_string_t function_name = {0};
  cef_string_t message_name = {0};
  (void)self;
  (void)browser;
  lepus_trace("context created");
  if (context == NULL || !context->enter(context)) {
    return;
  }
  global = context->get_global(context);
  lepus_set_string(&function_name, "__lepusNativeInvoke");
  function = cef_v8_value_create_function(&function_name, &lepus_app_instance.v8);
  if (global != NULL && function != NULL) {
    global->set_value_bykey(global, &function_name, function, V8_PROPERTY_ATTRIBUTE_NONE);
  }
  {
    cef_string_t ready_code = {0};
    cef_string_t ready_url = {0};
    cef_v8_value_t *ready_result = NULL;
    cef_v8_exception_t *ready_exception = NULL;
    lepus_set_string(&ready_code, "__lepusNativeInvoke('__lepusReady','[]');");
    lepus_set_string(&ready_url, "lepus://ready");
    context->eval(context, &ready_code, &ready_url, 1, &ready_result, &ready_exception);
    cef_string_clear(&ready_code);
    cef_string_clear(&ready_url);
    if (ready_result != NULL) {
      ready_result->base.release((cef_base_ref_counted_t *)ready_result);
    }
    if (ready_exception != NULL) {
      ready_exception->base.release((cef_base_ref_counted_t *)ready_exception);
    }
  }
  if (function != NULL) {
    function->base.release((cef_base_ref_counted_t *)function);
  }
  if (global != NULL) {
    global->base.release((cef_base_ref_counted_t *)global);
  }
  message_frame = frame;
  if (message_frame == NULL && context != NULL) {
    message_frame = context->get_frame(context);
  }
  cef_string_clear(&function_name);
  context->exit(context);
  if (message_frame != NULL) {
    lepus_set_string(&message_name, LEPUS_CEF_MESSAGE_CONTEXT_READY);
    message = cef_process_message_create(&message_name);
    cef_string_clear(&message_name);
    if (message != NULL) {
      message_frame->send_process_message(message_frame, PID_BROWSER, message);
    }
    if (message_frame != frame) {
      message_frame->base.release((cef_base_ref_counted_t *)message_frame);
    }
  }
}

static int CEF_CALLBACK lepus_render_message(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  cef_string_userfree_t raw_name;
  char *message_name;
  cef_list_value_t *list;
  char *seq;
  char *result;
  char *binding_name;
  int status;
  (void)self;
  (void)frame;
  (void)source_process;
  raw_name = message->get_name(message);
  message_name = lepus_userfree_to_utf8(raw_name);
  if (strcmp(message_name, LEPUS_CEF_MESSAGE_INSTALL_BINDING) == 0) {
    lepus_trace("renderer install binding message");
    free(message_name);
    list = message->get_argument_list(message);
    binding_name = lepus_list_string(list, 0);
    if (frame != NULL) {
      lepus_install_binding_script_on_frame(frame, binding_name);
    } else if (browser != NULL) {
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      if (main_frame != NULL) {
        lepus_install_binding_script_on_frame(main_frame, binding_name);
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
    }
    free(binding_name);
    return 1;
  }
  if (strcmp(message_name, LEPUS_CEF_MESSAGE_RESPONSE) != 0) {
    free(message_name);
    return 0;
  }
  lepus_trace("renderer response message");
  free(message_name);
  list = message->get_argument_list(message);
  seq = lepus_list_string(list, 0);
  status = list->get_int(list, 1);
  result = lepus_list_string(list, 2);
  lepus_response_script_for_browser(browser, seq, status, result);
  free(seq);
  free(result);
  return 1;
}

static cef_life_span_handler_t *CEF_CALLBACK lepus_get_life_span_handler(
    cef_client_t *client) {
  struct lepus_client *owner =
      (struct lepus_client *)((char *)client - offsetof(struct lepus_client, client));
  return &owner->life_span;
}

static cef_load_handler_t *CEF_CALLBACK lepus_get_load_handler(
    cef_client_t *client) {
  struct lepus_client *owner =
      (struct lepus_client *)((char *)client - offsetof(struct lepus_client, client));
  return &owner->load;
}

static int CEF_CALLBACK lepus_client_message(
    cef_client_t *client,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  cef_string_userfree_t raw_name;
  char *message_name;
  cef_list_value_t *list;
  char *seq;
  char *binding_name;
  char *request_json;
  struct moonbit_webview *w;
  struct moonbit_webview_binding *binding;
  (void)client;
  (void)frame;
  (void)source_process;
  raw_name = message->get_name(message);
  message_name = lepus_userfree_to_utf8(raw_name);
  if (strcmp(message_name, LEPUS_CEF_MESSAGE_CONTEXT_READY) == 0) {
    free(message_name);
    lepus_trace("browser context ready");
    w = lepus_webview_from_browser(browser);
    if (w != NULL && w->running) {
      lepus_install_all_bindings(w);
    }
    return 1;
  }
  if (strcmp(message_name, LEPUS_CEF_MESSAGE_INVOKE) != 0) {
    free(message_name);
    return 0;
  }
  lepus_trace("browser invoke message");
  free(message_name);
  w = lepus_webview_from_browser(browser);
  list = message->get_argument_list(message);
  seq = lepus_list_string(list, 0);
  binding_name = lepus_list_string(list, 1);
  request_json = lepus_list_string(list, 2);
  if (lepus_trace_enabled()) {
    fprintf(stderr, "[lepus-cef] invoke binding: %s\n", binding_name);
    fflush(stderr);
  }
  if (strcmp(binding_name, "__lepusReady") == 0) {
    if (w != NULL && w->running) {
      lepus_install_all_bindings(w);
    }
    free(seq);
    free(binding_name);
    free(request_json);
    return 1;
  }
  binding = lepus_find_binding(w, binding_name);
  if (binding == NULL) {
    lepus_send_response_to_renderer(
        w,
        seq,
        1,
        "\"native binding is not registered\"");
  } else {
    binding->callback((void *)seq, (void *)request_json, binding->arg);
  }
  free(seq);
  free(binding_name);
  free(request_json);
  return 1;
}

static void CEF_CALLBACK lepus_on_after_created(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  struct lepus_client *owner =
      (struct lepus_client *)((char *)self - offsetof(struct lepus_client, life_span));
  lepus_trace("browser after created");
  owner->webview->browser = browser;
  lepus_addref_browser(browser);
  lepus_flush_ops(owner->webview);
}

static int CEF_CALLBACK lepus_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  (void)browser;
  return 0;
}

static void CEF_CALLBACK lepus_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  struct lepus_client *owner =
      (struct lepus_client *)((char *)self - offsetof(struct lepus_client, life_span));
  (void)browser;
  owner->webview->terminated = 1;
  cef_quit_message_loop();
}

static void CEF_CALLBACK lepus_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int http_status_code) {
  struct lepus_client *owner =
      (struct lepus_client *)((char *)self - offsetof(struct lepus_client, load));
  (void)browser;
  (void)http_status_code;
  if (frame != NULL && frame->is_main(frame)) {
    lepus_trace("load end");
    if (owner->webview != NULL && owner->webview->running) {
      lepus_install_all_bindings(owner->webview);
    }
  }
}

static void lepus_init_app(void) {
  static int initialized = 0;
  if (initialized) {
    return;
  }
  lepus_init_base((cef_base_ref_counted_t *)&lepus_app_instance.app.base,
                  sizeof(lepus_app_instance.app));
  lepus_app_instance.app.on_before_command_line_processing =
      lepus_on_before_command_line_processing;
  lepus_app_instance.app.get_render_process_handler = lepus_get_render_handler;
  lepus_init_base((cef_base_ref_counted_t *)&lepus_app_instance.render.base,
                  sizeof(lepus_app_instance.render));
  lepus_app_instance.render.on_context_created = lepus_on_context_created;
  lepus_app_instance.render.on_process_message_received = lepus_render_message;
  lepus_init_base((cef_base_ref_counted_t *)&lepus_app_instance.v8.base,
                  sizeof(lepus_app_instance.v8));
  lepus_app_instance.v8.execute = lepus_v8_execute;
  initialized = 1;
}

static void lepus_cef_shutdown(void) {
  if (lepus_cef_initialized) {
    cef_shutdown();
    lepus_cef_initialized = 0;
  }
}

static void lepus_ensure_cef_initialized(int debug) {
  cef_main_args_t args;
  cef_settings_t settings;
  int exit_code;
  const char *cef_root;
  char *resources_dir = NULL;
  char *locales_dir = NULL;
  char *root_cache_path = NULL;
  char *log_file = NULL;
  if (lepus_cef_initialized) {
    return;
  }
  cef_root = getenv("LEPUS_CEF_ROOT");
  lepus_prepare_cef_runtime(cef_root);
  lepus_trace("init app");
  lepus_init_app();
#ifdef CEF_API_VERSION
  (void)cef_api_hash(CEF_API_VERSION, 0);
#else
  (void)cef_api_hash(0);
#endif
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  lepus_trace("execute process");
  exit_code = cef_execute_process(&args, &lepus_app_instance.app, NULL);
  if (exit_code >= 0) {
    lepus_trace("cef child process exit");
    exit(exit_code);
  }
  memset(&settings, 0, sizeof(settings));
  settings.size = sizeof(settings);
  settings.no_sandbox = 1;
  settings.multi_threaded_message_loop = 0;
  (void)debug;
  settings.remote_debugging_port = 0;
  settings.log_severity =
      lepus_trace_enabled() ? LOGSEVERITY_DEFAULT : LOGSEVERITY_DISABLE;
  if (lepus_trace_enabled()) {
    log_file = lepus_temp_path_join("lepus-cef.log");
    if (log_file != NULL) {
      lepus_set_string(&settings.log_file, log_file);
    }
  }
  if (cef_root != NULL && cef_root[0] != '\0') {
    resources_dir = lepus_path_join(cef_root, "Resources");
    if (resources_dir != NULL) {
      locales_dir = lepus_path_join(resources_dir, "locales");
      lepus_set_string(&settings.resources_dir_path, resources_dir);
    }
    if (locales_dir != NULL) {
      lepus_set_string(&settings.locales_dir_path, locales_dir);
    }
  }
  root_cache_path = lepus_cache_path_for_process();
  if (root_cache_path != NULL) {
    CreateDirectoryA(root_cache_path, NULL);
    lepus_set_string(&settings.root_cache_path, root_cache_path);
  }
  lepus_trace("cef initialize");
  if (!cef_initialize(&args, &settings, &lepus_app_instance.app, NULL)) {
    abort();
  }
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.root_cache_path);
  cef_string_clear(&settings.log_file);
  free(resources_dir);
  free(locales_dir);
  free(root_cache_path);
  free(log_file);
  lepus_cef_initialized = 1;
  lepus_trace("cef initialized");
  if (!lepus_cef_shutdown_registered) {
    atexit(lepus_cef_shutdown);
    lepus_cef_shutdown_registered = 1;
  }
}

static struct lepus_client *lepus_client_new(struct moonbit_webview *w) {
  struct lepus_client *client =
      (struct lepus_client *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  client->webview = w;
  lepus_init_base((cef_base_ref_counted_t *)&client->client.base,
                  sizeof(client->client));
  client->client.get_life_span_handler = lepus_get_life_span_handler;
  client->client.get_load_handler = lepus_get_load_handler;
  client->client.on_process_message_received = lepus_client_message;
  lepus_init_base((cef_base_ref_counted_t *)&client->life_span.base,
                  sizeof(client->life_span));
  client->life_span.on_after_created = lepus_on_after_created;
  client->life_span.do_close = lepus_do_close;
  client->life_span.on_before_close = lepus_on_before_close;
  lepus_init_base((cef_base_ref_counted_t *)&client->load.base,
                  sizeof(client->load));
  client->load.on_load_end = lepus_on_load_end;
  return client;
}

static void lepus_create_browser(struct moonbit_webview *w) {
  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  RECT rect;
  if (w->browser != NULL) {
    return;
  }
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  GetClientRect(w->window, &rect);
  lepus_set_string(&window_info.window_name, "Lepus");
  window_info.parent_window = w->window;
  window_info.style = WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = rect.right - rect.left;
  window_info.bounds.height = rect.bottom - rect.top;
  lepus_set_string(&url, LEPUS_CEF_DEFAULT_URL);
  lepus_trace("create browser");
  w->browser = cef_browser_host_create_browser_sync(
      &window_info,
      w->client,
      &url,
      &browser_settings,
      NULL,
      NULL);
  if (w->browser != NULL) {
    lepus_install_all_bindings(w);
    lepus_flush_ops(w);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
}

MOONBIT_FFI_EXPORT int32_t moonbit_webview_backend_available(void) {
  return 1;
}

MOONBIT_FFI_EXPORT webview_t webview_create(int32_t debug, int64_t window) {
  struct moonbit_webview *w;
  DWORD style = WS_OVERLAPPEDWINDOW | WS_VISIBLE;
  (void)window;
  lepus_trace("webview create");
  lepus_ensure_cef_initialized(debug);
  lepus_register_window_class();
  w = (struct moonbit_webview *)calloc(1, sizeof(*w));
  if (w == NULL) {
    abort();
  }
  w->debug = debug;
  w->width = 800;
  w->height = 600;
  w->client = (cef_client_t *)lepus_client_new(w);
  if (w->client == NULL) {
    free(w);
    abort();
  }
  w->window = CreateWindowExW(
      0,
      LEPUS_CEF_CLASS_NAME,
      L"Lepus",
      style,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      w->width,
      w->height,
      NULL,
      NULL,
      GetModuleHandleW(NULL),
      NULL);
  if (w->window == NULL) {
    free(w->client);
    free(w);
    abort();
  }
  SetWindowLongPtrW(w->window, GWLP_USERDATA, (LONG_PTR)w);
  lepus_webview_list_add(w);
  lepus_create_browser(w);
  return w;
}

static void lepus_apply_op(
    struct moonbit_webview *w,
    struct moonbit_webview_op *op) {
  cef_frame_t *frame;
  cef_string_t value = {0};
  cef_string_t url = {0};
  (void)op->hint;
  if (w == NULL || op == NULL) {
    return;
  }
  if (!w->running && op->type >= 3 && op->type <= 7) {
    lepus_queue_op(
        w,
        op->type,
        op->value,
        op->width,
        op->height,
        op->hint,
        op->dispatch_cb,
        op->dispatch_arg);
    op->dispatch_arg = NULL;
    return;
  }
  if (w->browser == NULL && op->type != 1 && op->type != 2 && op->type != 7) {
    lepus_queue_op(
        w,
        op->type,
        op->value,
        op->width,
        op->height,
        op->hint,
        op->dispatch_cb,
        op->dispatch_arg);
    op->dispatch_arg = NULL;
    return;
  }
  switch (op->type) {
  case 1:
    lepus_trace("apply title");
    SetWindowTextA(w->window, op->value != NULL ? op->value : "");
    break;
  case 2:
    lepus_trace("apply size");
    w->width = op->width;
    w->height = op->height;
    SetWindowPos(w->window, NULL, 0, 0, op->width, op->height, SWP_NOMOVE | SWP_NOZORDER);
    break;
  case 3:
    lepus_trace("apply html");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      char *quoted_html = lepus_js_quote(op->value);
      struct lepus_dispatch_task *task;
      if (quoted_html != NULL) {
        size_t script_len = strlen(quoted_html) + 80;
        char *script = (char *)malloc(script_len);
        if (script != NULL) {
          snprintf(
              script,
              script_len,
              "document.open();document.write(%s);document.close();",
              quoted_html);
          lepus_frame_execute(frame, script);
          free(script);
        }
        free(quoted_html);
      }
      task = lepus_dispatch_task_new((webview_t)w, lepus_install_bindings_dispatch, NULL);
      if (task != NULL) {
        task->task.base.add_ref((cef_base_ref_counted_t *)&task->task);
        if (cef_post_delayed_task(TID_UI, &task->task, 500)) {
          task->task.base.release((cef_base_ref_counted_t *)&task->task);
        } else {
          task->task.base.release((cef_base_ref_counted_t *)&task->task);
          task->task.base.release((cef_base_ref_counted_t *)&task->task);
        }
      }
      frame->base.release((cef_base_ref_counted_t *)frame);
    } else {
      lepus_trace("html frame missing");
    }
    break;
  case 4:
    lepus_trace("apply navigate");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      lepus_set_string(&value, op->value);
      frame->load_url(frame, &value);
      cef_string_clear(&value);
      frame->base.release((cef_base_ref_counted_t *)frame);
    } else {
      lepus_trace("navigate frame missing");
    }
    break;
  case 5:
  case 6:
    lepus_trace("apply script");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      lepus_frame_execute(frame, op->value);
      frame->base.release((cef_base_ref_counted_t *)frame);
    } else {
      lepus_trace("script frame missing");
    }
    break;
  case 7:
    lepus_trace("apply dispatch");
    if (op->dispatch_cb != NULL) {
      op->dispatch_cb((webview_t)w, op->dispatch_arg);
      op->dispatch_arg = NULL;
    }
    break;
  default:
    break;
  }
  if (op->dispatch_arg != NULL) {
    moonbit_decref(op->dispatch_arg);
    op->dispatch_arg = NULL;
  }
}

MOONBIT_FFI_EXPORT int32_t webview_destroy(webview_t raw) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_binding *binding;
  struct moonbit_webview_op *op;
  int had_browser;
  if (w == NULL || w->destroyed) {
    return 0;
  }
  w->destroyed = 1;
  had_browser = w->browser != NULL;
  if (w->browser != NULL) {
    cef_browser_host_t *host = w->browser->get_host(w->browser);
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    lepus_release_browser(w->browser);
    w->browser = NULL;
  }
  while (w->bindings != NULL) {
    binding = w->bindings;
    w->bindings = binding->next;
    moonbit_webview_free_binding(binding);
  }
  while (w->op_head != NULL) {
    op = w->op_head;
    w->op_head = op->next;
    if (op->dispatch_arg != NULL) {
      moonbit_decref(op->dispatch_arg);
    }
    free(op->value);
    free(op);
  }
  if (w->window != NULL) {
    DestroyWindow(w->window);
    w->window = NULL;
  }
  lepus_webview_list_remove(w);
  if (had_browser) {
    return 0;
  }
  free(w->client);
  free(w);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_run(webview_t raw) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return -1;
  }
  if (w->terminated) {
    return 0;
  }
  w->running = 1;
  if (w->op_head != NULL) {
    PostMessageW(w->window, LEPUS_WM_FLUSH_OPS, 0, 0);
  }
  ShowWindow(w->window, SW_SHOW);
  lepus_trace("run message loop");
  cef_run_message_loop();
  lepus_trace("message loop returned");
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_terminate(webview_t raw) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w != NULL) {
    w->terminated = 1;
    if (w->browser != NULL) {
      cef_browser_host_t *host = w->browser->get_host(w->browser);
      if (host != NULL) {
        host->close_browser(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  }
  lepus_trace("terminate");
  cef_quit_message_loop();
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_dispatch(
    webview_t raw,
    void (*fn)(webview_t w, void *arg),
    void *arg) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct lepus_dispatch_task *task;
  int posted;
  if (w == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return -1;
  }
  if (!w->running || w->browser == NULL) {
    lepus_queue_op(w, 7, NULL, 0, 0, 0, fn, arg);
    return 0;
  }
  if (cef_currently_on(TID_UI)) {
    if (fn != NULL) {
      fn(raw, arg);
    }
    return 0;
  }
  task = lepus_dispatch_task_new(raw, fn, arg);
  if (task == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return -1;
  }
  task->task.base.add_ref((cef_base_ref_counted_t *)&task->task);
  posted = cef_post_task(TID_UI, &task->task);
  task->task.base.release((cef_base_ref_counted_t *)&task->task);
  if (!posted) {
    task->task.base.release((cef_base_ref_counted_t *)&task->task);
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int64_t webview_get_window(webview_t raw) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  return (int64_t)(intptr_t)(w != NULL ? w->window : NULL);
}

MOONBIT_FFI_EXPORT int64_t webview_get_native_handle(webview_t raw, int32_t kind) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return 0;
  }
  if (kind == 0) {
    return (int64_t)(intptr_t)w->window;
  }
  if (kind == 2 && w->browser != NULL) {
    return (int64_t)(intptr_t)w->browser;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_set_title(webview_t raw, const char *title) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_op op;
  if (w == NULL) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  op.type = 1;
  op.value = (char *)(title != NULL ? title : "");
  lepus_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_set_size(
    webview_t raw,
    int32_t width,
    int32_t height,
    int32_t hint) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_op op;
  if (w == NULL) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  op.type = 2;
  op.width = width;
  op.height = height;
  op.hint = hint;
  lepus_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_set_html(webview_t raw, const char *html) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_op op;
  if (w == NULL) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  op.type = 3;
  op.value = (char *)(html != NULL ? html : "");
  lepus_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_navigate(webview_t raw, const char *url) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_op op;
  if (w == NULL) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  op.type = 4;
  op.value = (char *)(url != NULL ? url : "");
  lepus_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_init(webview_t raw, const char *script) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return -1;
  }
  lepus_queue_op(w, 5, script, 0, 0, 0, NULL, NULL);
  if (w->browser != NULL) {
    lepus_flush_ops(w);
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_eval(webview_t raw, const char *script) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return -1;
  }
  lepus_queue_op(w, 6, script, 0, 0, 0, NULL, NULL);
  if (w->browser != NULL) {
    lepus_flush_ops(w);
  }
  return 0;
}

MOONBIT_FFI_EXPORT void *moonbit_webview_bind(
    webview_t raw,
    const char *name,
    moonbit_webview_bind_callback_t fn,
    void *arg) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_binding *binding;
  if (w == NULL || name == NULL || fn == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }
  binding =
      (struct moonbit_webview_binding *)calloc(1, sizeof(*binding));
  if (binding == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }
  binding->name = moonbit_webview_strdup(name);
  if (binding->name == NULL) {
    free(binding);
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }
  binding->callback = fn;
  binding->arg = arg;
  binding->next = w->bindings;
  w->bindings = binding;
  if (w->running) {
    lepus_install_binding_script(w, binding->name);
  }
  return binding;
}

MOONBIT_FFI_EXPORT int32_t moonbit_webview_unbind(
    webview_t raw,
    const char *name,
    void *raw_binding) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_binding *binding =
      (struct moonbit_webview_binding *)raw_binding;
  struct moonbit_webview_binding **cursor;
  (void)name;
  if (w == NULL || binding == NULL) {
    return 0;
  }
  cursor = &w->bindings;
  while (*cursor != NULL) {
    if (*cursor == binding) {
      *cursor = binding->next;
      moonbit_webview_free_binding(binding);
      return 0;
    }
    cursor = &(*cursor)->next;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_return(
    webview_t raw,
    const char *seq,
    int32_t status,
    const char *result) {
  lepus_send_response_to_renderer(
      (struct moonbit_webview *)raw,
      seq,
      status,
      result != NULL ? result : "");
  return 0;
}

MOONBIT_FFI_EXPORT int64_t moonbit_webview_identity(webview_t raw) {
  return (int64_t)(intptr_t)raw;
}

#else

MOONBIT_FFI_EXPORT int32_t moonbit_webview_backend_available(void) {
  return 0;
}

MOONBIT_FFI_EXPORT webview_t webview_create(int32_t debug, int64_t window) {
  (void)debug;
  (void)window;
  fprintf(
      stderr,
      "Lepus CEF backend is not linked. Set LEPUS_CEF_ROOT to a Windows CEF "
      "binary distribution before building.\n");
  abort();
}

MOONBIT_FFI_EXPORT int32_t webview_destroy(webview_t w) {
  (void)w;
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_run(webview_t w) {
  (void)w;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_terminate(webview_t w) {
  (void)w;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_dispatch(
    webview_t w,
    void (*fn)(webview_t w, void *arg),
    void *arg) {
  (void)w;
  (void)fn;
  if (arg != NULL) {
    moonbit_decref(arg);
  }
  return -1;
}

MOONBIT_FFI_EXPORT int64_t webview_get_window(webview_t w) {
  (void)w;
  return 0;
}

MOONBIT_FFI_EXPORT int64_t webview_get_native_handle(webview_t w, int32_t kind) {
  (void)w;
  (void)kind;
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_set_title(webview_t w, const char *title) {
  (void)w;
  (void)title;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_set_size(
    webview_t w,
    int32_t width,
    int32_t height,
    int32_t hint) {
  (void)w;
  (void)width;
  (void)height;
  (void)hint;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_set_html(webview_t w, const char *html) {
  (void)w;
  (void)html;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_navigate(webview_t w, const char *url) {
  (void)w;
  (void)url;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_init(webview_t w, const char *script) {
  (void)w;
  (void)script;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t webview_eval(webview_t w, const char *script) {
  (void)w;
  (void)script;
  return -1;
}

MOONBIT_FFI_EXPORT void *moonbit_webview_bind(
    webview_t w,
    const char *name,
    moonbit_webview_bind_callback_t fn,
    void *arg) {
  (void)w;
  (void)name;
  (void)fn;
  if (arg != NULL) {
    moonbit_decref(arg);
  }
  return NULL;
}

MOONBIT_FFI_EXPORT int32_t moonbit_webview_unbind(
    webview_t w,
    const char *name,
    void *binding) {
  (void)w;
  (void)name;
  moonbit_webview_free_binding((struct moonbit_webview_binding *)binding);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_return(
    webview_t w,
    const char *seq,
    int32_t status,
    const char *result) {
  (void)w;
  (void)seq;
  (void)status;
  (void)result;
  return -1;
}

MOONBIT_FFI_EXPORT int64_t moonbit_webview_identity(webview_t w) {
  return (int64_t)(intptr_t)w;
}

#endif

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_webview_copy_cstr(void *raw_cstr) {
  return moonbit_webview_make_cstr((const char *)raw_cstr);
}
