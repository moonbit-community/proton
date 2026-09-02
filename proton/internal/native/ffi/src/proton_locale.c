#include "proton_internal.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#endif

typedef struct {
  char **items;
  int32_t count;
  int32_t capacity;
} proton_locale_list_t;

static void proton_locale_list_dispose(proton_locale_list_t *list) {
  if (list == NULL) {
    return;
  }
  for (int32_t index = 0; index < list->count; index++) {
    free(list->items[index]);
  }
  free(list->items);
  memset(list, 0, sizeof(*list));
}

static int proton_locale_list_reserve(proton_locale_list_t *list,
                                      int32_t capacity) {
  if (capacity <= list->capacity) {
    return 1;
  }
  int32_t next_capacity = list->capacity == 0 ? 4 : list->capacity;
  while (next_capacity < capacity) {
    if (next_capacity > INT32_MAX / 2) {
      return 0;
    }
    next_capacity *= 2;
  }
  char **items = (char **)realloc(list->items,
                                  (size_t)next_capacity * sizeof(char *));
  if (items == NULL) {
    return 0;
  }
  list->items = items;
  list->capacity = next_capacity;
  return 1;
}

static int proton_locale_list_append_slice(proton_locale_list_t *list,
                                           const char *value, size_t length) {
  if (value == NULL || length == 0) {
    return 1;
  }
  if (list->count == INT32_MAX ||
      !proton_locale_list_reserve(list, list->count + 1)) {
    return 0;
  }
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return 0;
  }
  memcpy(copy, value, length);
  copy[length] = '\0';
  list->items[list->count++] = copy;
  return 1;
}

static int proton_locale_list_append(proton_locale_list_t *list,
                                     const char *value) {
  return value == NULL ? 1
                       : proton_locale_list_append_slice(list, value,
                                                         strlen(value));
}

#ifdef _WIN32
static int32_t proton_locale_collect_platform(proton_locale_list_t *list,
                                              char *error, size_t error_len) {
  ULONG language_count = 0;
  ULONG buffer_length = 0;
  if (GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &language_count, NULL,
                                  &buffer_length) == 0 &&
      GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    snprintf(error, error_len,
             "GetUserPreferredUILanguages size query failed: %lu",
             (unsigned long)GetLastError());
    return PROTON_ERR_PLATFORM;
  }
  if (buffer_length == 0) {
    return PROTON_OK;
  }
  WCHAR *languages = (WCHAR *)calloc(buffer_length, sizeof(WCHAR));
  if (languages == NULL) {
    snprintf(error, error_len, "failed to allocate preferred language buffer");
    return PROTON_ERR_PLATFORM;
  }
  if (GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &language_count, languages,
                                  &buffer_length) == 0) {
    snprintf(error, error_len, "GetUserPreferredUILanguages failed: %lu",
             (unsigned long)GetLastError());
    free(languages);
    return PROTON_ERR_PLATFORM;
  }
  for (const WCHAR *language = languages; *language != L'\0';
       language += wcslen(language) + 1) {
    int utf8_length =
        WideCharToMultiByte(CP_UTF8, 0, language, -1, NULL, 0, NULL, NULL);
    char *utf8 = utf8_length > 0 ? (char *)malloc((size_t)utf8_length) : NULL;
    if (utf8 == NULL ||
        WideCharToMultiByte(CP_UTF8, 0, language, -1, utf8, utf8_length, NULL,
                            NULL) <= 0 ||
        !proton_locale_list_append(list, utf8)) {
      free(utf8);
      free(languages);
      snprintf(error, error_len, "failed to encode preferred language as UTF-8");
      return PROTON_ERR_PLATFORM;
    }
    free(utf8);
  }
  free(languages);
  return PROTON_OK;
}
#elif defined(__APPLE__)
static int32_t proton_locale_collect_platform(proton_locale_list_t *list,
                                              char *error, size_t error_len) {
  CFArrayRef languages = CFLocaleCopyPreferredLanguages();
  if (languages == NULL) {
    snprintf(error, error_len, "CFLocaleCopyPreferredLanguages failed");
    return PROTON_ERR_PLATFORM;
  }
  for (CFIndex index = 0; index < CFArrayGetCount(languages); index++) {
    CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(languages, index);
    if (language == NULL || CFGetTypeID(language) != CFStringGetTypeID()) {
      continue;
    }
    CFIndex maximum = CFStringGetMaximumSizeForEncoding(
        CFStringGetLength(language), kCFStringEncodingUTF8);
    char *utf8 = maximum >= 0 && maximum < INT32_MAX
                     ? (char *)malloc((size_t)maximum + 1)
                     : NULL;
    if (utf8 == NULL ||
        !CFStringGetCString(language, utf8, maximum + 1,
                            kCFStringEncodingUTF8) ||
        !proton_locale_list_append(list, utf8)) {
      free(utf8);
      CFRelease(languages);
      snprintf(error, error_len, "failed to encode preferred language as UTF-8");
      return PROTON_ERR_PLATFORM;
    }
    free(utf8);
  }
  CFRelease(languages);
  return PROTON_OK;
}
#else
static int32_t proton_locale_collect_platform(proton_locale_list_t *list,
                                              char *error, size_t error_len) {
  const char *language = getenv("LANGUAGE");
  if (language != NULL && language[0] != '\0') {
    const char *start = language;
    for (const char *cursor = language;; cursor++) {
      if (*cursor != ':' && *cursor != '\0') {
        continue;
      }
      if (!proton_locale_list_append_slice(list, start,
                                           (size_t)(cursor - start))) {
        snprintf(error, error_len, "failed to allocate preferred language");
        return PROTON_ERR_PLATFORM;
      }
      if (*cursor == '\0') {
        return PROTON_OK;
      }
      start = cursor + 1;
    }
  }
  static const char *variables[] = {"LC_ALL", "LC_MESSAGES", "LANG"};
  for (size_t index = 0; index < sizeof(variables) / sizeof(variables[0]);
       index++) {
    const char *value = getenv(variables[index]);
    if (value != NULL && value[0] != '\0') {
      if (!proton_locale_list_append(list, value)) {
        snprintf(error, error_len, "failed to allocate preferred language");
        return PROTON_ERR_PLATFORM;
      }
      break;
    }
  }
  return PROTON_OK;
}
#endif

