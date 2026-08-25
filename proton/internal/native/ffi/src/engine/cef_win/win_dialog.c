#if defined(_WIN32)

#include "win_internal.h"

#include "../../proton_event.h"
#include "../cef_common/message.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <shobjidl.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define PROTON_ENGINE_DIALOG_CLASS L"ProtonNativeMessageDialog"

/* Dialog HWNDs stay on the runtime owner thread. The host loop dispatches
   their messages, and completion crosses into MoonBit through the wake source. */
typedef struct proton_engine_win_dialog_request {
  int64_t id;
  int64_t public_window;
  proton_engine_runtime_t *runtime;
  proton_engine_window_t *window;
  wchar_t *title;
  wchar_t *message;
  wchar_t *ok_label;
  wchar_t *cancel_label;
  HWND dialog;
  HWND icon_control;
  HWND message_control;
  HWND ok_button;
  HWND cancel_button;
  HWND parent;
  int parent_was_enabled;
  int completed;
  int kind;
  int clicked_ok;
  int32_t level;
  struct proton_engine_win_dialog_request *next;
} proton_engine_win_dialog_request_t;

enum {
  PROTON_ENGINE_WIN_DIALOG_KIND_MESSAGE = 0,
  PROTON_ENGINE_WIN_DIALOG_KIND_CONFIRM = 1,
};

enum {
  PROTON_ENGINE_WIN_FILE_DIALOG_OPEN = 0,
  PROTON_ENGINE_WIN_FILE_DIALOG_SAVE = 1,
  PROTON_ENGINE_WIN_FILE_DIALOG_CHOOSE_DIRECTORY = 2,
};

static int64_t g_next_dialog_id = 1;
static proton_engine_win_dialog_request_t *g_dialog_requests = NULL;

static void proton_engine_file_dialog_cancel_window(
    proton_engine_window_t *window);

static wchar_t *proton_engine_dialog_text(const char *text, int32_t text_len) {
  if (text == NULL || text_len <= 0) {
    return (wchar_t *)calloc(1, sizeof(wchar_t));
  }
  int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text,
                                     text_len, NULL, 0);
  if (required <= 0) {
    return NULL;
  }
  wchar_t *result =
      (wchar_t *)calloc((size_t)required + 1, sizeof(wchar_t));
  if (result == NULL ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, text_len,
                          result, required) != required) {
    free(result);
    return NULL;
  }
  return result;
}

static void proton_engine_dialog_free(
    proton_engine_win_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  free(request->title);
  free(request->message);
  free(request->ok_label);
  free(request->cancel_label);
  free(request);
}

