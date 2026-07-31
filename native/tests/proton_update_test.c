#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../src/proton_update.h"

static char root[1024];

static void make_bundle(const char *path) {
  char buffer[1200];
  assert(mkdir(path, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents", path);
  assert(mkdir(buffer, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/MacOS", path);
  assert(mkdir(buffer, 0755) == 0);
}

static void write_marker(const char *bundle, const char *value) {
  char buffer[1200];
  snprintf(buffer, sizeof(buffer), "%s/Contents/marker", bundle);
  FILE *file = fopen(buffer, "w");
  assert(file != NULL);
  fputs(value, file);
  fclose(file);
}

static int marker_is(const char *bundle, const char *value) {
  char buffer[1200];
  snprintf(buffer, sizeof(buffer), "%s/Contents/marker", bundle);
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

static int exists(const char *path) {
  struct stat info;
  return lstat(path, &info) == 0;
}

int main(void) {
  char error[512];
  snprintf(root, sizeof(root), "/tmp/proton-update-test-%ld", (long)getpid());
  assert(mkdir(root, 0755) == 0);

  char installed[1100];
  char staged[1100];
  snprintf(installed, sizeof(installed), "%s/Installed.app", root);
  snprintf(staged, sizeof(staged), "%s/Staged.app", root);
  make_bundle(installed);
  make_bundle(staged);
  write_marker(installed, "old");
  write_marker(staged, "new");

  /* Nothing is treated as running until a test says so, and the running
     bundle is a throwaway directory rather than this test binary's own. */
  proton_update_set_current_bundle_for_testing(installed);

#if defined(__APPLE__)
  /* Expansion: a real archive containing one bundle, produced the way a
     release would produce it. */
  char archive_root[1100];
  char archive[1200];
  char expanded[1100];
  char command[2600];
  snprintf(archive_root, sizeof(archive_root), "%s/archive", root);
  assert(mkdir(archive_root, 0755) == 0);
  char packed[1200];
  snprintf(packed, sizeof(packed), "%s/Packed.app", archive_root);
  make_bundle(packed);
  write_marker(packed, "packed");
  snprintf(archive, sizeof(archive), "%s/update.zip", root);
  snprintf(command, sizeof(command),
           "cd '%s' && /usr/bin/ditto -c -k --keepParent 'Packed.app' '%s'",
           archive_root, archive);
  assert(system(command) == 0);

  char bundle[1100];
  snprintf(expanded, sizeof(expanded), "%s/expanded", root);
  assert(proton_update_expand(archive, expanded, bundle, sizeof(bundle), error,
                              sizeof(error)) == 0);
  assert(marker_is(bundle, "packed"));
  /* The expansion directory is created by this call, so expanding twice into
     the same place is refused rather than mixing two archives. */
  assert(proton_update_expand(archive, expanded, bundle, sizeof(bundle), error,
                              sizeof(error)) != 0);
  /* An archive with no bundle, and one with two, are both refused: neither
     says which application to install. */
  char empty_root[1100];
  char empty_archive[1200];
  snprintf(empty_root, sizeof(empty_root), "%s/empty", root);
  assert(mkdir(empty_root, 0755) == 0);
  snprintf(command, sizeof(command), "touch '%s/README'", empty_root);
  assert(system(command) == 0);
  snprintf(empty_archive, sizeof(empty_archive), "%s/empty.zip", root);
  snprintf(command, sizeof(command),
           "cd '%s' && /usr/bin/ditto -c -k --keepParent 'README' '%s'",
           empty_root, empty_archive);
  assert(system(command) == 0);
  char empty_out[1100];
  char empty_dest[1100];
  snprintf(empty_dest, sizeof(empty_dest), "%s/expanded-empty", root);
  assert(proton_update_expand(empty_archive, empty_dest, empty_out,
                              sizeof(empty_out), error, sizeof(error)) != 0);
  /* Relative paths are refused before anything is created. */
  assert(proton_update_expand("update.zip", expanded, bundle, sizeof(bundle),
                              error, sizeof(error)) != 0);

  /* A relative path, a directory that is not a bundle, a missing bundle, and a
     bundle without an executable directory are all refused before anything is
     touched. */
  assert(proton_update_stage("Staged.app", error, sizeof(error)) != 0);
  assert(proton_update_stage(root, error, sizeof(error)) != 0);
  char missing[1100];
  snprintf(missing, sizeof(missing), "%s/Absent.app", root);
  assert(proton_update_stage(missing, error, sizeof(error)) != 0);
  char shallow[1100];
  snprintf(shallow, sizeof(shallow), "%s/Shallow.app", root);
  assert(mkdir(shallow, 0755) == 0);
  assert(proton_update_stage(shallow, error, sizeof(error)) != 0);
  /* Installing the running bundle over itself is refused rather than being a
     rename onto the same path. */
  assert(proton_update_stage(installed, error, sizeof(error)) != 0);
  /* Applying without a staged bundle is refused. */
  assert(proton_update_apply(error, sizeof(error)) != 0);
  assert(exists(installed));
  assert(marker_is(installed, "old"));

  /* The accepted case replaces the installed bundle and keeps the old one. */
  assert(proton_update_stage(staged, error, sizeof(error)) == 0);
  assert(marker_is(installed, "old"));
  assert(proton_update_apply(error, sizeof(error)) == 0);
  assert(marker_is(installed, "new"));
  assert(!exists(staged));
  const char *previous = proton_update_previous_bundle_path();
  assert(previous != NULL && previous[0] != '\0');
  assert(exists(previous));
  assert(marker_is(previous, "old"));

  /* A staged bundle that disappears between staging and applying leaves the
     installed application exactly as it was. */
  char vanishing[1100];
  snprintf(vanishing, sizeof(vanishing), "%s/Vanishing.app", root);
  make_bundle(vanishing);
  write_marker(vanishing, "never");
  assert(proton_update_stage(vanishing, error, sizeof(error)) == 0);
  char buffer[1300];
  snprintf(buffer, sizeof(buffer), "rm -rf '%s'", vanishing);
  assert(system(buffer) == 0);
  assert(proton_update_apply(error, sizeof(error)) != 0);
  assert(exists(installed));
  assert(marker_is(installed, "new"));
#else
  /* Every entry point reports that it is unimplemented rather than pretending
     to have installed something. */
  assert(proton_update_stage(staged, error, sizeof(error)) != 0);
  assert(proton_update_apply(error, sizeof(error)) != 0);
  assert(proton_update_relaunch(error, sizeof(error)) != 0);
  assert(marker_is(installed, "old"));
#endif

  char cleanup[1300];
  snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", root);
  assert(system(cleanup) == 0);
  return 0;
}
