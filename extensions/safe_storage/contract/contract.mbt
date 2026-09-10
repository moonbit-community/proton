///|
pub(all) struct EncryptRequest {
  value : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend EncryptRequest with ToJson::{to_json}

///|
pub extend EncryptRequest with FromJson::{from_json}

///|
pub extend EncryptRequest with Debug::{to_repr}

///|
pub extend EncryptRequest with Eq::{not_equal, equal}

///|
pub(all) struct EncryptReply {
  encrypted : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend EncryptReply with ToJson::{to_json}

///|
pub extend EncryptReply with FromJson::{from_json}

///|
pub extend EncryptReply with Debug::{to_repr}

///|
pub extend EncryptReply with Eq::{not_equal, equal}

///|
pub(all) struct DecryptRequest {
  encrypted : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DecryptRequest with ToJson::{to_json}

///|
pub extend DecryptRequest with FromJson::{from_json}

///|
pub extend DecryptRequest with Debug::{to_repr}

///|
pub extend DecryptRequest with Eq::{not_equal, equal}

///|
pub(all) struct DecryptReply {
  value : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DecryptReply with ToJson::{to_json}

///|
pub extend DecryptReply with FromJson::{from_json}

///|
pub extend DecryptReply with Debug::{to_repr}

///|
pub extend DecryptReply with Eq::{not_equal, equal}

///|
pub(all) struct AvailabilityReply {
  available : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend AvailabilityReply with ToJson::{to_json}

///|
pub extend AvailabilityReply with FromJson::{from_json}

///|
pub extend AvailabilityReply with Debug::{to_repr}

///|
pub extend AvailabilityReply with Eq::{not_equal, equal}

///|
pub let encrypt : @proton_contract.Command[EncryptRequest, EncryptReply] = extension.command(
  "encryptString",
)

///|
pub let decrypt : @proton_contract.Command[DecryptRequest, DecryptReply] = extension.command(
  "decryptString",
)

///|
pub let availability : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  AvailabilityReply,
] = extension.command("isAvailable")
