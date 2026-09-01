#if defined(__APPLE__)

#include "mac_internal.h"

#include "../ffi/src/proton_config.h"
#include "../ffi/src/proton_event.h"
#include "../ffi/src/engine/cef_common/bridge_lifecycle.h"
#include "../ffi/src/engine/cef_common/bridge_client.h"
#include "../ffi/src/engine/cef_common/browser_session.h"
#include "../ffi/src/engine/cef_common/bridge_renderer.h"
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
#include "mac_dialog.h"
#include "mac_launch_input.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_find_handler_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/capi/cef_v8_capi.h"
#include "include/internal/cef_string.h"

#import <Cocoa/Cocoa.h>

#include <math.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  cef_find_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_find_handler_t;

static proton_engine_app_t g_app;
static proton_engine_browser_process_handler_t g_browser_process_handler;
static proton_engine_render_process_handler_t g_render_process_handler;
static proton_engine_v8_handler_t g_v8_handler;
static proton_engine_life_span_handler_t g_life_span_handler;
static proton_engine_load_handler_t g_load_handler;
static proton_engine_request_handler_t g_request_handler;
static proton_engine_download_handler_t g_download_handler;
static proton_engine_find_handler_t g_find_handler;
static proton_engine_permission_handler_t g_permission_handler;
static proton_engine_render_handler_t g_render_handler;
static proton_engine_display_handler_t g_display_handler;
static proton_engine_scheme_factory_t g_scheme_factory;

int proton_engine_bridge_resolve_host(cef_browser_t *browser,
                                      proton_engine_bridge_host_t *out_host) {
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window == NULL || window->runtime == NULL || out_host == NULL) {
    return 0;
  }
  memset(out_host, 0, sizeof(*out_host));
  out_host->runtime = window->runtime;
  out_host->public_window = window->public_window_id;
  out_host->bridge_config = window->bridge_config;
  out_host->max_payload_bytes = window->max_bridge_payload_bytes;
  out_host->next_request_id = &window->runtime->next_bridge_request_id;
  out_host->lifecycle = &window->bridge_lifecycle;
  return 1;
}

void proton_engine_bridge_signal(proton_engine_runtime_t *runtime) {
  (void)runtime;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_bridge_response_sent(proton_engine_runtime_t *runtime) {
  proton_engine_bridge_signal(runtime);
}

cef_app_t *proton_engine_cef_app(void) {
  return &g_app.app;
}

int proton_engine_register_scheme_factory(void) {
  return proton_engine_register_app_scheme_factory(&g_scheme_factory.factory);
}

static int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

static cef_browser_process_handler_t *CEF_CALLBACK
proton_engine_get_browser_process_handler(cef_app_t *self) {
  (void)self;
  g_browser_process_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_browser_process_handler.handler);
  return &g_browser_process_handler.handler;
}

static void proton_engine_window_load_initial_url(
    proton_engine_window_t *window) {
  if (window == NULL || window->closed || proton_engine_window_browser(window) == NULL ||
      window->initial_url == NULL || window->initial_url[0] == '\0' ||
      strcmp(window->initial_url, "about:blank") == 0) {
    return;
  }
  char error[512] = {0};
  int32_t status = proton_engine_window_load_url(
      window, window->initial_url, error, sizeof(error));
  if (status != PROTON_OK) {
    proton_engine_window_mark_closed(window);
    proton_engine_window_request_browser_close(window, 1);
  }
}

static void CEF_CALLBACK proton_engine_initial_navigation_task_execute(
    cef_task_t *base) {
  proton_engine_initial_navigation_task_t *task =
      (proton_engine_initial_navigation_task_t *)base;
  proton_engine_window_t *window =
      proton_engine_window_from_native_id(task->native_id);
  if (window == NULL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      free(task);
    });
    return;
  }
  window->initial_navigation_pending = 0;
  proton_engine_window_load_initial_url(window);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  uint64_t native_id = task->native_id;
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_window_t *pending_window =
        proton_engine_window_from_native_id(native_id);
    if (pending_window != NULL) {
      proton_engine_window_finalize_if_ready(pending_window);
    }
    free(task);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  });
}

