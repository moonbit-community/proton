///|
fn notification_native_ensure_supported() -> Unit raise NotificationError {
  let supported = @proton.notification_supported() catch {
    error => raise NativeOperation(detail=error.message())
  }
  guard supported else { raise UnsupportedPlatform }
}

///|
async fn notification_native_show(
  title : String,
  body : String,
  payload : String?,
) -> Unit raise NotificationError {
  match payload {
    Some(payload) =>
      @proton.notification_show_and_wait(title, body, payload~) catch {
        error => raise NativeOperation(detail=error.message())
      }
    None =>
      @proton.notification_show_and_wait(title, body) catch {
        error => raise NativeOperation(detail=error.message())
      }
  }
}

///|
fn notification_native_cleanup() -> Unit raise NotificationError {
  @proton.notification_cleanup() catch {
    error => raise NativeOperation(detail=error.message())
  }
}
