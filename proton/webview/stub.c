#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

#include "moonbit.h"

#define PROTON_CEF_BACKEND_NAME "cef"

typedef void *webview_t;
typedef void (*moonbit_webview_bind_callback_t)(void *seq, void *req, void *arg);

struct moonbit_webview_binding {
  char *name;
  moonbit_webview_bind_callback_t callback;
  void *arg;
  struct moonbit_webview_binding *next;
};

struct moonbit_webview_init_script {
  char *script;
  struct moonbit_webview_init_script *next;
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

static void proton_trace(const char *message) {
  if (getenv("PROTON_CEF_TRACE") != NULL) {
    fprintf(stderr, "[proton-cef] %s\n", message);
    fflush(stderr);
  }
}

static int proton_trace_enabled(void) {
  return getenv("PROTON_CEF_TRACE") != NULL;
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
  return moonbit_webview_make_cstr(PROTON_CEF_BACKEND_NAME);
}

#if defined(_WIN32) && defined(PROTON_CEF_ENABLED) && PROTON_CEF_ENABLED

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"
#include "include/cef_api_hash.h"

#define PROTON_CEF_MESSAGE_INVOKE "proton.invoke"
#define PROTON_CEF_MESSAGE_RESPONSE "proton.response"
#define PROTON_CEF_MESSAGE_CONTEXT_READY "proton.context_ready"
#define PROTON_CEF_MESSAGE_INSTALL_BINDING "proton.install_binding"
#define PROTON_CEF_MESSAGE_INIT_SCRIPT "proton.init_script"
#define PROTON_CEF_DEFAULT_URL "about:blank"
#define PROTON_CEF_CLASS_NAME L"ProtonCefWindow"
#define PROTON_WM_FLUSH_OPS (WM_APP + 51)

#ifndef PROTON_CEF_ROOT_PATH
#define PROTON_CEF_ROOT_PATH ""
#endif

#ifndef PROTON_CEF_SUBPROCESS_PATH
#define PROTON_CEF_SUBPROCESS_PATH ""
#endif

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
  struct moonbit_webview_init_script *init_scripts;
  struct moonbit_webview_op *op_head;
  struct moonbit_webview_op *op_tail;
  struct moonbit_webview *next;
};

struct proton_ref_counted {
  long refs;
};

struct proton_client {
  cef_client_t client;
  struct proton_ref_counted refs;
  struct moonbit_webview *webview;
  cef_life_span_handler_t life_span;
  struct proton_ref_counted life_span_refs;
  cef_load_handler_t load;
  struct proton_ref_counted load_refs;
};

struct proton_app {
  cef_app_t app;
  struct proton_ref_counted refs;
  cef_render_process_handler_t render;
  struct proton_ref_counted render_refs;
  cef_v8_handler_t v8;
  struct proton_ref_counted v8_refs;
};

struct proton_dispatch_task {
  cef_task_t task;
  struct proton_ref_counted refs;
  webview_t webview;
  void (*callback)(webview_t, void *);
  void *arg;
};

struct proton_render_init_script {
  int browser_id;
  char *script;
  struct proton_render_init_script *next;
};

static int proton_cef_initialized = 0;
static int proton_cef_shutdown_registered = 0;
static HMODULE proton_cef_module = NULL;
static struct moonbit_webview *proton_webviews = NULL;
static struct proton_render_init_script *proton_render_init_scripts = NULL;
static struct proton_app proton_app_instance;

static void CEF_CALLBACK proton_add_ref(cef_base_ref_counted_t *base) {
  struct proton_ref_counted *refs =
      (struct proton_ref_counted *)((char *)base + base->size);
  InterlockedIncrement(&refs->refs);
}

static int CEF_CALLBACK proton_release(cef_base_ref_counted_t *base) {
  struct proton_ref_counted *refs =
      (struct proton_ref_counted *)((char *)base + base->size);
  long value = InterlockedDecrement(&refs->refs);
  if (value <= 0) {
    refs->refs = 1;
  }
  return 0;
}

static int CEF_CALLBACK proton_has_one_ref(cef_base_ref_counted_t *base) {
  struct proton_ref_counted *refs =
      (struct proton_ref_counted *)((char *)base + base->size);
  return refs->refs == 1;
}

static int CEF_CALLBACK proton_has_at_least_one_ref(
    cef_base_ref_counted_t *base) {
  struct proton_ref_counted *refs =
      (struct proton_ref_counted *)((char *)base + base->size);
  return refs->refs > 0;
}

static void proton_init_base(cef_base_ref_counted_t *base, size_t size) {
  struct proton_ref_counted *refs =
      (struct proton_ref_counted *)((char *)base + size);
  memset(base, 0, size + sizeof(*refs));
  base->size = size;
  base->add_ref = proton_add_ref;
  base->release = proton_release;
  base->has_one_ref = proton_has_one_ref;
  base->has_at_least_one_ref = proton_has_at_least_one_ref;
  refs->refs = 1;
}

static void CEF_CALLBACK proton_task_add_ref(cef_base_ref_counted_t *base) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)((char *)base -
                                     offsetof(struct proton_dispatch_task, task));
  InterlockedIncrement(&task->refs.refs);
}

static int CEF_CALLBACK proton_task_release(cef_base_ref_counted_t *base) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)((char *)base -
                                     offsetof(struct proton_dispatch_task, task));
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

static int CEF_CALLBACK proton_task_has_one_ref(cef_base_ref_counted_t *base) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)((char *)base -
                                     offsetof(struct proton_dispatch_task, task));
  return task->refs.refs == 1;
}

static int CEF_CALLBACK proton_task_has_at_least_one_ref(
    cef_base_ref_counted_t *base) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)((char *)base -
                                     offsetof(struct proton_dispatch_task, task));
  return task->refs.refs > 0;
}

static void CEF_CALLBACK proton_dispatch_task_execute(cef_task_t *raw_task) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)((char *)raw_task -
                                     offsetof(struct proton_dispatch_task, task));
  if (task->callback != NULL) {
    task->callback(task->webview, task->arg);
    task->arg = NULL;
  }
}

