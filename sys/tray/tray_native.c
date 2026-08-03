#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#ifdef _MSC_VER
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")
#endif
#elif defined(__linux__)
#include <dlfcn.h>
#include <pthread.h>
#include <sys/stat.h>
#elif defined(__APPLE__)
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#endif

#ifndef _WIN32
#include <unistd.h>
#endif

#include "moonbit.h"

#define MOONBIT_TRAY_MAX_EVENTS 32
#define MOONBIT_TRAY_MAX_EVENT_BYTES 1024
#define MOONBIT_TRAY_MAX_MENU_ITEMS 64
#define MOONBIT_TRAY_MAX_MENU_ID_BYTES 128
#define MOONBIT_TRAY_MAX_MENU_DEPTH 8

#ifdef _WIN32
#define MOONBIT_TRAY_CALLBACK_MESSAGE (WM_APP + 1)
#define MOONBIT_TRAY_COMMAND_BASE 0x7000
#endif

typedef struct moonbit_tray_state {
#ifdef _WIN32
  HWND hwnd;
  NOTIFYICONDATAW icon_data;
  int32_t icon_owned;
  HMENU menu;
  HMENU pending_menu;
  HMENU menu_stack[MOONBIT_TRAY_MAX_MENU_DEPTH + 1];
  uint32_t menu_depth;
  char menu_item_ids[MOONBIT_TRAY_MAX_MENU_ITEMS][MOONBIT_TRAY_MAX_MENU_ID_BYTES];
  uint32_t menu_item_count;
  char pending_menu_item_ids[MOONBIT_TRAY_MAX_MENU_ITEMS]
                            [MOONBIT_TRAY_MAX_MENU_ID_BYTES];
  uint32_t pending_menu_item_count;
#elif defined(__linux__)
  void *indicator;
  void *menu;
  void *pending_menu;
  void *menu_stack[MOONBIT_TRAY_MAX_MENU_DEPTH + 1];
  uint32_t menu_depth;
  uint32_t pending_menu_item_count;
#elif defined(__APPLE__)
  void *pool;
  void *app;
  void *status_bar;
  void *status_item;
  void *button;
  void *menu;
  void *pending_menu;
  void *menu_stack[MOONBIT_TRAY_MAX_MENU_DEPTH + 1];
  uint32_t menu_depth;
  uint32_t pending_menu_item_count;
  void *menu_target;
#endif
  int32_t visible;
  char events[MOONBIT_TRAY_MAX_EVENTS][MOONBIT_TRAY_MAX_EVENT_BYTES];
  uint32_t event_head;
  uint32_t event_count;
  char last_error[256];
} moonbit_tray_state_t;

static char moonbit_tray_create_error[256];
static char moonbit_tray_support_message[256];

#define MOONBIT_TRAY_MAX_STATES 16

#ifdef _WIN32
typedef DWORD moonbit_tray_thread_id_t;

static moonbit_tray_thread_id_t moonbit_tray_thread_self(void) {
  return GetCurrentThreadId();
}

static int32_t moonbit_tray_thread_equal(
    moonbit_tray_thread_id_t left,
    moonbit_tray_thread_id_t right) {
  return left == right;
}
#elif defined(__linux__) || defined(__APPLE__)
typedef pthread_t moonbit_tray_thread_id_t;

static moonbit_tray_thread_id_t moonbit_tray_thread_self(void) {
  return pthread_self();
}

static int32_t moonbit_tray_thread_equal(
    moonbit_tray_thread_id_t left,
    moonbit_tray_thread_id_t right) {
  return pthread_equal(left, right);
}
#else
typedef int moonbit_tray_thread_id_t;

static moonbit_tray_thread_id_t moonbit_tray_thread_self(void) {
  return 0;
}

static int32_t moonbit_tray_thread_equal(
    moonbit_tray_thread_id_t left,
    moonbit_tray_thread_id_t right) {
  return left == right;
}
#endif

typedef struct {
  moonbit_tray_state_t *state;  /* NULL = slot free */
  uint32_t generation;          /* bumped on each insert, skips 0 */
  moonbit_tray_thread_id_t owner;  /* creating thread */
} moonbit_tray_slot_t;

/*
 * No mutex protects g_tray_slots: all legal FFI calls and native callbacks
 * run on the slot's owner thread (callbacks fire synchronously inside pump),
 * and the owner check rejects foreign-thread calls before any slot pointer
 * is handed out. A mutex held across calls would deadlock on pump's
 * synchronous callbacks. Concurrent create from multiple threads is not
 * supported.
 */
static moonbit_tray_slot_t g_tray_slots[MOONBIT_TRAY_MAX_STATES];

static moonbit_tray_slot_t *moonbit_tray_registry_lookup(int64_t handle) {
  uint32_t index;
  uint32_t generation;
  moonbit_tray_slot_t *slot;
  if (handle <= 0) {
    return NULL;
  }
  index = (uint32_t)((uint64_t)handle & 0xFFFFFFFFu);
  generation = (uint32_t)((uint64_t)handle >> 32);
  if (index == 0 || index > MOONBIT_TRAY_MAX_STATES || generation == 0) {
    return NULL;
  }
  slot = &g_tray_slots[index - 1];
  if (slot->generation != generation || slot->state == NULL) {
    return NULL;
  }
  if (!moonbit_tray_thread_equal(slot->owner, moonbit_tray_thread_self())) {
    return NULL;
  }
  return slot;
}

static moonbit_tray_state_t *moonbit_tray_from_handle(int64_t handle) {
  moonbit_tray_slot_t *slot = moonbit_tray_registry_lookup(handle);
  if (slot == NULL) {
    return NULL;
  }
  return slot->state;
}

/* Handle 0 stays permanently invalid: slot indexes are stored +1. */
static int64_t moonbit_tray_registry_insert(moonbit_tray_state_t *state) {
  uint32_t index;
  for (index = 0; index < MOONBIT_TRAY_MAX_STATES; index++) {
    moonbit_tray_slot_t *slot = &g_tray_slots[index];
    if (slot->state != NULL) {
      continue;
    }
    slot->generation++;
    if (slot->generation == 0 || slot->generation > 0x7FFFFFFFu) {
      /* Keep the packed handle positive: bit 63 must stay clear. */
      slot->generation = 1;
    }
    slot->state = state;
    slot->owner = moonbit_tray_thread_self();
    return ((int64_t)slot->generation << 32) | (int64_t)(index + 1);
  }
  return 0;
}

static moonbit_tray_state_t *moonbit_tray_registry_invalidate(int64_t handle) {
  moonbit_tray_slot_t *slot = moonbit_tray_registry_lookup(handle);
  moonbit_tray_state_t *state;
  if (slot == NULL) {
    return NULL;
  }
  state = slot->state;
  slot->state = NULL;
  return state;
}

static const char *moonbit_tray_text_or(const char *value, const char *fallback) {
  if (value == NULL || value[0] == '\0') {
    return fallback;
  }
  return value;
}

static void moonbit_tray_set_message(char *buffer, size_t size, const char *message) {
  if (size == 0) {
    return;
  }
  if (message == NULL) {
    buffer[0] = '\0';
    return;
  }
  snprintf(buffer, size, "%s", message);
}

static void moonbit_tray_clear_message(char *buffer, size_t size) {
  moonbit_tray_set_message(buffer, size, "");
}

static moonbit_bytes_t moonbit_tray_copy_message(const char *message) {
  int32_t len;
  moonbit_bytes_t bytes;
  if (message == NULL) {
    message = "";
  }
  len = (int32_t)strlen(message);
  bytes = moonbit_make_bytes(len, 0);
  if (len > 0) {
    memcpy(bytes, message, (size_t)len);
  }
  return bytes;
}

static int32_t moonbit_tray_enqueue_event(
    moonbit_tray_state_t *state,
    const char *event_json) {
  if (state == NULL || event_json == NULL) {
    return 0;
  }
  size_t len = strlen(event_json);
  if (len >= MOONBIT_TRAY_MAX_EVENT_BYTES) {
    return 0;
  }
  if (state->event_count >= MOONBIT_TRAY_MAX_EVENTS) {
    state->events[state->event_head][0] = '\0';
    state->event_head = (state->event_head + 1) % MOONBIT_TRAY_MAX_EVENTS;
    state->event_count--;
  }
  uint32_t index =
      (state->event_head + state->event_count) % MOONBIT_TRAY_MAX_EVENTS;
  memcpy(state->events[index], event_json, len + 1);
  state->event_count++;
  return 1;
}

static int32_t moonbit_tray_json_escape_string(
    char *out,
    size_t out_len,
    const char *value) {
  size_t written = 0;
  if (out == NULL || out_len == 0 || value == NULL) {
    return 0;
  }
  for (const unsigned char *cursor = (const unsigned char *)value;
       *cursor != '\0';
       cursor++) {
    char escaped[8];
    const char *chunk = escaped;
    switch (*cursor) {
    case '"':
      chunk = "\\\"";
      break;
    case '\\':
      chunk = "\\\\";
      break;
    case '\b':
      chunk = "\\b";
      break;
    case '\f':
      chunk = "\\f";
      break;
    case '\n':
      chunk = "\\n";
      break;
    case '\r':
      chunk = "\\r";
      break;
    case '\t':
      chunk = "\\t";
      break;
    default:
      if (*cursor < 0x20) {
        snprintf(escaped, sizeof(escaped), "\\u%04x", *cursor);
      } else {
        escaped[0] = (char)*cursor;
        escaped[1] = '\0';
      }
      break;
    }
    size_t chunk_len = strlen(chunk);
    if (written + chunk_len >= out_len) {
      return 0;
    }
    memcpy(out + written, chunk, chunk_len);
    written += chunk_len;
  }
  out[written] = '\0';
  return 1;
}

static int32_t moonbit_tray_enqueue_menu_event(
    moonbit_tray_state_t *state,
    const char *item_id) {
  char escaped[MOONBIT_TRAY_MAX_MENU_ID_BYTES * 6];
  char event_json[MOONBIT_TRAY_MAX_EVENT_BYTES];
  if (!moonbit_tray_json_escape_string(escaped, sizeof(escaped), item_id)) {
    return 0;
  }
  int written = snprintf(
      event_json,
      sizeof(event_json),
      "{\"type\":\"menuItemClick\",\"item_id\":\"%s\"}",
      escaped);
  if (written < 0 || written >= (int)sizeof(event_json)) {
    return 0;
  }
  return moonbit_tray_enqueue_event(state, event_json);
}

static char *moonbit_tray_strdup(const char *value) {
  size_t len;
  char *copy;
  if (value == NULL) {
    return NULL;
  }
  len = strlen(value);
  copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, value, len + 1);
  return copy;
}

