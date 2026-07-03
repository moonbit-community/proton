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
async fn show_message_dialog(
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[MessageReply, String] {
  match
    @native.show_message_dialog_async(
      window,
      payload.title,
      payload.message,
      level_to_native(payload.level),
    ) {
    Err(error) => Err(native_error_message(error))
    Ok(_) => Ok({ acknowledged: true })
  }
}

///|
async fn confirm_message_dialog(
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[ConfirmReply, String] {
  match
    @native.show_confirm_dialog_async(
      window,
      payload.title,
      payload.message,
      level_to_native(payload.level),
    ) {
    Err(error) => Err(native_error_message(error))
    Ok(confirmed) => Ok({ confirmed, })
  }
}

///|
async fn open_file_dialog(
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match @native.open_file_dialog_async(window, payload.title, payload.path) {
    Err(error) => Err(native_error_message(error))
    Ok(path) => Ok({ path, })
  }
}

///|
async fn save_file_dialog(
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match @native.save_file_dialog_async(window, payload.title, payload.path) {
    Err(error) => Err(native_error_message(error))
    Ok(path) => Ok({ path, })
  }
}
