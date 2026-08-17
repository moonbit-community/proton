#ifndef PROTON_ENGINE_CEF_COMMON_DOCUMENT_H
#define PROTON_ENGINE_CEF_COMMON_DOCUMENT_H

#include "window_state.h"

#include <stddef.h>
#include <stdint.h>

/* Installs `html` as the document served for `document_url` and, when an asset
   root is supplied, binds that root to the runtime's application origin.

   The document is never handed to CEF inline: the scheme factory reads it back
   out of the window when the navigation asks for it, which is what lets
   relative URLs resolve against the same origin. Publishing the document and
   navigating to it are therefore separate steps, and only the first is shared.
   Engines differ too much in the second -- one defers the navigation until the
   browser exists, another has to hold a frame reference across it.

   `html` may be NULL, which installs an empty document, and `document_url` may
   be NULL or empty, which installs at the application origin's root. On
   PROTON_OK the caller owns `*out_url` and must free it; `out_html_len`
   reports the installed byte count and may be NULL. On failure `*out_url` is
   NULL and the window is left untouched. */
int32_t proton_engine_window_install_document(proton_engine_window_t *window,
                                              const char *html,
                                              const char *document_url,
                                              const char *asset_root,
                                              char **out_url,
                                              size_t *out_html_len,
                                              char *error, size_t error_len);

#endif
