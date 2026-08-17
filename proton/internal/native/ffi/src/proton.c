#include "proton_native.h"
#include "proton_app_instance.h"
#include "proton_config.h"
#include "proton_engine.h"
#include "proton_internal.h"
#include "proton_state.h"

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

#ifndef PROTON_WITH_ENGINE
#define PROTON_WITH_ENGINE 0
#endif

#ifdef _WIN32
#define PROTON_PLATFORM_NAME "windows"
#elif defined(__APPLE__)
#define PROTON_PLATFORM_NAME "macos"
#else
#define PROTON_PLATFORM_NAME "linux"
#endif

/* The prebuilt this library was built as, in the same vocabulary as
   `proton/prebuilt/<id>/` and the update manifest's platform keys.

   It is reported rather than derived by the caller because this library is the
   platform-specific artifact: anything reconstructing the pair from a platform
   name and a CPU query is guessing at what this file already knows. */
#if defined(_WIN32)
#define PROTON_PLATFORM_ID "win32-x64"
#elif defined(__APPLE__) && defined(__aarch64__)
#define PROTON_PLATFORM_ID "darwin-arm64"
#elif defined(__APPLE__)
#define PROTON_PLATFORM_ID "darwin-x64"
#else
#define PROTON_PLATFORM_ID "linux-x64"
#endif

#if PROTON_WITH_ENGINE && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__))
#define PROTON_RUNTIME_WAIT_FEATURE ",\"runtime_wait\""
#else
#define PROTON_RUNTIME_WAIT_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__))
#define PROTON_TITLEBAR_OVERLAY_FEATURE ",\"titlebar_overlay\""
#define PROTON_HEADLESS_OSR_FEATURE ",\"headless_osr\""
#define PROTON_WINDOW_SIZE_HINTS_FEATURE ",\"window_size_hints\""
#define PROTON_WINDOW_SESSION_FEATURE ",\"window_session\""
#define PROTON_BROWSER_SESSION_FEATURE ",\"browser_session\""
#else
#define PROTON_TITLEBAR_OVERLAY_FEATURE ""
#define PROTON_HEADLESS_OSR_FEATURE ""
#define PROTON_WINDOW_SIZE_HINTS_FEATURE ""
#define PROTON_WINDOW_SESSION_FEATURE ""
#define PROTON_BROWSER_SESSION_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && defined(__APPLE__)
#define PROTON_RUNTIME_WAKEUP_FD_FEATURE ",\"runtime_wakeup_fd\""
#define PROTON_RUNTIME_WAKEUP_SOURCE_FEATURE ""
#elif PROTON_WITH_ENGINE && defined(_WIN32)
#define PROTON_RUNTIME_WAKEUP_FD_FEATURE ""
#define PROTON_RUNTIME_WAKEUP_SOURCE_FEATURE ",\"runtime_wakeup_source\""
#else
#define PROTON_RUNTIME_WAKEUP_FD_FEATURE ""
#define PROTON_RUNTIME_WAKEUP_SOURCE_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && \
    (defined(__APPLE__) || defined(__linux__) || defined(_WIN32))
#define PROTON_APP_SINGLE_INSTANCE_FEATURE ",\"app_single_instance\""
#else
#define PROTON_APP_SINGLE_INSTANCE_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && \
    (defined(__APPLE__) || defined(_WIN32) || defined(__linux__))
#define PROTON_WEB_CONTENTS_VIEW_FEATURE ",\"web_contents_view\""
#define PROTON_NATIVE_IMAGE_FEATURE ",\"native_image\""
#else
#define PROTON_WEB_CONTENTS_VIEW_FEATURE ""
#define PROTON_NATIVE_IMAGE_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && defined(__APPLE__)
#define PROTON_NOTIFICATION_RESULT_FEATURE ",\"notification_result\""
#else
#define PROTON_NOTIFICATION_RESULT_FEATURE ""
#endif

#define PROTON_MAX_DIALOG_TEXT_BYTES 1048576

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

// Drain app-menu commands assigned to this runtime into its event queue.
// Take from the engine queue only when the public queue has room, so a full
// queue defers delivery instead of dropping commands.
static void proton_runtime_sync_menu_commands(proton_runtime_slot_t *runtime) {
  while (proton_event_queue_count(&runtime->events) <
         PROTON_EVENT_QUEUE_CAPACITY) {
    char command_id[PROTON_MAX_EVENT_BYTES];
    proton_window_id_t focused_window = PROTON_INVALID_HANDLE;
    int32_t present = 0;
    if (proton_engine_take_menu_command(
            runtime->engine_runtime, command_id, sizeof(command_id),
            &focused_window, &present) != PROTON_OK ||
        present == 0) {
      return;
    }
    proton_event_t *event = proton_event_create(PROTON_EVENT_MENU_COMMAND);
    if (event == NULL ||
        !proton_event_set_text(&event->text_a, command_id)) {
      proton_event_destroy(event);
      return;
    }
    event->window = focused_window;
    if (!proton_runtime_enqueue_event(runtime, event)) {
      return;
    }
  }
}