static int proton_engine_window_schedule_initial_navigation(
    proton_engine_window_t *window) {
  proton_engine_initial_navigation_task_t *task =
      calloc(1, sizeof(*task));
  if (task == NULL) {
    return 0;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&task->task,
                                 sizeof(task->task), &task->refs);
  task->task.execute = proton_engine_initial_navigation_task_execute;
  task->native_id = window->native_id;
  int posted = cef_post_task(TID_UI, &task->task);
  if (!posted) {
    free(task);
  }
  return posted;
}

static int CEF_CALLBACK proton_engine_on_before_popup(
    cef_life_span_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int popup_id,
    const cef_string_t *target_url,
    const cef_string_t *target_frame_name,
    cef_window_open_disposition_t target_disposition,
    int user_gesture,
    const cef_popup_features_t *popupFeatures,
    cef_window_info_t *windowInfo,
    cef_client_t **client,
    cef_browser_settings_t *settings,
    struct _cef_dictionary_value_t **extra_info,
    int *no_javascript_access) {
  (void)self;
  (void)frame;
  (void)popup_id;
  (void)target_frame_name;
  (void)popupFeatures;
  (void)windowInfo;
  (void)client;
  (void)settings;
  (void)extra_info;
  (void)no_javascript_access;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_popup(
      window != NULL ? window->browser_session : NULL, target_url,
      target_disposition, user_gesture);
}

