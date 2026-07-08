#include "../../proton_engine.h"

#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void proton_engine_set_message(char *error,
                                      size_t error_len,
                                      const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message != NULL ? message : "");
  }
}

static NSString *proton_engine_string_from_utf8(
    const char *value,
    int32_t value_len) {
  if (value == NULL || value_len <= 0) {
    return @"";
  }
  NSString *text = [[NSString alloc]
      initWithBytes:value
             length:(NSUInteger)value_len
           encoding:NSUTF8StringEncoding];
  return text != nil ? [text autorelease] : @"";
}

#define PROTON_ENGINE_MAX_NOTIFICATION_CLICKS 16
#define PROTON_ENGINE_MAX_NOTIFICATION_PAYLOAD_BYTES 4096
static char g_notification_clicks[PROTON_ENGINE_MAX_NOTIFICATION_CLICKS]
                                 [PROTON_ENGINE_MAX_NOTIFICATION_PAYLOAD_BYTES];
static uint32_t g_notification_click_head = 0;
static uint32_t g_notification_click_count = 0;
static pthread_mutex_t g_notification_click_lock = PTHREAD_MUTEX_INITIALIZER;

static NSString *const ProtonEngineNotificationPayloadKey = @"proton_payload";

static void proton_engine_enqueue_notification_click(NSString *payload) {
  const char *utf8 = payload != nil ? [payload UTF8String] : "";
  if (utf8 == NULL ||
      strlen(utf8) >= PROTON_ENGINE_MAX_NOTIFICATION_PAYLOAD_BYTES) {
    return;
  }
  pthread_mutex_lock(&g_notification_click_lock);
  if (g_notification_click_count < PROTON_ENGINE_MAX_NOTIFICATION_CLICKS) {
    uint32_t index =
        (g_notification_click_head + g_notification_click_count) %
        PROTON_ENGINE_MAX_NOTIFICATION_CLICKS;
    snprintf(g_notification_clicks[index],
             PROTON_ENGINE_MAX_NOTIFICATION_PAYLOAD_BYTES, "%s", utf8);
    g_notification_click_count++;
  }
  pthread_mutex_unlock(&g_notification_click_lock);
}

int32_t proton_engine_take_notification_click(char *buffer,
                                              size_t buffer_len,
                                              int32_t *out_present) {
  if (out_present == NULL) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_present = 0;
  pthread_mutex_lock(&g_notification_click_lock);
  if (g_notification_click_count > 0) {
    const char *payload = g_notification_clicks[g_notification_click_head];
    size_t payload_len = strlen(payload);
    if (buffer == NULL || buffer_len <= payload_len) {
      pthread_mutex_unlock(&g_notification_click_lock);
      return PROTON_ERR_BUFFER_TOO_SMALL;
    }
    memcpy(buffer, payload, payload_len + 1);
    g_notification_click_head =
        (g_notification_click_head + 1) % PROTON_ENGINE_MAX_NOTIFICATION_CLICKS;
    g_notification_click_count--;
    *out_present = 1;
  }
  pthread_mutex_unlock(&g_notification_click_lock);
  return PROTON_OK;
}

// Reveals the app the way clicking its Dock icon would: activate, restore
// any miniaturized windows, and bring the key candidate forward.
static void proton_engine_reveal_app_windows(void) {
  [NSApp activateIgnoringOtherApps:YES];
  NSWindow *front = nil;
  for (NSWindow *window in [NSApp windows]) {
    if ([window isMiniaturized]) {
      [window deminiaturize:nil];
    }
    if (front == nil && [window canBecomeKeyWindow] &&
        ([window isVisible] || [window isMiniaturized])) {
      front = window;
    }
  }
  if (front != nil) {
    [front makeKeyAndOrderFront:nil];
  }
}

// Routes notification clicks back to the app: the payload is queued for the
// runtime's event poll and the window is pulled forward. Foreground
// presentation is deliberately NOT implemented — the delegate default keeps
// banners suppressed while the app is frontmost, matching what users expect
// from a "task finished while I was elsewhere" notification.
@interface ProtonEngineNotificationDelegate
    : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation ProtonEngineNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  NSDictionary *user_info =
      response.notification.request.content.userInfo;
  id payload = [user_info objectForKey:ProtonEngineNotificationPayloadKey];
  if ([payload isKindOfClass:[NSString class]]) {
    proton_engine_enqueue_notification_click((NSString *)payload);
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    proton_engine_reveal_app_windows();
  });
  completionHandler();
}

@end

int32_t proton_engine_post_notification(const char *title_utf8,
                                        int32_t title_len,
                                        const char *body_utf8,
                                        int32_t body_len,
                                        const char *payload_utf8,
                                        int32_t payload_len,
                                        char *error,
                                        size_t error_len) {
  // UNUserNotificationCenter aborts with an ObjC exception outside an app
  // bundle, so refuse cleanly instead.
  if ([[NSBundle mainBundle] bundleIdentifier] == nil) {
    proton_engine_set_message(
        error, error_len,
        "notifications require an app bundle with a bundle identifier");
    return PROTON_ERR_UNSUPPORTED;
  }
  @autoreleasepool {
    NSString *title = proton_engine_string_from_utf8(title_utf8, title_len);
    NSString *body = proton_engine_string_from_utf8(body_utf8, body_len);
    NSString *payload =
        proton_engine_string_from_utf8(payload_utf8, payload_len);
    UNUserNotificationCenter *center =
        [UNUserNotificationCenter currentNotificationCenter];
    static ProtonEngineNotificationDelegate *g_notification_delegate = nil;
    static dispatch_once_t g_notification_delegate_once;
    dispatch_once(&g_notification_delegate_once, ^{
      g_notification_delegate =
          [[ProtonEngineNotificationDelegate alloc] init];
    });
    if ([center delegate] == nil) {
      [center setDelegate:g_notification_delegate];
    }
    // Repeat requests after the user has answered complete immediately
    // without UI, so asking on every post is safe. Denied permission drops
    // the notification silently — same as any other notifying app.
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                             UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted,
                                              NSError *auth_error) {
      (void)auth_error;
      if (!granted) {
        return;
      }
      @autoreleasepool {
        UNMutableNotificationContent *content =
            [[[UNMutableNotificationContent alloc] init] autorelease];
        if ([title length] > 0) {
          [content setTitle:title];
        }
        [content setBody:body];
        [content setSound:[UNNotificationSound defaultSound]];
        if ([payload length] > 0) {
          [content setUserInfo:@{
            ProtonEngineNotificationPayloadKey : payload
          }];
        }
        UNNotificationRequest *request = [UNNotificationRequest
            requestWithIdentifier:[[NSUUID UUID] UUIDString]
                          content:content
                          trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter]
            addNotificationRequest:request
             withCompletionHandler:nil];
      }
    }];
  }
  return PROTON_OK;
}

