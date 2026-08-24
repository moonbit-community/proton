#if defined(__APPLE__)

#include "launch_input.h"
#include "../../proton_event.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

static void proton_engine_launch_input_enqueue(proton_event_kind_t kind,
                                               NSArray<NSString *> *items) {
  proton_event_t *event = proton_event_create(kind);
  if (event == NULL) {
    return;
  }
  NSUInteger count = items != nil ? [items count] : 0;
  const char **values = count > 0 ? calloc(count, sizeof(char *)) : NULL;
  if (count > 0 && values == NULL) {
    proton_event_destroy(event);
    return;
  }
  for (NSUInteger i = 0; i < count; i++) {
    values[i] = [[items objectAtIndex:i] UTF8String];
  }
  if (!proton_event_set_items(event, values, (int32_t)count)) {
    proton_event_destroy(event);
    free(values);
    return;
  }
  free(values);
  (void)proton_event_publish(event);
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
    proton_engine_launch_input_enqueue(PROTON_EVENT_OPEN_URLS, values);
  }
}

- (void)application:(NSApplication *)application
           openFiles:(NSArray<NSString *> *)filenames {
  proton_engine_launch_input_enqueue(PROTON_EVENT_OPEN_FILES, filenames);
  [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
  (void)application;
  (void)hasVisibleWindows;
  proton_engine_launch_input_enqueue(PROTON_EVENT_REOPEN, nil);
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