// Drain platform-originated events into the ordered runtime event queue.
// Take from the engine queue only when the public queue has room, so a full
// queue defers delivery instead of dropping events.
static void proton_runtime_sync_platform_events(proton_runtime_slot_t *runtime) {
  while (proton_event_queue_count(&runtime->events) <
         PROTON_EVENT_QUEUE_CAPACITY) {
    proton_event_t *event =
        proton_engine_take_platform_event(runtime->engine_runtime);
    if (event == NULL) {
      return;
    }
    if (!proton_runtime_enqueue_event(runtime, event)) {
      return;
    }
  }
}

// Move renderer cancellations onto the owner-thread runtime event queue.
static void proton_runtime_sync_bridge_cancellations(
    proton_runtime_slot_t *runtime) {
  while (proton_event_queue_count(&runtime->events) <
         PROTON_EVENT_QUEUE_CAPACITY) {
    int64_t request_id = 0;
    int32_t present = 0;
    char engine_error[512] = {0};
    if (proton_engine_runtime_poll_bridge_cancellation(
            runtime->engine_runtime, &request_id, &present, engine_error,
            sizeof(engine_error)) != PROTON_OK ||
        present == 0) {
      return;
    }
    proton_event_t *event =
        proton_event_create(PROTON_EVENT_BRIDGE_REQUEST_CANCELLED);
    if (event == NULL) {
      return;
    }
    event->request_id = request_id;
    if (!proton_runtime_enqueue_event(runtime, event)) {
      return;
    }
  }
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

int32_t proton_runtime_info_json(char *buffer,
                                 int32_t buffer_len,
                                 int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  char info[512];
  int required = snprintf(
      info, sizeof(info),
      "{\"abi_version\":%d,\"runtime_available\":%s,"
      "\"build_mode\":\"%s\",\"platform\":\"%s\","
      "\"platform_id\":\"%s\","
      "\"features\":[\"base_abi\",\"event_polling\",\"bridge_polling\","
      "\"bridge_permission_grants\""
      PROTON_RUNTIME_WAIT_FEATURE PROTON_TITLEBAR_OVERLAY_FEATURE
          PROTON_HEADLESS_OSR_FEATURE
          PROTON_WINDOW_SIZE_HINTS_FEATURE
          PROTON_WINDOW_SESSION_FEATURE
          PROTON_BROWSER_SESSION_FEATURE
          PROTON_APP_SINGLE_INSTANCE_FEATURE
          PROTON_RUNTIME_WAKEUP_FD_FEATURE
          PROTON_RUNTIME_WAKEUP_SOURCE_FEATURE
          PROTON_WEB_CONTENTS_VIEW_FEATURE PROTON_NATIVE_IMAGE_FEATURE
              PROTON_NOTIFICATION_RESULT_FEATURE
              "]}",
      PROTON_ABI_VERSION, PROTON_WITH_ENGINE ? "true" : "false",
      PROTON_WITH_ENGINE ? "runtime" : "abi-only", PROTON_PLATFORM_NAME,
      PROTON_PLATFORM_ID);
  if (required < 0 || required >= (int)sizeof(info)) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "runtime info buffer is too small internally");
  }
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "runtime info buffer is too small");
  }
  memcpy(buffer, info, (size_t)required + 1);
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

