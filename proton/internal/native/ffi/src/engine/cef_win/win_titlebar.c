#if defined(_WIN32)

#include "win_internal.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <string.h>
#include <windowsx.h>

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

int proton_engine_overlay_frame_top_thickness(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

int proton_engine_overlay_caption_band_height(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  return proton_engine_overlay_frame_top_thickness(hwnd) +
         GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
}

int proton_engine_overlay_caption_buttons_rect(HWND hwnd, RECT *out) {
  if (hwnd == NULL || out == NULL) {
    return 0;
  }
  TITLEBARINFOEX info;
  memset(&info, 0, sizeof(info));
  info.cbSize = sizeof(info);
  SendMessageW(hwnd, WM_GETTITLEBARINFOEX, 0, (LPARAM)&info);

  const int indices[] = {2, 3, 5};
  RECT cluster = {0};
  int found = 0;
  for (size_t i = 0; i < sizeof(indices) / sizeof(indices[0]); i++) {
    RECT rect = info.rgrect[indices[i]];
    if (rect.right <= rect.left || rect.bottom <= rect.top) {
      continue;
    }
    if (!found) {
      cluster = rect;
      found = 1;
    } else {
      cluster.left = min(cluster.left, rect.left);
      cluster.top = min(cluster.top, rect.top);
      cluster.right = max(cluster.right, rect.right);
      cluster.bottom = max(cluster.bottom, rect.bottom);
    }
  }
  if (!found) {
    return 0;
  }

  POINT top_left = {cluster.left, cluster.top};
  POINT bottom_right = {cluster.right, cluster.bottom};
  if (!ScreenToClient(hwnd, &top_left) ||
      !ScreenToClient(hwnd, &bottom_right)) {
    return 0;
  }
  out->left = top_left.x;
  out->top = top_left.y;
  out->right = bottom_right.x;
  out->bottom = bottom_right.y;
  return out->right > out->left && out->bottom > out->top;
}

void proton_engine_overlay_apply_frame(HWND hwnd) {
  MARGINS margins = {
      .cxLeftWidth = 0,
      .cxRightWidth = 0,
      .cyTopHeight = proton_engine_overlay_caption_band_height(hwnd),
      .cyBottomHeight = 0,
  };
  (void)DwmExtendFrameIntoClientArea(hwnd, &margins);
}

static int proton_engine_overlay_drag_strip_rect(HWND hwnd, RECT *out) {
  if (hwnd == NULL || out == NULL) {
    return 0;
  }

  RECT client;
  RECT window_rect;
  if (!GetClientRect(hwnd, &client) || !GetWindowRect(hwnd, &window_rect)) {
    return 0;
  }

  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  const int padded_border =
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border;
  const int caption_height = GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
  int drag_handle_width = GetSystemMetricsForDpi(SM_CXSIZE, dpi);

  RECT caption_buttons;
  const int has_caption_buttons =
      proton_engine_overlay_caption_buttons_rect(hwnd, &caption_buttons);
  if (has_caption_buttons) {
    const int live_caption_button_width =
        (caption_buttons.right - caption_buttons.left) / 3;
    if (live_caption_button_width > 0) {
      drag_handle_width = live_caption_button_width;
    }
  }

  POINT client_origin = {0, 0};
  if (!ClientToScreen(hwnd, &client_origin)) {
    return 0;
  }
  const int client_top = client_origin.y - window_rect.top;
  const int drag_top_in_window = IsZoomed(hwnd) ? client_top : resize_border_y;

  out->left = client.left;
  out->right = min(client.right, client.left + drag_handle_width);
  out->top = max(client.top, drag_top_in_window - client_top);
  out->bottom = has_caption_buttons
                    ? min(client.bottom, caption_buttons.bottom)
                    : min(client.bottom, out->top + caption_height);
  return out->right > out->left && out->bottom > out->top;
}

static void proton_engine_overlay_subtract_rect(HRGN destination,
                                                const RECT *rect) {
  if (destination == NULL || rect == NULL || rect->right <= rect->left ||
      rect->bottom <= rect->top) {
    return;
  }
  HRGN region =
      CreateRectRgn(rect->left, rect->top, rect->right, rect->bottom);
  if (region != NULL) {
    CombineRgn(destination, destination, region, RGN_DIFF);
    DeleteObject(region);
  }
}

LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam);

