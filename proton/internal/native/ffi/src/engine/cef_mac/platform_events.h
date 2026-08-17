#ifndef PROTON_ENGINE_MAC_PLATFORM_EVENTS_H
#define PROTON_ENGINE_MAC_PLATFORM_EVENTS_H

#include <stdint.h>

typedef struct proton_event proton_event_t;

typedef void (*proton_engine_platform_event_signal_callback_t)(
    uint32_t ready_mask);

void proton_engine_platform_event_set_signal_callback(
    proton_engine_platform_event_signal_callback_t callback);
void proton_engine_platform_event_enqueue(proton_event_t *event);

#endif
