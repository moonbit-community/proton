///|
pub(all) struct SpawnRequest {
  command : String
  args : Array[String]
  cwd : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SpawnReply {
  process_id : Int
  pid : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct WaitRequest {
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct WaitReply {
  exit_code : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KillRequest {
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct KillReply {
  killed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ProcessActivity {
  operation : String
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let spawn : @proton_contract.Command[SpawnRequest, SpawnReply] = extension.command(
  "spawn",
)

///|
pub let wait : @proton_contract.Command[WaitRequest, WaitReply] = extension.command(
  "wait",
)

///|
pub let kill : @proton_contract.Command[KillRequest, KillReply] = extension.command(
  "kill",
)

///|
pub let activity : @proton_contract.Event[ProcessActivity] = extension.event(
  "activity",
)
