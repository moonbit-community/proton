#if defined(_WIN32)

#include "win_internal.h"
#include "../../proton_engine.h"
#include "../cef_common/message.h"

#include <wchar.h>

/* System preferences that Windows owns: the accent color the user picked in
   Personalization, the system animation guidance, and the device consent that
   Windows Settings stores for microphone and camera access. The values follow
   Electron's systemPreferences module so an application can move between the
   two frameworks without reinterpreting them. */

#define PROTON_SYSTEM_ACCENT_BYTES 16
#define PROTON_SYSTEM_CONSENT_KEY \
  L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore"
#define PROTON_SYSTEM_PATH_CHARS 4096
#define PROTON_SYSTEM_CONSENT_CHARS \
  (PROTON_SYSTEM_PATH_CHARS + 128)

int32_t proton_engine_system_accent_color(char *buffer, int32_t buffer_len,
                                          char *error, size_t error_len) {
  if (buffer == NULL || buffer_len < PROTON_SYSTEM_ACCENT_BYTES) {
    proton_engine_set_message(error, error_len,
                              "accent color buffer is too small");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* An unset value is not a failure: Electron reports an empty accent color
     when the user has not configured one. */
  buffer[0] = '\0';
  DWORD accent = 0;
  DWORD size = sizeof(accent);
  if (RegGetValueW(HKEY_CURRENT_USER, L"SOFTWARE\\Microsoft\\Windows\\DWM",
                   L"AccentColor", RRF_RT_REG_DWORD, NULL, &accent,
                   &size) != ERROR_SUCCESS) {
    return PROTON_OK;
  }
  /* The DWM stores the color as ABGR. Electron reports RGBA digits with a full
     alpha channel, because it converts through a COLORREF. */
  snprintf(buffer, (size_t)buffer_len, "%02X%02X%02X%02X",
           (unsigned int)(accent & 0xFFu),
           (unsigned int)((accent >> 8) & 0xFFu),
           (unsigned int)((accent >> 16) & 0xFFu), 255u);
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
  /* Chromium defaults to enabled before it reads the parameter, so a system
     without the client area animation setting keeps its animations. */
  BOOL animations_enabled = TRUE;
  int32_t rich_animation = 1;
  int32_t reduced_motion = 0;
  if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0,
                            &animations_enabled, 0)) {
    rich_animation = animations_enabled ? 1 : 0;
    reduced_motion = animations_enabled ? 0 : 1;
  } else if (GetSystemMetrics(SM_REMOTESESSION) != 0) {
    /* Chromium falls back to the session type when the parameter is missing. */
    rich_animation = 0;
  }
  *out_rich_animation = rich_animation;
  /* Chromium drives every Linux and Windows animation decision from the same
     global state, so scroll animations follow the rich animation report. */
  *out_scroll_animations = rich_animation;
  *out_reduced_motion = reduced_motion;
  return PROTON_OK;
}

static const wchar_t *proton_system_media_name(int32_t media) {
  switch (media) {
  case PROTON_MEDIA_ACCESS_MICROPHONE:
    return L"microphone";
  case PROTON_MEDIA_ACCESS_CAMERA:
    return L"camera";
  default:
    return NULL;
  }
}

/* Reads one consent value. Returns 0 when the value is absent, so the caller
   can continue with the next scope. */
static int proton_system_read_consent(HKEY root, const wchar_t *path,
                                      int32_t *out_status) {
  wchar_t value[64] = {0};
  DWORD size = sizeof(value);
  if (RegGetValueW(root, path, L"Value", RRF_RT_REG_SZ, NULL, value, &size) !=
      ERROR_SUCCESS) {
    return 0;
  }
  if (_wcsicmp(value, L"Allow") == 0) {
    *out_status = PROTON_MEDIA_ACCESS_STATUS_GRANTED;
  } else if (_wcsicmp(value, L"Deny") == 0) {
    *out_status = PROTON_MEDIA_ACCESS_STATUS_DENIED;
  } else {
    *out_status = PROTON_MEDIA_ACCESS_STATUS_NOT_DETERMINED;
  }
  return 1;
}

/* Windows keys a non-packaged application by its executable path with the
   separators replaced by '#'. */
static void proton_system_app_consent_path(wchar_t *out, size_t capacity,
                                           const wchar_t *media) {
  wchar_t executable[PROTON_SYSTEM_PATH_CHARS] = {0};
  out[0] = L'\0';
  DWORD length = GetModuleFileNameW(NULL, executable,
                                    PROTON_SYSTEM_PATH_CHARS);
  if (length == 0 || length >= PROTON_SYSTEM_PATH_CHARS) {
    return;
  }
  for (DWORD index = 0; index < length; index++) {
    if (executable[index] == L'\\') {
      executable[index] = L'#';
    }
  }
  if (swprintf(out, capacity, L"%s\\%s\\NonPackaged\\%s",
               PROTON_SYSTEM_CONSENT_KEY, media, executable) < 0) {
    out[0] = L'\0';
  }
}

int32_t proton_engine_system_media_access_status(int32_t media,
                                                 int32_t *out_status,
                                                 char *error,
                                                 size_t error_len) {
  if (out_status == NULL) {
    proton_engine_set_message(error, error_len,
                              "media access status output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (media == PROTON_MEDIA_ACCESS_SCREEN) {
    /* Electron always reports granted for screen capture on Windows. */
    *out_status = PROTON_MEDIA_ACCESS_STATUS_GRANTED;
    return PROTON_OK;
  }
  const wchar_t *name = proton_system_media_name(media);
  if (name == NULL) {
    proton_engine_set_message(error, error_len,
                              "media access kind is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  wchar_t device_key[PROTON_SYSTEM_CONSENT_CHARS] = {0};
  swprintf(device_key, PROTON_SYSTEM_CONSENT_CHARS, L"%s\\%s",
           PROTON_SYSTEM_CONSENT_KEY, name);
  int32_t status = PROTON_MEDIA_ACCESS_STATUS_UNKNOWN;
  /* An administrative policy that denies the device class is what Electron
     reports as restricted; the user-level keys cannot override it. */
  if (proton_system_read_consent(HKEY_LOCAL_MACHINE, device_key, &status) &&
      status == PROTON_MEDIA_ACCESS_STATUS_DENIED) {
    *out_status = PROTON_MEDIA_ACCESS_STATUS_RESTRICTED;
    return PROTON_OK;
  }
  /* The per-application entry is written once the application asks for the
     device; the device entry below it is the all-applications default. */
  wchar_t app_key[PROTON_SYSTEM_CONSENT_CHARS] = {0};
  proton_system_app_consent_path(app_key, PROTON_SYSTEM_CONSENT_CHARS, name);
  if (app_key[0] != L'\0' &&
      proton_system_read_consent(HKEY_CURRENT_USER, app_key, &status)) {
    *out_status = status;
    return PROTON_OK;
  }
  if (proton_system_read_consent(HKEY_CURRENT_USER, device_key, &status)) {
    *out_status = status;
    return PROTON_OK;
  }
  *out_status = PROTON_MEDIA_ACCESS_STATUS_NOT_DETERMINED;
  return PROTON_OK;
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