static proton_engine_client_t *proton_engine_client_from_browser(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_engine_client_t *client =
      cef_client != NULL ? proton_engine_client_from_base(cef_client) : NULL;
  if (cef_client != NULL) {
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return client;
}

static void CEF_CALLBACK proton_engine_on_after_created(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  if (browser == NULL) {
    return;
  }
  proton_engine_client_t *client = proton_engine_client_from_browser(browser);
  proton_browser_lifecycle_t *lifecycle =
      client != NULL ? client->browser_lifecycle : NULL;
  if (lifecycle == NULL) {
    cef_browser_host_t *host = browser->get_host(browser);
    if (host != NULL) {
      host->close_browser(host, 1);
      host->base.release((cef_base_ref_counted_t *)host);
    }
    return;
  }
  proton_browser_lifecycle_on_after_created(lifecycle, browser);
  proton_browser_role_t role = proton_browser_lifecycle_role(lifecycle);
  if (role == PROTON_BROWSER_ROLE_DEVTOOLS) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  if (role == PROTON_BROWSER_ROLE_VIEW) {
    proton_engine_view_t *view =
        (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
    if (view != NULL) {
      proton_engine_view_on_after_created(view, browser);
    }
    return;
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
  if (window == NULL) {
    proton_browser_lifecycle_request_close(lifecycle, 1);
    return;
  }

  cef_browser_host_t *host = browser->get_host(browser);
  proton_engine_window_lock();
  proton_engine_window_unlock();
  window->browser_create_scheduled = 0;
  if (host == NULL) {
    proton_browser_lifecycle_request_close(lifecycle, 1);
  } else {
    if (window->headless) {
      if (window->headless_hidden && host->was_hidden != NULL) {
        host->was_hidden(host, 1);
      }
      if (window->headless_focused && host->set_focus != NULL) {
        host->set_focus(host, 1);
      }
    } else {
      window->browser_view = (__bridge NSView *)host->get_window_handle(host);
    }
    host->base.release((cef_base_ref_counted_t *)host);
  }
  if (window->content_view != nil && window->browser_view != nil &&
      window->browser_view.superview == nil) {
    [window->content_view addSubview:window->browser_view];
  }
  if (window->content_view != nil && window->browser_view != nil) {
    [window->browser_view setFrame:window->content_view.bounds];
    [window->browser_view setAutoresizingMask:NSViewWidthSizable |
                                          NSViewHeightSizable];
  }
  // The main browser view must stay below any web contents views, including
  // views created before this browser finished loading.
  proton_engine_window_layout_views(window);

  if (window->closed || window->finalize_after_browser_close) {
    window->initial_navigation_pending = 0;
    proton_engine_window_request_browser_close(window, 1);
    proton_engine_window_finalize_if_ready(window);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  if (!proton_engine_window_schedule_initial_navigation(window)) {
    window->initial_navigation_pending = 0;
    proton_engine_window_mark_closed(window);
    proton_engine_window_request_browser_close(window, 1);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void CEF_CALLBACK proton_engine_on_before_close(
    cef_life_span_handler_t *self,
    cef_browser_t *browser) {
  (void)self;
  proton_engine_client_t *client = proton_engine_client_from_browser(browser);
  proton_browser_lifecycle_t *lifecycle =
      client != NULL ? client->browser_lifecycle : NULL;
  if (lifecycle == NULL) {
    return;
  }
  proton_browser_role_t role = proton_browser_lifecycle_role(lifecycle);
  if (role == PROTON_BROWSER_ROLE_VIEW) {
    proton_engine_view_t *view =
        (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
    if (view == NULL) {
      proton_browser_lifecycle_on_before_close(lifecycle, browser);
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
      return;
    }
    proton_engine_view_on_before_close(view, browser);
    return;
  }
  if (role == PROTON_BROWSER_ROLE_DEVTOOLS) {
    proton_browser_lifecycle_on_before_close(lifecycle, browser);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return;
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
  if (window != NULL) {
    proton_engine_bridge_pending_remove_browser(
        window->runtime, proton_browser_lifecycle_browser_id(lifecycle));
  }
  proton_browser_lifecycle_on_before_close(lifecycle, browser);
  if (window != NULL) {
    proton_engine_window_close_views(window);
    proton_engine_window_mark_closed(window);
    if (window->window != nil && !window->appkit_closing) {
      [window->window close];
    }
    proton_engine_window_finalize_if_ready(window);
  }
}

static int CEF_CALLBACK proton_engine_do_close(cef_life_span_handler_t *self,
                                               cef_browser_t *browser) {
  (void)self;
  proton_engine_client_t *client = proton_engine_client_from_browser(browser);
  proton_browser_lifecycle_t *lifecycle =
      client != NULL ? client->browser_lifecycle : NULL;
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) ==
          PROTON_BROWSER_ROLE_DEVTOOLS) {
    return 0;
  }
  proton_engine_view_t *view =
      proton_browser_lifecycle_role(lifecycle) == PROTON_BROWSER_ROLE_VIEW
          ? (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle)
          : NULL;
  if (view != NULL) {
    if (view->browser_view != nil) {
      // A view browser owns no top-level window, so the default behavior for
      // windowed rendering (performClose: on the browser's top-level parent
      // window) would target the owning NSWindow and be cancelled by its
      // delegate, leaving the browser in a partially closed state. Take over
      // the close: detach the browser host view so its dealloc completes the
      // teardown via WindowDestroyed().
      [view->browser_view removeFromSuperview];
      view->browser_view = nil;
      return 1;
    }
    if (view->window != NULL && view->window->headless) {
      // Windowless (headless) rendering has no host view; returning false lets
      // CEF destroy the browser object immediately.
      return 0;
    }
    // Defensive: a windowed view with no host view pointer — either it was
    // never captured (the browser host or its window handle was unavailable
    // at creation), or windowWillClose already cleared it while the NSWindow
    // teardown is still pending. CEF only asks do_close before
    // WindowDestroyed, so no dealloc handshake can complete this teardown
    // from here — but returning false is strictly worse: CEF's default would
    // performClose: the owning NSWindow, which the window delegate cancels.
    // Cancel the default and log the wedge; in the windowWillClose interleave
    // the pending teardown still completes via WindowDestroyed.
    return 1;
  }
  proton_engine_window_t *window =
      (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
  if (window != NULL) {
    window->cef_allows_appkit_close = 1;
  }
  return 0;
}

cef_life_span_handler_t *CEF_CALLBACK
proton_engine_client_get_life_span_handler(cef_client_t *self) {
  (void)self;
  g_life_span_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_life_span_handler.handler);
  return &g_life_span_handler.handler;
}

cef_load_handler_t *CEF_CALLBACK
proton_engine_client_get_load_handler(cef_client_t *self) {
  (void)self;
  g_load_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_load_handler.handler);
  return &g_load_handler.handler;
}

static cef_request_handler_t *CEF_CALLBACK
proton_engine_client_get_request_handler(cef_client_t *self) {
  (void)self;
  g_request_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_request_handler.handler);
  return &g_request_handler.handler;
}

static cef_download_handler_t *CEF_CALLBACK
proton_engine_client_get_download_handler(cef_client_t *self) {
  (void)self;
  g_download_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_download_handler.handler);
  return &g_download_handler.handler;
}

static cef_find_handler_t *CEF_CALLBACK
proton_engine_client_get_find_handler(cef_client_t *self) {
  (void)self;
  g_find_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_find_handler.handler);
  return &g_find_handler.handler;
}

static cef_permission_handler_t *CEF_CALLBACK
proton_engine_client_get_permission_handler(cef_client_t *self) {
  (void)self;
  g_permission_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_permission_handler.handler);
  return &g_permission_handler.handler;
}

cef_render_handler_t *CEF_CALLBACK
proton_engine_client_get_render_handler(cef_client_t *self) {
  proton_engine_client_t *client = proton_engine_client_from_base(self);
  if (client == NULL) {
    return NULL;
  }
  proton_browser_lifecycle_t *lifecycle = client->browser_lifecycle;
  if (lifecycle == NULL ||
      proton_browser_lifecycle_role(lifecycle) == PROTON_BROWSER_ROLE_DEVTOOLS) {
    return NULL;
  }
  if (proton_browser_lifecycle_role(lifecycle) == PROTON_BROWSER_ROLE_VIEW) {
    proton_engine_view_t *view =
        (proton_engine_view_t *)proton_browser_lifecycle_owner(lifecycle);
    if (view == NULL || view->window == NULL || !view->window->headless) {
      return NULL;
    }
  } else {
    proton_engine_window_t *window =
        (proton_engine_window_t *)proton_browser_lifecycle_owner(lifecycle);
    if (window == NULL || !window->headless) {
      return NULL;
    }
  }
  g_render_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_render_handler.handler);
  return &g_render_handler.handler;
}

