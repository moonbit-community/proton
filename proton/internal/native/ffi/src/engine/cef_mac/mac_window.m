#if defined(__APPLE__)

#include "mac_internal.h"

#include "../../proton_config.h"
#include "../../proton_event.h"
#include "../cef_common/bridge_lifecycle.h"
#include "../cef_common/browser_session.h"
#include "../cef_common/bridge_renderer.h"
#include "../cef_common/message.h"
#include "../cef_common/scheme.h"
#include "../cef_common/strings.h"
#include "../cef_common/view_events.h"
#include "mac_dialog.h"
#include "mac_launch_input.h"
#include "mac_menu.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_frame_capi.h"
#include "include/capi/cef_task_capi.h"
#include "include/capi/cef_values_capi.h"
#include "include/internal/cef_string.h"

#import <Cocoa/Cocoa.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static proton_engine_window_t *g_windows = NULL;
static uint64_t g_next_window_native_id = 1;
static proton_engine_window_t *g_dock_progress_owner = NULL;
static NSImageView *g_dock_progress_content = nil;
static NSProgressIndicator *g_dock_progress_indicator = nil;

static void proton_engine_apply_size_constraints(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == nil) {
    return;
  }
  [window->window
      setMinSize:window->min_width > 0
                     ? NSMakeSize(window->min_width, window->min_height)
                     : NSZeroSize];
  [window->window
      setMaxSize:window->max_width > 0
                     ? NSMakeSize(window->max_width, window->max_height)
                     : NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
}

static void proton_engine_dock_progress_clear(void) {
  if (g_dock_progress_indicator != nil) {
    [g_dock_progress_indicator stopAnimation:nil];
  }
  [[NSApp dockTile] setContentView:nil];
  [g_dock_progress_indicator release];
  [g_dock_progress_content release];
  g_dock_progress_owner = NULL;
  g_dock_progress_indicator = nil;
  g_dock_progress_content = nil;
  [[NSApp dockTile] display];
}

static int proton_engine_dock_progress_prepare(char *error,
                                               size_t error_len) {
  if (g_dock_progress_content != nil &&
      g_dock_progress_indicator != nil) {
    return 1;
  }
  NSDockTile *dock_tile = [NSApp dockTile];
  if (dock_tile == nil) {
    proton_engine_set_message(error, error_len,
                              "application Dock tile is not available");
    return 0;
  }
  NSSize tile_size = dock_tile.size;
  if (tile_size.width <= 0.0 || tile_size.height <= 0.0) {
    tile_size = NSMakeSize(128.0, 128.0);
  }
  NSImageView *content = [[NSImageView alloc]
      initWithFrame:NSMakeRect(0.0, 0.0, tile_size.width, tile_size.height)];
  NSProgressIndicator *indicator = [[NSProgressIndicator alloc]
      initWithFrame:NSMakeRect(8.0, 5.0, MAX(1.0, tile_size.width - 16.0),
                               14.0)];
  if (content == nil || indicator == nil) {
    [indicator release];
    [content release];
    proton_engine_set_message(error, error_len,
                              "failed to create Dock progress indicator");
    return 0;
  }
  content.image = [NSApp applicationIconImage];
  content.imageScaling = NSImageScaleProportionallyUpOrDown;
  indicator.style = NSProgressIndicatorStyleBar;
  indicator.minValue = 0.0;
  indicator.maxValue = 1.0;
  indicator.displayedWhenStopped = YES;
  [content addSubview:indicator];
  dock_tile.contentView = content;
  g_dock_progress_content = content;
  g_dock_progress_indicator = indicator;
  return 1;
}

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len);

static int proton_engine_browser_id(cef_browser_t *browser) {
  return browser != NULL ? browser->get_identifier(browser) : 0;
}

proton_engine_client_t *proton_engine_client_from_base(
    cef_client_t *client) {
  return (proton_engine_client_t *)client;
}

static void proton_engine_window_list_add(proton_engine_window_t *window) {
  if (window == NULL || window->window_listed) {
    return;
  }
  proton_engine_window_lock();
  window->next = g_windows;
  g_windows = window;
  window->window_listed = 1;
  proton_engine_window_unlock();
}

static void proton_engine_window_list_remove(proton_engine_window_t *window) {
  proton_engine_window_lock();
  proton_engine_window_t **cursor = &g_windows;
  while (*cursor != NULL) {
    if (*cursor == window) {
      *cursor = window->next;
      window->next = NULL;
      window->window_listed = 0;
      break;
    }
    cursor = &(*cursor)->next;
  }
  proton_engine_window_unlock();
}

int proton_engine_window_has_any(void) {
  return g_windows != NULL;
}

proton_engine_window_t *proton_engine_window_from_browser(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->browser_id == browser_id) {
      return window;
    }
  }
  return NULL;
}

proton_engine_window_t *proton_engine_window_from_browser_client(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_engine_window_t *window = NULL;
  if (cef_client != NULL) {
    proton_engine_client_t *client = proton_engine_client_from_base(cef_client);
    window = client != NULL ? client->window : NULL;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return window;
}

proton_engine_window_t *proton_engine_window_from_native_id(
    uint64_t native_id) {
  if (native_id == 0) {
    return NULL;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->native_id == native_id) {
      return window;
    }
  }
  return NULL;
}

proton_engine_view_t *proton_engine_view_from_browser(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  int browser_id = browser->get_identifier(browser);
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    for (proton_engine_view_t *view = window->views; view != NULL;
         view = view->next) {
      if (view->browser_id == browser_id) {
        return view;
      }
    }
  }
  return NULL;
}

proton_engine_view_t *proton_engine_view_from_native_id(
    uint64_t native_id) {
  if (native_id == 0) {
    return NULL;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    for (proton_engine_view_t *view = window->views; view != NULL;
         view = view->next) {
      if (view->native_id == native_id) {
        return view;
      }
    }
  }
  return NULL;
}

