#include "proton_app_instance.h"
#include "proton_event.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
static CRITICAL_SECTION events_lock;
#define LOCK() EnterCriticalSection(&events_lock)
#define UNLOCK() LeaveCriticalSection(&events_lock)
#else
static pthread_mutex_t events_lock = PTHREAD_MUTEX_INITIALIZER;
#define LOCK() pthread_mutex_lock(&events_lock)
#define UNLOCK() pthread_mutex_unlock(&events_lock)
#endif

// Only the event sink is substituted: transport, ownership and listener are real.
static proton_event_t *events;
static proton_event_t *events_tail;
proton_event_t *proton_event_create(proton_event_kind_t kind) {
  proton_event_t *event = calloc(1, sizeof(*event));
  if (event) event->kind = kind;
  return event;
}
bool proton_event_set_text(char **field, const char *text) {
  *field = malloc(strlen(text) + 1);
  if (*field) strcpy(*field, text);
  return *field != NULL;
}
void proton_event_destroy(proton_event_t *event) {
  if (event) { free(event->text_a); free(event); }
}
bool proton_event_publish(proton_event_t *event) {
  LOCK();
  event->next = NULL;
  if (events_tail) events_tail->next = event;
  else events = event;
  events_tail = event;
  printf("QUEUED %lld\n", (long long)event->request_id);
  UNLOCK();
  return true;
}
int main(int argc, char **argv) {
  if (argc != 2) return 2;
  setvbuf(stdout, NULL, _IONBF, 0);
#ifdef _WIN32
  InitializeCriticalSection(&events_lock);
#endif
  int64_t instance = 0;
  int32_t primary = 0;
  char error[512] = {0};
  int status = proton_app_instance_acquire_impl(argv[1], "{}", &instance,
                                               &primary, error, sizeof(error));
  printf("RESULT %d %d %s\n", status, primary, error);
  if (status != 0 || !primary) return status == 0 ? 0 : 1;
  // Releasing the lock disposes the instance, so the shutdown path below only
  // applies while this harness still owns it.
  int released = 0;
  char command[32];
  while (fgets(command, sizeof(command), stdin)) {
    if (!strncmp(command, "attach", 6)) {
      status = proton_app_instance_attach_runtime_impl(instance,
          (proton_engine_runtime_t *)(uintptr_t)1, error, sizeof(error));
      printf("ATTACH %d\n", status);
    } else if (!strncmp(command, "pump", 4)) {
      LOCK();
      proton_event_t *head = events;
      events = NULL;
      events_tail = NULL;
      UNLOCK();
      while (head) {
        proton_event_t *next = head->next;
        if (head->request_id != 0) {
          printf("ACCEPT %lld %d\n", (long long)head->request_id, proton_app_instance_respond_activation_impl(
              instance, head->request_id, 1));
        }
        proton_event_destroy(head);
        head = next;
      }
      puts("PUMPED");
    } else if (!strncmp(command, "detach", 6)) {
      proton_app_instance_detach_runtime_impl(instance);
      puts("DETACHED");
    } else if (!strncmp(command, "stop", 4)) {
      proton_app_instance_stop_accepting_impl(instance);
      puts("STOPPED");
    } else if (!strncmp(command, "release", 7)) {
      status = proton_app_instance_release_impl(instance, error, sizeof(error));
      printf("RELEASED %d %s\n", status, error);
      released = status == 0;
    } else if (!strncmp(command, "quit", 4)) break;
  }
  if (released) return 0;
  proton_app_instance_detach_runtime_impl(instance);
  status = proton_app_instance_destroy_impl(instance, error, sizeof(error));
  printf("DESTROY %d %s\n", status, error);
  return status == 0 ? 0 : 1;
}