static void CEF_CALLBACK proton_engine_on_title_change(
    cef_display_handler_t *self,
    cef_browser_t *browser,
    const cef_string_t *title) {
  (void)self;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  char *title_utf8 = proton_engine_cef_string_to_utf8(title);
  if (view != NULL) {
    proton_view_events_title_updated(view->events, title_utf8);
    free(title_utf8);
    proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
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

static cef_render_process_handler_t *CEF_CALLBACK
proton_engine_get_render_process_handler(cef_app_t *self);
static void CEF_CALLBACK proton_engine_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context);
static void CEF_CALLBACK proton_engine_on_context_released(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context);
static int CEF_CALLBACK proton_engine_renderer_on_process_message_received(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message);
static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_transition_type_t transition_type);
static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode);
static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_errorcode_t errorCode, const cef_string_t *errorText,
    const cef_string_t *failedUrl);
static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string);
static int CEF_CALLBACK proton_engine_on_before_browse(
    cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect);
static int CEF_CALLBACK proton_engine_on_certificate_error(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_errorcode_t cert_error, const cef_string_t *request_url,
    cef_sslinfo_t *ssl_info, cef_callback_t *callback);
static int CEF_CALLBACK proton_engine_can_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    const cef_string_t *url, const cef_string_t *request_method);
static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback);
static void CEF_CALLBACK proton_engine_on_download_updated(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback);
static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback);
static void CEF_CALLBACK proton_engine_on_find_result(
    cef_find_handler_t *self, cef_browser_t *browser, int identifier,
    int count, const cef_rect_t *selection_rect, int active_match_ordinal,
    int final_update);

