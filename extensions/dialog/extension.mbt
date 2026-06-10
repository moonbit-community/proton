///|
fn file_dialog_result_path(result : Result[FileDialogReply, String]) -> String? {
  match result {
    Ok(reply) => reply.path
    Err(_) => None
  }
}

///|
async fn[Reply] emit_command_result(
  context : @app.AppCommandExtensionContext,
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
#lepus.command(name="message")
async fn message(
  context : @app.AppCommandExtensionContext,
  message : String,
  title : String?,
  level : String?,
) -> Result[MessageReply, String] {
  let payload = MessagePayload::{ message, title, level }
  emit_command_result(
    context,
    show_message_dialog(0, payload),
    "message",
    level=payload.level,
  )
}

///|
/// Shows a confirmation dialog from a generated app-command extension.
#lepus.command(name="confirm")
async fn confirm(
  context : @app.AppCommandExtensionContext,
  message : String,
  title : String?,
  level : String?,
) -> Result[ConfirmReply, String] {
  let payload = MessagePayload::{ message, title, level }
  emit_command_result(
    context,
    confirm_message_dialog(0, payload),
    "confirm",
    level=payload.level,
  )
}

///|
/// Shows an open-file dialog from a generated app-command extension.
#lepus.command(name="openFile")
async fn open_file(
  context : @app.AppCommandExtensionContext,
  title : String?,
  path : String?,
) -> Result[FileDialogReply, String] {
  let payload = FileDialogPayload::{ title, path }
  let result = open_file_dialog(0, payload)
  let path = file_dialog_result_path(result)
  emit_command_result(context, result, "openFile", path~)
}

///|
/// Shows a save-file dialog from a generated app-command extension.
#lepus.command(name="saveFile")
async fn save_file(
  context : @app.AppCommandExtensionContext,
  title : String?,
  path : String?,
) -> Result[FileDialogReply, String] {
  let payload = FileDialogPayload::{ title, path }
  let result = save_file_dialog(0, payload)
  let path = file_dialog_result_path(result)
  emit_command_result(context, result, "saveFile", path~)
}

///|
#lepus.event(name="activity")
struct DialogActivity {
  operation : String
  path : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)
