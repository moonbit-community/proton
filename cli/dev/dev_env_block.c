#include <string.h>

#include "moonbit.h"

/*
 * Keep this stub limited to reading the raw process environment block.
 * Parsing, override merging, and child-process spawn policy belong in
 * dev.mbt.
 */
#ifdef _WIN32
#include <windows.h>

/*
 * Returns the current process environment block as a MoonBit string of
 * UTF-16 code units, keeping each embedded NUL separator. The result ends
 * with the NUL that terminates the last entry; the final block terminator
 * is not included.
 *
 * moonbitlang/x/sys get_env_vars() reads the ANSI environment block, which
 * mangles non-ASCII values before they are re-encoded for a child process.
 * Reading the wide block here keeps every inherited value intact.
 */
MOONBIT_FFI_EXPORT moonbit_string_t proton_cli_dev_env_block(void) {
  LPWCH env_block = GetEnvironmentStringsW();
  if (env_block == NULL) {
    return moonbit_make_string(0, 0);
  }

  int len = 1;
  while (env_block[len - 1] != 0 || env_block[len] != 0) {
    ++len;
  }
  moonbit_string_t result = moonbit_make_string_raw(len);
  memcpy(result, env_block, len * sizeof(WCHAR));
  FreeEnvironmentStringsW(env_block);
  return result;
}
#endif
