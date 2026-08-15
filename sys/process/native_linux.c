#include "native_stub.h"

/* Linux uses the same POSIX implementation as macOS.
   The actual implementation is in native_macos.c, guarded by
   #if defined(__APPLE__) || defined(__linux__). This file exists
   so the CMake/MoonBit native-stub list has a per-platform entry
   consistent with the other sys/ modules. */

#ifdef __linux__
/* All implementation is in native_macos.c under the shared
   __APPLE__ || __linux__ guard. */
#endif
