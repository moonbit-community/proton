#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
typedef HMODULE proton_library_t;
#define PROTON_LIBRARY_NAME "proton.dll"
static proton_library_t proton_open_library(void) {
  return LoadLibraryA(PROTON_LIBRARY_NAME);
}
static void *proton_find_symbol(proton_library_t library, const char *name) {
  return (void *)GetProcAddress(library, name);
}
static void proton_close_library(proton_library_t library) {
  if (library != NULL) {
    FreeLibrary(library);
  }
}
static void proton_print_loader_error(void) {
  fprintf(stderr, "LoadLibraryA(%s) failed with error %lu\n",
          PROTON_LIBRARY_NAME, (unsigned long)GetLastError());
}
#else
#include <dlfcn.h>
typedef void *proton_library_t;
#if defined(__APPLE__)
#define PROTON_LIBRARY_NAME "libproton.dylib"
#else
#define PROTON_LIBRARY_NAME "libproton.so"
#endif
static proton_library_t proton_open_library(void) {
  return dlopen(PROTON_LIBRARY_NAME, RTLD_NOW | RTLD_LOCAL);
}
static void *proton_find_symbol(proton_library_t library, const char *name) {
  return dlsym(library, name);
}
static void proton_close_library(proton_library_t library) {
  if (library != NULL) {
    dlclose(library);
  }
}
static void proton_print_loader_error(void) {
  const char *message = dlerror();
  fprintf(stderr, "dlopen(%s) failed: %s\n", PROTON_LIBRARY_NAME,
          message != NULL ? message : "unknown error");
}
#endif

static const char *const expected_exports[] = {
    "proton_abi_version",
    "proton_runtime_info_json",
    "proton_execute_process",
    "proton_runtime_probe_json",
    "proton_runtime_create_json",
    "proton_runtime_destroy",
    "proton_runtime_run",
    "proton_runtime_quit",
    "proton_runtime_do_message_loop_work",
    "proton_runtime_wait",
    "proton_runtime_poll_event_json",
    "proton_runtime_poll_bridge_request_json",
    "proton_runtime_respond_bridge_request_json",
    "proton_window_create_json",
    "proton_window_destroy",
    "proton_window_show",
    "proton_window_hide",
    "proton_window_close",
    "proton_window_focus",
    "proton_window_set_title",
    "proton_window_set_size",
    "proton_window_load_url",
    "proton_window_load_html",
    "proton_window_eval",
    "proton_window_install_bridge_json",
    "proton_window_show_message_dialog",
    "proton_window_show_confirm_dialog",
    "proton_window_open_file_dialog",
    "proton_window_save_file_dialog",
    "proton_last_error_message",
};

static const char *const removed_exports[] = {
    "proton_available",
    "proton_window_init_script",
};

int main(void) {
  proton_library_t library = proton_open_library();
  if (library == NULL) {
    proton_print_loader_error();
    return 1;
  }

  int failed = 0;
  for (size_t i = 0; i < sizeof(expected_exports) / sizeof(expected_exports[0]);
       i++) {
    const char *name = expected_exports[i];
    if (proton_find_symbol(library, name) == NULL) {
      fprintf(stderr, "missing expected export: %s\n", name);
      failed = 1;
    }
  }

  for (size_t i = 0; i < sizeof(removed_exports) / sizeof(removed_exports[0]);
       i++) {
    const char *name = removed_exports[i];
    if (proton_find_symbol(library, name) != NULL) {
      fprintf(stderr, "removed export is still present: %s\n", name);
      failed = 1;
    }
  }

  proton_close_library(library);
  return failed;
}
