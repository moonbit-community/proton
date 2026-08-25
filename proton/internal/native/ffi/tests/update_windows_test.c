#include "proton_update.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

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

static void write_text(const wchar_t *path, const char *text) {
  HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    fail("failed to create a test file");
  }
  DWORD length = (DWORD)strlen(text);
  DWORD written = 0;
  if (!WriteFile(file, text, length, &written, NULL) || written != length) {
    CloseHandle(file);
    fail("failed to write a test file");
  }
  CloseHandle(file);
}

static void to_utf8(const wchar_t *wide, char *out, int out_len) {
  if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, out_len, NULL, NULL) ==
      0) {
    fail("failed to convert a test path to UTF-8");
  }
}

int main(void) {
  wchar_t temp[MAX_PATH];
  DWORD temp_len = GetTempPathW(MAX_PATH, temp);
  if (temp_len == 0 || temp_len >= MAX_PATH) {
    fail("failed to find the temporary directory");
  }
  wchar_t root[MAX_PATH];
  _snwprintf(root, MAX_PATH, L"%sproton-update-windows-%lu", temp,
             (unsigned long)GetCurrentProcessId());
  if (!CreateDirectoryW(root, NULL)) {
    fail("failed to create the test directory");
  }
  wchar_t executable[MAX_PATH];
  wchar_t uninstaller[MAX_PATH];
  wchar_t revision[MAX_PATH];
  _snwprintf(executable, MAX_PATH, L"%s\\Demo.exe", root);
  _snwprintf(uninstaller, MAX_PATH, L"%s\\Uninstall.exe", root);
  _snwprintf(revision, MAX_PATH, L"%s\\proton-update-revision", root);
  write_text(executable, "application");
  write_text(uninstaller, "uninstaller");
  write_text(revision, "1\n");
  char executable_utf8[MAX_PATH * 3];
  char root_utf8[MAX_PATH * 3];
  to_utf8(executable, executable_utf8, (int)sizeof(executable_utf8));
  to_utf8(root, root_utf8, (int)sizeof(root_utf8));
  proton_update_set_current_bundle_for_testing(executable_utf8);

  char error[512] = {0};
  proton_update_stage_id_t stage = PROTON_INVALID_HANDLE;
  const char *installer = "signed-installer";
  require_status(proton_update_stage_begin_revision(
                     root_utf8, (int64_t)strlen(installer), 2, &stage, error,
                     (int32_t)sizeof(error)),
                 "stage begin failed", error);
  require_status(proton_update_stage_write(
                     stage, installer, (int32_t)strlen(installer), error,
                     (int32_t)sizeof(error)),
                 "stage write failed", error);
  int32_t outcome = -1;
  require_status(proton_update_stage_install_outcome(
                     stage, &outcome, error, (int32_t)sizeof(error)),
                 "stage install failed", error);
  if (outcome != PROTON_UPDATE_INSTALLED) {
    fail("the Windows installer was not prepared");
  }
  uint64_t current = 0;
  require_status(proton_update_current_revision(
                     &current, error, (int32_t)sizeof(error)),
                 "current revision failed", error);
  if (current != 2) {
    fail("the prepared Windows revision was not visible");
  }
  proton_update_discard_pending_for_testing();

  if (!DeleteFileW(uninstaller)) {
    fail("failed to remove the NSIS install marker");
  }
  stage = PROTON_INVALID_HANDLE;
  int32_t status = proton_update_stage_begin_revision(
      root_utf8, 1, 3, &stage, error, (int32_t)sizeof(error));
  if (status != PROTON_ERR_UNSUPPORTED) {
    fail("a portable Windows directory was accepted for self-update");
  }

  proton_update_set_current_bundle_for_testing(NULL);
  (void)DeleteFileW(executable);
  (void)DeleteFileW(revision);
  if (!RemoveDirectoryW(root)) {
    fail("failed to remove the test directory");
  }
  return 0;
}
