///|
/// Check whether a native source name matches the monitor/source-loopback
/// shapes produced by Linux audio stacks ("Monitor of ...", "*.monitor",
/// "monitor-source", "...-monitor"). Other platforms may legitimately carry
/// "monitor" in a device name (a display's built-in microphone), so a bare
/// substring match is intentionally not enough.
fn is_monitor_name(name : String) -> Bool {
  let lower = name.to_lower()
  lower.contains("monitor of") ||
  lower.contains(".monitor") ||
  lower.contains("monitor-source") ||
  lower.has_suffix("-monitor") ||
  lower == "monitor"
}

///|
/// Build a parsed microphone device with the next stable listing id.
fn parsed_device(name : String, id_number : Int) -> MicrophoneDevice {
  {
    id: "mic-\{id_number}",
    name,
    state: Idle,
    default_config: CaptureConfig(),
    monitor_supported: false,
  }
}

///|
/// Parse a native microphone listing into device descriptors.
///
/// The parser expects one device name per line after the private FFI layer has
/// decoded the native string encoding. Empty lines are ignored, Linux
/// monitor/source-loopback names are filtered out, and parsed ids are assigned
/// densely as `mic-0`, `mic-1`, and so on. Each parsed device receives
/// `CaptureConfig()` defaults and starts in `Idle`, which keeps tests
/// deterministic even when the host platform reports devices in a different
/// order.
///
/// # Example
/// ```mbt check
/// test "parse_listing assigns dense ids and drops monitors" {
///   let devices = MicrophoneDevice::parse_listing(
///     "Built-in Mic\nMonitor of Output\nUSB Mic\n",
///   )
///   assert_eq(devices.length(), 2)
///   assert_eq(devices[0].id, "mic-0")
///   assert_eq(devices[1].name, "USB Mic")
/// }
/// ```
pub fn MicrophoneDevice::parse_listing(
  output : String,
) -> Array[MicrophoneDevice] {
  let devices : Array[MicrophoneDevice] = []
  for line in output.split("\n").to_array() {
    let name = line.trim().to_owned()
    if name != "" && !is_monitor_name(name) {
      devices.push(parsed_device(name, devices.length()))
    }
  }
  devices
}

///|
/// List microphone-like capture devices visible to the current platform.
///
/// Discovery is best-effort and uses the host audio API directly: Windows uses
/// Core Audio capture endpoints, Linux uses ALSA device hints when available,
/// and macOS uses Core Audio device properties. If the platform API is
/// unavailable, blocked, or returns no capture devices, the function returns an
/// empty array instead of raising.
///
/// # Example
/// ```mbt nocheck
/// for device in @proton_microphone.MicrophoneDevice::list() {
///   println(device.session_label())
/// }
/// ```
pub fn MicrophoneDevice::list() -> Array[MicrophoneDevice] {
  MicrophoneDevice::parse_listing(native_microphone_listing_text())
}
