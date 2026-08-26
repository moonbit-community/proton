#if defined(_WIN32)

#include "win_internal.h"
#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../../proton_json.h"

#include "../cef_common/bridge_json.h"
#include "../cef_common/bridge_renderer.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/profile_storage.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#include "include/cef_api_hash.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_command_line_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_drag_handler_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_process_message_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_render_handler_capi.h"
#include "include/capi/cef_render_process_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_scheme_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LRESULT CALLBACK proton_engine_window_proc(HWND hwnd,
                                                  UINT msg,
                                                  WPARAM wparam,
                                                  LPARAM lparam) {
  proton_engine_window_t *window =
      (proton_engine_window_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
  case PROTON_ENGINE_WM_DESTROY_SELF:
    // Self-destruction deferred from OnBeforeClose; the owning engine window
    // may already be freed, so only the HWND is touched here.
    DestroyWindow(hwnd);
    return 0;
  case PROTON_ENGINE_WM_DESTROY_CHILD: {
    HWND child = (HWND)lparam;
    if (child != NULL && IsWindow(child) && GetParent(child) == hwnd) {
      DestroyWindow(child);
    }
    return 0;
  }
  case WM_NCCREATE: {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    window = (proton_engine_window_t *)create->lpCreateParams;
    if (window != NULL) {
      window->hwnd = hwnd;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)window);
    }
    break;
  }
  case WM_NCCALCSIZE:
    if (window != NULL && window->titlebar_overlay && wparam == TRUE) {
      NCCALCSIZE_PARAMS *params = (NCCALCSIZE_PARAMS *)lparam;
      LONG proposed_top = params->rgrc[0].top;
      LRESULT result = DefWindowProcW(hwnd, msg, wparam, lparam);
      if (result != 0) {
        return result;
      }
      params->rgrc[0].top =
          proposed_top +
          (IsZoomed(hwnd) ? proton_engine_overlay_frame_top_thickness(hwnd)
                          : 0);
      return 0;
    }
    break;
  case WM_NCHITTEST:
    if (window != NULL && window->titlebar_overlay) {
      return proton_engine_overlay_hit_test(hwnd, lparam);
    }
    break;
  case WM_GETMINMAXINFO:
    if (window != NULL) {
      bool handled = false;
      MINMAXINFO *minmax = (MINMAXINFO *)lparam;
      if (window->titlebar_overlay) {
      HMONITOR monitor =
          MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info;
      memset(&monitor_info, 0, sizeof(monitor_info));
      monitor_info.cbSize = sizeof(monitor_info);
      if (monitor != NULL && GetMonitorInfoW(monitor, &monitor_info)) {
        minmax->ptMaxPosition.x =
            monitor_info.rcWork.left - monitor_info.rcMonitor.left;
        minmax->ptMaxPosition.y =
            monitor_info.rcWork.top - monitor_info.rcMonitor.top;
        minmax->ptMaxSize.x =
            monitor_info.rcWork.right - monitor_info.rcWork.left;
        minmax->ptMaxSize.y =
            monitor_info.rcWork.bottom - monitor_info.rcWork.top;
          handled = true;
        }
      }
      if (!window->resizable) {
        minmax->ptMinTrackSize.x = window->width;
        minmax->ptMinTrackSize.y = window->height;
        handled = true;
      }
      if (window->resizable && window->min_width > 0) {
        minmax->ptMinTrackSize.x = window->min_width;
        minmax->ptMinTrackSize.y = window->min_height;
        handled = true;
      }
      if (window->resizable && window->max_width > 0) {
        minmax->ptMaxTrackSize.x = window->max_width;
        minmax->ptMaxTrackSize.y = window->max_height;
        handled = true;
      }
      if (!window->resizable) {
        minmax->ptMaxTrackSize.x = window->width;
        minmax->ptMaxTrackSize.y = window->height;
        handled = true;
      }
      if (handled) {
        return 0;
      }
    }
    break;
  case WM_DPICHANGED:
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    if (window != NULL && window->titlebar_overlay) {
      RECT *suggested = (RECT *)lparam;
      SetWindowPos(hwnd, NULL, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      proton_engine_overlay_apply_frame(hwnd);
      RECT client;
      if (GetClientRect(hwnd, &client)) {
        proton_engine_resize_browser(window, client.right - client.left,
                                     client.bottom - client.top);
      }
      return 0;
    }
    break;
  case WM_PARENTNOTIFY:
    if (window != NULL && window->titlebar_overlay &&
        LOWORD(wparam) == WM_CREATE) {
      proton_engine_overlay_subclass_browser(window, (HWND)lparam);
    }
    break;
  case WM_ACTIVATE:
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    if (window != NULL && window->titlebar_overlay) {
      proton_engine_overlay_apply_frame(hwnd);
      RECT client;
      if (GetClientRect(hwnd, &client)) {
        proton_engine_resize_browser(window, client.right - client.left,
                                     client.bottom - client.top);
      }
    }
    break;
  case WM_SIZE:
    if (window != NULL) {
      proton_engine_resize_browser(window, LOWORD(lparam), HIWORD(lparam));
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    return 0;
  case WM_MOVING:
    if (window != NULL && !window->movable) {
      // Electron blocks manual frame movement by restoring the current rect.
      // Programmatic SetWindowPos calls do not enter this message path.
      GetWindowRect(hwnd, (RECT *)lparam);
      return TRUE;
    }
    break;
  case WM_MOVE:
  case WM_DISPLAYCHANGE:
  case WM_THEMECHANGED:
  case WM_SETTINGCHANGE:
    if (window != NULL) {
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    break;
  case WM_ERASEBKGND:
    if (window != NULL && window->titlebar_overlay) {
      RECT client;
      GetClientRect(hwnd, &client);
      FillRect((HDC)wparam, &client, (HBRUSH)GetStockObject(BLACK_BRUSH));
      return 1;
    }
    break;
  case WM_PAINT:
    if (window != NULL && window->titlebar_overlay) {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(hwnd, &paint);
      FillRect(dc, &paint.rcPaint, (HBRUSH)GetStockObject(BLACK_BRUSH));
      EndPaint(hwnd, &paint);
      return 0;
    }
    break;
  case WM_CLOSE:
    if (window != NULL) {
      if (window->close_interception_enabled &&
          !window->close_interception_bypass) {
        if (!window->close_request_pending) {
          window->close_request_id++;
          if (window->close_request_id == 0) {
            window->close_request_id = 1;
          }
          window->close_request_pending = 1;
          proton_engine_signal_wait_source(window->runtime,
                                           PROTON_WAIT_PLATFORM);
        }
        return 0;
      }
      window->close_interception_bypass = 0;
      if (window->browser != NULL) {
        cef_browser_host_t *host = window->browser->get_host(window->browser);
        if (host != NULL) {
          int allow_close = 0;
          if (host->is_ready_to_be_closed != NULL &&
              host->is_ready_to_be_closed(host)) {
            allow_close = 1;
          } else if (host->try_close_browser != NULL) {
            allow_close = host->try_close_browser(host);
          } else if (!window->browser_close_requested) {
            host->close_browser(host, 0);
          }
          window->browser_close_requested = 1;
          host->base.release((cef_base_ref_counted_t *)host);
          if (!allow_close) {
            return 0;
          }
        }
      }
      DestroyWindow(hwnd);
      return 0;
    }
    break;
  case WM_DESTROY:
    if (window != NULL) {
      window->closed = 1;
      window->hwnd = NULL;
    }
    return 0;
  default:
    break;
  }
  if (window != NULL && window->titlebar_overlay) {
    LRESULT dwm_result = 0;
    if (DwmDefWindowProc(hwnd, msg, wparam, lparam, &dwm_result)) {
      return dwm_result;
    }
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static void proton_engine_register_window_class(void) {
  static int registered = 0;
  if (registered) {
    return;
  }
  WNDCLASSW wc;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = proton_engine_window_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = PROTON_ENGINE_WINDOW_CLASS;
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassW(&wc);
  registered = 1;
}

cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self);
cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self);
static cef_drag_handler_t *CEF_CALLBACK
proton_engine_client_get_drag_handler(cef_client_t *self);
static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self);
static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self);
static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self);
cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self);

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
  if (window == NULL || window->client == NULL ||
      (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  int browser_width = window->width;
  int browser_height = window->height;
  RECT rect = {0};
  if (!window->headless && GetClientRect(window->hwnd, &rect)) {
    browser_width = rect.right - rect.left;
    browser_height = rect.bottom - rect.top;
  }

  cef_window_info_t window_info;
  cef_browser_settings_t browser_settings;
  cef_string_t url = {0};
  memset(&window_info, 0, sizeof(window_info));
  memset(&browser_settings, 0, sizeof(browser_settings));
  window_info.size = sizeof(window_info);
  browser_settings.size = sizeof(browser_settings);
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    window_info.parent_window = window->hwnd;
    window_info.style =
        WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  }
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = browser_width;
  window_info.bounds.height = browser_height;
  proton_engine_set_string(&window_info.window_name, "Proton");
  proton_engine_set_string(&url,
                           initial_url != NULL && initial_url[0] != '\0'
                               ? initial_url
                               : "about:blank");

  cef_value_t *extra_info_value =
      proton_engine_bridge_renderer_extra_info_value(window->bridge_config_json);
  cef_dictionary_value_t *extra_info =
      extra_info_value != NULL
          ? extra_info_value->get_dictionary(extra_info_value)
          : NULL;
  window->browser = cef_browser_host_create_browser_sync(
      &window_info, window->client, &url, &browser_settings, extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);

  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  window->browser_id = proton_engine_browser_id(window->browser);
  proton_engine_resize_browser(window, browser_width, browser_height);
  return PROTON_OK;
}

