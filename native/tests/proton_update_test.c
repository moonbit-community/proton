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

/* Reads a whole file, the way the updater holds a downloaded archive. */
static char *read_file(const char *path, long *length) {
  FILE *file = fopen(path, "rb");
  assert(file != NULL);
  assert(fseek(file, 0, SEEK_END) == 0);
  long size = ftell(file);
  assert(size > 0);
  assert(fseek(file, 0, SEEK_SET) == 0);
  char *data = malloc((size_t)size);
  assert(data != NULL);
  assert(fread(data, 1, (size_t)size, file) == (size_t)size);
  fclose(file);
  *length = size;
  return data;
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
  long archive_len = 0;
  char *archive_bytes = read_file(archive, &archive_len);

  char parent[1100];
  char bundle[1100];
  snprintf(parent, sizeof(parent), "%s/staging", root);
  assert(mkdir(parent, 0755) == 0);
  assert(proton_update_expand(archive_bytes, (int32_t)archive_len, parent,
                              bundle, sizeof(bundle), error,
                              sizeof(error)) == 0);
  assert(marker_is(bundle, "packed"));
  /* The staging directory belongs to this call, so a second expansion lands
     somewhere else instead of mixing two archives together. */
  char second[1100];
  assert(proton_update_expand(archive_bytes, (int32_t)archive_len, parent,
                              second, sizeof(second), error,
                              sizeof(error)) == 0);
  assert(strcmp(bundle, second) != 0);
  assert(marker_is(second, "packed"));
  /* Both live under the directory the caller named, and neither is readable by
     anyone else. */
  assert(strncmp(bundle, parent, strlen(parent)) == 0);
  struct stat staging_info;
  char staging_dir[1100];
  snprintf(staging_dir, sizeof(staging_dir), "%s", bundle);
  *strrchr(staging_dir, '/') = '\0';
  assert(lstat(staging_dir, &staging_info) == 0);
  assert((staging_info.st_mode & (S_IRWXG | S_IRWXO)) == 0);
  /* The archive is not left beside the bundle it produced. */
  char leftover[1200];
  snprintf(leftover, sizeof(leftover), "%s/update.zip", staging_dir);
  assert(!exists(leftover));

  /* An archive with no bundle is refused, and nothing is left behind. */
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
  long empty_len = 0;
  char *empty_bytes = read_file(empty_archive, &empty_len);
  char empty_parent[1100];
  char empty_out[1100];
  snprintf(empty_parent, sizeof(empty_parent), "%s/staging-empty", root);
  assert(mkdir(empty_parent, 0755) == 0);
  assert(proton_update_expand(empty_bytes, (int32_t)empty_len, empty_parent,
                              empty_out, sizeof(empty_out), error,
                              sizeof(error)) != 0);
  snprintf(command, sizeof(command),
           "test -z \"$(ls -A '%s')\"", empty_parent);
  assert(system(command) == 0);
  free(empty_bytes);

  /* A relative parent and an empty archive are refused before anything is
     created. */
  assert(proton_update_expand(archive_bytes, (int32_t)archive_len, "staging",
                              bundle, sizeof(bundle), error,
                              sizeof(error)) != 0);
  assert(proton_update_expand(archive_bytes, 0, parent, bundle, sizeof(bundle),
                              error, sizeof(error)) != 0);
  free(archive_bytes);

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

  /* A whole expand-stage-apply run leaves nothing behind: the bundle moves
     into place and the directory it was expanded into goes with it. */
  char second_dir[1100];
  snprintf(second_dir, sizeof(second_dir), "%s", second);
  *strrchr(second_dir, '/') = '\0';
  assert(exists(second_dir));
  assert(proton_update_stage(second, error, sizeof(error)) == 0);
  assert(proton_update_apply(error, sizeof(error)) == 0);
  assert(marker_is(installed, "packed"));
  assert(!exists(second_dir));
  /* Applying twice is refused: the run that succeeded consumed the bundle. */
  assert(proton_update_apply(error, sizeof(error)) != 0);
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
