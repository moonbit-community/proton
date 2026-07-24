///|
priv struct NotificationNativeClick {
  payload : String?
}

///|
fn notification_native_ensure_supported() -> Result[Unit, String] {
  @proton_native.notification_supported()
  .map_err(fn(error) { error.message })
  .bind(fn(supported) {
    if supported {
      Ok(())
    } else {
      Err("native notifications are not implemented on this platform")
    }
  })
}

///|
fn notification_native_show(
  title : String,
  body : String,
  payload : String?,
) -> Result[Unit, String] {
  match payload {
    Some(payload) =>
      @proton_native.notification_show(title, body, payload~).map_err(fn(
        error,
      ) {
        error.message
      })
    None =>
      @proton_native.notification_show(title, body).map_err(fn(error) {
        error.message
      })
  }
}

///|
fn notification_native_take_click() -> Result[NotificationNativeClick?, String] {
  @proton_native.notification_poll_click()
  .map_err(fn(error) { error.message })
  .map(fn(click) {
    click.map(fn(click) { NotificationNativeClick::{ payload: click.payload } })
  })
}

///|
fn notification_native_cleanup() -> Unit {
  ignore(@proton_native.notification_cleanup())
}
