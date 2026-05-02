#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <direct.h>
#include <io.h>
#define CINTERFACE
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <wchar.h>
#include "../../build/_deps/microsoft_web_webview2-src/build/native/include/WebView2.h"
#ifdef _MSC_VER
#pragma comment(lib, "ole32.lib")
#endif
#else
#include <unistd.h>
#endif

#include "moonbit.h"

#ifdef _WIN32
#define EXTENSIONS_FS_WEBVIEW2_17_POST_SHARED_BUFFER_TO_SCRIPT_INDEX 116
#define EXTENSIONS_FS_ENVIRONMENT12_CREATE_SHARED_BUFFER_INDEX 24
#define EXTENSIONS_FS_SHARED_BUFFER_GET_BUFFER_INDEX 4
#define EXTENSIONS_FS_SHARED_BUFFER_CLOSE_INDEX 7
#define EXTENSIONS_FS_UNKNOWN_RELEASE_INDEX 2
#define EXTENSIONS_FS_SHARED_BUFFER_MAX_SIZE (64 * 1024 * 1024)
#define EXTENSIONS_FS_SHARED_BUFFER_ACCESS_READ_ONLY 0
#define EXTENSIONS_FS_SHARED_BUFFER_ACCESS_READ_WRITE 1

static const IID EXTENSIONS_FS_IID_ICoreWebView2_17 = {
    0x702e75d4,
    0xfd44,
    0x434d,
    {0x9d, 0x70, 0x1a, 0x68, 0xa6, 0xb1, 0x19, 0x2a}};

static const IID EXTENSIONS_FS_IID_ICoreWebView2Environment12 = {
    0xf503db9b,
    0x739f,
    0x48dd,
    {0xb1, 0x51, 0xfd, 0xfc, 0xf2, 0x53, 0xf5, 0x4e}};

typedef ULONG(STDMETHODCALLTYPE *extensions_fs_release_fn)(void *self);
typedef HRESULT(STDMETHODCALLTYPE *extensions_fs_create_shared_buffer_fn)(
    void *self, UINT64 size, void **shared_buffer);
typedef HRESULT(STDMETHODCALLTYPE *extensions_fs_shared_buffer_get_buffer_fn)(
    void *self, BYTE **buffer);
typedef HRESULT(STDMETHODCALLTYPE *extensions_fs_shared_buffer_close_fn)(void *self);
typedef HRESULT(STDMETHODCALLTYPE *extensions_fs_post_shared_buffer_to_script_fn)(
    void *self, void *shared_buffer, int access, LPCWSTR additional_data_as_json);

typedef struct {
  int64_t controller_handle;
  void *webview17;
  void *environment12;
  void *read_shared_buffer;
  BYTE *read_buffer;
  uint64_t read_capacity;
  void *write_shared_buffer;
  BYTE *write_buffer;
  uint64_t write_capacity;
  int32_t write_sequence;
} extensions_fs_shared_buffer_cache_t;

static extensions_fs_shared_buffer_cache_t extensions_fs_shared_buffer_cache = {
    0, NULL, NULL, NULL, NULL, 0, NULL, NULL, 0, 0};

static char extensions_fs_shared_buffer_error[512] = "ok";

static void extensions_fs_shared_buffer_set_ok(void) {
  snprintf(
      extensions_fs_shared_buffer_error,
      sizeof(extensions_fs_shared_buffer_error),
      "ok");
}

static HRESULT extensions_fs_shared_buffer_set_hresult(const char *step, HRESULT hr) {
  snprintf(
      extensions_fs_shared_buffer_error,
      sizeof(extensions_fs_shared_buffer_error),
      "%s failed: HRESULT 0x%08lx",
      step,
      (unsigned long)(uint32_t)hr);
  return hr;
}

static HRESULT extensions_fs_shared_buffer_set_message(
    const char *message, HRESULT hr) {
  snprintf(
      extensions_fs_shared_buffer_error,
      sizeof(extensions_fs_shared_buffer_error),
      "%s",
      message);
  return hr;
}

