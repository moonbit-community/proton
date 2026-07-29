#if defined(__linux__)

#include "native_buffer.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef int (*MoonBitAlsaDeviceNameHint)(int, const char *, void ***);
typedef char *(*MoonBitAlsaDeviceNameGetHint)(const void *, const char *);
typedef int (*MoonBitAlsaDeviceNameFreeHint)(void **);
typedef void (*MoonBitAlsaConfigUpdateFreeGlobal)(void);

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer) {
  void *alsa = dlopen("libasound.so.2", RTLD_LAZY | RTLD_LOCAL);
  if (alsa == NULL) {
    alsa = dlopen("libasound.so", RTLD_LAZY | RTLD_LOCAL);
  }
  if (alsa == NULL) {
    return 0;
  }

  MoonBitAlsaDeviceNameHint device_name_hint =
    (MoonBitAlsaDeviceNameHint)dlsym(alsa, "snd_device_name_hint");
  MoonBitAlsaDeviceNameGetHint device_name_get_hint =
    (MoonBitAlsaDeviceNameGetHint)dlsym(alsa, "snd_device_name_get_hint");
  MoonBitAlsaDeviceNameFreeHint device_name_free_hint =
    (MoonBitAlsaDeviceNameFreeHint)dlsym(alsa, "snd_device_name_free_hint");
  MoonBitAlsaConfigUpdateFreeGlobal config_update_free_global =
    (MoonBitAlsaConfigUpdateFreeGlobal)dlsym(
      alsa,
      "snd_config_update_free_global"
    );

  if (
    device_name_hint == NULL ||
    device_name_get_hint == NULL ||
    device_name_free_hint == NULL
  ) {
    dlclose(alsa);
    return 0;
  }

  void **hints = NULL;
  if (device_name_hint(-1, "pcm", &hints) < 0 || hints == NULL) {
    dlclose(alsa);
    return 0;
  }

  for (void **hint = hints; *hint != NULL; hint++) {
    char *io = device_name_get_hint(*hint, "IOID");
    int capture_capable = io == NULL || strcmp(io, "Input") == 0;
    if (capture_capable) {
      char *name = device_name_get_hint(*hint, "NAME");
      char *description = device_name_get_hint(*hint, "DESC");
      const char *label =
        description != NULL && description[0] != '\0' ? description : name;
      moonbit_microphone_append_label_line(buffer, label);
      free(description);
      free(name);
    }
    free(io);
  }

  device_name_free_hint(hints);
  if (config_update_free_global != NULL) {
    config_update_free_global();
  }
  dlclose(alsa);
  return 1;
}

#endif
