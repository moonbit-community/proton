#include "native_stub.h"

#include <string.h>

#ifdef _WIN32

#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <stdint.h>
#include <windows.h>

typedef struct window_sources_buffer {
  char *data;
  size_t length;
  size_t capacity;
  int first;
  int width;
  int height;
} window_sources_buffer_t;

static const char base64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *capture_thumbnail(HWND hwnd, int width, int height) {
  if (width <= 0 || height <= 0) return NULL;
  RECT rect;
  if (!GetWindowRect(hwnd, &rect)) return NULL;
  int source_width = rect.right - rect.left;
  int source_height = rect.bottom - rect.top;
  if (source_width <= 0 || source_height <= 0) return NULL;
  HDC source = GetWindowDC(hwnd);
  HDC target = CreateCompatibleDC(source);
  HBITMAP bitmap = CreateCompatibleBitmap(source, width, height);
  if (source == NULL || target == NULL || bitmap == NULL) {
    if (bitmap) DeleteObject(bitmap); if (target) DeleteDC(target); if (source) ReleaseDC(hwnd, source);
    return NULL;
  }
  HGDIOBJ old = SelectObject(target, bitmap);
  SetStretchBltMode(target, HALFTONE);
  BOOL captured = PrintWindow(hwnd, target, 2);
  if (!captured) captured = StretchBlt(target, 0, 0, width, height, source, 0, 0, source_width, source_height, SRCCOPY);
  BITMAPINFO info; memset(&info, 0, sizeof(info));
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height; info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  size_t pixels_size = (size_t)width * (size_t)height * 4;
  unsigned char *pixels = (unsigned char *)malloc(pixels_size);
  char *result = NULL;
  if (captured && pixels && GetDIBits(target, bitmap, 0, (UINT)height, pixels, &info, DIB_RGB_COLORS) == (int)height) {
    size_t raw_size = 54 + pixels_size;
    size_t encoded_size = ((raw_size + 2) / 3) * 4;
    result = (char *)malloc(23 + encoded_size + 1);
    if (result) {
      unsigned char *raw = (unsigned char *)calloc(1, raw_size);
      if (!raw) { free(result); result = NULL; }
      else {
        raw[0] = 'B'; raw[1] = 'M'; uint32_t file_size = (uint32_t)raw_size;
        memcpy(raw + 2, &file_size, 4); uint32_t offset = 54; memcpy(raw + 10, &offset, 4);
        uint32_t header_size = 40; memcpy(raw + 14, &header_size, 4); int32_t bmp_height = -height; memcpy(raw + 18, &width, 4); memcpy(raw + 22, &bmp_height, 4);
        uint16_t planes = 1, bits = 32; memcpy(raw + 26, &planes, 2); memcpy(raw + 28, &bits, 2); uint32_t image_size = (uint32_t)pixels_size; memcpy(raw + 34, &image_size, 4);
        memcpy(raw + 54, pixels, pixels_size); memcpy(result, "data:image/bmp;base64,", 22);
        size_t out = 22;
        for (size_t i = 0; i < raw_size; i += 3) { uint32_t v = raw[i] << 16; if (i + 1 < raw_size) v |= raw[i + 1] << 8; if (i + 2 < raw_size) v |= raw[i + 2]; result[out++] = base64_table[(v >> 18) & 63]; result[out++] = base64_table[(v >> 12) & 63]; result[out++] = i + 1 < raw_size ? base64_table[(v >> 6) & 63] : '='; result[out++] = i + 2 < raw_size ? base64_table[v & 63] : '='; }
        result[out] = '\0'; free(raw);
      }
    }
  }
  free(pixels); SelectObject(target, old); DeleteObject(bitmap); DeleteDC(target); ReleaseDC(hwnd, source); return result;
}

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
  char *thumbnail = capture_thumbnail(hwnd, buffer->width, buffer->height);
  snprintf(item, sizeof(item), "%s{\"id\":\"window:%llu\",\"display_id\":\"\",\"x\":%ld,\"y\":%ld,\"width\":%ld,\"height\":%ld,\"thumbnail\":",
           buffer->first ? "" : ",", (unsigned long long)(uintptr_t)hwnd,
           rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
  int ok = append_text(buffer, item);
  if (ok && thumbnail) ok = append_text(buffer, "\"") && append_text(buffer, thumbnail) && append_text(buffer, "\"");
  if (ok && !thumbnail) ok = append_text(buffer, "null");
  ok = ok && append_text(buffer, ",\"name\":") && append_json_string(buffer, title) && append_text(buffer, "}");
  free(thumbnail); if (!ok) return FALSE;
  buffer->first = 0;
  return TRUE;
}

#endif

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_screen_monitor_window_sources_json(int32_t width, int32_t height) {
#ifdef _WIN32
  window_sources_buffer_t buffer = { NULL, 0, 0, 1, width, height };
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
