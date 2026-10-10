#include "devtools.h"
#include "../../proton_event.h"
#include "include/capi/cef_devtools_message_observer_capi.h"
#include "message.h"
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <stdatomic.h>
#endif

/* Callbacks, enqueue/dequeue, and explicit close run on the owner/UI thread.
   CEF may release its observer reference on another thread. No callback enters
   MoonBit. Queue credits keep native events bounded even before MoonBit polls.
 */
struct proton_devtools {
  cef_dev_tools_message_observer_t observer;
#ifdef _WIN32
  volatile LONG refs;
#else
  atomic_int refs;
#endif
  cef_registration_t *registration;
  int64_t window, view, token;
  size_t queued_bytes;
  unsigned queued_count;
  int stopped;
};

typedef struct {
  proton_devtools_t *session;
  size_t size;
} proton_devtools_credit_t;

static void CEF_CALLBACK devtools_add_ref(cef_base_ref_counted_t *base) {
  proton_devtools_t *session = (proton_devtools_t *)base;
#ifdef _WIN32
  InterlockedIncrement(&session->refs);
#else
  atomic_fetch_add_explicit(&session->refs, 1, memory_order_relaxed);
#endif
}
static int CEF_CALLBACK devtools_release(cef_base_ref_counted_t *base) {
  proton_devtools_t *session = (proton_devtools_t *)base;
#ifdef _WIN32
  int refs = InterlockedDecrement(&session->refs);
#else
  int refs =
      atomic_fetch_sub_explicit(&session->refs, 1, memory_order_acq_rel) - 1;
#endif
  if (refs == 0) {
    free(session);
    return 1;
  }
  return 0;
}
static int devtools_refs(proton_devtools_t *session) {
#ifdef _WIN32
  return InterlockedCompareExchange(&session->refs, 0, 0);
#else
  return atomic_load_explicit(&session->refs, memory_order_acquire);
#endif
}
static int CEF_CALLBACK devtools_one_ref(cef_base_ref_counted_t *base) {
  return devtools_refs((proton_devtools_t *)base) == 1;
}
static int CEF_CALLBACK devtools_any_ref(cef_base_ref_counted_t *base) {
  return devtools_refs((proton_devtools_t *)base) > 0;
}
static void devtools_credit_release(void *payload) {
  proton_devtools_credit_t *credit = payload;
  credit->session->queued_bytes -= credit->size;
  credit->session->queued_count--;
  devtools_release(&credit->session->observer.base);
  free(credit);
}
static void devtools_fail(proton_devtools_t *session, const char *detail) {
  if (session->stopped) {
    return;
  }
  session->stopped = 1;
  proton_event_t *event = proton_event_create(PROTON_EVENT_DEVTOOLS_MESSAGE);
  if (event == NULL) {
    return;
  }
  event->window = session->window;
  event->view = session->view;
  event->request_id = session->token;
  event->bool_a = 1;
  if (!proton_event_set_text(&event->text_a, detail)) {
    proton_event_destroy(event);
    return;
  }
  proton_event_publish(event);
}
static int CEF_CALLBACK devtools_message(cef_dev_tools_message_observer_t *self,
                                         cef_browser_t *browser,
                                         const void *message, size_t size) {
  (void)browser;
  proton_devtools_t *session = (proton_devtools_t *)self;
  if (session->stopped) {
    return 1;
  }
  if (size > 2 * 1024 * 1024 || session->queued_count >= 256 ||
      session->queued_bytes + size > 16 * 1024 * 1024) {
    devtools_fail(session, "DevTools inbound queue limit exceeded");
    return 1;
  }
  proton_event_t *event = proton_event_create(PROTON_EVENT_DEVTOOLS_MESSAGE);
  proton_devtools_credit_t *credit = malloc(sizeof(*credit));
  char *copy = malloc(size + 1);
  if (event == NULL || credit == NULL || copy == NULL) {
    if (event != NULL) {
      proton_event_destroy(event);
    }
    free(credit);
    free(copy);
    devtools_fail(session, "Could not copy DevTools message");
    return 1;
  }
  memcpy(copy, message, size);
  copy[size] = '\0';
  event->window = session->window;
  event->view = session->view;
  event->request_id = session->token;
  event->text_a = copy;
  credit->session = session;
  credit->size = size;
  devtools_add_ref(&session->observer.base);
  session->queued_count++;
  session->queued_bytes += size;
  event->payload = credit;
  event->destroy_payload = devtools_credit_release;
  proton_event_publish(event);
  return 1;
}
static void CEF_CALLBACK devtools_detached(
    cef_dev_tools_message_observer_t *self, cef_browser_t *browser) {
  (void)browser;
  devtools_fail((proton_devtools_t *)self, "DevTools agent detached");
}
int64_t proton_devtools_token(proton_devtools_t *session) {
  return session->token;
}
void proton_devtools_close(proton_devtools_t **slot) {
  proton_devtools_t *session = *slot;
  if (session == NULL) {
    return;
  }
  *slot = NULL;
  session->stopped = 1;
  if (session->registration != NULL) {
    session->registration->base.release(&session->registration->base);
    session->registration = NULL;
  }
  devtools_release(&session->observer.base);
}
int32_t proton_devtools_open(proton_devtools_t **out, cef_browser_t *browser,
                             int64_t window, int64_t view, int64_t token,
                             char *error, size_t error_len) {
  if (*out != NULL) {
    proton_engine_set_message(
        error, error_len,
        "A native DevTools session is already attached to this page");
    return PROTON_ERR_BUSY;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_devtools_t *session = calloc(1, sizeof(*session));
  if (session == NULL) {
    host->base.release(&host->base);
    return PROTON_ERR_PLATFORM;
  }
  session->observer.base.size = sizeof(session->observer);
  session->observer.base.add_ref = devtools_add_ref;
  session->observer.base.release = devtools_release;
  session->observer.base.has_one_ref = devtools_one_ref;
  session->observer.base.has_at_least_one_ref = devtools_any_ref;
#ifdef _WIN32
  session->refs = 1;
#else
  atomic_init(&session->refs, 1);
#endif
  session->observer.on_dev_tools_message = devtools_message;
  session->observer.on_dev_tools_agent_detached = devtools_detached;
  session->window = window;
  session->view = view;
  session->token = token;
  session->registration =
      host->add_dev_tools_message_observer(host, &session->observer);
  host->base.release(&host->base);
  if (session->registration == NULL) {
    devtools_release(&session->observer.base);
    proton_engine_set_message(error, error_len,
                              "Could not attach DevTools observer");
    return PROTON_ERR_ENGINE;
  }
  *out = session;
  return PROTON_OK;
}
int32_t proton_devtools_send(proton_devtools_t *session, cef_browser_t *browser,
                             int64_t token, const char *message, char *error,
                             size_t error_len) {
  if (session == NULL || session->token != token || session->stopped) {
    proton_engine_set_message(error, error_len, "DevTools session is closed");
    return PROTON_ERR_ENGINE;
  }
  cef_browser_host_t *host = browser->get_host(browser);
  if (host == NULL) {
    return PROTON_ERR_NOT_INITIALIZED;
  }
  int accepted = host->send_dev_tools_message(host, message, strlen(message));
  host->base.release(&host->base);
  if (!accepted) {
    proton_engine_set_message(error, error_len,
                              "DevTools command was not accepted");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}
