#ifndef PROTON_PROCESS_STUB_H
#define PROTON_PROCESS_STUB_H

#include "moonbit.h"

#include <stdint.h>

enum process_status {
  process_STATUS_OK = 0,
  process_STATUS_OPERATION_FAILED = 1,
  process_STATUS_INVALID_ARGUMENT = 2,
};

typedef struct process_state {
  int32_t status;
  int32_t pid;
  int32_t exited;
  int32_t exit_code;
  char last_error[512];
#ifdef _WIN32
  void *h_process; /* HANDLE */
  void *h_thread;  /* HANDLE */
#elif defined(__APPLE__) || defined(__linux__)
  int32_t child_pid;
#endif
} process_state_t;

int32_t process_platform_spawn(process_state_t *state,
                               const char *command,
                               const char *args,
                               const char *cwd,
                               int32_t capture_output);

int32_t process_platform_try_wait(process_state_t *state,
                                  int32_t *out_exit_code,
                                  int32_t *out_exited);

int32_t process_platform_kill(process_state_t *state);

void process_platform_cleanup(process_state_t *state);

void process_platform_sleep_ms(int32_t ms);

#endif
