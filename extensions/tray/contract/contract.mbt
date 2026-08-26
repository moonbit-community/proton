///|
pub(all) struct TrayMenuItem {
  id : String?
  label : String?
  kind : String?
  enabled : Bool?
  checked : Bool?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayMenuItem with Eq::{not_equal, equal}

///|
pub extend TrayMenuItem with Debug::{to_repr}

///|
pub extend TrayMenuItem with ToJson::{to_json}

///|
pub extend TrayMenuItem with FromJson::{from_json}

///|
pub(all) struct TrayMenu {
  items : Array[TrayMenuItem]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayMenu with Eq::{not_equal, equal}

///|
pub extend TrayMenu with Debug::{to_repr}

///|
pub extend TrayMenu with ToJson::{to_json}

///|
pub extend TrayMenu with FromJson::{from_json}

///|
pub(all) struct ShowRequest {
  icon : Json?
  tooltip : String?
  menu : TrayMenu?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ShowRequest with Eq::{not_equal, equal}

///|
pub extend ShowRequest with Debug::{to_repr}

///|
pub extend ShowRequest with ToJson::{to_json}

///|
pub extend ShowRequest with FromJson::{from_json}

///|
pub(all) struct SetIconRequest {
  icon : Json?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SetIconRequest with Eq::{not_equal, equal}

///|
pub extend SetIconRequest with Debug::{to_repr}

///|
pub extend SetIconRequest with ToJson::{to_json}

///|
pub extend SetIconRequest with FromJson::{from_json}

///|
pub(all) struct SetTooltipRequest {
  tooltip : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SetTooltipRequest with Eq::{not_equal, equal}

///|
pub extend SetTooltipRequest with Debug::{to_repr}

///|
pub extend SetTooltipRequest with ToJson::{to_json}

///|
pub extend SetTooltipRequest with FromJson::{from_json}

///|
pub(all) struct SetMenuRequest {
  items : Array[TrayMenuItem]
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend SetMenuRequest with Eq::{not_equal, equal}

///|
pub extend SetMenuRequest with Debug::{to_repr}

///|
pub extend SetMenuRequest with ToJson::{to_json}

///|
pub extend SetMenuRequest with FromJson::{from_json}

///|
pub(all) struct TrayReply {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayReply with Eq::{not_equal, equal}

///|
pub extend TrayReply with Debug::{to_repr}

///|
pub extend TrayReply with ToJson::{to_json}

///|
pub extend TrayReply with FromJson::{from_json}

///|
pub(all) struct TrayActivity {
  operation : String
  visible : Bool
  tooltip : String?
  icon : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayActivity with Eq::{not_equal, equal}

///|
pub extend TrayActivity with Debug::{to_repr}

///|
pub extend TrayActivity with ToJson::{to_json}

///|
pub extend TrayActivity with FromJson::{from_json}

///|
pub(all) struct TrayClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayClick with Eq::{not_equal, equal}

///|
pub extend TrayClick with Debug::{to_repr}

///|
pub extend TrayClick with ToJson::{to_json}

///|
pub extend TrayClick with FromJson::{from_json}

///|
pub(all) struct TrayRightClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayRightClick with Eq::{not_equal, equal}

///|
pub extend TrayRightClick with Debug::{to_repr}

///|
pub extend TrayRightClick with ToJson::{to_json}

///|
pub extend TrayRightClick with FromJson::{from_json}

///|
pub(all) struct TrayDoubleClick {
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayDoubleClick with Eq::{not_equal, equal}

///|
pub extend TrayDoubleClick with Debug::{to_repr}

///|
pub extend TrayDoubleClick with ToJson::{to_json}

///|
pub extend TrayDoubleClick with FromJson::{from_json}

///|
pub(all) struct TrayMenuItemClick {
  item_id : String
  visible : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend TrayMenuItemClick with Eq::{not_equal, equal}

///|
pub extend TrayMenuItemClick with Debug::{to_repr}

///|
pub extend TrayMenuItemClick with ToJson::{to_json}

///|
pub extend TrayMenuItemClick with FromJson::{from_json}

///|
pub let support : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  @proton_contract.SupportReply,
] = extension.command("support")

///|
pub let show : @proton_contract.Command[ShowRequest, TrayReply] = extension.command(
  "show",
)

///|
pub let hide : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  TrayReply,
] = extension.command("hide")

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
pub let destroy : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  TrayReply,
] = extension.command("destroy")

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
