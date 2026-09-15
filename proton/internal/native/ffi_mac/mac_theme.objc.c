#if defined(__APPLE__)

#import "mac_internal.h"

#include "../ffi/src/proton_event.h"

static int32_t g_native_theme_published = 0;
static int32_t g_native_theme_dark_colors = 0;
static int32_t g_native_theme_high_contrast_colors = 0;

// Publish once per observable system appearance
// change. AppKit and the accessibility display options both announce their
// changes more than once, so compare against the last observed snapshot
// before queuing an event. Main thread only: the runtime and every
// window belong to it.
void proton_engine_publish_native_theme_change(void) {
  int32_t dark_colors = 0;
  int32_t high_contrast_colors = 0;
  char error[256] = {0};
  if (proton_engine_native_theme_query(&dark_colors, &high_contrast_colors,
                                       error, sizeof(error)) !=
      PROTON_OK) {
    return;
  }
  if (!g_native_theme_published) {
    g_native_theme_published = 1;
    g_native_theme_dark_colors = dark_colors;
    g_native_theme_high_contrast_colors = high_contrast_colors;
    return;
  }
  if (g_native_theme_published && dark_colors == g_native_theme_dark_colors &&
      high_contrast_colors == g_native_theme_high_contrast_colors) {
    return;
  }
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_NATIVE_THEME_CHANGED);
  if (event == NULL) {
    return;
  }
  event->bool_a = dark_colors != 0 ? 1 : 0;
  event->bool_b = high_contrast_colors != 0 ? 1 : 0;
  if (!proton_event_publish(event)) {
    proton_event_destroy(event);
    return;
  }
  g_native_theme_published = 1;
  g_native_theme_dark_colors = dark_colors;
  g_native_theme_high_contrast_colors = high_contrast_colors;
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

static void *proton_native_theme_context = &proton_native_theme_context;

@interface ProtonNativeThemeObserver : NSObject

- (instancetype)init;
- (void)invalidate;
- (void)themeDidChange:(NSNotification *)notification;

@end

static ProtonNativeThemeObserver *g_native_theme_observer = nil;

@implementation ProtonNativeThemeObserver

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  // The two inputs of the snapshot. AppKit switches NSApp to a new effective
  // appearance when the user picks light or dark mode, which is how Chromium
  // watches the same setting; the accessibility contrast option is announced
  // on the workspace notification center. Both arrive on the main thread,
  // which owns the runtime.
  [NSApp addObserver:self
          forKeyPath:@"effectiveAppearance"
             options:0
             context:proton_native_theme_context];
  [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserver:self
         selector:@selector(themeDidChange:)
             name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
           object:nil];
  return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if (context == proton_native_theme_context) {
    proton_engine_publish_native_theme_change();
    return;
  }
  [super observeValueForKeyPath:keyPath
                       ofObject:object
                         change:change
                        context:context];
}

- (void)themeDidChange:(NSNotification *)notification {
  (void)notification;
  proton_engine_publish_native_theme_change();
}

- (void)invalidate {
  [NSApp removeObserver:self forKeyPath:@"effectiveAppearance"];
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

@end

void proton_engine_native_theme_start_observing(void) {
  if (g_native_theme_observer != nil) {
    return;
  }
  g_native_theme_published = 0;
  proton_engine_publish_native_theme_change();
  g_native_theme_observer = [[ProtonNativeThemeObserver alloc] init];
}

void proton_engine_native_theme_stop_observing(void) {
  if (g_native_theme_observer == nil) {
    return;
  }
  [g_native_theme_observer invalidate];
  [g_native_theme_observer release];
  g_native_theme_observer = nil;
}

#endif
