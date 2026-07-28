///|
pub(all) struct EmptyRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ParseListingRequest {
  listing : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct CaptureConfigRequest {
  channels : Int?
  sample_rate_hz : Int?
  sample_format : String?
  echo_cancellation : Bool?
  noise_suppression : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct CaptureConfigReply {
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
pub(all) struct MicrophoneDeviceReply {
  id : String
  name : String
  state : String
  default_config : CaptureConfigReply
  monitor_supported : Bool
  live : Bool
  session_label : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MicrophoneDevicesReply {
  devices : Array[MicrophoneDeviceReply]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MicrophoneActivity {
  operation : String
  count : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-microphone",
  js_namespace="microphone",
)

///|
pub let list_devices : @proton_contract.Command[
  EmptyRequest,
  MicrophoneDevicesReply,
] = extension.command("listDevices")

///|
pub let parse_listing : @proton_contract.Command[
  ParseListingRequest,
  MicrophoneDevicesReply,
] = extension.command("parseListing")

///|
pub let config : @proton_contract.Command[
  CaptureConfigRequest,
  CaptureConfigReply,
] = extension.command("config")

///|
pub let activity : @proton_contract.Event[MicrophoneActivity] = extension.event(
  "activity",
)
