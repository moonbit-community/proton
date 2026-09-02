#ifndef PROTON_ENGINE_CEF_COMMON_COOKIE_CACHE_H
#define PROTON_ENGINE_CEF_COMMON_COOKIE_CACHE_H

#include <stdint.h>

typedef struct proton_cookie_snapshot proton_cookie_snapshot_t;

void proton_cookie_snapshot_destroy(void *snapshot);
int32_t proton_cookie_snapshot_count(const proton_cookie_snapshot_t *snapshot,
                                     int32_t *out_count);
int32_t proton_cookie_snapshot_copy_string_field(
    const proton_cookie_snapshot_t *snapshot, int32_t index, int32_t field,
    char *buffer, int32_t buffer_len, int32_t *out_required_len);
int32_t proton_cookie_snapshot_int_field(const proton_cookie_snapshot_t *snapshot,
                                         int32_t index, int32_t field,
                                         int32_t *out_value);
int32_t proton_cookie_snapshot_int64_field(
    const proton_cookie_snapshot_t *snapshot, int32_t index, int32_t field,
    int64_t *out_value, int32_t *out_present);

#endif
