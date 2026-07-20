///|
const NOTIFICATION_CLICK_BUFFER_BYTES = 65536

///|
extern "C" fn notification_native_is_supported_ffi() -> Bool = "extensions_notification_is_supported"

///|
#borrow(title, body, payload)
extern "C" fn notification_native_show_ffi(
  title : Bytes,
  body : Bytes,
  payload : Bytes,
  has_payload : Int,
) -> Int = "extensions_notification_show"

///|
#borrow(buffer, out_has_payload)
extern "C" fn notification_native_take_click_ffi(
  buffer : Bytes,
  buffer_len : Int,
  out_has_payload : Ref[Int],
) -> Int = "extensions_notification_take_click"

///|
extern "C" fn notification_native_cleanup_ffi() -> Unit = "extensions_notification_cleanup"

///|
priv struct NotificationNativeClick {
  payload : String?
}

///|
fn notification_native_error(status : Int) -> String {
  match status {
    -1 => "notification extension currently supports macOS app bundles only"
    -2 => "notifications require an app bundle with a bundle identifier"
    -3 => "another component already owns the app notification delegate"
    -4 => "notification title, body, or payload is invalid UTF-8"
    -5 => "notification payload exceeds 65535 UTF-8 bytes"
    -6 => "notification click buffer is too small"
    _ => "native notification operation failed with status \{status}"
  }
}

///|
fn notification_native_ensure_supported() -> Result[Unit, String] {
  if notification_native_is_supported_ffi() {
    Ok(())
  } else {
    Err("notification extension currently supports macOS app bundles only")
  }
}

///|
fn notification_native_show(
  title : String,
  body : String,
  payload : String?,
) -> Result[Unit, String] {
  let (payload_text, has_payload) = match payload {
    Some(value) => (value, 1)
    None => ("", 0)
  }
  let status = notification_native_show_ffi(
    @ffi.to_cstr(title),
    @ffi.to_cstr(body),
    @ffi.to_cstr(payload_text),
    has_payload,
  )
  if status < 0 {
    Err(notification_native_error(status))
  } else {
    Ok(())
  }
}

///|
fn notification_native_take_click() -> Result[NotificationNativeClick?, String] {
  let buffer = Bytes::make(NOTIFICATION_CLICK_BUFFER_BYTES, b'\x00')
  let has_payload = Ref(0)
  let status = notification_native_take_click_ffi(
    buffer,
    buffer.length(),
    has_payload,
  )
  if status < 0 {
    Err(notification_native_error(status))
  } else if status == 0 {
    Ok(None)
  } else {
    let payload = if has_payload.val == 0 {
      None
    } else {
      Some(@ffi.from_cstr(buffer[0:status].to_owned()))
    }
    Ok(Some(NotificationNativeClick::{ payload, }))
  }
}

///|
fn notification_native_cleanup() -> Unit {
  notification_native_cleanup_ffi()
}
