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
fn show_message_dialog(
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[MessageReply, String] {
  match
    @native.show_message_dialog(
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
fn confirm_message_dialog(
  window : @native.WindowRef,
  payload : MessagePayload,
) -> Result[ConfirmReply, String] {
  match
    @native.show_confirm_dialog(
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
async fn pick_file_dialog(
  window : @native.WindowRef,
  payload : FileDialogPayload,
  mode : @native.FileDialogMode,
) -> Result[String?, String] {
  match (payload.title, payload.path) {
    (None, None) => @proton.pick_file_dialog(window, mode~)
    (Some(title), None) => @proton.pick_file_dialog(window, title~, mode~)
    (None, Some(initial_path)) =>
      @proton.pick_file_dialog(window, initial_path~, mode~)
    (Some(title), Some(initial_path)) =>
      @proton.pick_file_dialog(window, title~, initial_path~, mode~)
  }
}

///|
async fn open_file_dialog(
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match pick_file_dialog(window, payload, OpenFile) {
    Err(error) => Err(error)
    Ok(path) => Ok({ path, })
  }
}

///|
async fn save_file_dialog(
  window : @native.WindowRef,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  match pick_file_dialog(window, payload, SaveFile) {
    Err(error) => Err(error)
    Ok(path) => Ok({ path, })
  }
}
