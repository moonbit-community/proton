#if defined(__APPLE__)

#import "mac_internal.h"

#include "../ffi/src/engine/cef_common/message.h"

static void *proton_voice_over_context = &proton_voice_over_context;
static void *proton_switch_control_context = &proton_switch_control_context;

@interface ProtonAccessibilityObserver : NSObject {
@private
  proton_engine_runtime_t *runtime_;
}

- (instancetype)initWithRuntime:(proton_engine_runtime_t *)runtime;
- (void)invalidate;
- (void)refresh;
- (void)scheduleRefresh;
@end

// Main-thread only. Foreign accessibility callbacks dispatch before reading it.
static ProtonAccessibilityObserver *g_accessibility_observer = nil;
static NSUInteger g_enhanced_user_interface_requests = 0;

@implementation ProtonAccessibilityObserver

- (instancetype)initWithRuntime:(proton_engine_runtime_t *)runtime {
  self = [super init];
  if (self != nil) {
    runtime_ = runtime;
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    [workspace addObserver:self
                forKeyPath:@"voiceOverEnabled"
                   options:0
                   context:proton_voice_over_context];
    [workspace addObserver:self
                forKeyPath:@"switchControlEnabled"
                   options:0
                   context:proton_switch_control_context];
  }
  return self;
}

- (void)refresh {
  proton_engine_runtime_t *runtime = runtime_;
  if (runtime == NULL || runtime->browsers == NULL) {
    return;
  }
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  BOOL active = runtime->headless || [workspace isVoiceOverEnabled] ||
                [workspace isSwitchControlEnabled] ||
                g_enhanced_user_interface_requests > 0;
  proton_browser_registry_set_accessibility_state(
      runtime->browsers, active ? STATE_ENABLED : STATE_DISABLED);
}

- (void)scheduleRefresh {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self refresh];
  });
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  (void)keyPath;
  (void)object;
  (void)change;
  if (context == proton_voice_over_context ||
      context == proton_switch_control_context) {
    [self scheduleRefresh];
    return;
  }
  [super observeValueForKeyPath:keyPath
                       ofObject:object
                         change:change
                        context:context];
}

- (void)invalidate {
  if (runtime_ == NULL) {
    return;
  }
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  [workspace removeObserver:self
                 forKeyPath:@"voiceOverEnabled"
                    context:proton_voice_over_context];
  [workspace removeObserver:self
                 forKeyPath:@"switchControlEnabled"
                    context:proton_switch_control_context];
  runtime_ = NULL;
}

@end

void proton_engine_accessibility_set_enhanced_user_interface(int enabled) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (enabled) {
      g_enhanced_user_interface_requests++;
    } else if (g_enhanced_user_interface_requests > 0) {
      g_enhanced_user_interface_requests--;
    }
    [g_accessibility_observer refresh];
  });
  proton_engine_signal_wait_source(PROTON_WAIT_PLATFORM);
}

void proton_engine_runtime_stop_accessibility(
    proton_engine_runtime_t *runtime) {
  if (runtime == NULL || runtime->accessibility_observer == nil) {
    return;
  }
  ProtonAccessibilityObserver *observer =
      (ProtonAccessibilityObserver *)runtime->accessibility_observer;
  if (g_accessibility_observer == observer) {
    g_accessibility_observer = nil;
  }
  [observer invalidate];
  [observer release];
  runtime->accessibility_observer = nil;
}

int32_t proton_engine_runtime_start_accessibility(
    proton_engine_runtime_t *runtime, int32_t mode, char *error,
    size_t error_len) {
  if (runtime == NULL) {
    proton_engine_set_message(error, error_len, "runtime is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (mode == PROTON_ACCESSIBILITY_ALWAYS_ENABLED || runtime->headless) {
    proton_browser_registry_set_accessibility_state(runtime->browsers,
                                                    STATE_ENABLED);
    return PROTON_OK;
  }
  ProtonAccessibilityObserver *observer =
      [[ProtonAccessibilityObserver alloc] initWithRuntime:runtime];
  if (observer == nil) {
    proton_engine_set_message(error, error_len,
                              "failed to observe accessibility state");
    return PROTON_ERR_PLATFORM;
  }
  runtime->accessibility_observer = observer;
  g_accessibility_observer = observer;
  [observer refresh];
  return PROTON_OK;
}

#endif
