#ifndef PROTON_LINUX_TITLEBAR_H
#define PROTON_LINUX_TITLEBAR_H

#include <stddef.h>

typedef struct {
  int x;
  int y;
} proton_linux_titlebar_point_t;

typedef struct {
  int x;
  int y;
  int width;
  int height;
} proton_linux_titlebar_rect_t;

typedef struct {
  int x;
  int y;
  int width;
  int height;
  int draggable;
} proton_linux_titlebar_region_t;

typedef enum {
  PROTON_LINUX_TITLEBAR_HIT_NONE = 0,
  PROTON_LINUX_TITLEBAR_HIT_CLIENT,
  PROTON_LINUX_TITLEBAR_HIT_DRAG,
  PROTON_LINUX_TITLEBAR_HIT_CONTROLS,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH,
  PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST,
} proton_linux_titlebar_hit_t;

typedef struct {
  proton_linux_titlebar_point_t point;
  int width;
  int height;
  int resize_handle;
  int maximized;
  proton_linux_titlebar_rect_t controls;
  proton_linux_titlebar_rect_t fallback_drag;
  int draggable_regions_reported;
  size_t draggable_region_count;
  const proton_linux_titlebar_region_t *draggable_regions;
} proton_linux_titlebar_hit_test_input_t;

int proton_linux_titlebar_device_to_logical(int coordinate,
                                            int device_extent,
                                            int logical_extent);

int proton_linux_titlebar_control_margin(int resize_handle);

int proton_linux_titlebar_point_in_draggable_regions(
    proton_linux_titlebar_point_t point,
    size_t region_count,
    const proton_linux_titlebar_region_t *regions);

proton_linux_titlebar_hit_t proton_linux_titlebar_hit_test(
    const proton_linux_titlebar_hit_test_input_t *input);

#endif
