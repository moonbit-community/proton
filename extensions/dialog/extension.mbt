///|
let message_command = @dialog_contract.message

///|
let confirm_command = @dialog_contract.confirm

///|
let open_file_command = @dialog_contract.open_file

///|
let save_file_command = @dialog_contract.save_file

///|
async fn[Reply] emit_command_result(
  context : @proton.CommandContext,
  reply : Reply,
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Reply {
  context.emit(@dialog_contract.activity, @dialog_contract.DialogActivity::{
    operation,
    path,
    level,
  })
  reply
}

///|
/// Shows a message dialog from a generated app-command extension.
#proton.command(contract=message_command)
async fn message(
  context : @proton.CommandContext,
  request : @dialog_contract.MessageRequest,
) -> @dialog_contract.MessageReply {
  let window = @native.WindowRef::unsafe_from_handle(context.window())
  emit_command_result(
    context,
    show_message_dialog(context, window, request),
    "message",
    level=request.level,
  )
}

///|
/// Shows a confirmation dialog from a generated app-command extension.
#proton.command(contract=confirm_command)
async fn confirm(
  context : @proton.CommandContext,
  request : @dialog_contract.MessageRequest,
) -> @dialog_contract.ConfirmReply {
  let window = @native.WindowRef::unsafe_from_handle(context.window())
  emit_command_result(
    context,
    confirm_message_dialog(context, window, request),
    "confirm",
    level=request.level,
  )
}

///|
/// Shows an open-file dialog from a generated app-command extension.
#proton.command(contract=open_file_command)
async fn open_file(
  context : @proton.CommandContext,
  request : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply {
  let window = @native.WindowRef::unsafe_from_handle(context.window())
  let reply = open_file_dialog(context, window, request)
  emit_command_result(context, reply, "openFile", path=reply.path)
}

///|
/// Shows a save-file dialog from a generated app-command extension.
#proton.command(contract=save_file_command)
async fn save_file(
  context : @proton.CommandContext,
  request : @dialog_contract.FileDialogRequest,
) -> @dialog_contract.FileDialogReply {
  let window = @native.WindowRef::unsafe_from_handle(context.window())
  let reply = save_file_dialog(context, window, request)
  emit_command_result(context, reply, "saveFile", path=reply.path)
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @dialog_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
