#if !defined(_WIN32) && !(defined(__APPLE__) && defined(__MACH__)) && \
  !defined(__linux__)

#include "native_buffer.h"

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer) {
  (void)buffer;
  return 0;
}

#endif
