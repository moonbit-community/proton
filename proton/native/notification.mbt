///|
const NOTIFICATION_CLICK_BUFFER_BYTES = 65536

///|
/// Reports whether native notifications are available in the current process.
pub fn notification_supported() -> Result[Bool, NativeError] {
  let supported = Ref(0)
  let status = proton_notification_is_supported_ffi(supported)
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(supported.val != 0)
  }
}

///|
/// Schedules a native notification with an optional activation payload.
pub fn notification_show(
  title : String,
  body : String,
  payload? : String,
) -> Result[Unit, NativeError] {
  let (payload_text, has_payload) = match payload {
    Some(value) => (value, 1)
    None => ("", 0)
  }
  status_to_result(
    proton_notification_show_ffi(
      @ffi.to_cstr(title),
      @ffi.to_cstr(body),
      @ffi.to_cstr(payload_text),
      has_payload,
    ),
  )
}

///|
/// Removes and returns the oldest pending notification activation.
pub fn notification_poll_click() -> Result[
  NativeNotificationClick?,
  NativeError,
] {
  let buffer = FixedArray::make(NOTIFICATION_CLICK_BUFFER_BYTES, b'\x00')
  let required = Ref(0)
  let has_payload = Ref(0)
  let available = Ref(0)
  let status = proton_notification_poll_click_ffi(
    buffer,
    buffer.length(),
    required,
    has_payload,
    available,
  )
  if status < 0 {
    Err(native_error(status))
  } else if available.val == 0 {
    Ok(None)
  } else {
    let payload = if has_payload.val == 0 {
      None
    } else {
      Some(@ffi.from_cstr(Bytes::from_array(buffer)))
    }
    Ok(Some(NativeNotificationClick::{ payload, }))
  }
}

///|
/// Releases process-level notification hooks installed by Proton.
pub fn notification_cleanup() -> Result[Unit, NativeError] {
  status_to_result(proton_notification_cleanup_ffi())
}
