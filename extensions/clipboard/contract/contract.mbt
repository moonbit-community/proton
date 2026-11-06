///|
/// Request to read plain text from the native clipboard.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ReadTextRequest {}

///|
pub extend ReadTextRequest with Eq::{not_equal, equal}

///|
pub extend ReadTextRequest with Debug::{to_repr}

///|
pub extend ReadTextRequest with ToJson::{to_json}

///|
pub extend ReadTextRequest with FromJson::{from_json}

///|
/// Request to write plain text to the native clipboard.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct WriteTextRequest {
  text : String
}

///|
pub extend WriteTextRequest with Eq::{not_equal, equal}

///|
pub extend WriteTextRequest with Debug::{to_repr}

///|
pub extend WriteTextRequest with ToJson::{to_json}

///|
pub extend WriteTextRequest with FromJson::{from_json}

///|
/// Request to clear the native clipboard.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ClearRequest {}

///|
pub extend ClearRequest with Eq::{not_equal, equal}

///|
pub extend ClearRequest with Debug::{to_repr}

///|
pub extend ClearRequest with ToJson::{to_json}

///|
pub extend ClearRequest with FromJson::{from_json}

///|
/// Current plain-text clipboard contents.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ReadTextReply {
  text : String?
}

///|
pub extend ReadTextReply with Eq::{not_equal, equal}

///|
pub extend ReadTextReply with Debug::{to_repr}

///|
pub extend ReadTextReply with ToJson::{to_json}

///|
pub extend ReadTextReply with FromJson::{from_json}

///|
/// Result of writing plain text to the clipboard.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct WriteTextReply {
  written : Bool
}

///|
pub extend WriteTextReply with Eq::{not_equal, equal}

///|
pub extend WriteTextReply with Debug::{to_repr}

///|
pub extend WriteTextReply with ToJson::{to_json}

///|
pub extend WriteTextReply with FromJson::{from_json}

///|
/// Result of clearing the clipboard.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ClearReply {
  cleared : Bool
}

///|
pub extend ClearReply with Eq::{not_equal, equal}

///|
pub extend ClearReply with Debug::{to_repr}

///|
pub extend ClearReply with ToJson::{to_json}

///|
pub extend ClearReply with FromJson::{from_json}

///|
/// One completed clipboard operation.
#derive(ToJson, FromJson, Debug, Eq)
pub(all) struct ClipboardActivity {
  operation : String
  text_length : Int32?
}

///|
pub extend ClipboardActivity with Eq::{not_equal, equal}

///|
pub extend ClipboardActivity with Debug::{to_repr}

///|
pub extend ClipboardActivity with ToJson::{to_json}

///|
pub extend ClipboardActivity with FromJson::{from_json}

///|
pub let read_text : @proton_contract.Command[ReadTextRequest, ReadTextReply] = extension.command(
  "readText",
)

///|
pub let write_text : @proton_contract.Command[WriteTextRequest, WriteTextReply] = extension.command(
  "writeText",
)

///|
pub let clear : @proton_contract.Command[ClearRequest, ClearReply] = extension.command(
  "clear",
)

///|
pub let activity : @proton_contract.Event[ClipboardActivity] = extension.event(
  "activity",
)
