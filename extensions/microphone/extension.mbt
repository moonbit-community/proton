///|
let extension_id = "justjavac/lepus-microphone"

///|
let extension_namespace = "microphone"

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
struct ParseListingPayload {
  listing : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct CaptureConfigPayload {
  channels : Int?
  sample_rate_hz : Int?
  sample_format : String?
  echo_cancellation : Bool?
  noise_suppression : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct CaptureConfigReply {
  channels : Int
  sample_rate_hz : Int
  sample_format : String
  echo_cancellation : Bool
  noise_suppression : Bool
  bytes_per_sample : Int
  recommended_chunk_frames : Int
  uses_voice_processing : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MicrophoneDeviceReply {
  id : String
  name : String
  state : String
  default_config : CaptureConfigReply
  monitor_supported : Bool
  live : Bool
  session_label : String
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MicrophoneDevicesReply {
  devices : Array[MicrophoneDeviceReply]
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MicrophoneActivity {
  operation : String
  count : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Converts a sample format label from JavaScript into the package enum.
fn parse_sample_format(
  sample_format : String?,
) -> Result[@sys_microphone.SampleFormat?, String] {
  match sample_format {
    Some("i16") => Ok(Some(I16))
    Some("u16") => Ok(Some(U16))
    Some("f32") => Ok(Some(F32))
    Some(value) => Err("unknown microphone sample format: " + value)
    None => Ok(None)
  }
}

///|
/// Converts a sample format into a stable JS label.
fn sample_format_label(format : @sys_microphone.SampleFormat) -> String {
  match format {
    I16 => "i16"
    U16 => "u16"
    F32 => "f32"
  }
}

///|
/// Emits a microphone activity event for JavaScript listeners.
fn emit_activity(
  extension : @core.ExtensionContext,
  operation : String,
  count? : Int? = None,
) -> Unit {
  extension.emit("activity", MicrophoneActivity::{ operation, count })
}

///|
/// Builds and normalizes one capture config from JavaScript payload data.
fn build_capture_config(
  payload : CaptureConfigPayload,
) -> Result[@sys_microphone.CaptureConfig, String] {
  parse_sample_format(payload.sample_format).map(fn(sample_format) {
    let channels = match payload.channels {
      Some(value) => value
      None => 1
    }
    let sample_rate_hz = match payload.sample_rate_hz {
      Some(value) => value
      None => 48_000
    }
    let sample_format = match sample_format {
      Some(value) => value
      None => F32
    }
    let echo_cancellation = match payload.echo_cancellation {
      Some(value) => value
      None => false
    }
    let noise_suppression = match payload.noise_suppression {
      Some(value) => value
      None => false
    }
    @sys_microphone.CaptureConfig::new(
      channels~,
      sample_rate_hz~,
      sample_format~,
      echo_cancellation~,
      noise_suppression~,
    ).normalized()
  })
}

///|
/// Converts a capture config into the serializable descriptor used by JS.
fn capture_config_reply(
  config : @sys_microphone.CaptureConfig,
) -> CaptureConfigReply {
  CaptureConfigReply::{
    channels: config.channels,
    sample_rate_hz: config.sample_rate_hz,
    sample_format: sample_format_label(config.sample_format),
    echo_cancellation: config.echo_cancellation,
    noise_suppression: config.noise_suppression,
    bytes_per_sample: config.sample_format.bytes_per_sample(),
    recommended_chunk_frames: config.recommended_chunk_frames(),
    uses_voice_processing: config.uses_voice_processing(),
  }
}

///|
/// Converts one microphone device descriptor into a JavaScript-friendly shape.
fn microphone_device_reply(
  device : @sys_microphone.MicrophoneDevice,
) -> MicrophoneDeviceReply {
  MicrophoneDeviceReply::{
    id: device.id,
    name: device.name,
    state: device.state.label(),
    default_config: capture_config_reply(device.default_config),
    monitor_supported: device.monitor_supported,
    live: device.is_live(),
    session_label: device.session_label(),
  }
}

///|
/// Converts many microphone devices into a JavaScript-friendly reply.
fn microphone_devices_reply(
  devices : Array[@sys_microphone.MicrophoneDevice],
) -> MicrophoneDevicesReply {
  MicrophoneDevicesReply::{ devices: devices.map(microphone_device_reply) }
}

///|
/// Builds the `microphone` extension for direct installation.
/// It currently exposes native device discovery and capture-config helpers from
/// the `justjavac/microphone` package.
pub fn extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) {
    extension.op("listDevices", fn(_payload : EmptyPayload) {
      let devices = @sys_microphone.MicrophoneDevice::list()
      emit_activity(extension, "listDevices", count=Some(devices.length()))
      microphone_devices_reply(devices)
    })

    extension.op("parseListing", fn(payload : ParseListingPayload) {
      let devices = @sys_microphone.MicrophoneDevice::parse_listing(
        payload.listing,
      )
      microphone_devices_reply(devices)
    })

    extension.op_result("config", fn(payload : CaptureConfigPayload) {
      build_capture_config(payload).map(capture_config_reply)
    })
  })
}

///|
/// Builds the declarative `microphone` extension spec.
/// Register this when microphone discovery helpers should be selected through
/// app composition or generated registry code.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
