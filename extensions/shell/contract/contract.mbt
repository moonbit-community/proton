///|
pub(all) struct OpenRequest {
  target : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend OpenRequest with Eq::{not_equal, equal}

///|
pub extend OpenRequest with Debug::{to_repr}

///|
pub extend OpenRequest with ToJson::{to_json}

///|
pub extend OpenRequest with FromJson::{from_json}

///|
pub(all) struct RevealItemRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend RevealItemRequest with Eq::{not_equal, equal}

///|
pub extend RevealItemRequest with Debug::{to_repr}

///|
pub extend RevealItemRequest with ToJson::{to_json}

///|
pub extend RevealItemRequest with FromJson::{from_json}

///|
pub(all) struct ShellReply {
  launched : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ShellReply with Eq::{not_equal, equal}

///|
pub extend ShellReply with Debug::{to_repr}

///|
pub extend ShellReply with ToJson::{to_json}

///|
pub extend ShellReply with FromJson::{from_json}

///|
pub(all) struct ShellActivity {
  operation : String
  target : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ShellActivity with Eq::{not_equal, equal}

///|
pub extend ShellActivity with Debug::{to_repr}

///|
pub extend ShellActivity with ToJson::{to_json}

///|
pub extend ShellActivity with FromJson::{from_json}

///|
pub let open : @proton_contract.Command[OpenRequest, ShellReply] = extension.command(
  "open",
)

///|
pub let reveal_item : @proton_contract.Command[RevealItemRequest, ShellReply] = extension.command(
  "revealItem",
)

///|
pub let activity : @proton_contract.Event[ShellActivity] = extension.event(
  "activity",
)
