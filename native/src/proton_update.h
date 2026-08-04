#ifndef PROTON_UPDATE_H
#define PROTON_UPDATE_H

/* The shipped update entry points are declared in the public header; only the
   hooks the tests need live here. They deliberately carry no PROTON_API, so
   hidden visibility keeps them out of the shipped export set: a way to lie
   about which bundle is running does not belong in the ABI an application
   links against. */
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
