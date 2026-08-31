#if defined(_WIN32)

#include "win_internal.h"

#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) InterlockedIncrement(&(refs)->refs)
#define PROTON_ENGINE_REF_DECREMENT(refs) InterlockedDecrement(&(refs)->refs)
#define PROTON_ENGINE_REF_LOAD(refs) InterlockedCompareExchange(&(refs)->refs, 0, 0)
#define PROTON_ENGINE_REF_STORE(refs, value) InterlockedExchange(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Web contents views
//
// A view is an extra child browser hosted inside a window's client area,
// following the Electron WebContentsView model: explicit top-left bounds,
// visibility, z-order, and an independent load target. Struct lifetime is
// owned by the window: views are only freed from proton_engine_window_free
// once every view has finalized, so native ABI view slots stay valid for the
// whole window lifetime. Close semantics mirror the macOS engine: do_close
// takes over from CEF's default (which would post WM_CLOSE to the frame
// window) and tears down the browser's child HWND instead.

static proton_engine_display_handler_t g_display_handler;
static uint64_t g_next_view_native_id = 1;

static void proton_engine_view_list_add(proton_engine_window_t *window,
                                        proton_engine_view_t *view) {
  proton_engine_window_lock();
  view->next = window->views;
  window->views = view;
  proton_engine_window_unlock();
}

void proton_engine_window_free_views(proton_engine_window_t *window) {
  proton_engine_view_t *view = window->views;
  window->views = NULL;
  while (view != NULL) {
    proton_engine_view_t *next = view->next;
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    if (view->client != NULL) {
      view->client->view = NULL;
    }
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view);
    view = next;
  }
}

void proton_engine_view_finalize_if_ready(proton_engine_view_t *view) {
  if (view == NULL || view->finalized ||
      !view->finalize_after_browser_close) {
    return;
  }
  proton_browser_lifecycle_state_t browser_state =
      proton_browser_lifecycle_state(view->browser_lifecycle);
  if (browser_state != PROTON_BROWSER_CLOSED &&
      browser_state != PROTON_BROWSER_CREATION_FAILED) {
    return;
  }
  if (view->client != NULL) {
    view->client->view = NULL;
  }
  proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
  view->hwnd = NULL;
  view->finalized = 1;
  // The window's own finalize is gated on every view being finalized; this
  // call is a no-op unless the window is waiting on exactly this view.
  proton_engine_window_finalize_if_ready(view->window);
}

void proton_engine_window_finalize_if_ready(proton_engine_window_t *window) {
  if (window == NULL || window->finalize_queued ||
      !window->destroy_requested) {
    return;
  }
  proton_browser_lifecycle_state_t browser_state =
      proton_browser_lifecycle_state(window->browser_lifecycle);
  if (browser_state != PROTON_BROWSER_CLOSED &&
      browser_state != PROTON_BROWSER_CREATION_FAILED) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->finalized) {
      return;
    }
  }
  // OnBeforeClose is CEF's final browser callback, but CEF still owns and
  // releases callback objects while unwinding it and during cef_shutdown.
  // Keep the host storage alive until that shutdown has completed.
  proton_engine_window_defer_free(window);
}

void proton_engine_window_close_views(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->closed) {
      view->closed = 1;
      view->finalize_after_browser_close = 1;
      if (view->browser != NULL) {
        proton_browser_lifecycle_request_close(view->browser_lifecycle, 1);
      }
    } else if (!view->finalize_after_browser_close) {
      // Already closed by the page (JS window.close): allow its cleanup to
      // complete so the window finalize gate can pass.
      view->finalize_after_browser_close = 1;
    }
    proton_engine_view_finalize_if_ready(view);
  }
}

// Re-stacks view browser windows above the window's main browser view by
// ascending (z_order, native_id).
void proton_engine_window_layout_views(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->hwnd != NULL && !view->closed) {
      count++;
    }
  }
  if (count == 0) {
    return;
  }
  proton_engine_view_t **order =
      (proton_engine_view_t **)malloc(count * sizeof(*order));
  if (order == NULL) {
    return;
  }
  size_t index = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->hwnd != NULL && !view->closed) {
      order[index++] = view;
    }
  }
  for (size_t i = 1; i < count; i++) {
    proton_engine_view_t *current = order[i];
    size_t j = i;
    while (j > 0 &&
           (order[j - 1]->z_order > current->z_order ||
            (order[j - 1]->z_order == current->z_order &&
             order[j - 1]->native_id > current->native_id))) {
      order[j] = order[j - 1];
      j--;
    }
    order[j] = current;
  }
  for (size_t i = 0; i < count; i++) {
    SetWindowPos(order[i]->hwnd, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  free(order);
}

int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_browser_lifecycle_t *lifecycle =
      proton_engine_browser_lifecycle(browser);
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) != PROTON_BROWSER_ROLE_VIEW) {
    // Main and DevTools browsers keep CEF's top-level close behavior.
    return 0;
  }
  proton_engine_view_t *view =
      (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
  if (view == NULL) {
    return 0;
  }
  // A view browser owns no top-level window; CEF's default would post
  // WM_CLOSE to the frame window and cancel the view close. Take over and
  // destroy the browser's child window on the next frame-window message,
  // which completes the teardown via WindowDestroyed without re-entering CEF.
  if (view->hwnd != NULL) {
    PostMessageW(view->window->hwnd, PROTON_ENGINE_WM_DESTROY_CHILD, 0,
                 (LPARAM)view->hwnd);
    view->hwnd = NULL;
    return 1;
  }
  // Windowless (headless) rendering has no child window; returning false lets
  // CEF destroy the browser object immediately.
  return 0;
}

