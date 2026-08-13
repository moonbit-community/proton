#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#elif !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif

#include "profile_storage.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

#define PROTON_PROFILE_PATH_CHARS 4096

static volatile LONG proton_profile_serial = 0;

static int proton_profile_utf8_to_wide(const char *value, wchar_t *out,
                                       size_t out_len) {
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, out,
                             (int)out_len) > 0;
}

static void proton_profile_remove_wide(const wchar_t *path) {
  DWORD attributes = GetFileAttributesW(path);
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    return;
  }
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      RemoveDirectoryW(path);
    } else {
      DeleteFileW(path);
    }
    return;
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    DeleteFileW(path);
    return;
  }

  wchar_t pattern[PROTON_PROFILE_PATH_CHARS];
  if (_snwprintf_s(pattern, PROTON_PROFILE_PATH_CHARS, _TRUNCATE, L"%ls\\*",
                   path) < 0) {
    return;
  }
  WIN32_FIND_DATAW entry;
  HANDLE search = FindFirstFileW(pattern, &entry);
  if (search != INVALID_HANDLE_VALUE) {
    do {
      if (wcscmp(entry.cFileName, L".") == 0 ||
          wcscmp(entry.cFileName, L"..") == 0) {
        continue;
      }
      wchar_t child[PROTON_PROFILE_PATH_CHARS];
      if (_snwprintf_s(child, PROTON_PROFILE_PATH_CHARS, _TRUNCATE,
                       L"%ls\\%ls", path, entry.cFileName) >= 0) {
        proton_profile_remove_wide(child);
      }
    } while (FindNextFileW(search, &entry));
    FindClose(search);
  }
  RemoveDirectoryW(path);
}

int proton_profile_storage_create_temporary(char *path, size_t path_len,
                                            char *error, size_t error_len) {
  wchar_t base[PROTON_PROFILE_PATH_CHARS];
  DWORD base_len = GetTempPathW(PROTON_PROFILE_PATH_CHARS, base);
  if (base_len == 0 || base_len >= PROTON_PROFILE_PATH_CHARS) {
    snprintf(error, error_len, "failed to resolve temporary directory: %lu",
             (unsigned long)GetLastError());
    return 0;
  }
  for (int attempt = 0; attempt < 128; attempt++) {
    wchar_t candidate[PROTON_PROFILE_PATH_CHARS];
    LONG serial = InterlockedIncrement(&proton_profile_serial);
    if (_snwprintf_s(candidate, PROTON_PROFILE_PATH_CHARS, _TRUNCATE,
                     L"%lsproton-cef-%lu-%llu-%ld", base,
                     (unsigned long)GetCurrentProcessId(),
                     (unsigned long long)GetTickCount64(), (long)serial) < 0) {
      break;
    }
    if (!CreateDirectoryW(candidate, NULL)) {
      if (GetLastError() == ERROR_ALREADY_EXISTS) {
        continue;
      }
      break;
    }
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, candidate, -1, path,
                            (int)path_len, NULL, NULL) > 0) {
      return 1;
    }
    proton_profile_remove_wide(candidate);
    break;
  }
  snprintf(error, error_len, "failed to create temporary browser storage: %lu",
           (unsigned long)GetLastError());
  return 0;
}

void proton_profile_storage_remove_temporary(const char *path) {
  wchar_t wide_path[PROTON_PROFILE_PATH_CHARS];
  if (path != NULL && path[0] != '\0' &&
      proton_profile_utf8_to_wide(path, wide_path, PROTON_PROFILE_PATH_CHARS)) {
    proton_profile_remove_wide(wide_path);
  }
}

#else

#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#define PROTON_PROFILE_PATH_BYTES 4096

static void proton_profile_remove_path(const char *path) {
  struct stat info;
  if (lstat(path, &info) != 0) {
    return;
  }
  if (!S_ISDIR(info.st_mode) || S_ISLNK(info.st_mode)) {
    (void)unlink(path);
    return;
  }

  DIR *directory = opendir(path);
  if (directory != NULL) {
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
      if (strcmp(entry->d_name, ".") == 0 ||
          strcmp(entry->d_name, "..") == 0) {
        continue;
      }
      char child[PROTON_PROFILE_PATH_BYTES];
      int written = snprintf(child, sizeof(child), "%s/%s", path,
                             entry->d_name);
      if (written > 0 && (size_t)written < sizeof(child)) {
        proton_profile_remove_path(child);
      }
    }
    closedir(directory);
  }
  (void)rmdir(path);
}

int proton_profile_storage_create_temporary(char *path, size_t path_len,
                                            char *error, size_t error_len) {
  const char *base = getenv("TMPDIR");
  if (base == NULL || base[0] == '\0') {
    base = "/tmp";
  }
  int written = snprintf(path, path_len, "%s%sproton-cef-XXXXXX", base,
                         base[strlen(base) - 1] == '/' ? "" : "/");
  if (written < 0 || (size_t)written >= path_len) {
    snprintf(error, error_len, "temporary browser storage path is too long");
    return 0;
  }
  if (mkdtemp(path) == NULL) {
    snprintf(error, error_len, "failed to create temporary browser storage: %s",
             strerror(errno));
    path[0] = '\0';
    return 0;
  }
  return 1;
}

void proton_profile_storage_remove_temporary(const char *path) {
  if (path != NULL && path[0] != '\0') {
    proton_profile_remove_path(path);
  }
}

#endif
