#include "../../src/engine/cef_common/browser_lifecycle.h"

#include "moonbit.h"

#include <stdio.h>
#include <string.h>

typedef struct {
  cef_browser_host_t host;
  int accessibility_calls;
  cef_state_t accessibility_state;
} proton_test_browser_host_t;

typedef struct {
  cef_browser_t browser;
  proton_test_browser_host_t host;
  int identifier;
} proton_test_browser_t;

static void CEF_CALLBACK proton_test_add_ref(cef_base_ref_counted_t *base) {
  (void)base;
}

static int CEF_CALLBACK proton_test_release(cef_base_ref_counted_t *base) {
  (void)base;
  return 0;
}

static int CEF_CALLBACK proton_test_browser_identifier(cef_browser_t *self) {
  return ((proton_test_browser_t *)self)->identifier;
}

static cef_browser_host_t *CEF_CALLBACK
proton_test_browser_get_host(cef_browser_t *self) {
  proton_test_browser_host_t *host = &((proton_test_browser_t *)self)->host;
  return &host->host;
}

static void CEF_CALLBACK proton_test_set_accessibility_state(
    cef_browser_host_t *self, cef_state_t state) {
  proton_test_browser_host_t *host = (proton_test_browser_host_t *)self;
  host->accessibility_calls++;
  host->accessibility_state = state;
}

static void proton_test_browser_init(proton_test_browser_t *browser,
                                     int identifier) {
  memset(browser, 0, sizeof(*browser));
  browser->browser.base.size = sizeof(browser->browser);
  browser->browser.base.add_ref = proton_test_add_ref;
  browser->browser.base.release = proton_test_release;
  browser->browser.get_identifier = proton_test_browser_identifier;
  browser->browser.get_host = proton_test_browser_get_host;
  browser->host.host.base.size = sizeof(browser->host.host);
  browser->host.host.base.add_ref = proton_test_add_ref;
  browser->host.host.base.release = proton_test_release;
  browser->host.host.set_accessibility_state =
      proton_test_set_accessibility_state;
  browser->identifier = identifier;
}

static moonbit_bytes_t proton_test_copy_trace(const char *trace) {
  size_t length = strlen(trace);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, trace, length);
  return result;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t
proton_test_browser_accessibility_lifecycle_trace(void) {
  proton_test_browser_t first;
  proton_test_browser_t second;
  proton_test_browser_init(&first, 1);
  proton_test_browser_init(&second, 2);

  proton_browser_registry_t *registry =
      proton_browser_registry_create(NULL, NULL);
  proton_browser_registry_set_accessibility_state(registry, STATE_ENABLED);
  proton_browser_lifecycle_t *first_lifecycle =
      proton_browser_lifecycle_create(registry, PROTON_BROWSER_ROLE_MAIN, NULL,
                                      NULL);
  proton_browser_lifecycle_on_after_created(first_lifecycle, &first.browser);
  int first_initial_calls = first.host.accessibility_calls;
  cef_state_t first_initial_state = first.host.accessibility_state;

  proton_browser_registry_set_accessibility_state(registry, STATE_DISABLED);
  proton_browser_lifecycle_t *second_lifecycle =
      proton_browser_lifecycle_create(registry, PROTON_BROWSER_ROLE_VIEW, NULL,
                                      NULL);
  proton_browser_lifecycle_on_after_created(second_lifecycle, &second.browser);

  char trace[192];
  snprintf(trace, sizeof(trace),
           "first_initial=%d:%d,first_updated=%d:%d,second_initial=%d:%d",
           first_initial_calls, first_initial_state,
           first.host.accessibility_calls, first.host.accessibility_state,
           second.host.accessibility_calls, second.host.accessibility_state);
  proton_browser_registry_destroy(registry);
  return proton_test_copy_trace(trace);
}
