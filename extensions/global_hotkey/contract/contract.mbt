///|
pub(all) struct GlobalHotkeyRequest {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GlobalHotkeyRequest with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyRequest with Debug::{to_repr}

///|
pub extend GlobalHotkeyRequest with ToJson::{to_json}

///|
pub extend GlobalHotkeyRequest with FromJson::{from_json}

///|
pub(all) struct GlobalHotkeyReply {
  registered : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GlobalHotkeyReply with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyReply with Debug::{to_repr}

///|
pub extend GlobalHotkeyReply with ToJson::{to_json}

///|
pub extend GlobalHotkeyReply with FromJson::{from_json}

///|
pub(all) struct GlobalHotkeyListReply {
  accelerators : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GlobalHotkeyListReply with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyListReply with Debug::{to_repr}

///|
pub extend GlobalHotkeyListReply with ToJson::{to_json}

///|
pub extend GlobalHotkeyListReply with FromJson::{from_json}

///|
pub(all) struct GlobalHotkeyActivity {
  operation : String
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GlobalHotkeyActivity with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyActivity with Debug::{to_repr}

///|
pub extend GlobalHotkeyActivity with ToJson::{to_json}

///|
pub extend GlobalHotkeyActivity with FromJson::{from_json}

///|
pub(all) struct GlobalHotkeyTriggered {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend GlobalHotkeyTriggered with Eq::{not_equal, equal}

///|
pub extend GlobalHotkeyTriggered with Debug::{to_repr}

///|
pub extend GlobalHotkeyTriggered with ToJson::{to_json}

///|
pub extend GlobalHotkeyTriggered with FromJson::{from_json}

///|
pub let register : @proton_contract.Command[
  GlobalHotkeyRequest,
  GlobalHotkeyReply,
] = extension.command("register")

///|
pub let unregister : @proton_contract.Command[
  GlobalHotkeyRequest,
  GlobalHotkeyReply,
] = extension.command("unregister")

///|
pub let list : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  GlobalHotkeyListReply,
] = extension.command("list")

///|
pub let drain_triggered : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  GlobalHotkeyListReply,
] = extension.command("drainTriggered")

///|
pub let activity : @proton_contract.Event[GlobalHotkeyActivity] = extension.event(
  "activity",
)

///|
pub let triggered : @proton_contract.Event[GlobalHotkeyTriggered] = extension.event(
  "triggered",
)
