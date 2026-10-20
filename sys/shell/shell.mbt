///|
/// Returns the shared unsupported-platform error message.
fn unsupported_error_message() -> String {
  "shell package currently supports Windows, macOS, and Linux native builds"
}

///|
/// Returns `true` when the current native target has a shell backend that
/// this package knows how to call.
pub fn is_supported() -> Bool {
  is_supported_ffi()
}

///|
/// Verifies that the current native platform is supported by this package.
///
/// Returns `Ok(())` on supported platforms and an explanatory `Err(String)` on
/// unsupported targets.
pub fn ensure_supported() -> Result[Unit, String] {
  if is_supported() {
    Ok(())
  } else {
    Err(unsupported_error_message())
  }
}

///|
/// Opens a URL or filesystem path with its default application.
///
/// Uses ShellExecuteW on Windows, /usr/bin/open on macOS, and gio open on Linux.
/// Linux requires gio and a desktop session with a default handler. Returns
/// `Ok(())` on success or `Err(String)` on unsupported platforms or launch
/// failures. Success means the platform accepted the request; it does not wait
/// for the target application to finish starting.
pub fn open(target : String) -> Result[Unit, String] {
  if !is_supported() {
    return Err(unsupported_error_message())
  }
  if open_ffi(@ffi.to_cstr(target)) {
    Ok(())
  } else {
    Err("shell.open failed")
  }
}

///|
/// Opens the native file manager and selects the filesystem entry at `path`.
///
/// Uses Explorer on Windows, /usr/bin/open -R on macOS, and FileManager1
/// ShowItems via dbus-send on Linux. Linux requires dbus-send and a file manager
/// implementing that session-bus interface. Returns `Ok(())`
/// on success or `Err(String)` on unsupported platforms or launch failures.
pub fn reveal_item(path : String) -> Result[Unit, String] {
  if !is_supported() {
    return Err(unsupported_error_message())
  }
  if reveal_item_ffi(@ffi.to_cstr(path)) {
    Ok(())
  } else {
    Err("shell.revealItem failed")
  }
}

///|
/// Moves `path` to the operating-system trash or recycle bin.
///
/// On Windows this uses the recycle bin (the item can still be restored), on
/// macOS this uses the Finder Trash (supporting "Put Back"), and on Linux this
/// delegates to `gio trash`. Returns `Err(String)` on unsupported platforms or
/// when the item could not be trashed.
pub fn trash_item(path : String) -> Result[Unit, String] {
  if !is_supported() {
    return Err(unsupported_error_message())
  }
  if trash_item_ffi(@ffi.to_cstr(path)) {
    Ok(())
  } else {
    Err("shell.trashItem failed")
  }
}

///|
/// Plays the operating system's default alert sound.
///
/// On Windows this calls `MessageBeep`. On macOS and Linux it writes the
/// terminal bell escape to stderr. Returns `Ok(())` when the platform has a
/// beep backend.
pub fn beep() -> Result[Unit, String] {
  if !is_supported() {
    return Err(unsupported_error_message())
  }
  if beep_ffi() {
    Ok(())
  } else {
    Err("shell.beep failed")
  }
}
