#ifndef PROTON_APP_RUNNER_H
#define PROTON_APP_RUNNER_H

#include "proton_internal.h"

#include <stdbool.h>
#include <stdint.h>

PROTON_INTERNAL bool proton_app_runner_is_active(void);

#ifdef __OBJC__
typedef int32_t (^proton_app_main_int_work_t)(void);
typedef uint64_t (^proton_app_main_u64_work_t)(void);
typedef void (^proton_app_main_void_work_t)(void);

PROTON_INTERNAL int32_t
proton_app_dispatch_sync_int(proton_app_main_int_work_t work);
PROTON_INTERNAL uint64_t
proton_app_dispatch_sync_u64(proton_app_main_u64_work_t work);
PROTON_INTERNAL void
proton_app_dispatch_sync_void(proton_app_main_void_work_t work);
#endif

#endif
