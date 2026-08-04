#include "document.h"

#include "include/internal/cef_string.h"

#include <stdlib.h>
#include <string.h>

#include "app_origin.h"
#include "assets.h"
#include "message.h"
#include "strings.h"

int32_t proton_engine_window_install_document(proton_engine_window_t *window,
                                              const char *html,
                                              const char *document_url,
                                              const char *asset_root,
                                              char **out_url,
                                              size_t *out_html_len,
                                              char *error, size_t error_len) {
  if (out_url != NULL) {
    *out_url = NULL;
  }
  if (out_html_len != NULL) {
    *out_html_len = 0;
  }
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (html == NULL) {
    html = "";
  }
  const char *url = document_url != NULL && document_url[0] != '\0'
                        ? document_url
                        : PROTON_ENGINE_APP_URL_PREFIX;
  if (!proton_engine_url_is_proton(url)) {
    proton_engine_set_message(
        error, error_len, "document_url must use a Proton application origin");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  /* Everything the window will own is allocated before the lock is taken, so
     a failure here leaves the previous document in place. */
  char *url_copy = proton_engine_strdup(url);
  char *html_copy = proton_engine_strdup(html);
  char *caller_url = out_url != NULL ? proton_engine_strdup(url) : NULL;
  char *root_copy = asset_root != NULL
                        ? proton_engine_asset_canonical_path(asset_root)
                        : NULL;
  if (url_copy == NULL || html_copy == NULL ||
      (out_url != NULL && caller_url == NULL) ||
      (asset_root != NULL && root_copy == NULL)) {
    free(url_copy);
    free(html_copy);
    free(caller_url);
    free(root_copy);
    proton_engine_set_message(error, error_len,
                              "failed to prepare html document");
    return PROTON_ERR_ENGINE;
  }

  proton_engine_window_lock();
  /* One origin cannot serve two roots: the factory has only the request URL
     to go on, so a second root would make resolution ambiguous. */
  const char *existing_root = proton_engine_runtime_asset_root(window);
  if (root_copy != NULL && existing_root != NULL &&
      strcmp(root_copy, existing_root) != 0) {
    proton_engine_window_unlock();
    free(url_copy);
    free(html_copy);
    free(caller_url);
    free(root_copy);
    proton_engine_set_message(
        error, error_len,
        "the Proton application origin already has a different asset root");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (root_copy != NULL && existing_root == NULL) {
    proton_engine_runtime_adopt_asset_root(window, root_copy);
    root_copy = NULL;
  }
  size_t html_len = strlen(html_copy);
  proton_engine_window_replace_document(window, url_copy, html_copy, html_len);
  proton_engine_window_unlock();
  /* Non-NULL only when the runtime already had this exact root. */
  free(root_copy);

  if (out_url != NULL) {
    *out_url = caller_url;
  }
  if (out_html_len != NULL) {
    *out_html_len = html_len;
  }
  return PROTON_OK;
}
