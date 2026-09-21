#if defined(_WIN32)

#include "../../src/engine/cef_win/win_geometry.h"
#include "../../src/engine/cef_win/win_internal.h"

/* Return the failing C line to the MoonBit assertion, preserving fixture
 * cleanup. */
#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      result = __LINE__;                                                       \
      goto cleanup;                                                            \
    }                                                                          \
  } while (0)

int32_t proton_test_window_dpi_conversion(void) {
  int result = 0;
  const UINT dpis[] = {96, 144, 240};
  const int widths[] = {1120, 1680, 2800};
  const int heights[] = {760, 1140, 1900};
  for (int i = 0; i < 3; ++i) {
    CHECK(proton_win_pixels(1120, dpis[i]) == widths[i]);
    CHECK(proton_win_pixels(760, dpis[i]) == heights[i]);
    CHECK(proton_win_logical(widths[i], dpis[i]) == 1120);
    CHECK(proton_win_logical(heights[i], dpis[i]) == 760);
    CHECK(proton_win_logical(proton_win_pixels(503, dpis[i]), dpis[i]) == 503);
  }
  CHECK(proton_win_pixels(INT_MAX, 240) == INT_MAX);
cleanup:
  return result;
}

/* The tracking sizes the window proc hands to the system live in device
 * pixels, so a fixed window and explicit min/max hints must scale with the
 * window DPI instead of being passed through as logical lengths. */
int32_t proton_test_window_tracking_sizes(void) {
  int result = 0;
  MINMAXINFO fixed = {0};
  MINMAXINFO minimum = {0};
  MINMAXINFO maximum = {0};
  MINMAXINFO unconstrained = {0};

  /* A fixed window pins both tracking sizes to the scaled frame. */
  CHECK(proton_win_tracking_sizes(0, 1120, 760, 0, 0, 0, 0, 240, &fixed));
  CHECK(fixed.ptMinTrackSize.x == 2800 && fixed.ptMinTrackSize.y == 1900);
  CHECK(fixed.ptMaxTrackSize.x == 2800 && fixed.ptMaxTrackSize.y == 1900);

  /* An explicit minimum hint scales at 150%. */
  CHECK(proton_win_tracking_sizes(1, 1000, 700, 800, 600, 0, 0, 144, &minimum));
  CHECK(minimum.ptMinTrackSize.x == 1200 && minimum.ptMinTrackSize.y == 900);
  CHECK(minimum.ptMaxTrackSize.x == 0 && minimum.ptMaxTrackSize.y == 0);

  /* An explicit maximum hint scales at 100%. */
  CHECK(proton_win_tracking_sizes(1, 1000, 700, 0, 0, 1600, 900, 96, &maximum));
  CHECK(maximum.ptMaxTrackSize.x == 1600 && maximum.ptMaxTrackSize.y == 900);
  CHECK(maximum.ptMinTrackSize.x == 0 && maximum.ptMinTrackSize.y == 0);

  /* A resizable window without hints keeps the system defaults. */
  CHECK(
      !proton_win_tracking_sizes(1, 1000, 700, 0, 0, 0, 0, 96, &unconstrained));
  CHECK(unconstrained.ptMinTrackSize.x == 0 &&
        unconstrained.ptMinTrackSize.y == 0);
  CHECK(unconstrained.ptMaxTrackSize.x == 0 &&
        unconstrained.ptMaxTrackSize.y == 0);

cleanup:
  return result;
}

int32_t proton_test_window_initial_placement(void) {
  int result = 0;
  RECT work = {-1920, 40, 0, 1080};
  RECT frame = {-200, 800, 920, 1560};
  RECT fitted = proton_win_initial_rect(frame, work, 2800, 1900, 0);
  CHECK(EqualRect(&fitted, &work));
  fitted = proton_win_initial_rect(frame, work, 600, 400, 0);
  CHECK(fitted.left == -600 && fitted.top == 680);
  CHECK(fitted.right == 0 && fitted.bottom == 1080);
  fitted = proton_win_initial_rect(frame, work, 2800, 1900, 1);
  CHECK(fitted.right - fitted.left == 2800);
  CHECK(fitted.bottom - fitted.top == 1900);
  fitted = proton_win_initial_rect(frame, work, 2800, 1900, 2);
  CHECK(fitted.right - fitted.left == 2800);
  fitted = proton_win_initial_rect(frame, work, 2800, 1900, 3);
  CHECK(EqualRect(&fitted, &work));
cleanup:
  return result;
}

