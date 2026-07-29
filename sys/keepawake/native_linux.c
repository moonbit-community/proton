#include "native_stub.h"

#if !defined(_WIN32) && !defined(__APPLE__)
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *keepawake_linux_scope_to_what(int32_t scope) {
  switch (scope) {
  case keepawake_SCOPE_DISPLAY:
    return "idle";
  case keepawake_SCOPE_SYSTEM_AND_DISPLAY:
    return "idle:sleep";
  case keepawake_SCOPE_SYSTEM:
  default:
    return "sleep";
  }
}

void keepawake_platform_release(keepawake_guard_t *guard) {
  if (!guard->active) {
    return;
  }

  if (guard->child_pid > 0) {
    if (kill(-guard->child_pid, SIGTERM) != 0 && errno != ESRCH) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_OPERATION_FAILED,
        "Failed to terminate the Linux keep-awake helper: %s",
        strerror(errno)
      );
      return;
    }
    waitpid(guard->child_pid, NULL, 0);
  }

  guard->child_pid = 0;
  guard->active = 0;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
}

void keepawake_platform_start(
  keepawake_guard_t *guard,
  const char *reason,
  int32_t scope
) {
  int exec_error_pipe[2];
  pid_t pid;
  const char *what = keepawake_linux_scope_to_what(scope);
  char error_buffer[64];

  if (pipe(exec_error_pipe) != 0) {
    keepawake_set_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to create the Linux startup pipe: %s",
      strerror(errno)
    );
    return;
  }

  pid = fork();
  if (pid < 0) {
    close(exec_error_pipe[0]);
    close(exec_error_pipe[1]);
    keepawake_set_error(
      guard,
      keepawake_STATUS_OPERATION_FAILED,
      "Failed to fork the Linux keep-awake helper: %s",
      strerror(errno)
    );
    return;
  }

  if (pid == 0) {
    char *const argv[] = {
      "systemd-inhibit",
      "--what",
      (char *)what,
      "--mode",
      "block",
      "--why",
      (char *)reason,
      "/bin/sh",
      "-c",
      "while :; do sleep 3600; done",
      NULL,
    };
    close(exec_error_pipe[0]);
    setpgid(0, 0);
    execvp("systemd-inhibit", argv);
    snprintf(error_buffer, sizeof(error_buffer), "%d", errno);
    write(exec_error_pipe[1], error_buffer, strlen(error_buffer));
    _exit(127);
  }

  close(exec_error_pipe[1]);

  {
    ssize_t read_len = read(
      exec_error_pipe[0],
      error_buffer,
      sizeof(error_buffer) - 1
    );
    close(exec_error_pipe[0]);
    if (read_len > 0) {
      int child_errno = 0;
      error_buffer[read_len] = '\0';
      child_errno = atoi(error_buffer);
      waitpid(pid, NULL, 0);
      if (child_errno == ENOENT) {
        keepawake_set_error(
          guard,
          keepawake_STATUS_BACKEND_UNAVAILABLE,
          "systemd-inhibit was not found in PATH"
        );
      } else {
        keepawake_set_error(
          guard,
          keepawake_STATUS_OPERATION_FAILED,
          "Failed to launch systemd-inhibit: %s",
          strerror(child_errno)
        );
      }
      return;
    }
  }

  usleep(100000);
  {
    int child_status = 0;
    pid_t wait_result = waitpid(pid, &child_status, WNOHANG);
    if (wait_result == pid) {
      keepawake_set_error(
        guard,
        keepawake_STATUS_BACKEND_UNAVAILABLE,
        "systemd-inhibit exited immediately; ensure logind is available"
      );
      return;
    }
  }

  guard->child_pid = (int32_t)pid;
  guard->active = 1;
  guard->status = keepawake_STATUS_OK;
  keepawake_clear_error(guard);
}

#endif