void proton_engine_init_handlers(void) {
  static int initialized = 0;
  if (initialized) {
    return;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&g_app.app.base,
                                 sizeof(g_app.app), &g_app.refs);
  g_app.app.on_before_command_line_processing =
      proton_engine_on_before_command_line_processing;
  g_app.app.on_register_custom_schemes =
      proton_engine_on_register_custom_schemes;
  g_app.app.get_browser_process_handler =
      proton_engine_get_browser_process_handler;
  g_app.app.get_render_process_handler =
      proton_engine_get_render_process_handler;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_browser_process_handler.handler.base,
      sizeof(g_browser_process_handler.handler), &g_browser_process_handler.refs);
  g_browser_process_handler.handler.on_schedule_message_pump_work =
      proton_engine_on_schedule_message_pump_work;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_render_process_handler.handler.base,
      sizeof(g_render_process_handler.handler), &g_render_process_handler.refs);
  g_render_process_handler.handler.on_context_created =
      proton_engine_on_context_created;
  g_render_process_handler.handler.on_context_released =
      proton_engine_on_context_released;
  g_render_process_handler.handler.on_browser_created =
      proton_engine_bridge_renderer_on_browser_created;
  g_render_process_handler.handler.on_browser_destroyed =
      proton_engine_bridge_renderer_on_browser_destroyed;
  g_render_process_handler.handler.on_process_message_received =
      proton_engine_renderer_on_process_message_received;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_v8_handler.handler.base,
      sizeof(g_v8_handler.handler), &g_v8_handler.refs);
  g_v8_handler.handler.execute = proton_engine_bridge_v8_execute;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_life_span_handler.handler.base,
      sizeof(g_life_span_handler.handler), &g_life_span_handler.refs);
  g_life_span_handler.handler.on_before_popup = proton_engine_on_before_popup;
  g_life_span_handler.handler.on_after_created = proton_engine_on_after_created;
  g_life_span_handler.handler.do_close = proton_engine_do_close;
  g_life_span_handler.handler.on_before_close = proton_engine_on_before_close;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_load_handler.handler.base,
      sizeof(g_load_handler.handler), &g_load_handler.refs);
  g_load_handler.handler.on_load_start = proton_engine_on_load_start;
  g_load_handler.handler.on_load_end = proton_engine_on_load_end;
  g_load_handler.handler.on_load_error = proton_engine_on_load_error;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_request_handler.handler.base,
      sizeof(g_request_handler.handler), &g_request_handler.refs);
  g_request_handler.handler.on_before_browse =
      proton_engine_on_before_browse;
  g_request_handler.handler.on_certificate_error =
      proton_engine_on_certificate_error;
  g_request_handler.handler.on_render_process_terminated =
      proton_engine_on_render_process_terminated;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_download_handler.handler.base,
      sizeof(g_download_handler.handler), &g_download_handler.refs);
  g_download_handler.handler.can_download = proton_engine_can_download;
  g_download_handler.handler.on_before_download =
      proton_engine_on_before_download;
  g_download_handler.handler.on_download_updated =
      proton_engine_on_download_updated;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_find_handler.handler.base,
      sizeof(g_find_handler.handler), &g_find_handler.refs);
  g_find_handler.handler.on_find_result = proton_engine_on_find_result;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_permission_handler.handler.base,
      sizeof(g_permission_handler.handler), &g_permission_handler.refs);
  g_permission_handler.handler.on_request_media_access_permission =
      proton_engine_on_media_permission;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_render_handler.handler.base,
      sizeof(g_render_handler.handler), &g_render_handler.refs);
  g_render_handler.handler.get_view_rect = proton_engine_osr_get_view_rect;
  g_render_handler.handler.get_screen_info = proton_engine_osr_get_screen_info;
  g_render_handler.handler.on_popup_show = proton_engine_osr_on_popup_show;
  g_render_handler.handler.on_popup_size = proton_engine_osr_on_popup_size;
  g_render_handler.handler.on_paint = proton_engine_osr_on_paint;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_display_handler.handler.base,
      sizeof(g_display_handler.handler), &g_display_handler.refs);
  g_display_handler.handler.on_title_change = proton_engine_on_title_change;

  proton_engine_init_ref_counted(
      (cef_base_ref_counted_t *)&g_scheme_factory.factory.base,
      sizeof(g_scheme_factory.factory), &g_scheme_factory.refs);
  g_scheme_factory.factory.create = proton_engine_scheme_create;
  initialized = 1;
}

static void CEF_CALLBACK proton_engine_on_context_created(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  (void)self;
  proton_engine_bridge_renderer_on_context_created(
      browser, frame, context, &g_v8_handler.handler);
}

static void CEF_CALLBACK proton_engine_on_context_released(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_v8_context_t *context) {
  (void)self;
  proton_engine_bridge_renderer_on_context_released(browser, frame, context);
}

static int CEF_CALLBACK proton_engine_renderer_on_process_message_received(
    cef_render_process_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  (void)self;
  return proton_engine_bridge_renderer_on_process_message_received(
      browser, frame, source_process, message);
}

static cef_render_process_handler_t *CEF_CALLBACK
proton_engine_get_render_process_handler(cef_app_t *self) {
  (void)self;
  g_render_process_handler.handler.base.add_ref(
      (cef_base_ref_counted_t *)&g_render_process_handler.handler);
  return &g_render_process_handler.handler;
}

