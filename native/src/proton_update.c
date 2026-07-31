#include "proton_update.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
#include <errno.h>
#include <mach-o/dyld.h>
#include <dirent.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
extern char **environ;
#endif

#define PROTON_UPDATE_MAX_PATH 4096

static char proton_update_staged[PROTON_UPDATE_MAX_PATH];
static char proton_update_current[PROTON_UPDATE_MAX_PATH];
static char proton_update_previous[PROTON_UPDATE_MAX_PATH];
static char proton_update_override[PROTON_UPDATE_MAX_PATH];

static void proton_update_set_message(char *error, size_t error_len,
                                      const char *message) {
  if (error == NULL || error_len == 0) {
    return;
  }
  snprintf(error, error_len, "%s", message != NULL ? message : "");
}

PROTON_API void proton_update_set_current_bundle_for_testing(const char *path) {
  if (path == NULL) {
    proton_update_override[0] = '\0';
    return;
  }
  snprintf(proton_update_override, sizeof(proton_update_override), "%s", path);
}

PROTON_API const char *proton_update_previous_bundle_path(void) {
  return proton_update_previous;
}

#if !defined(__APPLE__)

PROTON_API int32_t proton_update_expand(const char *archive_path,
                                       const char *destination_dir,
                                       char *bundle_out, size_t bundle_out_len,
                                       char *error, size_t error_len) {
  (void)archive_path;
  (void)destination_dir;
  if (bundle_out != NULL && bundle_out_len > 0) {
    bundle_out[0] = '\0';
  }
  proton_update_set_message(error, error_len,
                            "expanding an update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_stage(const char *staged_bundle_path, char *error,
                                 size_t error_len) {
  (void)staged_bundle_path;
  proton_update_set_message(
      error, error_len,
      "applying an update is implemented on macOS only; other platforms need "
      "an installer to replace");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_apply(char *error, size_t error_len) {
  proton_update_set_message(error, error_len,
                            "applying an update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_relaunch(char *error, size_t error_len) {
  proton_update_set_message(error, error_len,
                            "applying an update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

#else

/* Returns the `.app` directory containing the running executable.

   A macOS bundle puts the executable at `<name>.app/Contents/MacOS/<exe>`, so
   the bundle is three components up. An executable that is not in that layout
   has no bundle to replace, and saying so is better than guessing at one. */
static int proton_update_running_bundle(char *out, size_t out_len) {
  if (proton_update_override[0] != '\0') {
    snprintf(out, out_len, "%s", proton_update_override);
    return 1;
  }
  char executable[PROTON_UPDATE_MAX_PATH];
  uint32_t size = (uint32_t)sizeof(executable);
  if (_NSGetExecutablePath(executable, &size) != 0) {
    return 0;
  }
  char resolved[PROTON_UPDATE_MAX_PATH];
  if (realpath(executable, resolved) == NULL) {
    return 0;
  }
  for (int level = 0; level < 3; level++) {
    char *slash = strrchr(resolved, '/');
    if (slash == NULL || slash == resolved) {
      return 0;
    }
    *slash = '\0';
  }
  size_t length = strlen(resolved);
  if (length < 4 || strcmp(resolved + length - 4, ".app") != 0) {
    return 0;
  }
  snprintf(out, out_len, "%s", resolved);
  return 1;
}

static int proton_update_is_directory(const char *path) {
  struct stat info;
  return lstat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static int proton_update_has_suffix(const char *value, const char *suffix) {
  size_t value_len = strlen(value);
  size_t suffix_len = strlen(suffix);
  return value_len >= suffix_len &&
         strcmp(value + value_len - suffix_len, suffix) == 0;
}

/* Runs a command to completion and reports whether it succeeded. */
static int proton_update_run(char *const argv[]) {
  pid_t child = 0;
  if (posix_spawn(&child, argv[0], NULL, NULL, argv, environ) != 0) {
    return 0;
  }
  int status = 0;
  if (waitpid(child, &status, 0) != child) {
    return 0;
  }
  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

/* Returns the single `.app` directory directly inside a directory.

   Exactly one is required. An archive containing several bundles does not say
   which one to install, and picking the first would make that choice silently.
*/
static int proton_update_find_bundle(const char *directory, char *out,
                                     size_t out_len) {
  DIR *handle = opendir(directory);
  if (handle == NULL) {
    return 0;
  }
  int found = 0;
  struct dirent *entry = NULL;
  while ((entry = readdir(handle)) != NULL) {
    if (entry->d_name[0] == '.') {
      continue;
    }
    if (!proton_update_has_suffix(entry->d_name, ".app")) {
      continue;
    }
    char candidate[PROTON_UPDATE_MAX_PATH];
    int written = snprintf(candidate, sizeof(candidate), "%s/%s", directory,
                           entry->d_name);
    if (written < 0 || (size_t)written >= sizeof(candidate)) {
      continue;
    }
    if (!proton_update_is_directory(candidate)) {
      continue;
    }
    found++;
    if (found > 1) {
      break;
    }
    snprintf(out, out_len, "%s", candidate);
  }
  closedir(handle);
  return found == 1;
}

PROTON_API int32_t proton_update_expand(const char *archive_path,
                                       const char *destination_dir,
                                       char *bundle_out, size_t bundle_out_len,
                                       char *error, size_t error_len) {
  if (bundle_out != NULL && bundle_out_len > 0) {
    bundle_out[0] = '\0';
  }
  if (archive_path == NULL || archive_path[0] != '/' ||
      destination_dir == NULL || destination_dir[0] != '/') {
    proton_update_set_message(error, error_len,
                              "archive and destination paths must be absolute");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (bundle_out == NULL || bundle_out_len == 0) {
    proton_update_set_message(error, error_len,
                              "a buffer for the expanded bundle is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* The destination is created here rather than reused, and private to this
     user. An expansion into a directory someone else can write is an
     expansion someone else can replace between unpacking and installing. */
  if (mkdir(destination_dir, S_IRWXU) != 0) {
    proton_update_set_message(error, error_len,
                              "the expansion directory could not be created");
    return PROTON_ERR_PLATFORM;
  }
  struct stat info;
  if (lstat(destination_dir, &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != geteuid() ||
      (info.st_mode & (S_IRWXG | S_IRWXO)) != 0) {
    proton_update_set_message(
        error, error_len,
        "the expansion directory is not private to the current user");
    return PROTON_ERR_PLATFORM;
  }
  /* `ditto` rather than an unzip implementation written here: a macOS bundle
     carries resource forks, symlinks and extended attributes that a plain
     extractor drops, and a bundle that loses them fails its code signature. */
  char *const argv[] = {"/usr/bin/ditto", "-x", "-k", (char *)archive_path,
                        (char *)destination_dir, NULL};
  if (!proton_update_run(argv)) {
    proton_update_set_message(error, error_len,
                              "the update archive could not be expanded");
    return PROTON_ERR_PLATFORM;
  }
  if (!proton_update_find_bundle(destination_dir, bundle_out, bundle_out_len)) {
    proton_update_set_message(
        error, error_len,
        "the update archive does not contain exactly one .app bundle");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage(const char *staged_bundle_path, char *error,
                                 size_t error_len) {
  proton_update_staged[0] = '\0';
  proton_update_current[0] = '\0';
  if (staged_bundle_path == NULL || staged_bundle_path[0] != '/') {
    proton_update_set_message(error, error_len,
                              "the staged bundle path must be absolute");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (strlen(staged_bundle_path) >= PROTON_UPDATE_MAX_PATH) {
    proton_update_set_message(error, error_len,
                              "the staged bundle path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_update_has_suffix(staged_bundle_path, ".app")) {
    proton_update_set_message(error, error_len,
                              "the staged bundle must be a .app directory");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* lstat, not stat: a symlink pointing at a .app is not a bundle this code
     will install, because what it points at can change after the check. */
  if (!proton_update_is_directory(staged_bundle_path)) {
    proton_update_set_message(error, error_len,
                              "the staged bundle is not a directory");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char executable_dir[PROTON_UPDATE_MAX_PATH];
  snprintf(executable_dir, sizeof(executable_dir), "%s/Contents/MacOS",
           staged_bundle_path);
  if (!proton_update_is_directory(executable_dir)) {
    proton_update_set_message(
        error, error_len,
        "the staged bundle has no Contents/MacOS directory");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char current[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_running_bundle(current, sizeof(current))) {
    proton_update_set_message(
        error, error_len,
        "the running executable is not inside a .app bundle, so there is "
        "nothing to replace");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (strcmp(current, staged_bundle_path) == 0) {
    proton_update_set_message(error, error_len,
                              "the staged bundle is the running bundle");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  snprintf(proton_update_staged, sizeof(proton_update_staged), "%s",
           staged_bundle_path);
  snprintf(proton_update_current, sizeof(proton_update_current), "%s", current);
  return PROTON_OK;
}

PROTON_API int32_t proton_update_apply(char *error, size_t error_len) {
  if (proton_update_staged[0] == '\0' || proton_update_current[0] == '\0') {
    proton_update_set_message(error, error_len,
                              "no staged bundle has been accepted");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char previous[PROTON_UPDATE_MAX_PATH];
  int written = snprintf(previous, sizeof(previous), "%s.previous-%ld",
                         proton_update_current, (long)getpid());
  if (written < 0 || (size_t)written >= sizeof(previous)) {
    proton_update_set_message(error, error_len,
                              "the replaced bundle path is too long");
    return PROTON_ERR_PLATFORM;
  }

  /* Two renames on one volume. A crash before the first leaves the old
     application in place; a crash after the second leaves the new one. The
     only window is between them, and it is closed by moving the old bundle
     back. Nothing ever observes a half-written bundle, because neither rename
     copies anything. */
  if (rename(proton_update_current, previous) != 0) {
    proton_update_set_message(error, error_len,
                              "cannot move the installed application aside");
    return PROTON_ERR_PLATFORM;
  }
  if (rename(proton_update_staged, proton_update_current) != 0) {
    if (rename(previous, proton_update_current) != 0) {
      proton_update_set_message(
          error, error_len,
          "the update could not be installed and the previous application "
          "could not be restored; it remains beside the install location");
      return PROTON_ERR_PLATFORM;
    }
    proton_update_set_message(error, error_len,
                              "cannot move the staged application into place");
    return PROTON_ERR_PLATFORM;
  }

  /* The previous bundle is kept rather than deleted. Until the replacement has
     started once there is no evidence it works, and a copy that can be moved
     back by hand is the difference between a bad release and an unusable
     install. */
  snprintf(proton_update_previous, sizeof(proton_update_previous), "%s",
           previous);
  return PROTON_OK;
}

PROTON_API int32_t proton_update_relaunch(char *error, size_t error_len) {
  if (proton_update_current[0] == '\0') {
    proton_update_set_message(error, error_len,
                              "no application has been replaced");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* `open -n` asks Launch Services to start a new instance, which gives the
     replacement a clean session rather than one inherited from the process
     that is about to exit. */
  char *const argv[] = {"/usr/bin/open", "-n", proton_update_current, NULL};
  pid_t child = 0;
  if (posix_spawn(&child, "/usr/bin/open", NULL, NULL, argv, environ) != 0) {
    proton_update_set_message(error, error_len,
                              "cannot start the replaced application");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

#endif
