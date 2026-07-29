# justjavac/microphone

[![coverage](https://img.shields.io/codecov/c/github/justjavac/moonbit-microphone/main?label=coverage)](https://codecov.io/gh/justjavac/moonbit-microphone)
[![linux](https://img.shields.io/codecov/c/github/justjavac/moonbit-microphone/main?flag=linux&label=linux)](https://codecov.io/gh/justjavac/moonbit-microphone)
[![macos](https://img.shields.io/codecov/c/github/justjavac/moonbit-microphone/main?flag=macos&label=macos)](https://codecov.io/gh/justjavac/moonbit-microphone)
[![windows](https://img.shields.io/codecov/c/github/justjavac/moonbit-microphone/main?flag=windows&label=windows)](https://codecov.io/gh/justjavac/moonbit-microphone)

Native-only microphone discovery and capture-session helpers.

```mbt nocheck
///|
fn main {
  let devices = @microphone.MicrophoneDevice::list()
  for device in devices {
    println(device.session_label())
  }
}
```

```mbt nocheck
///|
fn example_label {
  let device = @microphone.MicrophoneDevice::{
    id: "mic-1",
    name: "Built-in Mic",
    state: Idle,
    default_config: @microphone.CaptureConfig::new(
      echo_cancellation=true,
      noise_suppression=true,
    ),
    monitor_supported: true,
  }
  println(device.session_label())
}
```