static LRESULT CALLBACK proton_engine_overlay_child_proc(
    HWND hwnd,
    UINT msg,
    WPARAM wparam,
    LPARAM lparam,
    UINT_PTR subclass_id,
    DWORD_PTR ref_data) {
  proton_engine_window_t *window = (proton_engine_window_t *)ref_data;
  if (msg == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, proton_engine_overlay_child_proc, subclass_id);
    return DefSubclassProc(hwnd, msg, wparam, lparam);
  }
  if (window == NULL || !window->titlebar_overlay || window->hwnd == NULL ||
      !IsWindow(window->hwnd)) {
    return DefSubclassProc(hwnd, msg, wparam, lparam);
  }

  if (msg == WM_PARENTNOTIFY && LOWORD(wparam) == WM_CREATE) {
    HWND child = (HWND)lparam;
    if (child != NULL) {
      SetWindowSubclass(child, proton_engine_overlay_child_proc, subclass_id,
                        ref_data);
    }
  }

  if (msg == WM_NCHITTEST) {
    LRESULT hit = proton_engine_overlay_hit_test(window->hwnd, lparam);
    if (hit != HTCLIENT && hit != HTNOWHERE) {
      return hit;
    }
  } else if ((msg == WM_NCLBUTTONDOWN || msg == WM_NCLBUTTONUP ||
              msg == WM_NCLBUTTONDBLCLK || msg == WM_NCRBUTTONDOWN ||
              msg == WM_NCRBUTTONUP || msg == WM_NCRBUTTONDBLCLK) &&
             wparam != HTCLIENT && wparam != HTNOWHERE) {
    return SendMessageW(window->hwnd, msg, wparam, lparam);
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

static BOOL CALLBACK proton_engine_overlay_subclass_descendant(HWND hwnd,
                                                               LPARAM data) {
  (void)SetWindowSubclass(hwnd, proton_engine_overlay_child_proc, 1,
                          (DWORD_PTR)data);
  return TRUE;
}

void proton_engine_overlay_subclass_browser(
    proton_engine_window_t *window,
    HWND browser_hwnd) {
  if (window == NULL || browser_hwnd == NULL || !window->titlebar_overlay) {
    return;
  }
  (void)SetWindowSubclass(browser_hwnd, proton_engine_overlay_child_proc, 1,
                          (DWORD_PTR)window);
  EnumChildWindows(browser_hwnd, proton_engine_overlay_subclass_descendant,
                   (LPARAM)window);
}

void proton_engine_resize_browser(proton_engine_window_t *window,
                                  int width,
                                  int height) {
  if (window == NULL || proton_engine_window_browser(window) == NULL) {
    return;
  }
  cef_browser_host_t *host = proton_engine_window_browser(window)->get_host(proton_engine_window_browser(window));
  if (host == NULL) {
    return;
  }
  if (window->headless) {
    if (host->was_resized != NULL) {
      host->was_resized(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
    return;
  }
  HWND child = host->get_window_handle(host);
  if (child != NULL) {
    SetWindowPos(child, NULL, 0, 0, width, height, SWP_NOZORDER);
    if (window->titlebar_overlay) {
      proton_engine_overlay_subclass_browser(window, child);
      RECT client;
      if (GetClientRect(window->hwnd, &client)) {
        HRGN browser_region = CreateRectRgn(client.left, client.top,
                                            client.right, client.bottom);
        RECT cluster;
        if (browser_region != NULL &&
            proton_engine_overlay_caption_buttons_rect(window->hwnd,
                                                        &cluster)) {
          cluster.left = max(cluster.left, client.left);
          cluster.top = max(cluster.top, client.top);
          cluster.right = min(cluster.right, client.right);
          cluster.bottom = min(cluster.bottom, client.bottom);
          proton_engine_overlay_subtract_rect(browser_region, &cluster);
        }
        if (browser_region != NULL) {
          if (SetWindowRgn(child, browser_region, TRUE) != 0) {
            browser_region = NULL;
          }
          if (browser_region != NULL) {
            DeleteObject(browser_region);
          }
        }
      }
    }
  }
  host->base.release((cef_base_ref_counted_t *)host);
}

LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam) {
  LRESULT system_hit_test = HTNOWHERE;
  (void)DwmDefWindowProc(hwnd, WM_NCHITTEST, 0, lparam, &system_hit_test);

  POINT client_point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ScreenToClient(hwnd, &client_point);
  RECT caption_buttons;
  const int has_caption_buttons =
      proton_engine_overlay_caption_buttons_rect(hwnd, &caption_buttons);
  if (has_caption_buttons) {
    LRESULT caption_hit = proton_win_titlebar_caption_button_hit(
        client_point, &caption_buttons);
    if (caption_hit != HTNOWHERE) {
      system_hit_test = caption_hit;
    }
  }

  RECT window_rect;
  if (!GetWindowRect(hwnd, &window_rect)) {
    return DefWindowProcW(hwnd, WM_NCHITTEST, 0, lparam);
  }

  UINT dpi = GetDpiForWindow(hwnd);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  const int padded_border =
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_x =
      GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padded_border;
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border;
  const int maximized = IsZoomed(hwnd);
  POINT client_origin = {0, 0};
  ClientToScreen(hwnd, &client_origin);
  const int client_left = client_origin.x - window_rect.left;
  const int client_top = client_origin.y - window_rect.top;
  RECT drag_strip = {0};
  proton_engine_window_t *window =
      (proton_engine_window_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  if (window == NULL || !window->draggable_regions_reported) {
    (void)proton_engine_overlay_drag_strip_rect(hwnd, &drag_strip);
  }

  proton_win_titlebar_hit_test_input_t input = {
      .x = GET_X_LPARAM(lparam) - window_rect.left,
      .y = GET_Y_LPARAM(lparam) - window_rect.top,
      .width = window_rect.right - window_rect.left,
      .height = window_rect.bottom - window_rect.top,
      .resize_border_x = resize_border_x,
      .resize_border_y = resize_border_y,
      .drag_strip_left = client_left + drag_strip.left,
      .drag_strip_right = client_left + drag_strip.right,
      .drag_strip_top = client_top + drag_strip.top,
      .drag_strip_bottom = client_top + drag_strip.bottom,
      .maximized = maximized,
      .system_hit_test = system_hit_test,
  };
  LRESULT hit = proton_win_titlebar_hit_test(&input);
  if (hit == HTCLIENT && window != NULL &&
      proton_win_titlebar_point_in_draggable_regions(
          client_point, window->draggable_region_count,
          window->draggable_regions)) {
    return HTCAPTION;
  }
  return hit;
}

#endif
