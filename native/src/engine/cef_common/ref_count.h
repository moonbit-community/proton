#ifndef PROTON_ENGINE_CEF_COMMON_REF_COUNT_H
#define PROTON_ENGINE_CEF_COMMON_REF_COUNT_H

#ifndef PROTON_ENGINE_REF_INCREMENT
#error "PROTON_ENGINE_REF_INCREMENT must be defined before including ref_count.h"
#endif

#ifndef PROTON_ENGINE_REF_DECREMENT
#error "PROTON_ENGINE_REF_DECREMENT must be defined before including ref_count.h"
#endif

#ifndef PROTON_ENGINE_REF_LOAD
#error "PROTON_ENGINE_REF_LOAD must be defined before including ref_count.h"
#endif

#ifndef PROTON_ENGINE_REF_STORE
#error "PROTON_ENGINE_REF_STORE must be defined before including ref_count.h"
#endif

static void CEF_CALLBACK proton_engine_add_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  (void)PROTON_ENGINE_REF_INCREMENT(refs);
}

static int CEF_CALLBACK proton_engine_release(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  int value = (int)PROTON_ENGINE_REF_DECREMENT(refs);
  if (value <= 0) {
    PROTON_ENGINE_REF_STORE(refs, 1);
  }
  return 0;
}

static int CEF_CALLBACK proton_engine_has_one_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  return PROTON_ENGINE_REF_LOAD(refs) == 1;
}

static int CEF_CALLBACK
proton_engine_has_at_least_one_ref(cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  return PROTON_ENGINE_REF_LOAD(refs) > 0;
}

static void proton_engine_init_ref_counted(cef_base_ref_counted_t *base,
                                           size_t size,
                                           proton_engine_ref_counted_t *refs) {
  memset(base, 0, size);
  base->size = size;
  base->add_ref = proton_engine_add_ref;
  base->release = proton_engine_release;
  base->has_one_ref = proton_engine_has_one_ref;
  base->has_at_least_one_ref = proton_engine_has_at_least_one_ref;
  PROTON_ENGINE_REF_STORE(refs, 1);
}

#endif