#ifdef _WIN32
static ATOM moonbit_tray_window_class = 0;

static void moonbit_tray_win_destroy_menu(moonbit_tray_state_t *state) {
  if (state == NULL) {
    return;
  }
  if (state->menu != NULL) {
    DestroyMenu(state->menu);
    state->menu = NULL;
  }
  state->menu_item_count = 0;
  memset(state->menu_item_ids, 0, sizeof(state->menu_item_ids));
}

static void moonbit_tray_win_destroy_pending_menu(moonbit_tray_state_t *state) {
  if (state == NULL) {
    return;
  }
  if (state->pending_menu != NULL) {
    DestroyMenu(state->pending_menu);
    state->pending_menu = NULL;
  }
  state->menu_depth = 0;
  state->pending_menu_item_count = 0;
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
  memset(state->pending_menu_item_ids, 0, sizeof(state->pending_menu_item_ids));
}

static HMENU moonbit_tray_win_current_pending_menu(
    moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL ||
      state->menu_depth == 0) {
    return NULL;
  }
  return state->menu_stack[state->menu_depth - 1];
}

static uint32_t moonbit_tray_win_command_index(uint32_t command_id) {
  if (command_id < MOONBIT_TRAY_COMMAND_BASE) {
    return UINT32_MAX;
  }
  return command_id - MOONBIT_TRAY_COMMAND_BASE;
}

static void moonbit_tray_win_show_menu(moonbit_tray_state_t *state) {
  if (state == NULL || state->menu == NULL) {
    return;
  }
  POINT cursor;
  if (!GetCursorPos(&cursor)) {
    return;
  }
  SetForegroundWindow(state->hwnd);
  TrackPopupMenu(
      state->menu,
      TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
      cursor.x,
      cursor.y,
      0,
      state->hwnd,
      NULL);
  PostMessageW(state->hwnd, WM_NULL, 0, 0);
}

static LRESULT CALLBACK moonbit_tray_window_proc(
    HWND hwnd,
    UINT message,
    WPARAM w_param,
    LPARAM l_param) {
  moonbit_tray_state_t *state =
      (moonbit_tray_state_t *)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  if (message == MOONBIT_TRAY_CALLBACK_MESSAGE && state != NULL) {
    switch ((UINT)l_param) {
    case WM_LBUTTONUP:
      moonbit_tray_enqueue_event(state, "{\"type\":\"click\"}");
      return 0;
    case WM_RBUTTONUP:
      moonbit_tray_enqueue_event(state, "{\"type\":\"rightClick\"}");
      moonbit_tray_win_show_menu(state);
      return 0;
    case WM_LBUTTONDBLCLK:
      moonbit_tray_enqueue_event(state, "{\"type\":\"doubleClick\"}");
      return 0;
    default:
      return 0;
    }
  }
  switch (message) {
  case WM_COMMAND:
    if (state != NULL) {
      uint32_t index = moonbit_tray_win_command_index(LOWORD(w_param));
      if (index < state->menu_item_count) {
        moonbit_tray_enqueue_menu_event(state, state->menu_item_ids[index]);
        return 0;
      }
    }
    break;
  case WM_CLOSE:
    DestroyWindow(hwnd);
    return 0;
  case WM_DESTROY:
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)NULL);
    return 0;
  default:
    return DefWindowProcW(hwnd, message, w_param, l_param);
  }
  return DefWindowProcW(hwnd, message, w_param, l_param);
}

static int32_t moonbit_tray_ensure_window_class(void) {
  WNDCLASSEXW wc;
  if (moonbit_tray_window_class != 0) {
    return 1;
  }
  memset(&wc, 0, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = moonbit_tray_window_proc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = L"MoonBitTrayWindow";
  moonbit_tray_window_class = RegisterClassExW(&wc);
  return moonbit_tray_window_class != 0;
}

static wchar_t *moonbit_tray_utf8_cstr_to_wide(const char *text) {
  int32_t units;
  wchar_t *wide;
  if (text == NULL || text[0] == '\0') {
    return NULL;
  }
  units = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
  if (units <= 0) {
    return NULL;
  }
  wide = (wchar_t *)calloc((size_t)units, sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, 0, text, -1, wide, units) <= 0) {
    free(wide);
    return NULL;
  }
  return wide;
}

static wchar_t *moonbit_tray_utf8_to_wide(moonbit_bytes_t value) {
  return moonbit_tray_utf8_cstr_to_wide((const char *)value);
}

static void moonbit_tray_copy_tooltip(
    NOTIFYICONDATAW *icon_data,
    moonbit_bytes_t tooltip) {
  wchar_t *wide = moonbit_tray_utf8_to_wide(tooltip);
  if (wide == NULL) {
    icon_data->szTip[0] = L'\0';
    return;
  }
  wcsncpy(icon_data->szTip, wide, 127);
  icon_data->szTip[127] = L'\0';
  free(wide);
}

static HICON moonbit_tray_load_icon(
    moonbit_bytes_t icon,
    int32_t *owned) {
  wchar_t *path = moonbit_tray_utf8_to_wide(icon);
  HICON loaded = NULL;
  if (owned != NULL) {
    *owned = 0;
  }
  if (path != NULL) {
    loaded = (HICON)LoadImageW(
        NULL,
        path,
        IMAGE_ICON,
        0,
        0,
        LR_DEFAULTSIZE | LR_LOADFROMFILE);
    if (loaded != NULL && owned != NULL) {
      *owned = 1;
    }
    if (loaded == NULL) {
      ExtractIconExW(path, 0, NULL, &loaded, 1);
      if (loaded != NULL && owned != NULL) {
        *owned = 1;
      }
    }
    free(path);
  }
  if (loaded == NULL) {
    loaded = LoadIconW(NULL, (LPCWSTR)IDI_APPLICATION);
  }
  return loaded;
}

static void moonbit_tray_destroy_icon_if_owned(
    HICON icon,
    int32_t owned) {
  if (owned && icon != NULL) {
    DestroyIcon(icon);
  }
}

static void moonbit_tray_commit_icon(
    moonbit_tray_state_t *state,
    HICON next_icon,
    int32_t next_icon_owned) {
  HICON old_icon = state->icon_data.hIcon;
  int32_t old_icon_owned = state->icon_owned;
  state->icon_data.hIcon = next_icon;
  state->icon_owned = next_icon_owned;
  state->icon_data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  if (old_icon != next_icon) {
    moonbit_tray_destroy_icon_if_owned(old_icon, old_icon_owned);
  }
}

static int32_t moonbit_tray_replace_icon(
    moonbit_tray_state_t *state,
    moonbit_bytes_t icon) {
  int32_t next_icon_owned = 0;
  HICON next_icon = moonbit_tray_load_icon(icon, &next_icon_owned);
  if (next_icon == NULL) {
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "failed to load tray icon");
    return 0;
  }
  moonbit_tray_commit_icon(state, next_icon, next_icon_owned);
  return 1;
}

static int32_t moonbit_tray_win_append_clickable_menu_item(
    moonbit_tray_state_t *state,
    moonbit_bytes_t id_bytes,
    moonbit_bytes_t label_bytes,
    int32_t enabled,
    int32_t checked,
    int32_t checkbox) {
  HMENU menu = moonbit_tray_win_current_pending_menu(state);
  const char *id = (const char *)id_bytes;
  const char *label = (const char *)label_bytes;
  wchar_t *wide_label;
  uint32_t index;
  UINT flags = MF_STRING;
  UINT_PTR command_id;
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->pending_menu_item_count >= MOONBIT_TRAY_MAX_MENU_ITEMS) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu has too many clickable items");
    return 0;
  }
  if (id == NULL || id[0] == '\0' || label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu clickable items require id and label");
    return 0;
  }
  if (strlen(id) >= sizeof(state->pending_menu_item_ids[0])) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu item id is too long");
    return 0;
  }
  wide_label = moonbit_tray_utf8_cstr_to_wide(label);
  if (wide_label == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to convert tray menu label");
    return 0;
  }
  index = state->pending_menu_item_count;
  if (!enabled) {
    flags |= MF_GRAYED;
  }
  if (checkbox && checked) {
    flags |= MF_CHECKED;
  }
  command_id = (UINT_PTR)(MOONBIT_TRAY_COMMAND_BASE + index);
  if (!AppendMenuW(menu, flags, command_id, wide_label)) {
    free(wide_label);
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to append tray menu item");
    return 0;
  }
  free(wide_label);
  snprintf(
      state->pending_menu_item_ids[index],
      sizeof(state->pending_menu_item_ids[index]),
      "%s",
      id);
  state->pending_menu_item_count++;
  return 1;
}

static int32_t moonbit_tray_win_begin_menu(moonbit_tray_state_t *state) {
  if (state == NULL) {
    return 0;
  }
  moonbit_tray_win_destroy_pending_menu(state);
  state->pending_menu = CreatePopupMenu();
  if (state->pending_menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create tray popup menu");
    return 0;
  }
  state->menu_stack[0] = state->pending_menu;
  state->menu_depth = 1;
  state->pending_menu_item_count = 0;
  memset(state->pending_menu_item_ids, 0, sizeof(state->pending_menu_item_ids));
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static int32_t moonbit_tray_win_add_separator(moonbit_tray_state_t *state) {
  HMENU menu = moonbit_tray_win_current_pending_menu(state);
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (!AppendMenuW(menu, MF_SEPARATOR, 0, NULL)) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to append tray menu separator");
    return 0;
  }
  return 1;
}

static int32_t moonbit_tray_win_begin_submenu(
    moonbit_tray_state_t *state,
    moonbit_bytes_t label_bytes,
    int32_t enabled) {
  HMENU parent = moonbit_tray_win_current_pending_menu(state);
  HMENU submenu;
  const char *label = (const char *)label_bytes;
  wchar_t *wide_label;
  UINT flags = MF_POPUP;
  if (parent == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->menu_depth > MOONBIT_TRAY_MAX_MENU_DEPTH) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu submenu depth exceeds 8");
    return 0;
  }
  if (label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu label must not be empty");
    return 0;
  }
  wide_label = moonbit_tray_utf8_cstr_to_wide(label);
  if (wide_label == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to convert tray submenu label");
    return 0;
  }
  submenu = CreatePopupMenu();
  if (submenu == NULL) {
    free(wide_label);
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create tray submenu");
    return 0;
  }
  if (!enabled) {
    flags |= MF_GRAYED;
  }
  if (!AppendMenuW(parent, flags, (UINT_PTR)submenu, wide_label)) {
    DestroyMenu(submenu);
    free(wide_label);
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to append tray submenu");
    return 0;
  }
  free(wide_label);
  state->menu_stack[state->menu_depth] = submenu;
  state->menu_depth++;
  return 1;
}

