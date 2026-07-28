///|
pub(all) struct EmptyRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct GlobalHotkeyRequest {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct GlobalHotkeyReply {
  registered : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct GlobalHotkeyListReply {
  accelerators : Array[String]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct GlobalHotkeyActivity {
  operation : String
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct GlobalHotkeyTriggered {
  accelerator : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-global-hotkey",
  js_namespace="globalHotkey",
)

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
pub let list : @proton_contract.Command[EmptyRequest, GlobalHotkeyListReply] = extension.command(
  "list",
)

///|
pub let drain_triggered : @proton_contract.Command[
  EmptyRequest,
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
