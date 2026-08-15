///|
pub(all) struct ParseListingRequest {
  listing : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ParseListingRequest with Eq::{not_equal, equal}

///|
pub extend ParseListingRequest with Debug::{to_repr}

///|
pub extend ParseListingRequest with ToJson::{to_json}

///|
pub extend ParseListingRequest with FromJson::{from_json}

///|
pub(all) struct CaptureConfigRequest {
  channels : Int?
  sample_rate_hz : Int?
  sample_format : String?
  echo_cancellation : Bool?
  noise_suppression : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend CaptureConfigRequest with Eq::{not_equal, equal}

///|
pub extend CaptureConfigRequest with Debug::{to_repr}

///|
pub extend CaptureConfigRequest with ToJson::{to_json}

///|
pub extend CaptureConfigRequest with FromJson::{from_json}

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
pub extend CaptureConfigReply with Eq::{not_equal, equal}

///|
pub extend CaptureConfigReply with Debug::{to_repr}

///|
pub extend CaptureConfigReply with ToJson::{to_json}

///|
pub extend CaptureConfigReply with FromJson::{from_json}

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
pub extend MicrophoneDeviceReply with Eq::{not_equal, equal}

///|
pub extend MicrophoneDeviceReply with Debug::{to_repr}

///|
pub extend MicrophoneDeviceReply with ToJson::{to_json}

///|
pub extend MicrophoneDeviceReply with FromJson::{from_json}

///|
pub(all) struct MicrophoneDevicesReply {
  devices : Array[MicrophoneDeviceReply]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MicrophoneDevicesReply with Eq::{not_equal, equal}

///|
pub extend MicrophoneDevicesReply with Debug::{to_repr}

///|
pub extend MicrophoneDevicesReply with ToJson::{to_json}

///|
pub extend MicrophoneDevicesReply with FromJson::{from_json}

///|
pub(all) struct MicrophoneActivity {
  operation : String
  count : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MicrophoneActivity with Eq::{not_equal, equal}

///|
pub extend MicrophoneActivity with Debug::{to_repr}

///|
pub extend MicrophoneActivity with ToJson::{to_json}

///|
pub extend MicrophoneActivity with FromJson::{from_json}

///|
pub let list_devices : @proton_contract.Command[
  @proton_contract.EmptyRequest,
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
