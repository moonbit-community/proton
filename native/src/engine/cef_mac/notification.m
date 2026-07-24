#include "../../app_runner.h"
#include "../../proton_engine.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_NOTIFICATION_MAX_CLICKS 16
#define PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES 65536

typedef struct {
  char payload[PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES];
  int32_t has_payload;
} proton_notification_click_t;

static proton_notification_click_t
    g_notification_clicks[PROTON_NOTIFICATION_MAX_CLICKS];
static uint32_t g_notification_click_head = 0;
static uint32_t g_notification_click_count = 0;
static pthread_mutex_t g_notification_click_lock = PTHREAD_MUTEX_INITIALIZER;
static NSString *const ProtonNotificationPayloadKey = @"proton_payload";

static void proton_notification_set_message(char *error,
                                            size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message);
  }
}

static void proton_notification_enqueue_click(NSString *payload,
                                               int32_t has_payload) {
  const char *utf8 = payload != nil ? [payload UTF8String] : "";
  size_t payload_len = utf8 != NULL ? strlen(utf8) : 0;
  if (utf8 == NULL || payload_len >= PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES) {
    return;
  }

  pthread_mutex_lock(&g_notification_click_lock);
  if (g_notification_click_count == PROTON_NOTIFICATION_MAX_CLICKS) {
    g_notification_click_head =
        (g_notification_click_head + 1) % PROTON_NOTIFICATION_MAX_CLICKS;
    g_notification_click_count--;
  }
  uint32_t index =
      (g_notification_click_head + g_notification_click_count) %
      PROTON_NOTIFICATION_MAX_CLICKS;
  memcpy(g_notification_clicks[index].payload, utf8, payload_len + 1);
  g_notification_clicks[index].has_payload = has_payload;
  g_notification_click_count++;
  pthread_mutex_unlock(&g_notification_click_lock);
}

static void proton_notification_reveal_app(void) {
  [NSApp activateIgnoringOtherApps:YES];
  NSWindow *front = nil;
  for (NSWindow *window in [NSApp windows]) {
    if ([window isMiniaturized]) {
      [window deminiaturize:nil];
    }
    if (front == nil && [window canBecomeKeyWindow] && [window isVisible]) {
      front = window;
    }
  }
  if (front != nil) {
    [front makeKeyAndOrderFront:nil];
  }
}

@interface ProtonNotificationDelegate
    : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation ProtonNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  if ([response.actionIdentifier
          isEqualToString:UNNotificationDefaultActionIdentifier]) {
    id payload = [response.notification.request.content.userInfo
        objectForKey:ProtonNotificationPayloadKey];
    int32_t has_payload = [payload isKindOfClass:[NSString class]] ? 1 : 0;
    proton_notification_enqueue_click(has_payload ? (NSString *)payload : nil,
                                      has_payload);
    dispatch_async(dispatch_get_main_queue(), ^{
      proton_notification_reveal_app();
    });
  }
  completionHandler();
}

@end

static ProtonNotificationDelegate *g_notification_delegate = nil;

static int32_t proton_notification_install_delegate(char *error,
                                                    size_t error_len) {
  UNUserNotificationCenter *center =
      [UNUserNotificationCenter currentNotificationCenter];
  if (g_notification_delegate == nil) {
    g_notification_delegate = [[ProtonNotificationDelegate alloc] init];
  }
  if ([center delegate] != nil && [center delegate] != g_notification_delegate) {
    proton_notification_set_message(
        error, error_len,
        "another component already owns the app notification delegate");
    return PROTON_ERR_ALREADY_INITIALIZED;
  }
  [center setDelegate:g_notification_delegate];
  return PROTON_OK;
}

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len) {
  if (!pthread_main_np()) {
    return proton_app_dispatch_sync_int(^{
      return proton_engine_notification_is_supported(out_supported, error,
                                                     error_len);
    });
  }
  *out_supported = [[NSBundle mainBundle] bundleIdentifier] != nil ? 1 : 0;
  return PROTON_OK;
}

