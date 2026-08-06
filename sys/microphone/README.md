# moonbit-community/proton_microphone

[![CI](https://github.com/moonbit-community/proton/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbit-community/proton/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-mooncakes.io-green)](https://mooncakes.io/docs/moonbit-community/proton_microphone)

`moonbit-community/proton_microphone` is a native-only MoonBit package for microphone
device discovery and capture-session metadata. It uses small C native stubs for host integration, and exposes a focused MoonBit API that works on Windows, Linux, and macOS.

## Platform Support

The package is intentionally native-only. `moon.mod.json` sets
`"preferred-target": "native"`, and `src/moon.pkg` limits the package to the
native backend.

Discovery uses one platform audio API per operating system:

| Platform | Discovery API |
| --- | --- |
| Windows | Core Audio endpoint enumeration |
| Linux | ALSA device hints, loaded dynamically when available |
| macOS | Core Audio device properties |

The native stub returns an empty listing when the host API is unavailable.
`MicrophoneDevice::list()` therefore returns `[]` instead of raising in minimal CI images,
containers, or machines without audio services.

## Usage

List visible microphone-like devices:

```mbt
///|
fn main {
  let devices = @proton_microphone.MicrophoneDevice::list()
  if devices.length() == 0 {
    println("No microphones found.")
  } else {
    for device in devices {
      println(device.session_label())
    }
  }
}
```

Normalize capture settings before using them to size buffers:

```mbt
///|
fn chunk_bytes(config : @proton_microphone.CaptureConfig) -> Int {
  let normalized = config.normalized()
  normalized.recommended_chunk_frames() *
  normalized.channels *
  normalized.sample_format.bytes_per_sample()
}
```

Create a configuration by overriding only the fields that matter:

```mbt
///|
let config = @proton_microphone.CaptureConfig::new(
  channels=2,
  sample_rate_hz=48_000,
  echo_cancellation=true,
).normalized()
```

Parse a known listing in tests:

```mbt
///|
test "parse listing" {
  let devices = @proton_microphone.MicrophoneDevice::parse_listing(
    "Built-in Microphone\nmonitor-source\nUSB Studio Mic\n",
  )
  inspect(devices.length(), content="2")
  inspect(devices[0].session_label(), content="mic-0:idle:Built-in Microphone")
}
```

## Examples

Runnable examples live under `src/examples` so the repository keeps MoonBit
source in the configured source tree.

```bash
moon run src/examples/list_devices --target native
moon run src/examples/parse_listing --target native
```

## License

Apache-2.0.
