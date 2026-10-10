#ifndef PROTON_ENGINE_CEF_COMMON_REF_COUNT_H
#define PROTON_ENGINE_CEF_COMMON_REF_COUNT_H

#include "include/capi/cef_base_capi.h"
#include <string.h>

#ifdef _WIN32
#include <windows.h>
typedef struct {
  LONG refs;
} proton_engine_ref_counted_t;
#else
#include <stdatomic.h>
typedef struct {
  atomic_int refs;
} proton_engine_ref_counted_t;
#endif

static inline void proton_engine_ref_increment(proton_engine_ref_counted_t *refs) {
#ifdef _WIN32
  (void)InterlockedIncrement(&refs->refs);
#else
  (void)atomic_fetch_add_explicit(&refs->refs, 1, memory_order_relaxed);
#endif
}

/* Return the remaining count; the object's release callback owns destruction. */
static inline int proton_engine_ref_decrement(proton_engine_ref_counted_t *refs) {
#ifdef _WIN32
  return (int)InterlockedDecrement(&refs->refs);
#else
  return atomic_fetch_sub_explicit(&refs->refs, 1, memory_order_acq_rel) - 1;
#endif
}

static inline int proton_engine_ref_load(proton_engine_ref_counted_t *refs) {
#ifdef _WIN32
  return (int)InterlockedCompareExchange(&refs->refs, 0, 0);
#else
  return atomic_load_explicit(&refs->refs, memory_order_acquire);
#endif
}

static inline void proton_engine_ref_store(proton_engine_ref_counted_t *refs,
                                          int value) {
#ifdef _WIN32
  (void)InterlockedExchange(&refs->refs, value);
#else
  atomic_store(&refs->refs, value);
#endif
}

static inline void CEF_CALLBACK
proton_engine_add_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  proton_engine_ref_increment(refs);
}

/* Default for externally owned callback storage. Heap-owned objects override
   release and destroy their payload only after the final reference is dropped. */
static inline int CEF_CALLBACK
proton_engine_release(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  int value = proton_engine_ref_decrement(refs);
  if (value <= 0) {
    proton_engine_ref_store(refs, 1);
  }
  return 0;
}

static inline int CEF_CALLBACK
proton_engine_has_one_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  return proton_engine_ref_load(refs) == 1;
}

static inline int CEF_CALLBACK
proton_engine_has_at_least_one_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  return proton_engine_ref_load(refs) > 0;
}

static inline void proton_engine_init_ref_counted(
    cef_base_ref_counted_t *base, size_t size, proton_engine_ref_counted_t *refs) {
  memset(base, 0, size);
  base->size = size;
  base->add_ref = proton_engine_add_ref;
  base->release = proton_engine_release;
  base->has_one_ref = proton_engine_has_one_ref;
  base->has_at_least_one_ref = proton_engine_has_at_least_one_ref;
  proton_engine_ref_store(refs, 1);
}

#endif
