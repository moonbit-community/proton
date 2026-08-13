#ifndef PROTON_ENGINE_CEF_COMMON_PROFILE_STORAGE_H
#define PROTON_ENGINE_CEF_COMMON_PROFILE_STORAGE_H

#include <stddef.h>

/* CEF 120+ locks root_cache_path per process. Runtimes without an explicit
   persistent profile use this unique temporary root for their full lifetime. */
int proton_profile_storage_create_temporary(char *path, size_t path_len,
                                            char *error, size_t error_len);
void proton_profile_storage_remove_temporary(const char *path);

#endif