static int32_t moonbit_tray_win_end_submenu(moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL || state->menu_depth <= 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is not active");
    return 0;
  }
  state->menu_depth--;
  state->menu_stack[state->menu_depth] = NULL;
  return 1;
}

static int32_t moonbit_tray_win_commit_menu(moonbit_tray_state_t *state) {
  HMENU old_menu;
  if (state == NULL || state->pending_menu == NULL) {
    return 0;
  }
  if (state->menu_depth != 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is still open");
    return 0;
  }
  old_menu = state->menu;
  state->menu = state->pending_menu;
  state->pending_menu = NULL;
  state->menu_item_count = state->pending_menu_item_count;
  memcpy(
      state->menu_item_ids,
      state->pending_menu_item_ids,
      sizeof(state->menu_item_ids));
  state->pending_menu_item_count = 0;
  memset(state->pending_menu_item_ids, 0, sizeof(state->pending_menu_item_ids));
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
  state->menu_depth = 0;
  if (old_menu != NULL) {
    DestroyMenu(old_menu);
  }
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}
#endif

#if defined(__linux__)
typedef void (*moonbit_tray_linux_gcallback_t)(void);
typedef void (*moonbit_tray_linux_destroy_notify_t)(void *, void *);

typedef struct moonbit_tray_linux_backend {
  int32_t initialized;
  void *gtk_lib;
  void *indicator_lib;
  int (*gtk_init_check)(int *, char ***);
  void *(*gtk_menu_new)(void);
  void *(*gtk_menu_item_new_with_label)(const char *);
  void *(*gtk_check_menu_item_new_with_label)(const char *);
  void *(*gtk_separator_menu_item_new)(void);
  void (*gtk_menu_shell_append)(void *, void *);
  int (*gtk_main_iteration_do)(int);
  void (*gtk_widget_set_sensitive)(void *, int);
  void (*gtk_widget_show_all)(void *);
  void (*gtk_check_menu_item_set_active)(void *, int);
  void (*gtk_menu_item_set_submenu)(void *, void *);
  void (*gtk_widget_destroy)(void *);
  void (*g_object_unref)(void *);
  unsigned long (*g_signal_connect_data)(
      void *,
      const char *,
      moonbit_tray_linux_gcallback_t,
      void *,
      moonbit_tray_linux_destroy_notify_t,
      int);
  void *(*app_indicator_new)(const char *, const char *, int);
  void (*app_indicator_set_status)(void *, int);
  void (*app_indicator_set_menu)(void *, void *);
  void (*app_indicator_set_icon)(void *, const char *);
  void (*app_indicator_set_icon_full)(void *, const char *, const char *);
  void (*app_indicator_set_icon_theme_path)(void *, const char *);
  void (*app_indicator_set_title)(void *, const char *);
} moonbit_tray_linux_backend_t;

enum {
  MOONBIT_TRAY_APPINDICATOR_CATEGORY_APPLICATION_STATUS = 0,
  MOONBIT_TRAY_APPINDICATOR_STATUS_PASSIVE = 0,
  MOONBIT_TRAY_APPINDICATOR_STATUS_ACTIVE = 1,
};

static moonbit_tray_linux_backend_t moonbit_tray_linux_backend;

typedef struct moonbit_tray_linux_menu_event {
  moonbit_tray_state_t *state;
  char item_id[MOONBIT_TRAY_MAX_MENU_ID_BYTES];
} moonbit_tray_linux_menu_event_t;

static void moonbit_tray_linux_menu_item_activate(
    void *widget,
    void *user_data) {
  moonbit_tray_linux_menu_event_t *event_data =
      (moonbit_tray_linux_menu_event_t *)user_data;
  (void)widget;
  if (event_data != NULL) {
    moonbit_tray_enqueue_menu_event(
        event_data->state,
        event_data->item_id);
  }
}

static void moonbit_tray_linux_free_signal_data(
    void *data,
    void *closure) {
  (void)closure;
  free(data);
}

static int32_t moonbit_tray_linux_open_library(
    const char *const *names,
    void **out_handle) {
  const char *const *name = names;
  if (*out_handle != NULL) {
    return 1;
  }
  for (; *name != NULL; ++name) {
    *out_handle = dlopen(*name, RTLD_LAZY | RTLD_GLOBAL);
    if (*out_handle != NULL) {
      return 1;
    }
  }
  return 0;
}

static int32_t moonbit_tray_linux_load_symbol(
    void **out_symbol,
    void *library,
    const char *name,
    int32_t required) {
  *out_symbol = dlsym(library, name);
  if (*out_symbol == NULL && required) {
    char message[256];
    snprintf(message, sizeof(message), "failed to resolve %s", name);
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        message);
    return 0;
  }
  return 1;
}

static int32_t moonbit_tray_linux_backend_init(void) {
  static const char *const gtk_names[] = {
      "libgtk-3.so.0",
      "libgtk-3.so",
      NULL,
  };
  static const char *const indicator_names[] = {
      "libayatana-appindicator3.so.1",
      "libayatana-appindicator3.so",
      "libappindicator3.so.1",
      "libappindicator3.so",
      NULL,
  };
  if (moonbit_tray_linux_backend.initialized > 0) {
    return 1;
  }
  if (moonbit_tray_linux_backend.initialized < 0) {
    return 0;
  }
  if (!moonbit_tray_linux_open_library(
          gtk_names,
          &moonbit_tray_linux_backend.gtk_lib)) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "GTK 3 runtime not found (expected libgtk-3)");
    moonbit_tray_linux_backend.initialized = 0;
    return 0;
  }
  if (!moonbit_tray_linux_open_library(
          indicator_names,
          &moonbit_tray_linux_backend.indicator_lib)) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "AppIndicator runtime not found (expected libayatana-appindicator3 or libappindicator3)");
    moonbit_tray_linux_backend.initialized = 0;
    return 0;
  }
  if (!moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_init_check,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_init_check",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_menu_new,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_menu_new",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_menu_item_new_with_label,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_menu_item_new_with_label",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_check_menu_item_new_with_label,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_check_menu_item_new_with_label",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_separator_menu_item_new,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_separator_menu_item_new",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_menu_shell_append,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_menu_shell_append",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_main_iteration_do,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_main_iteration_do",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_widget_set_sensitive,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_widget_set_sensitive",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_widget_show_all,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_widget_show_all",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_check_menu_item_set_active,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_check_menu_item_set_active",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_menu_item_set_submenu,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_menu_item_set_submenu",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.gtk_widget_destroy,
          moonbit_tray_linux_backend.gtk_lib,
          "gtk_widget_destroy",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.app_indicator_new,
          moonbit_tray_linux_backend.indicator_lib,
          "app_indicator_new",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.app_indicator_set_status,
          moonbit_tray_linux_backend.indicator_lib,
          "app_indicator_set_status",
          1) ||
      !moonbit_tray_linux_load_symbol(
          (void **)&moonbit_tray_linux_backend.app_indicator_set_menu,
          moonbit_tray_linux_backend.indicator_lib,
          "app_indicator_set_menu",
          1)) {
    moonbit_tray_linux_backend.initialized = 0;
    return 0;
  }
  moonbit_tray_linux_load_symbol(
      (void **)&moonbit_tray_linux_backend.app_indicator_set_icon_full,
      moonbit_tray_linux_backend.indicator_lib,
      "app_indicator_set_icon_full",
      0);
  moonbit_tray_linux_load_symbol(
      (void **)&moonbit_tray_linux_backend.app_indicator_set_icon,
      moonbit_tray_linux_backend.indicator_lib,
      "app_indicator_set_icon",
      0);
  moonbit_tray_linux_load_symbol(
      (void **)&moonbit_tray_linux_backend.app_indicator_set_icon_theme_path,
      moonbit_tray_linux_backend.indicator_lib,
      "app_indicator_set_icon_theme_path",
      0);
  moonbit_tray_linux_load_symbol(
      (void **)&moonbit_tray_linux_backend.app_indicator_set_title,
      moonbit_tray_linux_backend.indicator_lib,
      "app_indicator_set_title",
      0);
  moonbit_tray_linux_backend.g_object_unref =
      (void (*)(void *))dlsym(RTLD_DEFAULT, "g_object_unref");
  moonbit_tray_linux_backend.g_signal_connect_data =
      (unsigned long (*)(
          void *,
          const char *,
          moonbit_tray_linux_gcallback_t,
          void *,
          moonbit_tray_linux_destroy_notify_t,
          int))dlsym(RTLD_DEFAULT, "g_signal_connect_data");
  if (moonbit_tray_linux_backend.g_signal_connect_data == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "failed to resolve g_signal_connect_data");
    moonbit_tray_linux_backend.initialized = -1;
    return 0;
  }
  if (!moonbit_tray_linux_backend.gtk_init_check(NULL, NULL)) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "GTK initialization failed; make sure a desktop session is available");
    moonbit_tray_linux_backend.initialized = 0;
    return 0;
  }
  moonbit_tray_clear_message(
      moonbit_tray_support_message,
      sizeof(moonbit_tray_support_message));
  moonbit_tray_linux_backend.initialized = 1;
  return 1;
}

static int32_t moonbit_tray_linux_has_path_separator(const char *icon) {
  return icon != NULL && strchr(icon, '/') != NULL;
}

static int32_t moonbit_tray_linux_is_readable_file(const char *path) {
  struct stat file_info;
  if (path == NULL || path[0] == '\0') {
    return 0;
  }
  if (stat(path, &file_info) != 0 || !S_ISREG(file_info.st_mode)) {
    return 0;
  }
  return access(path, R_OK) == 0;
}

static int32_t moonbit_tray_linux_ascii_equals_ignore_case(
    const char *left,
    const char *right) {
  char left_char;
  char right_char;
  if (left == NULL || right == NULL) {
    return 0;
  }
  while (*left != '\0' && *right != '\0') {
    left_char = *left;
    right_char = *right;
    if (left_char >= 'A' && left_char <= 'Z') {
      left_char = (char)(left_char - 'A' + 'a');
    }
    if (right_char >= 'A' && right_char <= 'Z') {
      right_char = (char)(right_char - 'A' + 'a');
    }
    if (left_char != right_char) {
      return 0;
    }
    ++left;
    ++right;
  }
  return *left == '\0' && *right == '\0';
}

