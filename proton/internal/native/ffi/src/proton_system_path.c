#if !defined(__APPLE__)

#include "proton_internal.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <shlobj.h>
#include <windows.h>
#else
#include <glib.h>
#endif

static int32_t proton_system_path_write(const char *path, char *buffer,
                                        int32_t buffer_len,
                                        int32_t *out_required_len) {
  if (path == NULL || path[0] == '\0') {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "system path query returned no value");
  }
  size_t required = strlen(path);
  if (required > INT32_MAX) {
    return proton_set_error(PROTON_ERR_PLATFORM, "system path is too long");
  }
  *out_required_len = (int32_t)required;
  if (buffer == NULL || buffer_len <= (int32_t)required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "system path buffer is too small");
  }
  memcpy(buffer, path, required + 1);
  return proton_set_error(PROTON_OK, NULL);
}

#if defined(_WIN32)
static const KNOWNFOLDERID *proton_system_path_windows_id(int32_t kind) {
  switch (kind) {
  case PROTON_SYSTEM_PATH_DESKTOP:
    return &FOLDERID_Desktop;
  case PROTON_SYSTEM_PATH_DOCUMENTS:
    return &FOLDERID_Documents;
  case PROTON_SYSTEM_PATH_DOWNLOADS:
    return &FOLDERID_Downloads;
  case PROTON_SYSTEM_PATH_MUSIC:
    return &FOLDERID_Music;
  case PROTON_SYSTEM_PATH_PICTURES:
    return &FOLDERID_Pictures;
  case PROTON_SYSTEM_PATH_VIDEOS:
    return &FOLDERID_Videos;
  case PROTON_SYSTEM_PATH_RECENT:
    return &FOLDERID_Recent;
  default:
    return NULL;
  }
}

static int32_t proton_system_path_platform(int32_t kind, char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len) {
  const KNOWNFOLDERID *folder = proton_system_path_windows_id(kind);
  if (folder == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "unsupported system path kind");
  }
  PWSTR wide = NULL;
  HRESULT result = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, NULL, &wide);
  if (FAILED(result) || wide == NULL) {
    char message[128];
    snprintf(message, sizeof(message), "SHGetKnownFolderPath failed: 0x%08lx",
             (unsigned long)result);
    CoTaskMemFree(wide);
    return proton_set_error(PROTON_ERR_PLATFORM, message);
  }
  int utf8_len = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
                                     NULL, 0, NULL, NULL);
  if (utf8_len <= 0) {
    CoTaskMemFree(wide);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to encode system path as UTF-8");
  }
  *out_required_len = utf8_len - 1;
  if (buffer == NULL || buffer_len < utf8_len) {
    CoTaskMemFree(wide);
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "system path buffer is too small");
  }
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, buffer,
                          buffer_len, NULL, NULL) <= 0) {
    CoTaskMemFree(wide);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to encode system path as UTF-8");
  }
  CoTaskMemFree(wide);
  return proton_set_error(PROTON_OK, NULL);
}
#else
static GUserDirectory proton_system_path_linux_directory(int32_t kind) {
  switch (kind) {
  case PROTON_SYSTEM_PATH_DESKTOP:
    return G_USER_DIRECTORY_DESKTOP;
  case PROTON_SYSTEM_PATH_DOCUMENTS:
    return G_USER_DIRECTORY_DOCUMENTS;
  case PROTON_SYSTEM_PATH_DOWNLOADS:
    return G_USER_DIRECTORY_DOWNLOAD;
  case PROTON_SYSTEM_PATH_MUSIC:
    return G_USER_DIRECTORY_MUSIC;
  case PROTON_SYSTEM_PATH_PICTURES:
    return G_USER_DIRECTORY_PICTURES;
  case PROTON_SYSTEM_PATH_VIDEOS:
    return G_USER_DIRECTORY_VIDEOS;
  default:
    return G_USER_N_DIRECTORIES;
  }
}

static const char *proton_system_path_linux_fallback(int32_t kind) {
  switch (kind) {
  case PROTON_SYSTEM_PATH_DESKTOP:
    return "Desktop";
  case PROTON_SYSTEM_PATH_DOCUMENTS:
    return "Documents";
  case PROTON_SYSTEM_PATH_DOWNLOADS:
    return "Downloads";
  case PROTON_SYSTEM_PATH_MUSIC:
    return "Music";
  case PROTON_SYSTEM_PATH_PICTURES:
    return "Pictures";
  case PROTON_SYSTEM_PATH_VIDEOS:
    return "Videos";
  default:
    return NULL;
  }
}

static int32_t proton_system_path_platform(int32_t kind, char *buffer,
                                           int32_t buffer_len,
                                           int32_t *out_required_len) {
  GUserDirectory directory = proton_system_path_linux_directory(kind);
  const char *fallback = proton_system_path_linux_fallback(kind);
  if (directory == G_USER_N_DIRECTORIES || fallback == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "unsupported system path kind");
  }
  const char *path = g_get_user_special_dir(directory);
  if (path != NULL && path[0] != '\0') {
    return proton_system_path_write(path, buffer, buffer_len, out_required_len);
  }
  const char *home = g_get_home_dir();
  if (home == NULL || home[0] == '\0') {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "cannot resolve the Linux home directory");
  }
  char *joined = g_build_filename(home, fallback, NULL);
  if (joined == NULL) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "failed to allocate Linux system path");
  }
  int32_t status =
      proton_system_path_write(joined, buffer, buffer_len, out_required_len);
  g_free(joined);
  return status;
}
#endif

int32_t proton_system_path(int32_t kind, char *buffer, int32_t buffer_len,
                           int32_t *out_required_len) {
  if (out_required_len == NULL || buffer_len < 0 ||
      (buffer == NULL && buffer_len != 0)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid system path output buffer");
  }
  *out_required_len = 0;
  return proton_system_path_platform(kind, buffer, buffer_len,
                                     out_required_len);
}

#endif
