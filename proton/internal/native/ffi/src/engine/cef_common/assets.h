#ifndef PROTON_ENGINE_CEF_COMMON_ASSETS_H
#define PROTON_ENGINE_CEF_COMMON_ASSETS_H

#include "app_origin.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

/* Every engine spells this the same way for a given platform, so the header
   supplies it rather than making each includer define it first. Engines that
   still declare their own keep it -- the definitions agree. */
#ifndef PROTON_ENGINE_PATH_SEPARATOR
#ifdef _WIN32
#define PROTON_ENGINE_PATH_SEPARATOR '\\'
#else
#define PROTON_ENGINE_PATH_SEPARATOR '/'
#endif
#endif

static int proton_engine_hex_value(char ch) {
  if (ch >= '0' && ch <= '9') {
    return ch - '0';
  }
  if (ch >= 'a' && ch <= 'f') {
    return ch - 'a' + 10;
  }
  if (ch >= 'A' && ch <= 'F') {
    return ch - 'A' + 10;
  }
  return -1;
}

static char *proton_engine_url_decode_path(const char *value, size_t len) {
  char *decoded = (char *)malloc(len + 1);
  if (decoded == NULL) {
    return NULL;
  }
  size_t out = 0;
  for (size_t i = 0; i < len; i++) {
    if (value[i] == '%' && i + 2 < len) {
      int hi = proton_engine_hex_value(value[i + 1]);
      int lo = proton_engine_hex_value(value[i + 2]);
      if (hi >= 0 && lo >= 0) {
        char decoded_byte = (char)((hi << 4) | lo);
        if (decoded_byte == '\0') {
          free(decoded);
          return NULL;
        }
        decoded[out++] = decoded_byte;
        i += 2;
        continue;
      }
    }
    decoded[out++] = value[i] == '/' ? PROTON_ENGINE_PATH_SEPARATOR : value[i];
  }
  decoded[out] = '\0';
  return decoded;
}

static int proton_engine_url_path_has_unsafe_segment(const char *path) {
  if (path == NULL) {
    return 1;
  }
  size_t segment_len = 0;
  for (const char *cursor = path;; cursor++) {
    char ch = *cursor;
    if (ch == '\0' || ch == '/' || ch == '\\') {
      if (segment_len == 2 && cursor[-2] == '.' && cursor[-1] == '.') {
        return 1;
      }
      segment_len = 0;
      if (ch == '\0') {
        return 0;
      }
    } else {
      segment_len++;
    }
  }
}

static int proton_engine_asset_path_separator(char ch) {
  return ch == '/' || ch == '\\';
}

static char *proton_engine_asset_canonical_path(const char *path) {
  if (path == NULL || path[0] == '\0') {
    return NULL;
  }
#ifdef _WIN32
  int wide_len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                     NULL, 0);
  if (wide_len <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)malloc(
      (size_t)wide_len * sizeof(wchar_t));
  if (wide == NULL ||
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide,
                          wide_len) == 0) {
    free(wide);
    return NULL;
  }
  DWORD full_len = GetFullPathNameW(wide, 0, NULL, NULL);
  if (full_len == 0) {
    free(wide);
    return NULL;
  }
  wchar_t *full = (wchar_t *)malloc(
      (size_t)full_len * sizeof(wchar_t));
  DWORD written = full == NULL
                      ? 0
                      : GetFullPathNameW(wide, full_len, full, NULL);
  if (written == 0 || written >= full_len) {
    free(wide);
    free(full);
    return NULL;
  }
  free(wide);
  int utf8_len = WideCharToMultiByte(CP_UTF8, 0, full, -1, NULL, 0, NULL, NULL);
  if (utf8_len <= 0) {
    free(full);
    return NULL;
  }
  char *result = (char *)malloc((size_t)utf8_len);
  if (result == NULL ||
      WideCharToMultiByte(CP_UTF8, 0, full, -1, result, utf8_len, NULL,
                          NULL) == 0) {
    free(full);
    free(result);
    return NULL;
  }
  free(full);
  return result;
#else
  return realpath(path, NULL);
#endif
}

