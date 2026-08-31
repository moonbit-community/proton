#if defined(__APPLE__)

#include "mac_internal.h"

#include "../ffi/src/proton_config.h"
#include "../ffi/src/proton_event.h"
#include "../ffi/src/proton_json.h"
#include "../ffi/src/engine/cef_common/browser_session.h"
#include "../ffi/src/engine/cef_common/message.h"
#define PROTON_ENGINE_REF_INCREMENT(refs) \
  atomic_fetch_add_explicit(&(refs)->refs, 1, memory_order_relaxed)
#define PROTON_ENGINE_REF_DECREMENT(refs) \
  (atomic_fetch_sub_explicit(&(refs)->refs, 1, memory_order_acq_rel) - 1)
#define PROTON_ENGINE_REF_LOAD(refs) \
  atomic_load_explicit(&(refs)->refs, memory_order_acquire)
#define PROTON_ENGINE_REF_STORE(refs, value) atomic_store(&(refs)->refs, value)
#include "../ffi/src/engine/cef_common/ref_count.h"
#undef PROTON_ENGINE_REF_INCREMENT
#undef PROTON_ENGINE_REF_DECREMENT
#undef PROTON_ENGINE_REF_LOAD
#undef PROTON_ENGINE_REF_STORE
#include "../ffi/src/engine/cef_common/scheme.h"
#include "../ffi/src/engine/cef_common/strings.h"
#include "../ffi/src/engine/cef_common/view_events.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#import <Cocoa/Cocoa.h>
#include <dispatch/dispatch.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Web contents views
//
// A view is an extra browser hosted inside a window's content view, following
// the Electron WebContentsView model: explicit top-left bounds, visibility,
// z-order, and an independent load_url target. Views reuse the window's
// deferred browser-creation dance (CEF issue 3810) and mirror the window
// browser close/finalize state machine: closing is gated on CEF's
// on_before_close, and the owning window's finalize waits until every view
// has left its view list.

typedef struct {
  cef_task_t task;
  proton_engine_ref_counted_t refs;
  uint64_t native_id;
} proton_engine_view_navigation_task_t;

cef_browser_t *proton_engine_view_browser(proton_engine_view_t *view) {
  return view != NULL
             ? proton_browser_lifecycle_browser(view->browser_lifecycle)
             : NULL;
}

static void proton_engine_view_list_add(proton_engine_window_t *window,
                                        proton_engine_view_t *view) {
  proton_engine_window_lock();
  view->next = window->views;
  window->views = view;
  proton_engine_window_unlock();
}

// Converts the public top-left bounds into the content view's bottom-left
// coordinate space and pins the view to the top edge so window resizes keep
// the Electron-style top-left anchoring.
static void proton_engine_view_apply_frame(proton_engine_view_t *view) {
  if (view == NULL || view->window == NULL ||
      view->window->content_view == nil || view->browser_view == nil) {
    return;
  }
  CGFloat content_height = view->window->content_view.bounds.size.height;
  NSRect frame = NSMakeRect((CGFloat)view->x,
                            content_height - (CGFloat)view->y -
                                (CGFloat)view->height,
                            (CGFloat)view->width, (CGFloat)view->height);
  [view->browser_view setFrame:frame];
  [view->browser_view setAutoresizingMask:NSViewMinYMargin];
  [view->browser_view setHidden:view->visible ? NO : YES];
}

