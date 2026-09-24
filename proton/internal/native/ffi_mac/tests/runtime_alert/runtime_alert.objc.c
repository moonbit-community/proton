#if defined(__APPLE__)
#include "../../mac_internal.h"
#include "../../mac_dialog.h"
#include <string.h>

static NSWindow *presented_window;
static int ended_sessions;
static int completed_dialogs;
static int64_t completed_id;

// Exercise the production controller without activating the app or displaying
// windows. NSAlert still builds and lays out its real AppKit controls.
@interface ProtonAlertTestApplication : NSApplication
@end
@implementation ProtonAlertTestApplication
- (void)activate {}
- (void)activateIgnoringOtherApps:(BOOL)flag { (void)flag; }
- (NSModalSession)beginModalSessionForWindow:(NSWindow *)window {
  presented_window = [window retain];
  return (NSModalSession)self;
}
- (NSModalResponse)runModalSession:(NSModalSession)session {
  (void)session;
  return NSModalResponseContinue;
}
- (void)endModalSession:(NSModalSession)session {
  (void)session;
  ended_sessions++;
}
@end

static bool capture_completion(void *context, proton_event_t *event) {
  (void)context;
  if (event->kind == PROTON_EVENT_DIALOG_COMPLETED && event->int_a == PROTON_OK) {
    completed_dialogs++;
    completed_id = event->request_id;
  }
  proton_event_destroy(event);
  return true;
}

static void inspect_controls(NSView *view, NSString *message,
                             NSTextField **detail, NSMutableArray *buttons) {
  if ([view isHidden]) return;
  if ([view isKindOfClass:[NSTextField class]] &&
      [[(NSTextField *)view stringValue] isEqualToString:message]) {
    *detail = (NSTextField *)view;
  }
  if ([view isKindOfClass:[NSButton class]]) [buttons addObject:view];
  for (NSView *child in [view subviews])
    inspect_controls(child, message, detail, buttons);
}

#define CHECK(condition) do { if (!(condition)) { result = __LINE__; goto cleanup; } } while (0)

int32_t proton_test_runtime_alert(void) {
  @autoreleasepool {
    [ProtonAlertTestApplication sharedApplication];
    proton_engine_runtime_t runtime = {0};
    int result = 0;
    proton_event_bind_sink(capture_completion, &runtime);
    NSArray *messages = @[
      @"The application encountered an error.\n\nread bridge state before command failed (-3): window is closing or closed",
      @"应用遇到错误。\n\nread bridge state before command failed (-3): window is closing or closed",
      @"应用遇到错误。\n\nFailed to initialize the application runtime.\nOperation: load application resources\nPath: /Users/example/Documents/应用资源/a-long-resource-directory/application/resources/index.html\nReason: the requested resource could not be opened. Verify that the application bundle contains all required files."
    ];
    for (NSUInteger i = 0; i < [messages count]; i++) {
      NSString *label = i == 0 ? @"OK" : @"确定";
      snprintf(runtime.dialog_ok_label, sizeof(runtime.dialog_ok_label), "%s", [label UTF8String]);
      const char *title = i == 0 ? "Application error" : "应用错误";
      const char *message = [messages[i] UTF8String];
      char error[256] = {0};
      int64_t dialog = 0;
      CHECK(proton_engine_runtime_begin_message_dialog(
          &runtime, title, (int32_t)strlen(title), message, (int32_t)strlen(message),
          2, &dialog, error, sizeof(error)) == PROTON_OK);
      CHECK(presented_window != nil && ![presented_window isVisible]);
      NSTextField *detail = nil;
      NSMutableArray *buttons = [NSMutableArray array];
      inspect_controls([presented_window contentView], messages[i], &detail, buttons);
      CHECK(detail != nil);
      NSSize needed = [[detail cell] cellSizeForBounds:NSMakeRect(
          0, 0, NSWidth([detail bounds]), CGFLOAT_MAX)];
      CHECK(NSHeight([detail bounds]) + 1 >= needed.height);
      NSView *content = [presented_window contentView];
      CHECK(NSContainsRect([content bounds], [detail convertRect:[detail bounds] toView:content]));
      CHECK([buttons count] == 1);
      NSButton *button = buttons[0];
      CHECK([[button title] isEqualToString:label]);
      [button performClick:nil];
      NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
      while (completed_dialogs < (int)i + 1 && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
      CHECK(completed_dialogs == (int)i + 1 && completed_id == dialog);
      CHECK(ended_sessions == completed_dialogs);
      proton_engine_dialog_dispose_runtime(&runtime);
      CHECK(ended_sessions == completed_dialogs);
      [presented_window release];
      presented_window = nil;
    }
cleanup:
    proton_engine_dialog_dispose_runtime(&runtime);
    proton_event_unbind_sink(&runtime);
    [presented_window release];
    presented_window = nil;
    return result;
  }
}
#else
#include <stdint.h>
int32_t proton_test_runtime_alert(void) { return -1; }
#endif