static int32_t moonbit_tray_linux_has_icon_file_extension(const char *icon) {
  static const char *const extensions[] = {
      "bmp",
      "gif",
      "ico",
      "jpeg",
      "jpg",
      "png",
      "svg",
      "tif",
      "tiff",
      "webp",
      "xpm",
      NULL,
  };
  const char *slash;
  const char *base;
  const char *dot;
  const char *const *extension;
  if (icon == NULL || icon[0] == '\0') {
    return 0;
  }
  slash = strrchr(icon, '/');
  base = slash == NULL ? icon : slash + 1;
  dot = strrchr(base, '.');
  if (dot == NULL || dot == base || dot[1] == '\0') {
    return 0;
  }
  for (extension = extensions; *extension != NULL; ++extension) {
    if (moonbit_tray_linux_ascii_equals_ignore_case(dot + 1, *extension)) {
      return 1;
    }
  }
  return 0;
}

static int32_t moonbit_tray_linux_looks_like_path(
    const char *icon,
    int32_t is_readable_file) {
  return icon != NULL &&
         icon[0] != '\0' &&
         (moonbit_tray_linux_has_path_separator(icon) ||
          is_readable_file ||
          moonbit_tray_linux_has_icon_file_extension(icon));
}

static char *moonbit_tray_linux_copy_range(const char *start, size_t length) {
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return NULL;
  }
  if (length > 0) {
    memcpy(copy, start, length);
  }
  copy[length] = '\0';
  return copy;
}

static int32_t moonbit_tray_linux_split_icon_path(
    const char *path,
    char **out_directory,
    char **out_icon_name) {
  const char *slash;
  const char *base;
  const char *dot;
  size_t directory_length;
  size_t icon_name_length;
  *out_directory = NULL;
  *out_icon_name = NULL;
  if (path == NULL || path[0] == '\0') {
    return 0;
  }
  slash = strrchr(path, '/');
  base = slash == NULL ? path : slash + 1;
  if (base[0] == '\0') {
    return 0;
  }
  if (slash == NULL) {
    *out_directory = moonbit_tray_linux_copy_range(".", 1);
  } else {
    directory_length = slash == path ? 1 : (size_t)(slash - path);
    *out_directory = moonbit_tray_linux_copy_range(path, directory_length);
  }
  if (*out_directory == NULL) {
    return 0;
  }
  dot = strrchr(base, '.');
  icon_name_length =
      dot != NULL && dot > base ? (size_t)(dot - base) : strlen(base);
  *out_icon_name = moonbit_tray_linux_copy_range(base, icon_name_length);
  if (*out_icon_name == NULL) {
    free(*out_directory);
    *out_directory = NULL;
    return 0;
  }
  return 1;
}

static int32_t moonbit_tray_linux_apply_icon(
    moonbit_tray_state_t *state,
    moonbit_bytes_t icon) {
  const char *raw_icon = (const char *)icon;
  const char *icon_name = moonbit_tray_text_or(raw_icon, "applications-system");
  char *icon_directory = NULL;
  char *theme_icon_name = NULL;
  int32_t icon_is_readable_file = moonbit_tray_linux_is_readable_file(raw_icon);
  int32_t icon_is_path =
      moonbit_tray_linux_looks_like_path(raw_icon, icon_is_readable_file);
  int32_t updated = 0;
  if (icon_is_path && !icon_is_readable_file) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray icon file is not readable");
    return 0;
  }
  if (icon_is_path) {
    if (moonbit_tray_linux_backend.app_indicator_set_icon_theme_path == NULL) {
      moonbit_tray_set_message(
          state->last_error,
          sizeof(state->last_error),
          "AppIndicator icon theme path setter is unavailable");
      return 0;
    }
    if (!moonbit_tray_linux_split_icon_path(
            raw_icon,
            &icon_directory,
            &theme_icon_name)) {
      moonbit_tray_set_message(
          state->last_error,
          sizeof(state->last_error),
          "failed to prepare the tray icon path");
      return 0;
    }
    moonbit_tray_linux_backend.app_indicator_set_icon_theme_path(
        state->indicator,
        icon_directory);
    icon_name = theme_icon_name;
  }
  if (moonbit_tray_linux_backend.app_indicator_set_icon_full != NULL) {
    moonbit_tray_linux_backend.app_indicator_set_icon_full(
        state->indicator,
        icon_name,
        "");
    updated = 1;
  } else if (moonbit_tray_linux_backend.app_indicator_set_icon != NULL) {
    moonbit_tray_linux_backend.app_indicator_set_icon(
        state->indicator,
        icon_name);
    updated = 1;
  } else {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "no AppIndicator icon setter is available");
  }
  free(icon_directory);
  free(theme_icon_name);
  if (!updated) {
    return 0;
  }
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static void moonbit_tray_linux_apply_tooltip(
    moonbit_tray_state_t *state,
    moonbit_bytes_t tooltip) {
  if (moonbit_tray_linux_backend.app_indicator_set_title != NULL) {
    moonbit_tray_linux_backend.app_indicator_set_title(
        state->indicator,
        moonbit_tray_text_or((const char *)tooltip, ""));
  }
}

static void moonbit_tray_linux_destroy_menu_widget(void **menu) {
  if (menu == NULL || *menu == NULL) {
    return;
  }
  if (moonbit_tray_linux_backend.gtk_widget_destroy != NULL) {
    moonbit_tray_linux_backend.gtk_widget_destroy(*menu);
  } else if (moonbit_tray_linux_backend.g_object_unref != NULL) {
    moonbit_tray_linux_backend.g_object_unref(*menu);
  }
  *menu = NULL;
}

static void moonbit_tray_linux_destroy_pending_menu(
    moonbit_tray_state_t *state) {
  if (state == NULL) {
    return;
  }
  moonbit_tray_linux_destroy_menu_widget(&state->pending_menu);
  state->menu_depth = 0;
  state->pending_menu_item_count = 0;
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
}

static void *moonbit_tray_linux_current_pending_menu(
    moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL ||
      state->menu_depth == 0) {
    return NULL;
  }
  return state->menu_stack[state->menu_depth - 1];
}

static int32_t moonbit_tray_linux_begin_menu(moonbit_tray_state_t *state) {
  if (state == NULL) {
    return 0;
  }
  moonbit_tray_linux_destroy_pending_menu(state);
  state->pending_menu = moonbit_tray_linux_backend.gtk_menu_new();
  if (state->pending_menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create GTK tray popup menu");
    return 0;
  }
  state->menu_stack[0] = state->pending_menu;
  state->menu_depth = 1;
  state->pending_menu_item_count = 0;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static int32_t moonbit_tray_linux_append_clickable_menu_item(
    moonbit_tray_state_t *state,
    moonbit_bytes_t id_bytes,
    moonbit_bytes_t label_bytes,
    int32_t enabled,
    int32_t checked,
    int32_t checkbox) {
  void *menu = moonbit_tray_linux_current_pending_menu(state);
  const char *id = (const char *)id_bytes;
  const char *label = (const char *)label_bytes;
  void *item;
  moonbit_tray_linux_menu_event_t *event_data;
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->pending_menu_item_count >= MOONBIT_TRAY_MAX_MENU_ITEMS) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu has too many clickable items");
    return 0;
  }
  if (id == NULL || id[0] == '\0' || label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu clickable items require id and label");
    return 0;
  }
  if (strlen(id) >= MOONBIT_TRAY_MAX_MENU_ID_BYTES) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu item id is too long");
    return 0;
  }
  item = checkbox
      ? moonbit_tray_linux_backend.gtk_check_menu_item_new_with_label(label)
      : moonbit_tray_linux_backend.gtk_menu_item_new_with_label(label);
  if (item == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create GTK tray menu item");
    return 0;
  }
  event_data = (moonbit_tray_linux_menu_event_t *)calloc(
      1,
      sizeof(moonbit_tray_linux_menu_event_t));
  if (event_data == NULL) {
    moonbit_tray_linux_backend.gtk_widget_destroy(item);
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to allocate GTK tray menu event data");
    return 0;
  }
  event_data->state = state;
  snprintf(event_data->item_id, sizeof(event_data->item_id), "%s", id);
  if (checked) {
    moonbit_tray_linux_backend.gtk_check_menu_item_set_active(item, 1);
  }
  if (!enabled) {
    moonbit_tray_linux_backend.gtk_widget_set_sensitive(item, 0);
  }
  moonbit_tray_linux_backend.g_signal_connect_data(
      item,
      "activate",
      (moonbit_tray_linux_gcallback_t)moonbit_tray_linux_menu_item_activate,
      event_data,
      moonbit_tray_linux_free_signal_data,
      0);
  moonbit_tray_linux_backend.gtk_menu_shell_append(menu, item);
  state->pending_menu_item_count++;
  return 1;
}

static int32_t moonbit_tray_linux_add_separator(
    moonbit_tray_state_t *state) {
  void *menu = moonbit_tray_linux_current_pending_menu(state);
  void *item;
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  item = moonbit_tray_linux_backend.gtk_separator_menu_item_new();
  if (item == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create GTK tray menu separator");
    return 0;
  }
  moonbit_tray_linux_backend.gtk_menu_shell_append(menu, item);
  return 1;
}

static int32_t moonbit_tray_linux_begin_submenu(
    moonbit_tray_state_t *state,
    moonbit_bytes_t label_bytes,
    int32_t enabled) {
  void *parent = moonbit_tray_linux_current_pending_menu(state);
  const char *label = (const char *)label_bytes;
  void *item;
  void *submenu;
  if (parent == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->menu_depth > MOONBIT_TRAY_MAX_MENU_DEPTH) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu submenu depth exceeds 8");
    return 0;
  }
  if (label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu label must not be empty");
    return 0;
  }
  item = moonbit_tray_linux_backend.gtk_menu_item_new_with_label(label);
  submenu = moonbit_tray_linux_backend.gtk_menu_new();
  if (item == NULL || submenu == NULL) {
    if (item != NULL) {
      moonbit_tray_linux_backend.gtk_widget_destroy(item);
    }
    if (submenu != NULL) {
      moonbit_tray_linux_backend.gtk_widget_destroy(submenu);
    }
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create GTK tray submenu");
    return 0;
  }
  if (!enabled) {
    moonbit_tray_linux_backend.gtk_widget_set_sensitive(item, 0);
  }
  moonbit_tray_linux_backend.gtk_menu_item_set_submenu(item, submenu);
  moonbit_tray_linux_backend.gtk_menu_shell_append(parent, item);
  state->menu_stack[state->menu_depth] = submenu;
  state->menu_depth++;
  return 1;
}

static int32_t moonbit_tray_linux_end_submenu(
    moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL || state->menu_depth <= 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is not active");
    return 0;
  }
  state->menu_depth--;
  state->menu_stack[state->menu_depth] = NULL;
  return 1;
}

