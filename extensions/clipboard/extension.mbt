///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
/// Reads plain text from the native clipboard.
#proton.command(name="readText")
async fn read_text(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[ReadTextReply, String] {
  match read_clipboard_text() {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_clipboard_activity(context, ClipboardActivity::{
        operation: "readText",
        text_length: text_length(reply.text),
      })
      Ok(reply)
    }
  }
}

///|
/// Writes plain text to the native clipboard.
#proton.command(name="writeText")
async fn write_text(
  context : @proton_command.AppCommandExtensionContext,
  text : String,
) -> Result[WriteTextReply, String] {
  match write_clipboard_text(text) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_clipboard_activity(context, ClipboardActivity::{
        operation: "writeText",
        text_length: Some(text.length()),
      })
      Ok(reply)
    }
  }
}

///|
#proton.event(name="activity")
struct ClipboardActivity {
  operation : String
  text_length : Int?
} derive(ToJson, FromJson, Debug, Eq)
