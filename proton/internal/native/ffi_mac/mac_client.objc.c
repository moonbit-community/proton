#if defined(__APPLE__)

#include "mac_internal.h"

#include "../ffi/src/proton_config.h"
#include "../ffi/src/proton_event.h"
#include "../ffi/src/engine/cef_common/bridge_lifecycle.h"
#include "../ffi/src/engine/cef_common/bridge_request.h"
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

typedef struct proton_engine_bridge_pending {
  int64_t request_id;
  int browser_id;
  int renderer_pending_id;
  char *page_instance;
  cef_frame_t *frame;
  struct proton_engine_bridge_pending *next;
} proton_engine_bridge_pending_t;

typedef struct {
  cef_find_handler_t handler;
  proton_engine_ref_counted_t refs;
} proton_engine_find_handler_t;

static proton_engine_bridge_pending_t *g_bridge_pending = NULL;
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

static int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id,
    int64_t public_window, const char *op, const char *payload,
    const char *page_instance, const char *source_origin);
static int proton_engine_bridge_pending_add(int64_t request_id,
                                            int browser_id,
                                            int renderer_pending_id,
                                            const char *page_instance,
                                            cef_frame_t *frame);
static int proton_engine_bridge_pending_cancel(
    proton_engine_runtime_t *runtime,
    int browser_id,
    int renderer_pending_id,
    const char *page_instance);
static void proton_engine_bridge_pending_remove_context(
    proton_engine_runtime_t *runtime,
    int browser_id,
    const char *page_instance);
static proton_engine_bridge_pending_t *proton_engine_bridge_pending_take(
    int64_t request_id);
static void proton_engine_bridge_pending_free(
    proton_engine_bridge_pending_t *pending);

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
static int CEF_CALLBACK proton_engine_v8_execute(
    cef_v8_handler_t *self,
    const cef_string_t *name,
    cef_v8_value_t *object,
    size_t argumentsCount,
    cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval,
    cef_string_t *exception);
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
  g_v8_handler.handler.execute = proton_engine_v8_execute;

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

