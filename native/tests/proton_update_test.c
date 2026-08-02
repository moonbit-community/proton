#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../src/proton_update.h"

static char root[1024];

/* Builds a real, signable application bundle.

   The updater checks a staged bundle's code signature, so a directory tree
   made with mkdir is no longer enough: these need an Info.plist, a Mach-O to
   be the executable, and a seal over both. */
static void make_bundle(const char *path, const char *identifier) {
  char buffer[1400];
  assert(mkdir(path, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents", path);
  assert(mkdir(buffer, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/MacOS", path);
  assert(mkdir(buffer, 0755) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/Resources", path);
  assert(mkdir(buffer, 0755) == 0);
#if defined(__APPLE__)
  char command[3000];
  /* A real Mach-O, with the signature it arrived with removed: a bundle whose
     executable is still signed by Apple is not the unsigned case this needs to
     be able to produce. */
  snprintf(command, sizeof(command),
           "cp /bin/echo '%s/Contents/MacOS/app' && codesign --remove-signature "
           "'%s/Contents/MacOS/app' 2>/dev/null",
           path, path);
  assert(system(command) == 0);
  snprintf(buffer, sizeof(buffer), "%s/Contents/Info.plist", path);
  FILE *plist = fopen(buffer, "w");
  assert(plist != NULL);
  fprintf(plist,
          "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          "<plist version=\"1.0\"><dict>\n"
          "<key>CFBundleExecutable</key><string>app</string>\n"
          "<key>CFBundleIdentifier</key><string>%s</string>\n"
          "<key>CFBundlePackageType</key><string>APPL</string>\n"
          "</dict></plist>\n",
          identifier);
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
  assert(system(command) == 0);
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
  assert(file != NULL);
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

/* Archives one bundle and returns the exact bytes the updater receives. */
static char *archive_bundle(const char *bundle, const char *archive,
                            long *length) {
  char command[3000];
  snprintf(command, sizeof(command),
           "/usr/bin/ditto -c -k --keepParent '%s' '%s'", bundle, archive);
  assert(system(command) == 0);
  return read_file(archive, length);
}

static int exists(const char *path) {
  struct stat info;
  return lstat(path, &info) == 0;
}

/* Every bundle in this test claims to be the same application, because the
   updater refuses one that does not. The cases that vary it say so. */
static const char *const kIdentifier = "com.example.proton-update-test";

int main(void) {
  char error[512];
  snprintf(root, sizeof(root), "/tmp/proton-update-test-%ld", (long)getpid());
  assert(mkdir(root, 0755) == 0);

  char installed[1100];
  char staged[1100];
  snprintf(installed, sizeof(installed), "%s/Installed.app", root);
  snprintf(staged, sizeof(staged), "%s/Staged.app", root);
  make_bundle(installed, kIdentifier);
  make_bundle(staged, kIdentifier);
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
  assert(mkdir(parent, 0755) == 0);

  /* Invalid input and an archive with no bundle are refused before the
     installed application is touched, and private staging is removed. */
  assert(proton_update_install("zip", 3, "staging", error, sizeof(error)) !=
         0);
  assert(proton_update_install("", 0, parent, error, sizeof(error)) != 0);
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
  assert(proton_update_install(empty_bytes, (int32_t)empty_len, parent, error,
                               sizeof(error)) != 0);
  snprintf(command, sizeof(command),
           "test -z \"$(ls -A '%s')\"", parent);
  assert(system(command) == 0);
  free(empty_bytes);

  /* An unsigned bundle is refused: with no seal, nothing covers its contents
     once the archive signature stopped applying. */
  char unsigned_bundle[1100];
  snprintf(unsigned_bundle, sizeof(unsigned_bundle), "%s/Unsigned.app", root);
  make_bundle(unsigned_bundle, kIdentifier);
  char unsigned_archive[1200];
  snprintf(unsigned_archive, sizeof(unsigned_archive), "%s/unsigned.zip",
           root);
  long unsigned_len = 0;
  char *unsigned_bytes =
      archive_bundle(unsigned_bundle, unsigned_archive, &unsigned_len);
  assert(proton_update_install(unsigned_bytes, (int32_t)unsigned_len, parent,
                               error, sizeof(error)) != 0);
  assert(strcmp(error, "the staged bundle is not signed") == 0);
  free(unsigned_bytes);

  /* A bundle altered after it was signed is refused. This is the window the
     archive signature cannot cover, because by now the archive is gone. */
  char tampered[1100];
  snprintf(tampered, sizeof(tampered), "%s/Tampered.app", root);
  make_bundle(tampered, kIdentifier);
  write_marker(tampered, "before");
  sign_bundle(tampered, kIdentifier);
  write_marker(tampered, "after");
  char tampered_archive[1200];
  snprintf(tampered_archive, sizeof(tampered_archive), "%s/tampered.zip",
           root);
  long tampered_len = 0;
  char *tampered_bytes =
      archive_bundle(tampered, tampered_archive, &tampered_len);
  assert(proton_update_install(tampered_bytes, (int32_t)tampered_len, parent,
                               error, sizeof(error)) != 0);
  assert(strncmp(error, "the staged bundle does not match its code signature",
                 50) == 0);
  free(tampered_bytes);

  /* A validly signed bundle that is a different application is refused. An
     intact seal says only that a bundle was not altered. */
  char stranger[1100];
  snprintf(stranger, sizeof(stranger), "%s/Stranger.app", root);
  make_bundle(stranger, "com.example.somebody-else");
  write_marker(stranger, "stranger");
  sign_bundle(stranger, "com.example.somebody-else");
  char stranger_archive[1200];
  snprintf(stranger_archive, sizeof(stranger_archive), "%s/stranger.zip",
           root);
  long stranger_len = 0;
  char *stranger_bytes =
      archive_bundle(stranger, stranger_archive, &stranger_len);
  assert(proton_update_install(stranger_bytes, (int32_t)stranger_len, parent,
                               error, sizeof(error)) != 0);
  assert(strcmp(error,
                "the staged bundle is signed as a different application") == 0);
  free(stranger_bytes);
  assert(exists(installed));
  assert(marker_is(installed, "old"));

  /* The install consumes authenticated bytes, not the path that produced
     them. Replacing that path after the bytes were read cannot change what is
     expanded, checked, and installed by the native transaction. */
  char accepted_archive[1200];
  snprintf(accepted_archive, sizeof(accepted_archive), "%s/accepted.zip",
           root);
  long accepted_len = 0;
  char *accepted_bytes =
      archive_bundle(staged, accepted_archive, &accepted_len);
  char accepted_original[1100];
  char substitute[1100];
  snprintf(accepted_original, sizeof(accepted_original), "%s/Accepted.app",
           root);
  snprintf(substitute, sizeof(substitute), "%s/Substitute.app", root);
  make_bundle(substitute, kIdentifier);
  write_marker(substitute, "substitute");
  sign_bundle(substitute, kIdentifier);
  assert(rename(staged, accepted_original) == 0);
  assert(rename(substitute, staged) == 0);
  assert(proton_update_install(accepted_bytes, (int32_t)accepted_len, parent,
                               error, sizeof(error)) == 0);
  assert(marker_is(installed, "new"));
  assert(marker_is(staged, "substitute"));
  free(accepted_bytes);
  const char *previous = proton_update_previous_bundle_path();
  assert(previous != NULL && previous[0] != '\0');
  assert(exists(previous));
  assert(marker_is(previous, "old"));
  snprintf(command, sizeof(command), "test -z \"$(ls -A '%s')\"", parent);
  assert(system(command) == 0);
#else
  /* Every entry point reports that it is unimplemented rather than pretending
     to have installed something. */
  assert(proton_update_install("zip", 3, root, error, sizeof(error)) != 0);
  assert(proton_update_relaunch(error, sizeof(error)) != 0);
  assert(marker_is(installed, "old"));
#endif

  char cleanup[1300];
  snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", root);
  assert(system(cleanup) == 0);
  return 0;
}