int32_t proton_internal_runtime_probe(
    int32_t use_bundled, const char *runtime_root, const char *helper_path,
    const char *resources_dir, const char *locales_dir, const char *cache_dir,
    const char *locale, const char *accept_languages,
    const char *dialog_ok_label, const char *dialog_cancel_label,
    int32_t remote_debugging_port, int32_t headless,
    int32_t persist_session_cookies) {
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
  g_last_error[0] = '\0';
  return PROTON_OK;
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

int32_t proton_runtime_do_message_loop_work(proton_runtime_handle_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_runtime_owner_thread(slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_runtime_do_message_loop_work(
        slot->engine_runtime, engine_error, sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_wait(proton_runtime_handle_t runtime,
                            uint32_t interest_mask,
                            int32_t timeout_ms,
                            uint32_t *out_ready_mask) {
  if (out_ready_mask == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_ready_mask is required");
  }
  /* Any negative value is an elapsed deadline rather than a request to wait
     forever; only the documented constant means that. Collapsing the two here
     would turn an arithmetic slip into a hang. */
  if (timeout_ms < 0 && timeout_ms != PROTON_WAIT_TIMEOUT_INFINITE) {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "timeout_ms must be non-negative or PROTON_WAIT_TIMEOUT_INFINITE");
  }
  *out_ready_mask = PROTON_WAIT_NONE;
  if (interest_mask == PROTON_WAIT_NONE) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "interest_mask is required");
  }
  if ((interest_mask & ~PROTON_WAIT_ALL) != 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "interest_mask contains unsupported bits");
  }

  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_runtime_owner_thread(slot);
  if (status != PROTON_OK) {
    return status;
  }
  uint32_t ready_mask = PROTON_WAIT_NONE;
  if ((interest_mask & PROTON_WAIT_EVENT) != 0) {
    proton_runtime_sync_engine_closed_windows(slot);
    proton_runtime_sync_bridge_cancellations(slot);
    proton_runtime_sync_menu_commands(slot);
    if (proton_runtime_has_events(slot)) {
      ready_mask |= PROTON_WAIT_EVENT;
    }
  }
  if (ready_mask != PROTON_WAIT_NONE) {
    *out_ready_mask = ready_mask;
    g_last_error[0] = '\0';
    return PROTON_OK;
  }

  uint32_t engine_interest =
      interest_mask & (PROTON_WAIT_BRIDGE | PROTON_WAIT_PLATFORM);
  if (engine_interest == PROTON_WAIT_NONE) {
    g_last_error[0] = '\0';
    return PROTON_OK;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "runtime wait requires native engine");
  }

  char engine_error[512] = {0};
  uint32_t engine_ready = PROTON_WAIT_NONE;
  status = proton_engine_runtime_wait(slot->engine_runtime, engine_interest,
                                      timeout_ms, &engine_ready, engine_error,
                                      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  ready_mask = engine_ready & engine_interest;
  if ((interest_mask & PROTON_WAIT_EVENT) != 0) {
    proton_runtime_sync_bridge_cancellations(slot);
    if (proton_runtime_has_events(slot)) {
      ready_mask |= PROTON_WAIT_EVENT;
    }
  }
  *out_ready_mask = ready_mask;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_host_loop_begin(void) {
  if (g_host_lifecycle != PROTON_HOST_IDLE) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "host loop is already active");
  }
  char engine_error[512] = {0};
  int32_t status =
      proton_engine_host_loop_begin(engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
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

int32_t proton_runtime_set_wakeup_fd(proton_runtime_handle_t runtime,
                                     int32_t wakeup_fd) {
  if (wakeup_fd < -1) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "wakeup_fd must be -1 or a valid descriptor");
  }
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
                            "runtime wakeup fd requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_set_wakeup_fd(
      slot->engine_runtime, wakeup_fd, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_runtime_prepare_wakeup_source(
    proton_runtime_handle_t runtime, char *buffer, int32_t buffer_len,
    int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  *out_required_len = 0;
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "runtime wakeup source requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_prepare_wakeup_source(
      slot->engine_runtime, buffer, buffer_len, out_required_len, engine_error,
      sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t
proton_runtime_activate_wakeup_source(proton_runtime_handle_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "runtime wakeup source requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_activate_wakeup_source(
      slot->engine_runtime, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
}

int32_t proton_runtime_next_wakeup_delay_ms(proton_runtime_handle_t runtime,
                                            int64_t *out_delay_ms) {
  if (out_delay_ms == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_delay_ms is required");
  }
  *out_delay_ms = -1;
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
                            "runtime wakeup delay requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_next_wakeup_delay_ms(
      slot->engine_runtime, out_delay_ms, engine_error, sizeof(engine_error));
  return proton_set_engine_status(status, engine_error);
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
  proton_runtime_sync_bridge_cancellations(slot);
  proton_runtime_sync_menu_commands(slot);
  proton_runtime_sync_platform_events(slot);
  if (slot->app_instance != PROTON_INVALID_HANDLE) {
    while (proton_event_queue_count(&slot->events) <
           PROTON_EVENT_QUEUE_CAPACITY) {
      char instance_error[512] = {0};
      proton_event_t *event = proton_app_instance_take_event_impl(
          slot->app_instance, instance_error, sizeof(instance_error));
      if (event == NULL) {
        break;
      }
      if (!proton_runtime_enqueue_event(slot, event)) {
        return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                                "failed to queue app activation event");
      }
    }
  }
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

