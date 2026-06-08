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
extern "C" fn is_windows_ffi() -> Bool = "extensions_dialog_is_windows"

///|
#borrow(title, message)
extern "C" fn message_dialog_ffi(
  window : Int64,
  title : Bytes,
  message : Bytes,
  level : Int,
) -> Int = "extensions_dialog_message"

///|
#borrow(title, message)
extern "C" fn confirm_dialog_ffi(
  window : Int64,
  title : Bytes,
  message : Bytes,
  level : Int,
) -> Bool = "extensions_dialog_confirm"

///|
#borrow(title, path)
extern "C" fn open_file_dialog_ffi(
  window : Int64,
  title : Bytes,
  path : Bytes,
) -> Bytes = "extensions_dialog_open_file"

///|
#borrow(title, path)
extern "C" fn save_file_dialog_ffi(
  window : Int64,
  title : Bytes,
  path : Bytes,
) -> Bytes = "extensions_dialog_save_file"

///|
/// Verifies that native dialog support is available on the current platform.
fn ensure_supported() -> Result[Unit, String] {
  if is_windows_ffi() {
    Ok(())
  } else {
    Err("dialog extension currently supports Windows native builds only")
  }
}

///|
/// Runs a dialog operation only when native dialog support is available.
fn[Reply] with_supported(
  callback : () -> Result[Reply, String],
) -> Result[Reply, String] {
  match ensure_supported() {
    Err(error) => Err(error)
    Ok(_) => callback()
  }
}

///|
/// Encodes an optional string as a UTF-16 buffer expected by the native dialog API.
fn to_wstr(value : String?) -> Bytes {
  match value {
    Some(value) => @ffi.to_wstr(value)
    None => @ffi.to_wstr("")
  }
}

///|
/// Decodes an empty wide-string dialog path as `None`.
fn optional_path_from_wstr(bytes : Bytes) -> String? {
  let value = @ffi.from_wstr_lossy(bytes)
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// Maps the public dialog level string to the native integer code.
fn level_to_int(level : String?) -> Int {
  match level {
    Some("warning") => 1
    Some("error") => 2
    _ => 0
  }
}

///|
fn show_message_dialog(
  window : Int64,
  payload : MessagePayload,
) -> Result[MessageReply, String] {
  with_supported(fn() {
    ignore(
      message_dialog_ffi(
        window,
        to_wstr(payload.title),
        @ffi.to_wstr(payload.message),
        level_to_int(payload.level),
      ),
    )
    Ok({ acknowledged: true })
  })
}

///|
fn confirm_message_dialog(
  window : Int64,
  payload : MessagePayload,
) -> Result[ConfirmReply, String] {
  with_supported(fn() {
    let confirmed = confirm_dialog_ffi(
      window,
      to_wstr(payload.title),
      @ffi.to_wstr(payload.message),
      level_to_int(payload.level),
    )
    Ok({ confirmed, })
  })
}

///|
/// Runs an open/save file dialog callback and normalizes its optional path result.
fn file_dialog_path(
  window : Int64,
  payload : FileDialogPayload,
  callback : (Int64, Bytes, Bytes) -> Bytes,
) -> String? {
  optional_path_from_wstr(
    callback(window, to_wstr(payload.title), to_wstr(payload.path)),
  )
}

///|
fn open_file_dialog(
  window : Int64,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  with_supported(fn() {
    let path = file_dialog_path(window, payload, open_file_dialog_ffi)
    Ok({ path, })
  })
}

///|
fn save_file_dialog(
  window : Int64,
  payload : FileDialogPayload,
) -> Result[FileDialogReply, String] {
  with_supported(fn() {
    let path = file_dialog_path(window, payload, save_file_dialog_ffi)
    Ok({ path, })
  })
}
