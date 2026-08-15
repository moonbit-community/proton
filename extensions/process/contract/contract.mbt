///|
pub(all) struct SpawnRequest {
  command : String
  args : Array[String]
  cwd : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SpawnRequest with Eq::{not_equal, equal}

///|
pub extend SpawnRequest with Debug::{to_repr}

///|
pub extend SpawnRequest with ToJson::{to_json}

///|
pub extend SpawnRequest with FromJson::{from_json}

///|
pub(all) struct SpawnReply {
  process_id : Int
  pid : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SpawnReply with Eq::{not_equal, equal}

///|
pub extend SpawnReply with Debug::{to_repr}

///|
pub extend SpawnReply with ToJson::{to_json}

///|
pub extend SpawnReply with FromJson::{from_json}

///|
pub(all) struct WaitRequest {
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend WaitRequest with Eq::{not_equal, equal}

///|
pub extend WaitRequest with Debug::{to_repr}

///|
pub extend WaitRequest with ToJson::{to_json}

///|
pub extend WaitRequest with FromJson::{from_json}

///|
pub(all) struct WaitReply {
  exit_code : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend WaitReply with Eq::{not_equal, equal}

///|
pub extend WaitReply with Debug::{to_repr}

///|
pub extend WaitReply with ToJson::{to_json}

///|
pub extend WaitReply with FromJson::{from_json}

///|
pub(all) struct KillRequest {
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KillRequest with Eq::{not_equal, equal}

///|
pub extend KillRequest with Debug::{to_repr}

///|
pub extend KillRequest with ToJson::{to_json}

///|
pub extend KillRequest with FromJson::{from_json}

///|
pub(all) struct KillReply {
  killed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend KillReply with Eq::{not_equal, equal}

///|
pub extend KillReply with Debug::{to_repr}

///|
pub extend KillReply with ToJson::{to_json}

///|
pub extend KillReply with FromJson::{from_json}

///|
pub(all) struct ProcessActivity {
  operation : String
  process_id : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ProcessActivity with Eq::{not_equal, equal}

///|
pub extend ProcessActivity with Debug::{to_repr}

///|
pub extend ProcessActivity with ToJson::{to_json}

///|
pub extend ProcessActivity with FromJson::{from_json}

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
