///|
pub(all) struct AcquireRequest {
  reason : String?
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KeepAwakeReply {
  active : Bool
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KeepAwakeActivity {
  operation : String
  scope : String?
} derive(ToJson, FromJson, Debug, Eq)

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
