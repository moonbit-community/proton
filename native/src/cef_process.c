#include "proton_native.h"

#include <stdint.h>

/*
 * CEF subprocess trampoline.
 *
 * The main MoonBit application links and loads proton.dll. During runtime
 * initialization, proton.dll configures CEF's browser_subprocess_path to point
 * at this helper executable. Renderer, GPU, and utility subprocesses enter
 * here first, then proton_execute_process delegates to cef_execute_process and
 * returns the subprocess exit code when CEF handles the process.
 */
int main(void) {
  int32_t exit_code = 0;
  int32_t status =
      proton_execute_process("{\"abi_version\":1,\"use_bundled\":true}",
                             &exit_code);
  if (status == PROTON_PROCESS_HANDLED) {
    return exit_code;
  }
  return status < 0 ? 1 : 0;
}