int proton_engine_send_bridge_response_to_frame(
    cef_frame_t *frame,
    int renderer_pending_id,
    int ok,
    const char *payload_json,
    const char *error_text) {
  if (frame == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name, PROTON_ENGINE_BRIDGE_RESPONSE_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 4);
  args->set_int(args, 0, renderer_pending_id);
  args->set_bool(args, 1, ok ? 1 : 0);
  cef_string_t payload = {0};
  cef_string_t error = {0};
  proton_engine_set_string(&payload, payload_json != NULL ? payload_json : "null");
  proton_engine_set_string(&error, error_text != NULL ? error_text : "");
  args->set_string(args, 2, &payload);
  args->set_string(args, 3, &error);
  cef_string_clear(&payload);
  cef_string_clear(&error);
  frame->send_process_message(frame, PID_RENDERER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

static void proton_engine_reject_renderer_request(cef_frame_t *frame,
                                                  int renderer_pending_id,
                                                  const char *message) {
  (void)proton_engine_send_bridge_response_to_frame(
      frame, renderer_pending_id, 0, "null",
      message != NULL ? message : "bridge request rejected");
}

static char *proton_engine_v8_value_to_utf8(cef_v8_value_t *value) {
  if (value == NULL || !value->is_string(value)) {
    return NULL;
  }
  return proton_engine_userfree_to_utf8(value->get_string_value(value));
}

static int proton_engine_send_bridge_request_to_browser(
    cef_frame_t *frame,
    const char *action,
    int pending_id,
    const char *op,
    const char *payload_json,
    const char *page_instance) {
  if (frame == NULL || action == NULL || op == NULL || payload_json == NULL ||
      page_instance == NULL) {
    return 0;
  }
  cef_string_t message_name = {0};
  proton_engine_set_string(&message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE);
  cef_process_message_t *message = cef_process_message_create(&message_name);
  cef_string_clear(&message_name);
  if (message == NULL) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL) {
    message->base.release((cef_base_ref_counted_t *)message);
    return 0;
  }
  args->set_size(args, 5);
  cef_string_t action_value = {0};
  cef_string_t op_value = {0};
  cef_string_t payload_value = {0};
  cef_string_t page_instance_value = {0};
  proton_engine_set_string(&action_value, action);
  proton_engine_set_string(&op_value, op);
  proton_engine_set_string(&payload_value, payload_json);
  proton_engine_set_string(&page_instance_value, page_instance);
  args->set_string(args, 0, &action_value);
  args->set_int(args, 1, pending_id);
  args->set_string(args, 2, &op_value);
  args->set_string(args, 3, &payload_value);
  args->set_string(args, 4, &page_instance_value);
  cef_string_clear(&action_value);
  cef_string_clear(&op_value);
  cef_string_clear(&payload_value);
  cef_string_clear(&page_instance_value);
  frame->send_process_message(frame, PID_BROWSER, message);
  args->base.release((cef_base_ref_counted_t *)args);
  return 1;
}

static int CEF_CALLBACK proton_engine_v8_execute(
    cef_v8_handler_t *self,
    const cef_string_t *name,
    cef_v8_value_t *object,
    size_t argumentsCount,
    cef_v8_value_t *const *arguments,
    cef_v8_value_t **retval,
    cef_string_t *exception) {
  (void)self;
  (void)object;
  char *function_name = proton_engine_cef_string_to_utf8(name);
  int handled = function_name != NULL &&
                strcmp(function_name, PROTON_ENGINE_BRIDGE_NATIVE_FUNCTION) == 0;
  free(function_name);
  if (!handled) {
    return 0;
  }
  if (retval != NULL) {
    *retval = NULL;
  }
  if (argumentsCount < 5 || arguments[0] == NULL ||
      !arguments[0]->is_string(arguments[0]) || arguments[1] == NULL ||
      !arguments[1]->is_int(arguments[1])) {
    proton_engine_set_string(exception,
                             "invokeOp requires action, pending id, name, payload and page instance");
    return 1;
  }
  char *action = proton_engine_v8_value_to_utf8(arguments[0]);
  int pending_id = arguments[1]->get_int_value(arguments[1]);
  char *op = proton_engine_v8_value_to_utf8(arguments[2]);
  char *payload_json = proton_engine_v8_value_to_utf8(arguments[3]);
  char *page_instance = proton_engine_v8_value_to_utf8(arguments[4]);
  int is_request = action != NULL && strcmp(action, "request") == 0;
  int is_cancel = action != NULL && strcmp(action, "cancel") == 0;
  if ((!is_request && !is_cancel) ||
      (is_request &&
       (!proton_engine_bridge_op_is_valid(op) ||
        !proton_engine_bridge_payload_is_valid(
            payload_json, PROTON_ENGINE_MAX_BRIDGE_BYTES))) ||
      !proton_engine_bridge_page_instance_is_valid(page_instance)) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "invalid bridge request");
    return 1;
  }
  cef_v8_context_t *context = cef_v8_context_get_current_context();
  if (context == NULL) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "no current V8 context");
    return 1;
  }
  cef_browser_t *browser = context->get_browser(context);
  cef_frame_t *frame = context->get_frame(context);
  if (browser == NULL || frame == NULL) {
    if (browser != NULL) {
      browser->base.release((cef_base_ref_counted_t *)browser);
    }
    if (frame != NULL) {
      frame->base.release((cef_base_ref_counted_t *)frame);
    }
    context->base.release((cef_base_ref_counted_t *)context);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    proton_engine_set_string(exception, "bridge requires a browser frame");
    return 1;
  }
  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  if (!proton_engine_url_is_bridge_candidate(frame_url)) {
    browser->base.release((cef_base_ref_counted_t *)browser);
    frame->base.release((cef_base_ref_counted_t *)frame);
    context->base.release((cef_base_ref_counted_t *)context);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    free(frame_url);
    proton_engine_set_string(exception,
                             "bridge is not available for this page");
    return 1;
  }
  free(frame_url);
  if (!proton_engine_send_bridge_request_to_browser(
          frame, action, pending_id, op, payload_json, page_instance)) {
    proton_engine_set_string(exception, "failed to send bridge request");
  }
  browser->base.release((cef_base_ref_counted_t *)browser);
  frame->base.release((cef_base_ref_counted_t *)frame);
  context->base.release((cef_base_ref_counted_t *)context);
  free(action);
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
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

