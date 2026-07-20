#include <stdint.h>
#include <string.h>

#include "moonbit.h"

#ifdef __APPLE__

#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>

// Carry framework dependencies with the native-stub object so MoonBit apps
// that consume the extension do not need to repeat platform linker flags.
__asm__(".linker_option \"-framework\", \"Cocoa\"");
__asm__(".linker_option \"-framework\", \"UserNotifications\"");

#include <pthread.h>

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

static int32_t proton_notification_install_delegate(void) {
  UNUserNotificationCenter *center =
      [UNUserNotificationCenter currentNotificationCenter];
  if (g_notification_delegate == nil) {
    g_notification_delegate = [[ProtonNotificationDelegate alloc] init];
  }
  if ([center delegate] != nil && [center delegate] != g_notification_delegate) {
    return -3;
  }
  [center setDelegate:g_notification_delegate];
  return 0;
}

MOONBIT_FFI_EXPORT int32_t extensions_notification_is_supported(void) {
  return [[NSBundle mainBundle] bundleIdentifier] != nil ? 1 : 0;
}

MOONBIT_FFI_EXPORT int32_t extensions_notification_show(
    moonbit_bytes_t title_bytes,
    moonbit_bytes_t body_bytes,
    moonbit_bytes_t payload_bytes,
    int32_t has_payload) {
  if ([[NSBundle mainBundle] bundleIdentifier] == nil) {
    return -2;
  }

  @autoreleasepool {
    NSString *title = [NSString stringWithUTF8String:(const char *)title_bytes];
    NSString *body = [NSString stringWithUTF8String:(const char *)body_bytes];
    NSString *payload =
        [NSString stringWithUTF8String:(const char *)payload_bytes];
    if (title == nil || body == nil || payload == nil) {
      return -4;
    }
    if (strlen((const char *)payload_bytes) >=
        PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES) {
      return -5;
    }

    int32_t delegate_status = proton_notification_install_delegate();
    if (delegate_status < 0) {
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
  return 0;
}

MOONBIT_FFI_EXPORT int32_t extensions_notification_take_click(
    moonbit_bytes_t buffer,
    int32_t buffer_len,
    int32_t *out_has_payload) {
  if (out_has_payload == NULL) {
    return -4;
  }
  *out_has_payload = 0;
  pthread_mutex_lock(&g_notification_click_lock);
  if (g_notification_click_count == 0) {
    pthread_mutex_unlock(&g_notification_click_lock);
    return 0;
  }

  const char *payload = g_notification_clicks[g_notification_click_head].payload;
  size_t required = strlen(payload) + 1;
  if (buffer == NULL || buffer_len < 0 || (size_t)buffer_len < required) {
    pthread_mutex_unlock(&g_notification_click_lock);
    return -6;
  }
  memcpy(buffer, payload, required);
  *out_has_payload =
      g_notification_clicks[g_notification_click_head].has_payload;
  g_notification_click_head =
      (g_notification_click_head + 1) % PROTON_NOTIFICATION_MAX_CLICKS;
  g_notification_click_count--;
  pthread_mutex_unlock(&g_notification_click_lock);
  return (int32_t)required;
}

MOONBIT_FFI_EXPORT void extensions_notification_cleanup(void) {
  UNUserNotificationCenter *center =
      [UNUserNotificationCenter currentNotificationCenter];
  if ([center delegate] == g_notification_delegate) {
    [center setDelegate:nil];
  }
  pthread_mutex_lock(&g_notification_click_lock);
  g_notification_click_head = 0;
  g_notification_click_count = 0;
  pthread_mutex_unlock(&g_notification_click_lock);
}

#else

// TODO: Implement the notification extension backend on Windows and Linux.
MOONBIT_FFI_EXPORT int32_t extensions_notification_is_supported(void) {
  return 0;
}

MOONBIT_FFI_EXPORT int32_t extensions_notification_show(
    moonbit_bytes_t title,
    moonbit_bytes_t body,
    moonbit_bytes_t payload,
    int32_t has_payload) {
  (void)title;
  (void)body;
  (void)payload;
  (void)has_payload;
  return -1;
}

MOONBIT_FFI_EXPORT int32_t extensions_notification_take_click(
    moonbit_bytes_t buffer,
    int32_t buffer_len,
    int32_t *out_has_payload) {
  (void)buffer;
  (void)buffer_len;
  if (out_has_payload != NULL) {
    *out_has_payload = 0;
  }
  return 0;
}

MOONBIT_FFI_EXPORT void extensions_notification_cleanup(void) {}

#endif
