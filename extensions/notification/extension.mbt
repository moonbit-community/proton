///|
let show_command = @notification_contract.show

///|
let drain_clicks_command = @notification_contract.drain_clicks

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
  payload : @notification_contract.NotificationRequest,
) -> @notification_contract.NotificationReply raise NotificationError {
  let body = ensure_body(payload.body)
  notification_native_ensure_supported()
  notification_native_show(
    payload.title.unwrap_or("Lepus"),
    body,
    payload.payload,
  )
  @notification_contract.NotificationReply::{ shown: true }
}

///|
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
fn cleanup_notification(
  context : @proton_command.AppCommandExtensionContext,
) -> Unit raise NotificationError {
  ignore(context.extension_id())
  notification_native_cleanup()
}

///|
/// Shows one native notification from a generated app-command extension.
#proton.command(contract=show_command)
async fn show(
  context : @proton.CommandContext,
  request : @notification_contract.NotificationRequest,
) -> @notification_contract.NotificationReply {
  let reply = show_notification(request)
  context.emit(@notification_contract.activity, @notification_contract.NotificationActivity::{
    operation: "show",
    title: request.title,
    level: request.level,
  })
  reply
}

///|
/// Drains native notification clicks into extension events.
#proton.command(contract=drain_clicks_command)
async fn drain_clicks(
  context : @proton.CommandContext,
  _request : @notification_contract.EmptyRequest,
) -> @notification_contract.NotificationDrainReply {
  let mut count = 0
  while true {
    match notification_native_take_click() {
      None => break
      Some(click) => {
        context.emit(@notification_contract.click, @notification_contract.NotificationClick::{
          payload: click.payload,
        })
        count += 1
      }
    }
  }
  @notification_contract.NotificationDrainReply::{ count, }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(_context, registrar) raise { register_commands(registrar) },
    scripts=[notification_click_poller_script()],
    on_destroy=fn(context) raise { cleanup_notification(context) },
  )
}