static struct proton_dispatch_task *proton_dispatch_task_new(
    webview_t webview,
    void (*callback)(webview_t, void *),
    void *arg) {
  struct proton_dispatch_task *task =
      (struct proton_dispatch_task *)calloc(1, sizeof(*task));
  if (task == NULL) {
    return NULL;
  }
  task->task.base.size = sizeof(task->task);
  task->task.base.add_ref = proton_task_add_ref;
  task->task.base.release = proton_task_release;
  task->task.base.has_one_ref = proton_task_has_one_ref;
  task->task.base.has_at_least_one_ref = proton_task_has_at_least_one_ref;
  task->task.execute = proton_dispatch_task_execute;
  task->refs.refs = 1;
  task->webview = webview;
  task->callback = callback;
  task->arg = arg;
  return task;
}

static void proton_set_string(cef_string_t *target, const char *value) {
  if (value == NULL) {
    value = "";
  }
  cef_string_from_utf8(value, strlen(value), target);
}

static char *proton_userfree_to_utf8(cef_string_userfree_t value) {
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

static char *proton_v8_to_utf8(cef_v8_value_t *value) {
  if (value == NULL || !value->is_string(value)) {
    return moonbit_webview_strdup("");
  }
  return proton_userfree_to_utf8(value->get_string_value(value));
}

static char *proton_list_string(cef_list_value_t *list, int index) {
  if (list == NULL || list->get_size(list) <= (size_t)index) {
    return moonbit_webview_strdup("");
  }
  return proton_userfree_to_utf8(list->get_string(list, index));
}

static char *proton_path_join(const char *left, const char *right) {
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

static int proton_path_file_exists(const char *path) {
  DWORD attributes;
  if (path == NULL || path[0] == '\0') {
    return 0;
  }
  attributes = GetFileAttributesA(path);
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static const char *proton_executable_dir_path(void) {
  static char dir[MAX_PATH];
  static int initialized = 0;
  DWORD len;
  char *slash;
  char *forward_slash;
  if (initialized) {
    return dir;
  }
  initialized = 1;
  len = GetModuleFileNameA(NULL, dir, sizeof(dir));
  if (len == 0 || len >= sizeof(dir)) {
    dir[0] = '\0';
    return dir;
  }
  slash = strrchr(dir, '\\');
  forward_slash = strrchr(dir, '/');
  if (forward_slash != NULL && (slash == NULL || forward_slash > slash)) {
    slash = forward_slash;
  }
  if (slash != NULL) {
    *slash = '\0';
  } else {
    dir[0] = '\0';
  }
  return dir;
}

static int proton_cef_root_runtime_available(const char *root) {
  char *release_dir = NULL;
  char *dll_path = NULL;
  char *resources_dir = NULL;
  char *icudtl_path = NULL;
  int available;
  if (root == NULL || root[0] == '\0') {
    return 0;
  }
  release_dir = proton_path_join(root, "Release");
  if (release_dir != NULL) {
    dll_path = proton_path_join(release_dir, "libcef.dll");
  }
  resources_dir = proton_path_join(root, "Resources");
  if (resources_dir != NULL) {
    icudtl_path = proton_path_join(resources_dir, "icudtl.dat");
  }
  available = proton_path_file_exists(dll_path) &&
              proton_path_file_exists(icudtl_path);
  free(release_dir);
  free(dll_path);
  free(resources_dir);
  free(icudtl_path);
  return available;
}

static const char *proton_default_cef_root_path(void) {
  const char *exe_dir;
  if (proton_cef_root_runtime_available(PROTON_CEF_ROOT_PATH)) {
    return PROTON_CEF_ROOT_PATH;
  }
  exe_dir = proton_executable_dir_path();
  if (proton_cef_root_runtime_available(exe_dir)) {
    return exe_dir;
  }
  return PROTON_CEF_ROOT_PATH;
}

static const char *proton_cef_root_path(void) {
  const char *env = getenv("PROTON_CEF_ROOT");
  if (env != NULL && env[0] != '\0') {
    return env;
  }
  return proton_default_cef_root_path();
}

static const char *proton_default_cef_subprocess_path(void) {
  static char subprocess_path[MAX_PATH];
  const char *exe_dir;
  char *joined;
  if (PROTON_CEF_SUBPROCESS_PATH[0] != '\0' &&
      proton_path_file_exists(PROTON_CEF_SUBPROCESS_PATH)) {
    return PROTON_CEF_SUBPROCESS_PATH;
  }
  exe_dir = proton_executable_dir_path();
  joined = proton_path_join(exe_dir, "cef_process.exe");
  if (joined != NULL) {
    if (strlen(joined) < sizeof(subprocess_path)) {
      memcpy(subprocess_path, joined, strlen(joined) + 1);
      free(joined);
      if (proton_path_file_exists(subprocess_path)) {
        return subprocess_path;
      }
    } else {
      free(joined);
    }
  }
  if (PROTON_CEF_SUBPROCESS_PATH[0] != '\0') {
    return PROTON_CEF_SUBPROCESS_PATH;
  }
  return subprocess_path;
}

static const char *proton_cef_subprocess_path(void) {
  const char *env = getenv("PROTON_CEF_SUBPROCESS_PATH");
  if (env != NULL && env[0] != '\0') {
    return env;
  }
  return proton_default_cef_subprocess_path();
}

static int proton_cef_remote_debugging_port(void) {
  const char *env = getenv("PROTON_CEF_REMOTE_DEBUGGING_PORT");
  char *end = NULL;
  long port;
  if (env == NULL || env[0] == '\0') {
    return 0;
  }
  port = strtol(env, &end, 10);
  if (end == env || *end != '\0' || port < 0 || port > 65535) {
    fprintf(stderr,
            "Ignoring invalid PROTON_CEF_REMOTE_DEBUGGING_PORT value: %s\n",
            env);
    return 0;
  }
  return (int)port;
}

static int proton_file_exists(const char *path) {
  return proton_path_file_exists(path);
}

static void proton_prepend_env_path(const char *dir) {
  DWORD old_len;
  char *old_path = NULL;
  char *new_path;
  size_t dir_len;
  size_t path_len = 0;
  if (dir == NULL || dir[0] == '\0') {
    return;
  }
  old_len = GetEnvironmentVariableA("PATH", NULL, 0);
  if (old_len > 0) {
    old_path = (char *)malloc((size_t)old_len + 1);
    if (old_path == NULL) {
      return;
    }
    if (GetEnvironmentVariableA("PATH", old_path, old_len + 1) == 0) {
      free(old_path);
      old_path = NULL;
    }
  }
  dir_len = strlen(dir);
  if (old_path != NULL) {
    path_len = strlen(old_path);
  }
  new_path = (char *)malloc(dir_len + (path_len > 0 ? 1 + path_len : 0) + 1);
  if (new_path == NULL) {
    free(old_path);
    return;
  }
  memcpy(new_path, dir, dir_len);
  if (path_len > 0) {
    new_path[dir_len] = ';';
    memcpy(new_path + dir_len + 1, old_path, path_len + 1);
  } else {
    new_path[dir_len] = '\0';
  }
  SetEnvironmentVariableA("PATH", new_path);
  free(old_path);
  free(new_path);
}

static int proton_cef_runtime_files_available(void) {
  const char *cef_root = proton_cef_root_path();
  const char *subprocess_path = proton_cef_subprocess_path();
  char *release_dir = NULL;
  char *dll_path = NULL;
  char *resources_dir = NULL;
  char *icudtl_path = NULL;
  int available = 0;
  if (cef_root == NULL || cef_root[0] == '\0') {
    return 0;
  }
  release_dir = proton_path_join(cef_root, "Release");
  if (release_dir != NULL) {
    dll_path = proton_path_join(release_dir, "libcef.dll");
  }
  resources_dir = proton_path_join(cef_root, "Resources");
  if (resources_dir != NULL) {
    icudtl_path = proton_path_join(resources_dir, "icudtl.dat");
  }
  available = proton_file_exists(dll_path) &&
              proton_file_exists(icudtl_path) &&
              proton_file_exists(subprocess_path);
  free(release_dir);
  free(dll_path);
  free(resources_dir);
  free(icudtl_path);
  return available;
}

static void proton_prepare_cef_runtime(const char *cef_root) {
  char *release_dir = NULL;
  char *dll_path = NULL;
  const char *load_path = "libcef.dll";
  DWORD flags = 0;
  DWORD error;
  if (proton_cef_module != NULL) {
    return;
  }
  if (cef_root != NULL && cef_root[0] != '\0') {
    release_dir = proton_path_join(cef_root, "Release");
    if (release_dir != NULL) {
      proton_prepend_env_path(release_dir);
      dll_path = proton_path_join(release_dir, "libcef.dll");
    }
    if (dll_path != NULL) {
      load_path = dll_path;
      flags = LOAD_WITH_ALTERED_SEARCH_PATH;
    }
  }
  proton_trace("load libcef");
  proton_cef_module = LoadLibraryExA(load_path, NULL, flags);
  if (proton_cef_module == NULL) {
    error = GetLastError();
    if (cef_root != NULL && cef_root[0] != '\0') {
      fprintf(stderr,
              "Proton CEF runtime DLL could not be loaded from %s "
              "(GetLastError=%lu).\n",
              load_path, (unsigned long)error);
    } else {
      fprintf(stderr,
              "Proton CEF runtime DLL could not be loaded "
              "(GetLastError=%lu). Install CEF with "
              "`proton cef setup` before building, or package "
              "the CEF runtime beside the app executable.\n",
              (unsigned long)error);
    }
    fflush(stderr);
    abort();
  }
  free(release_dir);
  free(dll_path);
}

static char *proton_temp_path_join(const char *name) {
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
  out = proton_path_join(tmp, name);
  free(tmp);
  return out;
}

static char *proton_cache_path_for_process(void) {
  char name[64];
  snprintf(name, sizeof(name), "proton-cef-cache-%lu", GetCurrentProcessId());
  return proton_temp_path_join(name);
}

static void proton_release_browser(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

static void proton_addref_browser(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.add_ref((cef_base_ref_counted_t *)browser);
  }
}

static void proton_webview_list_add(struct moonbit_webview *w) {
  w->next = proton_webviews;
  proton_webviews = w;
}

static void proton_webview_list_remove(struct moonbit_webview *w) {
  struct moonbit_webview **cursor = &proton_webviews;
  while (*cursor != NULL) {
    if (*cursor == w) {
      *cursor = w->next;
      w->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static struct moonbit_webview *proton_webview_from_browser(
    cef_browser_t *browser) {
  int identifier;
  struct moonbit_webview *cursor;
  if (browser == NULL) {
    return NULL;
  }
  identifier = browser->get_identifier(browser);
  for (cursor = proton_webviews; cursor != NULL; cursor = cursor->next) {
    if (cursor->browser != NULL &&
        cursor->browser->get_identifier(cursor->browser) == identifier) {
      return cursor;
    }
  }
  return NULL;
}

static struct moonbit_webview_binding *proton_find_binding(
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

static void proton_frame_execute(cef_frame_t *frame, const char *script) {
  cef_string_t code = {0};
  cef_string_t url = {0};
  if (frame == NULL || script == NULL) {
    return;
  }
  proton_set_string(&code, script);
  proton_set_string(&url, "proton://native");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
}

static void proton_context_eval(cef_v8_context_t *context, const char *script) {
  cef_string_t code = {0};
  cef_string_t url = {0};
  cef_v8_value_t *result = NULL;
  cef_v8_exception_t *exception = NULL;
  if (context == NULL || script == NULL) {
    return;
  }
  proton_set_string(&code, script);
  proton_set_string(&url, "proton://init");
  context->eval(context, &code, &url, 1, &result, &exception);
  cef_string_clear(&code);
  cef_string_clear(&url);
  if (result != NULL) {
    result->base.release((cef_base_ref_counted_t *)result);
  }
  if (exception != NULL) {
    exception->base.release((cef_base_ref_counted_t *)exception);
  }
}

static void proton_render_store_init_script(int browser_id, const char *script) {
  struct proton_render_init_script *entry;
  struct proton_render_init_script *cursor;
  if (script == NULL) {
    script = "";
  }
  for (cursor = proton_render_init_scripts; cursor != NULL; cursor = cursor->next) {
    if (cursor->browser_id == browser_id && strcmp(cursor->script, script) == 0) {
      return;
    }
  }
  entry = (struct proton_render_init_script *)calloc(1, sizeof(*entry));
  if (entry == NULL) {
    return;
  }
  entry->browser_id = browser_id;
  entry->script = moonbit_webview_strdup(script);
  if (entry->script == NULL) {
    free(entry);
    return;
  }
  if (proton_render_init_scripts == NULL) {
    proton_render_init_scripts = entry;
    return;
  }
  for (cursor = proton_render_init_scripts; cursor->next != NULL; cursor = cursor->next) {
  }
  cursor->next = entry;
}

static void proton_render_eval_init_scripts(
    cef_browser_t *browser,
    cef_v8_context_t *context) {
  int browser_id;
  struct proton_render_init_script *entry;
  if (browser == NULL || context == NULL) {
    return;
  }
  browser_id = browser->get_identifier(browser);
  for (entry = proton_render_init_scripts; entry != NULL; entry = entry->next) {
    if (entry->browser_id == browser_id) {
      proton_context_eval(context, entry->script);
    }
  }
}

static char *proton_js_quote(const char *value) {
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

static char *proton_html_replacement_script(const char *html) {
  char *quoted_html = proton_js_quote(html);
  char *script;
  size_t script_len;
  if (quoted_html == NULL) {
    return NULL;
  }
  script_len = strlen(quoted_html) + 80;
  script = (char *)malloc(script_len);
  if (script != NULL) {
    snprintf(
        script,
        script_len,
        "document.open();document.write(%s);document.close();",
        quoted_html);
  }
  free(quoted_html);
  return script;
}

static void proton_install_binding_script_on_frame(
    cef_frame_t *frame,
    const char *name) {
  char *quoted;
  char *script;
  size_t len;
  if (frame == NULL || name == NULL) {
    return;
  }
  proton_trace("install binding script");
  quoted = proton_js_quote(name);
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
        "var native=window.__protonNativeInvoke;"
        "if(typeof native!=='function')return;"
        "if(!window.__protonNativePending)window.__protonNativePending=Object.create(null);"
        "if(!window.__protonNativeResolve){window.__protonNativeResolve=function(id,status,result){"
        "var p=window.__protonNativePending[id];delete window.__protonNativePending[id];"
        "if(!p)return;try{if(status===0){p.resolve(result===''?undefined:JSON.parse(result));}"
        "else{p.reject(new Error(result===''?'native binding failed':JSON.parse(result)));}}"
        "catch(e){p.reject(e);}};}"
        "window[n]=function(){var args=Array.prototype.slice.call(arguments);"
        "return new Promise(function(resolve,reject){"
        "try{var id=native(n,JSON.stringify(args));window.__protonNativePending[id]={resolve:resolve,reject:reject};}"
        "catch(e){reject(e);}});};"
        "})();",
        quoted);
    proton_frame_execute(frame, script);
    free(script);
  }
  free(quoted);
}

static void proton_install_binding_script(
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
  proton_trace("send install binding");
  proton_set_string(&message_name, PROTON_CEF_MESSAGE_INSTALL_BINDING);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message != NULL) {
    list = message->get_argument_list(message);
    list->set_size(list, 1);
    proton_set_string(&binding_name, name);
    list->set_string(list, 0, &binding_name);
    cef_string_clear(&binding_name);
    frame->send_process_message(frame, PID_RENDERER, message);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_send_init_script(
    struct moonbit_webview *w,
    const char *script) {
  cef_frame_t *frame;
  cef_process_message_t *message;
  cef_list_value_t *list;
  cef_string_t message_name = {0};
  cef_string_t script_string = {0};
  if (w == NULL || w->browser == NULL || script == NULL) {
    return;
  }
  frame = w->browser->get_main_frame(w->browser);
  if (frame == NULL) {
    return;
  }
  proton_trace("send init script");
  proton_set_string(&message_name, PROTON_CEF_MESSAGE_INIT_SCRIPT);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message != NULL) {
    list = message->get_argument_list(message);
    list->set_size(list, 1);
    proton_set_string(&script_string, script);
    list->set_string(list, 0, &script_string);
    cef_string_clear(&script_string);
    frame->send_process_message(frame, PID_RENDERER, message);
  }
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_send_all_init_scripts(struct moonbit_webview *w) {
  struct moonbit_webview_init_script *entry;
  if (w == NULL) {
    return;
  }
  for (entry = w->init_scripts; entry != NULL; entry = entry->next) {
    proton_send_init_script(w, entry->script);
  }
}

static void proton_install_all_bindings(struct moonbit_webview *w) {
  struct moonbit_webview_binding *binding;
  for (binding = w->bindings; binding != NULL; binding = binding->next) {
    proton_install_binding_script(w, binding->name);
  }
}

static int proton_store_init_script(
    struct moonbit_webview *w,
    const char *script) {
  struct moonbit_webview_init_script *entry;
  struct moonbit_webview_init_script *cursor;
  if (w == NULL) {
    return 0;
  }
  entry = (struct moonbit_webview_init_script *)calloc(1, sizeof(*entry));
  if (entry == NULL) {
    return 0;
  }
  entry->script = moonbit_webview_strdup(script);
  if (entry->script == NULL) {
    free(entry);
    return 0;
  }
  if (w->init_scripts == NULL) {
    w->init_scripts = entry;
    return 1;
  }
  for (cursor = w->init_scripts; cursor->next != NULL; cursor = cursor->next) {
  }
  cursor->next = entry;
  return 1;
}

static void proton_response_script_for_browser(
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
  quoted_seq = proton_js_quote(seq);
  quoted_result = proton_js_quote(result);
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
        "if(window.__protonNativeResolve)window.__protonNativeResolve(%s,%d,%s);",
        quoted_seq,
        status,
        quoted_result);
    proton_frame_execute(frame, script);
    free(script);
  }
  free(quoted_seq);
  free(quoted_result);
}

static void proton_response_script(
    struct moonbit_webview *w,
    const char *seq,
    int status,
    const char *result) {
  if (w == NULL) {
    return;
  }
  proton_response_script_for_browser(w->browser, seq, status, result);
}

static void proton_send_response_to_renderer(
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
  proton_set_string(&message_name, PROTON_CEF_MESSAGE_RESPONSE);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
    return;
  }
  list = message->get_argument_list(message);
  list->set_size(list, 3);
  proton_set_string(&seq_string, seq);
  proton_set_string(&result_string, result != NULL ? result : "");
  list->set_string(list, 0, &seq_string);
  list->set_int(list, 1, status);
  list->set_string(list, 2, &result_string);
  frame->send_process_message(frame, PID_RENDERER, message);
  cef_string_clear(&seq_string);
  cef_string_clear(&result_string);
  frame->base.release((cef_base_ref_counted_t *)frame);
}

static void proton_queue_op(
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

static void proton_apply_op(struct moonbit_webview *w, struct moonbit_webview_op *op);

static void proton_flush_ops(struct moonbit_webview *w) {
  struct moonbit_webview_op *op = w->op_head;
  w->op_head = NULL;
  w->op_tail = NULL;
  while (op != NULL) {
    struct moonbit_webview_op *next = op->next;
    proton_apply_op(w, op);
    free(op->value);
    free(op);
    op = next;
  }
}

static void proton_flush_dispatch(webview_t raw, void *arg) {
  (void)arg;
  proton_flush_ops((struct moonbit_webview *)raw);
}

static void proton_install_bindings_dispatch(webview_t raw, void *arg) {
  (void)arg;
  proton_trace("delayed install bindings");
  proton_install_all_bindings((struct moonbit_webview *)raw);
}

static LRESULT CALLBACK proton_window_proc(
    HWND hwnd,
    UINT msg,
    WPARAM wparam,
    LPARAM lparam) {
  struct moonbit_webview *w =
      (struct moonbit_webview *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
  case PROTON_WM_FLUSH_OPS:
    if (w != NULL) {
      proton_trace("flush ops");
      proton_flush_ops(w);
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

static void proton_register_window_class(void) {
  static int registered = 0;
  WNDCLASSW wc;
  if (registered) {
    return;
  }
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = proton_window_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = PROTON_CEF_CLASS_NAME;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassW(&wc);
  registered = 1;
}

static void proton_on_before_command_line_processing(
    cef_app_t *self,
    const cef_string_t *process_type,
    cef_command_line_t *command_line) {
  const char *cef_root;
  char *resources_dir = NULL;
  char *locales_dir = NULL;
  (void)self;
  (void)process_type;
  if (command_line != NULL) {
    cef_string_t switch_name = {0};
    cef_string_t switch_value = {0};
    proton_set_string(&switch_name, "disable-gpu");
    command_line->append_switch(command_line, &switch_name);
    cef_string_clear(&switch_name);
    cef_root = proton_cef_root_path();
    if (cef_root != NULL && cef_root[0] != '\0') {
      resources_dir = proton_path_join(cef_root, "Resources");
      if (resources_dir != NULL) {
        proton_set_string(&switch_name, "resources-dir-path");
        proton_set_string(&switch_value, resources_dir);
        command_line->append_switch_with_value(
            command_line, &switch_name, &switch_value);
        cef_string_clear(&switch_name);
        cef_string_clear(&switch_value);
        locales_dir = proton_path_join(resources_dir, "locales");
      }
      if (locales_dir != NULL) {
        proton_set_string(&switch_name, "locales-dir-path");
        proton_set_string(&switch_value, locales_dir);
        command_line->append_switch_with_value(
            command_line, &switch_name, &switch_value);
        cef_string_clear(&switch_name);
        cef_string_clear(&switch_value);
      }
    }
  }
  free(resources_dir);
  free(locales_dir);
}

static cef_render_process_handler_t *CEF_CALLBACK proton_get_render_handler(
    cef_app_t *self) {
  (void)self;
  return &proton_app_instance.render;
}

static int CEF_CALLBACK proton_v8_execute(
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
  proton_trace("v8 invoke");
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
  binding_name = proton_v8_to_utf8(arguments[0]);
  request_json = proton_v8_to_utf8(arguments[1]);
  snprintf(seq, sizeof(seq), "cef:%ld", InterlockedIncrement(&request_id));
  proton_set_string(&message_name, PROTON_CEF_MESSAGE_INVOKE);
  message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message != NULL) {
    list = message->get_argument_list(message);
    list->set_size(list, 3);
    proton_set_string(&seq_string, seq);
    proton_set_string(&binding_string, binding_name);
    proton_set_string(&request_string, request_json);
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
  proton_set_string(&seq_string, seq);
  *retval = cef_v8_value_create_string(&seq_string);
  cef_string_clear(&seq_string);
  frame->base.release((cef_base_ref_counted_t *)frame);
  browser->base.release((cef_base_ref_counted_t *)browser);
  context->base.release((cef_base_ref_counted_t *)context);
  return 1;
}

static void CEF_CALLBACK proton_on_context_created(
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
  proton_trace("context created");
  if (context == NULL || !context->enter(context)) {
    return;
  }
  global = context->get_global(context);
  proton_set_string(&function_name, "__protonNativeInvoke");
  function = cef_v8_value_create_function(&function_name, &proton_app_instance.v8);
  if (global != NULL && function != NULL) {
    global->set_value_bykey(global, &function_name, function, V8_PROPERTY_ATTRIBUTE_NONE);
  }
  proton_render_eval_init_scripts(browser, context);
  {
    cef_string_t ready_code = {0};
    cef_string_t ready_url = {0};
    cef_v8_value_t *ready_result = NULL;
    cef_v8_exception_t *ready_exception = NULL;
    proton_set_string(&ready_code, "__protonNativeInvoke('__protonReady','[]');");
    proton_set_string(&ready_url, "proton://ready");
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
    proton_set_string(&message_name, PROTON_CEF_MESSAGE_CONTEXT_READY);
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

static int CEF_CALLBACK proton_render_message(
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
  char *init_script;
  int status;
  (void)self;
  (void)frame;
  (void)source_process;
  raw_name = message->get_name(message);
  message_name = proton_userfree_to_utf8(raw_name);
  if (strcmp(message_name, PROTON_CEF_MESSAGE_INSTALL_BINDING) == 0) {
    proton_trace("renderer install binding message");
    free(message_name);
    list = message->get_argument_list(message);
    binding_name = proton_list_string(list, 0);
    if (frame != NULL) {
      proton_install_binding_script_on_frame(frame, binding_name);
    } else if (browser != NULL) {
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      if (main_frame != NULL) {
        proton_install_binding_script_on_frame(main_frame, binding_name);
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
    }
    free(binding_name);
    return 1;
  }
  if (strcmp(message_name, PROTON_CEF_MESSAGE_INIT_SCRIPT) == 0) {
    proton_trace("renderer init script message");
    free(message_name);
    list = message->get_argument_list(message);
    init_script = proton_list_string(list, 0);
    if (browser != NULL) {
      proton_render_store_init_script(browser->get_identifier(browser), init_script);
    }
    if (frame != NULL) {
      proton_frame_execute(frame, init_script);
    } else if (browser != NULL) {
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      if (main_frame != NULL) {
        proton_frame_execute(main_frame, init_script);
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
    }
    free(init_script);
    return 1;
  }
  if (strcmp(message_name, PROTON_CEF_MESSAGE_RESPONSE) != 0) {
    free(message_name);
    return 0;
  }
  proton_trace("renderer response message");
  free(message_name);
  list = message->get_argument_list(message);
  seq = proton_list_string(list, 0);
  status = list->get_int(list, 1);
  result = proton_list_string(list, 2);
  proton_response_script_for_browser(browser, seq, status, result);
  free(seq);
  free(result);
  return 1;
}

static cef_life_span_handler_t *CEF_CALLBACK proton_get_life_span_handler(
    cef_client_t *client) {
  struct proton_client *owner =
      (struct proton_client *)((char *)client - offsetof(struct proton_client, client));
  return &owner->life_span;
}

static cef_load_handler_t *CEF_CALLBACK proton_get_load_handler(
    cef_client_t *client) {
  struct proton_client *owner =
      (struct proton_client *)((char *)client - offsetof(struct proton_client, client));
  return &owner->load;
}

static int CEF_CALLBACK proton_client_message(
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
  message_name = proton_userfree_to_utf8(raw_name);
  if (strcmp(message_name, PROTON_CEF_MESSAGE_CONTEXT_READY) == 0) {
    free(message_name);
    proton_trace("browser context ready");
    w = proton_webview_from_browser(browser);
    if (w != NULL && w->running) {
      proton_send_all_init_scripts(w);
      proton_install_all_bindings(w);
    }
    return 1;
  }
  if (strcmp(message_name, PROTON_CEF_MESSAGE_INVOKE) != 0) {
    free(message_name);
    return 0;
  }
  proton_trace("browser invoke message");
  free(message_name);
  w = proton_webview_from_browser(browser);
  list = message->get_argument_list(message);
  seq = proton_list_string(list, 0);
  binding_name = proton_list_string(list, 1);
  request_json = proton_list_string(list, 2);
  if (proton_trace_enabled()) {
    fprintf(stderr, "[proton-cef] invoke binding: %s\n", binding_name);
    fflush(stderr);
  }
  if (strcmp(binding_name, "__protonReady") == 0) {
    if (w != NULL && w->running) {
      proton_install_all_bindings(w);
    }
    free(seq);
    free(binding_name);
    free(request_json);
    return 1;
  }
  binding = proton_find_binding(w, binding_name);
  if (binding == NULL) {
    proton_send_response_to_renderer(
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

static void CEF_CALLBACK proton_on_after_created(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  struct proton_client *owner =
      (struct proton_client *)((char *)self - offsetof(struct proton_client, life_span));
  proton_trace("browser after created");
  owner->webview->browser = browser;
  proton_addref_browser(browser);
  proton_send_all_init_scripts(owner->webview);
  proton_flush_ops(owner->webview);
}

static int CEF_CALLBACK proton_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  (void)browser;
  return 0;
}

static void CEF_CALLBACK proton_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  struct proton_client *owner =
      (struct proton_client *)((char *)self - offsetof(struct proton_client, life_span));
  (void)browser;
  owner->webview->terminated = 1;
  cef_quit_message_loop();
}

static void CEF_CALLBACK proton_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int http_status_code) {
  struct proton_client *owner =
      (struct proton_client *)((char *)self - offsetof(struct proton_client, load));
  (void)browser;
  (void)http_status_code;
  if (frame != NULL && frame->is_main(frame)) {
    proton_trace("load end");
    if (owner->webview != NULL && owner->webview->running) {
      proton_install_all_bindings(owner->webview);
    }
  }
}

static void proton_init_app(void) {
  static int initialized = 0;
  if (initialized) {
    return;
  }
  proton_init_base((cef_base_ref_counted_t *)&proton_app_instance.app.base,
                  sizeof(proton_app_instance.app));
  proton_app_instance.app.on_before_command_line_processing =
      proton_on_before_command_line_processing;
  proton_app_instance.app.get_render_process_handler = proton_get_render_handler;
  proton_init_base((cef_base_ref_counted_t *)&proton_app_instance.render.base,
                  sizeof(proton_app_instance.render));
  proton_app_instance.render.on_context_created = proton_on_context_created;
  proton_app_instance.render.on_process_message_received = proton_render_message;
  proton_init_base((cef_base_ref_counted_t *)&proton_app_instance.v8.base,
                  sizeof(proton_app_instance.v8));
  proton_app_instance.v8.execute = proton_v8_execute;
  initialized = 1;
}

static void proton_check_cef_api_hash(void) {
#ifdef CEF_API_VERSION
  (void)cef_api_hash(CEF_API_VERSION, 0);
#else
  (void)cef_api_hash(0);
#endif
}

MOONBIT_FFI_EXPORT int32_t proton_cef_execute_process(void) {
  cef_main_args_t args;
  const char *cef_root = proton_cef_root_path();
  proton_prepare_cef_runtime(cef_root);
  proton_trace("init subprocess app");
  proton_init_app();
  proton_check_cef_api_hash();
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  proton_trace("cef execute process");
  return cef_execute_process(&args, &proton_app_instance.app, NULL);
}

static void proton_cef_shutdown(void) {
  if (proton_cef_initialized) {
    cef_shutdown();
    proton_cef_initialized = 0;
  }
}

static void proton_ensure_cef_initialized(int debug) {
  cef_main_args_t args;
  cef_settings_t settings;
  const char *cef_root;
  const char *subprocess_path;
  char *resources_dir = NULL;
  char *locales_dir = NULL;
  char *root_cache_path = NULL;
  char *log_file = NULL;
  if (proton_cef_initialized) {
    return;
  }
  cef_root = proton_cef_root_path();
  subprocess_path = proton_cef_subprocess_path();
  proton_prepare_cef_runtime(cef_root);
  proton_trace("init app");
  proton_init_app();
  proton_check_cef_api_hash();
  memset(&args, 0, sizeof(args));
  args.instance = GetModuleHandleW(NULL);
  memset(&settings, 0, sizeof(settings));
  settings.size = sizeof(settings);
  settings.no_sandbox = 1;
  settings.multi_threaded_message_loop = 0;
  (void)debug;
  settings.remote_debugging_port = proton_cef_remote_debugging_port();
  settings.log_severity =
      proton_trace_enabled() ? LOGSEVERITY_DEFAULT : LOGSEVERITY_DISABLE;
  if (!proton_file_exists(subprocess_path)) {
    fprintf(stderr,
            "Proton CEF subprocess executable is missing: %s\n"
            "Build it with `moon -C proton build cef_process --target native`, "
            "or package cef_process.exe beside the app executable.\n",
            subprocess_path);
    fflush(stderr);
    abort();
  }
  proton_set_string(&settings.browser_subprocess_path, subprocess_path);
  if (proton_trace_enabled()) {
    log_file = proton_temp_path_join("proton-cef.log");
    if (log_file != NULL) {
      proton_set_string(&settings.log_file, log_file);
    }
  }
  if (cef_root != NULL && cef_root[0] != '\0') {
    resources_dir = proton_path_join(cef_root, "Resources");
    if (resources_dir != NULL) {
      locales_dir = proton_path_join(resources_dir, "locales");
      proton_set_string(&settings.resources_dir_path, resources_dir);
    }
    if (locales_dir != NULL) {
      proton_set_string(&settings.locales_dir_path, locales_dir);
    }
  }
  root_cache_path = proton_cache_path_for_process();
  if (root_cache_path != NULL) {
    CreateDirectoryA(root_cache_path, NULL);
    proton_set_string(&settings.root_cache_path, root_cache_path);
  }
  proton_trace("cef initialize");
  if (!cef_initialize(&args, &settings, &proton_app_instance.app, NULL)) {
    abort();
  }
  cef_string_clear(&settings.resources_dir_path);
  cef_string_clear(&settings.locales_dir_path);
  cef_string_clear(&settings.root_cache_path);
  cef_string_clear(&settings.browser_subprocess_path);
  cef_string_clear(&settings.log_file);
  free(resources_dir);
  free(locales_dir);
  free(root_cache_path);
  free(log_file);
  proton_cef_initialized = 1;
  proton_trace("cef initialized");
  if (!proton_cef_shutdown_registered) {
    atexit(proton_cef_shutdown);
    proton_cef_shutdown_registered = 1;
  }
}

static struct proton_client *proton_client_new(struct moonbit_webview *w) {
  struct proton_client *client =
      (struct proton_client *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  client->webview = w;
  proton_init_base((cef_base_ref_counted_t *)&client->client.base,
                  sizeof(client->client));
  client->client.get_life_span_handler = proton_get_life_span_handler;
  client->client.get_load_handler = proton_get_load_handler;
  client->client.on_process_message_received = proton_client_message;
  proton_init_base((cef_base_ref_counted_t *)&client->life_span.base,
                  sizeof(client->life_span));
  client->life_span.on_after_created = proton_on_after_created;
  client->life_span.do_close = proton_do_close;
  client->life_span.on_before_close = proton_on_before_close;
  proton_init_base((cef_base_ref_counted_t *)&client->load.base,
                  sizeof(client->load));
  client->load.on_load_end = proton_on_load_end;
  return client;
}

static void proton_create_browser(struct moonbit_webview *w) {
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
  proton_set_string(&window_info.window_name, "Proton");
  window_info.parent_window = w->window;
  window_info.style = WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = rect.right - rect.left;
  window_info.bounds.height = rect.bottom - rect.top;
  proton_set_string(&url, PROTON_CEF_DEFAULT_URL);
  proton_trace("create browser");
  w->browser = cef_browser_host_create_browser_sync(
      &window_info,
      w->client,
      &url,
      &browser_settings,
      NULL,
      NULL);
  if (w->browser != NULL) {
    proton_install_all_bindings(w);
    proton_flush_ops(w);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
}

MOONBIT_FFI_EXPORT int32_t moonbit_webview_backend_available(void) {
  return proton_cef_runtime_files_available();
}

MOONBIT_FFI_EXPORT webview_t webview_create(int32_t debug, int64_t window) {
  struct moonbit_webview *w;
  DWORD style = WS_OVERLAPPEDWINDOW | WS_VISIBLE;
  (void)window;
  proton_trace("webview create");
  proton_ensure_cef_initialized(debug);
  proton_register_window_class();
  w = (struct moonbit_webview *)calloc(1, sizeof(*w));
  if (w == NULL) {
    abort();
  }
  w->debug = debug;
  w->width = 800;
  w->height = 600;
  w->client = (cef_client_t *)proton_client_new(w);
  if (w->client == NULL) {
    free(w);
    abort();
  }
  w->window = CreateWindowExW(
      0,
      PROTON_CEF_CLASS_NAME,
      L"Proton",
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
  proton_webview_list_add(w);
  proton_create_browser(w);
  return w;
}

static void proton_apply_op(
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
    proton_queue_op(
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
    proton_queue_op(
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
    proton_trace("apply title");
    SetWindowTextA(w->window, op->value != NULL ? op->value : "");
    break;
  case 2:
    proton_trace("apply size");
    w->width = op->width;
    w->height = op->height;
    SetWindowPos(w->window, NULL, 0, 0, op->width, op->height, SWP_NOMOVE | SWP_NOZORDER);
    break;
  case 3:
    proton_trace("apply html");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      struct proton_dispatch_task *task;
      proton_frame_execute(frame, op->value);
      task = proton_dispatch_task_new((webview_t)w, proton_install_bindings_dispatch, NULL);
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
      proton_trace("html frame missing");
    }
    break;
  case 4:
    proton_trace("apply navigate");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      proton_set_string(&value, op->value);
      frame->load_url(frame, &value);
      cef_string_clear(&value);
      frame->base.release((cef_base_ref_counted_t *)frame);
    } else {
      proton_trace("navigate frame missing");
    }
    break;
  case 5:
  case 6:
    proton_trace("apply script");
    frame = w->browser->get_main_frame(w->browser);
    if (frame != NULL) {
      proton_frame_execute(frame, op->value);
      frame->base.release((cef_base_ref_counted_t *)frame);
    } else {
      proton_trace("script frame missing");
    }
    break;
  case 7:
    proton_trace("apply dispatch");
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
  struct moonbit_webview_init_script *init_script;
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
    proton_release_browser(w->browser);
    w->browser = NULL;
  }
  while (w->bindings != NULL) {
    binding = w->bindings;
    w->bindings = binding->next;
    moonbit_webview_free_binding(binding);
  }
  while (w->init_scripts != NULL) {
    init_script = w->init_scripts;
    w->init_scripts = init_script->next;
    free(init_script->script);
    free(init_script);
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
  proton_webview_list_remove(w);
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
    PostMessageW(w->window, PROTON_WM_FLUSH_OPS, 0, 0);
  }
  ShowWindow(w->window, SW_SHOW);
  proton_trace("run message loop");
  cef_run_message_loop();
  proton_trace("message loop returned");
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
  proton_trace("terminate");
  cef_quit_message_loop();
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_dispatch(
    webview_t raw,
    void (*fn)(webview_t w, void *arg),
    void *arg) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct proton_dispatch_task *task;
  int posted;
  if (w == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return -1;
  }
  if (!w->running || w->browser == NULL) {
    proton_queue_op(w, 7, NULL, 0, 0, 0, fn, arg);
    return 0;
  }
  if (cef_currently_on(TID_UI)) {
    if (fn != NULL) {
      fn(raw, arg);
    }
    return 0;
  }
  task = proton_dispatch_task_new(raw, fn, arg);
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
  proton_apply_op(w, &op);
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
  proton_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t moonbit_webview_set_html_script(
    webview_t raw,
    const char *script) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  struct moonbit_webview_op op;
  if (w == NULL) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  op.type = 3;
  op.value = (char *)(script != NULL ? script : "");
  proton_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_set_html(webview_t raw, const char *html) {
  char *script = proton_html_replacement_script(html);
  int32_t result;
  if (script == NULL) {
    return -1;
  }
  result = moonbit_webview_set_html_script(raw, script);
  free(script);
  return result;
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
  proton_apply_op(w, &op);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_init(webview_t raw, const char *script) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return -1;
  }
  (void)proton_store_init_script(w, script);
  if (w->browser != NULL) {
    proton_send_init_script(w, script != NULL ? script : "");
    return 0;
  }
  proton_queue_op(w, 5, script, 0, 0, 0, NULL, NULL);
  return 0;
}

MOONBIT_FFI_EXPORT int32_t webview_eval(webview_t raw, const char *script) {
  struct moonbit_webview *w = (struct moonbit_webview *)raw;
  if (w == NULL) {
    return -1;
  }
  proton_queue_op(w, 6, script, 0, 0, 0, NULL, NULL);
  if (w->browser != NULL) {
    proton_flush_ops(w);
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
    proton_install_binding_script(w, binding->name);
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
  proton_send_response_to_renderer(
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

MOONBIT_FFI_EXPORT int32_t proton_cef_execute_process(void) {
  return -1;
}

MOONBIT_FFI_EXPORT webview_t webview_create(int32_t debug, int64_t window) {
  (void)debug;
  (void)window;
  fprintf(
      stderr,
      "Proton CEF backend is not linked. Install CEF with "
      "`proton cef setup` before building.\n");
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

MOONBIT_FFI_EXPORT int32_t moonbit_webview_set_html_script(
    webview_t w,
    const char *script) {
  (void)w;
  (void)script;
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