static int32_t proton_locale_collect(proton_locale_list_t *list) {
  char error[256] = {0};
  int32_t status = proton_locale_collect_platform(list, error, sizeof(error));
  if (status != PROTON_OK) {
    proton_locale_list_dispose(list);
    return proton_set_error(status, error);
  }
  return PROTON_OK;
}

int32_t proton_system_preferred_language_count(int32_t *out_count) {
  if (out_count == NULL) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "out_count is required");
  }
  proton_locale_list_t list = {0};
  int32_t status = proton_locale_collect(&list);
  if (status == PROTON_OK) {
    *out_count = list.count;
    proton_locale_list_dispose(&list);
    return proton_set_error(PROTON_OK, NULL);
  }
  return status;
}

int32_t proton_system_preferred_language_at(int32_t index, char *buffer,
                                            int32_t buffer_len,
                                            int32_t *out_required_len) {
  if (out_required_len == NULL || index < 0 || buffer_len < 0 ||
      (buffer == NULL && buffer_len != 0)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid preferred language query");
  }
  proton_locale_list_t list = {0};
  int32_t status = proton_locale_collect(&list);
  if (status != PROTON_OK) {
    return status;
  }
  if (index >= list.count) {
    proton_locale_list_dispose(&list);
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "preferred language index is out of range");
  }
  size_t length = strlen(list.items[index]);
  if (length > INT32_MAX) {
    proton_locale_list_dispose(&list);
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "preferred language is too long");
  }
  *out_required_len = (int32_t)length;
  if (buffer == NULL || buffer_len <= (int32_t)length) {
    proton_locale_list_dispose(&list);
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "preferred language buffer is too small");
  }
  memcpy(buffer, list.items[index], length + 1);
  proton_locale_list_dispose(&list);
  return proton_set_error(PROTON_OK, NULL);
}
