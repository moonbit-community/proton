///|
pub(all) struct IdleTimeReply {
  idle_seconds : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct PowerSourceReply {
  source : String
  battery_percent : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct PowerMonitorActivity {
  operation : String
} derive(ToJson, FromJson, Debug, Eq)

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
