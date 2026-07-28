///|
pub(all) struct EmptyRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayMenuItem {
  id : String?
  label : String?
  kind : String?
  enabled : Bool?
  checked : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayMenu {
  items : Array[TrayMenuItem]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ShowRequest {
  icon : Json?
  tooltip : String?
  menu : TrayMenu?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SetIconRequest {
  icon : Json?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SetTooltipRequest {
  tooltip : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct SetMenuRequest {
  items : Array[TrayMenuItem]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayReply {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TraySupportReply {
  supported : Bool
  platform : String
  reason : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayEventReply {
  count : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayActivity {
  operation : String
  visible : Bool
  tooltip : String?
  icon : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayRightClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayDoubleClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct TrayMenuItemClick {
  item_id : String
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-tray",
  js_namespace="tray",
)

///|
pub let support : @proton_contract.Command[EmptyRequest, TraySupportReply] = extension.command(
  "support",
)

///|
pub let show : @proton_contract.Command[ShowRequest, TrayReply] = extension.command(
  "show",
)

///|
pub let hide : @proton_contract.Command[EmptyRequest, TrayReply] = extension.command(
  "hide",
)

///|
pub let set_icon : @proton_contract.Command[SetIconRequest, TrayReply] = extension.command(
  "setIcon",
)

///|
pub let set_tooltip : @proton_contract.Command[SetTooltipRequest, TrayReply] = extension.command(
  "setTooltip",
)

///|
pub let set_menu : @proton_contract.Command[SetMenuRequest, TrayReply] = extension.command(
  "setMenu",
)

///|
pub let drain_events : @proton_contract.Command[EmptyRequest, TrayEventReply] = extension.command(
  "drainEvents",
)

///|
pub let destroy : @proton_contract.Command[EmptyRequest, TrayReply] = extension.command(
  "destroy",
)

///|
pub let activity : @proton_contract.Event[TrayActivity] = extension.event(
  "activity",
)

///|
pub let click : @proton_contract.Event[TrayClick] = extension.event("click")

///|
pub let right_click : @proton_contract.Event[TrayRightClick] = extension.event(
  "rightClick",
)

///|
pub let double_click : @proton_contract.Event[TrayDoubleClick] = extension.event(
  "doubleClick",
)

///|
pub let menu_item_click : @proton_contract.Event[TrayMenuItemClick] = extension.event(
  "menuItemClick",
)