int32_t proton_runtime_poll_bridge_request_json(proton_runtime_handle_t runtime,
                                                char *buffer,
                                                int32_t buffer_len,
                                                int32_t *out_required_len) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  if (slot->engine_runtime == NULL) {
    (void)buffer;
    (void)buffer_len;
    *out_required_len = 0;
    g_last_error[0] = '\0';
    return PROTON_EVENT_NONE;
  }

  char engine_error[512] = {0};
  status = proton_engine_runtime_poll_bridge_request_json(
      slot->engine_runtime, buffer, buffer_len, out_required_len, engine_error,
      sizeof(engine_error));
  if (status < 0) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return status;
}

int32_t proton_runtime_respond_bridge_request_json(
    proton_runtime_handle_t runtime,
    const char *response_json) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_config_validate_bridge_response(response_json);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "bridge response requires native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_runtime_respond_bridge_request_json(
      slot->engine_runtime, response_json, engine_error, sizeof(engine_error));
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

  status = proton_window_slot_create(runtime_slot, engine_window, width,
                                    height, out_window);
  if (status != PROTON_OK) {
    if (engine_window != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_window_destroy(engine_window, engine_error,
                                         sizeof(engine_error));
    }
    return status;
  }
  if (engine_window != NULL) {
    proton_engine_window_bind_public_id(engine_window,
                                        (*out_window)->logical_id);
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
  if (!slot->closed_event_sent &&
      proton_event_queue_count(&runtime->events) >=
          PROTON_EVENT_QUEUE_CAPACITY) {
    return proton_set_error(PROTON_ERR_QUEUE_FAILED,
                            "failed to queue window_closed event");
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

int32_t proton_window_state_json(proton_window_handle_t window,
                                 char *buffer,
                                 int32_t buffer_len,
                                 int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  *out_required_len = 0;
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
  char json[1024];
  int written = proton_format_window_state_json(&state, json, sizeof(json));
  if (written < 0 || written >= (int)sizeof(json)) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "window state payload is too large");
  }
  *out_required_len = written;
  if (buffer == NULL || buffer_len <= written) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "window state buffer is too small");
  }
  memcpy(buffer, json, (size_t)written + 1);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_screen_enumerate_json(char *buffer,
                                     int32_t buffer_len,
                                     int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  *out_required_len = 0;

  proton_engine_screen_info_t screens[PROTON_ENGINE_MAX_SCREENS];
  int32_t count = 0;
  char engine_error[512] = {0};
  int32_t status = proton_engine_screen_enumerate(
      screens, PROTON_ENGINE_MAX_SCREENS, &count, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }

  char json[4096];
  int written =
      proton_format_screen_array_json(screens, count, json, sizeof(json));
  if (written < 0 || written >= (int)sizeof(json)) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "screen enumeration payload is too large");
  }
  *out_required_len = written;
  if (buffer == NULL || buffer_len <= written) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "screen enumeration buffer is too small");
  }
  memcpy(buffer, json, (size_t)written + 1);
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