static LRESULT CALLBACK geometry_window_proc(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)create->lpCreateParams);
  }
  if (message == WM_NCCALCSIZE && wparam == TRUE &&
      GetWindowLongPtrW(hwnd, GWLP_USERDATA) != 0) {
    NCCALCSIZE_PARAMS *params = (NCCALCSIZE_PARAMS *)lparam;
    LONG top = params->rgrc[0].top;
    LRESULT result = DefWindowProcW(hwnd, message, wparam, lparam);
    if (result != 0)
      return result;
    params->rgrc[0].top = top;
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

int32_t proton_test_window_native_sizes(int32_t overlay) {
  int result = 0;
  HWND hwnd = NULL;
  ATOM window_class = 0;
  HINSTANCE instance = GetModuleHandleW(NULL);
  DPI_AWARENESS_CONTEXT previous =
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CHECK(previous != NULL);
  WNDCLASSW cls = {0};
  cls.lpfnWndProc = geometry_window_proc;
  cls.hInstance = instance;
  cls.lpszClassName = L"ProtonWindowGeometryTest";
  window_class = RegisterClassW(&cls);
  CHECK(window_class != 0);
  hwnd = CreateWindowExW(0, cls.lpszClassName, L"Proton geometry test",
                         WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 400,
                         300, NULL, NULL, instance, (void *)(INT_PTR)overlay);
  CHECK(hwnd != NULL);
  UINT dpi = GetDpiForWindow(hwnd);
  CHECK(dpi >= 96);
  CHECK(proton_win_initialize_geometry(hwnd, 1120, 760, 0));
  CHECK(!IsWindowVisible(hwnd));
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  CHECK(GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &info));
  RECT frame, client;
  CHECK(GetWindowRect(hwnd, &frame));
  CHECK(frame.right - frame.left == min(proton_win_pixels(1120, dpi),
                                        info.rcWork.right - info.rcWork.left));
  CHECK(frame.bottom - frame.top ==
        min(proton_win_pixels(760, dpi), info.rcWork.bottom - info.rcWork.top));
  CHECK(frame.left >= info.rcWork.left && frame.right <= info.rcWork.right);
  CHECK(frame.top >= info.rcWork.top && frame.bottom <= info.rcWork.bottom);

  proton_engine_window_t window = {0};
  window.hwnd = hwnd;
  window.resizable = 1;
  window.titlebar_overlay = overlay;
  char error[256] = {0};
  CHECK(proton_engine_window_set_size(&window, 640, 480, error,
                                      sizeof(error)) == PROTON_OK);
  CHECK(GetWindowRect(hwnd, &frame));
  CHECK(frame.right - frame.left == proton_win_pixels(640, dpi));
  CHECK(frame.bottom - frame.top == proton_win_pixels(480, dpi));
  proton_engine_window_state_t state;
  CHECK(proton_engine_window_get_state(&window, &state, error, sizeof(error)) ==
        PROTON_OK);
  CHECK(state.width == 640 && state.height == 480);

  CHECK(proton_engine_window_set_content_size(&window, 503, 307, error,
                                              sizeof(error)) == PROTON_OK);
  CHECK(GetClientRect(hwnd, &client));
  CHECK(client.right == proton_win_pixels(503, dpi));
  CHECK(client.bottom == proton_win_pixels(307, dpi));
  int32_t width, height;
  CHECK(proton_engine_window_get_content_size(&window, &width, &height, error,
                                              sizeof(error)) == PROTON_OK);
  CHECK(width == 503 && height == 307);
  /* Repeating a logical-size request must not scale the previous size again. */
  CHECK(proton_engine_window_set_content_size(&window, 503, 307, error,
                                              sizeof(error)) == PROTON_OK);
  RECT repeated;
  CHECK(GetClientRect(hwnd, &repeated));
  CHECK(EqualRect(&client, &repeated));
cleanup:
  if (hwnd != NULL)
    DestroyWindow(hwnd);
  if (window_class != 0)
    UnregisterClassW(L"ProtonWindowGeometryTest", instance);
  if (previous != NULL)
    SetThreadDpiAwarenessContext(previous);
  return result;
}

