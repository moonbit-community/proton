#ifndef PROTON_WIN_GEOMETRY_H
#define PROTON_WIN_GEOMETRY_H

#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <windows.h>

/* Only window-local lengths are converted here. Virtual-desktop origins
 * must not be scaled by an arbitrary monitor's DPI. */
static inline UINT proton_win_window_dpi(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  return dpi != 0 ? dpi : USER_DEFAULT_SCREEN_DPI;
}

static inline int proton_win_pixels(int logical, UINT dpi) {
  int64_t pixels = ((int64_t)logical * dpi + 48) / 96;
  return pixels > INT_MAX ? INT_MAX : (int)pixels;
}

static inline int proton_win_logical(int pixels, UINT dpi) {
  return MulDiv(pixels, USER_DEFAULT_SCREEN_DPI, (int)dpi);
}

/* Applies the fixed/minimum/maximum tracking constraints in device pixels.
 * Returns true when the window proc owns the message because a constraint or
 * the fixed frame size was applied. */
static inline bool proton_win_tracking_sizes(int resizable, int width,
                                             int height, int min_width,
                                             int min_height, int max_width,
                                             int max_height, UINT dpi,
                                             MINMAXINFO *minmax) {
  bool handled = false;
  if (!resizable) {
    minmax->ptMinTrackSize.x = proton_win_pixels(width, dpi);
    minmax->ptMinTrackSize.y = proton_win_pixels(height, dpi);
    handled = true;
  }
  if (resizable && min_width > 0) {
    minmax->ptMinTrackSize.x = proton_win_pixels(min_width, dpi);
    minmax->ptMinTrackSize.y = proton_win_pixels(min_height, dpi);
    handled = true;
  }
  if (resizable && max_width > 0) {
    minmax->ptMaxTrackSize.x = proton_win_pixels(max_width, dpi);
    minmax->ptMaxTrackSize.y = proton_win_pixels(max_height, dpi);
    handled = true;
  }
  if (!resizable) {
    minmax->ptMaxTrackSize.x = proton_win_pixels(width, dpi);
    minmax->ptMaxTrackSize.y = proton_win_pixels(height, dpi);
    handled = true;
  }
  return handled;
}

/* Fit a new, unconstrained window without assuming the monitor starts at 0,0.
 * Explicit fixed/minimum size hints take precedence over work-area fitting. */
static inline RECT proton_win_initial_rect(RECT frame, RECT work, int width,
                                           int height, int size_hint) {
  if (size_hint != 1 && size_hint != 2) {
    width = min(width, work.right - work.left);
    height = min(height, work.bottom - work.top);
  }
  frame.left = max(work.left, min(frame.left, work.right - width));
  frame.top = max(work.top, min(frame.top, work.bottom - height));
  frame.right = frame.left + width;
  frame.bottom = frame.top + height;
  return frame;
}

static inline BOOL proton_win_initialize_geometry(HWND hwnd, int width,
                                                  int height, int size_hint) {
  UINT dpi = proton_win_window_dpi(hwnd);
  RECT frame;
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (!GetWindowRect(hwnd, &frame) || !GetMonitorInfoW(monitor, &info)) {
    return FALSE;
  }
  frame =
      proton_win_initial_rect(frame, info.rcWork, proton_win_pixels(width, dpi),
                              proton_win_pixels(height, dpi), size_hint);
  return SetWindowPos(hwnd, NULL, frame.left, frame.top,
                      frame.right - frame.left, frame.bottom - frame.top,
                      SWP_NOZORDER | SWP_NOACTIVATE);
}

#endif
