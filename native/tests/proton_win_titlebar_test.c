#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "proton_win_titlebar.h"

#include <stdio.h>

static int expect_hit(const char *name, LRESULT actual, LRESULT expected) {
  if (actual == expected) {
    return 0;
  }
  fprintf(stderr, "%s: expected %ld, got %ld\n", name, (long)expected,
          (long)actual);
  return 1;
}

static proton_win_titlebar_hit_test_input_t input_for_dpi(int dpi) {
  const int border = MulDiv(8, dpi, USER_DEFAULT_SCREEN_DPI);
  const int caption = MulDiv(23, dpi, USER_DEFAULT_SCREEN_DPI);
  const int caption_button = MulDiv(46, dpi, USER_DEFAULT_SCREEN_DPI);
  proton_win_titlebar_hit_test_input_t input = {
      .x = 0,
      .y = 0,
      .width = MulDiv(800, dpi, USER_DEFAULT_SCREEN_DPI),
      .height = MulDiv(600, dpi, USER_DEFAULT_SCREEN_DPI),
      .resize_border_x = border,
      .resize_border_y = border,
      .drag_strip_left = border,
      .drag_strip_right = border + caption_button,
      .drag_strip_top = border,
      .drag_strip_bottom = border + caption,
      .maximized = 0,
      .system_hit_test = HTNOWHERE,
  };
  return input;
}

static int test_resize_edges_and_corners(int dpi) {
  proton_win_titlebar_hit_test_input_t input = input_for_dpi(dpi);
  int failures = 0;
  const int middle_x = input.width / 2;
  const int middle_y = input.height / 2;

  input.x = 0;
  input.y = 0;
  failures += expect_hit("top-left", proton_win_titlebar_hit_test(&input),
                         HTTOPLEFT);
  input.x = input.width - 1;
  failures += expect_hit("top-right", proton_win_titlebar_hit_test(&input),
                         HTTOPRIGHT);
  input.y = input.height - 1;
  failures += expect_hit("bottom-right", proton_win_titlebar_hit_test(&input),
                         HTBOTTOMRIGHT);
  input.x = 0;
  failures += expect_hit("bottom-left", proton_win_titlebar_hit_test(&input),
                         HTBOTTOMLEFT);

  input.x = 0;
  input.y = middle_y;
  failures +=
      expect_hit("left", proton_win_titlebar_hit_test(&input), HTLEFT);
  input.x = input.width - 1;
  failures +=
      expect_hit("right", proton_win_titlebar_hit_test(&input), HTRIGHT);
  input.x = middle_x;
  input.y = 0;
  failures += expect_hit("top", proton_win_titlebar_hit_test(&input), HTTOP);
  input.y = input.height - 1;
  failures +=
      expect_hit("bottom", proton_win_titlebar_hit_test(&input), HTBOTTOM);
  return failures;
}

static int test_caption_buttons(int dpi) {
  proton_win_titlebar_hit_test_input_t input = input_for_dpi(dpi);
  const int system_button_width =
      input.drag_strip_right - input.drag_strip_left;
  RECT buttons = {
      .left = input.width - system_button_width * 3,
      .top = 0,
      .right = input.width,
      .bottom = input.drag_strip_bottom,
  };
  const int button_width = (buttons.right - buttons.left) / 3;
  POINT point = {
      .x = buttons.left + button_width / 2,
      .y = buttons.top + 1,
  };
  input.x = point.x;
  input.y = point.y;

  input.system_hit_test =
      proton_win_titlebar_caption_button_hit(point, &buttons);
  if (expect_hit("minimize button", proton_win_titlebar_hit_test(&input),
                 HTMINBUTTON)) {
    return 1;
  }
  point.x = buttons.left + button_width + button_width / 2;
  input.x = point.x;
  input.system_hit_test =
      proton_win_titlebar_caption_button_hit(point, &buttons);
  if (expect_hit("maximize button", proton_win_titlebar_hit_test(&input),
                 HTMAXBUTTON)) {
    return 1;
  }
  point.x = buttons.left + button_width * 2 + button_width / 2;
  input.x = point.x;
  input.system_hit_test =
      proton_win_titlebar_caption_button_hit(point, &buttons);
  return expect_hit("close button", proton_win_titlebar_hit_test(&input),
                    HTCLOSE);
}

