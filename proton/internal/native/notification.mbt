///|
/// Reports whether native notifications are available in the current process.
pub fn notification_supported() -> Bool raise NativeError {
  let supported = Ref(0)
  let status = @native_ffi.proton_notification_is_supported_ffi(supported)
  if status < 0 {
    raise native_error(status)
  } else {
    supported.val != 0
  }
}

///|
/// Schedules a native notification with an optional activation payload.
pub fn notification_show(
  title : String,
  body : String,
  payload? : String,
) -> Unit raise NativeError {
  let (payload_text, has_payload) = match payload {
    Some(value) => (value, 1)
    None => ("", 0)
  }
  check_status(
    @native_ffi.proton_notification_show_ffi(
      @ffi.to_cstr(title),
      @ffi.to_cstr(body),
      @ffi.to_cstr(payload_text),
      has_payload,
    ),
  )
}

///|
/// Sets the absolute application badge count. Zero clears the badge.
pub fn notification_set_badge_count(count : Int) -> Unit raise NativeError {
  if count < 0 {
    raise InvalidArgument(
      message="notification badge count must be non-negative",
    )
  }
  check_status(@native_ffi.proton_notification_set_badge_count_ffi(count))
}

///|
/// Releases process-level notification hooks installed by Proton.
pub fn notification_cleanup() -> Unit raise NativeError {
  check_status(@native_ffi.proton_notification_cleanup_ffi())
}
