#ifndef PROTON_ENGINE_CEF_COMMON_WINDOW_STATE_H
#define PROTON_ENGINE_CEF_COMMON_WINDOW_STATE_H

#include "include/capi/cef_browser_capi.h"

#include "../../proton_engine.h"

#include <stddef.h>

/* The window-state seam. Each engine owns the layout of its own window and
   runtime structs; shared engine code reaches them only through the accessors
   below, and every engine supplies all of them.

   Two threads meet here. The scheme factory serves requests on CEF's IO thread
   while the main thread installs a new document, so the state is guarded by
   one engine-wide lock. That lock is leaf-only: an engine must never call back
   into CEF while holding it. */
void proton_engine_window_lock(void);
void proton_engine_window_unlock(void);

/* Everything below is called with the window lock held. */

proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser);

/* Returns the CEF browser bound to this window, or NULL if the browser has not
   been created yet or has already been released. The returned browser has its
   refcount unchanged; callers that need to hold it across a message loop
   iteration must call base.add_ref and base.release. */
cef_browser_t *proton_engine_window_browser(proton_engine_window_t *window);
cef_browser_t *proton_engine_view_browser(proton_engine_view_t *view);
proton_window_id_t proton_engine_window_public_id(
    proton_engine_window_t *window);

proton_engine_view_t *proton_engine_window_lookup_view_browser(
    cef_browser_t *browser);

proton_window_id_t proton_engine_view_window_public_id(
    proton_engine_view_t *view);
proton_view_id_t proton_engine_view_public_id(proton_engine_view_t *view);

#endif
