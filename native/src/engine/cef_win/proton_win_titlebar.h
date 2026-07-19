#ifndef PROTON_WIN_TITLEBAR_H
#define PROTON_WIN_TITLEBAR_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

typedef struct {
  int x;
  int y;
  int width;
  int height;
  int resize_border_x;
  int resize_border_y;
  int drag_strip_left;
  int drag_strip_right;
  int drag_strip_top;
  int drag_strip_bottom;
  int maximized;
  LRESULT system_hit_test;
} proton_win_titlebar_hit_test_input_t;

LRESULT proton_win_titlebar_hit_test(
    const proton_win_titlebar_hit_test_input_t *input);

LRESULT proton_win_titlebar_caption_button_hit(POINT point,
                                               const RECT *button_bounds);

#endif
