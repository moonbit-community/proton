#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

static void package_icon_error(char *buffer, int32_t buffer_length,
                               const char *message) {
  if (buffer == NULL || buffer_length <= 0) {
    return;
  }
  snprintf(buffer, (size_t)buffer_length, "%s", message);
}

#ifdef _WIN32
#include <windows.h>

enum {
  PACKAGE_ICON_OK = 0,
  PACKAGE_ICON_INVALID_ARGUMENT = -1,
  PACKAGE_ICON_IO_ERROR = -2,
  PACKAGE_ICON_INVALID_FORMAT = -3,
  PACKAGE_ICON_WINDOWS_ERROR = -4,
  PACKAGE_ICON_OUT_OF_MEMORY = -5,
};

static uint16_t package_icon_u16(const uint8_t *data) {
  return (uint16_t)(data[0] | ((uint16_t)data[1] << 8));
}

static uint32_t package_icon_u32(const uint8_t *data) {
  return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
         ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static void package_icon_write_u16(uint8_t *data, uint16_t value) {
  data[0] = (uint8_t)(value & 0xff);
  data[1] = (uint8_t)(value >> 8);
}

static void package_icon_write_u32(uint8_t *data, uint32_t value) {
  data[0] = (uint8_t)(value & 0xff);
  data[1] = (uint8_t)((value >> 8) & 0xff);
  data[2] = (uint8_t)((value >> 16) & 0xff);
  data[3] = (uint8_t)((value >> 24) & 0xff);
}

static void package_icon_windows_error(char *buffer, int32_t buffer_length,
                                       const char *operation,
                                       DWORD error_code) {
  if (buffer == NULL || buffer_length <= 0) {
    return;
  }
  char system_message[512] = {0};
  DWORD length = FormatMessageA(
      FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL,
      error_code, 0, system_message, (DWORD)sizeof(system_message), NULL);
  while (length > 0 &&
         (system_message[length - 1] == '\r' ||
          system_message[length - 1] == '\n' ||
          system_message[length - 1] == ' ')) {
    system_message[--length] = '\0';
  }
  if (length > 0) {
    snprintf(buffer, (size_t)buffer_length, "%s failed (Windows error %lu): %s",
             operation, (unsigned long)error_code, system_message);
  } else {
    snprintf(buffer, (size_t)buffer_length, "%s failed (Windows error %lu)",
             operation, (unsigned long)error_code);
  }
}

static wchar_t *package_icon_utf8_path(const uint8_t *path, int32_t length,
                                       char *error_buffer,
                                       int32_t error_buffer_length) {
  if (path == NULL || length <= 0) {
    package_icon_error(error_buffer, error_buffer_length,
                       "path must not be empty");
    return NULL;
  }
  int wide_length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        (const char *)path, length, NULL, 0);
  if (wide_length <= 0) {
    package_icon_windows_error(error_buffer, error_buffer_length,
                               "decode UTF-8 path", GetLastError());
    return NULL;
  }
  wchar_t *wide =
      (wchar_t *)calloc((size_t)wide_length + 1, sizeof(wchar_t));
  if (wide == NULL) {
    package_icon_error(error_buffer, error_buffer_length, "out of memory");
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                          (const char *)path, length, wide,
                          wide_length) != wide_length) {
    DWORD error_code = GetLastError();
    free(wide);
    package_icon_windows_error(error_buffer, error_buffer_length,
                               "decode UTF-8 path", error_code);
    return NULL;
  }
  return wide;
}

static uint8_t *package_icon_read_file(const wchar_t *path, size_t *size,
                                       char *error_buffer,
                                       int32_t error_buffer_length) {
  FILE *file = _wfopen(path, L"rb");
  if (file == NULL) {
    package_icon_error(error_buffer, error_buffer_length,
                       "failed to open Windows icon file");
    return NULL;
  }
  if (_fseeki64(file, 0, SEEK_END) != 0) {
    fclose(file);
    package_icon_error(error_buffer, error_buffer_length,
                       "failed to inspect Windows icon file");
    return NULL;
  }
  __int64 length = _ftelli64(file);
  if (length <= 0 || (uint64_t)length > SIZE_MAX) {
    fclose(file);
    package_icon_error(error_buffer, error_buffer_length,
                       "Windows icon file is empty or too large");
    return NULL;
  }
  rewind(file);
  uint8_t *data = (uint8_t *)malloc((size_t)length);
  if (data == NULL) {
    fclose(file);
    package_icon_error(error_buffer, error_buffer_length, "out of memory");
    return NULL;
  }
  if (fread(data, 1, (size_t)length, file) != (size_t)length) {
    free(data);
    fclose(file);
    package_icon_error(error_buffer, error_buffer_length,
                       "failed to read Windows icon file");
    return NULL;
  }
  fclose(file);
  *size = (size_t)length;
  return data;
}

static int package_icon_validate(const uint8_t *data, size_t size,
                                 uint16_t *count, char *error_buffer,
                                 int32_t error_buffer_length) {
  if (size < 6 || package_icon_u16(data) != 0 ||
      package_icon_u16(data + 2) != 1) {
    package_icon_error(error_buffer, error_buffer_length,
                       "invalid Windows ICO header");
    return 0;
  }
  uint16_t image_count = package_icon_u16(data + 4);
  if (image_count == 0 ||
      (size_t)image_count > (SIZE_MAX - 6) / 16 ||
      6 + (size_t)image_count * 16 > size) {
    package_icon_error(error_buffer, error_buffer_length,
                       "invalid Windows ICO directory");
    return 0;
  }
  for (uint32_t index = 0; index < image_count; index++) {
    const uint8_t *entry = data + 6 + (size_t)index * 16;
    uint32_t image_size = package_icon_u32(entry + 8);
    uint32_t image_offset = package_icon_u32(entry + 12);
    if (image_size == 0 || image_offset > size ||
        image_size > size - image_offset) {
      package_icon_error(error_buffer, error_buffer_length,
                         "Windows ICO image lies outside the file");
      return 0;
    }
  }
  *count = image_count;
  return 1;
}

