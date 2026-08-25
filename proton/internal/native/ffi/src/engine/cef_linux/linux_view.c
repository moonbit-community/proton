#if defined(__linux__)

#include "linux_internal.h"

#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/message.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"

#define PROTON_ENGINE_REF_INCREMENT(refs) atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#include "../cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#include <gdk/gdkx.h>
#include <X11/Xlib.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Web contents views
//
// A view is an extra child browser hosted inside a window's browser host,
// following the Electron WebContentsView model: explicit top-left bounds,
// visibility, z-order, and an independent load target. Struct lifetime is
// owned by the window: views are only freed from the window's storage
// teardown once every view has finalized, so native ABI view slots stay
// valid for the whole window lifetime. Close semantics mirror the macOS
// engine: do_close takes over from CEF's default (which would post a delete
// event to the frame window) and destroys the browser's X window instead.

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
    free(view->client);
    free(view);
    view = next;
  }
}

void proton_engine_view_finalize_if_ready(proton_engine_view_t *view) {
  if (view == NULL || view->finalized ||
      !view->finalize_after_browser_close) {
    return;
  }
  if (view->browser_id != 0 && !view->browser_before_close_seen) {
    return;
  }
  if (view->client != NULL) {
    view->client->view = NULL;
  }
  view->xwindow = 0;
  view->finalized = 1;
  // The window's own finalize is gated on every view being finalized; this
  // call is a no-op unless the window is waiting on exactly this view.
  proton_engine_window_finalize_if_ready(view->window);
}

void proton_engine_window_finalize_if_ready(proton_engine_window_t *window) {
  if (window == NULL || !window->destroy_requested ||
      window->browser != NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->finalized) {
      return;
    }
  }
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
        cef_browser_host_t *host = view->browser->get_host(view->browser);
        if (host != NULL) {
          view->browser_close_requested = 1;
          host->close_browser(host, 1);
          host->base.release((cef_base_ref_counted_t *)host);
        } else {
          // A browser without a host can never deliver on_before_close.
          view->browser_before_close_seen = 1;
        }
        proton_engine_browser_release(view->browser);
        view->browser = NULL;
      }
    } else if (!view->finalize_after_browser_close) {
      // Already closed by the page (JS window.close): allow its cleanup to
      // complete so the window finalize gate can pass.
      view->finalize_after_browser_close = 1;
    }
    proton_engine_view_finalize_if_ready(view);
  }
}

// Re-stacks view browser X windows above the window's main browser by
// ascending (z_order, native_id).
void proton_engine_window_layout_views(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->xwindow != 0 && view->display != NULL && !view->closed) {
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
    if (view->xwindow != 0 && view->display != NULL && !view->closed) {
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
    XRaiseWindow(order[i]->display, order[i]->xwindow);
  }
  free(order);
}

int CEF_CALLBACK proton_engine_do_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL) {
    // Frame windows keep CEF's default close behavior (delete event on the
    // top-level window).
    return 0;
  }
  // A view browser owns no top-level window; CEF's default would deliver a
  // delete event to the frame window and cancel the view close. Take over
  // and destroy the browser's X window, which completes the teardown via
  // WindowDestroyed.
  if (view->xwindow != 0 && view->display != NULL) {
    XDestroyWindow(view->display, view->xwindow);
    view->xwindow = 0;
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
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view == NULL) {
    return;
  }
  char *title_utf8 = proton_engine_cef_string_to_utf8(title);
  proton_view_events_title_updated(view->events, title_utf8);
  free(title_utf8);
  proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
}

static cef_display_handler_t *CEF_CALLBACK
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
    proton_engine_view_t *view) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->view = view;
  // Views wire the life span, load, display, and render handlers: life span
  // drives the close state machine, load/display feed the view event stream,
  // and the render handler gives headless (OSR) views a viewport. Navigation
  // policy, bridge, downloads, and permissions stay window-scoped for now.
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_display_handler = proton_engine_client_get_display_handler;
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
  if (!window->headless &&
      (window->browser_host == NULL ||
       gtk_widget_get_window(window->browser_host) == NULL)) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for view browser creation");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  } else {
    GdkWindow *host_gdk_window = gtk_widget_get_window(window->browser_host);
    view->display = GDK_WINDOW_XDISPLAY(host_gdk_window);
    window_info.parent_window =
        (cef_window_handle_t)GDK_WINDOW_XID(host_gdk_window);
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
  view->browser = cef_browser_host_create_browser_sync(
      &window_info, &view->client->client, &url, &browser_settings, NULL,
      NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (view->browser == NULL) {
    proton_engine_set_message(error, error_len, "view browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  view->browser_id = proton_engine_browser_id(view->browser);
  cef_browser_host_t *host = view->browser->get_host(view->browser);
  if (host != NULL) {
    if (window->headless) {
      if (!view->visible && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
    } else {
      view->xwindow = host->get_window_handle(host);
      if (!view->visible && view->xwindow != 0 && view->display != NULL) {
        XUnmapWindow(view->display, view->xwindow);
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
  view->visible = config.visible;
  view->has_background_color = config.has_background_color;
  view->background_color = config.background_color;
  snprintf(view->initial_url, sizeof(view->initial_url), "%s",
           config.initial_url);
  view->client = proton_engine_view_client_create(view);
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
    free(view->client);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  cef_browser_host_t *host =
      view->browser != NULL ? view->browser->get_host(view->browser) : NULL;
  if (view->browser != NULL && host == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser host is not available for close");
    return PROTON_ERR_ENGINE;
  }
  view->closed = 1;
  view->finalize_after_browser_close = 1;
  if (view->browser != NULL) {
    view->browser_close_requested = 1;
    host->close_browser(host, 1);
    host->base.release((cef_base_ref_counted_t *)host);
    proton_engine_browser_release(view->browser);
    view->browser = NULL;
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
  } else if (view->xwindow != 0 && view->display != NULL) {
    XMoveResizeWindow(view->display, view->xwindow, x, y, width, height);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  } else if (view->xwindow != 0 && view->display != NULL) {
    if (view->visible) {
      XMapWindow(view->display, view->xwindow);
    } else {
      XUnmapWindow(view->display, view->xwindow);
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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

#endif
