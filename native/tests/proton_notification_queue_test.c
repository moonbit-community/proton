#include "proton_notification_queue.h"

#include <stdio.h>
#include <string.h>

typedef struct {
  int accept;
  int calls;
  char payload[PROTON_NOTIFICATION_PAYLOAD_BYTES];
} consumer_probe_t;

static bool consume_payload(const char *payload, void *raw_probe) {
  consumer_probe_t *probe = (consumer_probe_t *)raw_probe;
  probe->calls++;
  snprintf(probe->payload, sizeof(probe->payload), "%s", payload);
  return probe->accept != 0;
}

static int fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  return 1;
}

int main(void) {
  proton_notification_queue_t queue = {0};
  if (!proton_notification_queue_try_push(&queue, "first") ||
      !proton_notification_queue_try_push(&queue, "second")) {
    return fail("failed to seed notification queue");
  }

  consumer_probe_t probe = {0};
  if (proton_notification_queue_try_deliver(&queue, consume_payload, &probe) !=
          PROTON_NOTIFICATION_QUEUE_RETRY ||
      strcmp(probe.payload, "first") != 0 || queue.count != 2) {
    return fail("rejected delivery did not retain the queue head");
  }

  probe.accept = 1;
  if (proton_notification_queue_try_deliver(&queue, consume_payload, &probe) !=
          PROTON_NOTIFICATION_QUEUE_DELIVERED ||
      strcmp(probe.payload, "first") != 0 || queue.count != 1) {
    return fail("retry did not deliver the retained queue head exactly once");
  }
  if (proton_notification_queue_try_deliver(&queue, consume_payload, &probe) !=
          PROTON_NOTIFICATION_QUEUE_DELIVERED ||
      strcmp(probe.payload, "second") != 0 || queue.count != 0) {
    return fail("notification queue did not preserve FIFO order");
  }
  if (proton_notification_queue_try_deliver(&queue, consume_payload, &probe) !=
      PROTON_NOTIFICATION_QUEUE_EMPTY) {
    return fail("empty notification queue reported a delivery");
  }

  char bounded[PROTON_NOTIFICATION_PAYLOAD_BYTES];
  memset(bounded, 'x', sizeof(bounded) - 1);
  bounded[sizeof(bounded) - 1] = '\0';
  if (!proton_notification_queue_try_push(&queue, bounded)) {
    return fail("notification queue rejected the maximum bounded payload");
  }
  proton_notification_queue_dispose(&queue);

  char oversized[PROTON_NOTIFICATION_PAYLOAD_BYTES + 1];
  memset(oversized, 'x', sizeof(oversized) - 1);
  oversized[sizeof(oversized) - 1] = '\0';
  if (proton_notification_queue_try_push(&queue, oversized)) {
    return fail("notification queue admitted an oversized payload");
  }

  for (size_t i = 0; i < 256; i++) {
    if (!proton_notification_queue_try_push(&queue, "queued")) {
      return fail("dynamic notification queue rejected a bounded payload");
    }
  }
  if (queue.count != 256) {
    return fail("dynamic notification queue lost an admitted payload");
  }
  proton_notification_queue_dispose(&queue);
  if (queue.count != 0 || queue.head != NULL || queue.tail != NULL) {
    return fail("notification queue disposal left live nodes");
  }
  return 0;
}
