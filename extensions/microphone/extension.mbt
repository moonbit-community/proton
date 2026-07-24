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
#proton.event(name="activity")
struct MicrophoneActivity {
  operation : String
  count : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Converts a sample format label from JavaScript into the package enum.
fn parse_sample_format(
  sample_format : String?,
) -> @sys_microphone.SampleFormat? raise MicrophoneConfigError {
  match sample_format {
    Some("i16") => Some(I16)
    Some("u16") => Some(U16)
    Some("f32") => Some(F32)
    Some(value) => raise UnknownSampleFormat(format=value)
    None => None
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
/// Builds and normalizes one capture config from JavaScript payload data.
fn build_capture_config(
  payload : CaptureConfigPayload,
) -> @sys_microphone.CaptureConfig raise MicrophoneConfigError {
  let sample_format = parse_sample_format(payload.sample_format).unwrap_or(F32)
  @sys_microphone.CaptureConfig::new(
    channels=payload.channels.unwrap_or(1),
    sample_rate_hz=payload.sample_rate_hz.unwrap_or(48_000),
    sample_format~,
    echo_cancellation=payload.echo_cancellation.unwrap_or(false),
    noise_suppression=payload.noise_suppression.unwrap_or(false),
  ).normalized()
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
/// Lists native microphone devices from a generated app-command extension.
#proton.command(name="listDevices")
async fn list_devices(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> MicrophoneDevicesReply {
  let devices = @sys_microphone.MicrophoneDevice::list()
  emit_microphone_activity(context, MicrophoneActivity::{
    operation: "listDevices",
    count: Some(devices.length()),
  })
  microphone_devices_reply(devices)
}

///|
/// Parses a platform microphone listing from a generated app-command extension.
#proton.command(name="parseListing")
fn parse_listing(listing : String) -> MicrophoneDevicesReply {
  let devices = @sys_microphone.MicrophoneDevice::parse_listing(listing)
  microphone_devices_reply(devices)
}

///|
/// Builds a normalized capture config from a generated app-command extension.
#proton.command(name="config")
fn config(
  channels : Int?,
  sample_rate_hz : Int?,
  sample_format : String?,
  echo_cancellation : Bool?,
  noise_suppression : Bool?,
) -> CaptureConfigReply raise MicrophoneConfigError {
  capture_config_reply(
    build_capture_config(CaptureConfigPayload::{
      channels,
      sample_rate_hz,
      sample_format,
      echo_cancellation,
      noise_suppression,
    }),
  )
}
