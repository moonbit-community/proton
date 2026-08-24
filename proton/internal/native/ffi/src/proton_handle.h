#ifndef PROTON_HANDLE_H
#define PROTON_HANDLE_H

#include <stdint.h>

#define PROTON_HANDLE_INDEX_MASK 0x00000000ffffffffULL
#define PROTON_HANDLE_GENERATION_SHIFT 32
#define PROTON_HANDLE_TYPE_SHIFT 60

enum {
  PROTON_HANDLE_TYPE_RUNTIME = 1,
  PROTON_HANDLE_TYPE_WINDOW = 2,
  PROTON_HANDLE_TYPE_UPDATE_STAGE = 3,
};

static inline uint64_t proton_make_handle(uint64_t type, uint32_t generation,
                                          uint32_t index) {
  return (type << PROTON_HANDLE_TYPE_SHIFT) |
         ((uint64_t)generation << PROTON_HANDLE_GENERATION_SHIFT) |
         (uint64_t)index;
}

static inline uint64_t proton_handle_type(uint64_t handle) {
  return handle >> PROTON_HANDLE_TYPE_SHIFT;
}

static inline uint32_t proton_handle_generation(uint64_t handle) {
  return (uint32_t)((handle >> PROTON_HANDLE_GENERATION_SHIFT) & 0x0fffffffU);
}

static inline uint32_t proton_handle_index(uint64_t handle) {
  return (uint32_t)(handle & PROTON_HANDLE_INDEX_MASK);
}

static inline uint32_t proton_next_handle_generation(uint32_t generation) {
  generation = (generation + 1) & 0x0fffffffU;
  return generation == 0 ? 1 : generation;
}

#endif