static int32_t moonbit_tray_linux_commit_menu(moonbit_tray_state_t *state) {
  void *old_menu;
  if (state == NULL || state->pending_menu == NULL) {
    return 0;
  }
  if (state->menu_depth != 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is still open");
    return 0;
  }
  old_menu = state->menu;
  state->menu = state->pending_menu;
  state->pending_menu = NULL;
  state->pending_menu_item_count = 0;
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
  state->menu_depth = 0;
  moonbit_tray_linux_backend.gtk_widget_show_all(state->menu);
  moonbit_tray_linux_backend.app_indicator_set_menu(
      state->indicator,
      state->menu);
  if (old_menu != NULL) {
    moonbit_tray_linux_destroy_menu_widget(&old_menu);
  }
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}
#endif

#if defined(__APPLE__)
typedef void *moonbit_tray_id;
typedef void *moonbit_tray_sel;
typedef signed char moonbit_tray_bool;

typedef struct moonbit_tray_macos_backend {
  int32_t initialized;
  void *objc_lib;
  void *appkit_lib;
  moonbit_tray_id (*objc_getClass)(const char *);
  moonbit_tray_id (*objc_lookUpClass)(const char *);
  moonbit_tray_id (*objc_allocateClassPair)(moonbit_tray_id, const char *, size_t);
  void (*objc_registerClassPair)(moonbit_tray_id);
  moonbit_tray_sel (*sel_registerName)(const char *);
  int (*class_addIvar)(moonbit_tray_id, const char *, size_t, uint8_t, const char *);
  int (*class_addMethod)(moonbit_tray_id, moonbit_tray_sel, void *, const char *);
  void *(*object_getInstanceVariable)(moonbit_tray_id, const char *, void **);
  void *(*object_setInstanceVariable)(moonbit_tray_id, const char *, void *);
  void *objc_msgSend;
  moonbit_tray_id menu_target_class;
} moonbit_tray_macos_backend_t;

static moonbit_tray_macos_backend_t moonbit_tray_macos_backend;

static void moonbit_tray_macos_menu_action(
    moonbit_tray_id target,
    moonbit_tray_sel selector,
    moonbit_tray_id sender);

static int32_t moonbit_tray_macos_ensure_menu_target_class(void) {
  moonbit_tray_id existing;
  moonbit_tray_id superclass;
  moonbit_tray_id target_class;
  uint8_t pointer_alignment = sizeof(void *) == 8 ? 3 : 2;
  if (moonbit_tray_macos_backend.menu_target_class != NULL) {
    return 1;
  }
  existing = moonbit_tray_macos_backend.objc_lookUpClass(
      "MoonBitTrayMenuTarget");
  if (existing != NULL) {
    moonbit_tray_macos_backend.menu_target_class = existing;
    return 1;
  }
  superclass = moonbit_tray_macos_backend.objc_getClass("NSObject");
  if (superclass == NULL) {
    return 0;
  }
  target_class = moonbit_tray_macos_backend.objc_allocateClassPair(
      superclass,
      "MoonBitTrayMenuTarget",
      0);
  if (target_class == NULL) {
    return 0;
  }
  if (!moonbit_tray_macos_backend.class_addIvar(
          target_class,
          "state",
          sizeof(void *),
          pointer_alignment,
          "^v") ||
      !moonbit_tray_macos_backend.class_addMethod(
          target_class,
          moonbit_tray_macos_backend.sel_registerName("moonbitTrayMenuAction:"),
          (void *)moonbit_tray_macos_menu_action,
          "v@:@")) {
    return 0;
  }
  moonbit_tray_macos_backend.objc_registerClassPair(target_class);
  moonbit_tray_macos_backend.menu_target_class = target_class;
  return 1;
}

static int32_t moonbit_tray_macos_backend_init(void) {
  if (moonbit_tray_macos_backend.initialized > 0) {
    return 1;
  }
  if (moonbit_tray_macos_backend.initialized < 0) {
    return 0;
  }
  moonbit_tray_macos_backend.objc_lib =
      dlopen("/usr/lib/libobjc.A.dylib", RTLD_LAZY | RTLD_GLOBAL);
  if (moonbit_tray_macos_backend.objc_lib == NULL) {
    moonbit_tray_macos_backend.objc_lib =
        dlopen("/usr/lib/libobjc.dylib", RTLD_LAZY | RTLD_GLOBAL);
  }
  moonbit_tray_macos_backend.appkit_lib =
      dlopen(
          "/System/Library/Frameworks/AppKit.framework/AppKit",
          RTLD_LAZY | RTLD_GLOBAL);
  if (moonbit_tray_macos_backend.objc_lib == NULL ||
      moonbit_tray_macos_backend.appkit_lib == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "AppKit or Objective-C runtime could not be loaded");
    moonbit_tray_macos_backend.initialized = -1;
    return 0;
  }
  moonbit_tray_macos_backend.objc_getClass =
      (moonbit_tray_id(*)(const char *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "objc_getClass");
  moonbit_tray_macos_backend.objc_lookUpClass =
      (moonbit_tray_id(*)(const char *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "objc_lookUpClass");
  moonbit_tray_macos_backend.objc_allocateClassPair =
      (moonbit_tray_id(*)(moonbit_tray_id, const char *, size_t))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "objc_allocateClassPair");
  moonbit_tray_macos_backend.objc_registerClassPair =
      (void (*)(moonbit_tray_id))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "objc_registerClassPair");
  moonbit_tray_macos_backend.sel_registerName =
      (moonbit_tray_sel(*)(const char *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "sel_registerName");
  moonbit_tray_macos_backend.class_addIvar =
      (int (*)(moonbit_tray_id, const char *, size_t, uint8_t, const char *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "class_addIvar");
  moonbit_tray_macos_backend.class_addMethod =
      (int (*)(moonbit_tray_id, moonbit_tray_sel, void *, const char *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "class_addMethod");
  moonbit_tray_macos_backend.object_getInstanceVariable =
      (void *(*)(moonbit_tray_id, const char *, void **))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "object_getInstanceVariable");
  moonbit_tray_macos_backend.object_setInstanceVariable =
      (void *(*)(moonbit_tray_id, const char *, void *))dlsym(
          moonbit_tray_macos_backend.objc_lib,
          "object_setInstanceVariable");
  moonbit_tray_macos_backend.objc_msgSend =
      dlsym(moonbit_tray_macos_backend.objc_lib, "objc_msgSend");
  if (moonbit_tray_macos_backend.objc_getClass == NULL ||
      moonbit_tray_macos_backend.objc_lookUpClass == NULL ||
      moonbit_tray_macos_backend.objc_allocateClassPair == NULL ||
      moonbit_tray_macos_backend.objc_registerClassPair == NULL ||
      moonbit_tray_macos_backend.sel_registerName == NULL ||
      moonbit_tray_macos_backend.class_addIvar == NULL ||
      moonbit_tray_macos_backend.class_addMethod == NULL ||
      moonbit_tray_macos_backend.object_getInstanceVariable == NULL ||
      moonbit_tray_macos_backend.object_setInstanceVariable == NULL ||
      moonbit_tray_macos_backend.objc_msgSend == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "failed to resolve Objective-C runtime entry points");
    moonbit_tray_macos_backend.initialized = -1;
    return 0;
  }
  if (!moonbit_tray_macos_ensure_menu_target_class()) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "failed to register macOS tray menu target");
    moonbit_tray_macos_backend.initialized = -1;
    return 0;
  }
  moonbit_tray_clear_message(
      moonbit_tray_support_message,
      sizeof(moonbit_tray_support_message));
  moonbit_tray_macos_backend.initialized = 1;
  return 1;
}

static moonbit_tray_sel moonbit_tray_macos_sel(const char *name) {
  return moonbit_tray_macos_backend.sel_registerName(name);
}

static moonbit_tray_id moonbit_tray_macos_class(const char *name) {
  return moonbit_tray_macos_backend.objc_getClass(name);
}

static moonbit_tray_id moonbit_tray_macos_send_id(
    moonbit_tray_id object,
    const char *selector_name) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name));
}

static moonbit_tray_id moonbit_tray_macos_send_id_id(
    moonbit_tray_id object,
    const char *selector_name,
    moonbit_tray_id arg) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel, moonbit_tray_id))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static moonbit_tray_id moonbit_tray_macos_send_id_id_sel_id(
    moonbit_tray_id object,
    const char *selector_name,
    moonbit_tray_id arg1,
    moonbit_tray_sel arg2,
    moonbit_tray_id arg3) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel, moonbit_tray_id, moonbit_tray_sel, moonbit_tray_id))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg1,
      arg2,
      arg3);
}

static moonbit_tray_id moonbit_tray_macos_send_id_cstring(
    moonbit_tray_id object,
    const char *selector_name,
    const char *arg) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel, const char *))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static moonbit_tray_id moonbit_tray_macos_send_id_double(
    moonbit_tray_id object,
    const char *selector_name,
    double arg) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel, double))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static moonbit_tray_id moonbit_tray_macos_send_id_ulong_id_id_bool(
    moonbit_tray_id object,
    const char *selector_name,
    unsigned long arg1,
    moonbit_tray_id arg2,
    moonbit_tray_id arg3,
    moonbit_tray_bool arg4) {
  return ((moonbit_tray_id(*)(moonbit_tray_id, moonbit_tray_sel, unsigned long, moonbit_tray_id, moonbit_tray_id, moonbit_tray_bool))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg1,
      arg2,
      arg3,
      arg4);
}

static void moonbit_tray_macos_send_void(
    moonbit_tray_id object,
    const char *selector_name) {
  ((void (*)(moonbit_tray_id, moonbit_tray_sel))
       moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name));
}

static const char *moonbit_tray_macos_send_cstring(
    moonbit_tray_id object,
    const char *selector_name) {
  return ((const char *(*)(moonbit_tray_id, moonbit_tray_sel))
              moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name));
}

