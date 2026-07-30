///|
/// Request to read plain text from the native clipboard.
pub(all) struct ReadTextRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
/// Request to write plain text to the native clipboard.
pub(all) struct WriteTextRequest {
  text : String
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Current plain-text clipboard contents.
pub(all) struct ReadTextReply {
  text : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Result of writing plain text to the clipboard.
pub(all) struct WriteTextReply {
  written : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
/// One completed clipboard operation.
pub(all) struct ClipboardActivity {
  operation : String
  text_length : Int?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let read_text : @proton_contract.Command[ReadTextRequest, ReadTextReply] = extension.command(
  "readText",
)

///|
pub let write_text : @proton_contract.Command[WriteTextRequest, WriteTextReply] = extension.command(
  "writeText",
)

///|
pub let activity : @proton_contract.Event[ClipboardActivity] = extension.event(
  "activity",
)
