#include "proton_native.h"
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

#if PROTON_WITH_ENGINE && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__))
#define PROTON_RUNTIME_WAIT_FEATURE ",\"runtime_wait\""
#else
#define PROTON_RUNTIME_WAIT_FEATURE ""
#endif

#if PROTON_WITH_ENGINE && \
    (defined(_WIN32) || defined(__APPLE__) || defined(__linux__))
#define PROTON_TITLEBAR_OVERLAY_FEATURE ",\"titlebar_overlay\""
#else
#define PROTON_TITLEBAR_OVERLAY_FEATURE ""
#endif

#define PROTON_MAX_DIALOG_TEXT_BYTES 1048576
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

// Escape `value` as JSON string contents into `out` (without the quotes).
// Returns false when the escaped text would not fit.
static bool proton_json_escape_into(const char *value,
                                    char *out,
                                    size_t out_len) {
  size_t written = 0;
  for (const unsigned char *p = (const unsigned char *)value; *p; p++) {
    char escaped[8];
    size_t escaped_len;
    switch (*p) {
    case '"':
      memcpy(escaped, "\\\"", 2);
      escaped_len = 2;
      break;
    case '\\':
      memcpy(escaped, "\\\\", 2);
      escaped_len = 2;
      break;
    case '\n':
      memcpy(escaped, "\\n", 2);
      escaped_len = 2;
      break;
    case '\r':
      memcpy(escaped, "\\r", 2);
      escaped_len = 2;
      break;
    case '\t':
      memcpy(escaped, "\\t", 2);
      escaped_len = 2;
      break;
    default:
      if (*p < 0x20) {
        escaped_len = (size_t)snprintf(escaped, sizeof(escaped), "\\u%04x",
                                       (unsigned)*p);
      } else {
        escaped[0] = (char)*p;
        escaped_len = 1;
      }
      break;
    }
    if (written + escaped_len >= out_len) {
      return false;
    }
    memcpy(out + written, escaped, escaped_len);
    written += escaped_len;
  }
  if (written >= out_len) {
    return false;
  }
  out[written] = '\0';
  return true;
}

// Drain app-menu commands assigned to this runtime into its event queue.
static void proton_runtime_sync_menu_commands(proton_runtime_slot_t *runtime) {
  for (;;) {
    char command_id[PROTON_MAX_EVENT_BYTES];
    proton_window_id_t focused_window = PROTON_INVALID_HANDLE;
    int32_t present = 0;
    if (proton_engine_take_menu_command(
            runtime->engine_runtime, command_id, sizeof(command_id),
            &focused_window, &present) != PROTON_OK ||
        present == 0) {
      return;
    }
    char escaped[PROTON_MAX_EVENT_BYTES];
    if (!proton_json_escape_into(command_id, escaped, sizeof(escaped))) {
      continue;
    }
    char event_json[PROTON_MAX_EVENT_BYTES];
    int written = focused_window == PROTON_INVALID_HANDLE
                      ? snprintf(event_json, sizeof(event_json),
                                 "{\"type\":\"menu_command\","
                                 "\"command_id\":\"%s\"}",
                                 escaped)
                      : snprintf(event_json, sizeof(event_json),
                                 "{\"type\":\"menu_command\","
                                 "\"command_id\":\"%s\",\"window\":\"%lld\"}",
                                 escaped, (long long)focused_window);
    if (written < 0 || written >= (int)sizeof(event_json)) {
      continue;
    }
    if (!proton_runtime_enqueue_event(runtime, event_json)) {
      return;
    }
  }
}


int32_t proton_abi_version(void) { return PROTON_ABI_VERSION; }

