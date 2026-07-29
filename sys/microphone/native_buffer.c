#include "native_buffer.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

moonbit_bytes_t moonbit_microphone_empty_bytes(void) {
  return moonbit_make_bytes(1, 0);
}

int moonbit_microphone_append_bytes(
  MoonBitMicrophoneBuffer *buffer,
  const char *chunk,
  size_t chunk_len
) {
  if (chunk_len == 0) {
    return 1;
  }
  if (chunk_len > ((size_t)-1) - buffer->len - 1) {
    return 0;
  }
  size_t needed = buffer->len + chunk_len;
  if (needed > buffer->cap) {
    size_t next_cap = buffer->cap == 0 ? 1024 : buffer->cap;
    while (needed > next_cap) {
      if (next_cap > ((size_t)-1) / 2) {
        return 0;
      }
      next_cap *= 2;
    }
    char *next = (char *)realloc(buffer->data, next_cap);
    if (next == NULL) {
      return 0;
    }
    buffer->data = next;
    buffer->cap = next_cap;
  }
  memcpy(buffer->data + buffer->len, chunk, chunk_len);
  buffer->len += chunk_len;
  return 1;
}

int moonbit_microphone_append_char(
  MoonBitMicrophoneBuffer *buffer,
  char ch
) {
  return moonbit_microphone_append_bytes(buffer, &ch, 1);
}

int moonbit_microphone_append_label_line(
  MoonBitMicrophoneBuffer *buffer,
  const char *label
) {
  if (label == NULL) {
    return 1;
  }

  const char *start = label;
  while (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n') {
    start++;
  }

  const char *end = start + strlen(start);
  while (
    end > start &&
    (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')
  ) {
    end--;
  }

  if (start == end) {
    return 1;
  }

  if (buffer->len > 0 && !moonbit_microphone_append_char(buffer, '\n')) {
    return 0;
  }

  for (const char *cursor = start; cursor < end; cursor++) {
    char ch = *cursor;
    if (ch == '\r' || ch == '\n') {
      ch = ' ';
    }
    if (!moonbit_microphone_append_char(buffer, ch)) {
      return 0;
    }
  }

  return 1;
}

moonbit_bytes_t moonbit_microphone_buffer_to_terminated_bytes(
  MoonBitMicrophoneBuffer *buffer,
  size_t terminator_size
) {
  if (terminator_size == 0) {
    terminator_size = 1;
  }
  if (
    buffer->data == NULL ||
    buffer->len == 0 ||
    terminator_size > (size_t)INT32_MAX ||
    buffer->len > (size_t)INT32_MAX - terminator_size
  ) {
    free(buffer->data);
    return moonbit_make_bytes((int32_t)terminator_size, 0);
  }

  moonbit_bytes_t bytes = moonbit_make_bytes(
    (int32_t)(buffer->len + terminator_size),
    0
  );
  memcpy(bytes, buffer->data, buffer->len);
  free(buffer->data);
  return bytes;
}

MOONBIT_FFI_EXPORT
int32_t moonbit_microphone_listing_encoding(void) {
#if defined(_WIN32)
  return MOONBIT_MICROPHONE_ENCODING_UTF16LE;
#else
  return MOONBIT_MICROPHONE_ENCODING_UTF8;
#endif
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_microphone_listing(void) {
  MoonBitMicrophoneBuffer buffer = { 0 };
  moonbit_microphone_collect_platform(&buffer);
  size_t terminator_size =
    moonbit_microphone_listing_encoding() ==
    MOONBIT_MICROPHONE_ENCODING_UTF16LE ? 2 : 1;
  return moonbit_microphone_buffer_to_terminated_bytes(
    &buffer,
    terminator_size
  );
}
