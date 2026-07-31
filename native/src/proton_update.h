#ifndef PROTON_UPDATE_H
#define PROTON_UPDATE_H

#include "proton_native.h"

#include <stddef.h>
#include <stdint.h>

/* Expands a downloaded archive into a directory and reports the `.app` it
   contains.

   The archive is expected to be authenticated already: this function unpacks,
   it does not decide whether unpacking is safe. */
PROTON_API int32_t proton_update_expand(const char *archive_path,
                                        const char *destination_dir,
                                        char *bundle_out, size_t bundle_out_len,
                                        char *error, size_t error_len);

/* Records a staged application bundle after checking that installing it would
   be safe. Nothing is modified. */
PROTON_API int32_t proton_update_stage(const char *staged_bundle_path, char *error,
                                 size_t error_len);

/* Replaces the running application with the staged bundle.

   This is the only irreversible operation in the updater. It is separated from
   the relaunch so that the replacement itself can be exercised against
   throwaway directories. */
PROTON_API int32_t proton_update_apply(char *error, size_t error_len);

/* Starts the replaced application. The caller exits afterwards. */
PROTON_API int32_t proton_update_relaunch(char *error, size_t error_len);

/* Overrides the bundle treated as "running", for tests. Passing NULL restores
   detection from the running executable. */
PROTON_API void proton_update_set_current_bundle_for_testing(const char *path);

/* Returns the path the previous bundle was moved to by the last successful
   apply, or an empty string. */
PROTON_API const char *proton_update_previous_bundle_path(void);

#endif
