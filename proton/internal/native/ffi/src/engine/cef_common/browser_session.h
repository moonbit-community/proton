#ifndef PROTON_ENGINE_CEF_COMMON_BROWSER_SESSION_H
#define PROTON_ENGINE_CEF_COMMON_BROWSER_SESSION_H

#include "proton_native.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_request_capi.h"
#include "include/capi/cef_request_handler_capi.h"

#include <stddef.h>
#include <stdint.h>

typedef enum {
  PROTON_BROWSER_POLICY_ALLOW = 0,
  PROTON_BROWSER_POLICY_DENY = 1,
  PROTON_BROWSER_POLICY_ASK = 2,
} proton_browser_policy_mode_t;

typedef struct {
  proton_browser_policy_mode_t navigation;
  proton_browser_policy_mode_t popup;
  proton_browser_policy_mode_t download;
  proton_browser_policy_mode_t certificate;
  proton_browser_policy_mode_t media;
  int32_t devtools;
} proton_browser_policy_t;

typedef struct proton_browser_session proton_browser_session_t;
typedef struct proton_event proton_event_t;

typedef void (*proton_browser_signal_fn)(void *user_data);

proton_browser_session_t *proton_browser_session_create(
    const proton_browser_policy_t *policy, proton_browser_signal_fn signal,
    void *signal_user_data);
void proton_browser_session_destroy(proton_browser_session_t *session);
void proton_browser_session_bind_window(proton_browser_session_t *session,
                                         proton_window_id_t window);

int32_t proton_browser_session_respond_json(
    proton_browser_session_t *session, const char *response_json,
    char *error, size_t error_len);
int32_t proton_browser_session_command_json(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *command_json, char *error, size_t error_len);
int32_t proton_browser_navigation_state(
    cef_browser_t *browser, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len);
int32_t proton_browser_set_zoom_percent(
    cef_browser_t *browser, int32_t zoom_percent,
    char *error, size_t error_len);

int proton_browser_session_before_browse(
    proton_browser_session_t *session, cef_frame_t *frame,
    cef_request_t *request, int user_gesture, int is_redirect);
int proton_browser_session_before_popup(
    proton_browser_session_t *session, const cef_string_t *target_url,
    cef_window_open_disposition_t target_disposition, int user_gesture);
int proton_browser_session_can_download(
    proton_browser_session_t *session);
int proton_browser_session_before_download(
    proton_browser_session_t *session, cef_download_item_t *download_item,
    const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback);
void proton_browser_session_download_updated(
    proton_browser_session_t *session, cef_download_item_t *download_item,
    cef_download_item_callback_t *callback);
int proton_browser_session_certificate_error(
    proton_browser_session_t *session, cef_errorcode_t cert_error,
    const cef_string_t *request_url, cef_callback_t *callback);
int proton_browser_session_media_permission(
    proton_browser_session_t *session, const cef_string_t *requesting_origin,
    uint32_t requested_permissions, cef_media_access_callback_t *callback);

#endif
