#include "proton_update.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define TEST_PATH_CAPACITY 4096

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(1);
}

static void require_status(int32_t status, const char *message,
                           const char *detail) {
  if (status != PROTON_OK) {
    fprintf(stderr, "%s: status %d: %s\n", message, (int)status, detail);
    exit(1);
  }
}

static void write_text(const char *path, const char *text) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0) {
    fail("failed to create a test file");
  }
  size_t length = strlen(text);
  if (write(fd, text, length) != (ssize_t)length || close(fd) != 0) {
    fail("failed to write a test file");
  }
}

static void read_text(const char *path, char *out, size_t out_len) {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    fail("failed to read a test file");
  }
  ssize_t length = read(fd, out, out_len - 1);
  close(fd);
  if (length < 0) {
    fail("failed to read test file contents");
  }
  out[length] = '\0';
}

int main(void) {
  char root[] = "/tmp/proton-update-linux-XXXXXX";
  if (mkdtemp(root) == NULL) {
    fail("failed to create the test directory");
  }
  char appimage[TEST_PATH_CAPACITY];
  char revision[TEST_PATH_CAPACITY];
  char lock[TEST_PATH_CAPACITY];
  snprintf(appimage, sizeof(appimage), "%s/Demo.AppImage", root);
  snprintf(revision, sizeof(revision), "%s.proton-revision", appimage);
  snprintf(lock, sizeof(lock), "%s.proton-update.lock", appimage);
  write_text(appimage, "release-1");
  write_text(revision, "1\n");
  proton_update_set_current_bundle_for_testing(appimage);
  proton_update_set_medium_for_testing("appimage");

  for (uint64_t target = 2; target <= 12; target++) {
    char payload[32];
    snprintf(payload, sizeof(payload), "release-%llu",
             (unsigned long long)target);
    char error[512] = {0};
    proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
    require_status(proton_update_stage_begin_revision(
                       root, (int64_t)strlen(payload), target, &stage, error,
                       (int32_t)sizeof(error)),
                   "stage begin failed", error);
    require_status(proton_update_stage_write(
                       stage, payload, (int32_t)strlen(payload), error,
                       (int32_t)sizeof(error)),
                   "stage write failed", error);
    int32_t outcome = -1;
    require_status(proton_update_stage_install_outcome(
                       stage, &outcome, error, (int32_t)sizeof(error)),
                   "stage install failed", error);
    if (outcome != PROTON_UPDATE_INSTALLED) {
      fail("the AppImage update did not report installation");
    }
    char installed[32];
    read_text(appimage, installed, sizeof(installed));
    if (strcmp(installed, payload) != 0) {
      fail("the AppImage was not replaced");
    }
    const char *reported_previous = proton_update_previous_bundle_path();
    if (reported_previous[0] == '\0' || access(reported_previous, F_OK) != 0) {
      fail("the previous AppImage was not retained");
    }
    char previous[TEST_PATH_CAPACITY];
    snprintf(previous, sizeof(previous), "%s", reported_previous);
    uint64_t current = 0;
    require_status(proton_update_current_revision(
                       &current, error, (int32_t)sizeof(error)),
                   "current revision failed", error);
    if (current != target) {
      fail("the in-process AppImage revision did not advance");
    }
    require_status(proton_update_cleanup_previous(error,
                                                   (int32_t)sizeof(error)),
                   "previous cleanup failed", error);
    if (access(previous, F_OK) == 0 || errno != ENOENT) {
      fail("the previous AppImage survived startup cleanup");
    }
  }

  proton_update_set_current_bundle_for_testing(NULL);
  proton_update_set_medium_for_testing(NULL);
  (void)unlink(appimage);
  (void)unlink(revision);
  (void)unlink(lock);
  if (rmdir(root) != 0) {
    fail("failed to remove the test directory");
  }
  return 0;
}