static int test_content_drag_and_maximized(int dpi) {
  proton_win_titlebar_hit_test_input_t input = input_for_dpi(dpi);
  input.x = input.drag_strip_left;
  input.y = input.drag_strip_top;
  if (expect_hit("leading drag handle", proton_win_titlebar_hit_test(&input),
                 HTCAPTION)) {
    return 1;
  }

  input.x = input.drag_strip_right;
  if (expect_hit("titlebar web control", proton_win_titlebar_hit_test(&input),
                 HTCLIENT)) {
    return 1;
  }

  input.x = input.width / 2;
  if (expect_hit("caption-band web content",
                 proton_win_titlebar_hit_test(&input), HTCLIENT)) {
    return 1;
  }

  input.y = input.drag_strip_bottom + 1;
  if (expect_hit("web content", proton_win_titlebar_hit_test(&input),
                 HTCLIENT)) {
    return 1;
  }

  input.maximized = 1;
  input.drag_strip_left = 0;
  input.drag_strip_right -= input.resize_border_x;
  input.drag_strip_top = 0;
  input.drag_strip_bottom -= input.resize_border_y;
  input.x = 0;
  input.y = input.height / 2;
  if (expect_hit("maximized left edge", proton_win_titlebar_hit_test(&input),
                 HTCLIENT)) {
    return 1;
  }
  input.x = input.drag_strip_left;
  input.y = 0;
  if (expect_hit("maximized drag handle",
                 proton_win_titlebar_hit_test(&input),
                 HTCAPTION)) {
    return 1;
  }
  input.x = input.drag_strip_right;
  if (expect_hit("maximized titlebar web control",
                 proton_win_titlebar_hit_test(&input), HTCLIENT)) {
    return 1;
  }
  input.system_hit_test = HTMAXBUTTON;
  return expect_hit("maximized button while maximized",
                    proton_win_titlebar_hit_test(&input), HTMAXBUTTON);
}

static int test_web_draggable_regions(int dpi) {
  const proton_win_titlebar_region_t regions[] = {
      {.x = 0,
       .y = 0,
       .width = MulDiv(800, dpi, USER_DEFAULT_SCREEN_DPI),
       .height = MulDiv(40, dpi, USER_DEFAULT_SCREEN_DPI),
       .draggable = 1},
      {.x = MulDiv(280, dpi, USER_DEFAULT_SCREEN_DPI),
       .y = MulDiv(4, dpi, USER_DEFAULT_SCREEN_DPI),
       .width = MulDiv(240, dpi, USER_DEFAULT_SCREEN_DPI),
       .height = MulDiv(32, dpi, USER_DEFAULT_SCREEN_DPI),
       .draggable = 0},
  };
  POINT drag_point = {
      .x = MulDiv(100, dpi, USER_DEFAULT_SCREEN_DPI),
      .y = MulDiv(20, dpi, USER_DEFAULT_SCREEN_DPI),
  };
  POINT control_point = {
      .x = MulDiv(320, dpi, USER_DEFAULT_SCREEN_DPI),
      .y = MulDiv(20, dpi, USER_DEFAULT_SCREEN_DPI),
  };
  POINT content_point = {
      .x = MulDiv(100, dpi, USER_DEFAULT_SCREEN_DPI),
      .y = MulDiv(80, dpi, USER_DEFAULT_SCREEN_DPI),
  };
  if (!proton_win_titlebar_point_in_draggable_regions(
          drag_point, sizeof(regions) / sizeof(regions[0]), regions)) {
    fprintf(stderr, "web drag region was not draggable at %d DPI\n", dpi);
    return 1;
  }
  if (proton_win_titlebar_point_in_draggable_regions(
          control_point, sizeof(regions) / sizeof(regions[0]), regions)) {
    fprintf(stderr, "web no-drag control was draggable at %d DPI\n", dpi);
    return 1;
  }
  if (proton_win_titlebar_point_in_draggable_regions(
          content_point, sizeof(regions) / sizeof(regions[0]), regions)) {
    fprintf(stderr, "web content outside titlebar was draggable at %d DPI\n",
            dpi);
    return 1;
  }
  return 0;
}

int main(void) {
  const int dpis[] = {96, 120, 144, 192};
  int failures = 0;
  for (size_t i = 0; i < sizeof(dpis) / sizeof(dpis[0]); i++) {
    failures += test_resize_edges_and_corners(dpis[i]);
    failures += test_caption_buttons(dpis[i]);
    failures += test_content_drag_and_maximized(dpis[i]);
    failures += test_web_draggable_regions(dpis[i]);
  }
  return failures == 0 ? 0 : 1;
}
