#ifndef PROTON_ENGINE_CEF_MAC_WINDOW_H
#define PROTON_ENGINE_CEF_MAC_WINDOW_H

#include "../../proton_engine.h"

/* The window lock and the html/asset accessors the shared scheme factory
   reads through are declared with the factory itself. */
#include "../cef_common/scheme.h"

#import <Cocoa/Cocoa.h>

#include <stddef.h>
#include <stdint.h>

uint64_t proton_engine_window_native_id(proton_engine_window_t *window);
int proton_engine_runtime_is_headless(proton_engine_runtime_t *runtime);
int proton_engine_window_is_headless(proton_engine_window_t *window);
NSWindow *proton_engine_window_get_native_window(proton_engine_window_t *window);
NSWindow *proton_engine_window_retain_native_window(
    proton_engine_window_t *window);
int proton_engine_window_is_closed_or_missing(proton_engine_window_t *window);
proton_engine_window_t *proton_engine_window_lookup_native_id(
    uint64_t native_id);
proton_window_id_t
proton_engine_window_public_id(proton_engine_window_t *window);
proton_window_id_t
proton_engine_window_public_id_for_native_window(NSWindow *native_window);

#endif
