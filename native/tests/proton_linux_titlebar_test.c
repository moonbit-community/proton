#include "proton_linux_titlebar.h"

#include <stdio.h>

static int expect_hit(const char *name,
                      proton_linux_titlebar_hit_t actual,
                      proton_linux_titlebar_hit_t expected) {
  if (actual == expected) {
    return 0;
  }
  fprintf(stderr, "%s expected hit %d, got %d\n", name, expected, actual);
  return 1;
}

static proton_linux_titlebar_hit_test_input_t input_for_scale(
    int scale_percent) {
  const int resize_handle = 12 * scale_percent / 100;
  const int controls_width = 120 * scale_percent / 100;
  proton_linux_titlebar_hit_test_input_t input = {
      .width = 800 * scale_percent / 100,
      .height = 600 * scale_percent / 100,
      .resize_handle = resize_handle,
      .controls =
          {
              .x = 800 * scale_percent / 100 - resize_handle - controls_width,
              .y = proton_linux_titlebar_control_margin(resize_handle),
              .width = controls_width,
              .height = 36 * scale_percent / 100,
          },
      .fallback_drag =
          {
              .x = 12 * scale_percent / 100,
              .y = 12 * scale_percent / 100,
              .width = 36 * scale_percent / 100,
              .height = 24 * scale_percent / 100,
          },
  };
  return input;
}

static int test_resize_edges_and_corners(int scale_percent) {
  proton_linux_titlebar_hit_test_input_t input =
      input_for_scale(scale_percent);
  const int edge = input.resize_handle / 2;
  int failures = 0;
  input.point = (proton_linux_titlebar_point_t){edge, edge};
  failures += expect_hit("north-west", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_WEST);
  input.point =
      (proton_linux_titlebar_point_t){input.width - edge - 1, edge};
  failures += expect_hit("north-east", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH_EAST);
  input.point = (proton_linux_titlebar_point_t){
      input.width - edge - 1, input.height - edge - 1};
  failures += expect_hit("south-east", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_EAST);
  input.point = (proton_linux_titlebar_point_t){edge,
                                                input.height - edge - 1};
  failures += expect_hit("south-west", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH_WEST);
  input.point = (proton_linux_titlebar_point_t){edge, input.height / 2};
  failures += expect_hit("west", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_WEST);
  input.point = (proton_linux_titlebar_point_t){input.width - edge - 1,
                                                input.height / 2};
  failures += expect_hit("east", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST);
  input.point = (proton_linux_titlebar_point_t){input.width / 2, edge};
  failures += expect_hit("north", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH);
  input.point = (proton_linux_titlebar_point_t){input.width / 2,
                                                input.height - edge - 1};
  failures += expect_hit("south", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_SOUTH);
  return failures;
}

static int test_controls_drag_and_content(int scale_percent) {
  proton_linux_titlebar_hit_test_input_t input =
      input_for_scale(scale_percent);
  int failures = 0;
  input.point = (proton_linux_titlebar_point_t){
      input.controls.x + input.controls.width / 2,
      input.controls.y + input.controls.height / 2};
  failures += expect_hit("native controls",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CONTROLS);
  input.point = (proton_linux_titlebar_point_t){
      input.controls.x + input.controls.width / 2, input.controls.y};
  failures += expect_hit("native controls over top resize band",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CONTROLS);
  input.point = (proton_linux_titlebar_point_t){
      input.controls.x + input.controls.width / 2, input.controls.y - 1};
  failures += expect_hit("top resize above native controls",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_NORTH);
  input.point = (proton_linux_titlebar_point_t){
      input.width - 1, input.controls.y + input.controls.height / 2};
  failures += expect_hit("right resize beside native controls",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_RESIZE_EAST);
  input.point = (proton_linux_titlebar_point_t){
      input.fallback_drag.x + input.fallback_drag.width / 2,
      input.fallback_drag.y + input.fallback_drag.height / 2};
  failures += expect_hit("fallback drag",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_DRAG);
  input.point = (proton_linux_titlebar_point_t){input.width / 2,
                                                input.height / 2};
  failures += expect_hit("ordinary content",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CLIENT);
  input.maximized = 1;
  input.point = (proton_linux_titlebar_point_t){0, input.height / 2};
  failures += expect_hit("maximized edge",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CLIENT);
  return failures;
}

static int test_web_regions(int scale_percent) {
  const proton_linux_titlebar_region_t regions[] = {
      {
          .x = 0,
          .y = 0,
          .width = 800 * scale_percent / 100,
          .height = 40 * scale_percent / 100,
          .draggable = 1,
      },
      {
          .x = 280 * scale_percent / 100,
          .y = 4 * scale_percent / 100,
          .width = 240 * scale_percent / 100,
          .height = 32 * scale_percent / 100,
          .draggable = 0,
      },
  };
  proton_linux_titlebar_hit_test_input_t input =
      input_for_scale(scale_percent);
  input.draggable_regions_reported = 1;
  input.draggable_regions = regions;
  input.draggable_region_count = sizeof(regions) / sizeof(regions[0]);
  int failures = 0;
  input.point = (proton_linux_titlebar_point_t){100 * scale_percent / 100,
                                                24 * scale_percent / 100};
  failures += expect_hit("web drag", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_DRAG);
  input.point = (proton_linux_titlebar_point_t){320 * scale_percent / 100,
                                                24 * scale_percent / 100};
  failures += expect_hit("web no-drag",
                         proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CLIENT);
  input.point = (proton_linux_titlebar_point_t){100 * scale_percent / 100,
                                                80 * scale_percent / 100};
  failures += expect_hit("web body", proton_linux_titlebar_hit_test(&input),
                         PROTON_LINUX_TITLEBAR_HIT_CLIENT);
  return failures;
}

static int test_device_scale_conversion(void) {
  const int scales[] = {100, 125, 150, 200};
  int failures = 0;
  for (size_t i = 0; i < sizeof(scales) / sizeof(scales[0]); i++) {
    const int device_extent = 800 * scales[i] / 100;
    const int device_point = 320 * scales[i] / 100;
    const int logical = proton_linux_titlebar_device_to_logical(
        device_point, device_extent, 800);
    if (logical != 320) {
      fprintf(stderr, "%d%% scale expected logical 320, got %d\n", scales[i],
              logical);
      failures++;
    }
  }
  return failures;
}

int main(void) {
  const int scales[] = {100, 125, 150, 200};
  int failures = test_device_scale_conversion();
  for (size_t i = 0; i < sizeof(scales) / sizeof(scales[0]); i++) {
    failures += test_resize_edges_and_corners(scales[i]);
    failures += test_controls_drag_and_content(scales[i]);
    failures += test_web_regions(scales[i]);
  }
  return failures == 0 ? 0 : 1;
}
