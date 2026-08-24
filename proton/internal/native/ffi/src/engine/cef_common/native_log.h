#ifndef PROTON_ENGINE_CEF_COMMON_NATIVE_LOG_H
#define PROTON_ENGINE_CEF_COMMON_NATIVE_LOG_H

#include <stdarg.h>

typedef enum proton_native_log_level {
  PROTON_NATIVE_LOG_DEBUG = 1,
  PROTON_NATIVE_LOG_TRACE = 2,
} proton_native_log_level_t;

void proton_native_log(proton_native_log_level_t level, const char *format,
                       ...);
void proton_native_logv(proton_native_log_level_t level, const char *format,
                        va_list args);

#define proton_native_log_debug(...)                                          \
  proton_native_log(PROTON_NATIVE_LOG_DEBUG, __VA_ARGS__)
#define proton_native_log_trace(...)                                          \
  proton_native_log(PROTON_NATIVE_LOG_TRACE, __VA_ARGS__)

#endif
