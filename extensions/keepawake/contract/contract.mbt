///|
pub(all) struct AcquireRequest {
  reason : String?
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend AcquireRequest with Eq::{not_equal, equal}

///|
pub extend AcquireRequest with Debug::{to_repr}

///|
pub extend AcquireRequest with ToJson::{to_json}

///|
pub extend AcquireRequest with FromJson::{from_json}

///|
pub(all) struct KeepAwakeReply {
  active : Bool
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KeepAwakeReply with Eq::{not_equal, equal}

///|
pub extend KeepAwakeReply with Debug::{to_repr}

///|
pub extend KeepAwakeReply with ToJson::{to_json}

///|
pub extend KeepAwakeReply with FromJson::{from_json}

///|
pub(all) struct KeepAwakeActivity {
  operation : String
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KeepAwakeActivity with Eq::{not_equal, equal}

///|
pub extend KeepAwakeActivity with Debug::{to_repr}

///|
pub extend KeepAwakeActivity with ToJson::{to_json}

///|
pub extend KeepAwakeActivity with FromJson::{from_json}

///|
pub let acquire : @proton_contract.Command[AcquireRequest, KeepAwakeReply] = extension.command(
  "acquire",
)

///|
pub let release : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  KeepAwakeReply,
] = extension.command("release")

///|
pub let status : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  KeepAwakeReply,
] = extension.command("status")

///|
pub let activity : @proton_contract.Event[KeepAwakeActivity] = extension.event(
  "activity",
)