static void proton_engine_dialog_remove(
    proton_engine_win_dialog_request_t *request) {
  proton_engine_win_dialog_request_t **cursor = &g_dialog_requests;
  while (*cursor != NULL) {
    if (*cursor == request) {
      *cursor = request->next;
      request->next = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static void proton_engine_dialog_release_parent(
    proton_engine_win_dialog_request_t *request) {
  if (request->parent == NULL || !request->parent_was_enabled) {
    return;
  }
  for (proton_engine_win_dialog_request_t *other = g_dialog_requests;
       other != NULL; other = other->next) {
    if (other != request && other->parent == request->parent &&
        other->dialog != NULL && !other->completed) {
      other->parent_was_enabled = 1;
      request->parent_was_enabled = 0;
      return;
    }
  }
  if (IsWindow(request->parent)) {
    EnableWindow(request->parent, TRUE);
    SetForegroundWindow(request->parent);
  }
  request->parent_was_enabled = 0;
}

static int proton_engine_dialog_scale(HWND hwnd, int value) {
  HDC dc = GetDC(hwnd);
  int dpi = dc != NULL ? GetDeviceCaps(dc, LOGPIXELSX) : 96;
  if (dc != NULL) {
    ReleaseDC(hwnd, dc);
  }
  return MulDiv(value, dpi > 0 ? dpi : 96, 96);
}

static void proton_engine_dialog_layout(
    proton_engine_win_dialog_request_t *request) {
  if (request == NULL || request->dialog == NULL) {
    return;
  }
  RECT client;
  GetClientRect(request->dialog, &client);
  int margin = proton_engine_dialog_scale(request->dialog, 20);
  int icon_size = proton_engine_dialog_scale(request->dialog, 32);
  int gap = proton_engine_dialog_scale(request->dialog, 16);
  int button_width = proton_engine_dialog_scale(request->dialog, 88);
  int button_height = proton_engine_dialog_scale(request->dialog, 28);
  int button_y = client.bottom - margin - button_height;
  int message_x = margin + icon_size + gap;
  int message_width = client.right - message_x - margin;
  int message_height = button_y - margin - gap;
  int button_gap = proton_engine_dialog_scale(request->dialog, 8);
  MoveWindow(request->icon_control, margin, margin, icon_size, icon_size, TRUE);
  MoveWindow(request->message_control, message_x, margin, message_width,
             message_height, TRUE);
  if (request->cancel_button != NULL) {
    int left = client.right - margin - 2 * button_width - button_gap;
    MoveWindow(request->cancel_button, left, button_y, button_width,
               button_height, TRUE);
    MoveWindow(request->ok_button, client.right - margin - button_width,
               button_y, button_width, button_height, TRUE);
  } else {
    MoveWindow(request->ok_button, client.right - margin - button_width,
               button_y, button_width, button_height, TRUE);
  }
}

/* Completing a dialog publishes PROTON_EVENT_DIALOG_COMPLETED so the facade
   can resolve the pending request by id. The event is thread-safe to publish;
   file dialogs that run on a worker thread call this on their own. */
static void proton_engine_publish_dialog_completed(int64_t window,
                                                   int64_t request_id,
                                                   int32_t status,
                                                   const char *result,
                                                   const char *error_message) {
  proton_event_t *event = proton_event_create(PROTON_EVENT_DIALOG_COMPLETED);
  if (event == NULL) {
    return;
  }
  event->window = window;
  event->request_id = request_id;
  event->int_a = status;
  if (proton_event_set_text(
          &event->text_a, status == PROTON_OK && result != NULL ? result : "") &&
      proton_event_set_text(&event->text_b,
                            error_message != NULL ? error_message : "")) {
    (void)proton_event_publish(event);
  } else {
    proton_event_destroy(event);
  }
}

static LRESULT CALLBACK proton_engine_dialog_window_proc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  proton_engine_win_dialog_request_t *request =
      (proton_engine_win_dialog_request_t *)GetWindowLongPtrW(
          hwnd, GWLP_USERDATA);
  if (message == WM_NCCREATE) {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    request = (proton_engine_win_dialog_request_t *)create->lpCreateParams;
    if (request == NULL) {
      return FALSE;
    }
    request->dialog = hwnd;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)request);
  }
  if (request == NULL) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  switch (message) {
  case WM_CREATE: {
    HINSTANCE instance = GetModuleHandleW(NULL);
    request->icon_control = CreateWindowExW(
        0, L"STATIC", NULL, WS_CHILD | WS_VISIBLE | SS_ICON, 0, 0, 0, 0,
        hwnd, NULL, instance, NULL);
    request->message_control = CreateWindowExW(
        0, L"STATIC", request->message,
        WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, hwnd, NULL, instance,
        NULL);
    request->ok_button = CreateWindowExW(
        0, L"BUTTON", request->ok_label,
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 0, 0, 0, 0,
        hwnd, (HMENU)(INT_PTR)IDOK, instance, NULL);
    if (request->kind == PROTON_ENGINE_WIN_DIALOG_KIND_CONFIRM) {
      request->cancel_button = CreateWindowExW(
          0, L"BUTTON", request->cancel_label,
          WS_CHILD | WS_VISIBLE | WS_TABSTOP, 0, 0, 0, 0, hwnd,
          (HMENU)(INT_PTR)IDCANCEL, instance, NULL);
    }
    if (request->icon_control == NULL || request->message_control == NULL ||
        request->ok_button == NULL ||
        (request->kind == PROTON_ENGINE_WIN_DIALOG_KIND_CONFIRM &&
         request->cancel_button == NULL)) {
      return -1;
    }
    HICON icon = LoadIconW(
        NULL, MAKEINTRESOURCEW(request->level == 2
                                    ? IDI_ERROR
                                    : (request->level == 1 ? IDI_WARNING : IDI_INFORMATION)));
    SendMessageW(request->icon_control, STM_SETICON, (WPARAM)icon, 0);
    HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
    SendMessageW(request->message_control, WM_SETFONT, (WPARAM)font, TRUE);
    SendMessageW(request->ok_button, WM_SETFONT, (WPARAM)font, TRUE);
    if (request->cancel_button != NULL) {
      SendMessageW(request->cancel_button, WM_SETFONT, (WPARAM)font, TRUE);
    }
    return 0;
  }
  case WM_SIZE:
    proton_engine_dialog_layout(request);
    return 0;
  case WM_COMMAND:
    if (HIWORD(wparam) == BN_CLICKED) {
      if (LOWORD(wparam) == IDOK) {
        request->clicked_ok = 1;
      } else if (LOWORD(wparam) == IDCANCEL) {
        request->clicked_ok = 0;
      } else {
        break;
      }
      DestroyWindow(hwnd);
      return 0;
    }
    break;
  case WM_CLOSE:
    DestroyWindow(hwnd);
    return 0;
  case WM_DESTROY: {
    proton_engine_runtime_t *runtime = request->runtime;
    request->dialog = NULL;
    request->completed = 1;
    proton_engine_dialog_release_parent(request);
    const char *result =
        request->kind == PROTON_ENGINE_WIN_DIALOG_KIND_CONFIRM
            ? (request->clicked_ok ? "1" : "0")
            : "";
    proton_engine_publish_dialog_completed(
        request->public_window, request->id, PROTON_OK, result, NULL);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    if (runtime != NULL) {
      proton_engine_signal_wait_source(runtime, PROTON_WAIT_PLATFORM);
    }
    return 0;
  }
  case WM_NCDESTROY:
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    return DefWindowProcW(hwnd, message, wparam, lparam);
  default:
    break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static int proton_engine_register_dialog_class(void) {
  HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSEXW existing;
  memset(&existing, 0, sizeof(existing));
  existing.cbSize = sizeof(existing);
  if (GetClassInfoExW(instance, PROTON_ENGINE_DIALOG_CLASS, &existing)) {
    return 1;
  }
  WNDCLASSEXW window_class;
  memset(&window_class, 0, sizeof(window_class));
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = proton_engine_dialog_window_proc;
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(IDC_ARROW));
  window_class.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
  window_class.lpszClassName = PROTON_ENGINE_DIALOG_CLASS;
  return RegisterClassExW(&window_class) != 0 ||
         GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

static void proton_engine_center_dialog(HWND dialog, HWND parent) {
  RECT dialog_rect;
  RECT bounds;
  GetWindowRect(dialog, &dialog_rect);
  if (parent == NULL || !GetWindowRect(parent, &bounds)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &bounds, 0);
  }
  int width = dialog_rect.right - dialog_rect.left;
  int height = dialog_rect.bottom - dialog_rect.top;
  int x = bounds.left + ((bounds.right - bounds.left) - width) / 2;
  int y = bounds.top + ((bounds.bottom - bounds.top) - height) / 2;
  SetWindowPos(dialog, NULL, x, y, 0, 0,
               SWP_NOACTIVATE | SWP_NOSIZE | SWP_NOZORDER);
}

static int32_t proton_engine_begin_message_dialog(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    const char *title_utf8, int32_t title_len, const char *message_utf8,
    int32_t message_len, int32_t level, int64_t *out_dialog, char *error,
    size_t error_len) {
  if (runtime == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog runtime and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  if (runtime->headless || (window != NULL && window->headless)) {
    proton_engine_set_message(
        error, error_len,
        "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window != NULL && window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime->dialog_ok_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog label is not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_win_dialog_request_t *request =
      (proton_engine_win_dialog_request_t *)calloc(1, sizeof(*request));
  if (request == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }
  request->title = proton_engine_dialog_text(title_utf8, title_len);
  request->message = proton_engine_dialog_text(message_utf8, message_len);
  request->ok_label = proton_engine_dialog_text(
      runtime->dialog_ok_label, (int32_t)strlen(runtime->dialog_ok_label));
  if (request->title == NULL || request->message == NULL ||
      request->ok_label == NULL) {
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len, "dialog text is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  request->runtime = runtime;
  request->window = window;
  request->public_window = proton_engine_window_public_id(window);
  request->level = level;
  request->parent = window != NULL ? window->hwnd : NULL;
  request->parent_was_enabled =
      request->parent != NULL && IsWindowEnabled(request->parent);
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id <= 0) {
    g_next_dialog_id = 1;
  }
  request->next = g_dialog_requests;
  g_dialog_requests = request;
  if (!proton_engine_register_dialog_class()) {
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to register native dialog class");
    return PROTON_ERR_PLATFORM;
  }
  UINT dpi = request->parent != NULL ? GetDpiForWindow(request->parent) : 96;
  int width = MulDiv(460, dpi > 0 ? (int)dpi : 96, 96);
  int height = MulDiv(210, dpi > 0 ? (int)dpi : 96, 96);
  if (request->parent_was_enabled) {
    EnableWindow(request->parent, FALSE);
  }
  HWND dialog_window = CreateWindowExW(
      WS_EX_DLGMODALFRAME, PROTON_ENGINE_DIALOG_CLASS, request->title,
      WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, CW_USEDEFAULT,
      CW_USEDEFAULT, width, height, request->parent, NULL, GetModuleHandleW(NULL),
      request);
  if (dialog_window == NULL) {
    if (request->parent_was_enabled) {
      EnableWindow(request->parent, TRUE);
    }
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to create native message dialog");
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_center_dialog(dialog_window, request->parent);
  ShowWindow(dialog_window, SW_SHOW);
  SetForegroundWindow(dialog_window);
  SetFocus(request->ok_button);
  *out_dialog = request->id;
  return PROTON_OK;
}

static void proton_engine_dialog_cancel_matching(
    proton_engine_runtime_t *runtime, proton_engine_window_t *window,
    int match_window) {
  for (;;) {
    proton_engine_win_dialog_request_t *request = g_dialog_requests;
    while (request != NULL &&
           (request->runtime != runtime ||
            (match_window && request->window != window))) {
      request = request->next;
    }
    if (request == NULL) {
      return;
    }
    if (request->dialog != NULL) {
      if (DestroyWindow(request->dialog)) {
        // WM_DESTROY published the completion event, then removed and freed
        // this request. Restart the scan to pick up the next match.
        continue;
      }
    }
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
  }
}

void proton_engine_dialog_cancel_runtime(
    proton_engine_runtime_t *runtime) {
  proton_engine_dialog_cancel_matching(runtime, NULL, 0);
}

void proton_engine_dialog_cancel_window(proton_engine_window_t *window) {
  if (window != NULL) {
    proton_engine_dialog_cancel_matching(window->runtime, window, 1);
    proton_engine_file_dialog_cancel_window(window);
  }
}

int32_t proton_engine_runtime_begin_message_dialog(
    proton_engine_runtime_t *runtime, const char *title_utf8,
    int32_t title_len, const char *message_utf8, int32_t message_len,
    int32_t level, int64_t *out_dialog, char *error, size_t error_len) {
  return proton_engine_begin_message_dialog(
      runtime, NULL, title_utf8, title_len, message_utf8, message_len, level,
      out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_message_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_begin_message_dialog(
      window != NULL ? window->runtime : NULL, window, title_utf8, title_len,
      message_utf8, message_len, level, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_confirm_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *message_utf8,
    int32_t message_len,
    int32_t level,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  if (window == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog window and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  proton_engine_runtime_t *runtime = window->runtime;
  if (window->headless || (runtime != NULL && runtime->headless)) {
    proton_engine_set_message(error, error_len,
                              "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (runtime->dialog_ok_label[0] == '\0' ||
      runtime->dialog_cancel_label[0] == '\0') {
    proton_engine_set_message(error, error_len,
                              "runtime dialog labels are not configured");
    return PROTON_ERR_NOT_INITIALIZED;
  }
  proton_engine_win_dialog_request_t *request =
      (proton_engine_win_dialog_request_t *)calloc(1, sizeof(*request));
  if (request == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }
  request->title = proton_engine_dialog_text(title_utf8, title_len);
  request->message = proton_engine_dialog_text(message_utf8, message_len);
  request->ok_label = proton_engine_dialog_text(
      runtime->dialog_ok_label, (int32_t)strlen(runtime->dialog_ok_label));
  request->cancel_label = proton_engine_dialog_text(
      runtime->dialog_cancel_label,
      (int32_t)strlen(runtime->dialog_cancel_label));
  if (request->title == NULL || request->message == NULL ||
      request->ok_label == NULL || request->cancel_label == NULL) {
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "dialog text is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  request->runtime = runtime;
  request->window = window;
  request->public_window = proton_engine_window_public_id(window);
  request->level = level;
  request->parent = window->hwnd;
  request->parent_was_enabled = IsWindowEnabled(request->parent);
  request->kind = PROTON_ENGINE_WIN_DIALOG_KIND_CONFIRM;
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id <= 0) {
    g_next_dialog_id = 1;
  }
  request->next = g_dialog_requests;
  g_dialog_requests = request;
  if (!proton_engine_register_dialog_class()) {
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to register native dialog class");
    return PROTON_ERR_PLATFORM;
  }
  UINT dpi = request->parent != NULL ? GetDpiForWindow(request->parent) : 96;
  int width = MulDiv(460, dpi > 0 ? (int)dpi : 96, 96);
  int height = MulDiv(210, dpi > 0 ? (int)dpi : 96, 96);
  if (request->parent_was_enabled) {
    EnableWindow(request->parent, FALSE);
  }
  HWND dialog_window = CreateWindowExW(
      WS_EX_DLGMODALFRAME, PROTON_ENGINE_DIALOG_CLASS, request->title,
      WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN, CW_USEDEFAULT,
      CW_USEDEFAULT, width, height, request->parent, NULL,
      GetModuleHandleW(NULL), request);
  if (dialog_window == NULL) {
    if (request->parent_was_enabled) {
      EnableWindow(request->parent, TRUE);
    }
    proton_engine_dialog_remove(request);
    proton_engine_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to create native confirm dialog");
    return PROTON_ERR_PLATFORM;
  }
  proton_engine_center_dialog(dialog_window, request->parent);
  ShowWindow(dialog_window, SW_SHOW);
  SetForegroundWindow(dialog_window);
  SetFocus(request->ok_button);
  *out_dialog = request->id;
  return PROTON_OK;
}

/* File dialogs run on a worker thread with IFileDialog because Show() drains
   a private modal message loop that would otherwise block the CEF host loop.
   On completion the worker publishes PROTON_EVENT_DIALOG_COMPLETED (matching
   the macOS async lifecycle) and frees its own request. */
typedef struct proton_engine_win_file_dialog_request {
  int64_t id;
  int64_t public_window;
  HWND parent;
  HWND cancel_window;
  IFileDialog *dialog;
  volatile LONG cancel_requested;
  wchar_t *title;
  wchar_t *initial_path;
  int mode;
  struct proton_engine_win_file_dialog_request *next;
} proton_engine_win_file_dialog_request_t;

static proton_engine_win_file_dialog_request_t *g_file_dialog_requests = NULL;
static INIT_ONCE g_file_dialog_lock_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION g_file_dialog_lock;

#define PROTON_ENGINE_FILE_DIALOG_CANCEL_MESSAGE (WM_APP + 0x51)
#define PROTON_ENGINE_FILE_DIALOG_CANCEL_CLASS                            \
  L"ProtonNativeFileDialogCancel"

static LRESULT CALLBACK proton_engine_file_dialog_cancel_proc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  proton_engine_win_file_dialog_request_t *request =
      (proton_engine_win_file_dialog_request_t *)GetWindowLongPtrW(
          hwnd, GWLP_USERDATA);
  if (message == WM_NCCREATE) {
    CREATESTRUCTW *create = (CREATESTRUCTW *)lparam;
    request = (proton_engine_win_file_dialog_request_t *)create->lpCreateParams;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)request);
  }
  if (message == PROTON_ENGINE_FILE_DIALOG_CANCEL_MESSAGE &&
      request != NULL && request->dialog != NULL) {
    (void)request->dialog->lpVtbl->Close(
        request->dialog, HRESULT_FROM_WIN32(ERROR_CANCELLED));
    return 0;
  }
  if (message == WM_NCDESTROY) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

static int proton_engine_register_file_dialog_cancel_class(void) {
  HINSTANCE instance = GetModuleHandleW(NULL);
  WNDCLASSEXW existing;
  memset(&existing, 0, sizeof(existing));
  existing.cbSize = sizeof(existing);
  if (GetClassInfoExW(instance, PROTON_ENGINE_FILE_DIALOG_CANCEL_CLASS,
                      &existing)) {
    return 1;
  }
  WNDCLASSEXW window_class;
  memset(&window_class, 0, sizeof(window_class));
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = proton_engine_file_dialog_cancel_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = PROTON_ENGINE_FILE_DIALOG_CANCEL_CLASS;
  return RegisterClassExW(&window_class) != 0;
}

static char *proton_engine_wide_to_utf8(const wchar_t *value) {
  if (value == NULL) {
    return NULL;
  }
  int required = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (required <= 0) {
    return NULL;
  }
  char *result = (char *)calloc((size_t)required, 1);
  if (result == NULL) {
    return NULL;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, result, required, NULL,
                          NULL) <= 0) {
    free(result);
    return NULL;
  }
  return result;
}

static void proton_engine_set_initial_location(IFileDialog *dialog,
                                               const wchar_t *path,
                                               int mode) {
  if (dialog == NULL || path == NULL || path[0] == L'\0') {
    return;
  }
  wchar_t folder[32768];
  wchar_t name[1024];
  folder[0] = L'\0';
  name[0] = L'\0';
  DWORD attributes = GetFileAttributesW(path);
  BOOL is_directory = attributes != INVALID_FILE_ATTRIBUTES &&
                      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  if (is_directory) {
    wcsncpy(folder, path, sizeof(folder) / sizeof(folder[0]) - 1);
    folder[sizeof(folder) / sizeof(folder[0]) - 1] = L'\0';
  } else {
    const wchar_t *slash = NULL;
    for (const wchar_t *cursor = path; *cursor != L'\0'; ++cursor) {
      if (*cursor == L'\\' || *cursor == L'/') {
        slash = cursor;
      }
    }
    if (slash != NULL) {
      size_t directory_length = (size_t)(slash - path);
      if (directory_length > 0 &&
          directory_length < sizeof(folder) / sizeof(folder[0])) {
        memcpy(folder, path, directory_length * sizeof(wchar_t));
        folder[directory_length] = L'\0';
      }
      if (slash[1] != L'\0') {
        wcsncpy(name, slash + 1, sizeof(name) / sizeof(name[0]) - 1);
        name[sizeof(name) / sizeof(name[0]) - 1] = L'\0';
      }
    } else {
      wcsncpy(name, path, sizeof(name) / sizeof(name[0]) - 1);
      name[sizeof(name) / sizeof(name[0]) - 1] = L'\0';
    }
  }
  if (folder[0] != L'\0') {
    IShellItem *item = NULL;
    if (SUCCEEDED(SHCreateItemFromParsingName(folder, NULL, &IID_IShellItem,
                                              (void **)&item)) &&
        item != NULL) {
      (void)dialog->lpVtbl->SetFolder(dialog, item);
      item->lpVtbl->Release(item);
    }
  }
  if (mode == PROTON_ENGINE_WIN_FILE_DIALOG_SAVE && name[0] != L'\0') {
    (void)dialog->lpVtbl->SetFileName(dialog, name);
  }
}

static BOOL CALLBACK proton_engine_file_dialog_lock_initialize(
    PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once;
  (void)parameter;
  (void)context;
  InitializeCriticalSection(&g_file_dialog_lock);
  return TRUE;
}

static void proton_engine_file_dialog_lock_init(void) {
  (void)InitOnceExecuteOnce(&g_file_dialog_lock_once,
                            proton_engine_file_dialog_lock_initialize, NULL,
                            NULL);
}

static proton_engine_win_file_dialog_request_t *proton_engine_file_dialog_add(
    proton_engine_win_file_dialog_request_t *request) {
  EnterCriticalSection(&g_file_dialog_lock);
  request->next = g_file_dialog_requests;
  g_file_dialog_requests = request;
  LeaveCriticalSection(&g_file_dialog_lock);
  return request;
}

static void proton_engine_file_dialog_remove(
    proton_engine_win_file_dialog_request_t *request) {
  EnterCriticalSection(&g_file_dialog_lock);
  proton_engine_win_file_dialog_request_t **cursor = &g_file_dialog_requests;
  while (*cursor != NULL) {
    if (*cursor == request) {
      *cursor = request->next;
      request->next = NULL;
      break;
    }
    cursor = &(*cursor)->next;
  }
  LeaveCriticalSection(&g_file_dialog_lock);
}

static void proton_engine_file_dialog_free(
    proton_engine_win_file_dialog_request_t *request) {
  if (request == NULL) {
    return;
  }
  free(request->title);
  free(request->initial_path);
  free(request);
}

static DWORD WINAPI proton_engine_file_dialog_thread(LPVOID param) {
  proton_engine_win_file_dialog_request_t *request =
      (proton_engine_win_file_dialog_request_t *)param;
  char *result_path = NULL;
  HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  BOOL com_ok = SUCCEEDED(hr);
  IFileDialog *filedialog = NULL;
  if (com_ok) {
    if (request->mode == PROTON_ENGINE_WIN_FILE_DIALOG_SAVE) {
      hr = CoCreateInstance(&CLSID_FileSaveDialog, NULL, CLSCTX_INPROC_SERVER,
                            &IID_IFileDialog, (void **)&filedialog);
    } else {
      hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
                            &IID_IFileDialog, (void **)&filedialog);
    }
  }
  if (SUCCEEDED(hr) && filedialog != NULL) {
    HWND cancel_window = NULL;
    if (proton_engine_register_file_dialog_cancel_class()) {
      cancel_window = CreateWindowExW(
          0, PROTON_ENGINE_FILE_DIALOG_CANCEL_CLASS, L"", 0, 0, 0, 0, 0,
          HWND_MESSAGE, NULL, GetModuleHandleW(NULL), request);
    }
    EnterCriticalSection(&g_file_dialog_lock);
    request->dialog = filedialog;
    request->cancel_window = cancel_window;
    LONG cancelled = request->cancel_requested;
    LeaveCriticalSection(&g_file_dialog_lock);
    if (request->title != NULL && request->title[0] != L'\0') {
      (void)filedialog->lpVtbl->SetTitle(filedialog, request->title);
    }
    DWORD options = FOS_OVERWRITEPROMPT;
    if (request->mode == PROTON_ENGINE_WIN_FILE_DIALOG_CHOOSE_DIRECTORY) {
      options |= FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM;
    } else if (request->mode == PROTON_ENGINE_WIN_FILE_DIALOG_OPEN) {
      options |= FOS_FILEMUSTEXIST;
    }
    (void)filedialog->lpVtbl->SetOptions(filedialog, options);
    proton_engine_set_initial_location(filedialog, request->initial_path,
                                       request->mode);
    if (!cancelled) {
      hr = filedialog->lpVtbl->Show(filedialog, request->parent);
    } else {
      hr = HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }
    if (SUCCEEDED(hr)) {
      IShellItem *selected = NULL;
      if (SUCCEEDED(filedialog->lpVtbl->GetResult(filedialog, &selected)) &&
          selected != NULL) {
        wchar_t *display = NULL;
        if (SUCCEEDED(selected->lpVtbl->GetDisplayName(
                selected, SIGDN_FILESYSPATH, &display)) &&
            display != NULL) {
          result_path = proton_engine_wide_to_utf8(display);
          CoTaskMemFree(display);
        }
        selected->lpVtbl->Release(selected);
      }
    }
    EnterCriticalSection(&g_file_dialog_lock);
    request->dialog = NULL;
    request->cancel_window = NULL;
    LeaveCriticalSection(&g_file_dialog_lock);
    if (cancel_window != NULL) {
      DestroyWindow(cancel_window);
    }
    filedialog->lpVtbl->Release(filedialog);
  }
  if (com_ok) {
    CoUninitialize();
  }
  proton_engine_publish_dialog_completed(
      request->public_window, request->id, PROTON_OK,
      result_path != NULL ? result_path : "", NULL);
  free(result_path);
  proton_engine_file_dialog_remove(request);
  proton_engine_file_dialog_free(request);
  return 0;
}

static int32_t proton_engine_window_begin_file_dialog(
    proton_engine_window_t *window, const char *title_utf8, int32_t title_len,
    const char *path_utf8, int32_t path_len, int32_t mode, int64_t *out_dialog,
    char *error, size_t error_len) {
  if (window == NULL || out_dialog == NULL) {
    proton_engine_set_message(error, error_len,
                              "dialog window and output are required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_dialog = PROTON_INVALID_HANDLE;
  proton_engine_runtime_t *runtime = window->runtime;
  if (window->headless || (runtime != NULL && runtime->headless)) {
    proton_engine_set_message(error, error_len,
                              "native dialogs are not supported in headless mode");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (window->hwnd == NULL) {
    proton_engine_set_message(error, error_len, "window is not initialized");
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_engine_file_dialog_lock_init();
  proton_engine_win_file_dialog_request_t *request =
      (proton_engine_win_file_dialog_request_t *)calloc(
          1, sizeof(*request));
  if (request == NULL) {
    proton_engine_set_message(error, error_len,
                              "failed to allocate dialog request");
    return PROTON_ERR_ENGINE;
  }
  request->title = proton_engine_dialog_text(title_utf8, title_len);
  request->initial_path = proton_engine_dialog_text(path_utf8, path_len);
  if (request->title == NULL || request->initial_path == NULL) {
    proton_engine_file_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "dialog text is not valid UTF-8");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  request->public_window = proton_engine_window_public_id(window);
  request->parent = window->hwnd;
  request->mode = mode;
  request->id = g_next_dialog_id++;
  if (g_next_dialog_id <= 0) {
    g_next_dialog_id = 1;
  }
  proton_engine_file_dialog_add(request);
  HANDLE thread = CreateThread(NULL, 0, proton_engine_file_dialog_thread,
                               request, 0, NULL);
  if (thread == NULL) {
    proton_engine_file_dialog_remove(request);
    proton_engine_file_dialog_free(request);
    proton_engine_set_message(error, error_len,
                              "failed to start file dialog thread");
    return PROTON_ERR_ENGINE;
  }
  CloseHandle(thread);
  *out_dialog = request->id;
  return PROTON_OK;
}

static int proton_engine_file_dialog_request_cancel(
    proton_engine_window_t *window, int64_t dialog, int match_id) {
  int matched = 0;
  proton_engine_file_dialog_lock_init();
  EnterCriticalSection(&g_file_dialog_lock);
  int64_t public_window = proton_engine_window_public_id(window);
  for (proton_engine_win_file_dialog_request_t *request =
           g_file_dialog_requests;
       request != NULL; request = request->next) {
    if (request->public_window != public_window ||
        (match_id && request->id != dialog)) {
      continue;
    }
    InterlockedExchange(&request->cancel_requested, 1);
    if (request->cancel_window != NULL) {
      (void)PostMessageW(request->cancel_window,
                         PROTON_ENGINE_FILE_DIALOG_CANCEL_MESSAGE, 0, 0);
    }
    matched = 1;
    if (match_id) {
      break;
    }
  }
  LeaveCriticalSection(&g_file_dialog_lock);
  return matched;
}

static void proton_engine_file_dialog_cancel_window(
    proton_engine_window_t *window) {
  if (window != NULL) {
    (void)proton_engine_file_dialog_request_cancel(window, 0, 0);
  }
}

int32_t proton_engine_window_begin_open_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_WIN_FILE_DIALOG_OPEN, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_save_file_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_WIN_FILE_DIALOG_SAVE, out_dialog, error, error_len);
}

int32_t proton_engine_window_begin_choose_directory_dialog(
    proton_engine_window_t *window,
    const char *title_utf8,
    int32_t title_len,
    const char *path_utf8,
    int32_t path_len,
    int64_t *out_dialog,
    char *error,
    size_t error_len) {
  return proton_engine_window_begin_file_dialog(
      window, title_utf8, title_len, path_utf8, path_len,
      PROTON_ENGINE_WIN_FILE_DIALOG_CHOOSE_DIRECTORY, out_dialog, error,
      error_len);
}

int32_t proton_engine_window_cancel_dialog(proton_engine_window_t *window,
                                           int64_t dialog,
                                           char *error,
                                           size_t error_len) {
  if (window == NULL) {
    proton_engine_set_message(error, error_len, "window is required");
    return PROTON_ERR_INVALID_HANDLE;
  }
  for (proton_engine_win_dialog_request_t *request = g_dialog_requests;
       request != NULL; request = request->next) {
    if (request->window == window && request->id == dialog) {
      if (request->dialog != NULL) {
        DestroyWindow(request->dialog);
      }
      return PROTON_OK;
    }
  }
  (void)proton_engine_file_dialog_request_cancel(window, dialog, 1);
  return PROTON_OK;
}

#endif
