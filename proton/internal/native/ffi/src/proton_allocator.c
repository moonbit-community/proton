#include "proton_allocator.h"

#include <stdint.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>

void *proton_native_malloc(size_t size) {
  return HeapAlloc(GetProcessHeap(), 0, size);
}

void *proton_native_calloc(size_t count, size_t size) {
  if (size != 0 && count > SIZE_MAX / size) {
    return NULL;
  }
  return HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, count * size);
}

void *proton_native_realloc(void *ptr, size_t size) {
  if (ptr == NULL) {
    return proton_native_malloc(size);
  }
  if (size == 0) {
    proton_native_free(ptr);
    return NULL;
  }
  return HeapReAlloc(GetProcessHeap(), 0, ptr, size);
}

void proton_native_free(void *ptr) {
  if (ptr != NULL) {
    (void)HeapFree(GetProcessHeap(), 0, ptr);
  }
}
#else
#include <dlfcn.h>
#include <pthread.h>

typedef void *(*proton_malloc_fn)(size_t);
typedef void *(*proton_calloc_fn)(size_t, size_t);
typedef void *(*proton_realloc_fn)(void *, size_t);
typedef void (*proton_free_fn)(void *);

static pthread_once_t g_proton_allocator_once = PTHREAD_ONCE_INIT;
static proton_malloc_fn g_proton_malloc = NULL;
static proton_calloc_fn g_proton_calloc = NULL;
static proton_realloc_fn g_proton_realloc = NULL;
static proton_free_fn g_proton_free = NULL;

static void proton_native_allocator_init(void) {
  g_proton_malloc = (proton_malloc_fn)dlsym(RTLD_NEXT, "malloc");
  g_proton_calloc = (proton_calloc_fn)dlsym(RTLD_NEXT, "calloc");
  g_proton_realloc = (proton_realloc_fn)dlsym(RTLD_NEXT, "realloc");
  g_proton_free = (proton_free_fn)dlsym(RTLD_NEXT, "free");
  if (g_proton_malloc == NULL || g_proton_calloc == NULL ||
      g_proton_realloc == NULL || g_proton_free == NULL) {
    abort();
  }
}

static void proton_native_allocator_require(void) {
  if (pthread_once(&g_proton_allocator_once, proton_native_allocator_init) != 0) {
    abort();
  }
}

__attribute__((constructor)) static void proton_native_allocator_prepare(void) {
  proton_native_allocator_require();
}

void *proton_native_malloc(size_t size) {
  proton_native_allocator_require();
  return g_proton_malloc(size);
}

void *proton_native_calloc(size_t count, size_t size) {
  proton_native_allocator_require();
  return g_proton_calloc(count, size);
}

void *proton_native_realloc(void *ptr, size_t size) {
  proton_native_allocator_require();
  return g_proton_realloc(ptr, size);
}

void proton_native_free(void *ptr) {
  if (ptr == NULL) {
    return;
  }
  proton_native_allocator_require();
  g_proton_free(ptr);
}
#endif