int32_t proton_window_load_html(proton_window_handle_t window, const char *html,
                                const char *base_url) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (html == NULL || base_url == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "html and base_url are required");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_load_html(slot->engine_window, html, base_url,
                                            engine_error,
                                            sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_load_asset(proton_window_handle_t window, const char *html,
                                 const char *document_url,
                                 const char *asset_root) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (html == NULL || document_url == NULL || document_url[0] == '\0' ||
      asset_root == NULL || asset_root[0] == '\0') {
    return proton_set_error(
        PROTON_ERR_INVALID_ARGUMENT,
        "html, document_url, and asset_root are required");
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_load_asset(
        slot->engine_window, html, document_url, asset_root, engine_error,
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

static int32_t proton_validate_poll_dialog_result_args(
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len) {
  if (dialog == PROTON_INVALID_HANDLE) {
    return proton_set_error(PROTON_ERR_INVALID_HANDLE,
                            "invalid dialog handle");
  }
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  *out_required_len = 0;
  if (buffer_len < 0) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "dialog result buffer length must not be negative");
  }
  if (buffer_len > 0 && buffer == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "dialog result buffer is required");
  }
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

int32_t proton_runtime_poll_dialog_result(
    proton_runtime_handle_t runtime, int64_t dialog, char *buffer,
    int32_t buffer_len, int32_t *out_required_len) {
  int32_t status = proton_validate_poll_dialog_result_args(
      dialog, buffer, buffer_len, out_required_len);
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
  status = proton_engine_runtime_poll_dialog_result(
      slot->engine_runtime, dialog, buffer, buffer_len, out_required_len,
      engine_error, sizeof(engine_error));
  if (status < 0) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return status;
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

int32_t proton_notification_poll_click(
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len,
    int32_t *out_has_payload,
    int32_t *out_available) {
  if (buffer_len < 0 || (buffer == NULL && buffer_len != 0) ||
      out_required_len == NULL || out_has_payload == NULL ||
      out_available == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid notification click output");
  }
  *out_required_len = 0;
  *out_has_payload = 0;
  *out_available = 0;
  char engine_error[512] = {0};
  int32_t status = proton_engine_notification_poll_click(
      buffer, buffer_len, out_required_len, out_has_payload, out_available,
      engine_error, sizeof(engine_error));
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

int32_t proton_window_poll_dialog_result(
    proton_window_handle_t window,
    int64_t dialog,
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required_len) {
  int32_t status = proton_validate_poll_dialog_result_args(
      dialog, buffer, buffer_len, out_required_len);
  if (status != PROTON_OK) {
    return status;
  }
  proton_window_slot_t *slot = NULL;
  status = proton_require_dialog_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_poll_dialog_result(
      slot->engine_window, dialog, buffer, buffer_len, out_required_len,
      engine_error, sizeof(engine_error));
  if (status < 0) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return status;
}

int32_t proton_window_cookie_begin_get_json(proton_window_handle_t window,
                                            const char *url_utf8,
                                            int32_t include_http_only) {
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
      slot->engine_window, url_utf8, include_http_only, engine_error,
      sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_poll_get_json(proton_window_handle_t window,
                                           char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  if (out_required_len != NULL) {
    *out_required_len = 0;
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_poll_get_json(
      slot->engine_window, buffer, buffer_len, out_required_len, engine_error,
      sizeof(engine_error));
  if (status == PROTON_ERR_PENDING) {
    return PROTON_ERR_PENDING;
  }
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_cookie_set_json(proton_window_handle_t window,
                                      const char *cookie_json) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (cookie_json == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "cookie JSON is required");
  }
  if (slot->engine_window == NULL) {
    return proton_set_error(PROTON_ERR_UNSUPPORTED,
                            "cookie operations require native engine");
  }
  char engine_error[512] = {0};
  status = proton_engine_window_cookie_set_json(slot->engine_window,
                                                 cookie_json, engine_error,
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
      window_slot, engine_view, config.x, config.y, config.width,
      config.height, config.z_order, config.visible != 0, out_view);
  if (status != PROTON_OK) {
    if (engine_view != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_view_destroy(engine_view, engine_error,
                                       sizeof(engine_error));
    }
    return status;
  }
  if (engine_view != NULL) {
    proton_engine_view_bind_public_id(engine_view, (*out_view)->logical_id);
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

int32_t proton_view_load_html(proton_view_handle_t view, const char *html,
                              const char *base_url) {
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (html == NULL || base_url == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "html and base_url are required");
  }
  if (slot->engine_view != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_view_load_html(slot->engine_view, html, base_url,
                                          engine_error, sizeof(engine_error));
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

int32_t proton_view_state_json(proton_view_handle_t view, char *buffer,
                               int32_t buffer_len,
                               int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  proton_view_slot_t *slot = NULL;
  int32_t status = proton_get_view(view, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  char state[256];
  int required = snprintf(
      state, sizeof(state),
      "{\"x\":%d,\"y\":%d,\"width\":%d,\"height\":%d,"
      "\"visible\":%s,\"z_order\":%d}",
      slot->x, slot->y, slot->width, slot->height,
      slot->visible ? "true" : "false", slot->z_order);
  if (required < 0 || required >= (int)sizeof(state)) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "view state payload is too large");
  }
  *out_required_len = required;
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "view state buffer is too small");
  }
  memcpy(buffer, state, (size_t)required + 1);
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

int32_t proton_image_get_size_json(proton_image_handle_t image, char *buffer,
                                   int32_t buffer_len,
                                   int32_t *out_required_len) {
  proton_image_slot_t *slot = NULL;
  int32_t status = proton_get_image(image, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  int32_t width = 0;
  int32_t height = 0;
  char engine_error[512] = {0};
  status = proton_engine_image_get_size(slot->engine_image, &width, &height,
                                        engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  char json[64];
  int required = snprintf(json, sizeof(json), "{\"width\":%d,\"height\":%d}",
                          width, height);
  if (required < 0 || required >= (int)sizeof(json)) {
    return proton_set_error(PROTON_ERR_ENGINE,
                            "image size payload is too large");
  }
  if (out_required_len != NULL) {
    *out_required_len = required;
  }
  if (buffer == NULL || buffer_len <= required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "image size buffer is too small");
  }
  memcpy(buffer, json, (size_t)required + 1);
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
