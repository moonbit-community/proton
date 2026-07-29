///|
/// Runtime state for a microphone capture session.
///
/// `Idle` means the device is known but not prepared, `Armed` means the
/// application is ready to begin capture, `Recording` means audio frames are
/// actively being collected, and `Muted` means capture is intentionally
/// suppressed while the device remains selected.
pub(all) enum CaptureState {
  Idle
  Armed
  Recording
  Muted
} derive(Debug, Eq)

///|
/// Sample representation requested from a microphone capture session.
///
/// `I16` and `U16` are 16-bit integer formats that are common in lower-level
/// APIs. `F32` is the preferred normalized floating-point representation for
/// processing pipelines because each sample is four bytes and typically maps
/// to the `[-1.0, 1.0]` audio range.
pub(all) enum SampleFormat {
  I16
  U16
  F32
} derive(Debug, Eq)

///|
/// Capture settings used when opening or describing a microphone stream.
///
/// `channels` and `sample_rate_hz` are normalized by `CaptureConfig::normalized` before
/// chunk sizing is computed. `echo_cancellation` and `noise_suppression` are
/// advisory voice-processing flags; support depends on the actual host audio
/// stack, but keeping them in the config makes intent explicit at API
/// boundaries.
pub(all) struct CaptureConfig {
  channels : Int
  sample_rate_hz : Int
  sample_format : SampleFormat
  echo_cancellation : Bool
  noise_suppression : Bool
} derive(Debug, Eq)

///|
/// Microphone device descriptor returned by native discovery.
///
/// `id` is a stable identifier for the parsed listing within one discovery
/// result, `name` is the human-facing device name, `state` starts at `Idle`,
/// `default_config` is safe for low-latency voice capture, and
/// `monitor_supported` reports whether this package recognized the entry as a
/// monitor/source-loopback device.
pub(all) struct MicrophoneDevice {
  id : String
  name : String
  state : CaptureState
  default_config : CaptureConfig
  monitor_supported : Bool
} derive(Debug, Eq)

///|
/// Write a derived debug representation to a `Show` logger.
fn[T : Debug] write_debug_show(value : T, logger : &Logger) -> Unit {
  logger.write_string(value.to_repr().to_string())
}

///|
/// Render `CaptureState` with the derived debug representation.
///
/// The implementation keeps `inspect`, logs, and string interpolation aligned
/// with the enum variant names while `CaptureState::label` remains the stable lowercase
/// label for persisted settings.
pub impl Show for CaptureState with fn output(self, logger : &Logger) -> Unit {
  write_debug_show(self, logger)
}

///|
/// Render `SampleFormat` with the derived debug representation.
///
/// This makes sample format values easy to print in tests and diagnostics
/// without introducing a separate formatting table for the public enum.
pub impl Show for SampleFormat with fn output(self, logger : &Logger) -> Unit {
  write_debug_show(self, logger)
}

///|
/// Render `CaptureConfig` with the derived debug representation.
///
/// The full record is printed, which is useful when checking normalized
/// settings or comparing expected capture profiles in tests.
pub impl Show for CaptureConfig with fn output(self, logger : &Logger) -> Unit {
  write_debug_show(self, logger)
}

///|
/// Render `MicrophoneDevice` with the derived debug representation.
///
/// Device descriptors include state and default configuration, so using the
/// derived representation gives callers a compact diagnostic view of discovery
/// results.
pub impl Show for MicrophoneDevice with fn output(self, logger : &Logger) -> Unit {
  write_debug_show(self, logger)
}