static void moonbit_tray_macos_send_void_id(
    moonbit_tray_id object,
    const char *selector_name,
    moonbit_tray_id arg) {
  ((void (*)(moonbit_tray_id, moonbit_tray_sel, moonbit_tray_id))
       moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static void moonbit_tray_macos_send_void_long(
    moonbit_tray_id object,
    const char *selector_name,
    long arg) {
  ((void (*)(moonbit_tray_id, moonbit_tray_sel, long))
       moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static void moonbit_tray_macos_send_void_bool(
    moonbit_tray_id object,
    const char *selector_name,
    moonbit_tray_bool arg) {
  ((void (*)(moonbit_tray_id, moonbit_tray_sel, moonbit_tray_bool))
       moonbit_tray_macos_backend.objc_msgSend)(
      object,
      moonbit_tray_macos_sel(selector_name),
      arg);
}

static moonbit_tray_id moonbit_tray_macos_new_pool(void) {
  return moonbit_tray_macos_send_id(
      moonbit_tray_macos_class("NSAutoreleasePool"),
      "new");
}

static void moonbit_tray_macos_drain_pool(moonbit_tray_id pool) {
  if (pool != NULL) {
    moonbit_tray_macos_send_void(pool, "drain");
  }
}

/*
 * All tray states share one autorelease pool, tracked by user count: the
 * first create pushes it and the last destroy drains it. Per-tray pools
 * imposed stack-discipline (LIFO) destroy ordering — destroying two live
 * trays out of order aborted the process. state->pool doubles as the token
 * recording that this state holds one user count. Create and destroy must
 * run outside any foreign autorelease-pool scope: a host pool pushed after
 * ours must also be drained before our last destroy.
 */
static int g_tray_macos_pool_users = 0;
static moonbit_tray_id g_tray_macos_shared_pool = NULL;

static moonbit_tray_id moonbit_tray_macos_pool_acquire(void) {
  if (g_tray_macos_shared_pool == NULL) {
    g_tray_macos_shared_pool = moonbit_tray_macos_new_pool();
  }
  if (g_tray_macos_shared_pool == NULL) {
    return NULL; /* no user counted */
  }
  g_tray_macos_pool_users++;
  return g_tray_macos_shared_pool;
}

static void moonbit_tray_macos_pool_release(void) {
  if (g_tray_macos_pool_users > 0) {
    g_tray_macos_pool_users--;
    if (g_tray_macos_pool_users == 0) {
      moonbit_tray_macos_drain_pool(g_tray_macos_shared_pool);
      g_tray_macos_shared_pool = NULL;
    }
  }
}

static moonbit_tray_id moonbit_tray_macos_string(const char *value) {
  return moonbit_tray_macos_send_id_cstring(
      moonbit_tray_macos_class("NSString"),
      "stringWithUTF8String:",
      moonbit_tray_text_or(value, ""));
}

static int32_t moonbit_tray_macos_apply_icon(
    moonbit_tray_state_t *state,
    moonbit_bytes_t icon) {
  const char *icon_text = (const char *)icon;
  moonbit_tray_id button =
      state->button != NULL ? state->button : state->status_item;
  moonbit_tray_id pool;
  if (button == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "status item button is unavailable");
    return 0;
  }
  pool = moonbit_tray_macos_new_pool();
  if (icon_text != NULL && icon_text[0] != '\0') {
    moonbit_tray_id path = moonbit_tray_macos_string(icon_text);
    int32_t image_owned = 1;
    moonbit_tray_id image = moonbit_tray_macos_send_id_id(
        moonbit_tray_macos_send_id(
            moonbit_tray_macos_class("NSImage"),
            "alloc"),
        "initWithContentsOfFile:",
        path);
    if (image == NULL) {
      image_owned = 0;
      image = moonbit_tray_macos_send_id_id(
          moonbit_tray_macos_class("NSImage"),
          "imageNamed:",
          path);
    }
    if (image != NULL) {
      moonbit_tray_macos_send_void_id(button, "setImage:", image);
      if (image_owned) {
        moonbit_tray_macos_send_void(image, "release");
      }
      moonbit_tray_macos_send_void_id(
          button,
          "setTitle:",
          moonbit_tray_macos_string(""));
      moonbit_tray_macos_drain_pool(pool);
      moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
      return 1;
    }
  }
  moonbit_tray_macos_send_void_id(button, "setImage:", NULL);
  moonbit_tray_macos_send_void_id(
      button,
      "setTitle:",
      moonbit_tray_macos_string("Tray"));
  moonbit_tray_macos_drain_pool(pool);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static void moonbit_tray_macos_apply_tooltip(
    moonbit_tray_state_t *state,
    moonbit_bytes_t tooltip) {
  moonbit_tray_id button =
      state->button != NULL ? state->button : state->status_item;
  if (button != NULL) {
    moonbit_tray_id pool = moonbit_tray_macos_new_pool();
    moonbit_tray_macos_send_void_id(
        button,
        "setToolTip:",
        moonbit_tray_macos_string((const char *)tooltip));
    moonbit_tray_macos_drain_pool(pool);
  }
}

static void moonbit_tray_macos_menu_action(
    moonbit_tray_id target,
    moonbit_tray_sel selector,
    moonbit_tray_id sender) {
  moonbit_tray_state_t *state = NULL;
  moonbit_tray_id represented = NULL;
  const char *item_id = NULL;
  (void)selector;
  if (target == NULL || sender == NULL) {
    return;
  }
  moonbit_tray_macos_backend.object_getInstanceVariable(
      target,
      "state",
      (void **)&state);
  represented = moonbit_tray_macos_send_id(sender, "representedObject");
  if (represented != NULL) {
    item_id = moonbit_tray_macos_send_cstring(represented, "UTF8String");
  }
  if (state != NULL && item_id != NULL) {
    moonbit_tray_enqueue_menu_event(state, item_id);
  }
}

static moonbit_tray_id moonbit_tray_macos_create_menu_target(
    moonbit_tray_state_t *state) {
  moonbit_tray_id target =
      moonbit_tray_macos_send_id(
          moonbit_tray_macos_backend.menu_target_class,
          "new");
  if (target == NULL) {
    return NULL;
  }
  moonbit_tray_macos_backend.object_setInstanceVariable(
      target,
      "state",
      state);
  return target;
}

static moonbit_tray_id moonbit_tray_macos_new_menu(const char *title) {
  return moonbit_tray_macos_send_id_id(
      moonbit_tray_macos_send_id(
          moonbit_tray_macos_class("NSMenu"),
          "alloc"),
      "initWithTitle:",
      moonbit_tray_macos_string(title));
}

static moonbit_tray_id moonbit_tray_macos_new_menu_item(
    const char *label,
    moonbit_tray_sel action) {
  return moonbit_tray_macos_send_id_id_sel_id(
      moonbit_tray_macos_send_id(
          moonbit_tray_macos_class("NSMenuItem"),
          "alloc"),
      "initWithTitle:action:keyEquivalent:",
      moonbit_tray_macos_string(label),
      action,
      moonbit_tray_macos_string(""));
}

static void moonbit_tray_macos_release_menu(moonbit_tray_id *menu) {
  if (menu == NULL || *menu == NULL) {
    return;
  }
  moonbit_tray_macos_send_void(*menu, "release");
  *menu = NULL;
}

static void moonbit_tray_macos_destroy_pending_menu(
    moonbit_tray_state_t *state) {
  if (state == NULL) {
    return;
  }
  moonbit_tray_macos_release_menu((moonbit_tray_id *)&state->pending_menu);
  state->menu_depth = 0;
  state->pending_menu_item_count = 0;
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
}

static moonbit_tray_id moonbit_tray_macos_current_pending_menu(
    moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL ||
      state->menu_depth == 0) {
    return NULL;
  }
  return (moonbit_tray_id)state->menu_stack[state->menu_depth - 1];
}

static int32_t moonbit_tray_macos_begin_menu(moonbit_tray_state_t *state) {
  if (state == NULL || state->menu_target == NULL) {
    return 0;
  }
  moonbit_tray_macos_destroy_pending_menu(state);
  state->pending_menu = moonbit_tray_macos_new_menu("");
  if (state->pending_menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create macOS tray menu");
    return 0;
  }
  state->menu_stack[0] = state->pending_menu;
  state->menu_depth = 1;
  state->pending_menu_item_count = 0;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static int32_t moonbit_tray_macos_append_clickable_menu_item(
    moonbit_tray_state_t *state,
    moonbit_bytes_t id_bytes,
    moonbit_bytes_t label_bytes,
    int32_t enabled,
    int32_t checked) {
  moonbit_tray_id menu = moonbit_tray_macos_current_pending_menu(state);
  const char *id = (const char *)id_bytes;
  const char *label = (const char *)label_bytes;
  moonbit_tray_id item;
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->pending_menu_item_count >= MOONBIT_TRAY_MAX_MENU_ITEMS) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu has too many clickable items");
    return 0;
  }
  if (id == NULL || id[0] == '\0' || label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu clickable items require id and label");
    return 0;
  }
  if (strlen(id) >= MOONBIT_TRAY_MAX_MENU_ID_BYTES) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu item id is too long");
    return 0;
  }
  item = moonbit_tray_macos_new_menu_item(
      label,
      moonbit_tray_macos_sel("moonbitTrayMenuAction:"));
  if (item == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create macOS tray menu item");
    return 0;
  }
  moonbit_tray_macos_send_void_id(
      item,
      "setRepresentedObject:",
      moonbit_tray_macos_string(id));
  moonbit_tray_macos_send_void_id(item, "setTarget:", state->menu_target);
  moonbit_tray_macos_send_void_bool(
      item,
      "setEnabled:",
      (moonbit_tray_bool)(enabled ? 1 : 0));
  moonbit_tray_macos_send_void_long(item, "setState:", checked ? 1L : 0L);
  moonbit_tray_macos_send_void_id(menu, "addItem:", item);
  moonbit_tray_macos_send_void(item, "release");
  state->pending_menu_item_count++;
  return 1;
}

static int32_t moonbit_tray_macos_add_separator(
    moonbit_tray_state_t *state) {
  moonbit_tray_id menu = moonbit_tray_macos_current_pending_menu(state);
  moonbit_tray_id item;
  if (menu == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  item = moonbit_tray_macos_send_id(
      moonbit_tray_macos_class("NSMenuItem"),
      "separatorItem");
  if (item == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create macOS tray menu separator");
    return 0;
  }
  moonbit_tray_macos_send_void_id(menu, "addItem:", item);
  return 1;
}

static int32_t moonbit_tray_macos_begin_submenu(
    moonbit_tray_state_t *state,
    moonbit_bytes_t label_bytes,
    int32_t enabled) {
  moonbit_tray_id parent = moonbit_tray_macos_current_pending_menu(state);
  const char *label = (const char *)label_bytes;
  moonbit_tray_id item;
  moonbit_tray_id submenu;
  if (parent == NULL) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu transaction is not active");
    return 0;
  }
  if (state->menu_depth > MOONBIT_TRAY_MAX_MENU_DEPTH) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray menu submenu depth exceeds 8");
    return 0;
  }
  if (label == NULL || label[0] == '\0') {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu label must not be empty");
    return 0;
  }
  item = moonbit_tray_macos_new_menu_item(label, NULL);
  submenu = moonbit_tray_macos_new_menu(label);
  if (item == NULL || submenu == NULL) {
    if (item != NULL) {
      moonbit_tray_macos_send_void(item, "release");
    }
    if (submenu != NULL) {
      moonbit_tray_macos_send_void(submenu, "release");
    }
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "failed to create macOS tray submenu");
    return 0;
  }
  moonbit_tray_macos_send_void_bool(
      item,
      "setEnabled:",
      (moonbit_tray_bool)(enabled ? 1 : 0));
  moonbit_tray_macos_send_void_id(item, "setSubmenu:", submenu);
  moonbit_tray_macos_send_void(submenu, "release");
  moonbit_tray_macos_send_void_id(parent, "addItem:", item);
  moonbit_tray_macos_send_void(item, "release");
  state->menu_stack[state->menu_depth] = submenu;
  state->menu_depth++;
  return 1;
}

