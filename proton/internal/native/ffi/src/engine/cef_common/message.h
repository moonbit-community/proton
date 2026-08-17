#ifndef PROTON_ENGINE_CEF_COMMON_MESSAGE_H
#define PROTON_ENGINE_CEF_COMMON_MESSAGE_H

#include <stddef.h>
#include <stdio.h>

/* Fills a caller-owned diagnostic buffer. Every engine reports failures this
   way and so does the shared engine code, so the helper lives here rather than
   once per translation unit. It deliberately depends on nothing but stdio, so
   it can be included before any CEF header. */
static void proton_engine_set_message(char *error, size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

#endif
