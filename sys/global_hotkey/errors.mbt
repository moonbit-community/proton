///|
/// Declares shared error message helpers for the public API.
fn decode_error_message(bytes : Bytes, default : String) -> String {
  let value = @utf8.decode_lossy(bytes[:])
  if value.is_empty() {
    default
  } else {
    value
  }
}

///|
/// Returns the generic unsupported-platform message for this package.
fn unsupported_error_message() -> String {
  "global_hotkey supports Windows and macOS native builds, plus Linux native builds running on X11."
}

///|
/// Builds a fallback message for native initialization failures.
fn create_error_message() -> String {
  "global_hotkey failed to initialize the native backend"
}

///|
/// Builds a fallback message for native registration failures.
fn register_error_message(accelerator : String) -> String {
  "global_hotkey failed to register: " + accelerator
}

///|
/// Builds a fallback message for native unregistration failures.
fn unregister_error_message(accelerator : String) -> String {
  "global_hotkey failed to unregister: " + accelerator
}

///|
/// Builds a fallback message for operations attempted after destroy.
fn destroyed_error_message() -> String {
  "global_hotkey manager has already been destroyed"
}
