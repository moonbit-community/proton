///|
priv struct NotificationNativeClick {
  payload : String?
}

///|
fn notification_native_ensure_supported() -> Unit raise NotificationError {
  let supported = @proton_native.notification_supported() catch {
    error => raise NativeCapability(error~)
  }
  guard supported else { raise UnsupportedPlatform }
}

///|
async fn notification_native_show(
  title : String,
  body : String,
  payload : String?,
) -> Unit raise NotificationError {
  let result = match payload {
    Some(payload) =>
      @proton.notification_show_and_wait(title, body, payload~) catch {
        error => raise NativeShow(error~)
      }
    None =>
      @proton.notification_show_and_wait(title, body) catch {
        error => raise NativeShow(error~)
      }
  }
  match result {
    @proton_native.NativeNotificationResult::Delivered => ()
    @proton_native.NativeNotificationResult::Failed(message) =>
      raise DeliveryFailed(message~)
  }
}

///|
fn notification_native_take_click() -> NotificationNativeClick? raise NotificationError {
  let click = @proton_native.notification_poll_click() catch {
    error => raise NativePoll(error~)
  }
  click.map(fn(click) { NotificationNativeClick::{ payload: click.payload } })
}

///|
fn notification_native_cleanup() -> Unit raise NotificationError {
  @proton_native.notification_cleanup() catch {
    error => raise NativeCleanup(error~)
  }
}
