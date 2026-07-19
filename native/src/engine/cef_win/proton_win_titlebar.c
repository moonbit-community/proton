#include "proton_win_titlebar.h"

static int proton_win_is_caption_button_hit(LRESULT hit_test) {
  return hit_test == HTMINBUTTON || hit_test == HTMAXBUTTON ||
         hit_test == HTCLOSE;
}

LRESULT proton_win_titlebar_caption_button_hit(POINT point,
                                               const RECT *button_bounds) {
  if (button_bounds == NULL || point.x < button_bounds->left ||
      point.x >= button_bounds->right || point.y < button_bounds->top ||
      point.y >= button_bounds->bottom) {
    return HTNOWHERE;
  }
  const LONG total_width = button_bounds->right - button_bounds->left;
  if (total_width < 3) {
    return HTNOWHERE;
  }
  const LONG button_width = total_width / 3;
  if (point.x < button_bounds->left + button_width) {
    return HTMINBUTTON;
  }
  if (point.x < button_bounds->left + button_width * 2) {
    return HTMAXBUTTON;
  }
  return HTCLOSE;
}

int proton_win_titlebar_point_in_draggable_regions(
    POINT point,
    size_t region_count,
    const proton_win_titlebar_region_t *regions) {
  if (region_count == 0 || regions == NULL) {
    return 0;
  }
  int draggable = 0;
  for (size_t i = 0; i < region_count; i++) {
    const proton_win_titlebar_region_t *region = &regions[i];
    const int64_t right = (int64_t)region->x + region->width;
    const int64_t bottom = (int64_t)region->y + region->height;
    const int inside =
        region->width > 0 && region->height > 0 && point.x >= region->x &&
        (int64_t)point.x < right && point.y >= region->y &&
        (int64_t)point.y < bottom;
    if (inside && region->draggable) {
      draggable = 1;
    }
  }
  if (!draggable) {
    return 0;
  }
  for (size_t i = 0; i < region_count; i++) {
    const proton_win_titlebar_region_t *region = &regions[i];
    const int64_t right = (int64_t)region->x + region->width;
    const int64_t bottom = (int64_t)region->y + region->height;
    const int inside =
        region->width > 0 && region->height > 0 && point.x >= region->x &&
        (int64_t)point.x < right && point.y >= region->y &&
        (int64_t)point.y < bottom;
    if (inside && !region->draggable) {
      return 0;
    }
  }
  return 1;
}

LRESULT proton_win_titlebar_hit_test(
    const proton_win_titlebar_hit_test_input_t *input) {
  if (input == NULL || input->width <= 0 || input->height <= 0) {
    return HTNOWHERE;
  }

  if (proton_win_is_caption_button_hit(input->system_hit_test)) {
    return input->system_hit_test;
  }

  const int inside_x = input->x >= 0 && input->x < input->width;
  const int inside_y = input->y >= 0 && input->y < input->height;
  if (!inside_x || !inside_y) {
    return HTNOWHERE;
  }

  if (!input->maximized) {
    const int on_left = input->x < input->resize_border_x;
    const int on_right = input->x >= input->width - input->resize_border_x;
    const int on_top = input->y < input->resize_border_y;
    const int on_bottom =
        input->y >= input->height - input->resize_border_y;

    if (on_top && on_left) {
      return HTTOPLEFT;
    }
    if (on_top && on_right) {
      return HTTOPRIGHT;
    }
    if (on_bottom && on_left) {
      return HTBOTTOMLEFT;
    }
    if (on_bottom && on_right) {
      return HTBOTTOMRIGHT;
    }
    if (on_left) {
      return HTLEFT;
    }
    if (on_right) {
      return HTRIGHT;
    }
    if (on_top) {
      return HTTOP;
    }
    if (on_bottom) {
      return HTBOTTOM;
    }
  }

  if (input->x >= input->drag_strip_left &&
      input->x < input->drag_strip_right &&
      input->y >= input->drag_strip_top &&
      input->y < input->drag_strip_bottom) {
    return HTCAPTION;
  }
  return HTCLIENT;
}
