#include "proton_native.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int expect_status(const char *label, int32_t actual, int32_t expected) {
  if (actual == expected) {
    return 0;
  }
  fprintf(stderr, "%s: expected %d, got %d\n", label, expected, actual);
  return 1;
}

static int build_engine_config(char *config, size_t config_len) {
  const char *engine_root = getenv("PROTON_TEST_ENGINE_ROOT");
  const char *helper_path = getenv("PROTON_TEST_HELPER_PATH");
  const char *cache_root = getenv("PROTON_TEST_CACHE_ROOT");
  if (engine_root == NULL || helper_path == NULL || cache_root == NULL) {
    fprintf(stderr, "real engine test paths are missing\n");
    return 1;
  }
  char normalized_root[MAX_PATH];
  char normalized_helper[MAX_PATH];
  char normalized_cache[MAX_PATH];
  snprintf(normalized_root, sizeof(normalized_root), "%s", engine_root);
  snprintf(normalized_helper, sizeof(normalized_helper), "%s", helper_path);
  snprintf(normalized_cache, sizeof(normalized_cache), "%s/%lu", cache_root,
           (unsigned long)GetCurrentProcessId());
  for (char *cursor = normalized_root; *cursor != '\0'; cursor++) {
    if (*cursor == '\\') {
      *cursor = '/';
    }
  }
  for (char *cursor = normalized_helper; *cursor != '\0'; cursor++) {
    if (*cursor == '\\') {
      *cursor = '/';
    }
  }
  for (char *cursor = normalized_cache; *cursor != '\0'; cursor++) {
    if (*cursor == '\\') {
      *cursor = '/';
    }
  }
  const int required = snprintf(
      config, config_len,
      "{\"abi_version\":1,\"runtime_root\":\"%s\","
      "\"helper_path\":\"%s\",\"cache_dir\":\"%s\"}",
      normalized_root, normalized_helper, normalized_cache);
  if (required < 0 || (size_t)required >= config_len) {
    fprintf(stderr, "real engine test config is too large\n");
    return 1;
  }
  return 0;
}

typedef struct {
  HWND hwnd;
  LONG width;
  LONG height;
} largest_child_t;

static BOOL CALLBACK find_process_window(HWND hwnd, LPARAM data) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == GetCurrentProcessId() && GetWindow(hwnd, GW_OWNER) == NULL) {
    *(HWND *)data = hwnd;
    return FALSE;
  }
  return TRUE;
}

static BOOL CALLBACK find_largest_visible_child(HWND child, LPARAM data) {
  if (!IsWindowVisible(child)) {
    return TRUE;
  }
  RECT rect;
  if (!GetWindowRect(child, &rect)) {
    return TRUE;
  }
  largest_child_t *largest = (largest_child_t *)data;
  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  if (width * height > largest->width * largest->height) {
    largest->hwnd = child;
    largest->width = width;
    largest->height = height;
  }
  return TRUE;
}

static int expect_browser_covers_client(void) {
  HWND parent = NULL;
  EnumWindows(find_process_window, (LPARAM)&parent);
  if (parent == NULL) {
    fprintf(stderr, "overlay parent HWND was not found\n");
    return 1;
  }
  RECT client;
  if (!GetClientRect(parent, &client)) {
    fprintf(stderr, "overlay parent client rect was unavailable\n");
    return 1;
  }
  largest_child_t largest = {0};
  EnumChildWindows(parent, find_largest_visible_child, (LPARAM)&largest);
  const LONG client_width = client.right - client.left;
  const LONG client_height = client.bottom - client.top;
  const LONG width_delta = largest.width - client_width;
  const LONG height_delta = largest.height - client_height;
  if (largest.hwnd == NULL || width_delta < -1 || width_delta > 1 ||
      height_delta < -1 || height_delta > 1) {
    fprintf(stderr,
            "CEF child does not cover client: client=%ldx%ld child=%ldx%ld\n",
            client_width, client_height, largest.width, largest.height);
    return 1;
  }
  return 0;
}

int main(void) {
  char info[256];
  int32_t required = 0;
  if (expect_status("runtime_info",
                    proton_runtime_info_json(info, (int32_t)sizeof(info),
                                             &required),
                    PROTON_OK)) {
    return 1;
  }
  if (strstr(info, "\"runtime_available\":true") == NULL ||
      strstr(info, "\"platform\":\"windows\"") == NULL) {
    fprintf(stderr, "Windows engine runtime metadata missing: %s\n", info);
    return 1;
  }

  char engine_config[MAX_PATH * 3 + 128];
  if (build_engine_config(engine_config, sizeof(engine_config))) {
    return 1;
  }

  int32_t exit_code = -1;
  if (expect_status("execute_process",
                    proton_execute_process(engine_config, &exit_code),
                    PROTON_OK) ||
      exit_code >= 0) {
    fprintf(stderr, "main process was unexpectedly handled: %d\n", exit_code);
    return 1;
  }

  proton_runtime_id_t runtime = PROTON_INVALID_HANDLE;
  if (expect_status("runtime_create",
                    proton_runtime_create_json(engine_config, &runtime),
                    PROTON_OK)) {
    return 1;
  }

  proton_window_id_t window = PROTON_INVALID_HANDLE;
  if (expect_status(
          "overlay window_create",
          proton_window_create_json(
              runtime,
              "{\"abi_version\":1,\"title\":\"Windows Overlay Smoke\","
              "\"width\":640,\"height\":480,"
              "\"titlebar_style\":\"overlay\"}",
              &window),
          PROTON_OK)) {
    proton_runtime_destroy(runtime);
    return 1;
  }

  if (expect_browser_covers_client()) {
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }

  if (expect_status("overlay window_show", proton_window_show(window),
                    PROTON_OK) ||
      expect_status("overlay window_set_size",
                    proton_window_set_size(window, 720, 520), PROTON_OK) ||
      expect_status("overlay message_loop_work",
                    proton_runtime_do_message_loop_work(runtime), PROTON_OK)) {
    return 1;
  }
  if (expect_browser_covers_client()) {
    proton_window_destroy(window);
    proton_runtime_destroy(runtime);
    return 1;
  }
  if (expect_status("overlay window_destroy", proton_window_destroy(window),
                    PROTON_OK) ||
      expect_status("overlay runtime_destroy",
                    proton_runtime_destroy(runtime), PROTON_OK)) {
    return 1;
  }
  return 0;
}
