#include "proton_update.h"

#include "proton_handle.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Install-medium detection probes the filesystem, so this is needed on every
   Unix, not just the platform that implements an apply path. */
#if !defined(_WIN32)
#include <unistd.h>
#endif

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <errno.h>
#include <fts.h>
#include <mach-o/dyld.h>
#include <dirent.h>
#include <fcntl.h>
#include <pthread.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
extern char **environ;
#endif

#define PROTON_UPDATE_MAX_PATH 4096

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

/* An application may only replace an installation it owns.

   A Flatpak or Snap image is mounted read-only and is updated by the system,
   so there is nothing an apply path could write. A distribution package is
   owned by dpkg or rpm, and replacing its files behind the package manager
   leaves the two disagreeing about what is installed — the failure surfaces
   later, as a downgrade on the next system upgrade. Only an AppImage is a
   single file the user owns, which is why it is the one self-updatable Linux
   medium. Tauri draws the same line.

   macOS and Windows have a single supported shape each — a bundle and an
   installed tree — so detection only has work to do on Linux. */
typedef enum {
  PROTON_UPDATE_MEDIUM_OWNED = 0,
  PROTON_UPDATE_MEDIUM_APPIMAGE,
  PROTON_UPDATE_MEDIUM_FLATPAK,
  PROTON_UPDATE_MEDIUM_SNAP,
  PROTON_UPDATE_MEDIUM_SYSTEM_PACKAGE,
} proton_update_medium_t;

static char proton_update_medium_override[32];

void proton_update_set_medium_for_testing(const char *medium) {
  if (medium == NULL) {
    proton_update_medium_override[0] = '\0';
    return;
  }
  snprintf(proton_update_medium_override,
           sizeof(proton_update_medium_override), "%s", medium);
}

static int proton_update_env_is_set(const char *name) {
  const char *value = getenv(name);
  return value != NULL && value[0] != '\0';
}

static proton_update_medium_t proton_update_detect_medium(void) {
  if (proton_update_medium_override[0] != '\0') {
    const char *value = proton_update_medium_override;
    if (strcmp(value, "appimage") == 0) {
      return PROTON_UPDATE_MEDIUM_APPIMAGE;
    }
    if (strcmp(value, "flatpak") == 0) {
      return PROTON_UPDATE_MEDIUM_FLATPAK;
    }
    if (strcmp(value, "snap") == 0) {
      return PROTON_UPDATE_MEDIUM_SNAP;
    }
    if (strcmp(value, "package") == 0) {
      return PROTON_UPDATE_MEDIUM_SYSTEM_PACKAGE;
    }
    return PROTON_UPDATE_MEDIUM_OWNED;
  }
#if defined(__linux__)
  /* Ordered most specific first: a Flatpak or Snap can also carry an
     unrelated APPIMAGE value inherited from whatever launched it. */
  if (access("/.flatpak-info", F_OK) == 0) {
    return PROTON_UPDATE_MEDIUM_FLATPAK;
  }
  if (proton_update_env_is_set("SNAP")) {
    return PROTON_UPDATE_MEDIUM_SNAP;
  }
  if (proton_update_env_is_set("APPIMAGE")) {
    return PROTON_UPDATE_MEDIUM_APPIMAGE;
  }
  /* Anything else on Linux is either package-managed or a development tree.
     Declining is the safe default in both cases: there is nothing an update
     could correctly replace. */
  return PROTON_UPDATE_MEDIUM_SYSTEM_PACKAGE;
#else
  return PROTON_UPDATE_MEDIUM_OWNED;
#endif
}

static const char *proton_update_medium_message(
    proton_update_medium_t medium) {
  switch (medium) {
  case PROTON_UPDATE_MEDIUM_FLATPAK:
    return "this application is installed as a Flatpak; updates are applied "
           "by the Flatpak client, not by the application";
  case PROTON_UPDATE_MEDIUM_SNAP:
    return "this application is installed as a Snap; updates are applied by "
           "snapd, not by the application";
  case PROTON_UPDATE_MEDIUM_SYSTEM_PACKAGE:
    return "this application was not installed as an AppImage; updates are "
           "applied by whichever package manager installed it";
  default:
    return "";
  }
}

/* Fails the apply path when the running installation is not ours to replace.
   Checked before any bytes are downloaded or staged, so a managed install
   reports the reason instead of doing throwaway work. */
static int32_t proton_update_require_owned_medium(char *error,
                                                  int32_t error_len) {
  proton_update_medium_t medium = proton_update_detect_medium();
  if (medium == PROTON_UPDATE_MEDIUM_OWNED ||
      medium == PROTON_UPDATE_MEDIUM_APPIMAGE) {
    return PROTON_OK;
  }
  proton_update_set_message(error, error_len,
                            proton_update_medium_message(medium));
  return PROTON_ERR_UNSUPPORTED;
}

/* Windows and Linux have no apply path yet.

   Sharing one with macOS means lifting the staging machinery — the handle
   table, the private same-volume directory, the chunked write — out of the
   block below, because it solves the same problem everywhere and only the
   meaning of "install" differs: a bundle swap checked against a code
   signature, versus replacing the single AppImage file the user owns. That
   move is the bulk of the remaining work, and it is not started here. */
