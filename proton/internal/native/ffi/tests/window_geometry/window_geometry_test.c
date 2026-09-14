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

#endif
