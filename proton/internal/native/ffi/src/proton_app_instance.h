#ifndef PROTON_APP_INSTANCE_H
#define PROTON_APP_INSTANCE_H

#include "proton_engine.h"

#include <stddef.h>
#include <stdint.h>

int32_t proton_app_instance_acquire_impl(
    const char *identifier, const char *activation_json,
    int64_t *out_instance, int32_t *out_primary, char *error,
    size_t error_len);
int32_t proton_app_instance_attach_runtime_impl(
    int64_t instance, proton_engine_runtime_t *runtime, char *error,
    size_t error_len);
int32_t proton_app_instance_destroy_impl(int64_t instance, char *error,
                                         size_t error_len);
/* Releases the lock this instance holds so another process can acquire it.
   Releasing an instance that holds no lock is a successful no-op. */
int32_t proton_app_instance_release_impl(int64_t instance, char *error,
                                         size_t error_len);
int32_t proton_app_instance_respond_activation_impl(int64_t instance, int64_t request_id, int32_t accept);
void proton_app_instance_stop_accepting_impl(int64_t instance);
void proton_app_instance_detach_runtime_impl(int64_t instance);

#endif
