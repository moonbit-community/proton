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
        error => raise map_delivery_error(error)
      }
    None =>
      @proton.notification_show_and_wait(title, body) catch {
        error => raise map_delivery_error(error)
      }
  }
  match result {
    @proton_native.NativeNotificationResult::Delivered => ()
    @proton_native.NativeNotificationResult::Failed(message) =>
      raise DeliveryFailed(message~)
  }
}

///|
/// Translates the facade-level `NotificationDeliveryError` into the
/// extension's `NotificationError` so callers see a single native error type
/// (`@proton_native.NativeError`) instead of a mix of facade and native errors.
fn map_delivery_error(
  error : @proton.NotificationDeliveryError,
) -> NotificationError {
  match error {
    @proton.NotificationDeliveryError::Native(native_error) =>
      NativeShow(error=native_error)
    @proton.NotificationDeliveryError::WaitInterrupted(detail~) =>
      ShowWaitInterrupted(detail~)
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
