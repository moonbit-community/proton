#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <process.h>
#include <windows.h>
#else
#include <dirent.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "moonbit.h"

static char proton_cli_error[1024] = "";

static moonbit_bytes_t proton_cli_make_bytes(const char *buffer) {
  size_t len = buffer == NULL ? 0 : strlen(buffer);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)(len + 1), 0);
  if (len > 0) {
    memcpy(result, buffer, len);
  }
  result[len] = '\0';
  return result;
}

static void proton_cli_set_error(const char *message) {
  if (message == NULL || message[0] == '\0') {
    message = strerror(errno);
  }
  snprintf(proton_cli_error, sizeof(proton_cli_error), "%s", message);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_cli_last_error(void) {
  return proton_cli_make_bytes(proton_cli_error);
}

MOONBIT_FFI_EXPORT int32_t proton_cli_is_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_cli_getcwd(void) {
  char buffer[4096];
#ifdef _WIN32
  if (_getcwd(buffer, sizeof(buffer)) == NULL) {
#else
  if (getcwd(buffer, sizeof(buffer)) == NULL) {
#endif
    proton_cli_set_error(NULL);
    return proton_cli_make_bytes("");
  }
  return proton_cli_make_bytes(buffer);
}

static int proton_cli_mkdir(const char *path) {
#ifdef _WIN32
  if (_mkdir(path) == 0 || errno == EEXIST) {
#else
  if (mkdir(path, 0777) == 0 || errno == EEXIST) {
#endif
    return 0;
  }
  proton_cli_set_error(NULL);
  return -1;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t proton_cli_make_temp_dir(moonbit_bytes_t prefix) {
  char buffer[4096];
#ifdef _WIN32
  char temp_path[MAX_PATH + 1];
  char unique[MAX_PATH + 1];
  DWORD len = GetTempPathA((DWORD)sizeof(temp_path), temp_path);
  if (len == 0 || len >= sizeof(temp_path)) {
    proton_cli_set_error("GetTempPathA failed");
    return proton_cli_make_bytes("");
  }
  if (GetTempFileNameA(temp_path, (const char *)prefix, 0, unique) == 0) {
    proton_cli_set_error("GetTempFileNameA failed");
    return proton_cli_make_bytes("");
  }
  DeleteFileA(unique);
  if (_mkdir(unique) != 0) {
    proton_cli_set_error(NULL);
    return proton_cli_make_bytes("");
  }
  return proton_cli_make_bytes(unique);
#else
  snprintf(buffer, sizeof(buffer), "/tmp/%sXXXXXX", (const char *)prefix);
  if (mkdtemp(buffer) == NULL) {
    proton_cli_set_error(NULL);
    return proton_cli_make_bytes("");
  }
  return proton_cli_make_bytes(buffer);
#endif
}

static int proton_cli_run_process(char *const argv[]) {
#ifdef _WIN32
  intptr_t code = _spawnvp(_P_WAIT, argv[0], (const char *const *)argv);
  if (code == -1) {
    proton_cli_set_error(NULL);
    return -1;
  }
  if (code != 0) {
    snprintf(proton_cli_error, sizeof(proton_cli_error), "%s exited with code %ld", argv[0], (long)code);
    return -1;
  }
  return 0;
#else
  pid_t pid = fork();
  if (pid < 0) {
    proton_cli_set_error(NULL);
    return -1;
  }
  if (pid == 0) {
    execvp(argv[0], argv);
    _exit(127);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    proton_cli_set_error(NULL);
    return -1;
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    snprintf(proton_cli_error, sizeof(proton_cli_error), "%s exited with code %d", argv[0], WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    return -1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t proton_cli_download_file(moonbit_bytes_t url, moonbit_bytes_t destination) {
  char *argv[] = {
    "curl",
    "-L",
    "--fail",
    "--output",
    (char *)destination,
    (char *)url,
    NULL,
  };
  return proton_cli_run_process(argv);
}

MOONBIT_FFI_EXPORT int32_t proton_cli_extract_tar_bz2(moonbit_bytes_t archive_path, moonbit_bytes_t destination) {
  char *argv[] = {
    "tar",
    "-xjf",
    (char *)archive_path,
    "-C",
    (char *)destination,
    NULL,
  };
  return proton_cli_run_process(argv);
}

static int proton_cli_is_dir(const char *path) {
  struct stat info;
  if (stat(path, &info) != 0) {
    return 0;
  }
#ifdef _WIN32
  return (info.st_mode & _S_IFDIR) != 0;
#else
  return S_ISDIR(info.st_mode);
#endif
}

static int proton_cli_is_file(const char *path) {
  struct stat info;
  if (stat(path, &info) != 0) {
    return 0;
  }
#ifdef _WIN32
  return (info.st_mode & _S_IFREG) != 0;
#else
  return S_ISREG(info.st_mode);
#endif
}

static void proton_cli_join_path(char *out, size_t out_len, const char *base, const char *child) {
  size_t len = strlen(base);
  const char sep =
#ifdef _WIN32
      '\\';
#else
      '/';
#endif
  if (len > 0 && (base[len - 1] == '/' || base[len - 1] == '\\')) {
    snprintf(out, out_len, "%s%s", base, child);
  } else {
    snprintf(out, out_len, "%s%c%s", base, sep, child);
  }
}

MOONBIT_FFI_EXPORT int32_t proton_cli_copy_file(moonbit_bytes_t src, moonbit_bytes_t dest) {
  FILE *in = fopen((const char *)src, "rb");
  if (in == NULL) {
    proton_cli_set_error(NULL);
    return -1;
  }
  FILE *out = fopen((const char *)dest, "wb");
  if (out == NULL) {
    fclose(in);
    proton_cli_set_error(NULL);
    return -1;
  }
  char buffer[8192];
  size_t read_count;
  while ((read_count = fread(buffer, 1, sizeof(buffer), in)) > 0) {
    if (fwrite(buffer, 1, read_count, out) != read_count) {
      fclose(in);
      fclose(out);
      proton_cli_set_error(NULL);
      return -1;
    }
  }
  if (ferror(in) != 0 || fflush(out) != 0) {
    fclose(in);
    fclose(out);
    proton_cli_set_error(NULL);
    return -1;
  }
  if (fclose(in) != 0 || fclose(out) != 0) {
    proton_cli_set_error(NULL);
    return -1;
  }
  return 0;
}

static int proton_cli_copy_tree_impl(const char *src, const char *dest) {
  if (proton_cli_is_file(src)) {
    return proton_cli_copy_file((moonbit_bytes_t)src, (moonbit_bytes_t)dest);
  }
  if (!proton_cli_is_dir(src)) {
    proton_cli_set_error("source path is not a file or directory");
    return -1;
  }
  if (proton_cli_mkdir(dest) != 0) {
    return -1;
  }
#ifdef _WIN32
  char pattern[4096];
  WIN32_FIND_DATAA data;
  HANDLE handle;
  proton_cli_join_path(pattern, sizeof(pattern), src, "*");
  handle = FindFirstFileA(pattern, &data);
  if (handle == INVALID_HANDLE_VALUE) {
    proton_cli_set_error("FindFirstFileA failed");
    return -1;
  }
  do {
    if (strcmp(data.cFileName, ".") == 0 || strcmp(data.cFileName, "..") == 0) {
      continue;
    }
    char child_src[4096];
    char child_dest[4096];
    proton_cli_join_path(child_src, sizeof(child_src), src, data.cFileName);
    proton_cli_join_path(child_dest, sizeof(child_dest), dest, data.cFileName);
    if (proton_cli_copy_tree_impl(child_src, child_dest) != 0) {
      FindClose(handle);
      return -1;
    }
  } while (FindNextFileA(handle, &data));
  FindClose(handle);
#else
  DIR *dir = opendir(src);
  if (dir == NULL) {
    proton_cli_set_error(NULL);
    return -1;
  }
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    char child_src[4096];
    char child_dest[4096];
    proton_cli_join_path(child_src, sizeof(child_src), src, entry->d_name);
    proton_cli_join_path(child_dest, sizeof(child_dest), dest, entry->d_name);
    if (proton_cli_copy_tree_impl(child_src, child_dest) != 0) {
      closedir(dir);
      return -1;
    }
  }
  closedir(dir);
#endif
  return 0;
}

MOONBIT_FFI_EXPORT int32_t proton_cli_copy_tree(moonbit_bytes_t src, moonbit_bytes_t dest) {
  return proton_cli_copy_tree_impl((const char *)src, (const char *)dest);
}

static int proton_cli_remove_tree_impl(const char *path) {
  if (proton_cli_is_file(path)) {
    if (remove(path) != 0) {
      proton_cli_set_error(NULL);
      return -1;
    }
    return 0;
  }
  if (!proton_cli_is_dir(path)) {
    return 0;
  }
#ifdef _WIN32
  char pattern[4096];
  WIN32_FIND_DATAA data;
  HANDLE handle;
  proton_cli_join_path(pattern, sizeof(pattern), path, "*");
  handle = FindFirstFileA(pattern, &data);
  if (handle != INVALID_HANDLE_VALUE) {
    do {
      if (strcmp(data.cFileName, ".") == 0 || strcmp(data.cFileName, "..") == 0) {
        continue;
      }
      char child[4096];
      proton_cli_join_path(child, sizeof(child), path, data.cFileName);
      if (proton_cli_remove_tree_impl(child) != 0) {
        FindClose(handle);
        return -1;
      }
    } while (FindNextFileA(handle, &data));
    FindClose(handle);
  }
  if (_rmdir(path) != 0) {
#else
  DIR *dir = opendir(path);
  if (dir != NULL) {
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
      if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
        continue;
      }
      char child[4096];
      proton_cli_join_path(child, sizeof(child), path, entry->d_name);
      if (proton_cli_remove_tree_impl(child) != 0) {
        closedir(dir);
        return -1;
      }
    }
    closedir(dir);
  }
  if (rmdir(path) != 0) {
#endif
    proton_cli_set_error(NULL);
    return -1;
  }
  return 0;
}

MOONBIT_FFI_EXPORT int32_t proton_cli_remove_tree(moonbit_bytes_t path) {
  return proton_cli_remove_tree_impl((const char *)path);
}

#ifdef __cplusplus
}
#endif
