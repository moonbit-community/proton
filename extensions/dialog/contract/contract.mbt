///|
pub(all) struct MessageRequest {
  message : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MessageRequest with Eq::{not_equal, equal}

///|
pub extend MessageRequest with Debug::{to_repr}

///|
pub extend MessageRequest with ToJson::{to_json}

///|
pub extend MessageRequest with FromJson::{from_json}

///|
pub(all) struct FileDialogRequest {
  title : String?
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend FileDialogRequest with Eq::{not_equal, equal}

///|
pub extend FileDialogRequest with Debug::{to_repr}

///|
pub extend FileDialogRequest with ToJson::{to_json}

///|
pub extend FileDialogRequest with FromJson::{from_json}

///|
pub(all) struct MessageReply {
  acknowledged : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend MessageReply with Eq::{not_equal, equal}

///|
pub extend MessageReply with Debug::{to_repr}

///|
pub extend MessageReply with ToJson::{to_json}

///|
pub extend MessageReply with FromJson::{from_json}

///|
pub(all) struct ConfirmReply {
  confirmed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend ConfirmReply with Eq::{not_equal, equal}

///|
pub extend ConfirmReply with Debug::{to_repr}

///|
pub extend ConfirmReply with ToJson::{to_json}

///|
pub extend ConfirmReply with FromJson::{from_json}

///|
pub(all) struct FileDialogReply {
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend FileDialogReply with Eq::{not_equal, equal}

///|
pub extend FileDialogReply with Debug::{to_repr}

///|
pub extend FileDialogReply with ToJson::{to_json}

///|
pub extend FileDialogReply with FromJson::{from_json}

///|
pub(all) struct DialogActivity {
  operation : String
  path : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend DialogActivity with Eq::{not_equal, equal}

///|
pub extend DialogActivity with Debug::{to_repr}

///|
pub extend DialogActivity with ToJson::{to_json}

///|
pub extend DialogActivity with FromJson::{from_json}

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
