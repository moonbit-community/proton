#include "proton_native.h"
#include "proton_app_instance.h"
#include "proton_config.h"
#include "proton_engine.h"
#include "proton_internal.h"
#include "proton_state.h"

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_MSC_VER)
#define PROTON_THREAD_LOCAL __declspec(thread)
#else
#define PROTON_THREAD_LOCAL _Thread_local
#endif

/* The current source-built target, in the same vocabulary as update manifest
   platform keys. It stays native-owned because MoonBit platform cfg does not
   expose every supported architecture. */
#if defined(_WIN32)
#define PROTON_PLATFORM_ID "win32-x64"
#elif defined(__APPLE__) && defined(__aarch64__)
#define PROTON_PLATFORM_ID "darwin-arm64"
#elif defined(__APPLE__)
#define PROTON_PLATFORM_ID "darwin-x64"
#else
#define PROTON_PLATFORM_ID "linux-x64"
#endif

#define PROTON_MAX_DIALOG_TEXT_BYTES 1048576
#define PROTON_WINDOW_STATE_FIELD_COUNT 21
#define PROTON_SCREEN_FIELD_COUNT 11
#define PROTON_VIEW_STATE_FIELD_COUNT 6

typedef enum proton_host_lifecycle {
  PROTON_HOST_IDLE = 0,
  PROTON_HOST_ACTIVE = 1,
  PROTON_HOST_ENDING = 2,
} proton_host_lifecycle_t;

static proton_host_lifecycle_t g_host_lifecycle = PROTON_HOST_IDLE;
static PROTON_THREAD_LOCAL char g_last_error[512];

int32_t proton_set_error(int32_t code, const char *message) {
  if (message == NULL) {
    g_last_error[0] = '\0';
  } else {
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
  }
  return code;
}

int32_t proton_set_engine_status(int32_t status, const char *engine_error) {
  if (status < 0) {
    return proton_set_error(status, engine_error);
  }
  g_last_error[0] = '\0';
  return status;
}



static char *proton_strdup(const char *text) {
  if (text == NULL) {
    return NULL;
  }
  size_t len = strlen(text);
  char *copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, text, len + 1);
  return copy;
}

int32_t proton_abi_version(void) { return PROTON_ABI_VERSION; }

proton_runtime_handle_t proton_runtime_null(void) { return NULL; }

proton_window_handle_t proton_window_null(void) { return NULL; }

proton_view_handle_t proton_view_null(void) { return NULL; }

proton_image_handle_t proton_image_null(void) { return NULL; }

proton_event_t *proton_internal_event_null(void) { return NULL; }

int64_t proton_window_logical_id(proton_window_handle_t window) {
  return window != NULL ? window->logical_id : 0;
}

int64_t proton_view_logical_id(proton_view_handle_t view) {
  return view != NULL ? view->logical_id : 0;
}

int32_t proton_runtime_platform_id(char *buffer,
                                   int32_t buffer_len,
                                   int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  int required = (int)strlen(PROTON_PLATFORM_ID);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "runtime platform id buffer is too small");
  }
  memcpy(buffer, PROTON_PLATFORM_ID, (size_t)required + 1);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_app_instance_acquire(
    const char *identifier, const char *activation_json,
    proton_app_instance_id_t *out_instance, int32_t *out_primary) {
  char instance_error[512] = {0};
  int32_t status = proton_app_instance_acquire_impl(
      identifier, activation_json, out_instance, out_primary, instance_error,
      sizeof(instance_error));
  return proton_set_engine_status(status, instance_error);
}

int32_t proton_app_instance_attach_runtime(
    proton_app_instance_id_t instance, proton_runtime_handle_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(
        PROTON_ERR_UNSUPPORTED,
        "app instance activation requires the native engine");
  }
  if (slot->app_instance != PROTON_INVALID_HANDLE &&
      slot->app_instance != instance) {
    return proton_set_error(
        PROTON_ERR_ALREADY_INITIALIZED,
        "runtime is already attached to an app instance");
  }
  char instance_error[512] = {0};
  status = proton_app_instance_attach_runtime_impl(
      instance, slot->engine_runtime, instance_error, sizeof(instance_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, instance_error);
  }
  slot->app_instance = instance;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_app_instance_destroy(proton_app_instance_id_t instance) {
  char instance_error[512] = {0};
  int32_t status = proton_app_instance_destroy_impl(
      instance, instance_error, sizeof(instance_error));
  return proton_set_engine_status(status, instance_error);
}

