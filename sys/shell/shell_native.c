#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#ifdef _MSC_VER
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")
#endif
#else
#include <stdio.h>
#endif

#ifdef __APPLE__
#include <objc/objc.h>
#include <objc/message.h>
#include <objc/runtime.h>
#endif

MOONBIT_FFI_EXPORT int32_t mb_shell_is_supported(void) {
#if defined(_WIN32) || defined(__APPLE__) || defined(__linux__)
  return 1;
#else
  return 0;
#endif
}

#ifdef _WIN32
static wchar_t *mb_shell_utf8_to_wide(const moonbit_bytes_t path);
#endif

MOONBIT_FFI_EXPORT int32_t mb_shell_open(moonbit_bytes_t target) {
#ifdef _WIN32
  wchar_t *wide = mb_shell_utf8_to_wide(target);
  if (wide == NULL) return 0;
  HINSTANCE result = ShellExecuteW(NULL, L"open", wide, NULL, NULL, SW_SHOWNORMAL);
  free(wide);
  return (INT_PTR)result > 32;
#else
  (void)target;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_shell_reveal_item(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *target = mb_shell_utf8_to_wide(path);
  if (target == NULL) return 0;
  size_t target_len = wcslen(target);
  size_t prefix_len = wcslen(L"/select,\"");
  size_t total_len = prefix_len + target_len + 2;
  wchar_t *parameters = (wchar_t *)malloc((total_len + 1) * sizeof(wchar_t));
  if (parameters == NULL) {
    free(target);
    return 0;
  }
  wcscpy(parameters, L"/select,\"");
  wcscat(parameters, target);
  wcscat(parameters, L"\"");
  HINSTANCE result = ShellExecuteW(
      NULL, L"open", L"explorer.exe", parameters, NULL, SW_SHOWNORMAL);
  free(parameters);
  free(target);
  return (INT_PTR)result > 32;
#else
  (void)path;
  return 0;
#endif
}

#ifdef __APPLE__
/* Moves an item to the macOS Trash through the Cocoa `NSFileManager` API,
   preserving the ability to "Put Back" the item. The call is dispatched over
   the public Objective-C runtime so it stays in a plain C source file. */
static int32_t mb_shell_trash_item_apple(const char *path) {
  id pool = ((id(*)(id, SEL))objc_msgSend)(
      (id)objc_getClass("NSAutoreleasePool"), sel_registerName("new"));
  int32_t ok = 0;
  Class nsString = objc_getClass("NSString");
  Class nsURL = objc_getClass("NSURL");
  if (nsString != NULL && nsURL != NULL) {
    id pathStr = ((id(*)(id, SEL, const char *))objc_msgSend)(
        (id)nsString, sel_registerName("stringWithUTF8String:"), path);
    if (pathStr != NULL) {
      id url = ((id(*)(id, SEL, id))objc_msgSend)(
          (id)nsURL, sel_registerName("fileURLWithPath:"), pathStr);
      id fm = ((id(*)(id, SEL))objc_msgSend)(
          (id)objc_getClass("NSFileManager"),
          sel_registerName("defaultManager"));
      id err = NULL;
      BOOL result = ((BOOL(*)(id, SEL, id, id, id *))objc_msgSend)(
          fm, sel_registerName("trashItemAtURL:resultingItemURL:error:"), url,
          NULL, &err);
      ok = result ? 1 : 0;
    }
  }
  ((void(*)(id, SEL))objc_msgSend)(pool, sel_registerName("drain"));
  return ok;
}
#endif

#ifdef _WIN32
/* Converts a UTF-8 path from the MoonBit side into a UTF-16 buffer that the
   recycle-bin APIs require. Returns a heap allocation the caller must free. */
static wchar_t *mb_shell_utf8_to_wide(const moonbit_bytes_t path) {
  const char *utf8 = (const char *)path;
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (len <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)malloc((size_t)len * sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, len) <= 0) {
    free(wide);
    return NULL;
  }
  return wide;
}

/* Moves an item to the Windows Recycle Bin so it can still be restored. */
static int32_t mb_shell_trash_item_windows(const moonbit_bytes_t path) {
  wchar_t *target = mb_shell_utf8_to_wide(path);
  if (target == NULL) {
    return 0;
  }
  size_t len = wcslen(target);
  wchar_t *from = (wchar_t *)malloc((len + 2) * sizeof(wchar_t));
  if (from == NULL) {
    free(target);
    return 0;
  }
  wcscpy(from, target);
  from[len] = L'\0';
  from[len + 1] = L'\0';

  SHFILEOPSTRUCTW op;
  memset(&op, 0, sizeof(op));
  op.hwnd = NULL;
  op.wFunc = FO_DELETE;
  op.pFrom = from;
  op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

  int rc = SHFileOperationW(&op);
  int deleted = (rc == 0 && !(op.fAnyOperationsAborted));
  free(from);
  free(target);
  return deleted;
}
#endif

MOONBIT_FFI_EXPORT int32_t mb_shell_trash_item(moonbit_bytes_t path) {
#ifdef _WIN32
  return mb_shell_trash_item_windows(path);
#elif defined(__APPLE__)
  return mb_shell_trash_item_apple((const char *)path);
#else
  (void)path;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_shell_beep(void) {
#ifdef _WIN32
  MessageBeep((UINT)-1);
  return 1;
#else
  /* Playing the default alert sound. A terminal bell is the portable POSIX
     approximation; the byte is written to stderr so it is harmless in a
     GUI-only windowed process. */
  fprintf(stderr, "\a");
  fflush(stderr);
  return 1;
#endif
}
