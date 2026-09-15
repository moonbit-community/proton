/* Exercise the real updater, with faults only at the filesystem deletion seam. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int deletion_failed = 0;

static int fault_unlink(const char *path) {
  if (deletion_failed) {
    errno = EACCES;
    return -1;
  }
  const char *fault = getenv("PROTON_TEST_DELETE_FAULT");
  if (fault != NULL && strstr(path, "/deleting.app/") != NULL &&
      strstr(path, "/Info.plist") != NULL) {
    (void)unlink(path);
    if (strcmp(fault, "interrupt") == 0) _exit(77);
    deletion_failed = 1;
    errno = EACCES;
    return -1;
  }
  return unlink(path);
}
static int fault_rmdir(const char *path) {
  if (deletion_failed) {
    errno = EACCES;
    return -1;
  }
  return rmdir(path);
}

static int fault_renameat(int from_fd, const char *from, int to_fd,
                          const char *to) {
  const char *fault = getenv("PROTON_TEST_DELETE_FAULT");
  if (fault != NULL && strcmp(fault, "before-transition") == 0) {
    errno = EACCES;
    return -1;
  }
  int result = renameat(from_fd, from, to_fd, to);
  if (result == 0 && fault != NULL && strcmp(fault, "after-transition") == 0) {
    _exit(77);
  }
  return result;
}

static const char *install_target;

static int fault_rename(const char *from, const char *to) {
  if (getenv("PROTON_TEST_INSTALL_FAILURE") != NULL &&
      strcmp(to, install_target) == 0 && strstr(from, "/.proton-update-") != NULL) {
    errno = EIO;
    return -1;
  }
  return rename(from, to);
}

#define renameat fault_renameat
#define rmdir fault_rmdir
#define rename fault_rename
#define unlink fault_unlink
#include "../../src/proton_update.c"
#undef unlink
#undef rename
#undef rmdir
#undef renameat

int main(int argc, char **argv) {
  if (argc < 3) return 2;
  install_target = argv[2];
  proton_update_set_current_bundle_for_testing(argv[2]);
  char error[1024] = {0};
  int status;
  if (strcmp(argv[1], "lock") == 0) {
    int fd = -1;
    status = proton_update_acquire_commit_lock(argv[2], &fd, error, sizeof(error));
    if (status == PROTON_OK) {
      puts("LOCKED");
      fflush(stdout);
      (void)getchar();
      close(fd);
    }
  } else if (strcmp(argv[1], "install") == 0 && argc == 4) {
    FILE *file = fopen(argv[3], "rb");
    if (file == NULL) return 2;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    rewind(file);
    char *bytes = malloc(size);
    if (bytes == NULL || fread(bytes, 1, size, file) != (size_t)size) return 2;
    fclose(file);
    status = proton_update_install(bytes, (int32_t)size, NULL, error, sizeof(error));
    free(bytes);
  } else {
    status = proton_update_cleanup_previous(error, sizeof(error));
  }
  printf("STATUS %d %s\n", status, error);
  return status == PROTON_OK ? 0 : 1;
}
