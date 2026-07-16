#include "proton_notification_queue.h"

#include <stdlib.h>
#include <string.h>

struct proton_notification_node {
  char *payload;
  struct proton_notification_node *next;
};

bool proton_notification_queue_try_push(proton_notification_queue_t *queue,
                                        const char *payload) {
  if (queue == NULL || payload == NULL) {
    return false;
  }
  size_t payload_len = strlen(payload);
  if (payload_len >= PROTON_NOTIFICATION_PAYLOAD_BYTES) {
    return false;
  }
  proton_notification_node_t *node =
      (proton_notification_node_t *)malloc(sizeof(*node));
  if (node == NULL) {
    return false;
  }
  node->payload = (char *)malloc(payload_len + 1);
  if (node->payload == NULL) {
    free(node);
    return false;
  }
  memcpy(node->payload, payload, payload_len + 1);
  node->next = NULL;
  if (queue->tail != NULL) {
    queue->tail->next = node;
  } else {
    queue->head = node;
  }
  queue->tail = node;
  queue->count++;
  return true;
}

proton_notification_delivery_t proton_notification_queue_try_deliver(
    proton_notification_queue_t *queue,
    proton_notification_consumer_t consumer,
    void *context) {
  if (queue == NULL || consumer == NULL || queue->count == 0) {
    return PROTON_NOTIFICATION_QUEUE_EMPTY;
  }
  proton_notification_node_t *node = queue->head;
  if (!consumer(node->payload, context)) {
    return PROTON_NOTIFICATION_QUEUE_RETRY;
  }
  queue->head = node->next;
  if (queue->head == NULL) {
    queue->tail = NULL;
  }
  queue->count--;
  free(node->payload);
  free(node);
  return PROTON_NOTIFICATION_QUEUE_DELIVERED;
}

void proton_notification_queue_dispose(proton_notification_queue_t *queue) {
  if (queue == NULL) {
    return;
  }
  proton_notification_node_t *node = queue->head;
  while (node != NULL) {
    proton_notification_node_t *next = node->next;
    free(node->payload);
    free(node);
    node = next;
  }
  queue->head = NULL;
  queue->tail = NULL;
  queue->count = 0;
}
