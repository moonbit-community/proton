#if defined(__APPLE__)

#import "mac_internal.h"

#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

#include "../ffi/src/engine/cef_common/message.h"

#include <math.h>

/* macOS system preferences: the accent color, the animation guidance AppKit
   and the accessibility display options publish, the capture permissions
   AVFoundation tracks, and the accessibility trust state. The values follow
   Electron's systemPreferences module. Synchronous callers do not inherit
   the event-pump pool, so each query drains its own temporary objects. */

#define PROTON_SYSTEM_ACCENT_BYTES 16

static void proton_system_format_color(NSColor *color, char *buffer,
                                       int32_t buffer_len) {
  buffer[0] = '\0';
  if (color == nil) {
    return;
  }
  NSColor *converted =
      [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  if (converted == nil) {
    return;
  }
  CGFloat red = 0.0;
  CGFloat green = 0.0;
  CGFloat blue = 0.0;
  CGFloat alpha = 0.0;
  [converted getRed:&red green:&green blue:&blue alpha:&alpha];
  snprintf(buffer, (size_t)buffer_len, "%02X%02X%02X%02X",
           (unsigned int)lround(red * 255.0),
           (unsigned int)lround(green * 255.0),
           (unsigned int)lround(blue * 255.0),
           (unsigned int)lround(alpha * 255.0));
}

int32_t proton_engine_system_accent_color(char *buffer, int32_t buffer_len,
                                          char *error, size_t error_len) {
  if (buffer == NULL || buffer_len < PROTON_SYSTEM_ACCENT_BYTES) {
    proton_engine_set_message(error, error_len,
                              "accent color buffer is too small");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  @autoreleasepool {
    proton_system_format_color([NSColor controlAccentColor], buffer, buffer_len);
    return PROTON_OK;
  }
}

int32_t proton_engine_system_animation_settings(
    int32_t *out_rich_animation, int32_t *out_scroll_animations,
    int32_t *out_reduced_motion, char *error, size_t error_len) {
  if (out_rich_animation == NULL || out_scroll_animations == NULL ||
      out_reduced_motion == NULL) {
    proton_engine_set_message(error, error_len,
                              "animation setting outputs are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  @autoreleasepool {
    /* Main thread only: the runtime and every window belong to it, and AppKit
       reads the workspace state on that thread. */
    const BOOL reduce_motion =
        [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
    /* Chromium reads the scroll animation preference from the same user default
       and treats an unset value as disabled. */
    id scroll_value = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"NSScrollAnimationEnabled"];
    const BOOL scroll_animations =
        scroll_value != nil && [scroll_value boolValue];
    *out_rich_animation = reduce_motion ? 0 : 1;
    *out_scroll_animations = scroll_animations ? 1 : 0;
    *out_reduced_motion = reduce_motion ? 1 : 0;
    return PROTON_OK;
  }
}

int32_t proton_engine_system_media_access_status(int32_t media,
                                                 int32_t *out_status,
                                                 char *error,
                                                 size_t error_len) {
  if (out_status == NULL) {
    proton_engine_set_message(error, error_len,
                              "media access status output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  @autoreleasepool {
    if (media == PROTON_MEDIA_ACCESS_SCREEN) {
      /* Screen capture has no authorization status before macOS 10.15, which is
         the same "granted" fallback Electron reports. */
      if (@available(macOS 10.15, *)) {
        *out_status = CGPreflightScreenCaptureAccess()
                          ? PROTON_MEDIA_ACCESS_STATUS_GRANTED
                          : PROTON_MEDIA_ACCESS_STATUS_DENIED;
      } else {
        *out_status = PROTON_MEDIA_ACCESS_STATUS_GRANTED;
      }
      return PROTON_OK;
    }
    AVMediaType media_type = nil;
    if (media == PROTON_MEDIA_ACCESS_MICROPHONE) {
      media_type = AVMediaTypeAudio;
    } else if (media == PROTON_MEDIA_ACCESS_CAMERA) {
      media_type = AVMediaTypeVideo;
    } else {
      proton_engine_set_message(error, error_len,
                                "media access kind is invalid");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
    switch ([AVCaptureDevice authorizationStatusForMediaType:media_type]) {
    case AVAuthorizationStatusAuthorized:
      *out_status = PROTON_MEDIA_ACCESS_STATUS_GRANTED;
      break;
    case AVAuthorizationStatusDenied:
      *out_status = PROTON_MEDIA_ACCESS_STATUS_DENIED;
      break;
    case AVAuthorizationStatusRestricted:
      *out_status = PROTON_MEDIA_ACCESS_STATUS_RESTRICTED;
      break;
    case AVAuthorizationStatusNotDetermined:
    default:
      *out_status = PROTON_MEDIA_ACCESS_STATUS_NOT_DETERMINED;
      break;
    }
    return PROTON_OK;
  }
}

int32_t proton_engine_system_accessibility_client_trusted(
    int32_t prompt, int32_t *out_trusted, char *error, size_t error_len) {
  if (out_trusted == NULL) {
    proton_engine_set_message(error, error_len,
                              "accessibility trust output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  @autoreleasepool {
    NSDictionary *options = @{
      (__bridge id)kAXTrustedCheckOptionPrompt : @(prompt != 0),
    };
    *out_trusted =
        AXIsProcessTrustedWithOptions((CFDictionaryRef)options) ? 1 : 0;
    return PROTON_OK;
  }
}

#endif
