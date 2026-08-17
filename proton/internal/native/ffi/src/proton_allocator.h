#ifndef PROTON_ALLOCATOR_H
#define PROTON_ALLOCATOR_H

#include <stddef.h>

void *proton_native_malloc(size_t size);
void *proton_native_calloc(size_t count, size_t size);
void *proton_native_realloc(void *ptr, size_t size);
void proton_native_free(void *ptr);

#define malloc proton_native_malloc
#define calloc proton_native_calloc
#define realloc proton_native_realloc
#define free proton_native_free

#endif
