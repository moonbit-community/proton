#include "../../src/engine/cef_common/devtools.h"
#include "../../src/proton_event.h"
#include "moonbit.h"
#include <stddef.h>
#include <string.h>

#define CHECK(value)                                                           \
  do {                                                                         \
    if (!(value))                                                              \
      return __LINE__;                                                         \
  } while (0)
typedef struct {
  cef_browser_t browser;
  cef_browser_host_t host;
  cef_registration_t registration;
  cef_dev_tools_message_observer_t *observer;
  int host_refs, registrations, sends;
  proton_event_queue_t queue;
} fixture_t;

static fixture_t *from_host(cef_base_ref_counted_t *base) {
  return (fixture_t *)((char *)base - offsetof(fixture_t, host));
}
static void CEF_CALLBACK host_add_ref(cef_base_ref_counted_t *base) {
  from_host(base)->host_refs++;
}
static int CEF_CALLBACK host_release(cef_base_ref_counted_t *base) {
  from_host(base)->host_refs--;
  return 0;
}
static cef_browser_host_t *CEF_CALLBACK get_host(cef_browser_t *browser) {
  fixture_t *f = (fixture_t *)browser;
  host_add_ref(&f->host.base);
  return &f->host;
}
static int CEF_CALLBACK registration_release(cef_base_ref_counted_t *base) {
  fixture_t *f =
      (fixture_t *)((char *)base - offsetof(fixture_t, registration));
  f->registrations--;
  f->observer->base.release(&f->observer->base);
  f->observer = NULL;
  return 1;
}
static cef_registration_t *CEF_CALLBACK add_observer(
    cef_browser_host_t *host, cef_dev_tools_message_observer_t *observer) {
  fixture_t *f = from_host(&host->base);
  f->registrations++;
  f->observer = observer;
  observer->base.add_ref(&observer->base);
  return &f->registration;
}
static int CEF_CALLBACK send_message(cef_browser_host_t *host,
                                     const void *message, size_t size) {
  fixture_t *f = from_host(&host->base);
  if (size == 0 || message == NULL) {
    return 0;
  }
  f->sends++;
  return 1;
}
static bool enqueue(void *data, proton_event_t *event) {
  fixture_t *f = data;
  return proton_event_queue_push(&f->queue, event);
}
MOONBIT_FFI_EXPORT int32_t moonbit_proton_devtools_test_lifetime(void) {
  fixture_t f = {0};
  f.browser.get_host = get_host;
  f.host.base.add_ref = host_add_ref;
  f.host.base.release = host_release;
  f.host.add_dev_tools_message_observer = add_observer;
  f.host.send_dev_tools_message = send_message;
  f.registration.base.release = registration_release;
  CHECK(proton_event_queue_init(&f.queue));
  proton_event_bind_sink(enqueue, &f);
  proton_devtools_t *session = NULL;
  char error[512] = {0};
  CHECK(proton_devtools_open(&session, &f.browser, 4, 9, 1, error,
                             sizeof(error)) == PROTON_OK);
  CHECK(f.host_refs == 0 && f.registrations == 1);
  CHECK(proton_devtools_open(&session, &f.browser, 4, 9, 2, error,
                             sizeof(error)) != PROTON_OK);
  CHECK(proton_devtools_send(session, &f.browser, 2, "{}", error,
                             sizeof(error)) != PROTON_OK);
  CHECK(proton_devtools_send(session, &f.browser, 1, "{}", error,
                             sizeof(error)) == PROTON_OK);
  CHECK(f.sends == 1);
  const char *reply = "{\"id\":1,\"result\":{}}";
  f.observer->on_dev_tools_message(f.observer, &f.browser, reply,
                                   strlen(reply));
  proton_event_t *event = proton_event_queue_pop(&f.queue);
  CHECK(event && event->window == 4 && event->view == 9 &&
        event->request_id == 1);
  CHECK(strcmp(event->text_a, reply) == 0);
  proton_event_destroy(event);
  // Queued messages own the observer until dequeue, even after native close.
  for (int i = 0; i < 256; i++) {
    f.observer->on_dev_tools_message(f.observer, &f.browser, "{}", 2);
  }
  CHECK(proton_event_queue_count(&f.queue) == 256);
  f.observer->on_dev_tools_message(f.observer, &f.browser, "{}", 2);
  CHECK(proton_event_queue_count(&f.queue) == 257);
  CHECK(proton_devtools_send(session, &f.browser, 1, "{}", error,
                             sizeof(error)) != PROTON_OK);
  cef_dev_tools_message_observer_t *late = f.observer;
  late->base.add_ref(&late->base);
  proton_devtools_close(&session);
  CHECK(session == NULL && f.registrations == 0);
  late->on_dev_tools_message(late, &f.browser, "{}", 2);
  CHECK(proton_event_queue_count(&f.queue) == 257);
  while ((event = proton_event_queue_pop(&f.queue)) != NULL) {
    proton_event_destroy(event);
  }
  CHECK(late->base.has_one_ref(&late->base));
  CHECK(late->base.release(&late->base) == 1);
  proton_devtools_close(&session);
  CHECK(proton_devtools_open(&session, &f.browser, 4, 9, 2, error,
                             sizeof(error)) == PROTON_OK);
  // Oversize is rejected before touching or allocating the payload.
  f.observer->on_dev_tools_message(f.observer, &f.browser, "x",
                                   2 * 1024 * 1024 + 1);
  event = proton_event_queue_pop(&f.queue);
  CHECK(event && event->bool_a && event->request_id == 2);
  proton_event_destroy(event);
  proton_devtools_close(&session);
  CHECK(f.registrations == 0 && f.host_refs == 0);
  CHECK(proton_devtools_open(&session, &f.browser, 4, 9, 3, error,
                             sizeof(error)) == PROTON_OK);
  f.observer->on_dev_tools_agent_detached(f.observer, &f.browser);
  event = proton_event_queue_pop(&f.queue);
  CHECK(event && event->bool_a && event->request_id == 3);
  proton_event_destroy(event);
  proton_devtools_close(&session);
  proton_event_unbind_sink(&f);
  proton_event_queue_destroy(&f.queue);
  return 0;
}
