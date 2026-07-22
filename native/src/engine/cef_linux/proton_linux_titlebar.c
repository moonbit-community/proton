#include "proton_linux_titlebar.h"

#include <stdint.h>

static int proton_linux_titlebar_point_in_rect(
    proton_linux_titlebar_point_t point,
    proton_linux_titlebar_rect_t rect) {
  const int64_t right = (int64_t)rect.x + rect.width;
  const int64_t bottom = (int64_t)rect.y + rect.height;
  return rect.width > 0 && rect.height > 0 && point.x >= rect.x &&
         (int64_t)point.x < right && point.y >= rect.y &&
         (int64_t)point.y < bottom;
}

int proton_linux_titlebar_device_to_logical(int coordinate,
                                            int device_extent,
                                            int logical_extent) {
  if (device_extent <= 0 || logical_extent <= 0) {
    return coordinate;
  }
  return (int)(((int64_t)coordinate * logical_extent) / device_extent);
}

int proton_linux_titlebar_control_margin(int resize_handle) {
  return resize_handle > 0 ? (resize_handle + 1) / 2 : 0;
}

int proton_linux_titlebar_point_in_draggable_regions(
    proton_linux_titlebar_point_t point,
    size_t region_count,
    const proton_linux_titlebar_region_t *regions) {
  if (region_count == 0 || regions == NULL) {
    return 0;
  }
  int draggable = 0;
  for (size_t i = 0; i < region_count; i++) {
    proton_linux_titlebar_rect_t rect = {
        .x = regions[i].x,
        .y = regions[i].y,
        .width = regions[i].width,
        .height = regions[i].height,
    };
    if (regions[i].draggable &&
        proton_linux_titlebar_point_in_rect(point, rect)) {
      draggable = 1;
    }
  }
  if (!draggable) {
    return 0;
  }
  for (size_t i = 0; i < region_count; i++) {
    proton_linux_titlebar_rect_t rect = {
        .x = regions[i].x,
        .y = regions[i].y,
        .width = regions[i].width,
        .height = regions[i].height,
    };
    if (!regions[i].draggable &&
        proton_linux_titlebar_point_in_rect(point, rect)) {
      return 0;
    }
  }
  return 1;
}

proton_linux_titlebar_hit_t proton_linux_titlebar_hit_test(
    const proton_linux_titlebar_hit_test_input_t *input) {
  if (input == NULL || input->width <= 0 || input->height <= 0) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }
  const proton_linux_titlebar_point_t point = input->point;
  if (point.x < 0 || point.x >= input->width || point.y < 0 ||
      point.y >= input->height) {
    return PROTON_LINUX_TITLEBAR_HIT_NONE;
  }

  if (proton_linux_titlebar_point_in_rect(point, input->controls)) {
    return PROTON_LINUX_TITLEBAR_HIT_CONTROLS;
  }

  if (!input->maximized && input->resize_handle > 0) {
    const int on_left = point.x < input->resize_handle;
    const int on_right = point.x >= input->width - input->resize_handle;
    const int on_top = point.y < input->resize_handle;
    const int on_bottom = point.y >= input->height - input->resize_handle;
    if (on_top && on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST;
    }
    if (on_top && on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST;
    }
    if (on_bottom && on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST;
    }
    if (on_bottom && on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST;
    }
    if (on_left) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST;
    }
    if (on_right) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST;
    }
    if (on_top) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH;
    }
    if (on_bottom) {
      return PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH;
    }
  }

  if (input->draggable_regions_reported) {
    return proton_linux_titlebar_point_in_draggable_regions(
               point, input->draggable_region_count,
               input->draggable_regions)
               ? PROTON_LINUX_TITLEBAR_HIT_DRAG
               : PROTON_LINUX_TITLEBAR_HIT_CLIENT;
  }
  if (proton_linux_titlebar_point_in_rect(point, input->fallback_drag)) {
    return PROTON_LINUX_TITLEBAR_HIT_DRAG;
  }
  return PROTON_LINUX_TITLEBAR_HIT_CLIENT;
}