static int32_t extensions_fs_shared_buffer_set_errno(const char *step) {
  snprintf(
      extensions_fs_shared_buffer_error,
      sizeof(extensions_fs_shared_buffer_error),
      "%s failed: %s",
      step,
      strerror(errno));
  return -1;
}

static void **extensions_fs_shared_buffer_vtbl(void *interface_pointer) {
  return *(void ***)interface_pointer;
}

static void extensions_fs_release_unknown(void *interface_pointer) {
  if (interface_pointer == NULL) {
    return;
  }
  void **vtbl = extensions_fs_shared_buffer_vtbl(interface_pointer);
  extensions_fs_release_fn release =
      (extensions_fs_release_fn)vtbl[EXTENSIONS_FS_UNKNOWN_RELEASE_INDEX];
  release(interface_pointer);
}

static HRESULT extensions_fs_close_shared_buffer(void *shared_buffer) {
  if (shared_buffer == NULL) {
    return S_OK;
  }
  void **vtbl = extensions_fs_shared_buffer_vtbl(shared_buffer);
  extensions_fs_shared_buffer_close_fn close =
      (extensions_fs_shared_buffer_close_fn)
          vtbl[EXTENSIONS_FS_SHARED_BUFFER_CLOSE_INDEX];
  return close(shared_buffer);
}

static void extensions_fs_release_shared_buffer(void *shared_buffer) {
  if (shared_buffer == NULL) {
    return;
  }
  (void)extensions_fs_close_shared_buffer(shared_buffer);
  extensions_fs_release_unknown(shared_buffer);
}

static void extensions_fs_release_read_buffer(void) {
  extensions_fs_release_shared_buffer(
      extensions_fs_shared_buffer_cache.read_shared_buffer);
  extensions_fs_shared_buffer_cache.read_shared_buffer = NULL;
  extensions_fs_shared_buffer_cache.read_buffer = NULL;
  extensions_fs_shared_buffer_cache.read_capacity = 0;
}

static void extensions_fs_release_write_buffer(void) {
  extensions_fs_release_shared_buffer(
      extensions_fs_shared_buffer_cache.write_shared_buffer);
  extensions_fs_shared_buffer_cache.write_shared_buffer = NULL;
  extensions_fs_shared_buffer_cache.write_buffer = NULL;
  extensions_fs_shared_buffer_cache.write_capacity = 0;
  extensions_fs_shared_buffer_cache.write_sequence = 0;
}

static void extensions_fs_release_shared_buffer_cache(void) {
  extensions_fs_release_read_buffer();
  extensions_fs_release_write_buffer();
  extensions_fs_release_unknown(extensions_fs_shared_buffer_cache.environment12);
  extensions_fs_release_unknown(extensions_fs_shared_buffer_cache.webview17);
  extensions_fs_shared_buffer_cache.controller_handle = 0;
  extensions_fs_shared_buffer_cache.webview17 = NULL;
  extensions_fs_shared_buffer_cache.environment12 = NULL;
}

static HRESULT extensions_fs_create_shared_buffer(
    void *environment12, uint64_t size, void **shared_buffer) {
  void **vtbl = extensions_fs_shared_buffer_vtbl(environment12);
  extensions_fs_create_shared_buffer_fn create_shared_buffer =
      (extensions_fs_create_shared_buffer_fn)
          vtbl[EXTENSIONS_FS_ENVIRONMENT12_CREATE_SHARED_BUFFER_INDEX];
  return create_shared_buffer(environment12, (UINT64)size, shared_buffer);
}

static HRESULT extensions_fs_get_shared_buffer_bytes(
    void *shared_buffer, BYTE **buffer) {
  void **vtbl = extensions_fs_shared_buffer_vtbl(shared_buffer);
  extensions_fs_shared_buffer_get_buffer_fn get_buffer =
      (extensions_fs_shared_buffer_get_buffer_fn)
          vtbl[EXTENSIONS_FS_SHARED_BUFFER_GET_BUFFER_INDEX];
  return get_buffer(shared_buffer, buffer);
}

