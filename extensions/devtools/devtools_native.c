#include <stdint.h>

#include "moonbit.h"

#ifdef _WIN32
#define CINTERFACE
#define COBJMACROS
#include <windows.h>
#include "../../build/_deps/microsoft_web_webview2-src/build/native/include/WebView2.h"
#endif

#define EXTENSIONS_DEVTOOLS_OPEN_OK 0
#define EXTENSIONS_DEVTOOLS_OPEN_UNSUPPORTED 1
#define EXTENSIONS_DEVTOOLS_OPEN_INVALID_HANDLE 2
#define EXTENSIONS_DEVTOOLS_OPEN_GET_WEBVIEW_FAILED 3
#define EXTENSIONS_DEVTOOLS_OPEN_FAILED 4

MOONBIT_FFI_EXPORT int32_t extensions_devtools_is_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_devtools_open(int64_t browser_handle) {
#ifdef _WIN32
  ICoreWebView2Controller *controller =
      (ICoreWebView2Controller *)(uintptr_t)browser_handle;
  ICoreWebView2 *webview = NULL;
  HRESULT hr;

  if (controller == NULL) {
    return EXTENSIONS_DEVTOOLS_OPEN_INVALID_HANDLE;
  }

  hr = ICoreWebView2Controller_get_CoreWebView2(controller, &webview);
  if (FAILED(hr) || webview == NULL) {
    return EXTENSIONS_DEVTOOLS_OPEN_GET_WEBVIEW_FAILED;
  }

  hr = ICoreWebView2_OpenDevToolsWindow(webview);
  ICoreWebView2_Release(webview);
  return SUCCEEDED(hr) ? EXTENSIONS_DEVTOOLS_OPEN_OK
                       : EXTENSIONS_DEVTOOLS_OPEN_FAILED;
#else
  (void)browser_handle;
  return EXTENSIONS_DEVTOOLS_OPEN_UNSUPPORTED;
#endif
}
