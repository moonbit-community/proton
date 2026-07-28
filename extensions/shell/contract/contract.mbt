///|
pub(all) struct OpenRequest {
  target : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct RevealItemRequest {
  path : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ShellReply {
  launched : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ShellActivity {
  operation : String
  target : String
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-shell",
  js_namespace="shell",
)

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
