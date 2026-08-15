///|
pub(all) struct IdleTimeReply {
  idle_seconds : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend IdleTimeReply with Eq::{not_equal, equal}

///|
pub extend IdleTimeReply with Debug::{to_repr}

///|
pub extend IdleTimeReply with ToJson::{to_json}

///|
pub extend IdleTimeReply with FromJson::{from_json}

///|
pub(all) struct PowerSourceReply {
  source : String
  battery_percent : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PowerSourceReply with Eq::{not_equal, equal}

///|
pub extend PowerSourceReply with Debug::{to_repr}

///|
pub extend PowerSourceReply with ToJson::{to_json}

///|
pub extend PowerSourceReply with FromJson::{from_json}

///|
pub(all) struct PowerMonitorActivity {
  operation : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend PowerMonitorActivity with Eq::{not_equal, equal}

///|
pub extend PowerMonitorActivity with Debug::{to_repr}

///|
pub extend PowerMonitorActivity with ToJson::{to_json}

///|
pub extend PowerMonitorActivity with FromJson::{from_json}

///|
pub let get_idle_time : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  IdleTimeReply,
] = extension.command("getIdleTime")

///|
pub let get_power_source : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  PowerSourceReply,
] = extension.command("getPowerSource")

///|
pub let activity : @proton_contract.Event[PowerMonitorActivity] = extension.event(
  "activity",
)
