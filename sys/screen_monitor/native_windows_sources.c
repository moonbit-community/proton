#include "native_stub.h"

#include <string.h>

#ifdef _WIN32

#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

typedef struct window_sources_buffer {
  char *data;
  size_t length;
  size_t capacity;
  int first;
} window_sources_buffer_t;

static int append_text(window_sources_buffer_t *buffer, const char *text) {
  size_t length = strlen(text);
  if (buffer->length + length + 1 > buffer->capacity) {
    size_t capacity = buffer->capacity == 0 ? 1024 : buffer->capacity * 2;
    while (capacity < buffer->length + length + 1) capacity *= 2;
    char *data = (char *)realloc(buffer->data, capacity);
    if (data == NULL) return 0;
    buffer->data = data;
    buffer->capacity = capacity;
  }
  memcpy(buffer->data + buffer->length, text, length);
  buffer->length += length;
  buffer->data[buffer->length] = '\0';
  return 1;
}

static int append_json_string(window_sources_buffer_t *buffer, const wchar_t *value) {
  int needed = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (needed <= 0) return 0;
  char *utf8 = (char *)malloc((size_t)needed);
  if (utf8 == NULL) return 0;
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, utf8, needed, NULL, NULL) <= 0) {
    free(utf8);
    return 0;
  }
  if (!append_text(buffer, "\"")) { free(utf8); return 0; }
  for (char *cursor = utf8; *cursor != '\0'; cursor++) {
    char escaped[3] = { 0, 0, 0 };
    if (*cursor == '\\' || *cursor == '"') {
      escaped[0] = '\\'; escaped[1] = *cursor;
      if (!append_text(buffer, escaped)) { free(utf8); return 0; }
    } else if ((unsigned char)*cursor < 0x20) {
      if (!append_text(buffer, " ")) { free(utf8); return 0; }
    } else {
      escaped[0] = *cursor;
      if (!append_text(buffer, escaped)) { free(utf8); return 0; }
    }
  }
  free(utf8);
  return append_text(buffer, "\"");
}

static BOOL CALLBACK enumerate_window(HWND hwnd, LPARAM parameter) {
  window_sources_buffer_t *buffer = (window_sources_buffer_t *)parameter;
  if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;
  wchar_t title[512];
  int length = GetWindowTextW(hwnd, title, 512);
  if (length <= 0) return TRUE;
  RECT rect;
  if (!GetWindowRect(hwnd, &rect) || rect.right <= rect.left || rect.bottom <= rect.top) return TRUE;
  char item[256];
  snprintf(item, sizeof(item), "%s{\"id\":\"window:%llu\",\"display_id\":\"\",\"x\":%ld,\"y\":%ld,\"width\":%ld,\"height\":%ld,\"thumbnail\":null,\"name\":",
           buffer->first ? "" : ",", (unsigned long long)(uintptr_t)hwnd,
           rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
  if (!append_text(buffer, item) || !append_json_string(buffer, title) || !append_text(buffer, "}")) return FALSE;
  buffer->first = 0;
  return TRUE;
}

#endif

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_window_sources_json(void) {
#ifdef _WIN32
  window_sources_buffer_t buffer = { NULL, 0, 0, 1 };
  if (!append_text(&buffer, "{\"supported\":true,\"sources\":[")) {
    free(buffer.data); return moonbit_make_bytes(0, 0);
  }
  EnumWindows(enumerate_window, (LPARAM)&buffer);
  if (!append_text(&buffer, "]}")) { free(buffer.data); return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)buffer.length, 0);
  memcpy(result, buffer.data, buffer.length);
  free(buffer.data);
  return result;
#else
  const char *unsupported = "{\"supported\":false,\"sources\":[],\"error\":\"window sources are not implemented on this platform\"}";
  size_t length = strlen(unsupported);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, unsupported, length);
  return result;
#endif
}
