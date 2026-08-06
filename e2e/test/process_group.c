#include <stdint.h>

#include "moonbit.h"

#if !defined(_WIN32)
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <unistd.h>
#endif

/*
 * Kill a process group only when the tracked child owns a group distinct from
 * the test runner. Returning 1 asks MoonBit to use its portable tree fallback.
 */
MOONBIT_FFI_EXPORT int32_t proton_e2e_kill_isolated_process_group(
  int32_t pid
) {
#if defined(_WIN32)
  (void)pid;
  return 1;
#else
  pid_t group;

  if (pid <= 0) {
    return -EINVAL;
  }

  group = getpgid((pid_t)pid);
  if (group < 0) {
    return errno == ESRCH ? 0 : -errno;
  }
  if (group != (pid_t)pid || group == getpgrp()) {
    return 1;
  }
  if (kill(-group, SIGKILL) == 0 || errno == ESRCH) {
    return 0;
  }
  return -errno;
#endif
}