static HRESULT extensions_fs_post_shared_buffer(
    void *webview17,
    void *shared_buffer,
    int access,
    LPCWSTR additional_data_as_json) {
  void **vtbl = extensions_fs_shared_buffer_vtbl(webview17);
  extensions_fs_post_shared_buffer_to_script_fn post_shared_buffer =
      (extensions_fs_post_shared_buffer_to_script_fn)
          vtbl[EXTENSIONS_FS_WEBVIEW2_17_POST_SHARED_BUFFER_TO_SCRIPT_INDEX];
  return post_shared_buffer(
      webview17, shared_buffer, access, additional_data_as_json);
}

static HRESULT extensions_fs_get_core_webview(
    int64_t controller_handle, ICoreWebView2 **webview) {
  ICoreWebView2Controller *controller =
      (ICoreWebView2Controller *)(uintptr_t)controller_handle;
  if (controller == NULL) {
    return extensions_fs_shared_buffer_set_message(
        "Native controller handle is null", E_POINTER);
  }
  HRESULT hr = ICoreWebView2Controller_get_CoreWebView2(controller, webview);
  if (FAILED(hr)) {
    return extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2Controller::get_CoreWebView2", hr);
  }
  return S_OK;
}

static HRESULT extensions_fs_get_shared_buffer_interfaces(
    int64_t controller_handle, void **webview17, void **environment12) {
  ICoreWebView2 *webview = NULL;
  ICoreWebView2_3 *webview3 = NULL;
  ICoreWebView2Environment *environment = NULL;
  HRESULT hr = extensions_fs_get_core_webview(controller_handle, &webview);
  if (FAILED(hr)) {
    return hr;
  }
  hr = ICoreWebView2_QueryInterface(
      webview, &EXTENSIONS_FS_IID_ICoreWebView2_17, webview17);
  if (FAILED(hr)) {
    extensions_fs_shared_buffer_set_hresult(
        "QueryInterface(ICoreWebView2_17)", hr);
    goto cleanup;
  }
  hr = ICoreWebView2_QueryInterface(
      webview, &IID_ICoreWebView2_3, (void **)&webview3);
  if (FAILED(hr)) {
    extensions_fs_shared_buffer_set_hresult("QueryInterface(ICoreWebView2_3)", hr);
    goto cleanup;
  }
  hr = ICoreWebView2_3_get_Environment(webview3, &environment);
  if (FAILED(hr)) {
    extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2_3::get_Environment", hr);
    goto cleanup;
  }
  hr = ICoreWebView2Environment_QueryInterface(
      environment,
      &EXTENSIONS_FS_IID_ICoreWebView2Environment12,
      environment12);
  if (FAILED(hr)) {
    extensions_fs_shared_buffer_set_hresult(
        "QueryInterface(ICoreWebView2Environment12)", hr);
    goto cleanup;
  }

cleanup:
  if (FAILED(hr)) {
    extensions_fs_release_unknown(*webview17);
    extensions_fs_release_unknown(*environment12);
    *webview17 = NULL;
    *environment12 = NULL;
  }
  if (environment != NULL) {
    ICoreWebView2Environment_Release(environment);
  }
  if (webview3 != NULL) {
    ICoreWebView2_3_Release(webview3);
  }
  if (webview != NULL) {
    ICoreWebView2_Release(webview);
  }
  return hr;
}

static HRESULT extensions_fs_ensure_shared_buffer_interfaces(
    int64_t controller_handle) {
  HRESULT hr;
  if (extensions_fs_shared_buffer_cache.controller_handle == controller_handle &&
      extensions_fs_shared_buffer_cache.webview17 != NULL &&
      extensions_fs_shared_buffer_cache.environment12 != NULL) {
    return S_OK;
  }
  extensions_fs_release_shared_buffer_cache();
  hr = extensions_fs_get_shared_buffer_interfaces(
      controller_handle,
      &extensions_fs_shared_buffer_cache.webview17,
      &extensions_fs_shared_buffer_cache.environment12);
  if (FAILED(hr)) {
    extensions_fs_release_shared_buffer_cache();
    return hr;
  }
  extensions_fs_shared_buffer_cache.controller_handle = controller_handle;
  return S_OK;
}