static int proton_engine_asset_path_is_under_root(const char *path,
                                                  const char *root) {
  if (path == NULL || root == NULL || root[0] == '\0') {
    return 0;
  }
  size_t root_len = strlen(root);
  while (root_len > 1 &&
         proton_engine_asset_path_separator(root[root_len - 1])) {
    root_len--;
  }
#ifdef _WIN32
  if (_strnicmp(path, root, root_len) != 0) {
#else
  if (strncmp(path, root, root_len) != 0) {
#endif
    return 0;
  }
  return path[root_len] == '\0' ||
         proton_engine_asset_path_separator(path[root_len]);
}

static char *proton_engine_url_to_rooted_asset_path(const char *url,
                                                    const char *asset_root) {
  static const char prefix[] = PROTON_ENGINE_APP_URL_PREFIX;
  if (url == NULL || asset_root == NULL || asset_root[0] == '\0' ||
      strncmp(url, prefix, sizeof(prefix) - 1) != 0) {
    return NULL;
  }
  const char *path = url + sizeof(prefix) - 1;
  size_t path_len = strcspn(path, "?#");
  if (path_len == 0) {
    return NULL;
  }
  char *decoded = proton_engine_url_decode_path(path, path_len);
  if (decoded == NULL || proton_engine_asset_path_separator(decoded[0]) ||
      proton_engine_url_path_has_unsafe_segment(decoded)
#ifdef _WIN32
      || strchr(decoded, ':') != NULL
#endif
  ) {
    free(decoded);
    return NULL;
  }
  size_t root_len = strlen(asset_root);
  size_t decoded_len = strlen(decoded);
  int needs_separator =
      root_len > 0 && !proton_engine_asset_path_separator(asset_root[root_len - 1]);
  if (root_len > SIZE_MAX - decoded_len - 2) {
    free(decoded);
    return NULL;
  }
  char *joined = (char *)malloc(root_len + (size_t)needs_separator +
                                decoded_len + 1);
  if (joined == NULL) {
    free(decoded);
    return NULL;
  }
  memcpy(joined, asset_root, root_len);
  if (needs_separator) {
    joined[root_len++] = PROTON_ENGINE_PATH_SEPARATOR;
  }
  memcpy(joined + root_len, decoded, decoded_len + 1);
  free(decoded);

  char *canonical_root = proton_engine_asset_canonical_path(asset_root);
  char *canonical_path = proton_engine_asset_canonical_path(joined);
  free(joined);
  if (!proton_engine_asset_path_is_under_root(canonical_path,
                                               canonical_root)) {
    free(canonical_root);
    free(canonical_path);
    return NULL;
  }
  free(canonical_root);
  return canonical_path;
}

static const char *proton_engine_asset_mime_type(const char *path) {
  const char *dot = path != NULL ? strrchr(path, '.') : NULL;
  if (dot == NULL) {
    return "application/octet-stream";
  }
  if (strcmp(dot, ".html") == 0 || strcmp(dot, ".htm") == 0) {
    return "text/html";
  }
  if (strcmp(dot, ".css") == 0) {
    return "text/css";
  }
  if (strcmp(dot, ".js") == 0 || strcmp(dot, ".mjs") == 0) {
    return "text/javascript";
  }
  if (strcmp(dot, ".json") == 0) {
    return "application/json";
  }
  if (strcmp(dot, ".svg") == 0) {
    return "image/svg+xml";
  }
  if (strcmp(dot, ".png") == 0) {
    return "image/png";
  }
  if (strcmp(dot, ".jpg") == 0 || strcmp(dot, ".jpeg") == 0) {
    return "image/jpeg";
  }
  if (strcmp(dot, ".gif") == 0) {
    return "image/gif";
  }
  if (strcmp(dot, ".webp") == 0) {
    return "image/webp";
  }
  if (strcmp(dot, ".ico") == 0) {
    return "image/x-icon";
  }
  if (strcmp(dot, ".txt") == 0) {
    return "text/plain";
  }
  if (strcmp(dot, ".woff") == 0) {
    return "font/woff";
  }
  if (strcmp(dot, ".woff2") == 0) {
    return "font/woff2";
  }
  if (strcmp(dot, ".ttf") == 0) {
    return "font/ttf";
  }
  if (strcmp(dot, ".otf") == 0) {
    return "font/otf";
  }
  return "application/octet-stream";
}

static FILE *proton_engine_asset_fopen_read(const char *path) {
#ifdef _WIN32
  /* Asset paths are UTF-8; ANSI fopen() would mangle non-ASCII roots. */
  wchar_t wide_path[4096];
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wide_path,
                          (int)(sizeof(wide_path) /
                                sizeof(wide_path[0]))) <= 0) {
    return NULL;
  }
  return _wfopen(wide_path, L"rb");
#else
  return fopen(path, "rb");
#endif
}

static int proton_engine_read_asset_file(const char *path,
                                         char **out_data,
                                         size_t *out_len) {
  if (out_data == NULL || out_len == NULL) {
    return 0;
  }
  *out_data = NULL;
  *out_len = 0;
  if (path == NULL || path[0] == '\0') {
    return 0;
  }
  FILE *file = proton_engine_asset_fopen_read(path);
  if (file == NULL) {
    return 0;
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    return 0;
  }
  long len = ftell(file);
  if (len < 0) {
    fclose(file);
    return 0;
  }
  if (fseek(file, 0, SEEK_SET) != 0) {
    fclose(file);
    return 0;
  }
  char *data = (char *)malloc((size_t)len + 1);
  if (data == NULL) {
    fclose(file);
    return 0;
  }
  size_t read_len = fread(data, 1, (size_t)len, file);
  fclose(file);
  if (read_len != (size_t)len) {
    free(data);
    return 0;
  }
  data[read_len] = '\0';
  *out_data = data;
  *out_len = read_len;
  return 1;
}

#endif
