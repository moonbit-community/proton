///|
struct NotificationPayload {
  title : String?
  body : String
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct NotificationReply {
  shown : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
#lepus.event(name="activity")
struct NotificationActivity {
  operation : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Verifies that native notification support is available on this platform.
fn ensure_supported() -> Result[Unit, String] {
  @sys_notification.ensure_supported()
}

///|
/// Runs a notification operation only when the platform is supported.
fn[Reply] with_supported(
  callback : () -> Result[Reply, String],
) -> Result[Reply, String] {
  ensure_supported().bind(fn(_) { callback() })
}

///|
/// Rejects empty notification bodies before calling the native package.
fn ensure_body(body : String) -> Result[String, String] {
  if body.is_empty() {
    Err("notification body must not be empty")
  } else {
    Ok(body)
  }
}

///|
/// Maps the public notification level string to the native enum.
fn level_to_native(level : String?) -> @sys_notification.NotificationLevel {
  match level {
    Some("warning") => @sys_notification.NotificationLevel::Warning
    Some("error") => @sys_notification.NotificationLevel::Error
    _ => @sys_notification.NotificationLevel::Info
  }
}

///|
/// Shows one native notification and converts the result into the extension reply shape.
fn show_notification(
  payload : NotificationPayload,
) -> Result[NotificationReply, String] {
  ensure_body(payload.body).bind(fn(body) {
    @sys_notification.show(
      body,
      title=payload.title,
      level=level_to_native(payload.level),
    ).map(fn(_) { NotificationReply::{ shown: true } })
  })
}

///|
/// Shows one native notification from a generated app-command extension.
#lepus.command(name="show")
async fn show(
  context : @lepus.AppCommandExtensionContext,
  title : String?,
  body : String,
  level : String?,
) -> Result[NotificationReply, String] {
  let payload = NotificationPayload::{ title, body, level }
  match with_supported(fn() { show_notification(payload) }) {
    Err(error) => Err(error)
    Ok(reply) => {
      emit_notification_activity(context, NotificationActivity::{
        operation: "show",
        title,
        level,
      })
      Ok(reply)
    }
  }
}