void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title) {
  (void)self;
  proton_engine_view_t *view =
      proton_engine_find_view_by_browser_id(proton_engine_browser_id(browser));
  char *title_utf8 = proton_engine_cef_string_to_utf8(title);
  if (view != NULL) {
    proton_view_events_title_updated(view->events, title_utf8);
    free(title_utf8);
    proton_engine_signal_wait_source(view->window->runtime, PROTON_WAIT_EVENT);
    return;
  }
  proton_engine_window_t *window =
      proton_engine_find_window_by_browser_id(proton_engine_browser_id(browser));
  proton_browser_session_title_updated(
      window != NULL ? window->browser_session : NULL, title_utf8);
  free(title_utf8);
}

cef_display_handler_t *CEF_CALLBACK
proton_engine_client_get_display_handler(cef_client_t *self) {
  (void)self;
  g_display_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_display_handler.handler);
  return &g_display_handler.handler;
}

void proton_engine_view_handlers_init(void) {
  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_display_handler.handler.base,
      sizeof(g_display_handler.handler), &g_display_handler.refs);
  g_display_handler.handler.on_title_change = proton_engine_on_title_change;
}

static proton_engine_client_t *proton_engine_view_client_create(
    proton_engine_view_t *view,
    proton_browser_lifecycle_t *browser_lifecycle) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->client.base.release = proton_engine_client_release;
  client->view = view;
  client->browser_lifecycle = browser_lifecycle;
  // Views wire the life span, load, display, and render handlers: life span
  // drives the close state machine, load/display feed the view event stream,
  // and the render handler gives headless (OSR) views a viewport. Find results
  // are view-scoped. Navigation policy, bridge, downloads, and
  // permissions stay window-scoped for now.
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_display_handler = proton_engine_client_get_display_handler;
  client->client.get_find_handler = view->window->client->get_find_handler;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
  return client;
}

