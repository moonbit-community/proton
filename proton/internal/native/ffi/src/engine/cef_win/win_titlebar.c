#if defined(_WIN32)

#include "win_internal.h"
#include "win_geometry.h"

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
    UINT dpi,
    size_t region_count,
    const proton_win_titlebar_region_t *regions) {
  if (region_count == 0 || regions == NULL) {
    return 0;
  }
  /* WM_NCHITTEST arrives in device pixels, but CEF reports view DIPs.
   * Keep fractional coordinates: rounding to the nearest DIP can move the
   * last physical pixel of a no-drag button outside its half-open bounds.
   * Convert at hit time so moving between monitors uses the current DPI. */
  const double x = (double)point.x * USER_DEFAULT_SCREEN_DPI / dpi;
  const double y = (double)point.y * USER_DEFAULT_SCREEN_DPI / dpi;
  int draggable = 0;
  for (size_t i = 0; i < region_count; i++) {
    const proton_win_titlebar_region_t *region = &regions[i];
    const int64_t right = (int64_t)region->x + region->width;
    const int64_t bottom = (int64_t)region->y + region->height;
    const int inside =
        region->width > 0 && region->height > 0 && x >= region->x &&
        x < right && y >= region->y && y < bottom;
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
        region->width > 0 && region->height > 0 && x >= region->x &&
        x < right && y >= region->y && y < bottom;
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

int proton_engine_overlay_controls_rect(const proton_engine_window_t *window,
                                        RECT *out) {
  if (window->custom_titlebar.height == 0) {
    return proton_engine_overlay_caption_buttons_rect(window->hwnd, out);
  }
  RECT client;
  if (window->fullscreen || !GetClientRect(window->hwnd, &client) ||
      IsIconic(window->hwnd)) {
    return 0;
  }
  const UINT dpi = proton_win_window_dpi(window->hwnd);
  const int button_width =
      min(proton_win_pixels(46, dpi), (client.right - client.left) / 3);
  *out = (RECT){
      .left = client.right - 3 * button_width,
      .top = client.top,
      .right = client.right,
      .bottom = client.top +
                min(client.bottom - client.top,
                    proton_win_pixels(window->custom_titlebar.height, dpi)),
  };
  return out->left < out->right && out->top < out->bottom;
}

void proton_engine_overlay_apply_frame(proton_engine_window_t *window) {
  // Keep the Win32 frame styles (resize, system menu, Snap), but do not
  // extend the DWM caption surface into a host-drawn overlay.
  MARGINS margins = {0};
  if (window->custom_titlebar.height == 0) {
    margins.cyTopHeight =
        proton_engine_overlay_caption_band_height(window->hwnd);
  }
  (void)DwmExtendFrameIntoClientArea(window->hwnd, &margins);
}

static UINT
proton_win_custom_titlebar_command(const proton_engine_window_t *window,
                                   LRESULT button) {
  const LONG style = GetWindowLongW(window->hwnd, GWL_STYLE);
  switch (button) {
  case HTMINBUTTON:
    return (style & WS_MINIMIZEBOX) ? SC_MINIMIZE : 0;
  case HTMAXBUTTON:
    return (style & WS_MAXIMIZEBOX)
               ? (IsZoomed(window->hwnd) ? SC_RESTORE : SC_MAXIMIZE)
               : 0;
  case HTCLOSE:
    return window->closable ? SC_CLOSE : 0;
  default:
    return 0;
  }
}

static void proton_win_custom_titlebar_glyph(HDC dc, RECT rect, LRESULT button,
                                             UINT command, UINT dpi,
                                             COLORREF color) {
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  const int size = min(proton_win_pixels(10, dpi), min(width, height) - 2);
  if (size < 3) {
    return;
  }
  const int x = rect.left + (width - size) / 2;
  const int y = rect.top + (height - size) / 2;
  const int end = size - 1;
  HPEN pen = CreatePen(PS_SOLID, max(1, proton_win_pixels(1, dpi)), color);
  if (pen == NULL) {
    return;
  }
  HGDIOBJ old_pen = SelectObject(dc, pen);
  HGDIOBJ old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
  if (button == HTMINBUTTON) {
    MoveToEx(dc, x, y + size / 2, NULL);
    LineTo(dc, x + size, y + size / 2);
  } else if (button == HTMAXBUTTON && command == SC_RESTORE) {
    const int offset = max(1, size / 4);
    Rectangle(dc, x, y + offset, x + size - offset, y + size);
    MoveToEx(dc, x + offset, y + offset, NULL);
    LineTo(dc, x + offset, y);
    LineTo(dc, x + end, y);
    LineTo(dc, x + end, y + end - offset);
    LineTo(dc, x + end - offset, y + end - offset);
  } else if (button == HTMAXBUTTON) {
    Rectangle(dc, x, y, x + size, y + size);
  } else {
    MoveToEx(dc, x, y, NULL);
    LineTo(dc, x + size, y + size);
    MoveToEx(dc, x + end, y, NULL);
    LineTo(dc, x - 1, y + size);
  }
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(pen);
}

void proton_engine_custom_titlebar_paint(proton_engine_window_t *window,
                                         HDC dc) {
  RECT controls;
  if (!proton_engine_overlay_controls_rect(window, &controls)) {
    return;
  }
  const UINT dpi = proton_win_window_dpi(window->hwnd);
  const int width = (controls.right - controls.left) / 3;
  const LRESULT buttons[] = {HTMINBUTTON, HTMAXBUTTON, HTCLOSE};
  for (int i = 0; i < 3; i++) {
    RECT rect = {controls.left + width * i, controls.top,
                 controls.left + width * (i + 1), controls.bottom};
    const LRESULT button = buttons[i];
    const UINT command = proton_win_custom_titlebar_command(window, button);
    COLORREF foreground = command ? window->custom_titlebar.foreground
                                  : GetSysColor(COLOR_GRAYTEXT);
    COLORREF background = window->custom_titlebar.background;
    if (command && window->titlebar_hot_button == button) {
      if (button == HTCLOSE) {
        background = window->titlebar_pressed_button == button
                         ? RGB(196, 43, 28)
                         : RGB(232, 17, 35);
        foreground = RGB(255, 255, 255);
      } else {
        /* Blend a little of the glyph color into the background. */
        const int weight = window->titlebar_pressed_button == button ? 5 : 9;
        background =
            RGB(GetRValue(background) +
                    (GetRValue(foreground) - GetRValue(background)) / weight,
                GetGValue(background) +
                    (GetGValue(foreground) - GetGValue(background)) / weight,
                GetBValue(background) +
                    (GetBValue(foreground) - GetBValue(background)) / weight);
      }
    }
    SetDCBrushColor(dc, background);
    FillRect(dc, &rect, (HBRUSH)GetStockObject(DC_BRUSH));
    proton_win_custom_titlebar_glyph(dc, rect, button, command, dpi,
                                     foreground);
  }
}

static LRESULT proton_win_custom_titlebar_hit(proton_engine_window_t *window,
                                              POINT client_point) {
  RECT controls;
  return proton_engine_overlay_controls_rect(window, &controls)
             ? proton_win_titlebar_caption_button_hit(client_point, &controls)
             : HTNOWHERE;
}

static void proton_win_custom_titlebar_hot(proton_engine_window_t *window,
                                           LRESULT button) {
  if (window->titlebar_hot_button != button) {
    window->titlebar_hot_button = button;
    RECT controls;
    if (proton_engine_overlay_controls_rect(window, &controls)) {
      InvalidateRect(window->hwnd, &controls, FALSE);
    }
  }
}

int proton_engine_custom_titlebar_mouse(proton_engine_window_t *window,
                                        UINT msg, WPARAM wparam,
                                        LPARAM lparam) {
  const HWND hwnd = window->hwnd;
  POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  switch (msg) {
  case WM_NCMOUSEMOVE:
    if (proton_win_is_caption_button_hit(wparam)) {
      TRACKMOUSEEVENT tracking = {sizeof(tracking), TME_LEAVE | TME_NONCLIENT,
                                  hwnd, 0};
      TrackMouseEvent(&tracking);
      proton_win_custom_titlebar_hot(window, wparam);
    } else {
      proton_win_custom_titlebar_hot(window, HTNOWHERE);
    }
    // Leave non-client hover handling to Windows for Snap Layouts.
    break;
  case WM_NCMOUSELEAVE:
    proton_win_custom_titlebar_hot(window, HTNOWHERE);
    break;
  case WM_NCLBUTTONDOWN:
  case WM_NCLBUTTONDBLCLK:
    if (proton_win_is_caption_button_hit(wparam)) {
      if (proton_win_custom_titlebar_command(window, wparam) != 0) {
        window->titlebar_pressed_button = wparam;
        SetCapture(hwnd);
        window->titlebar_hot_button = HTNOWHERE;
        proton_win_custom_titlebar_hot(window, wparam);
      }
      return 1; // Never let DefWindowProc draw a system pressed button.
    }
    break;
  case WM_MOUSEMOVE:
    if (window->titlebar_pressed_button != HTNOWHERE) {
      LRESULT hit = proton_win_custom_titlebar_hit(window, point);
      proton_win_custom_titlebar_hot(
          window, hit == window->titlebar_pressed_button ? hit : HTNOWHERE);
    }
    break;
  case WM_LBUTTONUP:
    if (window->titlebar_pressed_button != HTNOWHERE) {
      const LRESULT button = proton_win_custom_titlebar_hit(window, point);
      const UINT command =
          button == window->titlebar_pressed_button
              ? proton_win_custom_titlebar_command(window, button)
              : 0;
      window->titlebar_pressed_button = HTNOWHERE;
      proton_win_custom_titlebar_hot(window, HTNOWHERE);
      ReleaseCapture();
      if (command != 0) {
        SendMessageW(hwnd, WM_SYSCOMMAND, command, 0);
      }
      return 1;
    }
    break;
  case WM_CANCELMODE:
  case WM_CAPTURECHANGED:
    if (window->titlebar_pressed_button != HTNOWHERE) {
      window->titlebar_pressed_button = HTNOWHERE;
      proton_win_custom_titlebar_hot(window, HTNOWHERE);
    }
    break;
  }
  return 0;
}

static int proton_engine_overlay_drag_strip_rect(HWND hwnd,
                                                  const RECT *caption_buttons,
                                                  RECT *out) {
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

  if (caption_buttons != NULL) {
    const int live_caption_button_width =
        (caption_buttons->right - caption_buttons->left) / 3;
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
  out->bottom = caption_buttons != NULL
                    ? min(client.bottom, caption_buttons->bottom)
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

/* Regions are relative to the child window, while caption buttons are in
 * the parent's client coordinates. This applies equally to the main browser
 * and offset WebContentsViews. SetWindowRgn takes ownership on success. */
void proton_engine_overlay_clip_browser(proton_engine_window_t *window,
                                       HWND browser_hwnd) {
  if (window == NULL || !window->titlebar_overlay || browser_hwnd == NULL) {
    return;
  }
  RECT frame;
  if (!GetWindowRect(browser_hwnd, &frame)) {
    return;
  }
  HRGN region = CreateRectRgn(0, 0, frame.right - frame.left,
                              frame.bottom - frame.top);
  if (region == NULL) {
    return;
  }
  RECT buttons;
  if (proton_engine_overlay_controls_rect(window, &buttons)) {
    MapWindowPoints(window->hwnd, NULL, (POINT *)&buttons, 2);
    OffsetRect(&buttons, -frame.left, -frame.top);
    proton_engine_overlay_subtract_rect(region, &buttons);
  }
  if (!SetWindowRgn(browser_hwnd, region, TRUE)) {
    DeleteObject(region);
  }
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
      proton_engine_overlay_clip_browser(window, child);
      /* Parent resizes move the caption buttons even for fixed-size views. */
      for (proton_engine_view_t *view = window->views; view != NULL;
           view = view->next) {
        if (!view->closed && view->hwnd != NULL) {
          proton_engine_overlay_clip_browser(window, view->hwnd);
        }
      }
    }
  }
  host->base.release((cef_base_ref_counted_t *)host);
}

LRESULT proton_engine_overlay_hit_test(HWND hwnd, LPARAM lparam) {
  proton_engine_window_t *window =
      (proton_engine_window_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  const int custom = window != NULL && window->custom_titlebar.height > 0;
  LRESULT system_hit_test = HTNOWHERE;
  if (custom) {
    if (window->fullscreen) {
      return HTCLIENT;
    }
  } else {
    (void)DwmDefWindowProc(hwnd, WM_NCHITTEST, 0, lparam, &system_hit_test);
  }

  POINT client_point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  ScreenToClient(hwnd, &client_point);
  RECT caption_buttons;
  const int has_caption_buttons =
      custom
          ? proton_engine_overlay_controls_rect(window, &caption_buttons)
          : proton_engine_overlay_caption_buttons_rect(hwnd, &caption_buttons);
  if (has_caption_buttons) {
    LRESULT caption_hit =
        proton_win_titlebar_caption_button_hit(client_point, &caption_buttons);
    if (caption_hit != HTNOWHERE) {
      if (custom && !proton_win_custom_titlebar_command(window, caption_hit)) {
        return HTCLIENT;
      }
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
  const int resizable =
      !custom || (GetWindowLongW(hwnd, GWL_STYLE) & WS_THICKFRAME);
  const int padded_border = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_x =
      resizable ? GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padded_border
                : 0;
  const int resize_border_y =
      resizable ? GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border
                : 0;
  const int maximized = IsZoomed(hwnd);
  POINT client_origin = {0, 0};
  ClientToScreen(hwnd, &client_origin);
  const int client_left = client_origin.x - window_rect.left;
  const int client_top = client_origin.y - window_rect.top;
  RECT drag_strip = {0};
  if (window == NULL || !window->draggable_regions_reported) {
    (void)proton_engine_overlay_drag_strip_rect(
        hwnd, has_caption_buttons ? &caption_buttons : NULL, &drag_strip);
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
          client_point, dpi, window->draggable_region_count,
          window->draggable_regions)) {
    return HTCAPTION;
  }
  return hit;
}

#endif