static HRESULT extensions_fs_ensure_buffer_capacity(
    void **shared_buffer,
    BYTE **buffer,
    uint64_t *capacity,
    uint64_t size) {
  HRESULT hr;
  void *next_shared_buffer = NULL;
  BYTE *next_buffer = NULL;
  uint64_t requested = size == 0 ? 1 : size;
  if (*shared_buffer != NULL && *capacity >= requested && *buffer != NULL) {
    return S_OK;
  }
  extensions_fs_release_shared_buffer(*shared_buffer);
  *shared_buffer = NULL;
  *buffer = NULL;
  *capacity = 0;
  hr = extensions_fs_create_shared_buffer(
      extensions_fs_shared_buffer_cache.environment12,
      requested,
      &next_shared_buffer);
  if (FAILED(hr)) {
    return extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2Environment12::CreateSharedBuffer", hr);
  }
  hr = extensions_fs_get_shared_buffer_bytes(next_shared_buffer, &next_buffer);
  if (FAILED(hr)) {
    extensions_fs_release_shared_buffer(next_shared_buffer);
    return extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2SharedBuffer::get_Buffer", hr);
  }
  *shared_buffer = next_shared_buffer;
  *buffer = next_buffer;
  *capacity = requested;
  return S_OK;
}

static HRESULT extensions_fs_post_json_shared_buffer(
    void *shared_buffer,
    int access,
    const wchar_t *kind,
    int32_t sequence,
    int32_t size,
    uint64_t capacity) {
  wchar_t additional_data[256];
  int written = swprintf(
      additional_data,
      sizeof(additional_data) / sizeof(additional_data[0]),
      L"{\"kind\":\"%ls\",\"sequence\":%d,\"size\":%d,\"capacity\":%llu}",
      kind,
      sequence,
      size,
      (unsigned long long)capacity);
  if (written < 0 ||
      written >= (int)(sizeof(additional_data) / sizeof(additional_data[0]))) {
    return extensions_fs_shared_buffer_set_message(
        "SharedBuffer additional data did not fit in the fixed buffer",
        E_OUTOFMEMORY);
  }
  return extensions_fs_post_shared_buffer(
      extensions_fs_shared_buffer_cache.webview17,
      shared_buffer,
      access,
      additional_data);
}
#endif