static int32_t package_icon_update_resources(
    const wchar_t *executable, const uint8_t *icon_data, uint16_t image_count,
    char *error_buffer, int32_t error_buffer_length) {
  HANDLE update = BeginUpdateResourceW(executable, FALSE);
  if (update == NULL) {
    package_icon_windows_error(error_buffer, error_buffer_length,
                               "BeginUpdateResourceW", GetLastError());
    return PACKAGE_ICON_WINDOWS_ERROR;
  }

  size_t group_size = 6 + (size_t)image_count * 14;
  uint8_t *group = (uint8_t *)calloc(group_size, 1);
  if (group == NULL) {
    EndUpdateResourceW(update, TRUE);
    package_icon_error(error_buffer, error_buffer_length, "out of memory");
    return PACKAGE_ICON_OUT_OF_MEMORY;
  }
  package_icon_write_u16(group + 2, 1);
  package_icon_write_u16(group + 4, image_count);

  WORD language = MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL);
  for (uint32_t index = 0; index < image_count; index++) {
    const uint8_t *source = icon_data + 6 + (size_t)index * 16;
    uint8_t *target = group + 6 + (size_t)index * 14;
    uint16_t resource_id = (uint16_t)(index + 1);
    uint32_t image_size = package_icon_u32(source + 8);
    uint32_t image_offset = package_icon_u32(source + 12);
    memcpy(target, source, 8);
    package_icon_write_u32(target + 8, image_size);
    package_icon_write_u16(target + 12, resource_id);
    if (!UpdateResourceW(update, RT_ICON, MAKEINTRESOURCEW(resource_id),
                         language, (void *)(icon_data + image_offset),
                         image_size)) {
      DWORD error_code = GetLastError();
      free(group);
      EndUpdateResourceW(update, TRUE);
      package_icon_windows_error(error_buffer, error_buffer_length,
                                 "UpdateResourceW(RT_ICON)", error_code);
      return PACKAGE_ICON_WINDOWS_ERROR;
    }
  }

  if (!UpdateResourceW(update, RT_GROUP_ICON, MAKEINTRESOURCEW(1), language,
                       group, (DWORD)group_size)) {
    DWORD error_code = GetLastError();
    free(group);
    EndUpdateResourceW(update, TRUE);
    package_icon_windows_error(error_buffer, error_buffer_length,
                               "UpdateResourceW(RT_GROUP_ICON)", error_code);
    return PACKAGE_ICON_WINDOWS_ERROR;
  }
  free(group);
  if (!EndUpdateResourceW(update, FALSE)) {
    package_icon_windows_error(error_buffer, error_buffer_length,
                               "EndUpdateResourceW", GetLastError());
    return PACKAGE_ICON_WINDOWS_ERROR;
  }
  return PACKAGE_ICON_OK;
}
#endif

MOONBIT_FFI_EXPORT int32_t proton_package_set_windows_executable_icon(
    moonbit_bytes_t executable, int32_t executable_length,
    moonbit_bytes_t icon, int32_t icon_length, char *error_buffer,
    int32_t error_buffer_length) {
  package_icon_error(error_buffer, error_buffer_length, "");
#ifdef _WIN32
  if (executable == NULL || icon == NULL || executable_length <= 0 ||
      icon_length <= 0) {
    package_icon_error(error_buffer, error_buffer_length,
                       "executable and icon paths are required");
    return PACKAGE_ICON_INVALID_ARGUMENT;
  }
  wchar_t *wide_executable = package_icon_utf8_path(
      executable, executable_length, error_buffer, error_buffer_length);
  if (wide_executable == NULL) {
    return PACKAGE_ICON_INVALID_ARGUMENT;
  }
  wchar_t *wide_icon = package_icon_utf8_path(
      icon, icon_length, error_buffer, error_buffer_length);
  if (wide_icon == NULL) {
    free(wide_executable);
    return PACKAGE_ICON_INVALID_ARGUMENT;
  }
  size_t icon_size = 0;
  uint8_t *icon_data = package_icon_read_file(
      wide_icon, &icon_size, error_buffer, error_buffer_length);
  free(wide_icon);
  if (icon_data == NULL) {
    free(wide_executable);
    return PACKAGE_ICON_IO_ERROR;
  }
  uint16_t image_count = 0;
  if (!package_icon_validate(icon_data, icon_size, &image_count, error_buffer,
                             error_buffer_length)) {
    free(icon_data);
    free(wide_executable);
    return PACKAGE_ICON_INVALID_FORMAT;
  }
  int32_t status = package_icon_update_resources(
      wide_executable, icon_data, image_count, error_buffer,
      error_buffer_length);
  free(icon_data);
  free(wide_executable);
  return status;
#else
  (void)executable;
  (void)executable_length;
  (void)icon;
  (void)icon_length;
  package_icon_error(error_buffer, error_buffer_length,
                     "Windows icon embedding is only available on Windows");
  return -1;
#endif
}
