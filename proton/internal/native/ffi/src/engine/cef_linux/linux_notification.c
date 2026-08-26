#if defined(__linux__)

#include "../../proton_engine.h"

#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int (*proton_notify_init_t)(const char *);
typedef void *(*proton_notification_new_t)(const char *, const char *, const char *);
typedef int (*proton_notification_show_t)(void *, void **);
typedef void (*proton_notification_set_timeout_t)(void *, int);
typedef void (*proton_g_object_unref_t)(void *);
typedef int (*proton_g_type_init_t)(void);

static void *g_notify_lib = NULL;
static void *g_gobject_lib = NULL;
static proton_notify_init_t g_notify_init = NULL;
static proton_notification_new_t g_notify_new = NULL;
static proton_notification_show_t g_notify_show = NULL;
static proton_notification_set_timeout_t g_notify_set_timeout = NULL;
static proton_g_object_unref_t g_g_object_unref = NULL;
static int32_t g_notify_initialized = 0;
static int32_t g_notify_probe_attempted = 0;
static int32_t g_notify_probe_ok = 0;

static void proton_notification_set_message(char *error,
                                            size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message);
  }
}

// Loads libgobject/libnotify and resolves the required symbols. This does NOT
// call notify_init, which requires a notification daemon that may be absent in
// headless/CI environments; loading the libraries is enough to report the
// capability as supported (notifications are just silently dropped when no
// daemon is present).
static int32_t proton_notification_load_libraries(char *error,
                                                  size_t error_len) {
  if (g_notify_lib != NULL) {
    return PROTON_OK;
  }
  g_gobject_lib = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (g_gobject_lib == NULL) {
    proton_notification_set_message(
        error, error_len,
        "libgobject-2.0.so.0 is required for notifications");
    return PROTON_ERR_UNSUPPORTED;
  }
  g_notify_lib = dlopen("libnotify.so.4", RTLD_NOW);
  if (g_notify_lib == NULL) {
    g_notify_lib = dlopen("libnotify.so", RTLD_NOW);
  }
  if (g_notify_lib == NULL) {
    proton_notification_set_message(
        error, error_len,
        "libnotify is required for notifications on Linux");
    dlclose(g_gobject_lib);
    g_gobject_lib = NULL;
    return PROTON_ERR_UNSUPPORTED;
  }
  g_notify_init = (proton_notify_init_t)dlsym(g_notify_lib, "notify_init");
  g_notify_new = (proton_notification_new_t)dlsym(g_notify_lib, "notify_notification_new");
  g_notify_show = (proton_notification_show_t)dlsym(g_notify_lib, "notify_notification_show");
  g_notify_set_timeout = (proton_notification_set_timeout_t)dlsym(g_notify_lib, "notify_notification_set_timeout");
  g_g_object_unref = (proton_g_object_unref_t)dlsym(g_gobject_lib, "g_object_unref");
  if (g_notify_init == NULL || g_notify_new == NULL || g_notify_show == NULL ||
      g_g_object_unref == NULL) {
    proton_notification_set_message(
        error, error_len,
        "libnotify symbols could not be resolved");
    dlclose(g_notify_lib);
    dlclose(g_gobject_lib);
    g_notify_lib = NULL;
    g_gobject_lib = NULL;
    return PROTON_ERR_UNSUPPORTED;
  }
  proton_g_type_init_t g_type_init =
      (proton_g_type_init_t)dlsym(g_gobject_lib, "g_type_init");
  if (g_type_init != NULL) {
    g_type_init();
  }
  return PROTON_OK;
}

// Runs the capability probe once; subsequent calls return the cached result
// so is_supported does not re-attempt loading after a failure.
static int32_t proton_notification_probe_supported(char *error,
                                                   size_t error_len) {
  if (g_notify_probe_attempted) {
    return g_notify_probe_ok ? PROTON_OK : PROTON_ERR_UNSUPPORTED;
  }
  g_notify_probe_attempted = 1;
  int32_t status = proton_notification_load_libraries(error, error_len);
  g_notify_probe_ok = (status == PROTON_OK);
  return status;
}

static int32_t proton_notification_load_libnotify(char *error,
                                                  size_t error_len) {
  int32_t status = proton_notification_load_libraries(error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  if (!g_notify_init("proton")) {
    proton_notification_set_message(error, error_len,
                                    "notify_init failed");
    dlclose(g_notify_lib);
    dlclose(g_gobject_lib);
    g_notify_lib = NULL;
    g_gobject_lib = NULL;
    return PROTON_ERR_PLATFORM;
  }
  g_notify_initialized = 1;
  return PROTON_OK;
}

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len) {
  if (g_notify_initialized) {
    if (out_supported != NULL) {
      *out_supported = 1;
    }
    return PROTON_OK;
  }
  int32_t status = proton_notification_probe_supported(error, error_len);
  if (out_supported != NULL) {
    *out_supported = (status == PROTON_OK) ? 1 : 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_show(const char *title_utf8,
                                        const char *body_utf8,
                                        const char *payload_utf8,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len) {
  (void)payload_utf8;
  (void)has_payload;
  if (title_utf8 == NULL || body_utf8 == NULL) {
    proton_notification_set_message(error, error_len,
                                    "notification title and body are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int32_t load_status = proton_notification_load_libnotify(error, error_len);
  if (load_status != PROTON_OK) {
    return load_status;
  }
  void *notification =
      g_notify_new(title_utf8, body_utf8, "dialog-information");
  if (notification == NULL) {
    proton_notification_set_message(error, error_len,
                                    "notify_notification_new returned NULL");
    return PROTON_ERR_PLATFORM;
  }
  if (g_notify_set_timeout != NULL) {
    g_notify_set_timeout(notification, 5000);
  }
  void *gerror = NULL;
  int shown = g_notify_show(notification, &gerror);
  g_g_object_unref(notification);
  if (!shown) {
    proton_notification_set_message(
        error, error_len,
        "notify_notification_show failed");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_set_badge_count(int32_t count,
                                                   char *error,
                                                   size_t error_len) {
  (void)count;
  proton_notification_set_message(
      error, error_len,
      "application badge counts are not implemented on Linux");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_notification_cleanup(char *error, size_t error_len) {
  (void)error;
  (void)error_len;
  if (g_notify_initialized) {
    void (*notify_uninit)(void) =
        (void (*)(void))dlsym(g_notify_lib, "notify_uninit");
    if (notify_uninit != NULL) {
      notify_uninit();
    }
    g_notify_initialized = 0;
  }
  if (g_notify_lib != NULL) {
    dlclose(g_notify_lib);
    g_notify_lib = NULL;
  }
  if (g_gobject_lib != NULL) {
    dlclose(g_gobject_lib);
    g_gobject_lib = NULL;
  }
  g_notify_init = NULL;
  g_notify_new = NULL;
  g_notify_show = NULL;
  g_notify_set_timeout = NULL;
  g_g_object_unref = NULL;
  return PROTON_OK;
}

#endif
