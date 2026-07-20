#ifndef PROTON_INTERNAL_H
#define PROTON_INTERNAL_H

#include "proton_native.h"

#ifdef _WIN32
#define PROTON_INTERNAL
#else
#define PROTON_INTERNAL __attribute__((visibility("hidden")))
#endif

PROTON_INTERNAL int32_t proton_set_error(int32_t code, const char *message);
PROTON_INTERNAL int32_t proton_set_engine_status(int32_t status,
                                                 const char *engine_error);

#endif
