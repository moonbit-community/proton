///|
/// Whether the microphone is currently armed or actively capturing.
///
/// `Armed` and `Recording` are live states because either state means the
/// application has reserved the selected device for immediate capture. `Idle`
/// and `Muted` are not live states, so this helper is suitable for UI badges,
/// telemetry, and guard checks before reading capture buffers.
pub fn MicrophoneDevice::is_live(self : MicrophoneDevice) -> Bool {
  match self.state {
    Armed => true
    Recording => true
    _ => false
  }
}

///|
/// Return a stable lowercase label for a capture state.
///
/// The labels are designed for logs, telemetry, and user settings where a
/// compact string is easier to persist than a debug representation. They are
/// intentionally independent of the derived `Show` output so future internal
/// formatting changes do not affect persisted labels.
///
/// # Example
/// ```mbt check
/// test "label returns a stable lowercase string" {
///   assert_eq(CaptureState::Recording.label(), "recording")
/// }
/// ```
pub fn CaptureState::label(self : CaptureState) -> String {
  match self {
    Idle => "idle"
    Armed => "armed"
    Recording => "recording"
    Muted => "muted"
  }
}

///|
/// Produce a concise session label for settings or telemetry.
///
/// The label combines the parsed device id, stable state label, and device
/// name. It is deterministic for a single discovery result and convenient for
/// logs such as `mic-0:idle:Built-in Microphone`.
pub fn MicrophoneDevice::session_label(self : MicrophoneDevice) -> String {
  "\{self.id}:\{self.state.label()}:\{self.name}"
}