static int CEF_CALLBACK proton_engine_client_on_process_message_received(
    cef_client_t *self,
    cef_browser_t *browser,
    cef_frame_t *frame,
    cef_process_id_t source_process,
    cef_process_message_t *message) {
  (void)self;
  if (source_process != PID_RENDERER || browser == NULL || frame == NULL ||
      message == NULL) {
    return 0;
  }
  char *message_name =
      proton_engine_userfree_to_utf8(message->get_name(message));
  int is_request =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_REQUEST_MESSAGE) == 0;
  int is_context_disposed =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_CONTEXT_DISPOSED_MESSAGE) == 0;
  int is_lifecycle =
      message_name != NULL &&
      strcmp(message_name, PROTON_ENGINE_BRIDGE_LIFECYCLE_MESSAGE) == 0;
  free(message_name);
  int browser_id = proton_engine_browser_id(browser);
  proton_engine_window_t *window = proton_engine_window_from_browser(browser);
  if (is_lifecycle) {
    cef_list_value_t *args = message->get_argument_list(message);
    if (window != NULL && frame->is_main(frame) && args != NULL &&
        args->get_size(args) >= 14) {
      cef_frame_t *main_frame = browser->get_main_frame(browser);
      char *current_url =
          main_frame != NULL
              ? proton_engine_userfree_to_utf8(main_frame->get_url(main_frame))
              : NULL;
      (void)proton_engine_bridge_lifecycle_update_from_message(
          &window->bridge_lifecycle, args, current_url);
      free(current_url);
      if (main_frame != NULL) {
        main_frame->base.release((cef_base_ref_counted_t *)main_frame);
      }
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  if (is_context_disposed) {
    cef_list_value_t *args = message->get_argument_list(message);
    char *page_instance = args != NULL && args->get_size(args) >= 1
                              ? proton_engine_userfree_to_utf8(
                                    args->get_string(args, 0))
                              : NULL;
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    proton_engine_bridge_pending_remove_context(
        window != NULL ? window->runtime : NULL, browser_id, page_instance);
    free(page_instance);
    return 1;
  }
  if (!is_request) {
    return 0;
  }
  cef_list_value_t *args = message->get_argument_list(message);
  if (args == NULL || args->get_size(args) < 5) {
    if (args != NULL) {
      args->base.release((cef_base_ref_counted_t *)args);
    }
    return 1;
  }
  char *action = proton_engine_userfree_to_utf8(args->get_string(args, 0));
  int renderer_pending_id = args->get_int(args, 1);
  char *op = proton_engine_userfree_to_utf8(args->get_string(args, 2));
  char *payload_json = proton_engine_userfree_to_utf8(args->get_string(args, 3));
  char *page_instance =
      proton_engine_userfree_to_utf8(args->get_string(args, 4));
  args->base.release((cef_base_ref_counted_t *)args);
  if (action != NULL && strcmp(action, "cancel") == 0) {
    (void)proton_engine_bridge_pending_cancel(
        window != NULL ? window->runtime : NULL, browser_id,
        renderer_pending_id, page_instance);
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  if (action == NULL || strcmp(action, "request") != 0) {
    free(action);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(action);

  char *frame_url = proton_engine_userfree_to_utf8(frame->get_url(frame));
  int64_t request_id = 0;
  char *source_origin = NULL;
  proton_engine_bridge_request_status_t build_status =
      window == NULL || window->runtime == NULL
          ? PROTON_ENGINE_BRIDGE_REQUEST_ORIGIN_DENIED
          : proton_engine_bridge_build_request(
                window->bridge_config, frame_url, op, payload_json,
                page_instance, window->max_bridge_payload_bytes,
                &window->runtime->next_bridge_request_id, &request_id,
                &source_origin);
  if (build_status != PROTON_ENGINE_BRIDGE_REQUEST_OK) {
    proton_engine_reject_renderer_request(
        frame, renderer_pending_id,
        proton_engine_bridge_request_reject_message(build_status));
    free(frame_url);
    free(op);
    free(payload_json);
    free(page_instance);
    return 1;
  }
  free(frame_url);
  if (!proton_engine_bridge_pending_add(request_id, browser_id,
                                        renderer_pending_id, page_instance,
                                        frame) ||
      !proton_engine_runtime_enqueue_bridge_request(window->runtime,
                                                   request_id,
                                                   window->public_window_id, op,
                                                   payload_json, page_instance,
                                                   source_origin)) {
    proton_engine_bridge_pending_t *pending =
        proton_engine_bridge_pending_take(request_id);
    proton_engine_bridge_pending_free(pending);
    proton_engine_reject_renderer_request(frame, renderer_pending_id,
                                          "bridge request queue is full");
  }
  free(source_origin);
  free(op);
  free(payload_json);
  free(page_instance);
  return 1;
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
      proton_engine_client_on_process_message_received;
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



static int proton_engine_runtime_enqueue_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id,
    int64_t public_window, const char *op, const char *payload,
    const char *page_instance, const char *source_origin) {
  if (runtime == NULL || request_id <= 0 || public_window <= 0 ||
      op == NULL || payload == NULL || page_instance == NULL ||
      source_origin == NULL) {
    return 0;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_BRIDGE_REQUEST);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  event->window = public_window;
  const char *items[] = {op, payload, page_instance, source_origin};
  if (!proton_event_set_items(event, items, 4) ||
      !proton_event_try_publish(event)) {
    proton_event_destroy(event);
    return 0;
  }
  return 1;
}

static int proton_engine_runtime_enqueue_bridge_cancellation(
    proton_engine_runtime_t *runtime,
    int64_t request_id) {
  if (runtime == NULL || request_id <= 0) {
    return 0;
  }
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_BRIDGE_REQUEST_CANCELLED);
  if (event == NULL) {
    return 0;
  }
  event->request_id = request_id;
  return proton_event_publish(event);
}

static size_t proton_engine_bridge_pending_count(void) {
  size_t count = 0;
  for (proton_engine_bridge_pending_t *pending = g_bridge_pending;
       pending != NULL; pending = pending->next) {
    count++;
  }
  return count;
}

static void proton_engine_bridge_pending_free(
    proton_engine_bridge_pending_t *pending) {
  if (pending == NULL) {
    return;
  }
  if (pending->frame != NULL) {
    pending->frame->base.release((cef_base_ref_counted_t *)pending->frame);
  }
  free(pending->page_instance);
  free(pending);
}

static int proton_engine_bridge_pending_add(int64_t request_id,
                                            int browser_id,
                                            int renderer_pending_id,
                                            const char *page_instance,
                                            cef_frame_t *frame) {
  if (frame == NULL || page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  if (proton_engine_bridge_pending_count() >=
      PROTON_ENGINE_MAX_BRIDGE_PENDING) {
    return 0;
  }
  proton_engine_bridge_pending_t *pending =
      (proton_engine_bridge_pending_t *)calloc(1, sizeof(*pending));
  if (pending == NULL) {
    return 0;
  }
  pending->request_id = request_id;
  pending->browser_id = browser_id;
  pending->renderer_pending_id = renderer_pending_id;
  pending->page_instance = proton_engine_strdup(page_instance);
  if (pending->page_instance == NULL) {
    free(pending);
    return 0;
  }
  frame->base.add_ref((cef_base_ref_counted_t *)frame);
  pending->frame = frame;
  pending->next = g_bridge_pending;
  g_bridge_pending = pending;
  return 1;
}

static int proton_engine_bridge_pending_cancel(
    proton_engine_runtime_t *runtime,
    int browser_id,
    int renderer_pending_id,
    const char *page_instance) {
  if (page_instance == NULL || page_instance[0] == '\0') {
    return 0;
  }
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        pending->renderer_pending_id == renderer_pending_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id);
      proton_engine_bridge_pending_free(pending);
      return 1;
    }
    cursor = &pending->next;
  }
  return 0;
}