static moonbit_bytes_t extensions_fs_make_bytes(const char *buffer, size_t len) {
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)(len + 1), 0);
  if (len > 0) {
    memcpy(result, buffer, len);
  }
  result[len] = '\0';
  return result;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t extensions_fs_last_error_message(void) {
  const char *message = strerror(errno);
  size_t len = strlen(message);
  return extensions_fs_make_bytes(message, len);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t extensions_fs_stat_json_ffi(moonbit_bytes_t path) {
  struct stat info;
  char buffer[256];
  int exists = stat((const char *)path, &info) == 0;
  long long size = 0;
  int is_file = 0;
  int is_dir = 0;
  int readonly = 0;
  int written;

  if (exists) {
    size = (long long)info.st_size;
#ifdef _WIN32
    is_dir = (info.st_mode & _S_IFDIR) != 0;
    is_file = (info.st_mode & _S_IFREG) != 0;
#else
    is_dir = S_ISDIR(info.st_mode);
    is_file = S_ISREG(info.st_mode);
#endif
    #ifdef _WIN32
    readonly = _access((const char *)path, 2) != 0;
    #else
    readonly = access((const char *)path, W_OK) != 0;
    #endif
  }

  written = snprintf(
      buffer,
      sizeof(buffer),
      "{\"exists\":%s,\"size\":%lld,\"is_file\":%s,\"is_dir\":%s,\"is_readonly\":%s}",
      exists ? "true" : "false",
      size,
      is_file ? "true" : "false",
      is_dir ? "true" : "false",
      readonly ? "true" : "false");
  if (written < 0) {
    return extensions_fs_make_bytes("", 0);
  }
  if ((size_t)written >= sizeof(buffer)) {
    written = (int)sizeof(buffer) - 1;
  }
  return extensions_fs_make_bytes(buffer, (size_t)written);
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_rename_ffi(moonbit_bytes_t old_path,
                                                    moonbit_bytes_t new_path) {
  return rename((const char *)old_path, (const char *)new_path);
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_copy_file_ffi(moonbit_bytes_t src,
                                                       moonbit_bytes_t dest,
                                                       int32_t overwrite) {
  char buffer[8192];
  FILE *src_file;
  FILE *dest_file;
  long long total = 0;
  size_t read_count;

  if (!overwrite) {
    struct stat existing;
    if (stat((const char *)dest, &existing) == 0) {
      errno = EEXIST;
      return -1;
    }
  }

  src_file = fopen((const char *)src, "rb");
  if (src_file == NULL) {
    return -1;
  }

  dest_file = fopen((const char *)dest, "wb");
  if (dest_file == NULL) {
    fclose(src_file);
    return -1;
  }

  while ((read_count = fread(buffer, 1, sizeof(buffer), src_file)) > 0) {
    if (fwrite(buffer, 1, read_count, dest_file) != read_count) {
      fclose(src_file);
      fclose(dest_file);
      return -1;
    }
    total += (long long)read_count;
  }

  if (ferror(src_file) != 0 || fflush(dest_file) != 0) {
    fclose(src_file);
    fclose(dest_file);
    return -1;
  }

  if (fclose(src_file) != 0 || fclose(dest_file) != 0) {
    return -1;
  }

  if (total > INT32_MAX) {
    errno = EFBIG;
    return -1;
  }

  return (int32_t)total;
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_append_bytes_ffi(moonbit_bytes_t path,
                                                          moonbit_bytes_t content,
                                                          int32_t content_len) {
  FILE *file = fopen((const char *)path, "ab");
  size_t written;

  if (file == NULL) {
    return -1;
  }

  written = fwrite(content, 1, (size_t)content_len, file);
  if (written != (size_t)content_len || fflush(file) != 0 || fclose(file) != 0) {
    return -1;
  }

  if (written > INT32_MAX) {
    errno = EFBIG;
    return -1;
  }

  return (int32_t)written;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t extensions_fs_realpath_ffi(moonbit_bytes_t path) {
#ifdef _WIN32
  char buffer[4096];
  if (_fullpath(buffer, (const char *)path, sizeof(buffer)) == NULL) {
    return extensions_fs_make_bytes("", 0);
  }
  return extensions_fs_make_bytes(buffer, strlen(buffer));
#else
  char buffer[PATH_MAX];
  if (realpath((const char *)path, buffer) == NULL) {
    return extensions_fs_make_bytes("", 0);
  }
  return extensions_fs_make_bytes(buffer, strlen(buffer));
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_truncate_file_ffi(moonbit_bytes_t path,
                                                           int32_t len) {
#ifdef _WIN32
  FILE *file = fopen((const char *)path, "r+b");
  int result;
  if (file == NULL) {
    return -1;
  }
  result = _chsize_s(_fileno(file), len);
  fclose(file);
  return result;
#else
  return truncate((const char *)path, len);
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_shared_buffer_probe(
    int64_t controller_handle) {
#ifdef _WIN32
  int32_t mask = 1;
  ICoreWebView2 *webview = NULL;
  ICoreWebView2_3 *webview3 = NULL;
  ICoreWebView2Environment *environment = NULL;
  void *webview17 = NULL;
  void *environment12 = NULL;
  void *shared_buffer = NULL;
  HRESULT hr;

  extensions_fs_shared_buffer_set_ok();
  if (controller_handle == 0) {
    extensions_fs_shared_buffer_set_message(
        "Native controller handle is null", E_POINTER);
    return mask;
  }
  mask |= 2;
  hr = extensions_fs_get_core_webview(controller_handle, &webview);
  if (FAILED(hr)) {
    return mask;
  }
  mask |= 4;
  hr = ICoreWebView2_QueryInterface(
      webview, &EXTENSIONS_FS_IID_ICoreWebView2_17, &webview17);
  if (SUCCEEDED(hr)) {
    mask |= 8;
  } else {
    extensions_fs_shared_buffer_set_hresult(
        "QueryInterface(ICoreWebView2_17)", hr);
  }
  hr = ICoreWebView2_QueryInterface(
      webview, &IID_ICoreWebView2_3, (void **)&webview3);
  if (SUCCEEDED(hr)) {
    hr = ICoreWebView2_3_get_Environment(webview3, &environment);
  }
  if (SUCCEEDED(hr)) {
    hr = ICoreWebView2Environment_QueryInterface(
        environment,
        &EXTENSIONS_FS_IID_ICoreWebView2Environment12,
        &environment12);
    if (SUCCEEDED(hr)) {
      mask |= 16;
      hr = extensions_fs_create_shared_buffer(environment12, 16, &shared_buffer);
      if (SUCCEEDED(hr)) {
        mask |= 32;
      } else {
        extensions_fs_shared_buffer_set_hresult(
            "ICoreWebView2Environment12::CreateSharedBuffer", hr);
      }
    } else {
      extensions_fs_shared_buffer_set_hresult(
          "QueryInterface(ICoreWebView2Environment12)", hr);
    }
  } else {
    extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2_3::get_Environment", hr);
  }
  if ((mask & (8 | 16 | 32)) == (8 | 16 | 32)) {
    extensions_fs_shared_buffer_set_ok();
  }
  extensions_fs_release_shared_buffer(shared_buffer);
  extensions_fs_release_unknown(environment12);
  if (environment != NULL) {
    ICoreWebView2Environment_Release(environment);
  }
  if (webview3 != NULL) {
    ICoreWebView2_3_Release(webview3);
  }
  extensions_fs_release_unknown(webview17);
  if (webview != NULL) {
    ICoreWebView2_Release(webview);
  }
  return mask;
#else
  (void)controller_handle;
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_shared_buffer_publish_read(
    int64_t controller_handle,
    moonbit_bytes_t payload,
    int32_t size,
    int32_t sequence) {
#ifdef _WIN32
  HRESULT hr;

  extensions_fs_shared_buffer_set_ok();
  if (payload == NULL && size > 0) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer read payload is null", E_POINTER);
  }
  if (size < 0 || size > EXTENSIONS_FS_SHARED_BUFFER_MAX_SIZE) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer read size is outside the transfer limit", E_INVALIDARG);
  }
  hr = extensions_fs_ensure_shared_buffer_interfaces(controller_handle);
  if (FAILED(hr)) {
    return (int32_t)hr;
  }
  hr = extensions_fs_ensure_buffer_capacity(
      &extensions_fs_shared_buffer_cache.read_shared_buffer,
      &extensions_fs_shared_buffer_cache.read_buffer,
      &extensions_fs_shared_buffer_cache.read_capacity,
      (uint64_t)(uint32_t)size);
  if (FAILED(hr)) {
    return (int32_t)hr;
  }
  if (size > 0) {
    memcpy(
        extensions_fs_shared_buffer_cache.read_buffer,
        payload,
        (size_t)(uint32_t)size);
  }
  hr = extensions_fs_post_json_shared_buffer(
      extensions_fs_shared_buffer_cache.read_shared_buffer,
      EXTENSIONS_FS_SHARED_BUFFER_ACCESS_READ_ONLY,
      L"lepus-fs-read-buffer",
      sequence,
      size,
      extensions_fs_shared_buffer_cache.read_capacity);
  if (FAILED(hr)) {
    return (int32_t)extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2_17::PostSharedBufferToScript(read)", hr);
  }
  extensions_fs_shared_buffer_set_ok();
  return 0;
#else
  (void)controller_handle;
  (void)payload;
  (void)size;
  (void)sequence;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_shared_buffer_prepare_write(
    int64_t controller_handle,
    int32_t size,
    int32_t sequence) {
#ifdef _WIN32
  HRESULT hr;

  extensions_fs_shared_buffer_set_ok();
  if (size < 0 || size > EXTENSIONS_FS_SHARED_BUFFER_MAX_SIZE) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer write size is outside the transfer limit", E_INVALIDARG);
  }
  hr = extensions_fs_ensure_shared_buffer_interfaces(controller_handle);
  if (FAILED(hr)) {
    return (int32_t)hr;
  }
  hr = extensions_fs_ensure_buffer_capacity(
      &extensions_fs_shared_buffer_cache.write_shared_buffer,
      &extensions_fs_shared_buffer_cache.write_buffer,
      &extensions_fs_shared_buffer_cache.write_capacity,
      (uint64_t)(uint32_t)size);
  if (FAILED(hr)) {
    return (int32_t)hr;
  }
  if (extensions_fs_shared_buffer_cache.write_capacity > 0) {
    memset(
        extensions_fs_shared_buffer_cache.write_buffer,
        0,
        (size_t)extensions_fs_shared_buffer_cache.write_capacity);
  }
  extensions_fs_shared_buffer_cache.write_sequence = sequence;
  hr = extensions_fs_post_json_shared_buffer(
      extensions_fs_shared_buffer_cache.write_shared_buffer,
      EXTENSIONS_FS_SHARED_BUFFER_ACCESS_READ_WRITE,
      L"lepus-fs-write-buffer",
      sequence,
      size,
      extensions_fs_shared_buffer_cache.write_capacity);
  if (FAILED(hr)) {
    return (int32_t)extensions_fs_shared_buffer_set_hresult(
        "ICoreWebView2_17::PostSharedBufferToScript(write)", hr);
  }
  extensions_fs_shared_buffer_set_ok();
  return 0;
#else
  (void)controller_handle;
  (void)size;
  (void)sequence;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int32_t extensions_fs_shared_buffer_commit_write(
    int32_t sequence,
    int32_t size,
    moonbit_bytes_t path,
    int32_t flush) {
#ifdef _WIN32
  FILE *file;
  size_t written;
  int close_result;
  (void)flush;

  extensions_fs_shared_buffer_set_ok();
  if (path == NULL) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer write path is null", E_POINTER);
  }
  if (sequence != extensions_fs_shared_buffer_cache.write_sequence ||
      extensions_fs_shared_buffer_cache.write_buffer == NULL) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer write sequence is not prepared", E_INVALIDARG);
  }
  if (size < 0 ||
      (uint64_t)(uint32_t)size >
          extensions_fs_shared_buffer_cache.write_capacity) {
    return (int32_t)extensions_fs_shared_buffer_set_message(
        "SharedBuffer write size exceeds prepared capacity", E_INVALIDARG);
  }
  file = fopen((const char *)path, "wb");
  if (file == NULL) {
    return extensions_fs_shared_buffer_set_errno("fopen");
  }
  written = fwrite(
      extensions_fs_shared_buffer_cache.write_buffer,
      1,
      (size_t)(uint32_t)size,
      file);
  if (written != (size_t)(uint32_t)size) {
    fclose(file);
    return extensions_fs_shared_buffer_set_errno("fwrite");
  }
  if (fflush(file) != 0) {
    fclose(file);
    return extensions_fs_shared_buffer_set_errno("fflush");
  }
  close_result = fclose(file);
  if (close_result != 0) {
    return extensions_fs_shared_buffer_set_errno("fclose");
  }
  return 0;
#else
  (void)sequence;
  (void)size;
  (void)path;
  (void)flush;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t extensions_fs_shared_buffer_last_error(void) {
  const char *message =
#ifdef _WIN32
      extensions_fs_shared_buffer_error;
#else
      "fs SharedArrayBuffer transfer is Windows/WebView2-only";
#endif
  size_t len = strlen(message);
  return extensions_fs_make_bytes(message, len);
}

MOONBIT_FFI_EXPORT void extensions_fs_shared_buffer_release(void) {
#ifdef _WIN32
  extensions_fs_release_shared_buffer_cache();
  extensions_fs_shared_buffer_set_ok();
#endif
}

#ifdef __cplusplus
}
#endif
