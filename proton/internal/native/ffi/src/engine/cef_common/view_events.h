#ifndef PROTON_ENGINE_CEF_COMMON_VIEW_EVENTS_H
#define PROTON_ENGINE_CEF_COMMON_VIEW_EVENTS_H

#include "proton_native.h"

#include <stddef.h>
#include <stdint.h>

/* Bound view identity and exactly-once native close notification. */

typedef struct proton_view_events proton_view_events_t;
typedef struct proton_event proton_event_t;

proton_view_events_t *proton_view_events_create(void);
void proton_view_events_destroy(proton_view_events_t *events);
void proton_view_events_bind(proton_view_events_t *events,
                             proton_view_id_t view,
                             proton_window_id_t window);
int proton_view_events_ids(proton_view_events_t *events,
                           proton_view_id_t *out_view,
                           proton_window_id_t *out_window);

void proton_view_events_closed(proton_view_events_t *events);


#endif