/* A DPI change hands the window proc a frame already expressed in the new
 * monitor's pixels. The proc must adopt that rectangle verbatim, leave the
 * logical bookkeeping alone, and still convert later logical requests from the
 * new DPI instead of scaling the frame it was just given a second time. */
int32_t proton_test_window_dpi_change(void) {
  int result = 0;
  HWND hwnd = NULL;
  DPI_AWARENESS_CONTEXT previous =
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CHECK(previous != NULL);
  proton_engine_register_window_class();

  proton_engine_window_t window = {0};
  window.resizable = 1;
  hwnd = CreateWindowExW(0, PROTON_ENGINE_WINDOW_CLASS,
                         L"Proton DPI change test", WS_OVERLAPPEDWINDOW,
                         CW_USEDEFAULT, CW_USEDEFAULT, 400, 300, NULL, NULL,
                         GetModuleHandleW(NULL), &window);
  CHECK(hwnd != NULL);
  CHECK(window.hwnd == hwnd);
  window.width = 1120;
  window.height = 760;

  /* SetWindowPos clamps a target frame that does not fit the work area, so
   * derive the requested rectangle from the work area rather than hard-coding
   * one: the assertion is that a fitting suggestion is adopted verbatim, not
   * that the window can be forced past the screen. */
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  CHECK(GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &info));
  int work_width = info.rcWork.right - info.rcWork.left;
  int work_height = info.rcWork.bottom - info.rcWork.top;
  /* Fail loudly rather than silently degenerate on a display-less runner. */
  CHECK(work_width >= 200 && work_height >= 200);
  RECT suggested = {info.rcWork.left + work_width / 10,
                    info.rcWork.top + work_height / 10,
                    info.rcWork.left + work_width / 10 + work_width * 3 / 5,
                    info.rcWork.top + work_height / 10 + work_height * 3 / 5};
  SendMessageW(hwnd, WM_DPICHANGED, MAKEWPARAM(240, 240), (LPARAM)&suggested);

  RECT frame;
  CHECK(GetWindowRect(hwnd, &frame));
  CHECK(EqualRect(&frame, &suggested));
  /* The rectangle is already physical, so the logical size is untouched. */
  CHECK(window.width == 1120 && window.height == 760);

  /* A following logical-size request starts from the current DPI, so the size
   * the caller asked for is the size it gets — no compounding scale factor.
   * Half the work area stays inside it at any DPI. */
  UINT dpi = proton_win_window_dpi(hwnd);
  CHECK(dpi >= 96);
  int logical_width = proton_win_logical(work_width / 2, dpi);
  int logical_height = proton_win_logical(work_height / 2, dpi);
  char error[256] = {0};
  CHECK(proton_engine_window_set_size(&window, logical_width, logical_height,
                                      error,
                                      sizeof(error)) == PROTON_OK);
  CHECK(GetWindowRect(hwnd, &frame));
  CHECK(frame.right - frame.left == proton_win_pixels(logical_width, dpi));
  CHECK(frame.bottom - frame.top == proton_win_pixels(logical_height, dpi));
cleanup:
  if (hwnd != NULL)
    DestroyWindow(hwnd);
  if (previous != NULL)
    SetThreadDpiAwarenessContext(previous);
  return result;
}

