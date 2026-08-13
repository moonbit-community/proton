#include "../src/proton_config.h"

#include <stdio.h>
#include <string.h>

int32_t proton_set_error(int32_t code, const char *message) {
  (void)message;
  return code;
}

static int fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  return 1;
}

int main(void) {
  char helper[4096] = {0};
  if (!proton_config_macos_bundle_helper_path(
          "/Applications/Example App.app/Contents/MacOS/example-app", helper,
          sizeof(helper)) ||
      strcmp(helper,
             "/Applications/Example App.app/Contents/Frameworks/"
             "Example App Helper.app/Contents/MacOS/Example App Helper") !=
          0) {
    return fail("failed to derive the packaged macOS helper path");
  }
  if (proton_config_macos_bundle_helper_path(
          "/tmp/example-app", helper, sizeof(helper))) {
    return fail("accepted an executable outside a macOS app bundle");
  }
  char tiny[8] = {0};
  if (proton_config_macos_bundle_helper_path(
          "/Applications/Example.app/Contents/MacOS/example", tiny,
          sizeof(tiny))) {
    return fail("accepted an output buffer too small for the helper path");
  }
  return 0;
}
