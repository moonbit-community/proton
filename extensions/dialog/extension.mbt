///|
async fn[Reply] emit_command_result(
  context : @proton_command.AppCommandExtensionContext,
  reply : Reply,
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Reply noraise {
  emit_dialog_activity(context, { operation, path, level })
  reply
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
) -> MessageReply {
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
) -> ConfirmReply {
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
) -> FileDialogReply {
  let payload = FileDialogPayload::{ title, path }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  let reply = open_file_dialog(request_context, window, payload)
  emit_command_result(context, reply, "openFile", path=reply.path)
}

///|
/// Shows a save-file dialog from a generated app-command extension.
#proton.command(name="saveFile")
async fn save_file(
  context : @proton_command.AppCommandExtensionContext,
  request_context : @proton_command.AppCommandRequestContext,
  title : String?,
  path : String?,
) -> FileDialogReply {
  let payload = FileDialogPayload::{ title, path }
  let window = @native.WindowRef::unsafe_from_handle(request_context.window())
  let reply = save_file_dialog(request_context, window, payload)
  emit_command_result(context, reply, "saveFile", path=reply.path)
}

///|
#proton.event(name="activity")
struct DialogActivity {
  operation : String
  path : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)
