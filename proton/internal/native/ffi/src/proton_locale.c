#include "proton_internal.h"

#include <limits.h>
#include <stdbool.h>
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
  char *buffer;
  int32_t buffer_len;
  int64_t required;
  int32_t count;
  bool overflow;
} proton_locale_json_writer_t;

static void proton_locale_write_byte(proton_locale_json_writer_t *writer,
                                     char value) {
  if (writer->required < writer->buffer_len - 1 && writer->buffer != NULL) {
    writer->buffer[writer->required] = value;
  }
  writer->required++;
  if (writer->required > INT32_MAX) {
    writer->overflow = true;
  }
}

static void proton_locale_write_text(proton_locale_json_writer_t *writer,
                                     const char *text) {
  for (const unsigned char *cursor = (const unsigned char *)text; *cursor;
       cursor++) {
    switch (*cursor) {
    case '"':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, '"');
      break;
    case '\\':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, '\\');
      break;
    case '\b':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, 'b');
      break;
    case '\f':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, 'f');
      break;
    case '\n':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, 'n');
      break;
    case '\r':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, 'r');
      break;
    case '\t':
      proton_locale_write_byte(writer, '\\');
      proton_locale_write_byte(writer, 't');
      break;
    default:
      if (*cursor < 0x20) {
        static const char hex[] = "0123456789abcdef";
        proton_locale_write_byte(writer, '\\');
        proton_locale_write_byte(writer, 'u');
        proton_locale_write_byte(writer, '0');
        proton_locale_write_byte(writer, '0');
        proton_locale_write_byte(writer, hex[*cursor >> 4]);
        proton_locale_write_byte(writer, hex[*cursor & 0x0f]);
      } else {
        proton_locale_write_byte(writer, (char)*cursor);
      }
      break;
    }
  }
}

static void proton_locale_write_language(proton_locale_json_writer_t *writer,
                                         const char *language) {
  if (language == NULL || language[0] == '\0' || writer->overflow) {
    return;
  }
  if (writer->count > 0) {
    proton_locale_write_byte(writer, ',');
  }
  proton_locale_write_byte(writer, '"');
  proton_locale_write_text(writer, language);
  proton_locale_write_byte(writer, '"');
  writer->count++;
}

#ifdef _WIN32
static int32_t proton_locale_collect_platform(
    proton_locale_json_writer_t *writer, char *error, size_t error_len) {
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
    if (utf8_length <= 0) {
      snprintf(error, error_len, "failed to encode preferred language as UTF-8");
      free(languages);
      return PROTON_ERR_PLATFORM;
    }
    char *utf8 = (char *)malloc((size_t)utf8_length);
    if (utf8 == NULL ||
        WideCharToMultiByte(CP_UTF8, 0, language, -1, utf8, utf8_length, NULL,
                            NULL) <= 0) {
      free(utf8);
      free(languages);
      snprintf(error, error_len, "failed to encode preferred language as UTF-8");
      return PROTON_ERR_PLATFORM;
    }
    proton_locale_write_language(writer, utf8);
    free(utf8);
  }
  free(languages);
  return PROTON_OK;
}
#elif defined(__APPLE__)
static int32_t proton_locale_collect_platform(
    proton_locale_json_writer_t *writer, char *error, size_t error_len) {
  CFArrayRef languages = CFLocaleCopyPreferredLanguages();
  if (languages == NULL) {
    snprintf(error, error_len, "CFLocaleCopyPreferredLanguages failed");
    return PROTON_ERR_PLATFORM;
  }
  CFIndex count = CFArrayGetCount(languages);
  for (CFIndex index = 0; index < count; index++) {
    CFStringRef language =
        (CFStringRef)CFArrayGetValueAtIndex(languages, index);
    if (language == NULL || CFGetTypeID(language) != CFStringGetTypeID()) {
      continue;
    }
    CFIndex maximum = CFStringGetMaximumSizeForEncoding(
        CFStringGetLength(language), kCFStringEncodingUTF8);
    if (maximum < 0 || maximum >= INT32_MAX) {
      CFRelease(languages);
      snprintf(error, error_len, "preferred language is too long");
      return PROTON_ERR_PLATFORM;
    }
    char *utf8 = (char *)malloc((size_t)maximum + 1);
    if (utf8 == NULL ||
        !CFStringGetCString(language, utf8, maximum + 1,
                            kCFStringEncodingUTF8)) {
      free(utf8);
      CFRelease(languages);
      snprintf(error, error_len, "failed to encode preferred language as UTF-8");
      return PROTON_ERR_PLATFORM;
    }
    proton_locale_write_language(writer, utf8);
    free(utf8);
  }
  CFRelease(languages);
  return PROTON_OK;
}
#else
static int32_t proton_locale_collect_platform(
    proton_locale_json_writer_t *writer, char *error, size_t error_len) {
  (void)error;
  (void)error_len;
  const char *language = getenv("LANGUAGE");
  if (language != NULL && language[0] != '\0') {
    const char *start = language;
    for (const char *cursor = language;; cursor++) {
      if (*cursor != ':' && *cursor != '\0') {
        continue;
      }
      size_t length = (size_t)(cursor - start);
      if (length > 0) {
        char *candidate = (char *)malloc(length + 1);
        if (candidate == NULL) {
          snprintf(error, error_len,
                   "failed to allocate preferred language buffer");
          return PROTON_ERR_PLATFORM;
        }
        memcpy(candidate, start, length);
        candidate[length] = '\0';
        proton_locale_write_language(writer, candidate);
        free(candidate);
      }
      if (*cursor == '\0') {
        break;
      }
      start = cursor + 1;
    }
    return PROTON_OK;
  }
  static const char *variables[] = {"LC_ALL", "LC_MESSAGES", "LANG"};
  for (size_t index = 0; index < sizeof(variables) / sizeof(variables[0]);
       index++) {
    const char *value = getenv(variables[index]);
    if (value != NULL && value[0] != '\0') {
      proton_locale_write_language(writer, value);
      break;
    }
  }
  return PROTON_OK;
}
#endif

int32_t proton_system_preferred_languages_json(char *buffer,
                                               int32_t buffer_len,
                                               int32_t *out_required_len) {
  if (out_required_len == NULL || buffer_len < 0 ||
      (buffer == NULL && buffer_len != 0)) {
    return proton_set_error(PROTON_ERR_INVALID_ARGUMENT,
                            "invalid preferred languages output buffer");
  }
  *out_required_len = 0;
  proton_locale_json_writer_t writer = {
      .buffer = buffer,
      .buffer_len = buffer_len,
      .required = 0,
      .count = 0,
      .overflow = false,
  };
  proton_locale_write_byte(&writer, '[');
  char platform_error[256] = {0};
  int32_t status = proton_locale_collect_platform(
      &writer, platform_error, sizeof(platform_error));
  if (status != PROTON_OK) {
    return proton_set_error(status, platform_error);
  }
  proton_locale_write_byte(&writer, ']');
  if (writer.overflow) {
    return proton_set_error(PROTON_ERR_PLATFORM,
                            "preferred languages JSON is too large");
  }
  *out_required_len = (int32_t)writer.required;
  if (buffer == NULL || buffer_len <= writer.required) {
    return proton_set_error(PROTON_ERR_BUFFER_TOO_SMALL,
                            "preferred languages buffer is too small");
  }
  buffer[writer.required] = '\0';
  return proton_set_error(PROTON_OK, NULL);
}
