#ifndef PROTON_ENGINE_CEF_COMMON_VIEW_EVENTS_H
#define PROTON_ENGINE_CEF_COMMON_VIEW_EVENTS_H

#include "proton_native.h"

#include <stddef.h>
#include <stdint.h>

/* Per-view lifecycle event queue. Engine callbacks (UI/main thread) enqueue
   fully formatted runtime event JSON once the view is bound to its public
   ids; the ABI event sweep (runtime owner thread) drains it. Events emitted
   before binding are dropped. */

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

void proton_view_events_loading_changed(proton_view_events_t *events,
                                        int32_t is_loading);
void proton_view_events_navigated(proton_view_events_t *events,
                                  const char *url);
void proton_view_events_title_updated(proton_view_events_t *events,
                                      const char *title);
void proton_view_events_load_failed(proton_view_events_t *events,
                                    const char *url,
                                    int32_t error_code,
                                    const char *error_text);


#endif
