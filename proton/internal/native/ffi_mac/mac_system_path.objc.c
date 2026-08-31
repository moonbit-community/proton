#if defined(__APPLE__)

#include "../ffi/src/proton_internal.h"

#import <Foundation/Foundation.h>

#include <stdint.h>
#include <string.h>

static NSSearchPathDirectory proton_system_path_macos_directory(int32_t kind) {
  switch (kind) {
  case PROTON_SYSTEM_PATH_DESKTOP:
    return NSDesktopDirectory;
  case PROTON_SYSTEM_PATH_DOCUMENTS:
    return NSDocumentDirectory;
  case PROTON_SYSTEM_PATH_DOWNLOADS:
    return NSDownloadsDirectory;
  case PROTON_SYSTEM_PATH_MUSIC:
    return NSMusicDirectory;
  case PROTON_SYSTEM_PATH_PICTURES:
    return NSPicturesDirectory;
  case PROTON_SYSTEM_PATH_VIDEOS:
    return NSMoviesDirectory;
  default:
    return NSAllApplicationsDirectory;
  }
}

int32_t proton_system_path(int32_t kind, char *buffer, int32_t buffer_len,
                           int32_t *out_required_len) {
  if (out_required_len == NULL || buffer_len < 0 ||
      (buffer == NULL && buffer_len != 0)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid system path output buffer");
  }
  *out_required_len = 0;
  NSSearchPathDirectory directory = proton_system_path_macos_directory(kind);
  if (directory == NSAllApplicationsDirectory) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "unsupported system path kind");
  }
  @autoreleasepool {
    NSArray<NSString *> *paths =
        NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    NSString *path = [paths firstObject];
    const char *utf8 = [path UTF8String];
    if (utf8 == NULL || utf8[0] == '\0') {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "macOS system path query returned no value");
    }
    size_t required = strlen(utf8);
    if (required > INT32_MAX) {
      return proton_set_error(PROTON_ERR_PLATFORM,
                              "macOS system path is too long");
    }
    *out_required_len = (int32_t)required;
    if (buffer == NULL || buffer_len <= (int32_t)required) {
      return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                              "system path buffer is too small");
    }
    memcpy(buffer, utf8, required + 1);
  }
  return proton_set_error(PROTON_OK, NULL);
}

#endif
