///|
let extension_id = "justjavac/lepus-dialog"

///|
let extension_namespace = "dialog"

///|
/// Emits a dialog activity event for JavaScript listeners.
fn emit_core_activity(
  extension : @core.ExtensionContext,
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Unit {
  extension.emit("activity", DialogActivity::{ operation, path, level })
}

///|
/// Emits a dialog activity event for generated app-command listeners.
async fn emit_command_activity(
  context : @app.AppCommandExtensionContext,
  operation : String,
  path? : String? = None,
  level? : String? = None,
) -> Unit {
  emit_dialog_activity(context, DialogActivity::{ operation, path, level })
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
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => {
      let reply = show_message(0, payload)
      emit_command_activity(context, "message", level=payload.level)
      Ok(reply)
    }
  }
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
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => {
      let reply = confirm_message(0, payload)
      emit_command_activity(context, "confirm", level=payload.level)
      Ok(reply)
    }
  }
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
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => {
      let path = file_dialog_path(0, payload, open_file_dialog_ffi)
      emit_command_activity(context, "openFile", path~)
      Ok(FileDialogReply::{ path, })
    }
  }
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
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => {
      let path = file_dialog_path(0, payload, save_file_dialog_ffi)
      emit_command_activity(context, "saveFile", path~)
      Ok(FileDialogReply::{ path, })
    }
  }
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
      with_supported(fn() {
        let reply = show_message(window, payload)
        emit_core_activity(extension, "message", level=payload.level)
        Ok(reply)
      })
    })

    extension.op_result("confirm", fn(payload : MessagePayload) {
      with_supported(fn() {
        let reply = confirm_message(window, payload)
        emit_core_activity(extension, "confirm", level=payload.level)
        Ok(reply)
      })
    })

    extension.op_result("openFile", fn(payload : FileDialogPayload) {
      with_supported(fn() {
        let path = file_dialog_path(window, payload, open_file_dialog_ffi)
        emit_core_activity(extension, "openFile", path~)
        Ok(FileDialogReply::{ path, })
      })
    })

    extension.op_result("saveFile", fn(payload : FileDialogPayload) {
      with_supported(fn() {
        let path = file_dialog_path(window, payload, save_file_dialog_ffi)
        emit_core_activity(extension, "saveFile", path~)
        Ok(FileDialogReply::{ path, })
      })
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
