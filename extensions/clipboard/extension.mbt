///|
let read_text_command = @clipboard_contract.read_text

///|
let write_text_command = @clipboard_contract.write_text

///|
/// Reads plain text from the native clipboard.
#proton.command(contract=read_text_command)
async fn read_text(
  context : @proton.CommandContext,
  _request : @clipboard_contract.ReadTextRequest,
) -> @clipboard_contract.ReadTextReply {
  let reply = read_clipboard_text()
  context.emit(@clipboard_contract.activity, @clipboard_contract.ClipboardActivity::{
    operation: "readText",
    text_length: text_length(reply.text),
  })
  reply
}

///|
/// Writes plain text to the native clipboard.
#proton.command(contract=write_text_command)
async fn write_text(
  context : @proton.CommandContext,
  request : @clipboard_contract.WriteTextRequest,
) -> @clipboard_contract.WriteTextReply {
  let reply = write_clipboard_text(request.text)
  context.emit(@clipboard_contract.activity, @clipboard_contract.ClipboardActivity::{
    operation: "writeText",
    text_length: Some(request.text.length()),
  })
  reply
}

///|
/// Builds the typed clipboard extension.
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @clipboard_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
