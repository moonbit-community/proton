///|
pub(all) struct MessageRequest {
  message : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct FileDialogRequest {
  title : String?
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct MessageReply {
  acknowledged : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct ConfirmReply {
  confirmed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct FileDialogReply {
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct DialogActivity {
  operation : String
  path : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-dialog",
  js_namespace="dialog",
)

///|
pub let message : @proton_contract.Command[MessageRequest, MessageReply] = extension.command(
  "message",
)

///|
pub let confirm : @proton_contract.Command[MessageRequest, ConfirmReply] = extension.command(
  "confirm",
)

///|
pub let open_file : @proton_contract.Command[FileDialogRequest, FileDialogReply] = extension.command(
  "openFile",
)

///|
pub let save_file : @proton_contract.Command[FileDialogRequest, FileDialogReply] = extension.command(
  "saveFile",
)

///|
pub let activity : @proton_contract.Event[DialogActivity] = extension.event(
  "activity",
)
