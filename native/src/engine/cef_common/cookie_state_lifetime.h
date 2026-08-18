#ifndef PROTON_ENGINE_CEF_COMMON_COOKIE_STATE_LIFETIME_H
#define PROTON_ENGINE_CEF_COMMON_COOKIE_STATE_LIFETIME_H

#ifdef _WIN32
#include <windows.h>
typedef volatile LONG proton_cookie_state_ref_count_t;
typedef volatile LONG proton_cookie_state_detached_t;

static inline void proton_cookie_state_lifetime_init(
    proton_cookie_state_ref_count_t *refs,
    proton_cookie_state_detached_t *detached) {
  InterlockedExchange(refs, 1);
  InterlockedExchange(detached, 0);
}

static inline void proton_cookie_state_lifetime_retain(
    proton_cookie_state_ref_count_t *refs) {
  InterlockedIncrement(refs);
}

static inline int proton_cookie_state_lifetime_release(
    proton_cookie_state_ref_count_t *refs) {
  return InterlockedDecrement(refs) == 0;
}

static inline void proton_cookie_state_lifetime_detach(
    proton_cookie_state_detached_t *detached) {
  InterlockedExchange(detached, 1);
}

static inline int proton_cookie_state_lifetime_is_detached(
    proton_cookie_state_detached_t *detached) {
  return InterlockedCompareExchange(detached, 0, 0) != 0;
}
#else
#include <stdatomic.h>

typedef atomic_int proton_cookie_state_ref_count_t;
typedef atomic_int proton_cookie_state_detached_t;

static inline void proton_cookie_state_lifetime_init(
    proton_cookie_state_ref_count_t *refs,
    proton_cookie_state_detached_t *detached) {
  atomic_init(refs, 1);
  atomic_init(detached, 0);
}

static inline void proton_cookie_state_lifetime_retain(
    proton_cookie_state_ref_count_t *refs) {
  atomic_fetch_add_explicit(refs, 1, memory_order_relaxed);
}

static inline int proton_cookie_state_lifetime_release(
    proton_cookie_state_ref_count_t *refs) {
  return atomic_fetch_sub_explicit(refs, 1, memory_order_acq_rel) == 1;
}

static inline void proton_cookie_state_lifetime_detach(
    proton_cookie_state_detached_t *detached) {
  atomic_store_explicit(detached, 1, memory_order_release);
}

static inline int proton_cookie_state_lifetime_is_detached(
    proton_cookie_state_detached_t *detached) {
  return atomic_load_explicit(detached, memory_order_acquire) != 0;
}
#endif

#endif