// Re-orders view browser views above the window's main browser view by
// ascending (z_order, native_id); the main browser view stays at the bottom
// because it was added first and is never re-added here.
void proton_engine_window_layout_views(proton_engine_window_t *window) {
  if (window == NULL || window->content_view == nil) {
    return;
  }
  size_t count = 0;
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (view->browser_view != nil && !view->closed) {
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
    if (view->browser_view != nil && !view->closed) {
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
    [window->content_view addSubview:order[i]->browser_view
                          positioned:NSWindowAbove
                          relativeTo:nil];
  }
  free(order);
}

static int proton_engine_view_request_browser_close(proton_engine_view_t *view,
                                                    int force_close) {
  if (view == NULL || proton_engine_view_browser(view) == NULL) {
    return 0;
  }
  proton_browser_lifecycle_request_close(view->browser_lifecycle,
                                         force_close);
  // For windowed rendering the browser only dies once its host view leaves
  // the view hierarchy (CefBrowserHostView dealloc -> WindowDestroyed). The
  // detach is owned by do_close, which runs inside the close handshake above
  // and cancels CEF's default performClose: on the owning NSWindow. Do NOT
  // detach here: when CEF defers the close past this call (beforeunload or
  // unload handlers), do_close would later find browser_view already nil and
  // fall through to CEF's default, which the window delegate cancels, wedging
  // the browser half-closed and leaking it.
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return 1;
}

static void proton_engine_view_mark_closed(proton_engine_view_t *view) {
  if (view == NULL) {
    return;
  }
  view->closed = 1;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_view_defer_finalize(proton_engine_view_t *view) {
  if (view == NULL) {
    return;
  }
  view->finalize_after_browser_close = 1;
  view->browser_create_pending = 0;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_window_free_views(proton_engine_window_t *window) {
  proton_engine_view_t *view = window->views;
  window->views = NULL;
  while (view != NULL) {
    proton_engine_view_t *next = view->next;
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view->initial_url);
    free(view);
    view = next;
  }
}

void proton_engine_view_finalize_if_ready(proton_engine_view_t *view) {
  if (view == NULL || view->finalized ||
      !view->finalize_after_browser_close) {
    return;
  }
  if (view->browser_create_scheduled || view->initial_navigation_pending) {
    return;
  }
  proton_browser_lifecycle_state_t browser_state =
      proton_browser_lifecycle_state(view->browser_lifecycle);
  if (browser_state != PROTON_BROWSER_CLOSED &&
      browser_state != PROTON_BROWSER_CREATION_FAILED) {
    return;
  }
  // Resource cleanup only. The struct stays in the window's view list and is
  // freed by proton_engine_window_free once every view has finalized, which
  // keeps native ABI view slots valid for the whole window lifetime.
  proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
  if (view->browser_view != nil) {
    [view->browser_view removeFromSuperview];
    view->browser_view = nil;
  }
  view->finalized = 1;
  // The window's own finalize is gated on every view being finalized; this
  // call is a no-op unless the window is waiting on exactly this view.
  proton_engine_window_finalize_if_ready(view->window);
}

void proton_engine_window_close_views(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->closed) {
      if (proton_engine_view_browser(view) != NULL) {
        proton_engine_view_request_browser_close(view, 1);
        proton_engine_view_mark_closed(view);
        proton_engine_view_defer_finalize(view);
      } else {
        proton_engine_view_mark_closed(view);
        proton_engine_view_defer_finalize(view);
      }
    } else if (!view->finalize_after_browser_close) {
      // Already closed by the page (JS window.close): allow its cleanup to
      // complete so the window finalize gate can pass.
      proton_engine_view_defer_finalize(view);
    }
    proton_engine_view_finalize_if_ready(view);
  }
}

static int32_t proton_engine_view_create_browser(proton_engine_view_t *view,
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
  if (window->content_view != nil) {
    window_info.parent_view = (__bridge void *)window->content_view;
  }
  if (window->headless) {
    window_info.windowless_rendering_enabled = 1;
    window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  }
  CGFloat content_height = window->content_view != nil
                               ? window->content_view.bounds.size.height
                               : (CGFloat)(view->y + view->height);
  window_info.bounds.x = view->x;
  window_info.bounds.y =
      (int)(content_height - (CGFloat)view->y - (CGFloat)view->height);
  window_info.bounds.width = view->width;
  window_info.bounds.height = view->height;
  if (view->has_background_color) {
    browser_settings.background_color = view->background_color;
  }
  proton_engine_set_string(&window_info.window_name, "ProtonView");
  proton_engine_set_string(&url, "about:blank");
  int accepted = cef_browser_host_create_browser(
      &window_info, proton_browser_lifecycle_client(view->browser_lifecycle), &url, &browser_settings, NULL,
      NULL);
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (!accepted) {
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_engine_set_message(error, error_len, "view browser creation failed");
    return PROTON_ERR_ENGINE;
  }
  return PROTON_OK;
}

