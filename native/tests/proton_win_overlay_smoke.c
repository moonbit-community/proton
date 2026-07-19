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
  if (process_id != GetCurrentProcessId() || !IsWindowVisible(hwnd) ||
      GetWindow(hwnd, GW_OWNER) != NULL) {
    return TRUE;
  }
  RECT rect;
  if (!GetWindowRect(hwnd, &rect)) {
    return TRUE;
  }
  largest_child_t *largest = (largest_child_t *)data;
  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  if (width * height > largest->width * largest->height) {
    largest->hwnd = hwnd;
    largest->width = width;
    largest->height = height;
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

static HWND deepest_child_from_screen_point(HWND parent, POINT screen_point) {
  HWND current = parent;
  for (;;) {
    POINT local_point = screen_point;
    if (!ScreenToClient(current, &local_point)) {
      return current;
    }
    HWND child = ChildWindowFromPointEx(
        current, local_point, CWP_SKIPDISABLED | CWP_SKIPINVISIBLE);
    if (child == NULL || child == current) {
      return current;
    }
    current = child;
  }
}

static int expect_browser_covers_client(void) {
  largest_child_t parent_window = {0};
  EnumWindows(find_process_window, (LPARAM)&parent_window);
  HWND parent = parent_window.hwnd;
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

static int expect_overlay_hit_targets(void) {
  largest_child_t parent_window = {0};
  EnumWindows(find_process_window, (LPARAM)&parent_window);
  HWND parent = parent_window.hwnd;
  if (parent == NULL) {
    fprintf(stderr, "overlay parent HWND was not found for hit testing\n");
    return 1;
  }

  RECT client;
  if (!GetClientRect(parent, &client)) {
    fprintf(stderr, "overlay client rect was unavailable for hit testing\n");
    return 1;
  }
  UINT dpi = GetDpiForWindow(parent);
  if (dpi == 0) {
    dpi = USER_DEFAULT_SCREEN_DPI;
  }
  const int padded_border =
      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int resize_border_y =
      GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded_border;
  const int caption_height = GetSystemMetricsForDpi(SM_CYCAPTION, dpi);

  POINT drag_client_point = {
      .x = GetSystemMetricsForDpi(SM_CXSIZE, dpi) / 2,
      .y = resize_border_y + caption_height / 2,
  };
  POINT content_client_point = {
      .x = (client.right - client.left) / 2,
      .y = drag_client_point.y,
  };
  POINT drag_screen_point = drag_client_point;
  POINT content_screen_point = content_client_point;
  if (!ClientToScreen(parent, &drag_screen_point) ||
      !ClientToScreen(parent, &content_screen_point)) {
    fprintf(stderr, "overlay hit-test points could not be mapped\n");
    return 1;
  }

  HWND drag_target = deepest_child_from_screen_point(parent, drag_screen_point);
  if (drag_target == NULL || drag_target == parent ||
      !IsChild(parent, drag_target)) {
    fprintf(stderr,
            "overlay drag strip is not targeting a CEF child: target=%p parent=%p\n",
            (void *)drag_target, (void *)parent);
    return 1;
  }
  LRESULT drag_hit = SendMessageW(
      drag_target, WM_NCHITTEST, 0,
      MAKELPARAM((SHORT)drag_screen_point.x, (SHORT)drag_screen_point.y));
  if (drag_hit != HTCAPTION) {
    fprintf(stderr, "overlay drag strip expected HTCAPTION, got %ld\n",
            (long)drag_hit);
    return 1;
  }

  HWND late_host =
      CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE, 0, 0, 1, 1,
                      parent, NULL, GetModuleHandleW(NULL), NULL);
  if (late_host == NULL) {
    fprintf(stderr, "overlay late host HWND could not be created\n");
    return 1;
  }
  HWND late_child =
      CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE, 0, 0, 1, 1,
                      late_host, NULL, GetModuleHandleW(NULL), NULL);
  if (late_child == NULL) {
    fprintf(stderr, "overlay late child HWND could not be created\n");
    DestroyWindow(late_host);
    return 1;
  }
  LRESULT late_child_hit = SendMessageW(
      late_child, WM_NCHITTEST, 0,
      MAKELPARAM((SHORT)drag_screen_point.x, (SHORT)drag_screen_point.y));
  DestroyWindow(late_host);
  if (late_child_hit != HTCAPTION) {
    fprintf(stderr, "overlay late child expected HTCAPTION, got %ld\n",
            (long)late_child_hit);
    return 1;
  }

  HWND content_target =
      deepest_child_from_screen_point(parent, content_screen_point);
  if (content_target == NULL || content_target == parent ||
      !IsChild(parent, content_target)) {
    fprintf(stderr,
            "overlay web content is not targeting a CEF child: target=%p parent=%p\n",
            (void *)content_target, (void *)parent);
    return 1;
  }
  LRESULT content_hit = SendMessageW(
      content_target, WM_NCHITTEST, 0,
      MAKELPARAM((SHORT)content_screen_point.x, (SHORT)content_screen_point.y));
  if (content_hit != HTCLIENT) {
    fprintf(stderr, "overlay web content expected HTCLIENT, got %ld\n",
            (long)content_hit);
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
      strstr(info, "\"platform\":\"windows\"") == NULL ||
      strstr(info, "\"titlebar_overlay\"") == NULL) {
    fprintf(stderr, "Windows engine overlay capability missing: %s\n", info);
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
  if (expect_browser_covers_client() || expect_overlay_hit_targets()) {
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
  if (expect_browser_covers_client() || expect_overlay_hit_targets()) {
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
