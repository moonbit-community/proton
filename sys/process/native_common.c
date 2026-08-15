#include "native_stub.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

static void process_set_error(process_state_t *state, const char *message) {
  if (state != NULL && message != NULL) {
    snprintf(state->last_error, sizeof(state->last_error), "%s", message);
  }
}

/* GC finalizer: cleans up platform resources when the handle is collected. */
static void process_finalize(void *payload) {
  process_state_t *state = (process_state_t *)payload;
  if (state == NULL) {
    return;
  }
  process_platform_cleanup(state);
}

MOONBIT_FFI_EXPORT
process_state_t *moonbit_process_spawn(moonbit_bytes_t command,
                                       moonbit_bytes_t args_bytes,
                                       moonbit_bytes_t cwd,
                                       int32_t capture_output) {
  process_state_t *state =
      (process_state_t *)moonbit_make_external_object(
          process_finalize, (uint32_t)sizeof(process_state_t));
  if (state == NULL) {
    return NULL;
  }
  memset(state, 0, sizeof(*state));
  state->pid = -1;

  const char *cmd = (const char *)command;
  const char *args = (const char *)args_bytes;
  const char *working_dir = (const char *)cwd;
  if (working_dir != NULL && working_dir[0] == '\0') {
    working_dir = NULL;
  }

  int32_t status = process_platform_spawn(state, cmd, args, working_dir,
                                          capture_output);
  if (status != process_STATUS_OK) {
    if (state->last_error[0] == '\0') {
      process_set_error(state, "spawn failed");
    }
    state->status = status;
  }
  return state;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_process_pid(process_state_t *state) {
  if (state == NULL) {
    return -1;
  }
  return state->pid;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_process_status(process_state_t *state) {
  if (state == NULL) {
    return process_STATUS_INVALID_ARGUMENT;
  }
  return state->status;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_process_try_wait(process_state_t *state,
                                 int32_t *out_exit_code,
                                 int32_t *out_exited) {
  if (state == NULL || out_exit_code == NULL || out_exited == NULL) {
    return process_STATUS_INVALID_ARGUMENT;
  }
  *out_exit_code = 0;
  *out_exited = 0;
  if (state->exited) {
    *out_exit_code = state->exit_code;
    *out_exited = 1;
    return process_STATUS_OK;
  }
  return process_platform_try_wait(state, out_exit_code, out_exited);
}

MOONBIT_FFI_EXPORT
int32_t moonbit_process_wait(process_state_t *state,
                             int32_t *out_exit_code) {
  if (state == NULL || out_exit_code == NULL) {
    return process_STATUS_INVALID_ARGUMENT;
  }
  *out_exit_code = 0;
  if (state->exited) {
    *out_exit_code = state->exit_code;
    return process_STATUS_OK;
  }
  int32_t exited = 0;
  while (!exited) {
    int32_t status = moonbit_process_try_wait(state, out_exit_code, &exited);
    if (status != process_STATUS_OK) {
      return status;
    }
    if (!exited) {
      process_platform_sleep_ms(10);
    }
  }
  return process_STATUS_OK;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_process_kill(process_state_t *state) {
  if (state == NULL) {
    return process_STATUS_INVALID_ARGUMENT;
  }
  if (state->exited) {
    return process_STATUS_OK;
  }
  return process_platform_kill(state);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_process_last_error(process_state_t *state) {
  if (state == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  const char *text = state->last_error;
  if (text[0] == '\0') {
    return moonbit_make_bytes(0, 0);
  }
  int32_t len = (int32_t)strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, text, (size_t)len);
  return bytes;
}

MOONBIT_FFI_EXPORT
void moonbit_process_destroy(process_state_t *state) {
  if (state == NULL) {
    return;
  }
  process_platform_cleanup(state);
}
