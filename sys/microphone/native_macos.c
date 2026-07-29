#if defined(__APPLE__) && defined(__MACH__)

#include "native_buffer.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>

#define MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN 0

typedef OSStatus (*MoonBitAudioGetPropertyDataSize)(
  AudioObjectID,
  const AudioObjectPropertyAddress *,
  UInt32,
  const void *,
  UInt32 *
);
typedef OSStatus (*MoonBitAudioGetPropertyData)(
  AudioObjectID,
  const AudioObjectPropertyAddress *,
  UInt32,
  const void *,
  UInt32 *,
  void *
);
typedef Boolean (*MoonBitCFStringGetCString)(
  CFStringRef,
  char *,
  CFIndex,
  CFStringEncoding
);
typedef void (*MoonBitCFRelease)(CFTypeRef);

static UInt32 moonbit_microphone_macos_input_channels(
  AudioDeviceID device,
  MoonBitAudioGetPropertyDataSize get_size,
  MoonBitAudioGetPropertyData get_data
) {
  AudioObjectPropertyAddress address = {
    kAudioDevicePropertyStreamConfiguration,
    kAudioDevicePropertyScopeInput,
    MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN,
  };

  UInt32 data_size = 0;
  if (get_size(device, &address, 0, NULL, &data_size) != noErr ||
      data_size == 0) {
    return 0;
  }

  AudioBufferList *buffers = (AudioBufferList *)malloc(data_size);
  if (buffers == NULL) {
    return 0;
  }

  UInt32 channels = 0;
  if (get_data(device, &address, 0, NULL, &data_size, buffers) == noErr) {
    for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
      channels += buffers->mBuffers[index].mNumberChannels;
    }
  }

  free(buffers);
  return channels;
}

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer) {
  void *core_audio = dlopen(
    "/System/Library/Frameworks/CoreAudio.framework/CoreAudio",
    RTLD_LAZY | RTLD_LOCAL
  );
  void *core_foundation = dlopen(
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    RTLD_LAZY | RTLD_LOCAL
  );
  if (core_audio == NULL || core_foundation == NULL) {
    if (core_audio != NULL) {
      dlclose(core_audio);
    }
    if (core_foundation != NULL) {
      dlclose(core_foundation);
    }
    return 0;
  }

  MoonBitAudioGetPropertyDataSize get_size =
    (MoonBitAudioGetPropertyDataSize)dlsym(
      core_audio,
      "AudioObjectGetPropertyDataSize"
    );
  MoonBitAudioGetPropertyData get_data = (MoonBitAudioGetPropertyData)dlsym(
    core_audio,
    "AudioObjectGetPropertyData"
  );
  MoonBitCFStringGetCString string_get_cstring =
    (MoonBitCFStringGetCString)dlsym(core_foundation, "CFStringGetCString");
  MoonBitCFRelease cf_release =
    (MoonBitCFRelease)dlsym(core_foundation, "CFRelease");

  if (
    get_size == NULL ||
    get_data == NULL ||
    string_get_cstring == NULL ||
    cf_release == NULL
  ) {
    dlclose(core_foundation);
    dlclose(core_audio);
    return 0;
  }

  AudioObjectPropertyAddress devices_address = {
    kAudioHardwarePropertyDevices,
    kAudioObjectPropertyScopeGlobal,
    MOONBIT_AUDIO_OBJECT_PROPERTY_ELEMENT_MAIN,
  };

  UInt32 data_size = 0;
  if (
    get_size(kAudioObjectSystemObject, &devices_address, 0, NULL, &data_size) !=
      noErr ||
    data_size == 0
  ) {
    dlclose(core_foundation);
    dlclose(core_audio);
    return 0;
  }

  AudioDeviceID *devices = (AudioDeviceID *)malloc(data_size);
  if (devices == NULL) {
    dlclose(core_foundation);
    dlclose(core_audio);
    return 0;
  }

  if (
    get_data(
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
      if (moonbit_microphone_macos_input_channels(device, get_size, get_data) ==
          0) {
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
        get_data(device, &name_address, 0, NULL, &name_size, &name) == noErr &&
        name != NULL
      ) {
        char utf8[1024];
        if (
          string_get_cstring(name, utf8, sizeof(utf8), kCFStringEncodingUTF8)
        ) {
          moonbit_microphone_append_label_line(buffer, utf8);
        }
        cf_release(name);
      }
    }
  }

  free(devices);
  dlclose(core_foundation);
  dlclose(core_audio);
  return 1;
}

#endif