static int32_t moonbit_tray_macos_end_submenu(
    moonbit_tray_state_t *state) {
  if (state == NULL || state->pending_menu == NULL || state->menu_depth <= 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is not active");
    return 0;
  }
  state->menu_depth--;
  state->menu_stack[state->menu_depth] = NULL;
  return 1;
}

static int32_t moonbit_tray_macos_commit_menu(moonbit_tray_state_t *state) {
  moonbit_tray_id old_menu;
  if (state == NULL || state->pending_menu == NULL) {
    return 0;
  }
  if (state->menu_depth != 1) {
    moonbit_tray_set_message(
        state->last_error,
        sizeof(state->last_error),
        "tray submenu transaction is still open");
    return 0;
  }
  old_menu = (moonbit_tray_id)state->menu;
  state->menu = state->pending_menu;
  state->pending_menu = NULL;
  state->pending_menu_item_count = 0;
  memset(state->menu_stack, 0, sizeof(state->menu_stack));
  state->menu_depth = 0;
  moonbit_tray_macos_send_void_id(
      state->status_item,
      "setMenu:",
      (moonbit_tray_id)state->menu);
  if (old_menu != NULL) {
    moonbit_tray_macos_send_void(old_menu, "release");
  }
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
}

static void moonbit_tray_macos_release_state(moonbit_tray_state_t *state) {
  if (state == NULL) {
    return;
  }
  moonbit_tray_macos_destroy_pending_menu(state);
  if (state->status_item != NULL && state->menu != NULL) {
    moonbit_tray_macos_send_void_id(state->status_item, "setMenu:", NULL);
  }
  moonbit_tray_macos_release_menu((moonbit_tray_id *)&state->menu);
  if (state->menu_target != NULL) {
    moonbit_tray_macos_backend.object_setInstanceVariable(
        (moonbit_tray_id)state->menu_target,
        "state",
        NULL);
    moonbit_tray_macos_send_void(
        (moonbit_tray_id)state->menu_target,
        "release");
    state->menu_target = NULL;
  }
  if (state->status_item != NULL) {
    if (state->status_bar != NULL) {
      moonbit_tray_macos_send_void_id(
          state->status_bar,
          "removeStatusItem:",
          state->status_item);
    }
    moonbit_tray_macos_send_void(state->status_item, "release");
    state->status_item = NULL;
  }
  if (state->pool != NULL) {
    moonbit_tray_macos_pool_release();
    state->pool = NULL;
  }
}
#endif

MOONBIT_FFI_EXPORT int32_t moonbit_tray_current_platform(void) {
#ifdef _WIN32
  return 1;
#elif defined(__linux__)
  return 2;
#elif defined(__APPLE__)
  return 3;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_is_supported(void) {
#ifdef _WIN32
  return moonbit_tray_ensure_window_class();
#elif defined(__linux__)
  return moonbit_tray_linux_backend_init();
#elif defined(__APPLE__)
  if (!moonbit_tray_macos_backend_init()) {
    return 0;
  }
  if (pthread_main_np() == 0) {
    moonbit_tray_set_message(
        moonbit_tray_support_message,
        sizeof(moonbit_tray_support_message),
        "macOS tray must be created on the main thread");
    return 0;
  }
  moonbit_tray_clear_message(
      moonbit_tray_support_message,
      sizeof(moonbit_tray_support_message));
  return 1;
#else
  moonbit_tray_set_message(
      moonbit_tray_support_message,
      sizeof(moonbit_tray_support_message),
      "tray support is not available on this operating system");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_tray_support_error(void) {
  return moonbit_tray_copy_message(moonbit_tray_support_message);
}

static void moonbit_tray_teardown_state(moonbit_tray_state_t *state) {
#ifdef _WIN32
  if (state->visible) {
    Shell_NotifyIconW(NIM_DELETE, &state->icon_data);
  }
  moonbit_tray_win_destroy_pending_menu(state);
  moonbit_tray_win_destroy_menu(state);
  if (state->icon_owned && state->icon_data.hIcon != NULL) {
    DestroyIcon(state->icon_data.hIcon);
  }
  if (state->hwnd != NULL) {
    DestroyWindow(state->hwnd);
  }
#elif defined(__linux__)
  if (state->indicator != NULL) {
    moonbit_tray_linux_backend.app_indicator_set_status(
        state->indicator,
        MOONBIT_TRAY_APPINDICATOR_STATUS_PASSIVE);
  }
  moonbit_tray_linux_destroy_pending_menu(state);
  moonbit_tray_linux_destroy_menu_widget(&state->menu);
  if (moonbit_tray_linux_backend.g_object_unref != NULL) {
    if (state->indicator != NULL) {
      moonbit_tray_linux_backend.g_object_unref(state->indicator);
    }
  }
#elif defined(__APPLE__)
  moonbit_tray_macos_release_state(state);
#endif
}

/* Shared by the three create exits: register, or tear down when full. */
static int64_t moonbit_tray_finish_create(moonbit_tray_state_t *state) {
  int64_t handle = moonbit_tray_registry_insert(state);
  if (handle == 0) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "too many live tray states");
    moonbit_tray_teardown_state(state);
    free(state);
    return 0;
  }
  return handle;
}

MOONBIT_FFI_EXPORT int64_t moonbit_tray_create(
    moonbit_bytes_t identifier,
    moonbit_bytes_t icon,
    moonbit_bytes_t tooltip) {
  moonbit_tray_state_t *state;
#ifdef _WIN32
  if (!moonbit_tray_ensure_window_class()) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        moonbit_tray_support_message);
    return 0;
  }
  state = (moonbit_tray_state_t *)calloc(1, sizeof(moonbit_tray_state_t));
  if (state == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to allocate tray state");
    return 0;
  }
  state->hwnd = CreateWindowExW(
      0,
      L"MoonBitTrayWindow",
      L"MoonBitTrayWindow",
      0,
      0,
      0,
      0,
      0,
      HWND_MESSAGE,
      NULL,
      GetModuleHandleW(NULL),
      NULL);
  if (state->hwnd == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create the hidden tray window");
    free(state);
    return 0;
  }
  SetWindowLongPtrW(state->hwnd, GWLP_USERDATA, (LONG_PTR)state);
  memset(&state->icon_data, 0, sizeof(state->icon_data));
  state->icon_data.cbSize = sizeof(state->icon_data);
  state->icon_data.hWnd = state->hwnd;
  state->icon_data.uID = 0x6D42;
  state->icon_data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  state->icon_data.uCallbackMessage = MOONBIT_TRAY_CALLBACK_MESSAGE;
  moonbit_tray_copy_tooltip(&state->icon_data, tooltip);
  if (!moonbit_tray_replace_icon(state, icon)) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        state->last_error);
    DestroyWindow(state->hwnd);
    free(state);
    return 0;
  }
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  moonbit_tray_clear_message(
      moonbit_tray_create_error,
      sizeof(moonbit_tray_create_error));
  return moonbit_tray_finish_create(state);
#elif defined(__linux__)
  if (!moonbit_tray_linux_backend_init()) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        moonbit_tray_support_message);
    return 0;
  }
  state = (moonbit_tray_state_t *)calloc(1, sizeof(moonbit_tray_state_t));
  if (state == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to allocate tray state");
    return 0;
  }
  state->menu = moonbit_tray_linux_backend.gtk_menu_new();
  if (state->menu == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create the GTK tray menu");
    free(state);
    return 0;
  }
  state->indicator = moonbit_tray_linux_backend.app_indicator_new(
      moonbit_tray_text_or((const char *)identifier, "moonbit-tray"),
      moonbit_tray_text_or((const char *)icon, "applications-system"),
      MOONBIT_TRAY_APPINDICATOR_CATEGORY_APPLICATION_STATUS);
  if (state->indicator == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create the AppIndicator instance");
    moonbit_tray_linux_destroy_menu_widget(&state->menu);
    free(state);
    return 0;
  }
  moonbit_tray_linux_backend.app_indicator_set_menu(state->indicator, state->menu);
  moonbit_tray_linux_backend.app_indicator_set_status(
      state->indicator,
      MOONBIT_TRAY_APPINDICATOR_STATUS_PASSIVE);
  if (!moonbit_tray_linux_apply_icon(state, icon)) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        state->last_error);
    if (moonbit_tray_linux_backend.g_object_unref != NULL) {
      moonbit_tray_linux_backend.g_object_unref(state->indicator);
    }
    moonbit_tray_linux_destroy_menu_widget(&state->menu);
    free(state);
    return 0;
  }
  moonbit_tray_linux_apply_tooltip(state, tooltip);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  moonbit_tray_clear_message(
      moonbit_tray_create_error,
      sizeof(moonbit_tray_create_error));
  return moonbit_tray_finish_create(state);
#elif defined(__APPLE__)
  if (!moonbit_tray_macos_backend_init()) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        moonbit_tray_support_message);
    return 0;
  }
  if (pthread_main_np() == 0) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "macOS tray must be created on the main thread");
    return 0;
  }
  state = (moonbit_tray_state_t *)calloc(1, sizeof(moonbit_tray_state_t));
  if (state == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to allocate tray state");
    return 0;
  }
  state->pool = moonbit_tray_macos_pool_acquire();
  if (state->pool == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create tray autorelease pool");
    free(state);
    return 0;
  }
  state->app = moonbit_tray_macos_send_id(
      moonbit_tray_macos_class("NSApplication"),
      "sharedApplication");
  state->status_bar = moonbit_tray_macos_send_id(
      moonbit_tray_macos_class("NSStatusBar"),
      "systemStatusBar");
  state->status_item = moonbit_tray_macos_send_id_double(
      state->status_bar,
      "statusItemWithLength:",
      -1.0);
  if (state->status_item == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create the NSStatusItem");
    moonbit_tray_macos_release_state(state);
    free(state);
    return 0;
  }
  moonbit_tray_macos_send_id(state->status_item, "retain");
  moonbit_tray_macos_send_void_bool(
      state->status_item,
      "setHighlightMode:",
      (moonbit_tray_bool)1);
  state->button = moonbit_tray_macos_send_id(state->status_item, "button");
  state->menu_target = moonbit_tray_macos_create_menu_target(state);
  if (state->menu_target == NULL) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        "failed to create macOS tray menu target");
    moonbit_tray_macos_release_state(state);
    free(state);
    return 0;
  }
  moonbit_tray_macos_send_void_bool(
      state->app,
      "activateIgnoringOtherApps:",
      (moonbit_tray_bool)1);
  if (!moonbit_tray_macos_apply_icon(state, icon)) {
    moonbit_tray_set_message(
        moonbit_tray_create_error,
        sizeof(moonbit_tray_create_error),
        state->last_error);
    moonbit_tray_macos_release_state(state);
    free(state);
    return 0;
  }
  moonbit_tray_macos_apply_tooltip(state, tooltip);
  moonbit_tray_macos_send_void_bool(
      state->status_item,
      "setVisible:",
      (moonbit_tray_bool)0);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  moonbit_tray_clear_message(
      moonbit_tray_create_error,
      sizeof(moonbit_tray_create_error));
  return moonbit_tray_finish_create(state);