static void proton_engine_view_schedule_browser_create(
    proton_engine_view_t *view) {
  uint64_t native_id = view->native_id;
  view->browser_create_scheduled = 1;
  // Mirror the window path: create CEF browsers after the main run loop has
  // started pumping (CEF issue 3810).
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_view_t *pending_view =
        proton_engine_view_from_native_id(native_id);
    if (pending_view == NULL) {
      return;
    }
    if (pending_view->closed || !pending_view->browser_create_pending) {
      pending_view->browser_create_scheduled = 0;
      proton_engine_view_finalize_if_ready(pending_view);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
      return;
    }
    pending_view->browser_create_pending = 0;
    pending_view->initial_navigation_pending = 1;
    char error[512] = {0};
    int32_t status =
        proton_engine_view_create_browser(pending_view, error, sizeof(error));
    if (status != PROTON_OK) {
      pending_view->initial_navigation_pending = 0;
      pending_view->browser_create_scheduled = 0;
      proton_engine_view_mark_closed(pending_view);
      proton_engine_view_finalize_if_ready(pending_view);
    }
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static void CEF_CALLBACK proton_engine_view_navigation_task_execute(
    cef_task_t *base) {
  proton_engine_view_navigation_task_t *task =
      (proton_engine_view_navigation_task_t *)base;
  proton_engine_view_t *view = proton_engine_view_from_native_id(
      task->native_id);
  if (view == NULL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      free(task);
    });
    return;
  }
  view->initial_navigation_pending = 0;
  if (view->initial_url != NULL && view->initial_url[0] != '\0' &&
      strcmp(view->initial_url, "about:blank") != 0) {
    char error[512] = {0};
    int32_t status = proton_engine_view_load_url(view, view->initial_url,
                                                 error, sizeof(error));
    if (status != PROTON_OK) {
      proton_engine_view_mark_closed(view);
      proton_engine_view_request_browser_close(view, 1);
    }
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  uint64_t native_id = task->native_id;
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_view_t *pending_view =
        proton_engine_view_from_native_id(native_id);
    if (pending_view != NULL) {
      proton_engine_view_finalize_if_ready(pending_view);
    }
    free(task);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static int proton_engine_view_schedule_initial_navigation(
    proton_engine_view_t *view) {
  proton_engine_view_navigation_task_t *task = calloc(1, sizeof(*task));
  if (task == NULL) {
    return 0;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&task->task,
                                 sizeof(task->task), &task->refs);
  task->task.execute = proton_engine_view_navigation_task_execute;
  task->native_id = view->native_id;
  int posted = cef_post_task(TID_UI, &task->task);
  if (!posted) {
    free(task);
  }
  return posted;
}

void proton_engine_view_on_after_created(proton_engine_view_t *view,
                                         cef_browser_t *browser) {
  if (view == NULL || browser == NULL) {
    return;
  }
  proton_engine_window_t *window = view->window;
  cef_browser_host_t *host = browser->get_host(browser);
  view->browser_create_scheduled = 0;
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
      view->browser_view = (__bridge NSView *)host->get_window_handle(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
  }
  if (window->content_view != nil && view->browser_view != nil) {
    if (view->browser_view.superview == nil) {
      [window->content_view addSubview:view->browser_view];
    }
    proton_engine_view_apply_frame(view);
    proton_engine_window_layout_views(window);
  }

  if (view->closed || view->finalize_after_browser_close) {
    view->initial_navigation_pending = 0;
    proton_engine_view_request_browser_close(view, 1);
    proton_engine_view_finalize_if_ready(view);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  if (!proton_engine_view_schedule_initial_navigation(view)) {
    view->initial_navigation_pending = 0;
    proton_engine_view_mark_closed(view);
    proton_engine_view_request_browser_close(view, 1);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_view_on_before_close(proton_engine_view_t *view,
                                        cef_browser_t *browser) {
  if (view == NULL) {
    return;
  }
  proton_browser_lifecycle_on_before_close(view->browser_lifecycle, browser);
  proton_engine_view_mark_closed(view);
  proton_view_events_closed(view->events);
  if (view->browser_view != nil) {
    [view->browser_view removeFromSuperview];
    view->browser_view = nil;
  }
  // A page-initiated close (JS window.close) reaches here without a prior
  // engine destroy; let the cleanup state machine finish so the struct can be
  // reclaimed with its owning window.
  view->finalize_after_browser_close = 1;
  proton_engine_view_finalize_if_ready(view);
}

static proton_engine_client_t *proton_engine_view_client_create(
    proton_browser_lifecycle_t *browser_lifecycle) {
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->client.base.release = proton_engine_client_release;
  client->browser_lifecycle = browser_lifecycle;
  // Views wire the life span, load, display, and render handlers: life span
  // drives the close state machine, load/display feed the view event stream,
  // and the render handler gives headless (OSR) views a viewport. Find results
  // are view-scoped. Navigation policy, bridge, downloads, and
  // permissions stay window-scoped for now,
  // and CEF defaults (cancel popups, no bridge bootstrap) apply to view
  // browsers.
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_display_handler = proton_engine_client_get_display_handler;
  proton_engine_view_t *view =
      (proton_engine_view_t *)proton_browser_lifecycle_owner(browser_lifecycle);
  cef_client_t *window_client = view != NULL && view->window != NULL
                                    ? proton_browser_lifecycle_client(
                                          view->window->browser_lifecycle)
                                    : NULL;
  client->client.get_find_handler = window_client != NULL
                                        ? window_client->get_find_handler
                                        : NULL;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
  return client;
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
  if (!proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_view_config_t config = *input_config;

  proton_engine_view_t *view =
      (proton_engine_view_t *)calloc(1, sizeof(*view));
  if (view == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  view->window = window;
  view->native_id = proton_engine_allocate_view_native_id();
  view->x = config.x;
  view->y = config.y;
  view->width = config.width;
  view->height = config.height;
  view->z_order = config.z_order;
  view->zoom_percent = 100;
  view->audio_muted = 0;
  view->visible = config.visible;
  view->browser_lifecycle = proton_browser_lifecycle_create(
      window->runtime->browsers, PROTON_BROWSER_ROLE_VIEW, view, NULL);
  if (view->browser_lifecycle == NULL) {
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser lifecycle");
    return PROTON_ERR_ENGINE;
  }
  proton_engine_client_t *client = proton_engine_view_client_create(
      view->browser_lifecycle);
  if (client == NULL) {
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_lifecycle_set_client(view->browser_lifecycle,
                                      &client->client);
  view->initial_url = proton_engine_strdup(
      config.initial_url[0] != '\0' ? config.initial_url : "about:blank");
  if (view->initial_url == NULL) {
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to copy initial browser url");
    return PROTON_ERR_ENGINE;
  }
  // Views own a browser session with a fixed, non-interactive policy so the
  // usual browser commands (back/forward/reload/stop/devtools) work per view;
  // ASK flows are never used here.
  proton_browser_policy_t view_policy = {PROTON_BROWSER_POLICY_ALLOW,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         PROTON_BROWSER_POLICY_DENY,
                                         1};
  view->browser_session = proton_browser_session_create(
      &view_policy, proton_engine_browser_signal, NULL);
  view->events = proton_view_events_create();
  if (view->browser_session == NULL || view->events == NULL) {
    proton_browser_session_destroy(view->browser_session);
    proton_view_events_destroy(view->events);
    free(view->initial_url);
    proton_browser_lifecycle_creation_failed(view->browser_lifecycle);
    proton_browser_lifecycle_clear_owner(view->browser_lifecycle);
    free(view);
    proton_engine_set_message(error, error_len,
                              "failed to allocate view state");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_session_bind_lifecycle(view->browser_session,
                                        view->browser_lifecycle);
  proton_view_events_bind(view->events, config.public_view,
                          config.public_window);
  view->has_background_color = config.has_background_color;
  view->background_color = config.background_color;
  view->browser_create_pending = 1;
  proton_engine_view_list_add(window, view);
  proton_engine_view_schedule_browser_create(view);
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
  if (proton_engine_view_browser(view) != NULL) {
    if (!proton_engine_view_request_browser_close(view, 1)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_view_mark_closed(view);
    proton_engine_view_defer_finalize(view);
    proton_engine_view_finalize_if_ready(view);
    return PROTON_OK;
  }
  proton_engine_view_mark_closed(view);
  proton_engine_view_defer_finalize(view);
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
    if (proton_engine_view_browser(view) != NULL) {
      cef_browser_host_t *host = proton_engine_view_browser(view)->get_host(proton_engine_view_browser(view));
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    proton_engine_view_apply_frame(view);
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
    if (proton_engine_view_browser(view) != NULL) {
      cef_browser_host_t *host = proton_engine_view_browser(view)->get_host(proton_engine_view_browser(view));
      if (host != NULL && host->was_hidden != NULL) {
        host->was_hidden(host, view->visible ? 0 : 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else if (view->browser_view != nil) {
    [view->browser_view setHidden:view->visible ? NO : YES];
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

int32_t proton_engine_view_set_zoom_percent(proton_engine_view_t *view,
                                            int32_t zoom_percent,
                                            char *error,
                                            size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (proton_engine_view_browser(view) != NULL) {
    int32_t status = proton_browser_set_zoom_percent(
        proton_engine_view_browser(view), zoom_percent, error, error_len);
    if (status != PROTON_OK) {
      return status;
    }
  }
  view->zoom_percent = zoom_percent;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_view_set_audio_muted(proton_engine_view_t *view,
                                           int32_t muted, char *error,
                                           size_t error_len) {
  if (view == NULL || view->closed) {
    proton_engine_set_message(error, error_len, "view is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (proton_engine_view_browser(view) != NULL) {
    int32_t status = proton_browser_set_audio_muted(
        proton_engine_view_browser(view), muted, error, error_len);
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
  if (proton_engine_view_browser(view) != NULL) {
    int32_t status = proton_browser_is_audio_muted(
        proton_engine_view_browser(view), out_muted, error, error_len);
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
  if ((proton_engine_view_browser(view) == NULL &&
       (view->browser_create_pending || view->browser_create_scheduled)) ||
      view->initial_navigation_pending) {
    char *url_copy =
        proton_engine_strdup(url != NULL && url[0] != '\0' ? url : "about:blank");
    if (url_copy == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
    free(view->initial_url);
    view->initial_url = url_copy;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = proton_engine_view_browser(view)->get_main_frame(proton_engine_view_browser(view));
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

  if (view == NULL || view->closed || proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = proton_engine_view_browser(view)->get_main_frame(proton_engine_view_browser(view));
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
      proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_session_command_json(view->browser_session,
                                             proton_engine_view_browser(view), command_json,
                                             error, error_len);
}

int32_t proton_engine_view_get_browser_focus_state(
    proton_engine_view_t *view, int32_t *out_focused,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser_session == NULL ||
      proton_engine_view_browser(view) == NULL) {
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
        proton_engine_view_browser(view), out_focused, error, error_len);
  }
  *out_focused = proton_engine_browser_view_is_focused(view->browser_view);
  return PROTON_OK;
}

int32_t proton_engine_view_get_devtools_state(
    proton_engine_view_t *view, int32_t *out_opened,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_is_devtools_opened(
      proton_engine_view_browser(view), out_opened, error, error_len);
}

int32_t proton_engine_view_get_navigation_state(
    proton_engine_view_t *view, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len) {
  if (view == NULL || view->closed || proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_navigation_state(
      proton_engine_view_browser(view), out_can_go_back, out_can_go_forward, error, error_len);
}

int32_t proton_engine_view_find_in_page(
    proton_engine_view_t *view, const char *text, int32_t forward,
    int32_t match_case, int32_t find_next, int32_t *out_request_id,
    char *error, size_t error_len) {
  if (view == NULL || view->closed || view->browser_session == NULL ||
      proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_find_in_page(
      view->browser_session, proton_engine_view_browser(view), text, forward, match_case,
      find_next, out_request_id, error, error_len);
}

int32_t proton_engine_view_stop_find_in_page(
    proton_engine_view_t *view, int32_t clear_selection, char *error,
    size_t error_len) {
  if (view == NULL || view->closed || proton_engine_view_browser(view) == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  return proton_browser_stop_find_in_page(
      proton_engine_view_browser(view), clear_selection, error, error_len);
}

#endif
