#if defined(_WIN32)

#include "../../proton_engine.h"

#define UNICODE 1
#define _UNICODE 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_NOTIFICATION_MAX_CLICKS 16
#define PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES 65536
#define PROTON_NOTIFICATION_TRAY_ID 1
#define PROTON_NOTIFICATION_WM_CALLBACK (WM_APP + 1)
#define PROTON_NOTIFICATION_CLASS_NAME L"ProtonNotificationWindow"

typedef struct {
  char payload[PROTON_NOTIFICATION_MAX_PAYLOAD_BYTES];
  int32_t has_payload;
} proton_notification_click_t;

static proton_notification_click_t
    g_notification_clicks[PROTON_NOTIFICATION_MAX_CLICKS];
static uint32_t g_notification_click_head = 0;
static uint32_t g_notification_click_count = 0;
static SRWLOCK g_notification_click_lock = SRWLOCK_INIT;

static HWND g_notification_window = NULL;
static SRWLOCK g_notification_window_lock = SRWLOCK_INIT;
static ATOM g_notification_class_atom = 0;
static UINT g_notification_taskbar_created_msg = 0;
static int32_t g_notification_icon_added = 0;
static HICON g_notification_icon = NULL;

static void proton_notification_set_message(char *error,
                                            size_t error_len,
                                            const char *message) {
  if (error != NULL && error_len > 0) {
    snprintf(error, error_len, "%s", message);
  }
}

static int proton_notification_set_icon_version(HWND window) {
  NOTIFYICONDATAW icon = {0};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = PROTON_NOTIFICATION_TRAY_ID;
  icon.uVersion = NOTIFYICON_VERSION_4;
  return Shell_NotifyIconW(NIM_SETVERSION, &icon) != FALSE;
}