#if !defined(__APPLE__)

PROTON_API int32_t proton_update_stage_begin_revision(
    const char *parent_dir, int64_t expected_size, uint64_t target_revision,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len) {
  (void)parent_dir;
  (void)expected_size;
  (void)target_revision;
  if (out_stage != NULL) {
    *out_stage = PROTON_INVALID_HANDLE;
  }
  /* Checked even without an apply path. A Flatpak or Snap install would never
     gain one, so naming the mechanism that does own the update is a better
     answer than reporting the platform as unfinished. */
  int32_t medium_status = proton_update_require_owned_medium(error, error_len);
  if (medium_status != PROTON_OK) {
    return medium_status;
  }
  proton_update_set_message(
      error, error_len,
      "streaming update staging is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_stage_begin(
    const char *parent_dir, int64_t expected_size,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len) {
  return proton_update_stage_begin_revision(parent_dir, expected_size, 0,
                                            out_stage, error, error_len);
}

PROTON_API int32_t proton_update_stage_write(
    proton_update_stage_id_t stage, const char *chunk, int32_t chunk_len,
    char *error, int32_t error_len) {
  (void)stage;
  (void)chunk;
  (void)chunk_len;
  proton_update_set_message(
      error, error_len,
      "streaming update staging is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_stage_install_outcome(
    proton_update_stage_id_t stage, int32_t *out_outcome, char *error,
    int32_t error_len) {
  (void)stage;
  if (out_outcome != NULL) {
    *out_outcome = PROTON_UPDATE_INSTALLED;
  }
  proton_update_set_message(
      error, error_len,
      "applying a staged update is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_stage_install(
    proton_update_stage_id_t stage, char *error, int32_t error_len) {
  int32_t outcome = PROTON_UPDATE_INSTALLED;
  return proton_update_stage_install_outcome(stage, &outcome, error, error_len);
}

PROTON_API int32_t proton_update_current_revision(
    uint64_t *out_revision, char *error, int32_t error_len) {
  if (out_revision != NULL) {
    *out_revision = 0;
  }
  proton_update_set_message(
      error, error_len,
      "reading an application update revision is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_cleanup_previous(char *error,
                                                  int32_t error_len) {
  (void)error;
  (void)error_len;
  /* Cleanup is tied to the macOS bundle-swap apply path. Until another
     platform has an apply implementation, it has no retained artifact for
     this operation to remove. */
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage_abort(
    proton_update_stage_id_t stage, char *error, int32_t error_len) {
  (void)stage;
  proton_update_set_message(
      error, error_len,
      "streaming update staging is implemented on macOS only");
  return PROTON_ERR_UNSUPPORTED;
}

PROTON_API int32_t proton_update_install(const char *archive,
                                         int32_t archive_len,
                                         const char *parent_dir, char *error,
                                         int32_t error_len) {
  (void)archive;
  (void)archive_len;
  (void)parent_dir;
  proton_update_set_message(
      error, error_len,
      "applying an update is implemented on macOS only; the nsis and appimage "
      "package targets now produce what the other platforms will replace");
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

static int proton_update_parent_path(const char *path, char *out,
                                     size_t out_len) {
  const char *slash = strrchr(path, '/');
  if (slash == NULL) {
    return 0;
  }
  size_t length = slash == path ? 1 : (size_t)(slash - path);
  if (length >= out_len) {
    return 0;
  }
  memcpy(out, path, length);
  out[length] = '\0';
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

/* Removes one physical directory tree without following symlinks or crossing
   into another filesystem. Staging paths come directly from mkdtemp; retained
   bundle paths pass the reserved-name, signature, and revision checks below
   before reaching this function. */
static int proton_update_remove_tree(const char *directory) {
  char *paths[] = {(char *)directory, NULL};
  FTS *tree = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
  if (tree == NULL) {
    return 0;
  }
  int ok = 1;
  FTSENT *entry = NULL;
  while ((entry = fts_read(tree)) != NULL) {
    switch (entry->fts_info) {
    case FTS_D:
      break;
    case FTS_DP:
      if (rmdir(entry->fts_accpath) != 0) {
        ok = 0;
      }
      break;
    case FTS_F:
    case FTS_SL:
    case FTS_SLNONE:
    case FTS_DEFAULT:
      if (unlink(entry->fts_accpath) != 0) {
        ok = 0;
      }
      break;
    default:
      ok = 0;
      break;
    }
  }
  if (fts_close(tree) != 0) {
    ok = 0;
  }
  return ok;
}

#define PROTON_UPDATE_MAX_STAGES 8
typedef struct {
  uint32_t generation;
  int occupied;
  int destroyed;
  pthread_t owner_thread;
  int fd;
  int64_t expected_size;
  int64_t written_size;
  uint64_t target_revision;
  char staging[PROTON_UPDATE_MAX_PATH];
  char archive_path[PROTON_UPDATE_MAX_PATH];
} proton_update_stage_slot_t;

static proton_update_stage_slot_t
    g_update_stages[PROTON_UPDATE_MAX_STAGES];
static pthread_mutex_t g_update_stage_mutex = PTHREAD_MUTEX_INITIALIZER;

static proton_update_stage_id_t proton_update_make_stage_handle(
    uint32_t generation, uint32_t index) {
  uint64_t raw =
      proton_make_handle(PROTON_HANDLE_TYPE_UPDATE_STAGE, generation, index);
  return (proton_update_stage_id_t)raw;
}

static void proton_update_stage_release(proton_update_stage_slot_t *slot,
                                        int remove_staging) {
  if (slot->fd >= 0) {
    (void)close(slot->fd);
    slot->fd = -1;
  }
  if (remove_staging && slot->staging[0] != '\0') {
    (void)proton_update_remove_tree(slot->staging);
  }
  pthread_mutex_lock(&g_update_stage_mutex);
  slot->staging[0] = '\0';
  slot->archive_path[0] = '\0';
  slot->destroyed = 1;
  slot->expected_size = 0;
  slot->written_size = 0;
  slot->target_revision = 0;
  pthread_mutex_unlock(&g_update_stage_mutex);
}

static int32_t proton_update_get_stage(proton_update_stage_id_t handle,
                                       proton_update_stage_slot_t **out_slot,
                                       char *error, int32_t error_len) {
  uint64_t raw = (uint64_t)handle;
  pthread_mutex_lock(&g_update_stage_mutex);
  if (handle == PROTON_INVALID_HANDLE ||
      proton_handle_type(raw) != PROTON_HANDLE_TYPE_UPDATE_STAGE) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage handle is invalid");
    return PROTON_ERR_INVALID_HANDLE;
  }
  uint32_t index = proton_handle_index(raw);
  uint32_t generation = proton_handle_generation(raw);
  if (index >= PROTON_UPDATE_MAX_STAGES) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage handle is out of range");
    return PROTON_ERR_INVALID_HANDLE;
  }
  proton_update_stage_slot_t *slot = &g_update_stages[index];
  if (!slot->occupied || slot->generation != generation) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage handle is stale");
    return PROTON_ERR_INVALID_HANDLE;
  }
  if (slot->destroyed) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage is already closed");
    return PROTON_ERR_DESTROYED;
  }
  if (pthread_equal(slot->owner_thread, pthread_self()) == 0) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage belongs to another thread");
    return PROTON_ERR_WRONG_THREAD;
  }
  *out_slot = slot;
  pthread_mutex_unlock(&g_update_stage_mutex);
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage_begin_revision(
    const char *parent_dir, int64_t expected_size, uint64_t target_revision,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len) {
  if (out_stage != NULL) {
    *out_stage = PROTON_INVALID_HANDLE;
  }
  /* Before anything is downloaded: a managed installation reports why rather
     than staging bytes it could never install. */
  int32_t medium_status = proton_update_require_owned_medium(error, error_len);
  if (medium_status != PROTON_OK) {
    return medium_status;
  }
  if (parent_dir != NULL && parent_dir[0] != '\0' && parent_dir[0] != '/') {
    proton_update_set_message(error, error_len,
                              "the staging parent directory must be absolute");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char current_bundle[PROTON_UPDATE_MAX_PATH];
  char current_parent[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_running_bundle(current_bundle, sizeof(current_bundle)) ||
      !proton_update_parent_path(current_bundle, current_parent,
                                 sizeof(current_parent))) {
    proton_update_set_message(
        error, error_len,
        "the running executable is not inside a .app bundle, so a "
        "same-volume update stage cannot be created");
    return PROTON_ERR_PLATFORM;
  }
  if (parent_dir == NULL || parent_dir[0] == '\0') {
    parent_dir = current_parent;
  } else {
    struct stat parent_info;
    struct stat current_parent_info;
    if (stat(parent_dir, &parent_info) != 0 ||
        stat(current_parent, &current_parent_info) != 0) {
      proton_update_set_message(
          error, error_len,
          "the staging parent filesystem could not be inspected");
      return PROTON_ERR_PLATFORM;
    }
    if (parent_info.st_dev != current_parent_info.st_dev) {
      proton_update_set_message(
          error, error_len,
          "the staging parent must be on the running application's filesystem");
      return PROTON_ERR_INVALID_ARGUMENT;
    }
  }
  if (expected_size <= 0) {
    proton_update_set_message(error, error_len,
                              "the expected update size must be positive");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (out_stage == NULL) {
    proton_update_set_message(error, error_len,
                              "an update stage output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  proton_update_stage_slot_t *slot = NULL;
  uint32_t index = 0;
  pthread_mutex_lock(&g_update_stage_mutex);
  for (; index < PROTON_UPDATE_MAX_STAGES; index++) {
    proton_update_stage_slot_t *candidate = &g_update_stages[index];
    if (!candidate->occupied || candidate->destroyed) {
      slot = candidate;
      break;
    }
  }
  if (slot == NULL) {
    pthread_mutex_unlock(&g_update_stage_mutex);
    proton_update_set_message(error, error_len,
                              "the update stage registry is full");
    return PROTON_ERR_ENGINE;
  }
  if (slot->generation == 0) {
    slot->generation = 1;
  } else {
    slot->generation = proton_next_handle_generation(slot->generation);
  }
  slot->occupied = 1;
  slot->destroyed = 0;
  slot->owner_thread = pthread_self();
  slot->fd = -1;
  slot->expected_size = expected_size;
  slot->written_size = 0;
  slot->target_revision = target_revision;
  slot->staging[0] = '\0';
  slot->archive_path[0] = '\0';
  pthread_mutex_unlock(&g_update_stage_mutex);

  int written = snprintf(slot->staging, sizeof(slot->staging),
                         "%s/.proton-update-XXXXXX", parent_dir);
  if (written < 0 || (size_t)written >= sizeof(slot->staging)) {
    proton_update_stage_release(slot, 0);
    proton_update_set_message(error, error_len,
                              "the staging directory path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (mkdtemp(slot->staging) == NULL) {
    proton_update_stage_release(slot, 0);
    proton_update_set_message(error, error_len,
                              "the staging directory could not be created");
    return PROTON_ERR_PLATFORM;
  }
  written = snprintf(slot->archive_path, sizeof(slot->archive_path),
                     "%s/update.zip", slot->staging);
  if (written < 0 || (size_t)written >= sizeof(slot->archive_path)) {
    proton_update_stage_release(slot, 1);
    proton_update_set_message(error, error_len,
                              "the staging directory path is too long");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  slot->fd = open(slot->archive_path, O_WRONLY | O_CREAT | O_EXCL,
                  S_IRUSR | S_IWUSR);
  if (slot->fd < 0) {
    proton_update_stage_release(slot, 1);
    proton_update_set_message(error, error_len,
                              "the update archive could not be created");
    return PROTON_ERR_PLATFORM;
  }
  *out_stage = proton_update_make_stage_handle(slot->generation, index);
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage_begin(
    const char *parent_dir, int64_t expected_size,
    proton_update_stage_id_t *out_stage, char *error, int32_t error_len) {
  return proton_update_stage_begin_revision(parent_dir, expected_size, 0,
                                            out_stage, error, error_len);
}

PROTON_API int32_t proton_update_stage_write(
    proton_update_stage_id_t stage, const char *chunk, int32_t chunk_len,
    char *error, int32_t error_len) {
  proton_update_stage_slot_t *slot = NULL;
  int32_t status =
      proton_update_get_stage(stage, &slot, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  if (chunk_len < 0 || (chunk_len > 0 && chunk == NULL)) {
    proton_update_set_message(error, error_len,
                              "the update chunk is invalid");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if ((int64_t)chunk_len > slot->expected_size - slot->written_size) {
    proton_update_set_message(error, error_len,
                              "the update exceeds its signed size");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int32_t written = 0;
  while (written < chunk_len) {
    ssize_t count =
        write(slot->fd, chunk + written, (size_t)(chunk_len - written));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      proton_update_set_message(error, error_len,
                                "the update archive could not be written");
      return PROTON_ERR_PLATFORM;
    }
    written += (int32_t)count;
  }
  slot->written_size += chunk_len;
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage_abort(
    proton_update_stage_id_t stage, char *error, int32_t error_len) {
  proton_update_stage_slot_t *slot = NULL;
  int32_t status =
      proton_update_get_stage(stage, &slot, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  proton_update_stage_release(slot, 1);
  return PROTON_OK;
}

static int32_t proton_update_expand_staged_archive(
    proton_update_stage_slot_t *stage,
    char *bundle_buffer, int32_t bundle_buffer_len, char *error,
    int32_t error_len) {
  if (bundle_buffer != NULL && bundle_buffer_len > 0) {
    bundle_buffer[0] = '\0';
  }
  if (bundle_buffer == NULL || bundle_buffer_len <= 0) {
    proton_update_set_message(error, error_len,
                              "a buffer for the expanded bundle is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  /* `ditto` rather than an unzip implementation written here: a macOS bundle
     carries resource forks, symlinks and extended attributes that a plain
     extractor drops, and a bundle that loses them fails its code signature. */
  char *const argv[] = {"/usr/bin/ditto", "-x", "-k", stage->archive_path,
                        stage->staging, NULL};
  if (!proton_update_run(argv)) {
    proton_update_set_message(error, error_len,
                              "the update archive could not be expanded");
    return PROTON_ERR_PLATFORM;
  }
  /* The archive has done its job. Removing it keeps one copy of the
     application on disk rather than two, and leaves the staging directory
     empty once the bundle is moved out of it. */
  (void)unlink(stage->archive_path);

  if (!proton_update_find_bundle(stage->staging, bundle_buffer,
                                 (size_t)bundle_buffer_len)) {
    proton_update_set_message(
        error, error_len,
        "the update archive does not contain exactly one .app bundle");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

/* The longest signing identifier this compares. Bundle identifiers are
   reverse-DNS names and team identifiers are ten characters; anything past
   this is not a name either side of the comparison would produce. */
#define PROTON_UPDATE_MAX_IDENTITY 256

static SecStaticCodeRef proton_update_static_code(const char *path) {
  CFStringRef text =
      CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  if (text == NULL) {
    return NULL;
  }
  CFURLRef url =
      CFURLCreateWithFileSystemPath(NULL, text, kCFURLPOSIXPathStyle, true);
  CFRelease(text);
  if (url == NULL) {
    return NULL;
  }
  SecStaticCodeRef code = NULL;
  OSStatus status = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
  CFRelease(url);
  if (status != errSecSuccess) {
    return NULL;
  }
  return code;
}

#define PROTON_UPDATE_REVISION_KEY "ProtonUpdateRevision"

/* Reads the revision through CoreFoundation's property-list parser. Keeping it
   as a decimal string in Info.plist preserves the full uint64_t range; plist
   integers and JSON doubles do not provide that guarantee on every reader. */
static int proton_update_bundle_revision(const char *bundle,
                                         int missing_is_zero,
                                         uint64_t *out_revision, char *error,
                                         int32_t error_len) {
  char path[PROTON_UPDATE_MAX_PATH];
  int written = snprintf(path, sizeof(path), "%s/Contents/Info.plist", bundle);
  if (written < 0 || (size_t)written >= sizeof(path)) {
    proton_update_set_message(error, error_len,
                              "the application Info.plist path is too long");
    return 0;
  }
  FILE *file = fopen(path, "rb");
  if (file == NULL || fseek(file, 0, SEEK_END) != 0) {
    if (file != NULL) {
      fclose(file);
    }
    proton_update_set_message(error, error_len,
                              "the application Info.plist cannot be read");
    return 0;
  }
  long length = ftell(file);
  if (length <= 0 || length > 1024 * 1024 || fseek(file, 0, SEEK_SET) != 0) {
    fclose(file);
    proton_update_set_message(error, error_len,
                              "the application Info.plist has an invalid size");
    return 0;
  }
  UInt8 *bytes = malloc((size_t)length);
  if (bytes == NULL || fread(bytes, 1, (size_t)length, file) != (size_t)length) {
    free(bytes);
    fclose(file);
    proton_update_set_message(error, error_len,
                              "the application Info.plist cannot be read");
    return 0;
  }
  fclose(file);
  CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)length);
  free(bytes);
  if (data == NULL) {
    proton_update_set_message(error, error_len,
                              "the application Info.plist cannot be decoded");
    return 0;
  }
  CFErrorRef parse_error = NULL;
  CFPropertyListRef property = CFPropertyListCreateWithData(
      NULL, data, kCFPropertyListImmutable, NULL, &parse_error);
  CFRelease(data);
  if (parse_error != NULL) {
    CFRelease(parse_error);
  }
  if (property == NULL || CFGetTypeID(property) != CFDictionaryGetTypeID()) {
    if (property != NULL) {
      CFRelease(property);
    }
    proton_update_set_message(error, error_len,
                              "the application Info.plist is not a dictionary");
    return 0;
  }
  CFTypeRef raw = CFDictionaryGetValue((CFDictionaryRef)property,
                                       CFSTR(PROTON_UPDATE_REVISION_KEY));
  if (raw == NULL && missing_is_zero) {
    CFRelease(property);
    *out_revision = 0;
    return 1;
  }
  if (raw == NULL || CFGetTypeID(raw) != CFStringGetTypeID()) {
    CFRelease(property);
    proton_update_set_message(
        error, error_len,
        "the application has no valid monotonic update revision");
    return 0;
  }
  char text[32];
  int converted = CFStringGetCString((CFStringRef)raw, text, sizeof(text),
                                     kCFStringEncodingASCII);
  CFRelease(property);
  if (!converted || text[0] == '\0' || text[0] == '-') {
    proton_update_set_message(
        error, error_len,
        "the application has no valid monotonic update revision");
    return 0;
  }
  errno = 0;
  char *end = NULL;
  unsigned long long revision = strtoull(text, &end, 10);
  if (errno == ERANGE || end == text || *end != '\0') {
    proton_update_set_message(
        error, error_len,
        "the application has no valid monotonic update revision");
    return 0;
  }
  *out_revision = (uint64_t)revision;
  return 1;
}

PROTON_API int32_t proton_update_current_revision(
    uint64_t *out_revision, char *error, int32_t error_len) {
  if (out_revision == NULL) {
    proton_update_set_message(error, error_len,
                              "an update revision output is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_revision = 0;
  char current[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_running_bundle(current, sizeof(current))) {
    proton_update_set_message(
        error, error_len,
        "the running executable is not inside a .app bundle, so its update "
        "revision cannot be read");
    return PROTON_ERR_UNSUPPORTED;
  }
  if (!proton_update_bundle_revision(current, 1, out_revision, error,
                                     error_len)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  return PROTON_OK;
}

/* Acquires the one commit lock shared by every process updating this install.

   Downloads and extraction deliberately happen before this point. The lock
   covers only re-reading installed state, deciding monotonicity, and the
   rename transaction, so a slow network cannot block another process. */
static int32_t proton_update_acquire_commit_lock(const char *current,
                                                 int *out_fd, char *error,
                                                 int32_t error_len) {
  char path[PROTON_UPDATE_MAX_PATH];
  int written = snprintf(path, sizeof(path), "%s.proton-update.lock", current);
  if (written < 0 || (size_t)written >= sizeof(path)) {
    proton_update_set_message(error, error_len,
                              "the update commit lock path is too long");
    return PROTON_ERR_PLATFORM;
  }
  int fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR);
  if (fd < 0) {
    proton_update_set_message(error, error_len,
                              "the update commit lock cannot be opened");
    return PROTON_ERR_PLATFORM;
  }
  struct stat info;
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_uid != geteuid()) {
    close(fd);
    proton_update_set_message(error, error_len,
                              "the update commit lock is not a private file");
    return PROTON_ERR_PLATFORM;
  }
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    int lock_error = errno;
    close(fd);
    if (lock_error == EWOULDBLOCK || lock_error == EAGAIN) {
      proton_update_set_message(error, error_len,
                                "another process is installing an update");
      return PROTON_ERR_UPDATE_BUSY;
    }
    proton_update_set_message(error, error_len,
                              "the update commit lock cannot be acquired");
    return PROTON_ERR_PLATFORM;
  }
  *out_fd = fd;
  return PROTON_OK;
}

/* Reads the two names that say who signed a bundle.

   An absent team identifier is not a failure. An ad-hoc signature has none,
   and that is the normal state of an application that has not been through a
   Developer ID release — reporting it as an error would mean refusing to
   update every unreleased build. */
static int proton_update_signing_identity(SecStaticCodeRef code,
                                          char *identifier, char *team) {
  identifier[0] = '\0';
  team[0] = '\0';
  CFDictionaryRef info = NULL;
  if (SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info) !=
          errSecSuccess ||
      info == NULL) {
    return 0;
  }
  int ok = 1;
  CFStringRef value = CFDictionaryGetValue(info, kSecCodeInfoIdentifier);
  if (value == NULL ||
      !CFStringGetCString(value, identifier, PROTON_UPDATE_MAX_IDENTITY,
                          kCFStringEncodingUTF8)) {
    ok = 0;
  }
  value = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
  if (value != NULL && !CFStringGetCString(value, team,
                                           PROTON_UPDATE_MAX_IDENTITY,
                                           kCFStringEncodingUTF8)) {
    ok = 0;
  }
  CFRelease(info);
  return ok;
}

/* Reports whether the staged bundle is intact and is the same application as
   the one it would replace.

   This is the check the archive signature cannot make. That signature covered
   the bytes that were downloaded, and stopped covering anything the moment
   they were expanded into files another process running as this user can
   write. What covers those files is the bundle's own seal.

   Identity is compared as well, because an intact seal only says a bundle was
   not altered — not that it is this application. A validly signed copy of
   something else would pass the first check and fail this one. */
static int proton_update_verify_bundle(const char *staged, const char *installed,
                                       char *error, int32_t error_len) {
  SecStaticCodeRef staged_code = proton_update_static_code(staged);
  if (staged_code == NULL) {
    proton_update_set_message(error, error_len,
                              "the staged bundle cannot be read as an "
                              "application");
    return 0;
  }
  /* Nested code is checked as well as the resource seal. The engine framework
     and helper are signed separately by the packager, so leaving them out
     would exempt the largest part of the bundle from the check. */
  OSStatus status = SecStaticCodeCheckValidity(
      staged_code,
      kSecCSDefaultFlags | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode,
      NULL);
  if (status == errSecCSUnsigned) {
    CFRelease(staged_code);
    proton_update_set_message(error, error_len,
                              "the staged bundle is not signed");
    return 0;
  }
  if (status != errSecSuccess) {
    CFRelease(staged_code);
    /* The status is reported as well as the sentence. Every way a seal can
       fail to cover a bundle reaches this line, and which one it was is the
       difference between a tampered download and a mis-signed release. */
    char detail[192];
    snprintf(detail, sizeof(detail),
             "the staged bundle does not match its code signature (OSStatus "
             "%d)",
             (int)status);
    proton_update_set_message(error, error_len, detail);
    return 0;
  }
  SecStaticCodeRef installed_code = proton_update_static_code(installed);
  if (installed_code == NULL) {
    CFRelease(staged_code);
    proton_update_set_message(
        error, error_len,
        "the installed application has no code signature to compare against");
    return 0;
  }
  char staged_identifier[PROTON_UPDATE_MAX_IDENTITY];
  char staged_team[PROTON_UPDATE_MAX_IDENTITY];
  char installed_identifier[PROTON_UPDATE_MAX_IDENTITY];
  char installed_team[PROTON_UPDATE_MAX_IDENTITY];
  int read = proton_update_signing_identity(staged_code, staged_identifier,
                                            staged_team) &&
             proton_update_signing_identity(installed_code,
                                            installed_identifier,
                                            installed_team);
  CFRelease(staged_code);
  CFRelease(installed_code);
  if (!read) {
    proton_update_set_message(error, error_len,
                              "the signing identity could not be read");
    return 0;
  }
  if (strcmp(staged_identifier, installed_identifier) != 0) {
    proton_update_set_message(
        error, error_len,
        "the staged bundle is signed as a different application");
    return 0;
  }
  /* Both teams absent is a match: two ad-hoc signatures. That is a weaker
     statement than two matching Developer ID teams — an ad-hoc signature
     asserts no identity at all, so this only establishes that the bundle is
     intact and calls itself the same application. An application that ships
     with a Developer ID gets the strong form for free, because then the team
     is present and must be the same one. */
  if (strcmp(staged_team, installed_team) != 0) {
    proton_update_set_message(error, error_len,
                              "the staged bundle is signed by a different team");
    return 0;
  }
  return 1;
}

/* mkdtemp replaces exactly six trailing X characters with letters or digits.
   Requiring that exact shape prevents a broad prefix scan from turning into a
   deletion API for directories the updater did not reserve. */
static int proton_update_is_previous_name(const char *name,
                                          const char *bundle_name) {
  size_t bundle_len = strlen(bundle_name);
  static const char suffix[] = ".previous-";
  size_t prefix_len = bundle_len + sizeof(suffix) - 1;
  if (strlen(name) != prefix_len + 6 ||
      strncmp(name, bundle_name, bundle_len) != 0 ||
      strncmp(name + bundle_len, suffix, sizeof(suffix) - 1) != 0) {
    return 0;
  }
  for (size_t index = prefix_len; index < prefix_len + 6; index++) {
    char value = name[index];
    if (!((value >= 'a' && value <= 'z') ||
          (value >= 'A' && value <= 'Z') ||
          (value >= '0' && value <= '9'))) {
      return 0;
    }
  }
  return 1;
}

PROTON_API int32_t proton_update_cleanup_previous(char *error,
                                                  int32_t error_len) {
  char current[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_running_bundle(current, sizeof(current))) {
    /* Development executables do not run from an application bundle and have
       no retained update artifact. Startup cleanup is intentionally a no-op
       for them. */
    return PROTON_OK;
  }

  uint64_t current_revision = 0;
  if (!proton_update_bundle_revision(current, 1, &current_revision, error,
                                     error_len)) {
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  int lock_fd = -1;
  int32_t status = proton_update_acquire_commit_lock(
      current, &lock_fd, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }

  char parent[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_parent_path(current, parent, sizeof(parent))) {
    close(lock_fd);
    proton_update_set_message(error, error_len,
                              "the application parent path is invalid");
    return PROTON_ERR_PLATFORM;
  }
  const char *bundle_name = strrchr(current, '/');
  bundle_name = bundle_name == NULL ? current : bundle_name + 1;
  struct dirent **entries = NULL;
  int entry_count = scandir(parent, &entries, NULL, alphasort);
  if (entry_count < 0) {
    close(lock_fd);
    proton_update_set_message(
        error, error_len,
        "the application directory cannot be scanned for previous versions");
    return PROTON_ERR_PLATFORM;
  }

  int cleanup_failed = 0;
  for (int index = 0; index < entry_count; index++) {
    const char *name = entries[index]->d_name;
    if (proton_update_is_previous_name(name, bundle_name)) {
      char candidate[PROTON_UPDATE_MAX_PATH];
      int written = snprintf(candidate, sizeof(candidate), "%s/%s", parent,
                             name);
      if (written >= 0 && (size_t)written < sizeof(candidate) &&
          proton_update_is_directory(candidate)) {
        char ignored[512];
        uint64_t candidate_revision = 0;
        if (proton_update_verify_bundle(candidate, current, ignored,
                                        sizeof(ignored)) &&
            proton_update_bundle_revision(candidate, 1, &candidate_revision,
                                          ignored, sizeof(ignored)) &&
            candidate_revision < current_revision &&
            !proton_update_remove_tree(candidate)) {
          cleanup_failed = 1;
        }
      }
    }
    free(entries[index]);
  }
  free(entries);
  close(lock_fd);
  if (cleanup_failed) {
    proton_update_set_message(
        error, error_len,
        "an older application bundle could not be removed");
    return PROTON_ERR_PLATFORM;
  }
  return PROTON_OK;
}

static int32_t proton_update_replace_bundle(const char *staged_bundle_path,
                                            const char *current,
                                            int *preserve_staging, char *error,
                                            int32_t error_len) {
  *preserve_staging = 0;
  char previous[PROTON_UPDATE_MAX_PATH];
  int written = snprintf(previous, sizeof(previous), "%s.previous-XXXXXX",
                         current);
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
  if (rename(current, previous) != 0) {
    (void)rmdir(previous);
    proton_update_set_message(error, error_len,
                              "cannot move the installed application aside");
    return PROTON_ERR_PLATFORM;
  }
  if (rename(staged_bundle_path, current) != 0) {
    if (rename(previous, current) != 0) {
      *preserve_staging = 1;
      snprintf(proton_update_previous, sizeof(proton_update_previous), "%s",
               previous);
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
  snprintf(proton_update_current, sizeof(proton_update_current), "%s", current);
  return PROTON_OK;
}

PROTON_API int32_t proton_update_stage_install_outcome(
    proton_update_stage_id_t stage, int32_t *out_outcome, char *error,
    int32_t error_len) {
  if (out_outcome == NULL) {
    proton_update_set_message(error, error_len,
                              "an update install outcome is required");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  *out_outcome = PROTON_UPDATE_INSTALLED;
  proton_update_stage_slot_t *slot = NULL;
  int32_t status =
      proton_update_get_stage(stage, &slot, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  if (slot->written_size != slot->expected_size) {
    proton_update_set_message(
        error, error_len,
        "the staged update size does not match the signed size");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  if (slot->fd < 0 || close(slot->fd) != 0) {
    slot->fd = -1;
    proton_update_set_message(error, error_len,
                              "the update archive could not be closed");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_PLATFORM;
  }
  slot->fd = -1;

  proton_update_current[0] = '\0';
  char staged_bundle_path[PROTON_UPDATE_MAX_PATH];
  status = proton_update_expand_staged_archive(
      slot, staged_bundle_path,
      (int32_t)sizeof(staged_bundle_path), error, error_len);
  if (status != PROTON_OK) {
    proton_update_stage_release(slot, 1);
    return status;
  }

  char executable_dir[PROTON_UPDATE_MAX_PATH];
  snprintf(executable_dir, sizeof(executable_dir), "%s/Contents/MacOS",
           staged_bundle_path);
  if (!proton_update_is_directory(executable_dir)) {
    proton_update_set_message(
        error, error_len,
        "the staged bundle has no Contents/MacOS directory");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  char current[PROTON_UPDATE_MAX_PATH];
  if (!proton_update_running_bundle(current, sizeof(current))) {
    proton_update_set_message(
        error, error_len,
        "the running executable is not inside a .app bundle, so there is "
        "nothing to replace");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_UNSUPPORTED;
  }
  if (strcmp(current, staged_bundle_path) == 0) {
    proton_update_set_message(error, error_len,
                              "the staged bundle is the running bundle");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  int lock_fd = -1;
  status = proton_update_acquire_commit_lock(current, &lock_fd, error,
                                             error_len);
  if (status != PROTON_OK) {
    proton_update_stage_release(slot, 1);
    return status;
  }
  if (!proton_update_verify_bundle(staged_bundle_path, current, error,
                                   error_len)) {
    close(lock_fd);
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_INVALID_ARGUMENT;
  }

  uint64_t staged_revision = 0;
  uint64_t current_revision = 0;
  if (!proton_update_bundle_revision(staged_bundle_path, 0, &staged_revision,
                                     error, error_len) ||
      !proton_update_bundle_revision(current, 1, &current_revision, error,
                                     error_len)) {
    close(lock_fd);
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_UPDATE_REVISION_MISMATCH;
  }
  uint64_t target_revision = slot->target_revision != 0
                                 ? slot->target_revision
                                 : staged_revision;
  if (staged_revision != target_revision) {
    close(lock_fd);
    proton_update_set_message(
        error, error_len,
        "the staged application revision does not match the signed manifest");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_UPDATE_REVISION_MISMATCH;
  }
  if (target_revision < current_revision) {
    close(lock_fd);
    proton_update_set_message(
        error, error_len,
        "the staged update revision is older than the installed application");
    proton_update_stage_release(slot, 1);
    return PROTON_ERR_UPDATE_ROLLBACK;
  }
  if (target_revision == current_revision) {
    close(lock_fd);
    *out_outcome = PROTON_UPDATE_ALREADY_INSTALLED;
    proton_update_stage_release(slot, 1);
    return PROTON_OK;
  }
  int preserve_staging = 0;
  status = proton_update_replace_bundle(staged_bundle_path, current,
                                        &preserve_staging, error, error_len);
  close(lock_fd);
  proton_update_stage_release(slot, !preserve_staging);
  return status;
}

PROTON_API int32_t proton_update_stage_install(
    proton_update_stage_id_t stage, char *error, int32_t error_len) {
  int32_t outcome = PROTON_UPDATE_INSTALLED;
  return proton_update_stage_install_outcome(stage, &outcome, error, error_len);
}

PROTON_API int32_t proton_update_install(const char *archive,
                                         int32_t archive_len,
                                         const char *parent_dir, char *error,
                                         int32_t error_len) {
  if (archive == NULL || archive_len <= 0) {
    proton_update_set_message(error, error_len, "the update archive is empty");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
  int32_t status = proton_update_stage_begin_revision(
      parent_dir, archive_len, 0, &stage, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_update_stage_write(stage, archive, archive_len, error,
                                     error_len);
  if (status != PROTON_OK) {
    (void)proton_update_stage_abort(stage, NULL, 0);
    return status;
  }
  int32_t outcome = PROTON_UPDATE_INSTALLED;
  return proton_update_stage_install_outcome(stage, &outcome, error, error_len);
}

PROTON_API int32_t proton_update_relaunch(char *error, int32_t error_len) {
  if (proton_update_current[0] == '\0') {
    proton_update_set_message(error, error_len,
                              "no application has been replaced");
    return PROTON_ERR_INVALID_ARGUMENT;
  }
  /* `-n` asks Launch Services for a new instance rather than activating one
     that is already running. It does not give the replacement a fresh
     environment: `open` passes this process's environment on, which was
     established by running it. */
  char *const argv[] = {"/usr/bin/open", "-n", proton_update_current, NULL};
  if (!proton_update_run(argv)) {
    proton_update_set_message(error, error_len,
                              "cannot start the replaced application");
    return PROTON_ERR_PLATFORM;
  }
  /* This waits for `open` and reports what it said, which is more than the
     spawn succeeding: a missing or malformed bundle is refused here rather
     than silently reported as a relaunch.

     It is still not proof that the application is running. Launch Services
     accepts the request and decides afterwards, and it declines some locations
     — an application under the per-user temporary directory, for instance —
     without telling anyone. `open` exits 0 in that case and so does
     LSOpenFromURLSpec, so there is nothing here to check. Success means the
     request was accepted. */
  return PROTON_OK;
}

#endif