int32_t proton_engine_notification_show(const char *title_utf8,
                                        const char *body_utf8,
                                        const char *payload_utf8,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len) {
  if (!pthread_main_np()) {
    return proton_app_dispatch_sync_int(^{
      return proton_engine_notification_show(title_utf8, body_utf8,
                                             payload_utf8, has_payload, error,
                                             error_len);
    });
  }
  if ([[NSBundle mainBundle] bundleIdentifier] == nil) {
    proton_notification_set_message(
        error, error_len,
        "notifications require an app bundle with a bundle identifier");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  if (strlen(payload_utf8) >= PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES) {
    proton_notification_set_message(
        error, error_len,
        "notification payload exceeds 65535 UTF-8 bytes");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  @autoreleasepool {
    NSString *title = [NSString stringWithUTF8String:title_utf8];
    NSString *body = [NSString stringWithUTF8String:body_utf8];
    NSString *payload = [NSString stringWithUTF8String:payload_utf8];
    if (title == nil || body == nil || payload == nil) {
      proton_notification_set_message(
          error, error_len,
          "notification title, body, or payload is invalid UTF-8");
      return PROTON_ERR_INVALID_ARGUMENT;
    }

    int32_t delegate_status =
        proton_notification_install_delegate(error, error_len);
    if (delegate_status != PROTON_OK) {
      return delegate_status;
    }

    UNUserNotificationCenter *center =
        [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                             UNAuthorizationOptionSound)
                          completionHandler:^(BOOL granted,
                                              NSError *authorization_error) {
      (void)authorization_error;
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
        if (has_payload) {
          [content setUserInfo:@{ProtonNotificationPayloadKey : payload}];
        }
        UNNotificationRequest *request = [UNNotificationRequest
            requestWithIdentifier:[[NSUUID UUID] UUIDString]
                          content:content
                          trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:nil];
      }
    }];
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_poll_click(
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required,
    int32_t *out_has_payload,
    int32_t *out_available,
    char *error,
    size_t error_len) {
  *out_required = 0;
  *out_has_payload = 0;
  *out_available = 0;

  pthread_mutex_lock(&g_notification_click_lock);
  if (g_notification_click_count == 0) {
    pthread_mutex_unlock(&g_notification_click_lock);
    return PROTON_OK;
  }

  const proton_notification_click_t *click =
      &g_notification_clicks[g_notification_click_head];
  size_t required = strlen(click->payload) + 1;
  if (required > INT32_MAX) {
    pthread_mutex_unlock(&g_notification_click_lock);
    proton_notification_set_message(error, error_len,
                                    "notification click payload is too large");
    return PROTON_ERR_ENGINE;
  }
  *out_required = (int32_t)required;
  *out_has_payload = click->has_payload;
  *out_available = 1;
  if (buffer == NULL || buffer_len < *out_required) {
    pthread_mutex_unlock(&g_notification_click_lock);
    proton_notification_set_message(error, error_len,
                                    "notification click buffer is too small");
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }

  memcpy(buffer, click->payload, required);
  g_notification_click_head =
      (g_notification_click_head + 1) % PROTON_NOTIFICATION_MAX_CLICKS;
  g_notification_click_count--;
  pthread_mutex_unlock(&g_notification_click_lock);
  return PROTON_OK;
}

int32_t proton_engine_notification_cleanup(char *error, size_t error_len) {
  if (!pthread_main_np()) {
    return proton_app_dispatch_sync_int(^{
      return proton_engine_notification_cleanup(error, error_len);
    });
  }
  if (g_notification_delegate != nil) {
    UNUserNotificationCenter *center =
        [UNUserNotificationCenter currentNotificationCenter];
    if ([center delegate] == g_notification_delegate) {
      [center setDelegate:nil];
    }
  }
  pthread_mutex_lock(&g_notification_click_lock);
  g_notification_click_head = 0;
  g_notification_click_count = 0;
  pthread_mutex_unlock(&g_notification_click_lock);
  return PROTON_OK;
}
