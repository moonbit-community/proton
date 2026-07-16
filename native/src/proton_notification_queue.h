#ifndef PROTON_NOTIFICATION_QUEUE_H
#define PROTON_NOTIFICATION_QUEUE_H

#include <stdbool.h>
#include <stddef.h>

#define PROTON_NOTIFICATION_PAYLOAD_BYTES 4096

typedef struct proton_notification_node proton_notification_node_t;

typedef struct {
  proton_notification_node_t *head;
  proton_notification_node_t *tail;
  size_t count;
} proton_notification_queue_t;

typedef bool (*proton_notification_consumer_t)(const char *payload,
                                               void *context);

typedef enum {
  PROTON_NOTIFICATION_QUEUE_EMPTY = 0,
  PROTON_NOTIFICATION_QUEUE_RETRY = 1,
  PROTON_NOTIFICATION_QUEUE_DELIVERED = 2,
} proton_notification_delivery_t;

bool proton_notification_queue_try_push(proton_notification_queue_t *queue,
                                        const char *payload);

proton_notification_delivery_t proton_notification_queue_try_deliver(
    proton_notification_queue_t *queue,
    proton_notification_consumer_t consumer,
    void *context);

void proton_notification_queue_dispose(proton_notification_queue_t *queue);

#endif
