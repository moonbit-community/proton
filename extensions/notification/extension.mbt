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
fn ensure_body(body : String) -> Result[String, String] {
  if body.is_empty() {
    Err("notification body must not be empty")
  } else {
    Ok(body)
  }
}

///|
/// Shows one native notification and converts the result into the extension reply shape.
fn show_notification(
  payload : NotificationPayload,
) -> Result[NotificationReply, String] {
  ensure_body(payload.body).bind(fn(body) {
    notification_native_ensure_supported().bind(fn(_) {
      notification_native_show(
        payload.title.unwrap_or("Lepus"),
        body,
        payload.payload,
      ).map(fn(_) { NotificationReply::{ shown: true } })
    })
  })
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
) -> Unit {
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
) -> Result[NotificationReply, String] {
  let request = NotificationPayload::{ title, body, level, payload }
  match show_notification(request) {
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

///|
/// Drains native notification clicks into extension events.
#proton.command(name="drainClicks")
async fn drain_clicks(
  context : @proton_command.AppCommandExtensionContext,
  _payload : EmptyPayload?,
) -> Result[NotificationDrainReply, String] {
  let mut count = 0
  while true {
    match notification_native_take_click() {
      Err(error) => return Err(error)
      Ok(None) => break
      Ok(Some(click)) => {
        emit_notification_click(context, NotificationClick::{
          payload: click.payload,
        })
        count += 1
      }
    }
  }
  Ok(NotificationDrainReply::{ count, })
}