// Resolves a view through the browser's client. Unlike the browser-id list
// scan this also works while browser creation is still running, before the
// view records its browser id.
proton_engine_view_t *proton_engine_view_from_browser_client(
    cef_browser_t *browser) {
  if (browser == NULL) {
    return NULL;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return NULL;
  }
  cef_client_t *cef_client = host->get_client(host);
  proton_engine_view_t *view = NULL;
  if (cef_client != NULL) {
    proton_engine_client_t *client = proton_engine_client_from_base(cef_client);
    view = client != NULL ? client->view : NULL;
    cef_client->base.release((cef_base_ref_counted_t *)cef_client);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  return view;
}

uint64_t proton_engine_window_native_id(proton_engine_window_t *window) {
  return window != NULL ? window->native_id : 0;
}

int proton_engine_runtime_is_headless(proton_engine_runtime_t *runtime) {
  return runtime != NULL && runtime->headless;
}

const char *proton_engine_runtime_dialog_ok_label(
    proton_engine_runtime_t *runtime) {
  return runtime != NULL ? runtime->dialog_ok_label : "";
}

const char *proton_engine_runtime_dialog_cancel_label(
    proton_engine_runtime_t *runtime) {
  return runtime != NULL ? runtime->dialog_cancel_label : "";
}

proton_engine_runtime_t *proton_engine_window_get_runtime(
    proton_engine_window_t *window) {
  return window != NULL ? window->runtime : NULL;
}

int proton_engine_window_is_headless(proton_engine_window_t *window) {
  return window != NULL && window->headless;
}

NSWindow *proton_engine_window_get_native_window(proton_engine_window_t *window) {
  return window != NULL ? window->window : nil;
}

NSWindow *proton_engine_window_retain_native_window(
    proton_engine_window_t *window) {
  NSWindow *native_window = proton_engine_window_get_native_window(window);
  return native_window != nil ? [native_window retain] : nil;
}

int proton_engine_window_is_closed_or_missing(proton_engine_window_t *window) {
  return window == NULL || window->closed ||
         (!window->headless && window->window == nil);
}

proton_engine_window_t *proton_engine_window_lookup_native_id(
    uint64_t native_id) {
  return proton_engine_window_from_native_id(native_id);
}

proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser) {
  return proton_engine_window_from_browser(browser);
}

cef_browser_t *proton_engine_window_browser(proton_engine_window_t *window) {
  return window != NULL ? window->browser : NULL;
}

proton_engine_view_t *proton_engine_window_lookup_view_browser(
    cef_browser_t *browser) {
  return proton_engine_view_from_browser(browser);
}

proton_window_id_t proton_engine_view_window_public_id(
    proton_engine_view_t *view) {
  proton_view_id_t view_id = PROTON_INVALID_HANDLE;
  proton_window_id_t window_id = PROTON_INVALID_HANDLE;
  if (view == NULL ||
      !proton_view_events_ids(view->events, &view_id, &window_id)) {
    return PROTON_INVALID_HANDLE;
  }
  return window_id;
}

proton_view_id_t proton_engine_view_public_id(proton_engine_view_t *view) {
  proton_view_id_t view_id = PROTON_INVALID_HANDLE;
  proton_window_id_t window_id = PROTON_INVALID_HANDLE;
  if (view == NULL ||
      !proton_view_events_ids(view->events, &view_id, &window_id)) {
    return PROTON_INVALID_HANDLE;
  }
  return view_id;
}

proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window) {
  return window != NULL ? window->public_window_id : PROTON_INVALID_HANDLE;
}

proton_window_id_t
proton_engine_window_public_id_for_native_window(NSWindow *native_window) {
  if (native_window == nil) {
    return PROTON_INVALID_HANDLE;
  }
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (window->window == native_window) {
      return window->public_window_id;
    }
  }
  return PROTON_INVALID_HANDLE;
}

// NULL means every window, so the host loop keeps driving browser creation for
// runtimes whose handle it does not hold.
int proton_engine_runtime_has_pending_platform_work(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if (runtime != NULL && window->runtime != runtime) {
      continue;
    }
    if (window->browser_create_pending || window->browser_create_scheduled ||
        (window->browser != NULL && window->appkit_closing && !window->closed)) {
      return 1;
    }
  }
  return 0;
}

void proton_engine_browser_release(cef_browser_t *browser) {
  if (browser != NULL) {
    browser->base.release((cef_base_ref_counted_t *)browser);
  }
}

void proton_engine_window_release_browser(proton_engine_window_t *window) {
  if (window != NULL && window->browser != NULL) {
    cef_browser_t *browser = window->browser;
    window->browser = NULL;
    proton_engine_browser_release(browser);
  }
}

int proton_engine_window_request_browser_close(
    proton_engine_window_t *window,
    int force_close) {
  if (window == NULL || window->browser == NULL) {
    return 0;
  }
  if (window->browser_close_requested && !force_close) {
    return 1;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    return 0;
  }
  window->browser_close_requested = 1;
  host->close_browser(host, force_close);
  host->base.release((cef_base_ref_counted_t *)host);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return 1;
}