static void CEF_CALLBACK proton_engine_on_load_start(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_transition_type_t transition_type) {
  (void)self;
  (void)transition_type;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame) && url != NULL &&
        strcmp(url, "about:blank") != 0) {
      proton_view_events_navigated(view->events, url);
      proton_view_events_loading_changed(view->events, 1);
      proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
  if (frame != NULL && frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") != 0) {
    proton_engine_window_t *window = proton_engine_window_from_browser(browser);
    proton_browser_session_navigated(
        window != NULL ? window->browser_session : NULL, url);
    proton_browser_session_loading_changed(
        window != NULL ? window->browser_session : NULL, url, 1);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_end(
    cef_load_handler_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    int httpStatusCode) {
  (void)self;
  (void)httpStatusCode;
  char *url = frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                            : NULL;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    if (frame != NULL && frame->is_main(frame)) {
      proton_view_events_loading_changed(view->events, 0);
      proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    }
    free(url);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window != NULL && frame != NULL && frame->is_main(frame)) {
    proton_browser_session_loading_changed(window->browser_session, url, 0);
  }
  if (window != NULL && window->bridge_config != NULL && frame != NULL &&
      frame->is_main(frame) && url != NULL &&
      strcmp(url, "about:blank") != 0) {
    (void)proton_engine_bridge_send_lifecycle_probe(frame);
  }
  free(url);
}

static void CEF_CALLBACK proton_engine_on_load_error(
    cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_errorcode_t errorCode, const cef_string_t *errorText,
    const cef_string_t *failedUrl) {
  (void)self;
  if (frame == NULL || !frame->is_main(frame)) {
    return;
  }
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    char *view_message = proton_engine_cef_string_to_utf8(errorText);
    char *view_url = proton_engine_cef_string_to_utf8(failedUrl);
    proton_view_events_load_failed(view->events, view_url, (int32_t)errorCode,
                                   view_message);
    free(view_message);
    free(view_url);
    proton_engine_signal_wait_source(PROTON_WAIT_EVENT);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  char *message = proton_engine_cef_string_to_utf8(errorText);
  char *url = proton_engine_cef_string_to_utf8(failedUrl);
  proton_browser_session_load_failed(
      window != NULL ? window->browser_session : NULL, url,
      (int32_t)errorCode, message);
  if (window != NULL && window->bridge_config != NULL && url != NULL) {
    proton_engine_bridge_lifecycle_report_load_failure(
        &window->bridge_lifecycle, url,
        message != NULL && message[0] != '\0' ? message
                                               : "main frame failed to load",
        errorCode == ERR_ABORTED);
  }
  free(message);
  free(url);
}

static int CEF_CALLBACK proton_engine_on_before_browse(
    cef_request_handler_t *self, cef_browser_t *browser, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_browse(
      window != NULL ? window->browser_session : NULL, frame, request,
      user_gesture, is_redirect);
}

static int CEF_CALLBACK proton_engine_on_certificate_error(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_errorcode_t cert_error, const cef_string_t *request_url,
    cef_sslinfo_t *ssl_info, cef_callback_t *callback) {
  (void)self;
  (void)ssl_info;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_certificate_error(
      window != NULL ? window->browser_session : NULL, cert_error,
      request_url, callback);
}

static int CEF_CALLBACK proton_engine_can_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    const cef_string_t *url, const cef_string_t *request_method) {
  (void)self;
  (void)url;
  (void)request_method;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_can_download(
      window != NULL ? window->browser_session : NULL);
}

static int CEF_CALLBACK proton_engine_on_before_download(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item, const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_before_download(
      window != NULL ? window->browser_session : NULL, download_item,
      suggested_name, callback);
}

static void CEF_CALLBACK proton_engine_on_download_updated(
    cef_download_handler_t *self, cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  proton_browser_session_download_updated(
      window != NULL ? window->browser_session : NULL, download_item,
      callback);
}

