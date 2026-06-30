#ifndef PROTON_ENGINE_CEF_COMMON_ASSETS_H
#define PROTON_ENGINE_CEF_COMMON_ASSETS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        decoded[out++] = (char)((hi << 4) | lo);
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

static char *proton_engine_url_to_asset_path(const char *url) {
  static const char prefix[] = "proton://app/";
  if (url == NULL || strncmp(url, prefix, sizeof(prefix) - 1) != 0) {
    return NULL;
  }
  const char *path = url + sizeof(prefix) - 1;
  size_t path_len = strcspn(path, "?#");
  if (path_len == 0) {
    return NULL;
  }
  char *decoded = proton_engine_url_decode_path(path, path_len);
  if (decoded == NULL || proton_engine_url_path_has_unsafe_segment(decoded)) {
    free(decoded);
    return NULL;
  }
  return decoded;
}

static char *proton_engine_asset_path_dirname(const char *path) {
  if (path == NULL) {
    return NULL;
  }
  const char *slash = strrchr(path, '/');
  const char *backslash = strrchr(path, '\\');
  const char *separator = slash;
  if (backslash != NULL && (separator == NULL || backslash > separator)) {
    separator = backslash;
  }
  if (separator == NULL) {
    return proton_engine_strdup("");
  }
  return proton_engine_strdup_len(path, (size_t)(separator - path + 1));
}

static int proton_engine_asset_path_is_under_root(const char *path,
                                                  const char *root) {
  if (path == NULL || root == NULL || root[0] == '\0') {
    return 0;
  }
  size_t root_len = strlen(root);
  return strncmp(path, root, root_len) == 0;
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
  return "application/octet-stream";
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
  FILE *file = fopen(path, "rb");
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
