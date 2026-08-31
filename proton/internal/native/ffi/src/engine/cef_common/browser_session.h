#ifndef PROTON_ENGINE_CEF_COMMON_BROWSER_SESSION_H
#define PROTON_ENGINE_CEF_COMMON_BROWSER_SESSION_H

#include "proton_native.h"

#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_download_handler_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_request_capi.h"
#include "include/capi/cef_request_handler_capi.h"

#include "browser_lifecycle.h"

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
void proton_browser_session_bind_lifecycle(
    proton_browser_session_t *session,
    proton_browser_lifecycle_t *lifecycle);

void proton_browser_session_loading_changed(proton_browser_session_t *session,
                                             const char *url,
                                             int32_t is_loading);
void proton_browser_session_navigated(proton_browser_session_t *session,
                                      const char *url);
void proton_browser_session_title_updated(proton_browser_session_t *session,
                                           const char *title);
void proton_browser_session_load_failed(proton_browser_session_t *session,
                                        const char *url,
                                        int32_t error_code,
                                        const char *error_text);
int32_t proton_browser_session_copy_url(proton_browser_session_t *session,
                                        char *buffer, int32_t buffer_len,
                                        int32_t *out_required_len);
int32_t proton_browser_session_copy_title(proton_browser_session_t *session,
                                          char *buffer, int32_t buffer_len,
                                          int32_t *out_required_len);
int32_t proton_browser_session_is_loading(
    proton_browser_session_t *session);

int32_t proton_browser_session_respond(
    proton_browser_session_t *session, uint64_t request_id,
    const char *action, const char *path, char *error, size_t error_len);
int32_t proton_browser_session_command(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *command, int32_t download_id, char *error, size_t error_len);
int32_t proton_browser_navigation_state(
    cef_browser_t *browser, int32_t *out_can_go_back,
    int32_t *out_can_go_forward, char *error, size_t error_len);
int32_t proton_browser_headless_is_focused(
    cef_browser_t *browser, int32_t *out_focused, char *error,
    size_t error_len);
int32_t proton_browser_is_devtools_opened(
    cef_browser_t *browser, int32_t *out_opened,
    char *error, size_t error_len);
int32_t proton_browser_set_zoom_percent(
    cef_browser_t *browser, int32_t zoom_percent,
    char *error, size_t error_len);
int32_t proton_browser_set_audio_muted(
    cef_browser_t *browser, int32_t muted, char *error, size_t error_len);
int32_t proton_browser_is_audio_muted(
    cef_browser_t *browser, int32_t *out_muted, char *error,
    size_t error_len);
int32_t proton_browser_download_url(
    cef_browser_t *browser, const char *url, char *error, size_t error_len);
int32_t proton_browser_print(
    cef_browser_t *browser, char *error, size_t error_len);
int32_t proton_browser_print_to_pdf(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *path, int32_t landscape, int32_t print_background,
    double scale, double paper_width, double paper_height,
    int32_t prefer_css_page_size, int32_t margin_type,
    double margin_top, double margin_right, double margin_bottom,
    double margin_left, const char *page_ranges,
    int32_t display_header_footer, const char *header_template,
    const char *footer_template, int32_t generate_tagged_pdf,
    int32_t generate_document_outline, int32_t *out_request_id,
    char *error, size_t error_len);
int32_t proton_browser_find_in_page(
    proton_browser_session_t *session, cef_browser_t *browser,
    const char *text, int32_t forward, int32_t match_case,
    int32_t find_next, int32_t *out_request_id, char *error,
    size_t error_len);
int32_t proton_browser_stop_find_in_page(
    cef_browser_t *browser, int32_t clear_selection, char *error,
    size_t error_len);
int32_t proton_browser_session_find_request_id(
    proton_browser_session_t *session, int32_t cef_identifier);
void proton_browser_session_find_result(
    proton_browser_session_t *session, int32_t cef_identifier,
    int32_t count, int32_t x, int32_t y, int32_t width,
    int32_t height, int32_t active_match_ordinal, int32_t final_update);

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