int32_t proton_runtime_info_json(char *buffer,
                                 int32_t buffer_len,
                                 int32_t *out_required_len) {
  if (out_required_len == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_required_len is required");
  }
  char info[256];
  int required = snprintf(
      info, sizeof(info),
      "{\"abi_version\":%d,\"runtime_available\":%s,"
      "\"build_mode\":\"%s\",\"platform\":\"%s\","
      "\"features\":[\"base_abi\",\"event_polling\",\"bridge_polling\""
      PROTON_RUNTIME_WAIT_FEATURE PROTON_TITLEBAR_OVERLAY_FEATURE "]}",
      PROTON_ABI_VERSION, PROTON_WITH_ENGINE ? "true" : "false",
      PROTON_WITH_ENGINE ? "runtime" : "abi-only", PROTON_PLATFORM_NAME);
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

int32_t proton_execute_process(const char *config_json,
                               int32_t *out_exit_code) {
  if (out_exit_code == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_exit_code is required");
  }
  int32_t status = proton_config_validate_runtime(config_json);
  if (status != PROTON_OK) {
    return status;
  }
  if (proton_config_runtime_requests_engine(config_json)) {
    char engine_error[512] = {0};
    status = proton_config_probe_runtime_layout(config_json);
    if (status != PROTON_OK) {
      return status;
    }
    status = proton_engine_execute_process_json(config_json, out_exit_code,
                                                engine_error,
                                                sizeof(engine_error));
    return proton_set_engine_status(status, engine_error);
  }
  *out_exit_code = 0;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_probe_json(const char *config_json) {
  int32_t status = proton_config_validate_runtime(config_json);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_config_probe_runtime_layout(config_json);
  if (status != PROTON_OK) {
    return status;
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_create_json(const char *config_json,
                                   proton_runtime_id_t *out_runtime) {
  if (out_runtime == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_runtime is required");
  }
  *out_runtime = PROTON_INVALID_HANDLE;
  int32_t status = proton_config_validate_runtime(config_json);
  if (status != PROTON_OK) {
    return status;
  }
  if (proton_has_active_runtime()) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "runtime is already initialized");
  }
  bool engine_backed = proton_config_runtime_requests_engine(config_json);
  proton_engine_runtime_t *engine_runtime = NULL;
  if (engine_backed) {
    char engine_error[512] = {0};
    status = proton_config_probe_runtime_layout(config_json);
    if (status != PROTON_OK) {
      return status;
    }
    status = proton_engine_runtime_create_json(config_json, &engine_runtime,
                                               engine_error,
                                               sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (engine_runtime == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "native engine returned no runtime state");
    }
  }

  status = proton_runtime_slot_create(engine_backed, engine_runtime,
                                      out_runtime, NULL);
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

int32_t proton_runtime_destroy(proton_runtime_id_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }

  status = proton_destroy_windows_for_runtime(runtime);
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

int32_t proton_runtime_run(proton_runtime_id_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    slot->running = true;
    slot->quit_requested = false;
    status = proton_engine_runtime_run(slot->engine_runtime, engine_error,
                                       sizeof(engine_error));
    slot->running = false;
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    g_last_error[0] = '\0';
    return PROTON_OK;
  }
  slot->running = true;
  slot->quit_requested = false;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_quit(proton_runtime_id_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_runtime_quit(slot->engine_runtime, engine_error,
                                        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  }
  slot->quit_requested = true;
  slot->running = false;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_do_message_loop_work(proton_runtime_id_t runtime) {
  proton_runtime_slot_t *slot = NULL;
  int32_t status = proton_get_runtime(runtime, &slot);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_require_runtime_owner_thread(slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->running) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "runtime run loop is already active");
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

int32_t proton_runtime_wait(proton_runtime_id_t runtime,
                            uint32_t interest_mask,
                            uint32_t timeout_ms,
                            uint32_t *out_ready_mask) {
  if (out_ready_mask == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_ready_mask is required");
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
  if (slot->running) {
    return proton_set_error(PROTON_ERR_ALREADY_INITIALIZED,
                            "runtime run loop is already active");
  }

  uint32_t ready_mask = PROTON_WAIT_NONE;
  if ((interest_mask & PROTON_WAIT_EVENT) != 0) {
    status = proton_runtime_sync_engine_closed_windows(runtime, slot);
    if (status != PROTON_OK) {
      return status;
    }
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
  *out_ready_mask = engine_ready & engine_interest;
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_set_menu_json(proton_runtime_id_t runtime,
                                     const char *menu_json) {
  int32_t status = proton_config_validate_menu(menu_json);
  if (status != PROTON_OK) {
    return status;
  }
  proton_runtime_slot_t *slot = NULL;
  status = proton_get_runtime(runtime, &slot);
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
  status = proton_engine_runtime_set_menu_json(
      slot->engine_runtime, menu_json, engine_error, sizeof(engine_error));
  if (status != PROTON_OK) {
    return proton_set_engine_status(status, engine_error);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_runtime_poll_event_json(proton_runtime_id_t runtime,
                                       char *buffer, int32_t buffer_len,
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
  status = proton_runtime_sync_engine_closed_windows(runtime, slot);
  if (status != PROTON_OK) {
    return status;
  }
  proton_runtime_sync_menu_commands(slot);
  status = proton_runtime_poll_event(slot, buffer, buffer_len,
                                     out_required_len);
  if (status < 0) {
    return status;
  }
  g_last_error[0] = '\0';
  return status;
}

int32_t proton_runtime_poll_bridge_request_json(proton_runtime_id_t runtime,
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
    proton_runtime_id_t runtime,
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

int32_t proton_window_create_json(proton_runtime_id_t runtime,
                                  const char *config_json,
                                  proton_window_id_t *out_window) {
  proton_runtime_slot_t *runtime_slot = NULL;
  int32_t status = proton_get_runtime(runtime, &runtime_slot);
  if (status != PROTON_OK) {
    return status;
  }
  if (config_json == NULL || out_window == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "config_json and out_window are required");
  }
  int32_t width = 0;
  int32_t height = 0;
  status = proton_config_validate_window(config_json, &width, &height);
  if (status != PROTON_OK) {
    return status;
  }

  proton_engine_window_t *engine_window = NULL;
  if (runtime_slot->engine_runtime != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_create_json(runtime_slot->engine_runtime,
                                              config_json, &engine_window,
                                              engine_error,
                                              sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    if (engine_window == NULL) {
      return proton_set_error(PROTON_ERR_ENGINE,
                              "native engine returned no window state");
    }
  }

  status = proton_window_slot_create(runtime_slot, runtime, engine_window,
                                    width, height, out_window, NULL);
  if (status != PROTON_OK) {
    if (engine_window != NULL) {
      char engine_error[512] = {0};
      (void)proton_engine_window_destroy(engine_window, engine_error,
                                         sizeof(engine_error));
    }
    return status;
  }
  if (engine_window != NULL) {
    proton_engine_window_bind_public_id(engine_window, *out_window);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_destroy(proton_window_id_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
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
  status = proton_window_enqueue_closed_once(runtime, slot, window);
  if (status != PROTON_OK) {
    return status;
  }

  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_destroy(slot->engine_window, engine_error,
                                          sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
    slot->engine_window = NULL;
  }
  proton_window_slot_destroy(slot);
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_show(proton_window_id_t window) {
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

int32_t proton_window_hide(proton_window_id_t window) {
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

int32_t proton_window_close(proton_window_id_t window) {
  proton_window_slot_t *slot = NULL;
  int32_t status = proton_get_window(window, &slot);
  if (status == PROTON_ERR_DESTROYED) {
    return PROTON_OK;
  }
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->engine_window != NULL) {
    char engine_error[512] = {0};
    status = proton_engine_window_close(slot->engine_window, engine_error,
                                        sizeof(engine_error));
    if (status != PROTON_OK) {
      return proton_set_engine_status(status, engine_error);
    }
  } else {
    proton_runtime_slot_t *runtime = NULL;
    status = proton_get_runtime(slot->runtime, &runtime);
    if (status != PROTON_OK) {
      return status;
    }
    status = proton_window_enqueue_closed_once(runtime, slot, window);
    if (status != PROTON_OK) {
      return status;
    }
    proton_window_slot_close(slot);
  }
  g_last_error[0] = '\0';
  return PROTON_OK;
}

int32_t proton_window_focus(proton_window_id_t window) {
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

int32_t proton_window_set_title(proton_window_id_t window, const char *title) {
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

int32_t proton_window_set_size(proton_window_id_t window, int32_t width,
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

int32_t proton_window_load_url(proton_window_id_t window, const char *url) {
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

int32_t proton_window_load_html(proton_window_id_t window, const char *html,
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



int32_t proton_window_eval(proton_window_id_t window, const char *script) {
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

int32_t proton_window_emit_bridge_event_json(proton_window_id_t window,
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

static int32_t proton_require_dialog_window(proton_window_id_t window,
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



int32_t proton_window_begin_message_dialog(
    proton_window_id_t window,
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
    proton_window_id_t window,
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
    proton_window_id_t window,
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
    proton_window_id_t window,
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
    proton_window_id_t window,
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
    proton_window_id_t window,
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
