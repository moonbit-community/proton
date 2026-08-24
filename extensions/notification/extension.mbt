///|
let show_command = @notification_contract.show

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
async fn show_notification(
  payload : @notification_contract.NotificationRequest,
) -> @notification_contract.NotificationReply raise NotificationError {
  let body = ensure_body(payload.body)
  notification_native_ensure_supported()
  notification_native_show(payload.title.unwrap_or(""), body, payload.payload)
  @notification_contract.NotificationReply::{ shown: true }
}

///|
fn cleanup_notification() -> Unit raise NotificationError {
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
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @notification_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() raise { cleanup_notification() },
  )
}

///|
/// Grants notification commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