static void CEF_CALLBACK proton_engine_on_find_result(
    cef_find_handler_t *self, cef_browser_t *browser, int identifier,
    int count, const cef_rect_t *selection_rect, int active_match_ordinal,
    int final_update) {
  (void)self;
  int x = selection_rect != NULL ? selection_rect->x : 0;
  int y = selection_rect != NULL ? selection_rect->y : 0;
  int width = selection_rect != NULL ? selection_rect->width : 0;
  int height = selection_rect != NULL ? selection_rect->height : 0;
  proton_engine_view_t *view = proton_engine_view_from_browser(browser);
  if (view != NULL) {
    proton_view_events_find_result(
        view->events,
        proton_browser_session_find_request_id(view->browser_session,
                                               identifier),
        count, x, y, width, height, active_match_ordinal, final_update);
    return;
  }
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  proton_browser_session_find_result(
      window != NULL ? window->browser_session : NULL, identifier, count,
      x, y, width, height, active_match_ordinal, final_update);
}

static int CEF_CALLBACK proton_engine_on_media_permission(
    cef_permission_handler_t *self, cef_browser_t *browser,
    cef_frame_t *frame, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback) {
  (void)self;
  (void)frame;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  return proton_browser_session_media_permission(
      window != NULL ? window->browser_session : NULL, requesting_origin,
      requested_permissions, callback);
}

static void CEF_CALLBACK proton_engine_on_render_process_terminated(
    cef_request_handler_t *self, cef_browser_t *browser,
    cef_termination_status_t status, int error_code,
    const cef_string_t *error_string) {
  (void)self;
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (window == NULL || window->bridge_config == NULL || window->closing) {
    return;
  }
  cef_frame_t *frame = browser != NULL ? browser->get_main_frame(browser) : NULL;
  char *url =
      frame != NULL ? proton_engine_userfree_to_utf8(frame->get_url(frame))
                    : NULL;
  char *detail = proton_engine_cef_string_to_utf8(error_string);
  if (url != NULL &&
      !(window->bridge_lifecycle.outcome != NULL &&
        strcmp(window->bridge_lifecycle.outcome, "ineligible") == 0 &&
        window->bridge_lifecycle.url != NULL &&
        strcmp(window->bridge_lifecycle.url, url) == 0)) {
    char message[1024];
    snprintf(message, sizeof(message),
             "renderer process terminated (status=%d, error=%d)%s%s",
             (int)status, error_code,
             detail != NULL && detail[0] != '\0' ? ": " : "",
             detail != NULL ? detail : "");
    proton_engine_bridge_lifecycle_report_browser_failure(
        &window->bridge_lifecycle, url, "renderer_process_terminated", message,
        0);
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
  free(detail);
  free(url);
  if (frame != NULL) {
    frame->base.release((cef_base_ref_counted_t *)frame);
  }
}

int CEF_CALLBACK proton_engine_client_release(
    cef_base_ref_counted_t *base) {
  proton_engine_ref_counted_t *refs =
      (proton_engine_ref_counted_t *)((char *)base + base->size);
  int value =
      atomic_fetch_sub_explicit(&refs->refs, 1, memory_order_acq_rel) - 1;
  if (value <= 0) {
    free(base);
    return 1;
  }
  return 0;
}

proton_engine_client_t *proton_engine_client_create(
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
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  client->client.get_load_handler = proton_engine_client_get_load_handler;
  client->client.get_request_handler =
      proton_engine_client_get_request_handler;
  client->client.get_download_handler =
      proton_engine_client_get_download_handler;
  client->client.get_find_handler = proton_engine_client_get_find_handler;
  client->client.get_permission_handler =
      proton_engine_client_get_permission_handler;
  client->client.get_render_handler = proton_engine_client_get_render_handler;
  client->client.on_process_message_received =
      proton_engine_bridge_client_on_process_message_received;
  return client;
}

cef_client_t *proton_engine_browser_client_factory(
    void *context, proton_browser_lifecycle_t *browser_lifecycle) {
  (void)context;
  proton_engine_client_t *client =
      (proton_engine_client_t *)calloc(1, sizeof(*client));
  if (client == NULL) {
    return NULL;
  }
  proton_engine_init_ref_counted((cef_base_ref_counted_t *)&client->client.base,
                                 sizeof(client->client), &client->refs);
  client->client.base.release = proton_engine_client_release;
  client->browser_lifecycle = browser_lifecycle;
  client->client.get_life_span_handler =
      proton_engine_client_get_life_span_handler;
  return &client->client;
}





#endif