int32_t proton_engine_window_create(
    proton_engine_runtime_t *runtime,
    const proton_engine_window_config_t *input_config,
    proton_engine_window_t **out_window, char *error, size_t error_len) {
  if (out_window == NULL) {
    proton_engine_set_message(error, error_len, "out_window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_window = NULL;
  if (runtime == NULL || input_config == NULL ||
      !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }

  proton_engine_window_config_t config = *input_config;

  if (runtime->headless && config.titlebar_overlay) {
    proton_engine_set_message(
        error, error_len,
        "titlebar overlay is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (!runtime->headless) {
    proton_engine_register_window_class();
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "failed to allocate window");
    return PROTON_ERR_ENGINE;
  }
  window->width = config.width;
  window->height = config.height;
  window->headless = runtime->headless;
  window->size_hint = config.size_hint;
  window->resizable = config.size_hint != 1;
  window->movable = 1;
  window->min_width = config.size_hint == 2 ? config.width : 0;
  window->min_height = config.size_hint == 2 ? config.height : 0;
  window->max_width = config.size_hint == 3 ? config.width : 0;
  window->max_height = config.size_hint == 3 ? config.height : 0;
  window->titlebar_overlay = config.titlebar_overlay;
  window->zoom_percent = 100;
  window->windowed_placement.length = sizeof(WINDOWPLACEMENT);
  window->runtime = runtime;
  window->public_window_id = config.public_window;
  window->bridge_config_json =
      config.bridge_config_json != NULL
          ? proton_engine_strdup(config.bridge_config_json)
          : NULL;
  window->max_bridge_payload_bytes = config.max_bridge_payload_bytes;
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, window);
  if (window->browser_session == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser session");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_session_bind_window(window->browser_session,
                                     config.public_window);
  window->client = (cef_client_t *)proton_engine_client_new(window);
  if (window->client == NULL) {
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  if (!window->headless) {
    wchar_t wide_title[512];
    proton_engine_utf8_to_wide(
        config.title, wide_title,
        (int)(sizeof(wide_title) / sizeof(wide_title[0])));
    DWORD window_style = WS_OVERLAPPEDWINDOW;
    if (window->size_hint == 1) {
      window_style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    if (window->titlebar_overlay) {
      window_style |= WS_CLIPCHILDREN;
    }
    window->hwnd = CreateWindowExW(
        0, PROTON_ENGINE_WINDOW_CLASS, wide_title, window_style, CW_USEDEFAULT,
        CW_USEDEFAULT, config.width, config.height, NULL, NULL,
        GetModuleHandleW(NULL), window);
    if (window->hwnd == NULL) {
      ((cef_base_ref_counted_t *)window->client)
          ->release((cef_base_ref_counted_t *)window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    if (window->titlebar_overlay) {
      proton_engine_overlay_apply_frame(window->hwnd);
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
    }
    ShowWindow(window->hwnd, SW_SHOW);
  }

  int32_t status =
      proton_engine_window_create_browser(window, config.initial_url, error,
                                          error_len);
  if (status != PROTON_OK) {
    if (window->hwnd != NULL) {
      DestroyWindow(window->hwnd);
    }
    ((cef_base_ref_counted_t *)window->client)
        ->release((cef_base_ref_counted_t *)window->client);
    free(window->bridge_config_json);
    proton_browser_session_destroy(window->browser_session);
    free(window->draggable_regions);
    free(window);
    return status;
  }

  proton_engine_window_list_add(window);
  *out_window = window;
  return PROTON_OK;
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {
  if (window == NULL) {
    return PROTON_OK;
  }
  proton_engine_dialog_cancel_window(window);
  if (window->browser != NULL) {
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    window->destroy_requested = 1;
    proton_engine_window_close_views(window);
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
    window->browser_close_requested = 1;
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    return PROTON_OK;
  }
  window->destroy_requested = 1;
  proton_engine_window_close_views(window);
  if (window->hwnd != NULL) {
    DestroyWindow(window->hwnd);
    window->hwnd = NULL;
  }
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless && window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  window->close_interception_bypass = 0;
  if (window->headless) {
    window->headless_hidden = 0;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 0);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    ShowWindow(window->hwnd, SW_SHOW);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window size constraints are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (width > 0 && window->max_width > 0 &&
      (width > window->max_width || height > window->max_height)) {
    proton_engine_set_message(error, error_len,
                              "minimum size exceeds maximum size");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->min_width = width;
  window->min_height = height;
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window size constraints are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (width > 0 && window->min_width > 0 &&
      (width < window->min_width || height < window->min_height)) {
    proton_engine_set_message(error, error_len,
                              "maximum size is below minimum size");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->max_width = width;
  window->max_height = height;
  return PROTON_OK;
}

int32_t proton_engine_window_set_movable(proton_engine_window_t *window,
                                         int32_t movable, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (movable != 0 && movable != 1) {
    proton_engine_set_message(error, error_len,
                              "movable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window movement is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->movable = movable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_opacity(proton_engine_window_t *window,
                                         double opacity, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (isnan(opacity)) {
    proton_engine_set_message(error, error_len,
                              "opacity must not be NaN");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window opacity is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  const double bounded_opacity = opacity < 0.0 ? 0.0 : (opacity > 1.0 ? 1.0 : opacity);
  LONG_PTR extended_style = GetWindowLongPtrW(window->hwnd, GWL_EXSTYLE);
  SetLastError(0);
  if (SetWindowLongPtrW(window->hwnd, GWL_EXSTYLE,
                        extended_style | WS_EX_LAYERED) == 0 &&
      GetLastError() != 0) {
    proton_engine_set_message(error, error_len,
                              "failed to enable layered window opacity");
    return PROTON_ERR_PLATFORM;
  }
  if (!SetLayeredWindowAttributes(window->hwnd, 0,
                                  (BYTE)(bounded_opacity * 255.0), LWA_ALPHA)) {
    proton_engine_set_message(error, error_len,
                              "failed to update window opacity");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    window->headless_hidden = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_hidden(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    ShowWindow(window->hwnd, SW_HIDE);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host == NULL) {
        proton_engine_set_message(error, error_len,
                                  "browser host is not available for close");
        return PROTON_ERR_ENGINE;
      }
      window->browser_close_requested = 1;
      host->close_browser(host, 0);
      host->base.release((cef_base_ref_counted_t *)host);
    } else {
      window->closed = 1;
      proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
    }
  } else {
    PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {
  return window == NULL || window->closed;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->set_focus(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    SetForegroundWindow(window->hwnd);
    SetFocus(window->hwnd);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  wchar_t wide_title[512];
  proton_engine_utf8_to_wide(title, wide_title,
                             (int)(sizeof(wide_title) / sizeof(wide_title[0])));
  SetWindowTextW(window->hwnd, wide_title);
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->width = width;
  window->height = height;
  if (window->headless) {
    proton_engine_resize_browser(window, width, height);
  } else {
    SetWindowPos(window->hwnd, NULL, 0, 0, width, height,
                 SWP_NOMOVE | SWP_NOZORDER);
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_progress_bar(
    proton_engine_window_t *window, double progress, char *error,
    size_t error_len) {
  (void)progress;
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_set_message(
      error, error_len,
      "window progress is not implemented on Windows");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_window_flash_frame(
    proton_engine_window_t *window, int32_t flash, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (flash != 0 && flash != 1) {
    proton_engine_set_message(error, error_len, "flash must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window attention is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  FLASHWINFO info = {
      .cbSize = sizeof(info),
      .hwnd = window->hwnd,
      .dwFlags = flash ? (FLASHW_ALL | FLASHW_TIMERNOFG) : FLASHW_STOP,
      .uCount = 0,
      .dwTimeout = 0,
  };
  (void)FlashWindowEx(&info);
  return PROTON_OK;
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {
  if (window == NULL || action == NULL ||
      (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window and action are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (action->kind == PROTON_ENGINE_WINDOW_SET_ZOOM_PERCENT) {
    if (window->browser == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser is not initialized");
      return PROTON_ERR_NOT_INITIALIZED;
    }
    cef_browser_host_t *host = window->browser->get_host(window->browser);
    if (host == NULL) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available");
      return PROTON_ERR_ENGINE;
    }
    const double factor = (double)action->value / 100.0;
    host->set_zoom_level(host, log(factor) / log(1.2));
    host->base.release((cef_base_ref_counted_t *)host);
    window->zoom_percent = action->value;
    proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "native window operation is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  switch (action->kind) {
  case PROTON_ENGINE_WINDOW_MINIMIZE:
    ShowWindow(window->hwnd, SW_MINIMIZE);
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    ShowWindow(window->hwnd, SW_MAXIMIZE);
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    if (window->fullscreen) {
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)window->windowed_style);
      SetWindowPlacement(window->hwnd, &window->windowed_placement);
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
      window->fullscreen = 0;
    }
    ShowWindow(window->hwnd, SW_RESTORE);
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN:
    if (action->value != 0 && !window->fullscreen) {
      window->windowed_style =
          (DWORD)GetWindowLongW(window->hwnd, GWL_STYLE);
      window->windowed_placement.length = sizeof(WINDOWPLACEMENT);
      GetWindowPlacement(window->hwnd, &window->windowed_placement);
      HMONITOR monitor =
          MonitorFromWindow(window->hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
      if (monitor == NULL || !GetMonitorInfoW(monitor, &info)) {
        proton_engine_set_message(error, error_len,
                                  "failed to read monitor geometry");
        return PROTON_ERR_PLATFORM;
      }
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)(window->windowed_style &
                            ~WS_OVERLAPPEDWINDOW));
      SetWindowPos(window->hwnd, HWND_TOP, info.rcMonitor.left,
                   info.rcMonitor.top,
                   info.rcMonitor.right - info.rcMonitor.left,
                   info.rcMonitor.bottom - info.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      window->fullscreen = 1;
    } else if (action->value == 0 && window->fullscreen) {
      SetWindowLongW(window->hwnd, GWL_STYLE,
                     (LONG)window->windowed_style);
      SetWindowPlacement(window->hwnd, &window->windowed_placement);
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
      window->fullscreen = 0;
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_POSITION:
    SetWindowPos(window->hwnd, NULL, action->x, action->y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    break;
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    SetWindowPos(window->hwnd,
                 action->value != 0 ? HWND_TOPMOST : HWND_NOTOPMOST,
                 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    window->always_on_top = action->value != 0;
    break;
  case PROTON_ENGINE_WINDOW_SET_RESIZABLE: {
    LONG style = GetWindowLongW(window->hwnd, GWL_STYLE);
    if (action->value != 0) {
      style |= WS_THICKFRAME | WS_MAXIMIZEBOX;
    } else {
      style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    SetLastError(0);
    if (SetWindowLongW(window->hwnd, GWL_STYLE, style) == 0 &&
        GetLastError() != 0) {
      proton_engine_set_message(error, error_len,
                                "failed to update window style");
      return PROTON_ERR_PLATFORM;
    }
    window->resizable = action->value != 0;
    SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
    break;
  }
  default:
    proton_engine_set_message(error, error_len, "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

static int proton_engine_windows_theme(void) {
  DWORD light = 1;
  DWORD size = sizeof(light);
  LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light, &size);
  if (status != ERROR_SUCCESS) {
    return 0;
  }
  return light != 0 ? 1 : 2;
}

int32_t proton_engine_window_get_state(
    proton_engine_window_t *window,
    proton_engine_window_state_t *out_state,
    char *error,
    size_t error_len) {
  if (window == NULL || out_state == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and out_state are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  memset(out_state, 0, sizeof(*out_state));
  out_state->zoom_percent =
      window->zoom_percent > 0 ? window->zoom_percent : 100;
  out_state->scale_factor_percent = 100;
  if (window->headless) {
    out_state->width = window->width;
    out_state->height = window->height;
    out_state->visible = !window->headless_hidden;
    return PROTON_OK;
  }
  if (window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  RECT frame = {0};
  GetWindowRect(window->hwnd, &frame);
  HMONITOR monitor =
      MonitorFromWindow(window->hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {.cbSize = sizeof(MONITORINFO)};
  if (monitor != NULL) {
    GetMonitorInfoW(monitor, &info);
  }
  out_state->x = frame.left;
  out_state->y = frame.top;
  out_state->width = frame.right - frame.left;
  out_state->height = frame.bottom - frame.top;
  out_state->monitor_x = info.rcMonitor.left;
  out_state->monitor_y = info.rcMonitor.top;
  out_state->monitor_width = info.rcMonitor.right - info.rcMonitor.left;
  out_state->monitor_height = info.rcMonitor.bottom - info.rcMonitor.top;
  out_state->work_x = info.rcWork.left;
  out_state->work_y = info.rcWork.top;
  out_state->work_width = info.rcWork.right - info.rcWork.left;
  out_state->work_height = info.rcWork.bottom - info.rcWork.top;
  UINT dpi = GetDpiForWindow(window->hwnd);
  out_state->scale_factor_percent =
      dpi > 0 ? (int32_t)((dpi * 100 + 48) / 96) : 100;
  out_state->visible = IsWindowVisible(window->hwnd) ? 1 : 0;
  out_state->focused = GetForegroundWindow() == window->hwnd ? 1 : 0;
  out_state->minimized = IsIconic(window->hwnd) ? 1 : 0;
  out_state->maximized = IsZoomed(window->hwnd) ? 1 : 0;
  out_state->fullscreen = window->fullscreen;
  out_state->always_on_top = window->always_on_top;
  out_state->theme = proton_engine_windows_theme();
  return PROTON_OK;
}

int32_t proton_engine_window_set_close_interception(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->close_interception_enabled = enabled != 0;
  if (!window->close_interception_enabled) {
    window->close_request_pending = 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_get_close_request(
    proton_engine_window_t *window, uint64_t *out_request_id,
    int32_t *out_pending, char *error, size_t error_len) {
  if (window == NULL || out_request_id == NULL || out_pending == NULL) {
    proton_engine_set_message(
        error, error_len,
        "window, out_request_id, and out_pending are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_request_id = window->close_request_id;
  *out_pending = window->close_request_pending;
  return PROTON_OK;
}

int32_t proton_engine_window_respond_close_request(
    proton_engine_window_t *window, uint64_t request_id, int32_t allow,
    char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!window->close_request_pending ||
      window->close_request_id != request_id) {
    proton_engine_set_message(error, error_len,
                              "window close request is no longer pending");
    return PROTON_ERR_STALE_WINDOW_REQUEST;
  }
  window->close_request_pending = 0;
  if (allow && !window->closed) {
    window->close_interception_bypass = 1;
    if (window->headless) {
      return proton_engine_window_close(window, error, error_len);
    }
    if (window->hwnd != NULL) {
      PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
    }
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t value = {0};
  proton_engine_set_string(&value, url);
  frame->load_url(frame, &value);
  cef_string_clear(&value);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

/* Installs `html` as the document served for `document_url` and, when an
   asset root is supplied, binds that root to the runtime's application
   origin. The document is not handed to CEF inline: the scheme factory reads
   it back out of the window when the navigation asks for it, which is what
   lets relative URLs resolve against the same origin. */
int32_t proton_engine_window_eval(proton_engine_window_t *window,
                                  const char *script,
                                  char *error,
                                  size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t code = {0};
  cef_string_t url = {0};
  proton_engine_set_string(&code, script);
  proton_engine_set_string(&url, "proton://eval/");
  frame->execute_java_script(frame, &code, &url, 1);
  cef_string_clear(&code);
  cef_string_clear(&url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  return PROTON_OK;
}

int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(
      window->browser_session, window->browser, command_json, error,
      error_len);
}

int32_t proton_engine_window_respond_browser_request_json(
    proton_engine_window_t *window, const char *response_json,
    char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_respond_json(
      window->browser_session, response_json, error, error_len);
}

int32_t proton_engine_window_emit_bridge_event_json(
    proton_engine_window_t *window,
    const char *event_json,
    char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL ||
      window->bridge_config_json == NULL) {
    proton_engine_set_message(error, error_len, "bridge is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (!proton_engine_bridge_send_event(window->browser, event_json)) {
    proton_engine_set_message(error, error_len,
                              "failed to send bridge event to renderer");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window) {
  return window != NULL ? window->public_window_id : PROTON_INVALID_HANDLE;
}

uint64_t proton_engine_window_bridge_revision(proton_engine_window_t *window) {
  return window != NULL
             ? proton_engine_bridge_lifecycle_revision(&window->bridge_lifecycle)
             : 0;
}

int32_t proton_engine_window_bridge_state_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_state_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

int32_t proton_engine_window_take_bridge_failure_json(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  return proton_engine_bridge_lifecycle_take_failure_json(
      &window->bridge_lifecycle, buffer, buffer_len, out_required_len);
}

#endif
