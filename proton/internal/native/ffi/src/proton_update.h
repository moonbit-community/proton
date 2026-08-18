#ifndef PROTON_UPDATE_H
#define PROTON_UPDATE_H

/* Runtime entry points live in the shared private FFI header. This header only
   declares updater test hooks; the MoonBit production facade does not bind
   them. */
#include "proton_native.h"

#include <stddef.h>
#include <stdint.h>

/* Overrides the bundle treated as "running", for tests. Passing NULL restores
   detection from the running executable. */
void proton_update_set_current_bundle_for_testing(const char *path);

/* Overrides the detected install medium, for tests, so every branch can be
   exercised on any host. Accepts "appimage", "flatpak", "snap", or "package";
   NULL or an unrecognized value restores real detection. */
void proton_update_set_medium_for_testing(const char *medium);

/* Returns the path the previous bundle was moved to by the last successful
   apply, or an empty string. */
const char *proton_update_previous_bundle_path(void);

#endif
