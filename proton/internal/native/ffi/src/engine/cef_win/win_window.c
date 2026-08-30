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
#include <shobjidl.h>
#include <windowsx.h>

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

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
  case WM_MOUSEACTIVATE:
    if (window != NULL && !window->focusable) {
      return MA_NOACTIVATE;
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
  case WM_SIZING:
    if (window != NULL && window->aspect_ratio > 0.0 &&
        window->resizable && lparam != 0) {
      RECT *rect = (RECT *)lparam;
      const int edge = (int)wparam;
      RECT current_window;
      RECT current_client;
      int frame_width = 0;
      int frame_height = 0;
      if (GetWindowRect(hwnd, &current_window) &&
          GetClientRect(hwnd, &current_client)) {
        frame_width = (current_window.right - current_window.left) -
                      (current_client.right - current_client.left);
        frame_height = (current_window.bottom - current_window.top) -
                       (current_client.bottom - current_client.top);
      }
      int client_width = (rect->right - rect->left) - frame_width;
      int client_height = (rect->bottom - rect->top) - frame_height;
      if (client_width > 0 && client_height > 0) {
        if (edge == WMSZ_LEFT || edge == WMSZ_RIGHT) {
          client_height = (int)lround((double)client_width /
                                      window->aspect_ratio);
        } else if (edge == WMSZ_TOP || edge == WMSZ_BOTTOM) {
          client_width = (int)lround((double)client_height *
                                     window->aspect_ratio);
        } else {
          int height_from_width = (int)lround((double)client_width /
                                              window->aspect_ratio);
          int width_from_height = (int)lround((double)client_height *
                                              window->aspect_ratio);
          if (abs(height_from_width - client_height) <=
              abs(width_from_height - client_width)) {
            client_height = height_from_width;
          } else {
            client_width = width_from_height;
          }
        }
        const int outer_width = client_width + frame_width;
        const int outer_height = client_height + frame_height;
        if (edge == WMSZ_LEFT || edge == WMSZ_TOPLEFT ||
            edge == WMSZ_BOTTOMLEFT) {
          rect->left = rect->right - outer_width;
        } else {
          rect->right = rect->left + outer_width;
        }
        if (edge == WMSZ_TOP || edge == WMSZ_TOPLEFT ||
            edge == WMSZ_TOPRIGHT) {
          rect->top = rect->bottom - outer_height;
        } else {
          rect->bottom = rect->top + outer_height;
        }
      }
      return TRUE;
    }
    break;
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
  case WM_SYSCOMMAND:
    if (window != NULL && (wparam & 0xfff0) == SC_CLOSE &&
        !window->closable) {
      return 0;
    }
    break;
  case WM_CLOSE:
    if (window != NULL) {
      if (window->close_interception_enabled &&
          !window->close_authorized) {
        if (!window->close_request_pending) {
          window->close_request_id++;
          if (window->close_request_id == 0) {
            window->close_request_id = 1;
          }
          window->close_request_pending = 1;
          (void)proton_event_publish_window_close_requested(
              window->public_window_id, window->close_request_id);
          proton_engine_signal_wait_source(window->runtime,
                                           PROTON_WAIT_PLATFORM);
        }
        return 0;
      }
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
  case WM_COMMAND:
    if (window != NULL && HIWORD(wparam) == 0 &&
        window->app_menu_bindings != NULL) {
      proton_win_menu_dispatch_command(window, LOWORD(wparam));
      return 0;
    }
    break;
  case WM_DESTROY:
    if (window != NULL) {
      proton_win_menu_cleanup_window(window);
      if (window->window_icon != NULL) {
        DestroyIcon(window->window_icon);
        window->window_icon = NULL;
      }
      if (window->modal_parent && window->parent_hwnd != NULL &&
          IsWindow(window->parent_hwnd)) {
        EnableWindow(window->parent_hwnd, TRUE);
      }
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
  window->minimizable = 1;
  window->maximizable = 1;
  window->closable = 1;
  window->focusable = 1;
  window->fullscreenable = 1;
  window->enabled = 1;
  window->ignore_mouse_events = 0;
  window->ignore_mouse_forward = 0;
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
    if (runtime->menu_definition != NULL) {
      int32_t menu_status = proton_win_menu_apply_to_window(
          window, runtime->menu_definition, error, error_len);
      if (menu_status != PROTON_OK) {
        DestroyWindow(window->hwnd);
        window->hwnd = NULL;
        ((cef_base_ref_counted_t *)window->client)
            ->release((cef_base_ref_counted_t *)window->client);
        proton_browser_session_destroy(window->browser_session);
        free(window->bridge_config_json);
        free(window);
        return menu_status;
      }
    }
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

int32_t proton_engine_window_show_inactive(proton_engine_window_t *window,
                                           char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return proton_engine_window_show(window, error, error_len);
  ShowWindow(window->hwnd, SW_SHOWNOACTIVATE);
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

int32_t proton_engine_window_set_aspect_ratio(
    proton_engine_window_t *window, double aspect_ratio, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (isnan(aspect_ratio) || aspect_ratio < 0.0) {
    proton_engine_set_message(error, error_len,
                              "aspect ratio must be non-negative");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window aspect ratio is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->aspect_ratio = aspect_ratio;
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

int32_t proton_engine_window_set_skip_taskbar(proton_engine_window_t *window,
                                              int32_t skip, char *error,
                                              size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (skip != 0 && skip != 1) {
    proton_engine_set_message(error, error_len, "skip must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "taskbar visibility is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  ITaskbarList *taskbar = NULL;
  HRESULT hr = CoCreateInstance(&CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER,
                                &IID_ITaskbarList, (void **)&taskbar);
  if (FAILED(hr) || taskbar == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create taskbar list");
    return PROTON_ERR_PLATFORM;
  }
  hr = taskbar->lpVtbl->HrInit(taskbar);
  if (SUCCEEDED(hr)) {
    hr = skip != 0 ? taskbar->lpVtbl->DeleteTab(taskbar, window->hwnd)
                   : taskbar->lpVtbl->AddTab(taskbar, window->hwnd);
  }
  taskbar->lpVtbl->Release(taskbar);
  if (FAILED(hr)) {
    proton_engine_set_message(error, error_len,
                              "failed to update taskbar visibility");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_content_protection(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (enabled != 0 && enabled != 1) {
    proton_engine_set_message(error, error_len, "enabled must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "content protection is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  const DWORD affinity = enabled ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE;
  if (!SetWindowDisplayAffinity(window->hwnd, affinity)) {
    proton_engine_set_message(error, error_len,
                              "failed to update window display affinity");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimizable(
    proton_engine_window_t *window, int32_t minimizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (minimizable != 0 && minimizable != 1) {
    proton_engine_set_message(error, error_len, "minimizable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window minimizability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  DWORD style = window->fullscreen
                    ? window->windowed_style
                    : (DWORD)GetWindowLongW(window->hwnd, GWL_STYLE);
  if (minimizable) {
    style |= WS_MINIMIZEBOX;
  } else {
    style &= ~WS_MINIMIZEBOX;
  }
  if (window->fullscreen) {
    window->windowed_style = style;
  } else {
    SetLastError(0);
    if (SetWindowLongW(window->hwnd, GWL_STYLE, (LONG)style) == 0 &&
        GetLastError() != 0) {
      proton_engine_set_message(error, error_len, "failed to update window style");
      return PROTON_ERR_PLATFORM;
    }
    SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  }
  window->minimizable = minimizable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximizable(
    proton_engine_window_t *window, int32_t maximizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (maximizable != 0 && maximizable != 1) {
    proton_engine_set_message(error, error_len, "maximizable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window maximizability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  DWORD style = window->fullscreen
                    ? window->windowed_style
                    : (DWORD)GetWindowLongW(window->hwnd, GWL_STYLE);
  if (maximizable) {
    style |= WS_MAXIMIZEBOX;
  } else {
    style &= ~WS_MAXIMIZEBOX;
  }
  if (window->fullscreen) {
    window->windowed_style = style;
  } else {
    SetLastError(0);
    if (SetWindowLongW(window->hwnd, GWL_STYLE, (LONG)style) == 0 &&
        GetLastError() != 0) {
      proton_engine_set_message(error, error_len, "failed to update window style");
      return PROTON_ERR_PLATFORM;
    }
    SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  }
  window->maximizable = maximizable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_closable(
    proton_engine_window_t *window, int32_t closable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (closable != 0 && closable != 1) {
    proton_engine_set_message(error, error_len, "closable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window closability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  HMENU system_menu = GetSystemMenu(window->hwnd, FALSE);
  if (system_menu == NULL ||
      EnableMenuItem(system_menu, SC_CLOSE,
                     MF_BYCOMMAND | (closable ? MF_ENABLED : MF_GRAYED)) ==
          (UINT)-1) {
    proton_engine_set_message(error, error_len,
                              "failed to update window close control");
    return PROTON_ERR_PLATFORM;
  }
  DrawMenuBar(window->hwnd);
  window->closable = closable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_button_visibility(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (visible != 0 && visible != 1) {
    proton_engine_set_message(error, error_len, "visible must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window buttons are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_focusable(
    proton_engine_window_t *window, int32_t focusable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (focusable != 0 && focusable != 1) {
    proton_engine_set_message(error, error_len, "focusable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window focusability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  LONG_PTR style = GetWindowLongPtrW(window->hwnd, GWL_EXSTYLE);
  LONG_PTR updated = focusable ? (style & ~WS_EX_NOACTIVATE)
                               : (style | WS_EX_NOACTIVATE);
  SetLastError(0);
  if (SetWindowLongPtrW(window->hwnd, GWL_EXSTYLE, updated) == 0 &&
      GetLastError() != 0) {
    proton_engine_set_message(error, error_len,
                              "failed to update window focusability");
    return PROTON_ERR_PLATFORM;
  }
  window->focusable = focusable;
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
  if (window->headless && window->close_interception_enabled &&
      !window->close_authorized) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      (void)proton_event_publish_window_close_requested(
          window->public_window_id, window->close_request_id);
      proton_engine_signal_wait_source(window->runtime,
                                       PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
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

int32_t proton_engine_window_set_icon(proton_engine_window_t *window,
                                      const char *path, char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (path == NULL || path[0] == '\0') {
    proton_engine_set_message(error, error_len, "icon path is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window icon is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  wchar_t wide_path[PROTON_ENGINE_MAX_PATH_BYTES];
  if (proton_engine_utf8_to_wide(path, wide_path,
                                 (int)(sizeof(wide_path) / sizeof(wide_path[0]))) <= 0) {
    proton_engine_set_message(error, error_len, "icon path is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  HICON icon = (HICON)LoadImageW(NULL, wide_path, IMAGE_ICON, 0, 0,
                                 LR_LOADFROMFILE | LR_DEFAULTSIZE);
  if (icon == NULL) {
    proton_engine_set_message(error, error_len, "failed to load window icon");
    return PROTON_ERR_PLATFORM;
  }
  if (window->window_icon != NULL) DestroyIcon(window->window_icon);
  window->window_icon = icon;
  SendMessageW(window->hwnd, WM_SETICON, ICON_SMALL, (LPARAM)icon);
  SendMessageW(window->hwnd, WM_SETICON, ICON_BIG, (LPARAM)icon);
  return PROTON_OK;
}

int32_t proton_engine_window_set_parent(proton_engine_window_t *window,
                                        proton_engine_window_t *parent,
                                        int32_t modal, char *error,
                                        size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (modal != 0 && modal != 1) {
    proton_engine_set_message(error, error_len, "modal must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window parenting is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window->modal_parent && window->parent_hwnd != NULL &&
      IsWindow(window->parent_hwnd)) {
    EnableWindow(window->parent_hwnd, TRUE);
  }
  HWND parent_hwnd = parent != NULL ? parent->hwnd : NULL;
  SetLastError(0);
  if (SetWindowLongPtrW(window->hwnd, GWLP_HWNDPARENT,
                        (LONG_PTR)parent_hwnd) == 0 &&
      GetLastError() != 0) {
    proton_engine_set_message(error, error_len, "failed to set window owner");
    window->parent_hwnd = NULL;
    window->modal_parent = 0;
    return PROTON_ERR_PLATFORM;
  }
  window->parent_hwnd = parent_hwnd;
  window->modal_parent = modal != 0 && parent_hwnd != NULL;
  if (window->modal_parent) EnableWindow(parent_hwnd, FALSE);
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

int32_t proton_engine_window_set_content_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len, "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->width = width;
    window->height = height;
    proton_engine_resize_browser(window, width, height);
    return PROTON_OK;
  }
  RECT desired = {0, 0, width, height};
  DWORD style = (DWORD)GetWindowLongPtrW(window->hwnd, GWL_STYLE);
  DWORD ex_style = (DWORD)GetWindowLongPtrW(window->hwnd, GWL_EXSTYLE);
  if (!AdjustWindowRectEx(&desired, style, FALSE, ex_style)) {
    proton_engine_set_message(error, error_len, "failed to calculate window frame");
    return PROTON_ERR_PLATFORM;
  }
  return proton_engine_window_set_size(window, desired.right - desired.left,
                                       desired.bottom - desired.top, error,
                                       error_len);
}

int32_t proton_engine_window_get_content_size(
    proton_engine_window_t *window, int32_t *out_width, int32_t *out_height,
    char *error, size_t error_len) {
  if (window == NULL || out_width == NULL || out_height == NULL) {
    proton_engine_set_message(error, error_len, "window and outputs are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    *out_width = window->width;
    *out_height = window->height;
    return PROTON_OK;
  }
  RECT rect;
  if (!GetClientRect(window->hwnd, &rect)) {
    proton_engine_set_message(error, error_len, "failed to read client area");
    return PROTON_ERR_PLATFORM;
  }
  *out_width = rect.right - rect.left;
  *out_height = rect.bottom - rect.top;
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
  case PROTON_ENGINE_WINDOW_SET_KIOSK:
    if (action->kind == PROTON_ENGINE_WINDOW_SET_FULLSCREEN &&
        !window->fullscreenable && action->value != 0) break;
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
    if (action->value == 0 && window->resizable) {
      RECT frame;
      if (window->fullscreen) {
        frame = window->windowed_placement.rcNormalPosition;
      } else if (!GetWindowRect(window->hwnd, &frame)) {
        proton_engine_set_message(error, error_len,
                                  "failed to read current window frame");
        return PROTON_ERR_PLATFORM;
      }
      window->width = frame.right - frame.left;
      window->height = frame.bottom - frame.top;
    }
    DWORD style = window->fullscreen
                      ? window->windowed_style
                      : (DWORD)GetWindowLongW(window->hwnd, GWL_STYLE);
    if (action->value != 0) {
      style |= WS_THICKFRAME;
      if (window->maximizable) {
        style |= WS_MAXIMIZEBOX;
      }
    } else {
      style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    }
    if (window->fullscreen) {
      // Fullscreen uses a temporary borderless style. Update the saved
      // windowed style so the requested state is applied when it is restored.
      window->windowed_style = style;
    } else {
      SetLastError(0);
      if (SetWindowLongW(window->hwnd, GWL_STYLE, (LONG)style) == 0 &&
          GetLastError() != 0) {
        proton_engine_set_message(error, error_len,
                                  "failed to update window style");
        return PROTON_ERR_PLATFORM;
      }
      SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
    }
    window->resizable = action->value != 0;
    break;
  }
  default:
    proton_engine_set_message(error, error_len, "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_set_fullscreenable(
    proton_engine_window_t *window, int32_t fullscreenable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (fullscreenable != 0 && fullscreenable != 1) {
    proton_engine_set_message(error, error_len,
                              "fullscreenable must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window fullscreenability is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->fullscreenable = fullscreenable;
  return PROTON_OK;
}

int32_t proton_engine_window_set_has_shadow(
    proton_engine_window_t *window, int32_t has_shadow, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (has_shadow != 0 && has_shadow != 1) {
    proton_engine_set_message(error, error_len, "has_shadow must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window shadow is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_ignore_mouse_events(
    proton_engine_window_t *window, int32_t ignore, int32_t forward,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if ((ignore != 0 && ignore != 1) || (forward != 0 && forward != 1)) {
    proton_engine_set_message(error, error_len,
                              "ignore and forward must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "mouse event handling is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  LONG_PTR style = GetWindowLongPtrW(window->hwnd, GWL_EXSTYLE);
  if (ignore) style |= WS_EX_TRANSPARENT;
  else style &= ~WS_EX_TRANSPARENT;
  if (SetWindowLongPtrW(window->hwnd, GWL_EXSTYLE, style) == 0 &&
      GetLastError() != 0) {
    proton_engine_set_message(error, error_len,
                              "failed to update mouse event handling");
    return PROTON_ERR_PLATFORM;
  }
  window->ignore_mouse_events = ignore;
  window->ignore_mouse_forward = ignore ? forward : 0;
  SetWindowPos(window->hwnd, NULL, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  return PROTON_OK;
}

int32_t proton_engine_window_set_background_color(
    proton_engine_window_t *window, uint32_t color, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window background is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  const COLORREF native_color = RGB((color >> 16) & 0xff,
                                    (color >> 8) & 0xff, color & 0xff);
  HBRUSH brush = CreateSolidBrush(native_color);
  if (brush == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to create window background brush");
    return PROTON_ERR_PLATFORM;
  }
  SetLastError(ERROR_SUCCESS);
  if (SetClassLongPtrW(window->hwnd, GCLP_HBRBACKGROUND, (LONG_PTR)brush) == 0 &&
      GetLastError() != ERROR_SUCCESS) {
    DeleteObject(brush);
    window->background_brush = NULL;
    proton_engine_set_message(error, error_len,
                              "failed to update window background brush");
    return PROTON_ERR_PLATFORM;
  }
  if (window->background_brush != NULL) DeleteObject(window->background_brush);
  window->background_brush = brush;
  InvalidateRect(window->hwnd, NULL, TRUE);
  return PROTON_OK;
}

int32_t proton_engine_window_set_visible_on_all_workspaces(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (visible != 0 && visible != 1) {
    proton_engine_set_message(error, error_len, "visible must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "workspace visibility is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  // Windows has no desktop-wide window visibility equivalent. Electron also
  // treats this operation as a successful no-op on this platform.
  return PROTON_OK;
}

int32_t proton_engine_window_set_enabled(proton_engine_window_t *window,
                                         int32_t enabled, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->hwnd == NULL)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (enabled != 0 && enabled != 1) {
    proton_engine_set_message(error, error_len, "enabled must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return PROTON_OK;
  EnableWindow(window->hwnd, enabled != 0);
  window->enabled = enabled;
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
  if (window->close_interception_enabled) {
    window->close_authorized = 0;
  }
  if (!window->close_interception_enabled) {
    window->close_request_pending = 0;
  }
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
    window->close_authorized = 1;
    if (window->headless) {
      return proton_engine_window_close(window, error, error_len);
    }
    if (window->hwnd != NULL) {
      PostMessageW(window->hwnd, WM_CLOSE, 0, 0);
    }
  } else if (!allow) {
    window->close_authorized = 0;
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

int32_t proton_engine_window_get_navigation_state(
    proton_engine_window_t *window, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_navigation_state(
      window->browser, out_can_go_back, out_can_go_forward, error, error_len);
}

int32_t proton_engine_window_set_audio_muted(
    proton_engine_window_t *window, int32_t muted, char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_set_audio_muted(
      window->browser, muted, error, error_len);
}

int32_t proton_engine_window_is_audio_muted(
    proton_engine_window_t *window, int32_t *out_muted, char *error,
    size_t error_len) {
  if (window == NULL || window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_is_audio_muted(
      window->browser, out_muted, error, error_len);
}

int32_t proton_engine_window_get_browser_url(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  int32_t status = proton_browser_session_copy_url(
      window->browser_session, buffer, buffer_len, out_required_len);
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len,
                              "browser URL buffer is too small");
  }
  return status;
}

int32_t proton_engine_window_get_browser_title(
    proton_engine_window_t *window, char *buffer, int32_t buffer_len,
    int32_t *out_required_len, char *error, size_t error_len) {
  if (window == NULL || window->browser_session == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  int32_t status = proton_browser_session_copy_title(
      window->browser_session, buffer, buffer_len, out_required_len);
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len,
                              "browser title buffer is too small");
  }
  return status;
}

int32_t proton_engine_window_get_browser_loading(
    proton_engine_window_t *window, int32_t *out_is_loading, char *error,
    size_t error_len) {
  if (window == NULL || window->browser_session == NULL ||
      out_is_loading == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser session and loading output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_is_loading = proton_browser_session_is_loading(window->browser_session);
  return PROTON_OK;
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
