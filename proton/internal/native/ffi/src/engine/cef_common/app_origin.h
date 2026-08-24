#ifndef PROTON_ENGINE_CEF_COMMON_APP_ORIGIN_H
#define PROTON_ENGINE_CEF_COMMON_APP_ORIGIN_H

#include <string.h>

/* Application resources use a host-scoped HTTPS factory so browser features
   and vendored web applications observe an ordinary secure origin. Keep the
   proton scheme for framework-internal transport only. */
#define PROTON_ENGINE_APP_SCHEME "https"
#define PROTON_ENGINE_APP_DOMAIN "proton.localhost"
#define PROTON_ENGINE_APP_ORIGIN "https://proton.localhost"
#define PROTON_ENGINE_APP_URL_PREFIX PROTON_ENGINE_APP_ORIGIN "/"

static int proton_engine_url_is_app(const char *url) {
  static const char origin[] = PROTON_ENGINE_APP_ORIGIN;
  if (url == NULL || strncmp(url, origin, sizeof(origin) - 1) != 0) {
    return 0;
  }
  char suffix = url[sizeof(origin) - 1];
  return suffix == '\0' || suffix == '/' || suffix == '?' || suffix == '#';
}

/* Both names the framework answers to: the application origin above, and the
   proton scheme it still accepts for framework-internal transport. */
static int proton_engine_url_is_proton(const char *url) {
  return proton_engine_url_is_app(url) ||
         (url != NULL && strncmp(url, "proton://", 9) == 0);
}

#endif