void proton_engine_window_mark_closed(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  window->closed = 1;
  proton_engine_bridge_pending_remove_browser(window->runtime,
                                              window->browser_id);
  proton_engine_dialog_complete_window_closed(window->native_id);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void proton_engine_window_commit_appkit_close(
    proton_engine_window_t *window, NSWindow *native_window) {
  if (window == NULL || native_window == nil || window->window == nil) {
    return;
  }
  window->appkit_closing = 1;
  proton_engine_window_close_views(window);
  // Clear borrowed child-view pointers first so deferred close callbacks never
  // message AppKit objects released while the main browser view is detached.
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    view->browser_view = nil;
  }
  if (window->browser != NULL) {
    proton_engine_bridge_pending_remove_browser(window->runtime,
                                                window->browser_id);
  }
  NSView *browser_view = window->browser_view;
  window->window = nil;
  window->content_view = nil;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);

  // A windowed CEF browser completes close only after CefBrowserHostView is
  // destroyed. Detach and release the host view explicitly so its dealloc can
  // deliver WindowDestroyed; replacing the parent content view alone leaves
  // the browser partially closed.
  if (browser_view != nil) {
    [browser_view removeFromSuperview];
    [browser_view release];
  }
  window->browser_view = nil;
  [native_window setDelegate:nil];
  NSView *empty_content_view = [[NSView alloc] initWithFrame:NSZeroRect];
  [native_window setContentView:empty_content_view];
  [empty_content_view release];
  [native_window autorelease];
}

static void proton_engine_window_apply_closable_style(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == nil) {
    return;
  }
  NSWindowStyleMask style = window->window.styleMask;
  if (window->closable || window->programmatic_close_pending) {
    style |= NSWindowStyleMaskClosable;
  } else {
    style &= ~NSWindowStyleMaskClosable;
  }
  window->window.styleMask = style;
}

static void proton_engine_window_update_zoom_button(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == nil) return;
  NSButton *button = [window->window standardWindowButton:NSWindowZoomButton];
  if (button != nil) {
    const BOOL resizable =
        (window->window.styleMask & NSWindowStyleMaskResizable) != 0;
    button.enabled = resizable &&
                     (window->maximizable || window->fullscreenable);
  }
}

@interface ProtonWindow : NSWindow {
  BOOL proton_focusable;
  BOOL proton_enabled;
}
- (void)setProtonFocusable:(BOOL)focusable;
- (void)setProtonEnabled:(BOOL)enabled;
@end

@implementation ProtonWindow
- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backingStoreType
                              defer:(BOOL)flag {
  self = [super initWithContentRect:contentRect
                         styleMask:style
                           backing:backingStoreType
                             defer:flag];
  if (self != nil) {
    proton_focusable = YES;
    proton_enabled = YES;
  }
  return self;
}

- (BOOL)canBecomeKeyWindow {
  return proton_focusable && proton_enabled;
}

- (BOOL)canBecomeMainWindow {
  return proton_focusable && proton_enabled;
}

- (void)setProtonFocusable:(BOOL)focusable {
  proton_focusable = focusable;
}

- (void)setProtonEnabled:(BOOL)enabled {
  proton_enabled = enabled;
}
@end

@interface ProtonWindowDelegate : NSObject <NSWindowDelegate> {
@public
  proton_engine_window_t *window;
}
@end

@implementation ProtonWindowDelegate
- (void)windowStateDidChange:(NSNotification *)notification {
  (void)notification;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

- (void)windowDidMove:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidResize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidResignKey:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
  [self windowStateDidChange:notification];
}

