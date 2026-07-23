///|
struct MessagePayload {
  message : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct MessageReply {
  acknowledged : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct ConfirmReply {
  confirmed : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct FileDialogPayload {
  title : String?
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct FileDialogReply {
  path : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
fn native_error_message(error : @native.NativeError) -> String {
  if error.message.is_empty() {
    "dialog operation failed"
  } else {
    error.message
  }
}

///|
/// Maps the public dialog level string to the native dialog level.
fn level_to_native(level : String?) -> @native.DialogLevel {
  match level {
    Some("warning") => @native.DialogLevel::Warning
    Some("error") => @native.DialogLevel::Error
    _ => @native.DialogLevel::Info
  }
}

///|
async fn wait_for_dialog_result(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  dialog : Int64,
) -> Result[String, @native.NativeError] {
  while true {
    let revision = request_context.wake_revision()
    match window.poll_dialog_result(dialog) {
      Err(error) => return Err(error)
      Ok(@native.DialogPollResult::Ready(result)) => return Ok(result)
      Ok(@native.DialogPollResult::Pending) =>
        request_context.wait_for_wake(revision)
    }
  }
  Err({ status: -6, message: "dialog wait exited unexpectedly" })
}

///|
async fn show_message_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[MessageReply, String] {
  let dialog = match
    window.begin_message_dialog(
      payload.title,
      payload.message,
      level_to_native(payload.level),
    ) {
    Err(error) => Err(native_error_message(error))
    Ok(dialog) => Ok(dialog)
  }
  match dialog {
    Err(error) => Err(error)
    Ok(dialog) =>
      wait_for_dialog_result(request_context, window, dialog)
      .map_err(native_error_message)
      .map(fn(_) { { acknowledged: true } })
  }
}

///|
async fn confirm_message_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[ConfirmReply, String] {
  let dialog = match
    window.begin_confirm_dialog(
      payload.title,
      payload.message,
      level_to_native(payload.level),
    ) {
    Err(error) => Err(native_error_message(error))
    Ok(dialog) => Ok(dialog)
  }
  match dialog {
    Err(error) => Err(error)
    Ok(dialog) =>
      wait_for_dialog_result(request_context, window, dialog)
      .map_err(native_error_message)
      .map(fn(result) { { confirmed: result == "1" } })
  }
}

///|
async fn open_file_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match window.begin_open_file_dialog(payload.title, payload.path) {
    Err(error) => Err(native_error_message(error))
    Ok(dialog) =>
      wait_for_dialog_result(request_context, window, dialog)
      .map_err(native_error_message)
      .map(fn(path) {
        { path: if path.is_empty() { None } else { Some(path) } }
      })
  }
}

///|
async fn save_file_dialog(
  request_context : @proton_command.AppCommandRequestContext,
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match window.begin_save_file_dialog(payload.title, payload.path) {
    Err(error) => Err(native_error_message(error))
    Ok(dialog) =>
      wait_for_dialog_result(request_context, window, dialog)
      .map_err(native_error_message)
      .map(fn(path) {
        { path: if path.is_empty() { None } else { Some(path) } }
      })
  }
}