int32_t proton_test_titlebar_dpi_regions(void) {
  int result = 0;
  const UINT dpis[] = {96, 120, 144, 192, 240};
  const proton_win_titlebar_region_t regions[] = {
      {0, 0, 600, 46, 1}, {14, 9, 28, 28, 0}};
  const proton_win_titlebar_region_t reversed[] = {regions[1], regions[0]};
  for (int i = 0; i < 5; ++i) {
    const UINT dpi = dpis[i];
    /* Inspect every physical pixel of the button, not only its center. */
    const int left = (14 * dpi + 95) / 96;
    const int top = (9 * dpi + 95) / 96;
    const int right = (42 * dpi + 95) / 96;
    const int bottom = (37 * dpi + 95) / 96;
    for (int x = left; x < right; ++x) {
      for (int y = top; y < bottom; ++y) {
        POINT point = {x, y};
        CHECK(!proton_win_titlebar_point_in_draggable_regions(
            point, dpi, 2, regions));
        CHECK(!proton_win_titlebar_point_in_draggable_regions(
            point, dpi, 2, reversed));
      }
    }
    const POINT outside[] = {
        {left - 1, top}, {right, top}, {left, top - 1}, {left, bottom}};
    for (int j = 0; j < 4; ++j) {
      CHECK(proton_win_titlebar_point_in_draggable_regions(
          outside[j], dpi, 2, regions));
    }
    POINT negative = {-1, top};
    CHECK(!proton_win_titlebar_point_in_draggable_regions(
        negative, dpi, 2, regions));
    POINT below = {left, (46 * dpi + 95) / 96};
    CHECK(!proton_win_titlebar_point_in_draggable_regions(
        below, dpi, 2, regions));
  }
cleanup:
  return result;
}

/* Exercise the real overlay hit-test with screen-pixel mouse coordinates,
 * while CEF's cached regions remain in view DIPs. No browser or visible
 * window is needed to cover the Win32/renderer coordinate boundary. */
int32_t proton_test_titlebar_native_hit_test(void) {
  int result = 0;
  HWND hwnd = NULL;
  ATOM window_class = 0;
  HINSTANCE instance = GetModuleHandleW(NULL);
  DPI_AWARENESS_CONTEXT previous =
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CHECK(previous != NULL);
  WNDCLASSW cls = {0};
  cls.lpfnWndProc = geometry_window_proc;
  cls.hInstance = instance;
  cls.lpszClassName = L"ProtonTitlebarHitTest";
  window_class = RegisterClassW(&cls);
  CHECK(window_class != 0);
  proton_win_titlebar_region_t regions[] = {
      {0, 0, 600, 46, 1}, {14, 9, 28, 28, 0}};
  proton_engine_window_t window = {0};
  window.titlebar_overlay = 1;
  window.draggable_regions_reported = 1;
  window.draggable_regions = regions;
  window.draggable_region_count = 2;
  hwnd = CreateWindowExW(0, cls.lpszClassName, L"Proton titlebar test",
                         WS_OVERLAPPEDWINDOW, 100, 100, 900, 400, NULL, NULL,
                         instance, &window);
  CHECK(hwnd != NULL);
  window.hwnd = hwnd;
  CHECK(!IsWindowVisible(hwnd));
  const UINT dpi = GetDpiForWindow(hwnd);
  CHECK(dpi >= USER_DEFAULT_SCREEN_DPI);
  const int xs[] = {15, 28, 41};
  const int ys[] = {10, 23, 36};
  for (int x = 0; x < 3; ++x) {
    for (int y = 0; y < 3; ++y) {
      POINT point = {proton_win_pixels(xs[x], dpi),
                     proton_win_pixels(ys[y], dpi)};
      CHECK(ClientToScreen(hwnd, &point));
      CHECK(proton_engine_overlay_hit_test(
                hwnd, MAKELPARAM(point.x, point.y)) == HTCLIENT);
    }
  }
  POINT empty_chrome = {proton_win_pixels(80, dpi),
                        proton_win_pixels(23, dpi)};
  CHECK(ClientToScreen(hwnd, &empty_chrome));
  CHECK(proton_engine_overlay_hit_test(
            hwnd, MAKELPARAM(empty_chrome.x, empty_chrome.y)) == HTCAPTION);
cleanup:
  if (hwnd != NULL)
    DestroyWindow(hwnd);
  if (window_class != 0)
    UnregisterClassW(L"ProtonTitlebarHitTest", instance);
  if (previous != NULL)
    SetThreadDpiAwarenessContext(previous);
  return result;
}

#endif