int32_t proton_internal_execute_process(
    int32_t use_bundled, const char *runtime_root, const char *helper_path,
    const char *resources_dir, const char *locales_dir, const char *cache_dir,
    const char *locale, const char *accept_languages,
    const char *dialog_ok_label, const char *dialog_cancel_label,
    int32_t remote_debugging_port, int32_t headless,
    int32_t persist_session_cookies, int32_t *out_exit_code) {
  if (out_exit_code == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_exit_code is required");
  }
  proton_engine_runtime_config_t config;
  int32_t status = proton_config_prepare_runtime(
      use_bundled, runtime_root, helper_path, resources_dir, locales_dir,
      cache_dir, locale, accept_languages, dialog_ok_label,
      dialog_cancel_label, remote_debugging_port, headless,
      persist_session_cookies, &config);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_config_probe_runtime(&config);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_execute_process(&config, out_exit_code, engine_error,
                                         sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_internal_runtime_create(
    int32_t use_bundled, const char *runtime_root, const char *helper_path,
    const char *resources_dir, const char *locales_dir, const char *cache_dir,
    const char *locale, const char *accept_languages,
    const char *dialog_ok_label, const char *dialog_cancel_label,
    int32_t remote_debugging_port, int32_t headless,
    int32_t persist_session_cookies, proton_runtime_handle_t *out_runtime) {
  if (out_runtime == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_runtime is required");
  }
  *out_runtime = PROTON_INVALID_HANDLE;
  proton_engine_runtime_config_t config;
  int32_t status = proton_config_prepare_runtime(
      use_bundled, runtime_root, helper_path, resources_dir, locales_dir,
      cache_dir, locale, accept_languages, dialog_ok_label,
      dialog_cancel_label, remote_debugging_port, headless,
      persist_session_cookies, &config);
  if (status != PROTON_OK) {
    return status;
  }
  if (proton_has_active_runtime()) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "runtime is already initialized");
  }
  proton_engine_runtime_t *engine_runtime = NULL;
  char engine_error[512] = {0};
  status = proton_config_probe_runtime(&config);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_engine_runtime_create(&config, &engine_runtime, engine_error,
                                        sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  if (engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "native engine returned no runtime state");
  }

  status = proton_runtime_slot_create(engine_runtime, out_runtime);
  if (status != PROTON_OK) {
    if (engine_runtime != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_runtime_destroy(engine_runtime, engine_error,
                                          sizeof(engine_error));
    }
    return status;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_destroy(proton_runtime_handle_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime_for_destroy(runtime, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }
  proton_runtime_slot_begin_destroy(slot);

  if (slot->app_instance != PROTON_INVALID_HANDLE) {
    proton_app_instance_detach_runtime_impl(slot->app_instance);
    slot->app_instance = PROTON_INVALID_HANDLE;
  }
  status = proton_destroy_windows_for_runtime(slot);
  if (status != PROTON_OK) {
    return status;
  }
  proton_engine_cancel_resource_requests();
  if (slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_runtime_destroy(slot->engine_runtime, engine_error,
                                           sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    slot->engine_runtime = NULL;
  }
  proton_runtime_slot_destroy(slot);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_complete_resource_request(
    proton_runtime_handle_t runtime, int64_t request_id, int32_t status,
    const char *mime_type, const uint8_t *data, int32_t data_len) {
  proton_runtime_slot_t *slot = NULL;
  int32_t runtime_status = proton_get_runtime(runtime, &slot);
  if (runtime_status != PROTON_OK) {
    return runtime_status;
  }
  if (request_id <= 0 || status < 100 || status > 599 || mime_type == NULL ||
      mime_type[0] == '\0' || data_len < 0 ||
      (data == NULL && data_len > 0)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid resource response");
  }
  (void)slot;
  runtime_status = proton_engine_complete_resource_request(
      request_id, status, mime_type, data, (size_t)data_len);
  if (runtime_status == PROTON_ERR_STALE_RESOURCE_REQUEST) {
    return proton_set_error(runtime_status,
                            "resource request is no longer pending");
  }
  if (runtime_status != PROTON_OK) {
    return proton_set_error(runtime_status,
                            "failed to complete resource request");
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_host_loop_begin(void) {
  if (g_host_lifecycle != PROTON_HOST_IDLE) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "host loop is already active");
  }
  proton_event_dispatch_begin();
  char engine_error[512] = {0};
  int32_t status =
      proton_engine_host_loop_begin(engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    proton_event_dispatch_end();
    return proton_set_engine_status(status, engine_error);
  }
  g_host_lifecycle = PROTON_HOST_ACTIVE;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_host_loop_poll(int32_t timeout_ms, uint32_t *out_ready_mask) {
  if (out_ready_mask == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_ready_mask is required");
  }
  *out_ready_mask = PROTON_WAIT_NONE;
  if (timeout_ms < 0 && timeout_ms != PROTON_WAIT_TIMEOUT_INFINITE) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "timeout_ms must be non-negative or PROTON_WAIT_TIMEOUT_INFINITE");
  }
  if (g_host_lifecycle != PROTON_HOST_ACTIVE) {
    return proton_set_error(PROTON_ERR_NOT_INITIALIZED,
                            "host loop is not active");
  }
  /* No runtime handle: the loop predates the first one, and the engine walks
     its own process-wide state to decide what to pump. */
  char engine_error[512] = {0};
  uint32_t ready_mask = PROTON_WAIT_NONE;
  int32_t status = proton_engine_host_loop_poll(
      timeout_ms, &ready_mask, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  *out_ready_mask = ready_mask;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

void proton_host_loop_end(void) {
  if (g_host_lifecycle != PROTON_HOST_ACTIVE) {
    return;
  }
  g_host_lifecycle = PROTON_HOST_ENDING;
  proton_engine_host_loop_end();
  proton_event_dispatch_end();
  g_host_lifecycle = PROTON_HOST_IDLE;
}

void proton_runtime_signal_wakeup(void) {
  /* No handle lookup, and no runtime pointer passed on: every engine ignores
     the argument for this signal, and the caller is a thread that owns no
     handle. Reaching the registry from here would mean taking its lock on a
     foreign thread for a wakeup that only touches atomics and the platform
     run loop. */
  proton_engine_runtime_signal_external_event(NULL);
}

int32_t proton_internal_runtime_set_menu(proton_runtime_handle_t runtime,
                                         const proton_menu_bar_t *menu_bar) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_runtime_owner_thread(slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "runtime menu requires native engine");
  }

  char engine_error[512] = {0};
  status = proton_engine_runtime_set_menu(
      slot->engine_runtime, menu_bar, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_internal_menu_popup(proton_window_handle_t window, int32_t x,
                                   int32_t y,
                                   const proton_menu_bar_t *menu_bar) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_runtime_owner_thread(slot->runtime);
  if (status != PROTON_OK) {
    return status;
  }
  if (menu_bar == NULL || menu_bar->menu_count == 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "popup menu requires at least one menu");
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window popup menu requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_popup_menu(
      slot->engine_window, x, y, menu_bar, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_internal_runtime_poll_event(proton_runtime_handle_t runtime,
                                           proton_event_t **out_event) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_event == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_event is required");
  }
  *out_event = NULL;
  proton_runtime_sync_engine_closed_windows(slot);
  if (!proton_runtime_has_events(slot)) {
    status = proton_runtime_sync_engine_window_states(slot);
    if (status != PROTON_OK) {
      return status;
    }
    status = proton_runtime_sync_engine_close_requests(slot);
    if (status != PROTON_OK) {
      return status;
    }
  }
  proton_runtime_sync_engine_bridge_lifecycle(slot);
  *out_event = proton_runtime_poll_event(slot);
  if (*out_event == NULL) {
    return PROTON_EVENT_NONE;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_internal_event_kind(const proton_event_t *event) {
  return event == NULL ? 0 : (int32_t)event->kind;
}

int64_t proton_internal_event_int64(const proton_event_t *event,
                                    int32_t field) {
  if (event == NULL) {
    return 0;
  }
  switch (field) {
  case 0:
    return event->window;
  case 1:
    return event->view;
  case 2:
    return event->request_id;
  case 3:
    return event->revision;
  case 4:
    return event->int64_a;
  case 5:
    return event->int64_b;
  default:
    return 0;
  }
}

int32_t proton_internal_event_int(const proton_event_t *event,
                                  int32_t field) {
  if (event == NULL) {
    return 0;
  }
  switch (field) {
  case 0:
    return event->int_a;
  case 1:
    return event->int_b;
  case 2:
    return event->int_c;
  case 3:
    return event->bool_a;
  case 4:
    return event->bool_b;
  default:
    return 0;
  }
}

int32_t proton_internal_event_window_state_field(const proton_event_t *event,
                                                 int32_t field) {
  if (event == NULL) {
    return 0;
  }
  return field >= 0 && field < 21 ? event->window_state[field] : 0;
}

static int32_t proton_internal_copy_event_text(const char *text, char *buffer,
                                               int32_t buffer_len,
                                               int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  if (text == NULL) {
    *out_required_len = 0;
    return PROTON_EVENT_NONE;
  }
  int32_t required = (int32_t)strlen(text);
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "event text buffer is too small");
  }
  memcpy(buffer, text, (size_t)required + 1);
  return PROTON_OK;
}

int32_t proton_internal_event_text(const proton_event_t *event, int32_t field,
                                   char *buffer, int32_t buffer_len,
                                   int32_t *out_required_len) {
  if (event == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "event is required");
  }
  const char *text = field == 0 ? event->text_a
                     : field == 1 ? event->text_b
                     : field == 2 ? event->text_c
                                  : NULL;
  return proton_internal_copy_event_text(text, buffer, buffer_len,
                                         out_required_len);
}

int32_t proton_internal_event_item_count(const proton_event_t *event) {
  return event == NULL ? 0 : event->item_count;
}

int32_t proton_internal_event_item(const proton_event_t *event, int32_t index,
                                   char *buffer, int32_t buffer_len,
                                   int32_t *out_required_len) {
  if (event == NULL || index < 0 || index >= event->item_count) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "event item index is out of range");
  }
  return proton_internal_copy_event_text(event->items[index], buffer,
                                         buffer_len, out_required_len);
}

void proton_internal_event_destroy(proton_event_t *event) {
  proton_event_destroy(event);
}

int32_t proton_runtime_respond_bridge_request(
    proton_runtime_handle_t runtime, int64_t request_id, int32_t ok,
    const char *body_json) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (request_id <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response requires positive request_id");
  }
  if (ok != 0 && ok != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response ok must be 0 or 1");
  }
  if (body_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge response body_json is required");
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "bridge response requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_respond_bridge_request(
      slot->engine_runtime, request_id, ok, body_json, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_internal_window_create(
    proton_runtime_handle_t runtime, const char *title, int32_t width,
    int32_t height, const char *initial_url, int32_t size_hint,
    int32_t titlebar_overlay, int32_t navigation_policy,
    const char *titlebar_minimize_label, const char *titlebar_maximize_label,
    const char *titlebar_restore_label, const char *titlebar_close_label,
    int32_t popup_policy, int32_t download_policy,
    int32_t certificate_policy, int32_t media_policy, int32_t devtools,
    proton_bridge_config_t *bridge_config, proton_window_handle_t *out_window) {
  proton_runtime_slot_t *runtime_slot = NULL;
  int32_t status = proton_get_runtime(runtime, &runtime_slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_window == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_window is required");
  }
  proton_engine_window_config_t config;
  status = proton_config_prepare_window(
      title, width, height, initial_url, size_hint, titlebar_overlay,
      navigation_policy, titlebar_minimize_label, titlebar_maximize_label,
      titlebar_restore_label, titlebar_close_label, popup_policy,
      download_policy, certificate_policy, media_policy, devtools,
      bridge_config, &config);
  if (status != PROTON_OK) {
    return status;
  }
  int64_t logical_id = proton_runtime_reserve_window_id(runtime_slot);
  config.public_window = logical_id;

  proton_engine_window_t *engine_window = NULL;
  if (runtime_slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_create(runtime_slot->engine_runtime, &config,
                                         &engine_window, engine_error,
                                         sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (engine_window == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "native engine returned no window state");
    }
  }

  status = proton_window_slot_create(runtime_slot, engine_window, logical_id,
                                     width, height, out_window);
  if (status != PROTON_OK) {
    if (engine_window != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_window_destroy(engine_window, engine_error,
                                         sizeof(engine_error));
    }
    return status;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_destroy(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window_for_destroy(window, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }

  proton_runtime_slot_t *runtime = NULL;
  status = proton_get_runtime(slot->runtime, &runtime);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_begin_destroy(slot);
  proton_destroy_views_for_window(slot);
  if (slot->engine_window != NULL) {
    proton_engine_window_cookie_cleanup(slot->engine_window);
    char engine_error[512] = {0};
    status = proton_engine_window_destroy(slot->engine_window, engine_error,
                                          sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    slot->engine_window = NULL;
  }
  status = proton_window_enqueue_closed_once(runtime, slot);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_destroy(slot);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_show(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_show(slot->engine_window, engine_error,
                                       sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->visible = true;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_hide(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_hide(slot->engine_window, engine_error,
                                       sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->visible = false;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_close(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window_for_destroy(window, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->lifecycle != PROTON_WINDOW_LIVE) {
    g_last_error[0] = '\0';
    return PROTON_OK;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_close(slot->engine_window, engine_error,
                                        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    proton_window_slot_request_close(slot);
  } else {
    proton_runtime_slot_t *runtime = NULL;
    status = proton_get_runtime(slot->runtime, &runtime);
    if (status != PROTON_OK) {
      return status;
    }
    status = proton_window_enqueue_closed_once(runtime, slot);
    if (status != PROTON_OK) {
      return status;
    }
    proton_window_slot_request_close(slot);
    proton_window_slot_mark_closed(slot);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_focus(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_focus(slot->engine_window, engine_error,
                                        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_title(proton_window_handle_t window, const char *title) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (title == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "title is required");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_set_title(slot->engine_window, title,
                                            engine_error,
                                            sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_size(proton_window_handle_t window, int32_t width,
                               int32_t height) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "width and height must be positive");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_set_size(slot->engine_window, width, height,
                                           engine_error,
                                           sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->width = width;
  slot->height = height;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

static int32_t
proton_window_apply_action(proton_window_handle_t window,
                           const proton_engine_window_action_t *action) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window operation requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_apply(slot->engine_window, action,
                                      engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_minimize(proton_window_handle_t window) {
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_MINIMIZE,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_maximize(proton_window_handle_t window) {
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_MAXIMIZE,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_restore(proton_window_handle_t window) {
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_RESTORE,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_set_fullscreen(proton_window_handle_t window,
                                     int32_t fullscreen) {
  if (fullscreen != 0 && fullscreen != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "fullscreen must be 0 or 1");
  }
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_SET_FULLSCREEN,
      .value = fullscreen,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_set_position(proton_window_handle_t window,
                                   int32_t x,
                                   int32_t y) {
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_SET_POSITION,
      .x = x,
      .y = y,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_set_always_on_top(proton_window_handle_t window,
                                        int32_t always_on_top) {
  if (always_on_top != 0 && always_on_top != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "always_on_top must be 0 or 1");
  }
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP,
      .value = always_on_top,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_set_resizable(proton_window_handle_t window,
                                    int32_t resizable) {
  if (resizable != 0 && resizable != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "resizable must be 0 or 1");
  }
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_SET_RESIZABLE,
      .value = resizable,
  };
  return proton_window_apply_action(window, &action);
}

static int32_t proton_validate_size_constraint(int32_t width, int32_t height,
                                               const char *name) {
  if ((width == 0 && height == 0) || (width > 0 && height > 0)) {
    return PROTON_OK;
  }
  char message[128];
  snprintf(message, sizeof(message),
           "%s size must use two positive dimensions or (0, 0) to clear",
           name);
  return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
}

int32_t proton_window_set_minimum_size(proton_window_handle_t window,
                                       int32_t width, int32_t height) {
  int32_t status = proton_validate_size_constraint(width, height, "minimum");
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window size constraints require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_minimum_size(
      slot->engine_window, width, height, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_maximum_size(proton_window_handle_t window,
                                       int32_t width, int32_t height) {
  int32_t status = proton_validate_size_constraint(width, height, "maximum");
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window size constraints require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_maximum_size(
      slot->engine_window, width, height, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_aspect_ratio(proton_window_handle_t window,
                                       double aspect_ratio) {
  if (isnan(aspect_ratio) || aspect_ratio < 0.0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "aspect_ratio must be non-negative");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window aspect ratio requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_aspect_ratio(
      slot->engine_window, aspect_ratio, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_movable(proton_window_handle_t window,
                                  int32_t movable) {
  if (movable != 0 && movable != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "movable must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window movement requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_movable(
      slot->engine_window, movable, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_opacity(proton_window_handle_t window,
                                  double opacity) {
  if (isnan(opacity)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "opacity must not be NaN");
  }
  if (opacity < 0.0) {
    opacity = 0.0;
  } else if (opacity > 1.0) {
    opacity = 1.0;
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window opacity requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_opacity(
      slot->engine_window, opacity, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_skip_taskbar(proton_window_handle_t window,
                                       int32_t skip) {
  if (skip != 0 && skip != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "skip must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "taskbar visibility requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_skip_taskbar(
      slot->engine_window, skip, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_content_protection(proton_window_handle_t window,
                                             int32_t enabled) {
  if (enabled != 0 && enabled != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "enabled must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "content protection requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_content_protection(
      slot->engine_window, enabled, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_zoom_percent(proton_window_handle_t window,
                                       int32_t zoom_percent) {
  if (zoom_percent < 25 || zoom_percent > 500) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "zoom_percent must be between 25 and 500");
  }
  const proton_engine_window_action_t action = {
      .kind = PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT,
      .value = zoom_percent,
  };
  return proton_window_apply_action(window, &action);
}

int32_t proton_window_set_progress_bar(proton_window_handle_t window,
                                       double progress) {
  if (isnan(progress)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "progress must not be NaN");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window progress requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_progress_bar(
      slot->engine_window, progress, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_flash_frame(proton_window_handle_t window,
                                  int32_t flash) {
  if (flash != 0 && flash != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "flash must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "window attention requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_flash_frame(
      slot->engine_window, flash, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_get_state(proton_window_handle_t window,
                                int32_t *out_fields,
                                int32_t field_capacity) {
  if (out_fields == NULL || field_capacity < PROTON_WINDOW_STATE_FIELD_COUNT) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "window state field buffer is too small");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  proton_engine_window_state_t state = {
      .width = slot->width,
      .height = slot->height,
      .scale_factor_percent = 100,
      .zoom_percent = 100,
      .visible = slot->visible ? 1 : 0,
  };
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_get_state(
        slot->engine_window, &state, engine_error, sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  out_fields[0] = state.x;
  out_fields[1] = state.y;
  out_fields[2] = state.width;
  out_fields[3] = state.height;
  out_fields[4] = state.monitor_x;
  out_fields[5] = state.monitor_y;
  out_fields[6] = state.monitor_width;
  out_fields[7] = state.monitor_height;
  out_fields[8] = state.work_x;
  out_fields[9] = state.work_y;
  out_fields[10] = state.work_width;
  out_fields[11] = state.work_height;
  out_fields[12] = state.scale_factor_percent;
  out_fields[13] = state.zoom_percent;
  out_fields[14] = state.visible;
  out_fields[15] = state.focused;
  out_fields[16] = state.minimized;
  out_fields[17] = state.maximized;
  out_fields[18] = state.fullscreen;
  out_fields[19] = state.always_on_top;
  out_fields[20] = state.theme;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_screen_enumerate(int32_t *out_fields,
                                int32_t field_capacity,
                                int32_t *out_screen_count) {
  if (out_fields == NULL || out_screen_count == NULL ||
      field_capacity < PROTON_ENGINE_MAX_SCREENS * PROTON_SCREEN_FIELD_COUNT) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "screen field buffer is too small");
  }
  *out_screen_count = 0;

  proton_engine_screen_info_t screens[PROTON_ENGINE_MAX_SCREENS];
  int32_t count = 0;
  char engine_error[512] = {0};
  int32_t status = proton_engine_screen_enumerate(
      screens, PROTON_ENGINE_MAX_SCREENS, &count, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }

  for (int32_t i = 0; i < count; i++) {
    const proton_engine_screen_info_t *screen = &screens[i];
    int32_t *fields = out_fields + i * PROTON_SCREEN_FIELD_COUNT;
    fields[0] = screen->id;
    fields[1] = screen->x;
    fields[2] = screen->y;
    fields[3] = screen->width;
    fields[4] = screen->height;
    fields[5] = screen->work_x;
    fields[6] = screen->work_y;
    fields[7] = screen->work_width;
    fields[8] = screen->work_height;
    fields[9] = screen->scale_factor_percent;
    fields[10] = screen->is_primary;
  }
  *out_screen_count = count;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_set_close_interception(proton_window_handle_t window,
                                             int32_t enabled) {
  if (enabled != 0 && enabled != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "enabled must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "close interception requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_set_close_interception(
      slot->engine_window, enabled, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  if (!enabled) {
    slot->close_request_notified_revision = 0;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_respond_close_request(proton_window_handle_t window,
                                            int64_t request_id,
                                            int32_t allow) {
  if (request_id <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "request_id must be positive");
  }
  if (allow != 0 && allow != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "allow must be 0 or 1");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "close interception requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_respond_close_request(
      slot->engine_window, (uint64_t)request_id, allow, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_load_url(proton_window_handle_t window, const char *url) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (url == NULL || url[0] == '\0') {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "url is required");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_load_url(slot->engine_window, url,
                                           engine_error,
                                           sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}



int32_t proton_window_eval(proton_window_handle_t window, const char *script) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (script == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "script is required");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_eval(slot->engine_window, script,
                                       engine_error,
                                       sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_browser_command_json(proton_window_handle_t window,
                                           const char *command_json) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (command_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "browser command JSON is required");
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "browser commands require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_browser_command_json(
      slot->engine_window, command_json, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_respond_browser_request_json(
    proton_window_handle_t window, const char *response_json) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (response_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "browser response JSON is required");
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "browser responses require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_respond_browser_request_json(
      slot->engine_window, response_json, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_emit_bridge_event_json(proton_window_handle_t window,
                                              const char *event_json) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_config_validate_bridge_event(event_json);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_emit_bridge_event_json(
        slot->engine_window, event_json, engine_error, sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

static int32_t proton_require_dialog_window(proton_window_handle_t window,
                                            proton_window_slot_t **out_slot) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "native dialog requires native engine window");
  }
  *out_slot = slot;
  return PROTON_OK;
}

static int32_t proton_validate_utf8_arg(const char *label,
                                        const char *value,
                                        int32_t len) {
  if (len < 0) {
    char message[160];
    snprintf(message, sizeof(message), "%s length must not be negative", label);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  if (len > 0 && value == NULL) {
    char message[160];
    snprintf(message, sizeof(message), "%s buffer is required", label);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  if (len > PROTON_MAX_DIALOG_TEXT_BYTES) {
    char message[160];
    snprintf(message, sizeof(message), "%s is too large", label);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, message);
  }
  return PROTON_OK;
}

static int32_t proton_validate_dialog_text(const char *title_utf8,
                                           int32_t title_len,
                                           const char *message_utf8,
                                           int32_t message_len) {
  int32_t status =
      proton_validate_utf8_arg("dialog title", title_utf8, title_len);
  if (status != PROTON_OK) {
    return status;
  }
  return proton_validate_utf8_arg("dialog message", message_utf8,
                                     message_len);
}

static int32_t proton_validate_begin_dialog(int64_t *out_dialog) {
  if (out_dialog == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_dialog is required");
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  return PROTON_OK;
}

static int32_t proton_window_bridge_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len,
    int32_t (*query)(proton_engine_window_t *, char *, int32_t, int32_t *,
                     char *, size_t)) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  *out_required_len = 0;
  if (buffer_len < 0 || (buffer_len > 0 && buffer == NULL)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bridge JSON buffer is invalid");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "bridge lifecycle requires native engine");
  }
  char engine_error[512] = {0};
  status = query(slot->engine_window, buffer, buffer_len, out_required_len,
                 engine_error, sizeof(engine_error));
  if (status < 0) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return status;
}

int32_t proton_window_bridge_state_json(proton_window_handle_t window,
                                        char *buffer, int32_t buffer_len,
                                        int32_t *out_required_len) {
  return proton_window_bridge_json(window, buffer, buffer_len,
                                   out_required_len,
                                   proton_engine_window_bridge_state_json);
}

int32_t proton_window_take_bridge_failure_json(
    proton_window_handle_t window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len) {
  return proton_window_bridge_json(
      window, buffer, buffer_len, out_required_len,
      proton_engine_window_take_bridge_failure_json);
}

int32_t proton_runtime_begin_message_dialog(
    proton_runtime_handle_t runtime, const char *title_utf8, int32_t title_len,
    const char *message_utf8, int32_t message_len, int32_t level,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_dialog_text(title_utf8, title_len, message_utf8,
                                       message_len);
  if (status != PROTON_OK) {
    return status;
  }
  proton_runtime_slot_t *slot = NULL;
  status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "runtime dialog requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_begin_message_dialog(
      slot->engine_runtime, title_utf8, title_len, message_utf8, message_len,
      level, out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_notification_is_supported(int32_t *out_supported) {
  if (out_supported == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_supported is required");
  }
  *out_supported = 0;
  char engine_error[512] = {0};
  int32_t status = proton_engine_notification_is_supported(
      out_supported, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_notification_show(const char *title,
                                 const char *body,
                                 const char *payload,
                                 int32_t has_payload) {
  if (title == NULL || body == NULL || payload == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "notification text is required");
  }
  if (has_payload != 0 && has_payload != 1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "has_payload must be zero or one");
  }
  char engine_error[512] = {0};
  int32_t status = proton_engine_notification_show(
      title, body, payload, has_payload, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_notification_set_badge_count(int32_t count) {
  if (count < 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "notification badge count must be non-negative");
  }
  char engine_error[512] = {0};
  int32_t status = proton_engine_notification_set_badge_count(
      count, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_notification_cleanup(void) {
  char engine_error[512] = {0};
  int32_t status =
      proton_engine_notification_cleanup(engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_window_begin_message_dialog(
    proton_window_handle_t window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_dialog_text(
      title_utf8, title_len, message_utf8, message_len);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_begin_message_dialog(
      slot->engine_window, title_utf8, title_len, message_utf8,
      message_len, level, out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_begin_confirm_dialog(
    proton_window_handle_t window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_dialog_text(
      title_utf8, title_len, message_utf8, message_len);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_begin_confirm_dialog(
      slot->engine_window, title_utf8, title_len, message_utf8,
      message_len, level, out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_begin_open_file_dialog(
    proton_window_handle_t window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog title", title_utf8, title_len);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog path", path_utf8, path_len);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_begin_open_file_dialog(
      slot->engine_window, title_utf8, title_len, path_utf8, path_len,
      out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_begin_save_file_dialog(
    proton_window_handle_t window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog title", title_utf8, title_len);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog path", path_utf8, path_len);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_begin_save_file_dialog(
      slot->engine_window, title_utf8, title_len, path_utf8, path_len,
      out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_begin_choose_directory_dialog(
    proton_window_handle_t window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog) {
  int32_t status = proton_validate_begin_dialog(out_dialog);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog title", title_utf8, title_len);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_validate_utf8_arg("dialog path", path_utf8, path_len);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_begin_choose_directory_dialog(
      slot->engine_window, title_utf8, title_len, path_utf8, path_len,
      out_dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cancel_dialog(proton_window_handle_t window,
                                    int64_t dialog) {
  if (dialog == PROTON_INVALID_HANDLE) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "dialog id is required");
  }
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cancel_dialog(
      slot->engine_window, dialog, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_begin_get_json(proton_window_handle_t window,
                                            const char *url_utf8,
                                            int32_t include_http_only,
                                            int64_t *out_request_id) {
  if (out_request_id == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_request_id is required");
  }
  *out_request_id = PROTON_INVALID_HANDLE;
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_begin_get_json(
      slot->engine_window, url_utf8, include_http_only, out_request_id,
      engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_set(
    proton_window_handle_t window, const char *url_utf8,
    const char *name_utf8, const char *value_utf8,
    const char *domain_utf8, const char *path_utf8,
    int32_t secure, int32_t http_only, int32_t same_site) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (url_utf8 == NULL || name_utf8 == NULL || value_utf8 == NULL ||
      domain_utf8 == NULL || path_utf8 == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "cookie strings are required");
  }
  if ((secure != 0 && secure != 1) ||
      (http_only != 0 && http_only != 1) ||
      same_site < 0 || same_site > 3) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid cookie flags");
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_set(
      slot->engine_window, url_utf8, name_utf8, value_utf8, domain_utf8,
      path_utf8, secure, http_only, same_site, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_delete(proton_window_handle_t window,
                                    const char *url_utf8,
                                    const char *name_utf8) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_delete(slot->engine_window, url_utf8,
                                              name_utf8, engine_error,
                                              sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_flush(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_flush(slot->engine_window, engine_error,
                                             sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_clear_cache(proton_window_handle_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cache operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_clear_cache(slot->engine_window, engine_error,
                                            sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_internal_view_create(
    proton_window_handle_t window, int32_t x, int32_t y, int32_t width,
    int32_t height, int32_t visible, int32_t z_order, const char *initial_url,
    const char *background_color, proton_view_handle_t *out_view) {
  proton_window_slot_t *window_slot = NULL;
  int32_t status = proton_get_window(window, &window_slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_view == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_view is required");
  }
  proton_engine_view_config_t config;
  status = proton_config_prepare_view(
      x, y, width, height, visible, z_order, initial_url, background_color,
      &config);
  if (status != PROTON_OK) {
    return status;
  }

  proton_runtime_slot_t *runtime_slot = NULL;
  status = proton_get_runtime(window_slot->runtime, &runtime_slot);
  if (status != PROTON_OK) {
    return status;
  }
  int64_t logical_id = proton_runtime_reserve_view_id(runtime_slot);
  config.public_window = window_slot->logical_id;
  config.public_view = logical_id;

  proton_engine_view_t *engine_view = NULL;
  if (window_slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_create(
        window_slot->engine_window, &config, &engine_view, engine_error,
        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (engine_view == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "native engine returned no view state");
    }
  }

  status = proton_view_slot_create(
      window_slot, engine_view, logical_id, config.x, config.y, config.width,
      config.height, config.z_order, config.visible != 0, out_view);
  if (status != PROTON_OK) {
    if (engine_view != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_view_destroy(engine_view, engine_error,
                                       sizeof(engine_error));
    }
    return status;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_destroy(proton_view_handle_t view) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view_for_destroy(view, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }
  proton_view_slot_begin_destroy(slot);
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_destroy(slot->engine_view, engine_error,
                                        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  proton_view_slot_destroy(slot);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_set_bounds(proton_view_handle_t view, int32_t x, int32_t y,
                               int32_t width, int32_t height) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "view width and height must be positive");
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_set_bounds(slot->engine_view, x, y, width,
                                           height, engine_error,
                                           sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->x = x;
  slot->y = y;
  slot->width = width;
  slot->height = height;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_set_visible(proton_view_handle_t view, int32_t visible) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_set_visible(slot->engine_view, visible,
                                            engine_error,
                                            sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->visible = visible != 0;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_set_z_order(proton_view_handle_t view, int32_t z_order) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_set_z_order(slot->engine_view, z_order,
                                            engine_error,
                                            sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->z_order = z_order;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_load_url(proton_view_handle_t view, const char *url) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (url == NULL || url[0] == '\0') {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "url is required");
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_load_url(slot->engine_view, url, engine_error,
                                         sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_eval(proton_view_handle_t view, const char *script) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (script == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT, "script is required");
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_eval(slot->engine_view, script, engine_error,
                                     sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_browser_command_json(proton_view_handle_t view,
                                         const char *command_json) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (command_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "browser command JSON is required");
  }
  if (slot->engine_view == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "browser commands require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_view_browser_command_json(
      slot->engine_view, command_json, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_view_get_state(proton_view_handle_t view,
                              int32_t *out_fields,
                              int32_t field_capacity) {
  if (out_fields == NULL || field_capacity < PROTON_VIEW_STATE_FIELD_COUNT) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "view state field buffer is too small");
  }
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  out_fields[0] = slot->x;
  out_fields[1] = slot->y;
  out_fields[2] = slot->width;
  out_fields[3] = slot->height;
  out_fields[4] = slot->visible ? 1 : 0;
  out_fields[5] = slot->z_order;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

/* ------------------------------------------------------------------ */
/* Native image ABI                                                   */
/* ------------------------------------------------------------------ */

int32_t proton_image_create_empty(proton_image_handle_t *out_image) {
  if (out_image == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_image is required");
  }
  *out_image = PROTON_INVALID_HANDLE;
  char engine_error[512] = {0};
  proton_engine_image_t *engine_image = NULL;
  int32_t status = proton_engine_image_create(&engine_image, engine_error,
                                              sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  proton_image_handle_t handle = PROTON_INVALID_HANDLE;
  status = proton_image_slot_create(engine_image, &handle);
  if (status != PROTON_OK) {
    proton_engine_image_release(engine_image);
    return status;
  }
  *out_image = handle;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_image_destroy(proton_image_handle_t image) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_image != NULL) {
    proton_engine_image_release(slot->engine_image);
  }
  proton_image_slot_destroy(slot);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_image_add_png(proton_image_handle_t image, const uint8_t *data,
                             int32_t data_len, float scale_factor) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (data == NULL || data_len <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "png data is required");
  }
  char engine_error[512] = {0};
  status = proton_engine_image_add_png(slot->engine_image, data,
                                       (size_t)data_len, scale_factor,
                                       engine_error, sizeof(engine_error));
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_image_add_jpeg(proton_image_handle_t image, const uint8_t *data,
                              int32_t data_len, float scale_factor) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (data == NULL || data_len <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "jpeg data is required");
  }
  char engine_error[512] = {0};
  status = proton_engine_image_add_jpeg(slot->engine_image, data,
                                        (size_t)data_len, scale_factor,
                                        engine_error, sizeof(engine_error));
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_image_add_bitmap(proton_image_handle_t image, const uint8_t *data,
                                int32_t data_len, int32_t width,
                                int32_t height, float scale_factor) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (data == NULL || data_len <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bitmap data is required");
  }
  if (width <= 0 || height <= 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "bitmap dimensions must be positive");
  }
  char engine_error[512] = {0};
  status = proton_engine_image_add_bitmap(slot->engine_image, data,
                                          (size_t)data_len, width, height,
                                          scale_factor, engine_error,
                                          sizeof(engine_error));
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_image_is_empty(proton_image_handle_t image) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  int32_t empty = 1;
  char engine_error[512] = {0};
  status = proton_engine_image_is_empty(slot->engine_image, &empty,
                                        engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return empty ? 1 : 0;
}

int32_t proton_image_get_size(proton_image_handle_t image,
                              int32_t *out_width,
                              int32_t *out_height) {
  if (out_width == NULL || out_height == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "image size outputs are required");
  }
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_image_get_size(slot->engine_image, out_width,
                                        out_height, engine_error,
                                        sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_image_to_png(proton_image_handle_t image, float scale_factor,
                            int32_t with_transparency, uint8_t *buffer,
                            int32_t buffer_len, int32_t *out_required_len,
                            int32_t *out_width, int32_t *out_height) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (out_width != NULL) {
    *out_width = 0;
  }
  if (out_height != NULL) {
    *out_height = 0;
  }
  char engine_error[512] = {0};
  status = proton_engine_image_to_png(slot->engine_image, scale_factor,
                                      with_transparency, buffer, buffer_len,
                                      out_required_len, out_width, out_height,
                                      engine_error, sizeof(engine_error));
  if (status == PROTON_ERR_BUFFER_TOO_SMALL) {
    /* Buffer-too-small is a normal two-call flow: return the status without
       clobbering last_error so callers can retry. */
    return status;
  }
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_image_to_jpeg(proton_image_handle_t image, float scale_factor,
                             int32_t quality, uint8_t *buffer,
                             int32_t buffer_len, int32_t *out_required_len,
                             int32_t *out_width, int32_t *out_height) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (out_width != NULL) {
    *out_width = 0;
  }
  if (out_height != NULL) {
    *out_height = 0;
  }
  char engine_error[512] = {0};
  status = proton_engine_image_to_jpeg(slot->engine_image, scale_factor,
                                       quality, buffer, buffer_len,
                                       out_required_len, out_width, out_height,
                                       engine_error, sizeof(engine_error));
  if (status == PROTON_ERR_BUFFER_TOO_SMALL) {
    return status;
  }
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_image_to_bitmap(proton_image_handle_t image, float scale_factor,
                               uint8_t *buffer, int32_t buffer_len,
                               int32_t *out_required_len,
                               int32_t *out_width, int32_t *out_height) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  if (out_width != NULL) {
    *out_width = 0;
  }
  if (out_height != NULL) {
    *out_height = 0;
  }
  char engine_error[512] = {0};
  status = proton_engine_image_to_bitmap(
      slot->engine_image, scale_factor, buffer, buffer_len, out_required_len,
      out_width, out_height, engine_error, sizeof(engine_error));
  if (status == PROTON_ERR_BUFFER_TOO_SMALL) {
    return status;
  }
  return status == PROTON_OK
             ? (g_last_error[0] = '\0', PROTON_OK)
             : proton_set_engine_status(status, engine_error);
}

int32_t proton_last_error_message(char *buffer, int32_t buffer_len) {
  int32_t required = (int32_t)strlen(g_last_error);
  if (buffer == NULL || buffer_len <= 0) {
    return required;
  }
  if (buffer_len == 1) {
    buffer[0] = '\0';
    return required;
  }

  int32_t copy_len = required;
  if (copy_len > buffer_len - 1) {
    copy_len = buffer_len - 1;
  }
  memcpy(buffer, g_last_error, (size_t)copy_len);
  buffer[copy_len] = '\0';
  return required;
}
