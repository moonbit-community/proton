#if defined(__APPLE__) && defined(__MACH__)

#include "native_buffer.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>

#define MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN 0

static UInt32 moonbit_microphone_macos_input_channels(
  AudioDeviceID device
) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyStreamConfiguration,
    kAudioDevicePropertyScopeInput,
    MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN,
  };

  UInt32 data_size = 0;
  if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &data_size) != noErr ||
      data_size == 0) {
    return 0;
  }

  AudioBufferList *buffers = (AudioBufferList *)malloc(data_size);
  if (buffers == NULL) {
    return 0;
  }

  UInt32 channels = 0;
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &data_size, buffers) == noErr) {
    for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
      channels += buffers->mBuffers[index].mNumberChannels;
    }
  }

  free(buffers);
  return channels;
}

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer) {
  AudioObjectPropertyAddress devices_address = {
    kAudioHardwarePropertyDevices,
    kAudioObjectPropertyScopeGlobal,
    MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN,
  };

  UInt32 data_size = 0;
  if (
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &devices_address, 0, NULL, &data_size) !=
      noErr ||
    data_size == 0
  ) {
    return 0;
  }

  AudioDeviceID *devices = (AudioDeviceID *)malloc(data_size);
  if (devices == NULL) {
    return 0;
  }

  if (
    AudioObjectGetPropertyData(
      kAudioObjectSystemObject,
      &devices_address,
      0,
      NULL,
      &data_size,
      devices
    ) == noErr
  ) {
    UInt32 device_count = data_size / sizeof(AudioDeviceID);
    for (UInt32 index = 0; index < device_count; index++) {
      AudioDeviceID device = devices[index];
      if (moonbit_microphone_macos_input_channels(device) == 0) {
        continue;
      }

      CFStringRef name = NULL;
      UInt32 name_size = sizeof(name);
      AudioObjectPropertyAddress name_address = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN,
      };

      if (
        AudioObjectGetPropertyData(device, &name_address, 0, NULL, &name_size, &name) == noErr &&
        name != NULL
      ) {
        char utf8[1024];
        if (
          CFStringGetCString(name, utf8, sizeof(utf8), kCFStringEncodingUTF8)
        ) {
          moonbit_microphone_append_label_line(buffer, utf8);
        }
        CFRelease(name);
      }
    }
  }

  free(devices);

  return 1;
}

#endif
