#include "native_stub.h"

#if defined(__APPLE__) || defined(__linux__)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <time.h>

static char **parse_args(const char *command, const char *args) {
  /* The args string is a null-byte-separated list of arguments.
     The command is argv[0]. */
  int count = 1; /* command */
  if (args != NULL && args[0] != '\0') {
    const char *p = args;
    while (*p) {
      count++;
      p += strlen(p) + 1;
    }
  }
  char **argv = (char **)malloc((size_t)(count + 1) * sizeof(char *));
  if (argv == NULL) {
    return NULL;
  }
  argv[0] = strdup(command);
  if (argv[0] == NULL) {
    free(argv);
    return NULL;
  }
  int idx = 1;
  if (args != NULL && args[0] != '\0') {
    const char *p = args;
    while (*p) {
      argv[idx] = strdup(p);
      if (argv[idx] == NULL) {
        for (int i = 0; i < idx; i++) {
          free(argv[i]);
        }
        free(argv);
        return NULL;
      }
      idx++;
      p += strlen(p) + 1;
    }
  }
  argv[idx] = NULL;
  return argv;
}

static void free_args(char **argv) {
  if (argv == NULL) {
    return;
  }
  for (int i = 0; argv[i] != NULL; i++) {
    free(argv[i]);
  }
  free(argv);
}

int32_t process_platform_spawn(process_state_t *state,
                               const char *command,
                               const char *args,
                               const char *cwd,
                               int32_t capture_output) {
  (void)capture_output;
  char **argv = parse_args(command, args);
  if (argv == NULL) {
    snprintf(state->last_error, sizeof(state->last_error),
             "failed to parse arguments");
    return process_STATUS_OPERATION_FAILED;
  }

  pid_t pid = fork();
  if (pid < 0) {
    snprintf(state->last_error, sizeof(state->last_error),
             "fork failed: %s", strerror(errno));
    free_args(argv);
    return process_STATUS_OPERATION_FAILED;
  }
  if (pid == 0) {
    /* Child process */
    if (cwd != NULL) {
      if (chdir(cwd) != 0) {
        _exit(127);
      }
    }
    execvp(command, argv);
    /* execvp only returns on failure */
    _exit(127);
  }

  /* Parent process */
  state->pid = (int32_t)pid;
  state->child_pid = (int32_t)pid;
  free_args(argv);
  return process_STATUS_OK;
}

int32_t process_platform_try_wait(process_state_t *state,
                                  int32_t *out_exit_code,
                                  int32_t *out_exited) {
  if (state->child_pid <= 0) {
    *out_exited = 1;
    *out_exit_code = state->exit_code;
    return process_STATUS_OK;
  }
  int status = 0;
  pid_t result = waitpid(state->child_pid, &status, WNOHANG);
  if (result == 0) {
    /* Still running */
    *out_exited = 0;
    return process_STATUS_OK;
  }
  if (result < 0) {
    if (errno == ECHILD) {
      /* Process already reaped */
      state->exited = 1;
      *out_exit_code = state->exit_code;
      *out_exited = 1;
      return process_STATUS_OK;
    }
    snprintf(state->last_error, sizeof(state->last_error),
             "waitpid failed: %s", strerror(errno));
    return process_STATUS_OPERATION_FAILED;
  }
  /* Process exited */
  int code = 0;
  if (WIFEXITED(status)) {
    code = WEXITSTATUS(status);
  } else if (WIFSIGNALED(status)) {
    code = -WTERMSIG(status);
  }
  state->exit_code = code;
  state->exited = 1;
  state->child_pid = 0;
  *out_exit_code = code;
  *out_exited = 1;
  return process_STATUS_OK;
}

int32_t process_platform_kill(process_state_t *state) {
  if (state->child_pid <= 0) {
    return process_STATUS_OK;
  }
  if (kill(state->child_pid, SIGTERM) < 0) {
    if (errno != ESRCH) {
      snprintf(state->last_error, sizeof(state->last_error),
               "kill failed: %s", strerror(errno));
      return process_STATUS_OPERATION_FAILED;
    }
  }
  return process_STATUS_OK;
}

void process_platform_cleanup(process_state_t *state) {
  /* Nothing to clean up on POSIX; the process handle is just a PID */
  (void)state;
}

void process_platform_sleep_ms(int32_t ms) {
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (long)(ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
}

#endif /* __APPLE__ || __linux__ */