#else
  moonbit_tray_set_message(
      moonbit_tray_create_error,
      sizeof(moonbit_tray_create_error),
      "native tray backend is unavailable on this platform");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_tray_last_create_error(void) {
  return moonbit_tray_copy_message(moonbit_tray_create_error);
}

MOONBIT_FFI_EXPORT void moonbit_tray_destroy(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_registry_invalidate(handle);
  if (state == NULL) {
    return;
  }
  moonbit_tray_teardown_state(state);
  free(state);
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_show(
    int64_t handle,
    moonbit_bytes_t tooltip) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  NOTIFYICONDATAW next_icon_data = state->icon_data;
  moonbit_tray_copy_tooltip(&next_icon_data, tooltip);
  if (state->visible) {
    if (!Shell_NotifyIconW(NIM_MODIFY, &next_icon_data)) {
      moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "Shell_NotifyIconW(NIM_MODIFY) failed");
      return 0;
    }
    state->icon_data = next_icon_data;
    moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
    return 1;
  }
  if (!Shell_NotifyIconW(NIM_ADD, &next_icon_data)) {
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "Shell_NotifyIconW(NIM_ADD) failed");
    return 0;
  }
  state->icon_data = next_icon_data;
  state->visible = 1;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__linux__)
  moonbit_tray_linux_apply_tooltip(state, tooltip);
  moonbit_tray_linux_backend.app_indicator_set_status(
      state->indicator,
      MOONBIT_TRAY_APPINDICATOR_STATUS_ACTIVE);
  state->visible = 1;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__APPLE__)
  moonbit_tray_macos_apply_tooltip(state, tooltip);
  moonbit_tray_macos_send_void_bool(
      state->status_item,
      "setVisible:",
      (moonbit_tray_bool)1);
  state->visible = 1;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#else
  (void)tooltip;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_hide(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  if (!state->visible) {
    moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
    return 1;
  }
  if (!Shell_NotifyIconW(NIM_DELETE, &state->icon_data)) {
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "Shell_NotifyIconW(NIM_DELETE) failed");
    return 0;
  }
  state->visible = 0;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__linux__)
  moonbit_tray_linux_backend.app_indicator_set_status(
      state->indicator,
      MOONBIT_TRAY_APPINDICATOR_STATUS_PASSIVE);
  state->visible = 0;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__APPLE__)
  moonbit_tray_macos_send_void_bool(
      state->status_item,
      "setVisible:",
      (moonbit_tray_bool)0);
  state->visible = 0;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_set_tooltip(
    int64_t handle,
    moonbit_bytes_t tooltip) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  if (!state->visible) {
    moonbit_tray_copy_tooltip(&state->icon_data, tooltip);
    moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
    return 1;
  }
  NOTIFYICONDATAW next_icon_data = state->icon_data;
  moonbit_tray_copy_tooltip(&next_icon_data, tooltip);
  if (!Shell_NotifyIconW(NIM_MODIFY, &next_icon_data)) {
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "Shell_NotifyIconW(NIM_MODIFY) failed");
    return 0;
  }
  state->icon_data = next_icon_data;
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__linux__)
  moonbit_tray_linux_apply_tooltip(state, tooltip);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__APPLE__)
  moonbit_tray_macos_apply_tooltip(state, tooltip);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#else
  (void)tooltip;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_set_icon(
    int64_t handle,
    moonbit_bytes_t icon) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  if (!state->visible) {
    if (!moonbit_tray_replace_icon(state, icon)) {
      return 0;
    }
    moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
    return 1;
  }
  int32_t next_icon_owned = 0;
  HICON next_icon = moonbit_tray_load_icon(icon, &next_icon_owned);
  if (next_icon == NULL) {
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "failed to load tray icon");
    return 0;
  }
  NOTIFYICONDATAW next_icon_data = state->icon_data;
  next_icon_data.hIcon = next_icon;
  next_icon_data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  if (!Shell_NotifyIconW(NIM_MODIFY, &next_icon_data)) {
    if (next_icon != state->icon_data.hIcon) {
      moonbit_tray_destroy_icon_if_owned(next_icon, next_icon_owned);
    }
    moonbit_tray_set_message(state->last_error, sizeof(state->last_error), "Shell_NotifyIconW(NIM_MODIFY) failed");
    return 0;
  }
  moonbit_tray_commit_icon(state, next_icon, next_icon_owned);
  moonbit_tray_clear_message(state->last_error, sizeof(state->last_error));
  return 1;
#elif defined(__linux__)
  return moonbit_tray_linux_apply_icon(state, icon);
#elif defined(__APPLE__)
  return moonbit_tray_macos_apply_icon(state, icon);
#else
  (void)icon;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_begin(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_begin_menu(state);
#elif defined(__linux__)
  return moonbit_tray_linux_begin_menu(state);
#elif defined(__APPLE__)
  return moonbit_tray_macos_begin_menu(state);
#else
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu is unsupported on this platform");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_add_normal(
    int64_t handle,
    moonbit_bytes_t id,
    moonbit_bytes_t label,
    int32_t enabled) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      0,
      0);
#elif defined(__linux__)
  return moonbit_tray_linux_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      0,
      0);
#elif defined(__APPLE__)
  return moonbit_tray_macos_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      0);
#else
  (void)id;
  (void)label;
  (void)enabled;
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_add_checkbox(
    int64_t handle,
    moonbit_bytes_t id,
    moonbit_bytes_t label,
    int32_t enabled,
    int32_t checked) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      checked,
      1);
#elif defined(__linux__)
  return moonbit_tray_linux_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      checked,
      1);
#elif defined(__APPLE__)
  return moonbit_tray_macos_append_clickable_menu_item(
      state,
      id,
      label,
      enabled,
      checked);
#else
  (void)id;
  (void)label;
  (void)enabled;
  (void)checked;
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_add_separator(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_add_separator(state);
#elif defined(__linux__)
  return moonbit_tray_linux_add_separator(state);
#elif defined(__APPLE__)
  return moonbit_tray_macos_add_separator(state);
#else
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_begin_submenu(
    int64_t handle,
    moonbit_bytes_t label,
    int32_t enabled) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_begin_submenu(state, label, enabled);
#elif defined(__linux__)
  return moonbit_tray_linux_begin_submenu(state, label, enabled);
#elif defined(__APPLE__)
  return moonbit_tray_macos_begin_submenu(state, label, enabled);
#else
  (void)label;
  (void)enabled;
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_end_submenu(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_end_submenu(state);
#elif defined(__linux__)
  return moonbit_tray_linux_end_submenu(state);
#elif defined(__APPLE__)
  return moonbit_tray_macos_end_submenu(state);
#else
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_menu_commit(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return 0;
  }
#ifdef _WIN32
  return moonbit_tray_win_commit_menu(state);
#elif defined(__linux__)
  return moonbit_tray_linux_commit_menu(state);
#elif defined(__APPLE__)
  return moonbit_tray_macos_commit_menu(state);
#else
  moonbit_tray_set_message(
      state->last_error,
      sizeof(state->last_error),
      "tray menu transaction is not active");
  return 0;
#endif
}

MOONBIT_FFI_EXPORT void moonbit_tray_menu_abort(int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return;
  }
#ifdef _WIN32
  moonbit_tray_win_destroy_pending_menu(state);
#elif defined(__linux__)
  moonbit_tray_linux_destroy_pending_menu(state);
#elif defined(__APPLE__)
  moonbit_tray_macos_destroy_pending_menu(state);
#else
  (void)state;
#endif
}

MOONBIT_FFI_EXPORT int32_t moonbit_tray_pump(
    int64_t handle,
    int32_t blocking) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return -1;
  }
#ifdef _WIN32
  MSG message;
  BOOL has_message;
  if (blocking) {
    has_message = GetMessageW(&message, NULL, 0, 0);
    if (has_message <= 0) {
      return 0;
    }
  } else {
    has_message = PeekMessageW(&message, NULL, 0, 0, PM_REMOVE);
    if (!has_message) {
      return 1;
    }
  }
  TranslateMessage(&message);
  DispatchMessageW(&message);
  return 1;
#elif defined(__linux__)
  (void)state;
  moonbit_tray_linux_backend.gtk_main_iteration_do(blocking ? 1 : 0);
  return 1;
#elif defined(__APPLE__)
  {
    moonbit_tray_id pool = moonbit_tray_macos_new_pool();
    moonbit_tray_id until = blocking
        ? moonbit_tray_macos_send_id(
              moonbit_tray_macos_class("NSDate"),
              "distantFuture")
        : moonbit_tray_macos_send_id(
              moonbit_tray_macos_class("NSDate"),
              "distantPast");
    moonbit_tray_id event = moonbit_tray_macos_send_id_ulong_id_id_bool(
        state->app,
        "nextEventMatchingMask:untilDate:inMode:dequeue:",
        ULONG_MAX,
        until,
        moonbit_tray_macos_string("kCFRunLoopDefaultMode"),
        (moonbit_tray_bool)1);
    if (event != NULL) {
      moonbit_tray_macos_send_void_id(state->app, "sendEvent:", event);
    }
    moonbit_tray_macos_drain_pool(pool);
    return 1;
  }
#else
  (void)blocking;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_tray_poll_event_json(
    int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL || state->event_count == 0) {
    return moonbit_tray_copy_message("");
  }
  const char *event_json = state->events[state->event_head];
  moonbit_bytes_t result = moonbit_tray_copy_message(event_json);
  state->events[state->event_head][0] = '\0';
  state->event_head = (state->event_head + 1) % MOONBIT_TRAY_MAX_EVENTS;
  state->event_count--;
  return result;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t moonbit_tray_last_error(
    int64_t handle) {
  moonbit_tray_state_t *state = moonbit_tray_from_handle(handle);
  if (state == NULL) {
    return moonbit_tray_copy_message("invalid or stale tray handle");
  }
  return moonbit_tray_copy_message(state->last_error);
}
