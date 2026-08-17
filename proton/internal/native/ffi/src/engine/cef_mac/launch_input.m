#if defined(__APPLE__)

#include "launch_input.h"
#include "platform_events.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <string.h>

#define PROTON_LAUNCH_INPUT_MAX_BYTES 65536

static void proton_engine_launch_input_enqueue(NSString *type,
                                               NSArray<NSString *> *items) {
  NSMutableDictionary *event =
      [NSMutableDictionary dictionaryWithObject:type forKey:@"type"];
  if (items != nil) {
    [event setObject:items forKey:@"items"];
  }
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:event
                                                 options:0
                                                   error:&error];
  if (data == nil || error != nil ||
      [data length] >= PROTON_LAUNCH_INPUT_MAX_BYTES) {
    return;
  }

  char event_json[PROTON_LAUNCH_INPUT_MAX_BYTES];
  memcpy(event_json, [data bytes], [data length]);
  event_json[[data length]] = '\0';
  proton_engine_platform_event_enqueue_json(event_json);
}

@interface ProtonLaunchInputDelegate : NSObject <NSApplicationDelegate>
@end

@implementation ProtonLaunchInputDelegate

- (void)application:(NSApplication *)application
            openURLs:(NSArray<NSURL *> *)urls {
  (void)application;
  NSMutableArray<NSString *> *values = [NSMutableArray array];
  for (NSURL *url in urls) {
    NSString *value = [url absoluteString];
    if (value != nil) {
      [values addObject:value];
    }
  }
  if ([values count] > 0) {
    proton_engine_launch_input_enqueue(@"open_urls", values);
  }
}

- (void)application:(NSApplication *)application
           openFiles:(NSArray<NSString *> *)filenames {
  proton_engine_launch_input_enqueue(@"open_files", filenames);
  [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
  (void)application;
  (void)hasVisibleWindows;
  proton_engine_launch_input_enqueue(@"reopen", nil);
  return YES;
}

@end

static ProtonLaunchInputDelegate *g_launch_input_delegate = nil;

void proton_engine_launch_input_install(void) {
  if (g_launch_input_delegate == nil) {
    g_launch_input_delegate = [[ProtonLaunchInputDelegate alloc] init];
  }
  [NSApp setDelegate:g_launch_input_delegate];
}

#endif
