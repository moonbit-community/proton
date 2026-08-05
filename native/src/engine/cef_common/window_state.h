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

const char *proton_engine_window_html_url(proton_engine_window_t *window);
const char *proton_engine_window_html(proton_engine_window_t *window,
                                      size_t *len);

proton_engine_view_t *proton_engine_window_lookup_view_browser(
    cef_browser_t *browser);

const char *proton_engine_view_html_url(proton_engine_view_t *view);
const char *proton_engine_view_html(proton_engine_view_t *view, size_t *len);

/* Releases whatever document the window held and takes ownership of `url` and
   `html`, which must both be allocations that `free` accepts. */
void proton_engine_window_replace_document(proton_engine_window_t *window,
                                           char *url, char *html,
                                           size_t html_len);

const char *proton_engine_runtime_asset_root(proton_engine_window_t *window);

/* Takes ownership of `root`. Only called when the runtime has no root yet, so
   an engine never has to release a previous one here. */
void proton_engine_runtime_adopt_asset_root(proton_engine_window_t *window,
                                            char *root);

#endif
