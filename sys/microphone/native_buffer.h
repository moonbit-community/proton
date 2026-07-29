#ifndef MOONBIT_MICROPHONE_NATIVE_BUFFER_H
#define MOONBIT_MICROPHONE_NATIVE_BUFFER_H

#include <moonbit.h>

#include <stddef.h>

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} MoonBitMicrophoneBuffer;

#define MOONBIT_MICROPHONE_ENCODING_UTF8 1
#define MOONBIT_MICROPHONE_ENCODING_UTF16LE 2

moonbit_bytes_t moonbit_microphone_empty_bytes(void);

int moonbit_microphone_append_bytes(
  MoonBitMicrophoneBuffer *buffer,
  const char *chunk,
  size_t chunk_len
);

int moonbit_microphone_append_char(
  MoonBitMicrophoneBuffer *buffer,
  char ch
);

int moonbit_microphone_append_label_line(
  MoonBitMicrophoneBuffer *buffer,
  const char *label
);

moonbit_bytes_t moonbit_microphone_buffer_to_terminated_bytes(
  MoonBitMicrophoneBuffer *buffer,
  size_t terminator_size
);

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer);

#endif
