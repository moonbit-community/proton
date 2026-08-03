#ifndef PROTON_ENGINE_CEF_MAC_WINDOW_H
#define PROTON_ENGINE_CEF_MAC_WINDOW_H

#include "../../proton_engine.h"

#import <Cocoa/Cocoa.h>

#include <stddef.h>
#include <stdint.h>

typedef struct _cef_browser_t cef_browser_t;

/* Serializes access to the window list and per-window html state between the
   main thread (writers) and CEF's IO thread (scheme handler readers). */
void proton_engine_window_lock(void);
void proton_engine_window_unlock(void);

uint64_t proton_engine_window_native_id(proton_engine_window_t *window);
int proton_engine_runtime_is_headless(proton_engine_runtime_t *runtime);
int proton_engine_window_is_headless(proton_engine_window_t *window);
NSWindow *proton_engine_window_get_native_window(proton_engine_window_t *window);
NSWindow *proton_engine_window_retain_native_window(
    proton_engine_window_t *window);
int proton_engine_window_is_closed_or_missing(proton_engine_window_t *window);
proton_engine_window_t *proton_engine_window_lookup_native_id(
    uint64_t native_id);
proton_engine_window_t *proton_engine_window_lookup_browser(
    cef_browser_t *browser);
const char *proton_engine_window_html_url(proton_engine_window_t *window);
const char *proton_engine_runtime_asset_root(proton_engine_window_t *window);
const char *proton_engine_window_html(proton_engine_window_t *window,
                                     size_t *len);
proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window);
proton_window_id_t
proton_engine_window_public_id_for_native_window(NSWindow *native_window);

#endif
