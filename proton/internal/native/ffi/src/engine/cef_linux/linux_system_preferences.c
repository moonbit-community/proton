#if defined(__linux__)

#include "linux_internal.h"
#include "../../proton_engine.h"
#include "../cef_common/message.h"

/* Linux system preferences. GTK exposes one global animation switch, which is
   what Chromium reports on this platform, and no accent color: the accent
   color only exists through the XDG desktop portal, which Proton does not read
   yet, so the query answers with an empty value exactly like Electron does on
   a desktop without a configured accent color. Media access and accessibility
   trust stay Windows/macOS or macOS only. */

int32_t proton_engine_system_accent_color(char *buffer, int32_t buffer_len,
                                          char *error, size_t error_len) {
  (void)error;
  (void)error_len;
  if (buffer == NULL || buffer_len < 1) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  buffer[0] = '\0';
  return PROTON_OK;
}

int32_t proton_engine_system_animation_settings(
    int32_t *out_rich_animation, int32_t *out_scroll_animations,
    int32_t *out_reduced_motion, char *error, size_t error_len) {
  if (out_rich_animation == NULL || out_scroll_animations == NULL ||
      out_reduced_motion == NULL) {
    proton_engine_set_message(error, error_len,
                              "animation setting outputs are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* Chromium reports animations as enabled when no toolkit is available, and
     the connection probe can fail on a session without X11. Reporting the
     default keeps the query answerable on every Linux session. */
  gboolean animations_enabled = TRUE;
  if (proton_engine_ensure_gtk(error, error_len)) {
    GtkSettings *settings = gtk_settings_get_default();
    if (settings != NULL) {
      g_object_get(settings, "gtk-enable-animations", &animations_enabled, NULL);
    }
  }
  *out_rich_animation = animations_enabled ? 1 : 0;
  *out_scroll_animations = animations_enabled ? 1 : 0;
  *out_reduced_motion = animations_enabled ? 0 : 1;
  return PROTON_OK;
}

int32_t proton_engine_system_media_access_status(int32_t media,
                                                 int32_t *out_status,
                                                 char *error,
                                                 size_t error_len) {
  (void)media;
  (void)out_status;
  proton_engine_set_message(
      error, error_len,
      "media access status is only available on Windows and macOS");
  return PROTON_ERR_UNSUPPORTED;
}

int32_t proton_engine_system_accessibility_client_trusted(
    int32_t prompt, int32_t *out_trusted, char *error, size_t error_len) {
  (void)prompt;
  (void)out_trusted;
  proton_engine_set_message(
      error, error_len,
      "accessibility client trust is only available on macOS");
  return PROTON_ERR_UNSUPPORTED;
}

#endif