static LRESULT CALLBACK proton_notification_wnd_proc(HWND hwnd,
                                                     UINT msg,
                                                     WPARAM wparam,
                                                     LPARAM lparam) {
  if (msg == PROTON_NOTIFICATION_WM_CALLBACK) {
    switch (LOWORD(lparam)) {
      case NIN_BALLOONUSERCLICK: {
        AcquireSRWLockExclusive(&g_notification_click_lock);
        if (g_notification_click_count < PROTON_NOTIFICATION_MAX_CLICKS) {
          uint32_t index = (g_notification_click_head + g_notification_click_count) %
                           PROTON_NOTIFICATION_MAX_CLICKS;
          g_notification_clicks[index].has_payload = 0;
          g_notification_clicks[index].payload[0] = '\0';
          g_notification_click_count++;
        }
        ReleaseSRWLockExclusive(&g_notification_click_lock);
        return 0;
      }
      default:
        return 0;
    }
  }
  if (msg == g_notification_taskbar_created_msg && g_notification_icon_added) {
    NOTIFYICONDATAW icon = {0};
    icon.cbSize = sizeof(icon);
    icon.hWnd = hwnd;
    icon.uID = PROTON_NOTIFICATION_TRAY_ID;
    icon.uFlags = NIF_MESSAGE | NIF_ICON;
    icon.uCallbackMessage = PROTON_NOTIFICATION_WM_CALLBACK;
    icon.hIcon = g_notification_icon != NULL ? g_notification_icon
                                             : LoadIconW(NULL, IDI_APPLICATION);
    if (Shell_NotifyIconW(NIM_ADD, &icon)) {
      if (!proton_notification_set_icon_version(hwnd)) {
        Shell_NotifyIconW(NIM_DELETE, &icon);
        g_notification_icon_added = 0;
      }
    } else {
      g_notification_icon_added = 0;
    }
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static int32_t proton_notification_ensure_window(char *error,
                                                 size_t error_len) {
  AcquireSRWLockExclusive(&g_notification_window_lock);
  if (g_notification_window != NULL) {
    ReleaseSRWLockExclusive(&g_notification_window_lock);
    return PROTON_OK;
  }
  if (g_notification_class_atom == 0) {
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSEXW cls = {0};
    cls.cbSize = sizeof(cls);
    cls.lpfnWndProc = proton_notification_wnd_proc;
    cls.hInstance = instance;
    cls.lpszClassName = PROTON_NOTIFICATION_CLASS_NAME;
    cls.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    cls.hCursor = LoadCursorW(NULL, IDC_ARROW);
    g_notification_class_atom = RegisterClassExW(&cls);
    if (g_notification_class_atom == 0) {
      ReleaseSRWLockExclusive(&g_notification_window_lock);
      proton_notification_set_message(
          error, error_len,
          "registering the notification window class failed");
      return PROTON_ERR_PLATFORM;
    }
    g_notification_taskbar_created_msg =
        RegisterWindowMessageW(L"TaskbarCreated");
  }
  g_notification_window = CreateWindowExW(
      0, MAKEINTATOM(g_notification_class_atom), L"Proton Notification",
      WS_OVERLAPPED, 0, 0, 0, 0, HWND_MESSAGE, NULL, GetModuleHandleW(NULL),
      NULL);
  if (g_notification_window == NULL) {
    ReleaseSRWLockExclusive(&g_notification_window_lock);
    proton_notification_set_message(error, error_len,
                                    "creating the notification window failed");
    return PROTON_ERR_PLATFORM;
  }
  ReleaseSRWLockExclusive(&g_notification_window_lock);
  return PROTON_OK;
}

static HICON proton_notification_load_icon(void) {
  HICON icon = LoadIconW(NULL, IDI_APPLICATION);
  return icon;
}

int32_t proton_engine_notification_is_supported(int32_t *out_supported,
                                                char *error,
                                                size_t error_len) {
  (void)error;
  (void)error_len;
  if (out_supported != NULL) {
    *out_supported = 1;
  }
  return PROTON_OK;
}

int32_t proton_engine_notification_show(const char *title_utf8,
                                        const char *body_utf8,
                                        const char *payload_utf8,
                                        int32_t has_payload,
                                        char *error,
                                        size_t error_len) {
  (void)payload_utf8;
  (void)has_payload;
  if (title_utf8 == NULL || body_utf8 == NULL) {
    proton_notification_set_message(error, error_len,
                                    "notification title and body are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int32_t window_status = proton_notification_ensure_window(error, error_len);
  if (window_status != PROTON_OK) {
    return window_status;
  }
  HWND window = g_notification_window;
  if (window == NULL) {
    proton_notification_set_message(error, error_len,
                                    "notification window is not available");
    return PROTON_ERR_PLATFORM;
  }
  int title_w_len = MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1, NULL, 0);
  int body_w_len = MultiByteToWideChar(CP_UTF8, 0, body_utf8, -1, NULL, 0);
  if (title_w_len <= 0 || body_w_len <= 0) {
    proton_notification_set_message(
        error, error_len,
        "notification title or body is invalid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  wchar_t *title_w = (wchar_t *)malloc((size_t)title_w_len * sizeof(wchar_t));
  wchar_t *body_w = (wchar_t *)malloc((size_t)body_w_len * sizeof(wchar_t));
  if (title_w == NULL || body_w == NULL) {
    free(title_w);
    free(body_w);
    proton_notification_set_message(error, error_len,
                                    "allocating notification buffers failed");
    return PROTON_ERR_PLATFORM;
  }
  MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1, title_w, title_w_len);
  MultiByteToWideChar(CP_UTF8, 0, body_utf8, -1, body_w, body_w_len);

  if (g_notification_icon == NULL) {
    g_notification_icon = proton_notification_load_icon();
  }
  NOTIFYICONDATAW icon = {0};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = PROTON_NOTIFICATION_TRAY_ID;
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_INFO;
  icon.uCallbackMessage = PROTON_NOTIFICATION_WM_CALLBACK;
  icon.hIcon = g_notification_icon != NULL ? g_notification_icon
                                           : LoadIconW(NULL, IDI_APPLICATION);
  icon.dwInfoFlags = NIIF_INFO;
  wcsncpy(icon.szInfoTitle, title_w,
          sizeof(icon.szInfoTitle) / sizeof(wchar_t) - 1);
  icon.szInfoTitle[sizeof(icon.szInfoTitle) / sizeof(wchar_t) - 1] = L'\0';
  wcsncpy(icon.szInfo, body_w,
          sizeof(icon.szInfo) / sizeof(wchar_t) - 1);
  icon.szInfo[sizeof(icon.szInfo) / sizeof(wchar_t) - 1] = L'\0';
  free(title_w);
  free(body_w);

  DWORD command = g_notification_icon_added ? NIM_MODIFY : NIM_ADD;
  if (!Shell_NotifyIconW(command, &icon)) {
    proton_notification_set_message(error, error_len,
                                    "Shell_NotifyIconW failed");
    return PROTON_ERR_PLATFORM;
  }
  if (command == NIM_ADD) {
    if (!proton_notification_set_icon_version(window)) {
      Shell_NotifyIconW(NIM_DELETE, &icon);
      proton_notification_set_message(
          error, error_len,
          "Shell_NotifyIconW(NIM_SETVERSION) failed");
      return PROTON_ERR_PLATFORM;
    }
  }
  g_notification_icon_added = 1;
  return PROTON_OK;
}

int32_t proton_engine_notification_poll_click(
    char *buffer,
    int32_t buffer_len,
    int32_t *out_required,
    int32_t *out_has_payload,
    int32_t *out_available,
    char *error,
    size_t error_len) {
  (void)error;
  (void)error_len;
  if (out_required != NULL) {
    *out_required = 0;
  }
  if (out_has_payload != NULL) {
    *out_has_payload = 0;
  }
  if (out_available != NULL) {
    *out_available = 0;
  }
  AcquireSRWLockExclusive(&g_notification_click_lock);
  if (g_notification_click_count == 0) {
    ReleaseSRWLockExclusive(&g_notification_click_lock);
    return PROTON_OK;
  }
  const proton_notification_click_t *click =
      &g_notification_clicks[g_notification_click_head];
  size_t required = strlen(click->payload) + 1;
  if (required > INT32_MAX) {
    ReleaseSRWLockExclusive(&g_notification_click_lock);
    return PROTON_ERR_ENGINE;
  }
  if (out_required != NULL) {
    *out_required = (int32_t)required;
  }
  if (out_has_payload != NULL) {
    *out_has_payload = click->has_payload;
  }
  if (out_available != NULL) {
    *out_available = 1;
  }
  if (buffer == NULL || buffer_len < (int32_t)required) {
    ReleaseSRWLockExclusive(&g_notification_click_lock);
    return PROTON_ERR_BUFFER_TOO_SMALL;
  }
  memcpy(buffer, click->payload, required);
  g_notification_click_head =
      (g_notification_click_head + 1) % PROTON_NOTIFICATION_MAX_CLICKS;
  g_notification_click_count--;
  ReleaseSRWLockExclusive(&g_notification_click_lock);
  return PROTON_OK;
}

int32_t proton_engine_notification_cleanup(char *error, size_t error_len) {
  (void)error;
  (void)error_len;
  AcquireSRWLockExclusive(&g_notification_window_lock);
  if (g_notification_icon_added && g_notification_window != NULL) {
    NOTIFYICONDATAW icon = {0};
    icon.cbSize = sizeof(icon);
    icon.hWnd = g_notification_window;
    icon.uID = PROTON_NOTIFICATION_TRAY_ID;
    Shell_NotifyIconW(NIM_DELETE, &icon);
    g_notification_icon_added = 0;
  }
  if (g_notification_window != NULL) {
    DestroyWindow(g_notification_window);
    g_notification_window = NULL;
  }
  ReleaseSRWLockExclusive(&g_notification_window_lock);
  AcquireSRWLockExclusive(&g_notification_click_lock);
  g_notification_click_head = 0;
  g_notification_click_count = 0;
  ReleaseSRWLockExclusive(&g_notification_click_lock);
  return PROTON_OK;
}

#endif
