#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#define LEPUS_CEF_STATUS_OK 0
#define LEPUS_CEF_STATUS_UNSUPPORTED 1
#define LEPUS_CEF_STATUS_INVALID_ARGUMENT 2
#define LEPUS_CEF_STATUS_INVALID_STATE 3
#define LEPUS_CEF_STATUS_NATIVE_ERROR 4

typedef void (*lepus_cef_bind_callback_t)(void *seq, void *req, void *arg);

struct lepus_cef_runtime {
  int32_t status;
  int32_t running;
};

struct lepus_cef_binding {
  char *name;
  lepus_cef_bind_callback_t callback;
  void *arg;
  struct lepus_cef_binding *next;
};

struct lepus_cef_view {
  struct lepus_cef_runtime *runtime;
  int32_t status;
  int32_t width;
  int32_t height;
  char *title;
  struct lepus_cef_binding *bindings;
};

static char *lepus_cef_strdup(const char *value) {
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

static void lepus_cef_free_binding(struct lepus_cef_binding *binding) {
  if (binding == NULL) {
    return;
  }
  free(binding->name);
  if (binding->arg != NULL) {
    moonbit_decref(binding->arg);
  }
  free(binding);
}

static void lepus_cef_free_bindings(struct lepus_cef_binding *binding) {
  while (binding != NULL) {
    struct lepus_cef_binding *next = binding->next;
    lepus_cef_free_binding(binding);
    binding = next;
  }
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_is_available(void) {
#ifdef LEPUS_CEF_ENABLED
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT struct lepus_cef_runtime *lepus_cef_runtime_initialize(
    moonbit_bytes_t cache_path,
    moonbit_bytes_t user_data_path,
    moonbit_bytes_t subprocess_path,
    int32_t remote_debugging_port,
    moonbit_bytes_t locale,
    int32_t sandbox,
    int32_t debug) {
  struct lepus_cef_runtime *runtime =
      (struct lepus_cef_runtime *)malloc(sizeof(struct lepus_cef_runtime));

  (void)cache_path;
  (void)user_data_path;
  (void)subprocess_path;
  (void)remote_debugging_port;
  (void)locale;
  (void)sandbox;
  (void)debug;

  if (runtime == NULL) {
    return NULL;
  }

#ifdef LEPUS_CEF_ENABLED
  runtime->status = LEPUS_CEF_STATUS_UNSUPPORTED;
#else
  runtime->status = LEPUS_CEF_STATUS_UNSUPPORTED;
#endif
  runtime->running = 0;
  return runtime;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_runtime_status(
    struct lepus_cef_runtime *runtime) {
  if (runtime == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return runtime->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_runtime_destroy(
    struct lepus_cef_runtime *runtime) {
  if (runtime == NULL) {
    return LEPUS_CEF_STATUS_OK;
  }
  free(runtime);
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_runtime_run(
    struct lepus_cef_runtime *runtime) {
  if (runtime == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  if (runtime->status != LEPUS_CEF_STATUS_OK) {
    return runtime->status;
  }
  runtime->running = 1;
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_runtime_quit(
    struct lepus_cef_runtime *runtime) {
  if (runtime == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  runtime->running = 0;
  return runtime->status;
}

MOONBIT_FFI_EXPORT struct lepus_cef_view *lepus_cef_view_create(
    struct lepus_cef_runtime *runtime,
    moonbit_bytes_t title,
    int32_t width,
    int32_t height) {
  struct lepus_cef_view *view;

  if (runtime == NULL) {
    return NULL;
  }

  view = (struct lepus_cef_view *)malloc(sizeof(struct lepus_cef_view));
  if (view == NULL) {
    return NULL;
  }

  view->runtime = runtime;
  view->status = runtime->status;
  view->width = width;
  view->height = height;
  view->title = lepus_cef_strdup((const char *)title);
  view->bindings = NULL;
  if (view->title == NULL) {
    view->status = LEPUS_CEF_STATUS_NATIVE_ERROR;
  }
  return view;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_status(struct lepus_cef_view *view) {
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_destroy(struct lepus_cef_view *view) {
  if (view == NULL) {
    return LEPUS_CEF_STATUS_OK;
  }
  lepus_cef_free_bindings(view->bindings);
  free(view->title);
  free(view);
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int64_t lepus_cef_view_identity(struct lepus_cef_view *view) {
  return (int64_t)(intptr_t)view;
}

MOONBIT_FFI_EXPORT int64_t lepus_cef_view_native_handle(
    struct lepus_cef_view *view,
    int32_t kind) {
  (void)view;
  (void)kind;
  return 0;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_set_title(
    struct lepus_cef_view *view,
    moonbit_bytes_t title) {
  char *next_title;

  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  if (view->status != LEPUS_CEF_STATUS_OK) {
    return view->status;
  }

  next_title = lepus_cef_strdup((const char *)title);
  if (next_title == NULL) {
    return LEPUS_CEF_STATUS_NATIVE_ERROR;
  }
  free(view->title);
  view->title = next_title;
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_set_size(
    struct lepus_cef_view *view,
    int32_t width,
    int32_t height) {
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  if (view->status != LEPUS_CEF_STATUS_OK) {
    return view->status;
  }
  view->width = width;
  view->height = height;
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_set_html(
    struct lepus_cef_view *view,
    moonbit_bytes_t html) {
  (void)html;
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_navigate(
    struct lepus_cef_view *view,
    moonbit_bytes_t url) {
  (void)url;
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_init(
    struct lepus_cef_view *view,
    moonbit_bytes_t script) {
  (void)script;
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_eval(
    struct lepus_cef_view *view,
    moonbit_bytes_t script) {
  (void)script;
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_dispatch(
    struct lepus_cef_view *view,
    void (*call_closure)(struct lepus_cef_view *, void *),
    void *closure) {
  if (view == NULL) {
    if (closure != NULL) {
      moonbit_decref(closure);
    }
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  if (view->status != LEPUS_CEF_STATUS_OK) {
    if (closure != NULL) {
      moonbit_decref(closure);
    }
    return view->status;
  }
  call_closure(view, closure);
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT struct lepus_cef_binding *lepus_cef_view_bind(
    struct lepus_cef_view *view,
    moonbit_bytes_t name,
    lepus_cef_bind_callback_t callback,
    void *arg) {
  struct lepus_cef_binding *binding;

  if (view == NULL || view->status != LEPUS_CEF_STATUS_OK) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }

  binding =
      (struct lepus_cef_binding *)malloc(sizeof(struct lepus_cef_binding));
  if (binding == NULL) {
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }

  binding->name = lepus_cef_strdup((const char *)name);
  if (binding->name == NULL) {
    free(binding);
    if (arg != NULL) {
      moonbit_decref(arg);
    }
    return NULL;
  }

  binding->callback = callback;
  binding->arg = arg;
  binding->next = view->bindings;
  view->bindings = binding;
  return binding;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_unbind(
    struct lepus_cef_view *view,
    moonbit_bytes_t name,
    struct lepus_cef_binding *binding) {
  struct lepus_cef_binding **cursor;

  (void)name;

  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  if (binding == NULL) {
    return LEPUS_CEF_STATUS_OK;
  }

  cursor = &view->bindings;
  while (*cursor != NULL) {
    if (*cursor == binding) {
      *cursor = binding->next;
      lepus_cef_free_binding(binding);
      return LEPUS_CEF_STATUS_OK;
    }
    cursor = &(*cursor)->next;
  }
  return LEPUS_CEF_STATUS_OK;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_view_response(
    struct lepus_cef_view *view,
    moonbit_bytes_t seq,
    int32_t status,
    moonbit_bytes_t result) {
  (void)seq;
  (void)status;
  (void)result;
  if (view == NULL) {
    return LEPUS_CEF_STATUS_INVALID_ARGUMENT;
  }
  return view->status;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t lepus_cef_copy_cstr(void *raw_cstr) {
  const char *cstr = raw_cstr;
  moonbit_bytes_t bytes;
  size_t len;

  if (cstr == NULL) {
    bytes = moonbit_make_bytes_raw(1);
    bytes[0] = '\0';
    return bytes;
  }

  len = strlen(cstr) + 1;
  if (len > INT32_MAX) {
    abort();
  }
  bytes = moonbit_make_bytes_raw((int32_t)len);
  memcpy(bytes, cstr, len);
  return bytes;
}

MOONBIT_FFI_EXPORT int32_t lepus_cef_is_null(void *ptr) {
  return ptr == NULL;
}
