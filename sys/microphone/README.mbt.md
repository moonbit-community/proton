# moonbit-community/microphone

Native-only microphone device discovery helpers for MoonBit.

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