static void proton_engine_bridge_pending_remove_context(
    proton_engine_runtime_t *runtime,
    int browser_id,
    const char *page_instance) {
  // A stale context release must not cancel requests from its replacement.
  if (page_instance == NULL || page_instance[0] == '\0') {
    return;
  }
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id &&
        strcmp(pending->page_instance, page_instance) == 0) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                              request_id);
      proton_engine_bridge_pending_free(pending);
      continue;
    }
    cursor = &pending->next;
  }
}

static proton_engine_bridge_pending_t *proton_engine_bridge_pending_take(
    int64_t request_id) {
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->request_id == request_id) {
      *cursor = pending->next;
      pending->next = NULL;
      return pending;
    }
    cursor = &pending->next;
  }
  return NULL;
}

void proton_engine_bridge_pending_remove_browser(
    proton_engine_runtime_t *runtime,
    int browser_id) {
  proton_engine_bridge_pending_t **cursor = &g_bridge_pending;
  while (*cursor != NULL) {
    proton_engine_bridge_pending_t *pending = *cursor;
    if (pending->browser_id == browser_id) {
      int64_t request_id = pending->request_id;
      *cursor = pending->next;
      (void)proton_engine_runtime_enqueue_bridge_cancellation(runtime,
                                                               request_id);
      proton_engine_bridge_pending_free(pending);
      continue;
    }
    cursor = &pending->next;
  }
}

void proton_engine_bridge_pending_clear_all(void) {
  proton_engine_bridge_pending_t *pending = g_bridge_pending;
  g_bridge_pending = NULL;
  while (pending != NULL) {
    proton_engine_bridge_pending_t *next = pending->next;
    proton_engine_bridge_pending_free(pending);
    pending = next;
  }
}

int32_t proton_engine_runtime_respond_bridge_request(
    proton_engine_runtime_t *runtime, int64_t request_id, int32_t ok,
    const char *body_json, char *error, size_t error_len) {

  (void)runtime;
  if (body_json == NULL) {
    proton_engine_set_message(error, error_len, "body_json is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_bridge_pending_t *pending =
      proton_engine_bridge_pending_take(request_id);
  if (pending == NULL) {
    proton_engine_set_message(error, error_len,
                              "bridge request is no longer pending");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }

  int sent = proton_engine_send_bridge_response_to_frame(
      pending->frame, pending->renderer_pending_id, ok,
      ok ? body_json : "null", ok ? "" : body_json);
  proton_engine_bridge_pending_free(pending);
  if (!sent) {
    proton_engine_set_message(error, error_len,
                              "failed to send bridge response to renderer");
    return PROTON_ERR_STALE_BRIDGE_RESPONSE;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

#endif