static int32_t proton_engine_view_create_browser(
    proton_engine_view_t *view,
    char *error,
    size_t error_len) {
  proton_engine_window_t *window = view->window;
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
  window_info.bounds.x = view->x;
  window_info.bounds.y = view->y;
  window_info.bounds.width = view->width;
  window_info.bounds.height = view->height;
  if (view->has_background_color) {
    browser_settings.background_color = view->background_color;
  }
  proton_engine_set_string(&window_info.window_name, "ProtonView");
  proton_engine_set_string(&url, "about:blank");
  cef_browser_t *created_browser = cef_browser_host_create_browser_sync(
      &window_info, &view->client->client, &url, &browser_settings, NULL,
      NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (created_browser == NULL) {
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_engine_set_message(error, error_len, "view browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_adopt_created(view->browser_lifecycle,
                                         created_browser);
  view->browser = proton_browser_lifecycle_browser(view->browser_lifecycle);
  view->browser_id =
      proton_browser_lifecycle_browser_id(view->browser_lifecycle);
  cef_browser_host_t *host = view->browser->get_host(view->browser);
  if (host != NULL) {
    double factor = (double)view->zoom_percent / 100.0;
    host->set_zoom_level(host, log(factor) / log(1.2));
    if (host->set_audio_muted != NULL) {
      host->set_audio_muted(host, view->audio_muted);
    }
    if (window->headless) {
      if (!view->visible && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
    } else {
      view->hwnd = host->get_window_handle(host);
      if (!view->visible && view->hwnd != NULL) {
        ShowWindow(view->hwnd, SW_HIDE);
      }
    }
    host->base.release((cef_base_ref_counted_t *)host);
  }
  proton_engine_window_layout_views(window);
  if (view->initial_url[0] != '\0' &&
      strcmp(view->initial_url, "about:blank") != 0) {
    cef_frame_t *frame = view->browser->get_main_frame(view->browser);
    if (frame != NULL) {
      cef_string_t initial = {0};
      proton_engine_set_string(&initial, view->initial_url);
      frame->load_url(frame, &initial);
      cef_string_clear(&initial);
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
  }
  return PROTON_OK;
}

int32_t proton_engine_view_create(
    proton_engine_window_t *window,
    const proton_engine_view_config_t *input_config,
    proton_engine_view_t **out_view, char *error, size_t error_len) {
  if (out_view == NULL) {
    proton_engine_set_message(error, error_len, "out_view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_view = NULL;
  if (window == NULL || input_config == NULL) {
    proton_engine_set_message(error, error_len,
                              "window and view config are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->closed) {
    proton_engine_set_message(error, error_len, "window is closed");
    return PROTON_ERR_DESTROYED;
  }
  proton_engine_view_config_t config = *input_config;
  int32_t status = PROTON_OK;

  proton_engine_view_t *view =
      (proton_engine_view_t *)calloc(1, sizeof(*view));
  if (view == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  view->window = window;
  view->native_id = g_next_view_native_id++;
  if (g_next_view_native_id == 0) {
    g_next_view_native_id = 1;
  }
  view->x = config.x;
  view->y = config.y;
  view->width = config.width;
  view->height = config.height;
  view->z_order = config.z_order;
  view->zoom_percent = 100;
  view->audio_muted = 0;
  view->visible = config.visible;
  view->has_background_color = config.has_background_color;
  view->background_color = config.background_color;
  snprintf(view->initial_url, sizeof(view->initial_url), "%s",
           config.initial_url);
  view->browser_lifecycle = proton_browser_lifecycle_create(
      window->runtime->browsers, PROTON_BROWSER_ROLE_VIEW, view, NULL);
  if (view->browser_lifecycle == NULL) {
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser lifecycle");
    return PROTON_ERR_ENGINE;
  }
  view->client = proton_engine_view_client_create(
      view, view->browser_lifecycle);
  proton_browser_policy_t view_policy = {PROTON_BROWSER_POLICY_ALLOW,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         1};
  view->browser_session = proton_browser_session_create(
      &view_policy, proton_engine_browser_signal, NULL);
  view->events = proton_view_events_create();
  if (view->client == NULL || view->browser_session == NULL ||
      view->events == NULL) {
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    if (view->client != NULL) {
      view->client->view = NULL;
      proton_browser_lifecycle_set_client(view->browser_lifecycle,
                                          &view->client->client);
    }
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_set_client(view->browser_lifecycle,
                                      &view->client->client);
  proton_browser_session_bind_lifecycle(view->browser_session,
                                        view->browser_lifecycle);
  proton_view_events_bind(view->events, config.public_view,
                          config.public_window);
  proton_engine_view_list_add(window, view);
  status = proton_engine_view_create_browser(view, error, error_len);
  if (status != PROTON_OK) {
    // The browser never started, so the view finalizes immediately; the
    // struct stays owned by the window list and is reclaimed with it.
    view->closed = 1;
    view->finalize_after_browser_close = 1;
    proton_engine_view_finalize_if_ready(view);
    return status;
  }
  proton_engine_signal_wait_source(window->runtime, PROTON_WAIT_PLATFORM);
  *out_view = view;
  return PROTON_OK;
}

int32_t proton_engine_view_destroy(proton_engine_view_t *view,
                                   char *error,
                                   size_t error_len) {
  if (view == NULL) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->closed) {
    return PROTON_OK;
  }
  view->closed = 1;
  view->finalize_after_browser_close = 1;
  if (view->browser != NULL) {
    proton_browser_lifecycle_request_close(view->browser_lifecycle, 1);
  }
  proton_engine_view_finalize_if_ready(view);
  return PROTON_OK;
}

int32_t proton_engine_view_set_bounds(proton_engine_view_t *view,
                                      int32_t x,
                                      int32_t y,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "view width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->x = x;
  view->y = y;
  view->width = width;
  view->height = height;
  if (view->window != NULL && view->window->headless) {
    if (view->browser != NULL) {
      cef_browser_host_t *host = view->browser->get_host(view->browser);
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else if (view->hwnd != NULL) {
    SetWindowPos(view->hwnd, NULL, x, y, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_visible(proton_engine_view_t *view,
                                       int32_t visible,
                                       char *error,
                                       size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->visible = visible ? 1 : 0;
  if (view->window != NULL && view->window->headless) {
    if (view->browser != NULL) {
      cef_browser_host_t *host = view->browser->get_host(view->browser);
      if (host != NULL && host->was_hidden != NULL) {
        host->was_hidden(host, view->visible ? 0 : 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else if (view->hwnd != NULL) {
    ShowWindow(view->hwnd, view->visible ? SW_SHOW : SW_HIDE);
  }
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_z_order(proton_engine_view_t *view,
                                       int32_t z_order,
                                       char *error,
                                       size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  view->z_order = z_order;
  proton_engine_window_layout_views(view->window);
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_zoom_percent(proton_engine_view_t *view,
                                            int32_t zoom_percent,
                                            char *error,
                                            size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int32_t status = proton_browser_set_zoom_percent(
      view->browser, zoom_percent, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  view->zoom_percent = zoom_percent;
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_audio_muted(proton_engine_view_t *view,
                                           int32_t muted, char *error,
                                           size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->browser != NULL) {
    int32_t status = proton_browser_set_audio_muted(
        view->browser, muted, error, error_len);
    if (status != PROTON_OK) {
      return status;
    }
  }
  view->audio_muted = muted != 0;
  return PROTON_OK;
}

int32_t proton_engine_view_is_audio_muted(proton_engine_view_t *view,
                                          int32_t *out_muted, char *error,
                                          size_t error_len) {
  if (view == NULL || view->closed || out_muted == NULL) {
    proton_engine_set_message(error, error_len,
                              "view and muted output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->browser != NULL) {
    int32_t status = proton_browser_is_audio_muted(
        view->browser, out_muted, error, error_len);
    if (status != PROTON_OK) {
      return status;
    }
    view->audio_muted = *out_muted != 0;
  } else {
    *out_muted = view->audio_muted ? 1 : 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_view_load_url(proton_engine_view_t *view,
                                    const char *url,
                                    char *error,
                                    size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = view->browser->get_main_frame(view->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t cef_url = {0};
  proton_engine_set_string(&cef_url, url != NULL ? url : "about:blank");
  frame->load_url(frame, &cef_url);
  cef_string_clear(&cef_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_eval(proton_engine_view_t *view,
                                const char *script,
                                char *error,
                                size_t error_len) {
  if (view == NULL || view->closed || view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = view->browser->get_main_frame(view->browser);
  if (frame == NULL) {
    proton_engine_set_message(error, error_len, "main frame is not available");
    return PROTON_ERR_ENGINE;
  }
  cef_string_t code = {0};
  cef_string_t script_url = {0};
  proton_engine_set_string(&code, script != NULL ? script : "");
  proton_engine_set_string(&script_url, "proton://eval.js");
  frame->execute_java_script(frame, &code, &script_url, 1);
  cef_string_clear(&code);
  cef_string_clear(&script_url);
  frame->base.release((cef_base_ref_counted_t *)frame);
  proton_engine_signal_wait_source(view->window->runtime,
                                   PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_browser_command_json(proton_engine_view_t *view,
                                                const char *command_json,
                                                char *error,
                                                size_t error_len) {
  if (view == NULL || view->closed || view->browser_session == NULL ||
      view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(view->browser_session,
                                             view->browser, command_json,
                                             error, error_len);
}

int32_t proton_engine_view_get_browser_focus_state(
    proton_engine_view_t *view, int32_t *out_focused,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser_session == NULL ||
      view->browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (out_focused == NULL) {
    proton_engine_set_message(error, error_len, "focus output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (view->window != NULL && view->window->headless) {
    return proton_browser_headless_is_focused(
        view->browser, out_focused, error, error_len);
  }
  if (view->hwnd == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser window is not available");
    return PROTON_ERR_ENGINE;
  }
  *out_focused = proton_engine_browser_hwnd_is_focused(view->hwnd);
  return PROTON_OK;
}

int32_t proton_engine_view_get_devtools_state(
    proton_engine_view_t *view, int32_t *out_opened,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_is_devtools_opened(
      view->browser, out_opened, error, error_len);
}

int32_t proton_engine_view_get_navigation_state(
    proton_engine_view_t *view, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_navigation_state(
      view->browser, out_can_go_back, out_can_go_forward, error, error_len);
}

int32_t proton_engine_view_find_in_page(
    proton_engine_view_t *view, const char *text, int32_t forward,
    int32_t match_case, int32_t find_next, int32_t *out_request_id,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser_session == NULL ||
      view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_find_in_page(
      view->browser_session, view->browser, text, forward, match_case,
      find_next, out_request_id, error, error_len);
}

int32_t proton_engine_view_stop_find_in_page(
    proton_engine_view_t *view, int32_t clear_selection, char *error,
    size_t error_len) {
  if (view == NULL || view->closed || view->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_stop_find_in_page(
      view->browser, clear_selection, error, error_len);
}


#endif
