#include "proton_update.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
#include <errno.h>
#include <mach-o/dyld.h>
#include <dirent.h>
#include <fcntl.h>
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

static void proton_update_set_message(char *error, int32_t error_len,
                                      const char *message) {
  if (error == NULL || error_len <= 0) {
    return;
  }
  snprintf(error, (size_t)error_len, "%s", message != NULL ? message : "");
}

void proton_update_set_current_bundle_for_testing(const char *path) {
  if (path == NULL) {
    proton_update_override[0] = '\0';
    return;
  }
  snprintf(proton_update_override, sizeof(proton_update_override), "%s", path);
}

const char *proton_update_previous_bundle_path(void) {
  return proton_update_previous;
}

#if !defined(__APPLE__)

PROTON_API int32_t proton_update_expand(const char *archive, int32_t archive_len,
                                        const char *parent_dir,
                                        char *bundle_buffer,
                                        int32_t bundle_buffer_len, char *error,
                                        int32_t error_len) {
  (void)archive;
  (void)archive_len;
  (void)parent_dir;
  if (bundle_buffer != NULL && bundle_buffer_len > 0) {
    bundle_buffer[0] = '\0';
  }
  proton_update_set_message(error, error_len,
                            "expanding an update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_stage(const char *staged_bundle_path,
                                       char *error, int32_t error_len) {
  (void)staged_bundle_path;
  proton_update_set_message(
      error, error_len,
      "applying an update is implemented on macOS only; other platforms need "
      "an installer to replace");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_apply(char *error, int32_t error_len) {
  proton_update_set_message(error, error_len,
                            "applying an update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_relaunch(char *error, int32_t error_len) {
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
    /* A path that does not fit is not reported as a shorter path that exists:
       truncation here would hand back a directory nobody asked to install. */
    if (strlen(candidate) >= out_len) {
      closedir(handle);
      return 0;
    }
    snprintf(out, out_len, "%s", candidate);
  }
  closedir(handle);
  return found == 1;
}

/* Removes a directory tree this file created.

   Only ever called on a path mkdtemp returned below, so what it deletes is
   something this process made and owns exclusively. */
static void proton_update_remove_tree(const char *directory) {
  char *const argv[] = {"/bin/rm", "-rf", (char *)directory, NULL};
  (void)proton_update_run(argv);
}

/* Writes the archive into the staging directory.

   O_EXCL because that directory was just created empty: anything already at
   this name would mean the directory is not what it is assumed to be. */
static int proton_update_write_archive(const char *path, const char *archive,
                                       int32_t archive_len) {
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR);
  if (fd < 0) {
    return 0;
  }
  int32_t written = 0;
  while (written < archive_len) {
    ssize_t chunk =
        write(fd, archive + written, (size_t)(archive_len - written));
    if (chunk <= 0) {
      if (chunk < 0 && errno == EINTR) {
        continue;
      }
      close(fd);
      return 0;
    }
    written += (int32_t)chunk;
  }
  return close(fd) == 0;
}

PROTON_API int32_t proton_update_expand(const char *archive, int32_t archive_len,
                                        const char *parent_dir,
                                        char *bundle_buffer,
                                        int32_t bundle_buffer_len, char *error,
                                        int32_t error_len) {
  if (bundle_buffer != NULL && bundle_buffer_len > 0) {
    bundle_buffer[0] = '\0';
  }
  if (parent_dir == NULL || parent_dir[0] != '/') {
    proton_update_set_message(error, error_len,
                              "the staging parent directory must be absolute");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (archive == NULL || archive_len <= 0) {
    proton_update_set_message(error, error_len, "the update archive is empty");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (bundle_buffer == NULL || bundle_buffer_len <= 0) {
    proton_update_set_message(error, error_len,
                              "a buffer for the expanded bundle is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  /* mkdtemp rather than a directory the caller names. It creates a private
     0700 directory under a name that cannot already be taken, in one step, so
     there is no gap between deciding a path is free and claiming it. A caller
     cannot do this for itself: it would have to invent a unique name and then
     race everything else on the machine to it. */
  char staging[PROTON_UPDATE_MAX_PATH];
  int written =
      snprintf(staging, sizeof(staging), "%s/proton-update-XXXXXX", parent_dir);
  if (written < 0 || (size_t)written >= sizeof(staging)) {
    proton_update_set_message(error, error_len,
                              "the staging directory path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (mkdtemp(staging) == NULL) {
    proton_update_set_message(error, error_len,
                              "the staging directory could not be created");
    return PROTON_ERR_PLATFORM;
  }

  /* The archive arrives as bytes rather than as a path. Verified bytes handed
     to `ditto` by name could be replaced between the check and the read, which
     would spend the signature check on one archive and install another. Here
     they are only ever written inside a directory nobody else can write. */
  char archive_path[PROTON_UPDATE_MAX_PATH];
  written =
      snprintf(archive_path, sizeof(archive_path), "%s/update.zip", staging);
  if (written < 0 || (size_t)written >= sizeof(archive_path)) {
    proton_update_remove_tree(staging);
    proton_update_set_message(error, error_len,
                              "the staging directory path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (!proton_update_write_archive(archive_path, archive, archive_len)) {
    proton_update_remove_tree(staging);
    proton_update_set_message(error, error_len,
                              "the update archive could not be written");
    return PROTON_ERR_PLATFORM;
  }

  /* `ditto` rather than an unzip implementation written here: a macOS bundle
     carries resource forks, symlinks and extended attributes that a plain
     extractor drops, and a bundle that loses them fails its code signature. */
  char *const argv[] = {"/usr/bin/ditto", "-x", "-k", archive_path, staging,
                        NULL};
  if (!proton_update_run(argv)) {
    proton_update_remove_tree(staging);
    proton_update_set_message(error, error_len,
                              "the update archive could not be expanded");
    return PROTON_ERR_PLATFORM;
  }
  /* The archive has done its job. Removing it keeps one copy of the
     application on disk rather than two, and leaves the staging directory
     empty once the bundle is moved out of it. */
  (void)unlink(archive_path);

  if (!proton_update_find_bundle(staging, bundle_buffer,
                                 (size_t)bundle_buffer_len)) {
    proton_update_remove_tree(staging);
    proton_update_set_message(
        error, error_len,
        "the update archive does not contain exactly one .app bundle");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage(const char *staged_bundle_path,
                                       char *error, int32_t error_len) {
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

PROTON_API int32_t proton_update_apply(char *error, int32_t error_len) {
  if (proton_update_staged[0] == '\0' || proton_update_current[0] == '\0') {
    proton_update_set_message(error, error_len,
                              "no staged bundle has been accepted");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char previous[PROTON_UPDATE_MAX_PATH];
  int written = snprintf(previous, sizeof(previous), "%s.previous-XXXXXX",
                         proton_update_current);
  if (written < 0 || (size_t)written >= sizeof(previous)) {
    proton_update_set_message(error, error_len,
                              "the replaced bundle path is too long");
    return PROTON_ERR_PLATFORM;
  }
  /* mkdtemp, not a name built from the process id: a second update in the same
     process would reuse that name, and renaming a directory onto a non-empty
     one fails. Here the name is reserved atomically, and because what it
     reserves is an empty directory, the reservation doubles as the
     destination — renaming onto an empty directory replaces it. */
  if (mkdtemp(previous) == NULL) {
    proton_update_set_message(error, error_len,
                              "cannot reserve a place for the replaced "
                              "application");
    return PROTON_ERR_PLATFORM;
  }

  /* Two renames on one volume. A crash before the first leaves the old
     application in place; a crash after the second leaves the new one. The
     only window is between them, and it is closed by moving the old bundle
     back. Nothing ever observes a half-written bundle, because neither rename
     copies anything. */
  if (rename(proton_update_current, previous) != 0) {
    (void)rmdir(previous);
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

  /* The directory the bundle came out of is now empty, so plain rmdir removes
     it and does nothing at all if it holds anything unexpected. That is why it
     is rmdir and not a recursive delete: `stage` accepts any bundle path, and
     this must never remove a directory whose contents it did not put there. */
  char *slash = strrchr(proton_update_staged, '/');
  if (slash != NULL && slash != proton_update_staged) {
    *slash = '\0';
    (void)rmdir(proton_update_staged);
  }
  proton_update_staged[0] = '\0';
  return PROTON_OK;
}

PROTON_API int32_t proton_update_relaunch(char *error, int32_t error_len) {
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
