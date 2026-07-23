///|
fn file_dialog_result_path(result : Result[FileDialogReply, String]) -> String? {
  match result {
    Ok(reply) => reply.path
    Err(_) => None
  }
}

///|
async fn[Reply] emit_command_result(
  context : @proton_command.AppCommandExtensionContext,
  result : Result[Reply, String],
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Result[Reply, String] {
  match result {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_dialog_activity(context, { operation, path, level })
      Ok(reply)
    }
  }
}

///|
/// Shows a message dialog from a generated app-command extension.
#proton.command(name="message")
async fn message(
  context : @proton_command.AppCommandExtensionContext,
  request_context : @proton_command.AppCommandRequestContext,
  message : String,
  title : String?,
  level : String?,
) -> Result[MessageReply, String] {
  let payload = MessagePayload::{ message, title, level }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  emit_command_result(
    context,
    show_message_dialog(request_context, window, payload),
    "message",
    level=payload.level,
  )
}

///|
/// Shows a confirmation dialog from a generated app-command extension.
#proton.command(name="confirm")
async fn confirm(
  context : @proton_command.AppCommandExtensionContext,
  request_context : @proton_command.AppCommandRequestContext,
  message : String,
  title : String?,
  level : String?,
) -> Result[ConfirmReply, String] {
  let payload = MessagePayload::{ message, title, level }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  emit_command_result(
    context,
    confirm_message_dialog(request_context, window, payload),
    "confirm",
    level=payload.level,
  )
}

///|
/// Shows an open-file dialog from a generated app-command extension.
#proton.command(name="openFile")
async fn open_file(
  context : @proton_command.AppCommandExtensionContext,
  request_context : @proton_command.AppCommandRequestContext,
  title : String?,
  path : String?,
) -> Result[FileDialogReply, String] {
  let payload = FileDialogPayload::{ title, path }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  let result = open_file_dialog(request_context, window, payload)
  let path = file_dialog_result_path(result)
  emit_command_result(context, result, "openFile", path~)
}

///|
/// Shows a save-file dialog from a generated app-command extension.
#proton.command(name="saveFile")
async fn save_file(
  context : @proton_command.AppCommandExtensionContext,
  request_context : @proton_command.AppCommandRequestContext,
  title : String?,
  path : String?,
) -> Result[FileDialogReply, String] {
  let payload = FileDialogPayload::{ title, path }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  let result = save_file_dialog(request_context, window, payload)
  let path = file_dialog_result_path(result)
  emit_command_result(context, result, "saveFile", path~)
}

///|
#proton.event(name="activity")
struct DialogActivity {
  operation : String
  path : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)