- (BOOL)windowShouldClose:(id)sender {
  NSWindow *native_window = sender;
  if (window == NULL) {
    return YES;
  }
  if (window->closed) {
    proton_engine_window_commit_appkit_close(window, native_window);
    return YES;
  }
  if (window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return NO;
  }
  window->close_interception_bypass = 0;
  if (window->browser == NULL) {
    proton_engine_window_commit_appkit_close(window, native_window);
    return YES;
  }
  cef_browser_host_t *host = window->browser->get_host(window->browser);
  if (host == NULL) {
    proton_engine_window_commit_appkit_close(window, native_window);
    return YES;
  }
  int allow_close = 0;
  if (host->is_ready_to_be_closed != NULL &&
      host->is_ready_to_be_closed(host)) {
    allow_close = 1;
    window->appkit_closing = 1;
  } else if (host->try_close_browser != NULL) {
    window->browser_close_requested = 1;
    allow_close = host->try_close_browser(host);
    if (allow_close) {
      window->appkit_closing = 1;
    }
  } else if (window->cef_allows_appkit_close) {
    allow_close = 1;
    window->appkit_closing = 1;
  } else {
    window->browser_close_requested = 1;
    host->close_browser(host, 0);
  }
  host->base.release((cef_base_ref_counted_t *)host);
  if (allow_close) {
    proton_engine_window_commit_appkit_close(window, native_window);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return allow_close ? YES : NO;
}

- (void)windowWillClose:(NSNotification *)notification {
  if (window == NULL) {
    return;
  }
  proton_engine_window_commit_appkit_close(window, notification.object);
}
@end

@interface ProtonContentView : NSView {
@public
  proton_engine_window_t *window;
}
@end

@implementation ProtonContentView
- (void)viewDidChangeEffectiveAppearance {
  [super viewDidChangeEffectiveAppearance];
  if (window != NULL) {
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  }
}
@end

// A NULL runtime means every window in the process, the same rule the host
// loop follows everywhere else: it owns the main thread on behalf of whatever
// runtimes happen to exist, and holds a handle to none of them.
void proton_engine_runtime_create_pending_browsers(
    proton_engine_runtime_t *runtime) {
  for (proton_engine_window_t *window = g_windows; window != NULL;
       window = window->next) {
    if ((runtime != NULL && window->runtime != runtime) ||
        !window->browser_create_pending || window->browser_create_scheduled ||
        window->closed) {
      continue;
    }
    uint64_t native_id = window->native_id;
    window->browser_create_scheduled = 1;
    // Create CEF browsers after the main run loop has started pumping.
    dispatch_async(dispatch_get_main_queue(), ^{
      proton_engine_window_t *pending_window =
          proton_engine_window_from_native_id(native_id);
      if (pending_window == NULL) {
        return;
      }
      if (pending_window->closed || !pending_window->browser_create_pending) {
        pending_window->browser_create_scheduled = 0;
        proton_engine_window_finalize_if_ready(pending_window);
        proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
        return;
      }
      pending_window->browser_create_pending = 0;
      char error[512] = {0};
      // TODO(CEF issue 3810): See
      // https://github.com/chromiumembedded/cef/issues/3810. Keep browser
      // creation scheduled after the macOS run loop is pumping, and don't let
      // CEF's initial navigation touch Proton resources before cef_browser_t has
      // been registered to this window. Mark the navigation pending before
      // creation, then post it to CEF's UI task runner from on_after_created.
      pending_window->initial_navigation_pending = 1;
      int32_t status = proton_engine_window_create_browser(
          pending_window, "about:blank", error, sizeof(error));
      if (status != PROTON_OK) {
        pending_window->initial_navigation_pending = 0;
        pending_window->browser_create_scheduled = 0;
        proton_engine_window_mark_closed(pending_window);
        proton_engine_window_finalize_if_ready(pending_window);
      }
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    });
  }
}

void proton_engine_view_on_after_created(proton_engine_view_t *view,
                                         cef_browser_t *browser);
void proton_engine_view_on_before_close(proton_engine_view_t *view,
                                        cef_browser_t *browser);
void proton_engine_window_close_views(proton_engine_window_t *window);
void proton_engine_window_layout_views(proton_engine_window_t *window);
void proton_engine_window_free_views(proton_engine_window_t *window);
void proton_engine_view_finalize_if_ready(proton_engine_view_t *view);

static int32_t proton_engine_window_create_browser(
    proton_engine_window_t *window,
    const char *initial_url,
    char *error,
    size_t error_len) {
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
  window_info.bounds.x = 0;
  window_info.bounds.y = 0;
  window_info.bounds.width = window->width;
  window_info.bounds.height = window->height;
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
  int accepted = cef_browser_host_create_browser(
      &window_info, &window->client->client, &url, &browser_settings,
      extra_info, NULL);
  if (extra_info_value != NULL) {
    extra_info_value->base.release((cef_base_ref_counted_t *)extra_info_value);
  }
  cef_string_clear(&window_info.window_name);
  cef_string_clear(&url);
  if (!accepted) {
    proton_engine_set_message(error, error_len, "browser creation failed");
    return PROTON_ERR_ENGINE;
  }
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

  proton_engine_window_t *window =
      (proton_engine_window_t *)calloc(1, sizeof(*window));
  if (window == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate window state");
    return PROTON_ERR_ENGINE;
  }
  window->runtime = runtime;
  window->public_window_id = config.public_window;
  window->native_id = g_next_window_native_id++;
  if (g_next_window_native_id == 0) {
    g_next_window_native_id = 1;
  }
  window->width = config.width;
  window->height = config.height;
  window->min_width = config.size_hint == 2 ? config.width : 0;
  window->min_height = config.size_hint == 2 ? config.height : 0;
  window->max_width = config.size_hint == 3 ? config.width : 0;
  window->max_height = config.size_hint == 3 ? config.height : 0;
  window->zoom_percent = 100;
  window->maximizable = 1;
  window->closable = 1;
  window->fullscreenable = 1;
  window->enabled = 1;
  window->headless = runtime->headless;
  window->bridge_config_json =
      config.bridge_config_json != NULL
          ? proton_engine_strdup(config.bridge_config_json)
          : NULL;
  window->max_bridge_payload_bytes = config.max_bridge_payload_bytes;
  window->browser_session = proton_browser_session_create(
      &config.browser_policy, proton_engine_browser_signal, NULL);
  if (window->browser_session == NULL) {
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to allocate browser session");
    return PROTON_ERR_ENGINE;
  }
  proton_browser_session_bind_window(window->browser_session,
                                     config.public_window);
  window->client = proton_engine_client_create(window);
  if (window->client == NULL) {
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len, "failed to allocate client");
    return PROTON_ERR_ENGINE;
  }

  ProtonWindowDelegate *delegate = nil;
  if (!window->headless) {
    NSRect rect = NSMakeRect(0, 0, config.width, config.height);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable;
    if (config.size_hint != 1) {
      style |= NSWindowStyleMaskResizable;
    }
    if (config.titlebar_overlay) {
      style |= NSWindowStyleMaskFullSizeContentView;
    }
    NSString *title = [NSString stringWithUTF8String:config.title];
    window->window = [[ProtonWindow alloc] initWithContentRect:rect
                                                 styleMask:style
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    if (window->window == nil) {
      free(window->client);
      proton_browser_session_destroy(window->browser_session);
      free(window->bridge_config_json);
      free(window);
      proton_engine_set_message(error, error_len, "window creation failed");
      return PROTON_ERR_PLATFORM;
    }
    // The close delegate tears down the CEF view hierarchy before releasing
    // the window from the message-pump autorelease pool. Releasing directly in
    // AppKit's close callback can destroy CEF state while that callback is
    // still on the stack.
    [window->window setReleasedWhenClosed:NO];
    // Proton owns window restoration through its application manifest and
    // runtime session. Letting AppKit persist the same windows creates a second
    // lifecycle owner and can block startup on its crash-recovery UI before
    // Proton has created a window of its own.
    [window->window setRestorable:NO];
    [window->window disableSnapshotRestoration];
    [window->window setTitle:title != nil ? title : @"Proton"];
    proton_engine_apply_size_constraints(window);
    if (config.titlebar_overlay) {
      [window->window setTitleVisibility:NSWindowTitleHidden];
      [window->window setTitlebarAppearsTransparent:YES];
    }
    [window->window center];
    ProtonContentView *content_view = [[ProtonContentView alloc]
        initWithFrame:[[window->window contentView] bounds]];
    content_view->window = window;
    [content_view setAutoresizingMask:NSViewWidthSizable |
                                      NSViewHeightSizable];
    [window->window setContentView:content_view];
    window->content_view = content_view;
    [content_view release];
    delegate = [[ProtonWindowDelegate alloc] init];
    delegate->window = window;
    window->delegate = delegate;
    [window->window setDelegate:delegate];
  }


  window->initial_url =
      proton_engine_strdup(config.initial_url[0] != '\0' ? config.initial_url
                                                         : "about:blank");
  if (window->initial_url == NULL) {
    if (window->window != nil) {
      [window->window close];
    }
    if (delegate != nil) {
      [delegate release];
    }
    free(window->client);
    proton_browser_session_destroy(window->browser_session);
    free(window->bridge_config_json);
    free(window);
    proton_engine_set_message(error, error_len,
                              "failed to copy initial browser url");
    return PROTON_ERR_ENGINE;
  }
  window->browser_create_pending = 1;
  proton_engine_window_list_add(window);
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  *out_window = window;
  return PROTON_OK;
}

static void proton_engine_window_free(proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  if (window->attention_request_id != 0) {
    [NSApp cancelUserAttentionRequest:window->attention_request_id];
    window->attention_request_id = 0;
  }
  if (g_dock_progress_owner == window) {
    proton_engine_dock_progress_clear();
  }
  if (window->delegate != nil) {
    [window->delegate release];
    window->delegate = nil;
  }
  proton_engine_window_lock();
  proton_engine_window_free_views(window);
  free(window->client);
  free(window->bridge_config_json);
  free(window->initial_url);
  proton_browser_session_destroy(window->browser_session);
  proton_engine_bridge_lifecycle_dispose(&window->bridge_lifecycle);
  free(window);
  proton_engine_window_unlock();
}

static void proton_engine_window_detach_native_window(
    proton_engine_window_t *window) {
  if (window == NULL || window->window == nil) {
    if (window != NULL) {
      window->content_view = nil;
      window->browser_view = nil;
    }
    return;
  }
  NSWindow *native_window = window->window;
  window->window = nil;
  window->content_view = nil;
  window->browser_view = nil;
  [native_window setDelegate:nil];
  [native_window close];
}

static void proton_engine_window_defer_finalize(
    proton_engine_window_t *window) {
  if (window == NULL) {
    return;
  }
  window->finalize_after_browser_close = 1;
  window->browser_create_pending = 0;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_window_finalize_if_ready(
    proton_engine_window_t *window) {
  if (window == NULL || !window->finalize_after_browser_close) {
    return;
  }
  if (window->browser_create_scheduled ||
      window->initial_navigation_pending) {
    return;
  }
  if (window->browser_id != 0 && !window->browser_before_close_seen) {
    return;
  }
  for (proton_engine_view_t *view = window->views; view != NULL;
       view = view->next) {
    if (!view->finalized) {
      return;
    }
  }
  proton_engine_window_list_remove(window);
  if (window->client != NULL) {
    window->client->window = NULL;
  }
  proton_engine_window_detach_native_window(window);
  proton_engine_window_free(window);
}

int32_t proton_engine_window_destroy(proton_engine_window_t *window,
                                     char *error,
                                     size_t error_len) {

  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_window_close_views(window);
  if (window->browser != NULL) {
    if (!window->browser_close_requested &&
        !proton_engine_window_request_browser_close(window, 1)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    proton_engine_window_mark_closed(window);
    proton_engine_window_defer_finalize(window);
    proton_engine_window_finalize_if_ready(window);
    return PROTON_OK;
  }
  proton_engine_window_mark_closed(window);
  proton_engine_window_defer_finalize(window);
  proton_engine_window_finalize_if_ready(window);
  return PROTON_OK;
}

int32_t proton_engine_window_show(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
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
    [window->window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_show_inactive(proton_engine_window_t *window,
                                           char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return proton_engine_window_show(window, error, error_len);
  [window->window orderFront:nil];
  return PROTON_OK;
}

int32_t proton_engine_window_hide(proton_engine_window_t *window,
                                  char *error,
                                  size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
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
    [window->window orderOut:nil];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_close(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless && window->close_interception_enabled &&
      !window->close_interception_bypass) {
    if (!window->close_request_pending) {
      window->close_request_id++;
      if (window->close_request_id == 0) {
        window->close_request_id = 1;
      }
      window->close_request_pending = 1;
      proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    }
    return PROTON_OK;
  }
  window->close_interception_bypass = 0;
  if (!window->headless) {
    window->programmatic_close_pending = 1;
    proton_engine_window_apply_closable_style(window);
    [window->window performClose:nil];
    return PROTON_OK;
  }
  if (window->browser != NULL) {
    if (!proton_engine_window_request_browser_close(window, 0)) {
      proton_engine_set_message(error, error_len,
                                "browser host is not available for close");
      return PROTON_ERR_ENGINE;
    }
    return PROTON_OK;
  }
  proton_engine_window_mark_closed(window);
  window->browser_create_pending = 0;
  return PROTON_OK;
}

int32_t proton_engine_window_is_closed(proton_engine_window_t *window) {

  return window == NULL || window->closed;
}

int32_t proton_engine_window_popup_menu(
    proton_engine_window_t *window, int32_t x, int32_t y,
    const proton_menu_bar_t *menu_bar, char *error, size_t error_len) {
  if (window == NULL || !proton_engine_runtime_initialized()) {
    proton_engine_set_message(error, error_len, "runtime is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (menu_bar == NULL || menu_bar->menu_count == 0) {
    proton_engine_set_message(error, error_len,
                              "popup menu requires at least one menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->browser_view == nil) {
    proton_engine_set_message(error, error_len,
                              "window is not ready for a popup menu");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  NSView *view = window->browser_view;
  __block int32_t status = PROTON_OK;
  char main_error[512] = {0};
  char *main_error_buffer = main_error;
  /* Context menus can be the only menu surface in an application. Keep the
     runtime route installed while AppKit dispatches the synchronous popup so
     command items use the same event path as the application menu. */
  proton_engine_menu_set_runtime(window->runtime);
  void (^work)(void) = ^{
    status = proton_engine_menu_popup_on_main(
        (__bridge void *)view, x, y, menu_bar, main_error_buffer,
        sizeof(main_error));
  };
  if ([NSThread isMainThread]) {
    work();
  } else {
    dispatch_sync(dispatch_get_main_queue(), work);
  }
  if (status != PROTON_OK) {
    proton_engine_set_message(error, error_len, main_error);
  }
  return status;
}

int32_t proton_engine_window_focus(proton_engine_window_t *window,
                                   char *error,
                                   size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->headless_focused = 1;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->set_focus(host, 1);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    [NSApp activateIgnoringOtherApps:YES];
    [window->window makeKeyAndOrderFront:nil];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_title(proton_engine_window_t *window,
                                       const char *title,
                                       char *error,
                                       size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window title is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  NSString *value = [NSString stringWithUTF8String:title != NULL ? title : ""];
  [window->window setTitle:value != nil ? value : @""];
  return PROTON_OK;
}

int32_t proton_engine_window_set_icon(proton_engine_window_t *window,
                                      const char *path, char *error,
                                      size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  NSString *value = [NSString stringWithUTF8String:path];
  NSImage *image = [[NSImage alloc] initWithContentsOfFile:value];
  if (image == nil) {
    proton_engine_set_message(error, error_len, "failed to load window icon");
    return PROTON_ERR_PLATFORM;
  }
  [window->window setMiniwindowImage:image];
  [image release];
  return PROTON_OK;
}

int32_t proton_engine_window_set_parent(proton_engine_window_t *window,
                                        proton_engine_window_t *parent,
                                        int32_t modal, char *error,
                                        size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  NSWindow *native = window->window;
  NSWindow *sheet_parent = native.sheetParent;
  if (sheet_parent != nil) [sheet_parent endSheet:native];
  NSWindow *child_parent = native.parentWindow;
  if (child_parent != nil) [child_parent removeChildWindow:native];
  if (parent == NULL) return PROTON_OK;
  if (parent->window == nil) {
    proton_engine_set_message(error, error_len, "parent window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (modal) {
    [parent->window beginSheet:native completionHandler:nil];
  } else {
    [parent->window addChildWindow:native ordered:NSWindowAbove];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_size(proton_engine_window_t *window,
                                      int32_t width,
                                      int32_t height,
                                      char *error,
                                      size_t error_len) {

  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  window->width = width;
  window->height = height;
  if (window->headless) {
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
  } else {
    NSRect frame = [window->window frame];
    frame.size.width = width;
    frame.size.height = height;
    [window->window setFrame:frame display:YES animate:NO];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_content_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (width <= 0 || height <= 0) {
    proton_engine_set_message(error, error_len,
                              "width and height must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    window->width = width;
    window->height = height;
    if (window->browser != NULL) {
      cef_browser_host_t *host = window->browser->get_host(window->browser);
      if (host != NULL) {
        host->was_resized(host);
        host->base.release((cef_base_ref_counted_t *)host);
      }
    }
    return PROTON_OK;
  }
  [window->window setContentSize:NSMakeSize(width, height)];
  return PROTON_OK;
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
  if (window->window == nil) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  NSRect bounds = window->window.contentView.bounds;
  *out_width = (int32_t)llround(bounds.size.width);
  *out_height = (int32_t)llround(bounds.size.height);
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  proton_engine_apply_size_constraints(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximum_size(
    proton_engine_window_t *window, int32_t width, int32_t height,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  proton_engine_apply_size_constraints(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_aspect_ratio(
    proton_engine_window_t *window, double aspect_ratio, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  if (aspect_ratio > 0.0) {
    [window->window setContentAspectRatio:NSMakeSize(aspect_ratio, 1.0)];
  } else {
    [window->window setResizeIncrements:NSMakeSize(1.0, 1.0)];
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_movable(proton_engine_window_t *window,
                                         int32_t movable, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  [window->window setMovable:movable != 0];
  return PROTON_OK;
}

int32_t proton_engine_window_set_opacity(proton_engine_window_t *window,
                                         double opacity, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  [window->window setAlphaValue:bounded_opacity];
  return PROTON_OK;
}

int32_t proton_engine_window_set_skip_taskbar(proton_engine_window_t *window,
                                              int32_t skip, char *error,
                                              size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  // Electron's macOS implementation intentionally treats setSkipTaskbar as
  // a successful no-op because macOS has no taskbar equivalent.
  return PROTON_OK;
}

int32_t proton_engine_window_set_content_protection(
    proton_engine_window_t *window, int32_t enabled, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  window->window.sharingType = enabled ? NSWindowSharingNone : NSWindowSharingReadOnly;
  return PROTON_OK;
}

int32_t proton_engine_window_set_minimizable(
    proton_engine_window_t *window, int32_t minimizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  NSWindowStyleMask style = window->window.styleMask;
  if (minimizable) {
    style |= NSWindowStyleMaskMiniaturizable;
  } else {
    style &= ~NSWindowStyleMaskMiniaturizable;
  }
  window->window.styleMask = style;
  return PROTON_OK;
}

int32_t proton_engine_window_set_maximizable(
    proton_engine_window_t *window, int32_t maximizable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  window->maximizable = maximizable;
  proton_engine_window_update_zoom_button(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_closable(
    proton_engine_window_t *window, int32_t closable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  window->closable = closable;
  proton_engine_window_apply_closable_style(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_button_visibility(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  const NSWindowButton buttons[] = {
      NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
  for (size_t index = 0; index < sizeof(buttons) / sizeof(buttons[0]); index++) {
    NSButton *button = [window->window standardWindowButton:buttons[index]];
    if (button != nil) button.hidden = visible == 0;
  }
  return PROTON_OK;
}

int32_t proton_engine_window_set_focusable(
    proton_engine_window_t *window, int32_t focusable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  [(ProtonWindow *)window->window setProtonFocusable:focusable != 0];
  return PROTON_OK;
}

int32_t proton_engine_window_set_progress_bar(
    proton_engine_window_t *window, double progress, char *error,
    size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (isnan(progress)) {
    proton_engine_set_message(error, error_len,
                              "progress must not be NaN");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(
        error, error_len,
        "window progress is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (progress < 0.0) {
    proton_engine_dock_progress_clear();
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (!proton_engine_dock_progress_prepare(error, error_len)) {
    return PROTON_ERR_PLATFORM;
  }
  g_dock_progress_owner = window;
  if (progress > 1.0) {
    g_dock_progress_indicator.indeterminate = YES;
    [g_dock_progress_indicator startAnimation:nil];
  } else {
    [g_dock_progress_indicator stopAnimation:nil];
    g_dock_progress_indicator.indeterminate = NO;
    g_dock_progress_indicator.doubleValue = progress;
  }
  [[NSApp dockTile] display];
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_flash_frame(
    proton_engine_window_t *window, int32_t flash, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is required");
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
  if (flash) {
    if (window->attention_request_id != 0) {
      [NSApp cancelUserAttentionRequest:window->attention_request_id];
    }
    window->attention_request_id =
        [NSApp requestUserAttention:NSCriticalRequest];
  } else if (window->attention_request_id != 0) {
    [NSApp cancelUserAttentionRequest:window->attention_request_id];
    window->attention_request_id = 0;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

static CGFloat proton_engine_primary_screen_top(void) {
  NSArray<NSScreen *> *screens = [NSScreen screens];
  NSScreen *primary = screens.count > 0 ? screens[0] : nil;
  return primary != nil ? NSMaxY(primary.frame) : 0.0;
}

static int32_t proton_engine_macos_top_y(NSRect frame) {
  return (int32_t)llround(proton_engine_primary_screen_top() - NSMaxY(frame));
}

int32_t proton_engine_window_apply(
    proton_engine_window_t *window,
    const proton_engine_window_action_t *action,
    char *error,
    size_t error_len) {

  if (window == NULL || action == NULL ||
      (!window->headless && window->window == nil)) {
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
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
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
    [window->window miniaturize:nil];
    break;
  case PROTON_ENGINE_WINDOW_MAXIMIZE:
    if ([window->window isMiniaturized]) {
      [window->window deminiaturize:nil];
    }
    if (![window->window isZoomed]) {
      [window->window zoom:nil];
    }
    break;
  case PROTON_ENGINE_WINDOW_RESTORE:
    if ((window->window.styleMask & NSWindowStyleMaskFullScreen) != 0) {
      [window->window toggleFullScreen:nil];
    }
    if ([window->window isMiniaturized]) {
      [window->window deminiaturize:nil];
    }
    if ([window->window isZoomed]) {
      [window->window zoom:nil];
    }
    break;
  case PROTON_ENGINE_WINDOW_SET_FULLSCREEN: {
    if (!window->fullscreenable && action->value != 0) break;
    const BOOL fullscreen =
        (window->window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (fullscreen != (action->value != 0)) {
      [window->window toggleFullScreen:nil];
    }
    break;
  }
  case PROTON_ENGINE_WINDOW_SET_KIOSK: {
    const BOOL fullscreen =
        (window->window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (action->value != 0) {
      [NSApp setPresentationOptions:(NSApplicationPresentationAutoHideDock |
                                     NSApplicationPresentationAutoHideMenuBar |
                                     NSApplicationPresentationFullScreen)];
    } else {
      [NSApp setPresentationOptions:NSApplicationPresentationDefault];
    }
    if (fullscreen != (action->value != 0)) {
      [window->window toggleFullScreen:nil];
    }
    break;
  }
  case PROTON_ENGINE_WINDOW_SET_POSITION: {
    NSRect frame = window->window.frame;
    const CGFloat cocoa_y =
        proton_engine_primary_screen_top() - action->y - frame.size.height;
    [window->window
        setFrameOrigin:NSMakePoint((CGFloat)action->x, cocoa_y)];
    break;
  }
  case PROTON_ENGINE_WINDOW_SET_ALWAYS_ON_TOP:
    window->window.level =
        action->value != 0 ? NSFloatingWindowLevel : NSNormalWindowLevel;
    break;
  case PROTON_ENGINE_WINDOW_SET_RESIZABLE: {
    NSWindowStyleMask style = window->window.styleMask;
    if (action->value != 0) {
      style |= NSWindowStyleMaskResizable;
    } else {
      style &= ~NSWindowStyleMaskResizable;
    }
    window->window.styleMask = style;
    proton_engine_window_update_zoom_button(window);
    break;
  }
  default:
    proton_engine_set_message(error, error_len,
                              "unknown window action");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_set_fullscreenable(
    proton_engine_window_t *window, int32_t fullscreenable, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  NSWindowCollectionBehavior behavior = window->window.collectionBehavior;
  if (fullscreenable) {
    behavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    behavior &= ~NSWindowCollectionBehaviorFullScreenAuxiliary;
  } else {
    behavior &= ~NSWindowCollectionBehaviorFullScreenPrimary;
    behavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;
  }
  window->window.collectionBehavior = behavior;
  proton_engine_window_update_zoom_button(window);
  return PROTON_OK;
}

int32_t proton_engine_window_set_has_shadow(
    proton_engine_window_t *window, int32_t has_shadow, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  window->window.hasShadow = has_shadow != 0;
  return PROTON_OK;
}

int32_t proton_engine_window_set_ignore_mouse_events(
    proton_engine_window_t *window, int32_t ignore, int32_t forward,
    char *error, size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (ignore != 0 && ignore != 1) {
    proton_engine_set_message(error, error_len, "ignore must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (forward != 0 && forward != 1) {
    proton_engine_set_message(error, error_len, "forward must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "mouse event handling is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  window->ignore_mouse_events = ignore;
  window->ignore_mouse_forward = ignore ? forward : 0;
  [window->window
      setIgnoresMouseEvents:ignore != 0 || window->enabled == 0];
  return PROTON_OK;
}

int32_t proton_engine_window_set_background_color(
    proton_engine_window_t *window, uint32_t color, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (window->headless) {
    proton_engine_set_message(error, error_len,
                              "window background is not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  const CGFloat alpha = (CGFloat)((color >> 24) & 0xff) / 255.0;
  const CGFloat red = (CGFloat)((color >> 16) & 0xff) / 255.0;
  const CGFloat green = (CGFloat)((color >> 8) & 0xff) / 255.0;
  const CGFloat blue = (CGFloat)(color & 0xff) / 255.0;
  window->content_view.wantsLayer = YES;
  window->content_view.layer.backgroundColor =
      [NSColor colorWithRed:red green:green blue:blue alpha:alpha].CGColor;
  return PROTON_OK;
}

int32_t proton_engine_window_set_visible_on_all_workspaces(
    proton_engine_window_t *window, int32_t visible, char *error,
    size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
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
  NSWindowCollectionBehavior behavior = window->window.collectionBehavior;
  if (visible) {
    behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces;
  } else {
    behavior &= ~NSWindowCollectionBehaviorCanJoinAllSpaces;
  }
  window->window.collectionBehavior = behavior;
  return PROTON_OK;
}

int32_t proton_engine_window_set_enabled(proton_engine_window_t *window,
                                         int32_t enabled, char *error,
                                         size_t error_len) {
  if (window == NULL || (!window->headless && window->window == nil)) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (enabled != 0 && enabled != 1) {
    proton_engine_set_message(error, error_len, "enabled must be 0 or 1");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (window->headless) return PROTON_OK;
  window->enabled = enabled;
  [(ProtonWindow *)window->window setProtonEnabled:enabled != 0];
  [window->window setIgnoresMouseEvents:enabled == 0 || window->ignore_mouse_events != 0];
  if (!enabled && [window->window isKeyWindow]) [window->window resignKeyWindow];
  return PROTON_OK;
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
    out_state->focused = window->headless_focused;
    return PROTON_OK;
  }
  if (window->window == nil) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  const NSRect frame = window->window.frame;
  NSScreen *screen = window->window.screen;
  if (screen == nil) {
    screen = [NSScreen mainScreen];
  }
  const NSRect monitor = screen != nil ? screen.frame : NSZeroRect;
  const NSRect work = screen != nil ? screen.visibleFrame : NSZeroRect;
  out_state->x = (int32_t)llround(frame.origin.x);
  out_state->y = proton_engine_macos_top_y(frame);
  out_state->width = (int32_t)llround(frame.size.width);
  out_state->height = (int32_t)llround(frame.size.height);
  out_state->monitor_x = (int32_t)llround(monitor.origin.x);
  out_state->monitor_y = proton_engine_macos_top_y(monitor);
  out_state->monitor_width = (int32_t)llround(monitor.size.width);
  out_state->monitor_height = (int32_t)llround(monitor.size.height);
  out_state->work_x = (int32_t)llround(work.origin.x);
  out_state->work_y = proton_engine_macos_top_y(work);
  out_state->work_width = (int32_t)llround(work.size.width);
  out_state->work_height = (int32_t)llround(work.size.height);
  out_state->scale_factor_percent =
      (int32_t)llround(window->window.backingScaleFactor * 100.0);
  out_state->visible = window->window.isVisible ? 1 : 0;
  out_state->focused = window->window.isKeyWindow ? 1 : 0;
  out_state->minimized = window->window.isMiniaturized ? 1 : 0;
  out_state->maximized = window->window.isZoomed ? 1 : 0;
  out_state->fullscreen =
      (window->window.styleMask & NSWindowStyleMaskFullScreen) != 0 ? 1 : 0;
  out_state->always_on_top =
      window->window.level > NSNormalWindowLevel ? 1 : 0;
  NSAppearance *appearance = window->window.effectiveAppearance;
  NSAppearanceName match = [appearance
      bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua, NSAppearanceNameDarkAqua
      ]];
  out_state->theme = [match isEqualToString:NSAppearanceNameDarkAqua] ? 2 : 1;
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
    window->programmatic_close_pending = 0;
    proton_engine_window_apply_closable_style(window);
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
    [window->window performClose:nil];
  } else if (!allow) {
    window->programmatic_close_pending = 0;
    proton_engine_window_apply_closable_style(window);
  }
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
}

int32_t proton_engine_window_load_url(proton_engine_window_t *window,
                                      const char *url,
                                      char *error,
                                      size_t error_len) {

  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((window->browser == NULL &&
       (window->browser_create_pending || window->browser_create_scheduled)) ||
      window->initial_navigation_pending) {
    char *url_copy =
        proton_engine_strdup(url != NULL && url[0] != '\0' ? url : "about:blank");
    if (url_copy == NULL) {
      proton_engine_set_message(error, error_len,
                                "failed to copy pending browser url");
      return PROTON_ERR_ENGINE;
    }
    free(window->initial_url);
    window->initial_url = url_copy;
    proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
    return PROTON_OK;
  }
  if (window->browser == NULL) {
    proton_engine_set_message(error, error_len, "browser is not initialized");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  cef_frame_t *frame = window->browser->get_main_frame(window->browser);
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

int32_t proton_engine_window_browser_command_json(
    proton_engine_window_t *window, const char *command_json,
    char *error, size_t error_len) {

  if (window == NULL || window->browser_session == NULL ||
      window->browser == NULL) {
    proton_engine_set_message(error, error_len,
                              "browser is not initialized");
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
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
  return PROTON_OK;
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
