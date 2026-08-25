#if defined(__APPLE__)

#include "../../proton_engine.h"
#include "../../proton_event.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES 65536
static NSString *const ProtonNotificationPayloadKey = @"proton_payload";

static void proton_notification_complete(BOOL delivered, NSError *error) {
  NSString *message =
      error != nil ? [error localizedDescription]
                   : (delivered ? @"" : @"notification permission denied");
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_NOTIFICATION_RESULT);
  const char *text = [message UTF8String];
  if (event == NULL || !proton_event_set_text(&event->text_a, text)) {
    proton_event_destroy(event);
    return;
  }
  event->bool_a = delivered;
  (void)proton_event_publish(event);
}

static void proton_notification_set_message(char *error,
                                            size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message);
  }
}

static void proton_notification_publish_click(NSString *payload,
                                               int32_t has_payload) {
  proton_event_t *event =
      proton_event_create(PROTON_EVENT_NOTIFICATION_CLICKED);
  if (event == NULL) {
    return;
  }
  event->bool_a = has_payload;
  if (has_payload &&
      !proton_event_set_text(&event->text_a, [payload UTF8String])) {
    proton_event_destroy(event);
    return;
  }
  (void)proton_event_publish(event);
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
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))
                                   completionHandler {
  (void)center;
  (void)notification;
  completionHandler(UNNotificationPresentationOptionBanner |
                    UNNotificationPresentationOptionList |
                    UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  if ([response.actionIdentifier
          isEqualToString:UNNotificationDefaultActionIdentifier]) {
    id payload = [response.notification.request.content.userInfo
        objectForKey:ProtonNotificationPayloadKey];
    int32_t has_payload = [payload isKindOfClass:[NSString class]] ? 1 : 0;
    proton_notification_publish_click(has_payload ? (NSString *)payload : nil,
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
  *out_supported = [[NSBundle mainBundle] bundleIdentifier] != nil ? 1 : 0;
  return PROTON_OK;
}

int32_t proton_engine_notification_show(const char *title_utf8,
                                        const char *body_utf8,
                                        const char *payload_utf8,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len) {
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
      if (authorization_error != nil) {
        proton_notification_complete(NO, authorization_error);
        return;
      }
      if (!granted) {
        proton_notification_complete(NO, nil);
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
        [center
            addNotificationRequest:request
             withCompletionHandler:^(NSError *delivery_error) {
               proton_notification_complete(delivery_error == nil,
                                            delivery_error);
             }];
      }
    }];
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_cleanup(char *error, size_t error_len) {
  if (g_notification_delegate != nil) {
    UNUserNotificationCenter *center =
        [UNUserNotificationCenter currentNotificationCenter];
    if ([center delegate] == g_notification_delegate) {
      [center setDelegate:nil];
    }
  }
  return PROTON_OK;
}

#endif
