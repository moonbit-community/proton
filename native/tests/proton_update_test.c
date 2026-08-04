#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../src/proton_update.h"

/* Unlike assert, REQUIRE still evaluates setup and API calls under NDEBUG. */
#define REQUIRE(condition)                                                     \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: requirement failed: %s\n", __FILE__, __LINE__,   \
              #condition);                                                     \
      exit(EXIT_FAILURE);                                                      \
    }                                                                          \
  } while (0)

static char root[1024];

/* Builds a real, signable application bundle.

   The updater checks a staged bundle's code signature, so a directory tree
   made with mkdir is no longer enough: these need an Info.plist, a Mach-O to
   be the executable, and a seal over both. */
static void make_bundle(const char *path, const char *identifier,
                        unsigned long long revision) {
  char buffer[1400];
  REQUIRE(mkdir(path, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents", path);
  REQUIRE(mkdir(buffer, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/MacOS", path);
  REQUIRE(mkdir(buffer, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/Resources", path);
  REQUIRE(mkdir(buffer, 0755) == 0);
#if defined(__APPLE__)
  char command[3000];
  /* A real Mach-O, with the signature it arrived with removed: a bundle whose
     executable is still signed by Apple is not the unsigned case this needs to
     be able to produce. */
  snprintf(
      command, sizeof(command),
      "cp /bin/echo '%s/Contents/MacOS/app' && codesign --remove-signature "
      "'%s/Contents/MacOS/app' 2>/dev/null",
      path, path);
  REQUIRE(system(command) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/Info.plist", path);
  FILE *plist = fopen(buffer, "w");
  REQUIRE(plist != NULL);
  fprintf(plist,
          "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          "<plist version=\"1.0\"><dict>\n"
          "<key>CFBundleExecutable</key><string>app</string>\n"
          "<key>CFBundleIdentifier</key><string>%s</string>\n"
          "<key>CFBundlePackageType</key><string>APPL</string>\n"
          "<key>ProtonUpdateRevision</key><string>%llu</string>\n"
          "</dict></plist>\n",
          identifier, revision);
  fclose(plist);
#else
  (void)identifier;
#endif
}

/* Seals a bundle, ad-hoc.

   The identifier is passed explicitly: without it codesign inherits the one
   already on the copied executable, and the test would compare Apple's name
   for /bin/echo rather than the bundle's own. */
static void sign_bundle(const char *path, const char *identifier) {
#if defined(__APPLE__)
  char command[3000];
  snprintf(command, sizeof(command),
           "codesign --force --identifier '%s' --sign - '%s' 2>/dev/null",
           identifier, path);
  REQUIRE(system(command) == 0);
#else
  (void)path;
  (void)identifier;
#endif
}

/* Writes the file that identifies which bundle is which.

   It goes under Contents/Resources because that is sealed. A loose file
   directly under Contents is a subcomponent codesign refuses to sign. */
static void write_marker(const char *bundle, const char *value) {
  char buffer[1200];
  snprintf(buffer, sizeof(buffer), "%s/Contents/Resources/marker", bundle);
  FILE *file = fopen(buffer, "w");
  REQUIRE(file != NULL);
  fputs(value, file);
  fclose(file);
}

static int marker_is(const char *bundle, const char *value) {
  char buffer[1200];
  snprintf(buffer, sizeof(buffer), "%s/Contents/Resources/marker", bundle);
  FILE *file = fopen(buffer, "r");
  if (file == NULL) {
    return 0;
  }
  char found[64] = {0};
  size_t read = fread(found, 1, sizeof(found) - 1, file);
  fclose(file);
  found[read] = '\0';
  return strcmp(found, value) == 0;
}

/* Reads a whole file, the way the updater holds a downloaded archive. */
static char *read_file(const char *path, long *length) {
  FILE *file = fopen(path, "rb");
  REQUIRE(file != NULL);
  REQUIRE(fseek(file, 0, SEEK_END) == 0);
  long size = ftell(file);
  REQUIRE(size > 0);
  REQUIRE(fseek(file, 0, SEEK_SET) == 0);
  char *data = malloc((size_t)size);
  REQUIRE(data != NULL);
  REQUIRE(fread(data, 1, (size_t)size, file) == (size_t)size);
  fclose(file);
  *length = size;
  return data;
}

/* Archives one bundle and returns the exact bytes the updater receives. */
static char *archive_bundle(const char *bundle, const char *archive,
                            long *length) {
  char command[3000];
  snprintf(command, sizeof(command),
           "/usr/bin/ditto -c -k --keepParent '%s' '%s'", bundle, archive);
  REQUIRE(system(command) == 0);
  return read_file(archive, length);
}

static int32_t install_archive(const char *bytes, int32_t length,
                               uint64_t revision,
                               int32_t *out_outcome, char *error,
                               int32_t error_len) {
  proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
  int32_t status = proton_update_stage_begin_revision(NULL, length, revision,
                                                      &stage, error, error_len);
  if (status != PROTON_OK) {
    return status;
  }
  status = proton_update_stage_write(stage, bytes, length, error, error_len);
  if (status != PROTON_OK) {
    (void)proton_update_stage_abort(stage, NULL, 0);
    return status;
  }
  return proton_update_stage_install_outcome(stage, out_outcome, error,
                                             error_len);
}

static int exists(const char *path) {
  struct stat info;
  return lstat(path, &info) == 0;
}

static int count_entries_with_prefix(const char *directory,
                                     const char *prefix) {
  DIR *handle = opendir(directory);
  REQUIRE(handle != NULL);
  int count = 0;
  size_t prefix_len = strlen(prefix);
  struct dirent *entry = NULL;
  while ((entry = readdir(handle)) != NULL) {
    if (strncmp(entry->d_name, prefix, prefix_len) == 0) {
      count++;
    }
  }
  closedir(handle);
  return count;
}

/* Every bundle in this test claims to be the same application, because the
   updater refuses one that does not. The cases that vary it say so. */
static const char *const kIdentifier = "com.example.proton-update-test";

int main(void) {
  char error[512];
  snprintf(root, sizeof(root), "/tmp/proton-update-test-%ld", (long)getpid());
  REQUIRE(mkdir(root, 0755) == 0);

  char installed[1100];
  char staged[1100];
  snprintf(installed, sizeof(installed), "%s/Installed.app", root);
  snprintf(staged, sizeof(staged), "%s/Staged.app", root);
  make_bundle(installed, kIdentifier, 1);
  make_bundle(staged, kIdentifier, 2);
  write_marker(installed, "old");
  write_marker(staged, "new");
  sign_bundle(installed, kIdentifier);
  sign_bundle(staged, kIdentifier);

  /* Nothing is treated as running until a test says so, and the running
     bundle is a throwaway directory rather than this test binary's own. */
  proton_update_set_current_bundle_for_testing(installed);

#if defined(__APPLE__)
  /* Every install below consumes archive bytes and keeps the expanded path
     inside native code until validation and replacement are complete. */
  char command[2600];
  char parent[1100];
  snprintf(parent, sizeof(parent), "%s/staging", root);
  REQUIRE(mkdir(parent, 0755) == 0);
  uint64_t current_revision = 0;
  REQUIRE(proton_update_current_revision(&current_revision, error,
                                         sizeof(error)) == 0);
  REQUIRE(current_revision == 1);

  /* A stage enforces the signed size independently of the MoonBit stream
     consumer. Oversized chunks never reach disk, short stages are consumed and
     removed, and a closed generation cannot be reused. */
  proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
  int32_t install_outcome = PROTON_UPDATE_INSTALLED;
  REQUIRE(proton_update_stage_begin("staging", 3, &stage, error,
                                    sizeof(error)) != 0);
  REQUIRE(stage == PROTON_INVALID_HANDLE);
  REQUIRE(proton_update_stage_begin(parent, 3, &stage, error, sizeof(error)) ==
          0);
  REQUIRE(proton_update_stage_write(stage, "four", 4, error, sizeof(error)) !=
          0);
  REQUIRE(proton_update_stage_abort(stage, error, sizeof(error)) == 0);
  REQUIRE(proton_update_stage_abort(stage, error, sizeof(error)) != 0);
  REQUIRE(proton_update_stage_begin_revision(parent, 3, 2, &stage, error,
                                             sizeof(error)) == 0);
  REQUIRE(proton_update_stage_write(stage, "ab", 2, error, sizeof(error)) == 0);
  REQUIRE(proton_update_stage_install(stage, error, sizeof(error)) != 0);
  REQUIRE(strcmp(error,
                 "the staged update size does not match the signed size") == 0);
  snprintf(command, sizeof(command), "test -z \"$(ls -A '%s')\"", parent);
  REQUIRE(system(command) == 0);

  /* The application-facing default creates its private stage beside the
     installed bundle, not under a user-data or temporary directory that may
     be mounted on another filesystem. */
  REQUIRE(proton_update_stage_begin_revision(NULL, 3, 2, &stage, error,
                                             sizeof(error)) == 0);
  REQUIRE(count_entries_with_prefix(root, ".proton-update-") == 1);
  REQUIRE(proton_update_stage_abort(stage, error, sizeof(error)) == 0);
  REQUIRE(count_entries_with_prefix(root, ".proton-update-") == 0);

  /* Invalid input and an archive with no bundle are refused before the
     installed application is touched, and private staging is removed. */
  REQUIRE(proton_update_install("zip", 3, "staging", error, sizeof(error)) !=
          0);
  REQUIRE(proton_update_install("", 0, parent, error, sizeof(error)) != 0);
  char empty_root[1100];
  char empty_archive[1200];
  snprintf(empty_root, sizeof(empty_root), "%s/empty", root);
  REQUIRE(mkdir(empty_root, 0755) == 0);
  snprintf(command, sizeof(command), "touch '%s/README'", empty_root);
  REQUIRE(system(command) == 0);
  snprintf(empty_archive, sizeof(empty_archive), "%s/empty.zip", root);
  snprintf(command, sizeof(command),
           "cd '%s' && /usr/bin/ditto -c -k --keepParent 'README' '%s'",
           empty_root, empty_archive);
  REQUIRE(system(command) == 0);
  long empty_len = 0;
  char *empty_bytes = read_file(empty_archive, &empty_len);
  REQUIRE(proton_update_install(empty_bytes, (int32_t)empty_len, parent, error,
                                sizeof(error)) != 0);
  snprintf(command, sizeof(command), "test -z \"$(ls -A '%s')\"", parent);
  REQUIRE(system(command) == 0);
  free(empty_bytes);

  /* An unsigned bundle is refused: with no seal, nothing covers its contents
     once the archive signature stopped applying. */
  char unsigned_bundle[1100];
  snprintf(unsigned_bundle, sizeof(unsigned_bundle), "%s/Unsigned.app", root);
  make_bundle(unsigned_bundle, kIdentifier, 2);
  char unsigned_archive[1200];
  snprintf(unsigned_archive, sizeof(unsigned_archive), "%s/unsigned.zip", root);
  long unsigned_len = 0;
  char *unsigned_bytes =
      archive_bundle(unsigned_bundle, unsigned_archive, &unsigned_len);
  REQUIRE(proton_update_install(unsigned_bytes, (int32_t)unsigned_len, parent,
                                error, sizeof(error)) != 0);
  REQUIRE(strcmp(error, "the staged bundle is not signed") == 0);
  free(unsigned_bytes);

  /* A bundle altered after it was signed is refused. This is the window the
     archive signature cannot cover, because by now the archive is gone. */
  char tampered[1100];
  snprintf(tampered, sizeof(tampered), "%s/Tampered.app", root);
  make_bundle(tampered, kIdentifier, 2);
  write_marker(tampered, "before");
  sign_bundle(tampered, kIdentifier);
  write_marker(tampered, "after");
  char tampered_archive[1200];
  snprintf(tampered_archive, sizeof(tampered_archive), "%s/tampered.zip", root);
  long tampered_len = 0;
  char *tampered_bytes =
      archive_bundle(tampered, tampered_archive, &tampered_len);
  REQUIRE(proton_update_install(tampered_bytes, (int32_t)tampered_len, parent,
                                error, sizeof(error)) != 0);
  REQUIRE(strncmp(error, "the staged bundle does not match its code signature",
                  50) == 0);
  free(tampered_bytes);

  /* A validly signed bundle that is a different application is refused. An
     intact seal says only that a bundle was not altered. */
  char stranger[1100];
  snprintf(stranger, sizeof(stranger), "%s/Stranger.app", root);
  make_bundle(stranger, "com.example.somebody-else", 2);
  write_marker(stranger, "stranger");
  sign_bundle(stranger, "com.example.somebody-else");
  char stranger_archive[1200];
  snprintf(stranger_archive, sizeof(stranger_archive), "%s/stranger.zip", root);
  long stranger_len = 0;
  char *stranger_bytes =
      archive_bundle(stranger, stranger_archive, &stranger_len);
  REQUIRE(proton_update_install(stranger_bytes, (int32_t)stranger_len, parent,
                                error, sizeof(error)) != 0);
  REQUIRE(
      strcmp(error, "the staged bundle is signed as a different application") ==
      0);
  free(stranger_bytes);
  REQUIRE(exists(installed));
  REQUIRE(marker_is(installed, "old"));

  /* The install consumes authenticated bytes, not the path that produced
     them. Replacing that path after the bytes were read cannot change what is
     expanded, checked, and installed by the native transaction. */
  char accepted_archive[1200];
  snprintf(accepted_archive, sizeof(accepted_archive), "%s/accepted.zip", root);
  long accepted_len = 0;
  char *accepted_bytes =
      archive_bundle(staged, accepted_archive, &accepted_len);

  /* A process that reaches commit while another process owns the install lock
     gets a stable busy result. It does not wait behind code it cannot observe
     and it never touches the installed application. */
  char lock_path[1200];
  snprintf(lock_path, sizeof(lock_path), "%s.proton-update.lock", installed);
  int lock_fd = open(lock_path, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  REQUIRE(lock_fd >= 0);
  REQUIRE(flock(lock_fd, LOCK_EX | LOCK_NB) == 0);
  install_outcome = PROTON_UPDATE_INSTALLED;
  REQUIRE(install_archive(accepted_bytes, (int32_t)accepted_len, 2,
                          &install_outcome, error,
                          sizeof(error)) == PROTON_ERR_UPDATE_BUSY);
  REQUIRE(marker_is(installed, "old"));
  REQUIRE(close(lock_fd) == 0);

  char accepted_original[1100];
  char substitute[1100];
  snprintf(accepted_original, sizeof(accepted_original), "%s/Accepted.app",
           root);
  snprintf(substitute, sizeof(substitute), "%s/Substitute.app", root);
  make_bundle(substitute, kIdentifier, 2);
  write_marker(substitute, "substitute");
  sign_bundle(substitute, kIdentifier);
  REQUIRE(rename(staged, accepted_original) == 0);
  REQUIRE(rename(substitute, staged) == 0);
  REQUIRE(proton_update_stage_begin_revision(NULL, accepted_len, 2, &stage,
                                             error, sizeof(error)) == 0);
  int32_t first_chunk = (int32_t)(accepted_len / 2);
  REQUIRE(proton_update_stage_write(stage, accepted_bytes, first_chunk, error,
                                    sizeof(error)) == 0);
  REQUIRE(proton_update_stage_write(stage, accepted_bytes + first_chunk,
                                    (int32_t)accepted_len - first_chunk, error,
                                    sizeof(error)) == 0);
  REQUIRE(proton_update_stage_install_outcome(stage, &install_outcome, error,
                                              sizeof(error)) == 0);
  REQUIRE(install_outcome == PROTON_UPDATE_INSTALLED);
  REQUIRE(marker_is(installed, "new"));
  REQUIRE(marker_is(staged, "substitute"));
  free(accepted_bytes);
  const char *previous = proton_update_previous_bundle_path();
  REQUIRE(previous != NULL && previous[0] != '\0');
  REQUIRE(exists(previous));
  REQUIRE(marker_is(previous, "old"));
  REQUIRE(proton_update_current_revision(&current_revision, error,
                                         sizeof(error)) == 0);
  REQUIRE(current_revision == 2);
  snprintf(command, sizeof(command), "test -z \"$(ls -A '%s')\"", parent);
  REQUIRE(system(command) == 0);

  /* Reapplying the installed revision is idempotent. The authenticated stage
     is consumed, but the current bundle and retained previous bundle do not
     move again. */
  char equal_bundle[1100];
  char equal_archive[1200];
  snprintf(equal_bundle, sizeof(equal_bundle), "%s/Equal.app", root);
  snprintf(equal_archive, sizeof(equal_archive), "%s/equal.zip", root);
  make_bundle(equal_bundle, kIdentifier, 2);
  write_marker(equal_bundle, "equal");
  sign_bundle(equal_bundle, kIdentifier);
  long equal_len = 0;
  char *equal_bytes = archive_bundle(equal_bundle, equal_archive, &equal_len);
  install_outcome = PROTON_UPDATE_INSTALLED;
  REQUIRE(install_archive(equal_bytes, (int32_t)equal_len, 2,
                          &install_outcome, error, sizeof(error)) == 0);
  REQUIRE(install_outcome == PROTON_UPDATE_ALREADY_INSTALLED);
  REQUIRE(marker_is(installed, "new"));
  REQUIRE(strcmp(proton_update_previous_bundle_path(), previous) == 0);
  free(equal_bytes);

  /* A validly signed older application remains a rollback and a manifest that
     claims a different revision from the signed app is not installable. */
  char rollback_bundle[1100];
  char rollback_archive[1200];
  snprintf(rollback_bundle, sizeof(rollback_bundle), "%s/Rollback.app", root);
  snprintf(rollback_archive, sizeof(rollback_archive), "%s/rollback.zip", root);
  make_bundle(rollback_bundle, kIdentifier, 1);
  write_marker(rollback_bundle, "rollback");
  sign_bundle(rollback_bundle, kIdentifier);
  long rollback_len = 0;
  char *rollback_bytes =
      archive_bundle(rollback_bundle, rollback_archive, &rollback_len);
  REQUIRE(install_archive(rollback_bytes, (int32_t)rollback_len, 1,
                          &install_outcome, error,
                          sizeof(error)) == PROTON_ERR_UPDATE_ROLLBACK);
  REQUIRE(marker_is(installed, "new"));
  free(rollback_bytes);

  char mismatch_bundle[1100];
  char mismatch_archive[1200];
  snprintf(mismatch_bundle, sizeof(mismatch_bundle), "%s/Mismatch.app", root);
  snprintf(mismatch_archive, sizeof(mismatch_archive), "%s/mismatch.zip", root);
  make_bundle(mismatch_bundle, kIdentifier, 3);
  write_marker(mismatch_bundle, "mismatch");
  sign_bundle(mismatch_bundle, kIdentifier);
  long mismatch_len = 0;
  char *mismatch_bytes =
      archive_bundle(mismatch_bundle, mismatch_archive, &mismatch_len);
  REQUIRE(install_archive(mismatch_bytes, (int32_t)mismatch_len, 4,
                          &install_outcome, error, sizeof(error)) ==
          PROTON_ERR_UPDATE_REVISION_MISMATCH);
  REQUIRE(marker_is(installed, "new"));
  free(mismatch_bytes);
#else
  /* Every entry point reports that it is unimplemented rather than pretending
     to have installed something. */
  proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
  REQUIRE(proton_update_stage_begin(root, 3, &stage, error, sizeof(error)) !=
          0);
  REQUIRE(stage == PROTON_INVALID_HANDLE);
  REQUIRE(proton_update_install("zip", 3, root, error, sizeof(error)) != 0);
  REQUIRE(proton_update_relaunch(error, sizeof(error)) != 0);
  REQUIRE(marker_is(installed, "old"));
#endif

  /* Install-medium gating is shared, so it is exercised on every platform.
     An application may only replace an installation it owns; a managed one
     has to say so before any bytes are downloaded rather than stage work it
     could never install. */
  {
#if defined(__APPLE__)
    const char *expected_marker = "new";
#else
    const char *expected_marker = "old";
#endif
    proton_update_stage_id_t gated = PROTON_INVALID_HANDLE;
    static const struct {
      const char *medium;
      const char *expected_fragment;
    } managed[] = {
        {"flatpak", "Flatpak client"},
        {"snap", "snapd"},
        {"package", "package manager"},
    };
    for (size_t i = 0; i < sizeof(managed) / sizeof(managed[0]); i++) {
      proton_update_set_medium_for_testing(managed[i].medium);
      error[0] = '\0';
      gated = PROTON_INVALID_HANDLE;
      REQUIRE(proton_update_stage_begin(root, 3, &gated, error,
                                        sizeof(error)) ==
              PROTON_ERR_UNSUPPORTED);
      REQUIRE(gated == PROTON_INVALID_HANDLE);
      /* The reason names the mechanism that does own the update, so the
         message is actionable rather than a bare refusal. */
      REQUIRE(strstr(error, managed[i].expected_fragment) != NULL);
      /* Refusing must not touch the installation. */
      REQUIRE(marker_is(installed, expected_marker));
    }
    /* An AppImage is a single file the user owns, so it is not gated. The
       call still fails on this host for want of a real AppImage, but it must
       fail past the medium check rather than at it. */
    proton_update_set_medium_for_testing("appimage");
    error[0] = '\0';
    gated = PROTON_INVALID_HANDLE;
    int32_t appimage_status =
        proton_update_stage_begin(root, 3, &gated, error, sizeof(error));
    REQUIRE(appimage_status != PROTON_ERR_UNSUPPORTED ||
            strstr(error, "package manager") == NULL);
    if (gated != PROTON_INVALID_HANDLE) {
      REQUIRE(proton_update_stage_abort(gated, error, sizeof(error)) == 0);
    }
    proton_update_set_medium_for_testing(NULL);
  }

  char cleanup[1300];
  snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", root);
  REQUIRE(system(cleanup) == 0);
  return 0;
}
