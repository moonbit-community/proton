///|
struct NotificationPayload {
  title : String?
  body : String
  level : String?
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct NotificationReply {
  shown : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
struct EmptyPayload {} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="activity")
struct NotificationActivity {
  operation : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
struct NotificationDrainReply {
  count : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
#proton.event(name="click")
struct NotificationClick {
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
/// Rejects empty notification bodies before calling the native package.
fn ensure_body(body : String) -> String raise NotificationError {
  if body.is_empty() {
    raise EmptyBody
  } else {
    body
  }
}

///|
/// Shows one native notification and converts the result into the extension reply shape.
fn show_notification(
  payload : NotificationPayload,
) -> NotificationReply raise NotificationError {
  let body = ensure_body(payload.body)
  notification_native_ensure_supported()
  notification_native_show(
    payload.title.unwrap_or("Lepus"),
    body,
    payload.payload,
  )
  NotificationReply::{ shown: true }
}

///|
#proton.script
fn notification_click_poller_script() -> String {
  (
    #|(() => {
    #|  const root = window.__MoonBit__;
    #|  const notification = root && root.notification;
    #|  if (!notification || typeof notification.drainClicks !== "function") {
    #|    return;
    #|  }
    #|  if (notification.__protonClickPoller) {
    #|    return;
    #|  }
    #|  notification.__protonClickPoller = window.setInterval(() => {
    #|    notification.drainClicks({}).catch(() => {});
    #|  }, 100);
    #|})();
  )
}

///|
#proton.destroy
fn cleanup_notification(
  context : @proton_command.AppCommandExtensionContext,
) -> Unit raise NotificationError {
  ignore(context.extension_id())
  notification_native_cleanup()
}

///|
/// Shows one native notification from a generated app-command extension.
#proton.command(name="show")
async fn show(
  context : @proton_command.AppCommandExtensionContext,
  title : String?,
  body : String,
  level : String?,
  payload : String?,
) -> NotificationReply raise NotificationError {
  let request = NotificationPayload::{ title, body, level, payload }
  let reply = show_notification(request)
  emit_notification_activity(context, NotificationActivity::{
    operation: "show",
    title,
    level,
  })
  reply
}

///|
/// Drains native notification clicks into extension events.
#proton.command(name="drainClicks")
async fn drain_clicks(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> NotificationDrainReply raise NotificationError {
  let mut count = 0
  while true {
    match notification_native_take_click() {
      None => break
      Some(click) => {
        emit_notification_click(context, NotificationClick::{
          payload: click.payload,
        })
        count += 1
      }
    }
  }
  NotificationDrainReply::{ count, }
}
