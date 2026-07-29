#if defined(_WIN32)

#include "native_buffer.h"

#include <mmdeviceapi.h>
#include <objbase.h>
#include <propkeydef.h>
#include <propidl.h>
#include <propsys.h>
#include <windows.h>
#include <wchar.h>

#pragma comment(lib, "ole32.lib")

static const GUID MOONBIT_MICROPHONE_CLSID_MMDEVICE_ENUMERATOR = {
  0xbcde0395,
  0xe52f,
  0x467c,
  { 0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e },
};

static const GUID MOONBIT_MICROPHONE_IID_IMMDEVICE_ENUMERATOR = {
  0xa95664d2,
  0x9614,
  0x4f35,
  { 0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6 },
};

static const PROPERTYKEY MOONBIT_MICROPHONE_PKEY_DEVICE_FRIENDLY_NAME = {
  { 0xa45c254e,
    0xdf1c,
    0x4efd,
    { 0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0 } },
  14,
};

static int moonbit_microphone_append_wide_unit(
  MoonBitMicrophoneBuffer *buffer,
  wchar_t unit
) {
  unsigned char bytes[2] = {
    (unsigned char)((unsigned int)unit & 0xff),
    (unsigned char)(((unsigned int)unit >> 8) & 0xff),
  };
  return moonbit_microphone_append_bytes(buffer, (const char *)bytes, 2);
}

static int moonbit_microphone_append_wide_label_line(
  MoonBitMicrophoneBuffer *buffer,
  const wchar_t *label
) {
  if (label == NULL) {
    return 1;
  }

  const wchar_t *start = label;
  while (*start == L' ' || *start == L'\t' || *start == L'\r' || *start == L'\n') {
    start++;
  }

  const wchar_t *end = start + wcslen(start);
  while (
    end > start &&
    (end[-1] == L' ' || end[-1] == L'\t' || end[-1] == L'\r' || end[-1] == L'\n')
  ) {
    end--;
  }

  if (start == end) {
    return 1;
  }

  if (
    buffer->len > 0 &&
    !moonbit_microphone_append_wide_unit(buffer, L'\n')
  ) {
    return 0;
  }

  for (const wchar_t *cursor = start; cursor < end; cursor++) {
    wchar_t unit = *cursor;
    if (unit == L'\r' || unit == L'\n') {
      unit = L' ';
    }
    if (!moonbit_microphone_append_wide_unit(buffer, unit)) {
      return 0;
    }
  }

  return 1;
}

int moonbit_microphone_collect_platform(MoonBitMicrophoneBuffer *buffer) {
  HRESULT init = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  int should_uninitialize = SUCCEEDED(init);
  if (FAILED(init) && init != RPC_E_CHANGED_MODE) {
    return 0;
  }

  IMMDeviceEnumerator *enumerator = NULL;
  HRESULT hr = CoCreateInstance(
    &MOONBIT_MICROPHONE_CLSID_MMDEVICE_ENUMERATOR,
    NULL,
    CLSCTX_ALL,
    &MOONBIT_MICROPHONE_IID_IMMDEVICE_ENUMERATOR,
    (void **)&enumerator
  );
  if (FAILED(hr) || enumerator == NULL) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    return 0;
  }

  IMMDeviceCollection *collection = NULL;
  hr = enumerator->lpVtbl->EnumAudioEndpoints(
    enumerator,
    eCapture,
    DEVICE_STATE_ACTIVE,
    &collection
  );
  if (FAILED(hr) || collection == NULL) {
    enumerator->lpVtbl->Release(enumerator);
    if (should_uninitialize) {
      CoUninitialize();
    }
    return 0;
  }

  UINT count = 0;
  if (SUCCEEDED(collection->lpVtbl->GetCount(collection, &count))) {
    for (UINT index = 0; index < count; index++) {
      IMMDevice *device = NULL;
      if (FAILED(collection->lpVtbl->Item(collection, index, &device)) ||
          device == NULL) {
        continue;
      }

      IPropertyStore *store = NULL;
      if (SUCCEEDED(device->lpVtbl->OpenPropertyStore(device, STGM_READ, &store)) &&
          store != NULL) {
        PROPVARIANT friendly_name;
        PropVariantInit(&friendly_name);
        if (SUCCEEDED(
              store->lpVtbl->GetValue(
                store,
                &MOONBIT_MICROPHONE_PKEY_DEVICE_FRIENDLY_NAME,
                &friendly_name
              )
            ) &&
            friendly_name.vt == VT_LPWSTR) {
          moonbit_microphone_append_wide_label_line(buffer, friendly_name.pwszVal);
        }
        PropVariantClear(&friendly_name);
        store->lpVtbl->Release(store);
      }

      device->lpVtbl->Release(device);
    }
  }

  collection->lpVtbl->Release(collection);
  enumerator->lpVtbl->Release(enumerator);
  if (should_uninitialize) {
    CoUninitialize();
  }
  return 1;
}

#endif
