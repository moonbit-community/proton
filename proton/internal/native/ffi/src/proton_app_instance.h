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
void proton_app_instance_detach_runtime_impl(int64_t instance);
int32_t proton_app_instance_take_event_impl(
    int64_t instance, char *buffer, size_t buffer_len, int32_t *out_present,
    char *error, size_t error_len);

#endif
