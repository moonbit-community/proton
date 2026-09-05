///|
pub(all) struct EncryptRequest {
  value : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct EncryptReply {
  encrypted : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct DecryptRequest {
  encrypted : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct DecryptReply {
  value : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct AvailabilityReply {
  available : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let encrypt : @proton_contract.Command[EncryptRequest, EncryptReply] = extension.command(
  "encryptString",
)

///|
pub let decrypt : @proton_contract.Command[DecryptRequest, DecryptReply] = extension.command(
  "decryptString",
)

///|
pub let availability : @proton_contract.Command[Json, AvailabilityReply] = extension.command(
  "isAvailable",
)
