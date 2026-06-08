///|
let extension_id = "justjavac/lepus-dialog"

///|
let extension_namespace = "dialog"

///|
fn[Reply] emit_core_result(
  result : Result[Reply, String],
  extension : @core.ExtensionContext,
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Result[Reply, String] {
  result.map(fn(reply) {
    extension.emit("activity", { operation, path, level })
    reply
  })
}

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

///|
/// Builds the native `dialog` extension for direct installation.
///
/// Exposes `message`, `confirm`, `openFile`, and `saveFile` through
/// `window.__MoonBit__.dialog`.
pub fn extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) {
    let window = extension.webview().get_window()

    extension.op_result("message", fn(payload : MessagePayload) {
      emit_core_result(
        show_message_dialog(window, payload),
        extension,
        "message",
        level=payload.level,
      )
    })

    extension.op_result("confirm", fn(payload : MessagePayload) {
      emit_core_result(
        confirm_message_dialog(window, payload),
        extension,
        "confirm",
        level=payload.level,
      )
    })

    extension.op_result("openFile", fn(payload : FileDialogPayload) {
      let result = open_file_dialog(window, payload)
      let path = file_dialog_result_path(result)
      emit_core_result(result, extension, "openFile", path~)
    })

    extension.op_result("saveFile", fn(payload : FileDialogPayload) {
      let result = save_file_dialog(window, payload)
      let path = file_dialog_result_path(result)
      emit_core_result(result, extension, "saveFile", path~)
    })
  })
}

///|
/// Builds the declarative `dialog` extension spec.
/// Register this spec when dialog support should be linked declaratively instead
/// of installed by hand on a single webview.
pub fn spec() -> @core.ExtensionSpec {
  @core.ExtensionSpec::new(extension_id, extension_namespace, fn(_context) {
    Ok(extension())
  })
}
