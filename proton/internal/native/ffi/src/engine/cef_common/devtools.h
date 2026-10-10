#ifndef PROTON_DEVTOOLS_H
#define PROTON_DEVTOOLS_H
#include "include/capi/cef_browser_capi.h"
#include <stddef.h>
#include <stdint.h>
typedef struct proton_devtools proton_devtools_t;
int32_t proton_devtools_open(proton_devtools_t **out, cef_browser_t *browser,
                             int64_t window, int64_t view, int64_t token,
                             char *error, size_t error_len);
int32_t proton_devtools_send(proton_devtools_t *session, cef_browser_t *browser,
                             int64_t token, const char *message, char *error,
                             size_t error_len);
void proton_devtools_close(proton_devtools_t **session);
int64_t proton_devtools_token(proton_devtools_t *session);
#endif
