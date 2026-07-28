///|
pub(all) struct EmptyRequest {} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct NotificationRequest {
  title : String?
  body : String
  level : String?
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct NotificationReply {
  shown : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct NotificationDrainReply {
  count : Int
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct NotificationActivity {
  operation : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub(all) struct NotificationClick {
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub let extension : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="justjavac/proton-notification",
  js_namespace="notification",
)

///|
pub let show : @proton_contract.Command[NotificationRequest, NotificationReply] = extension.command(
  "show",
)

///|
pub let drain_clicks : @proton_contract.Command[
  EmptyRequest,
  NotificationDrainReply,
] = extension.command("drainClicks")

///|
pub let activity : @proton_contract.Event[NotificationActivity] = extension.event(
  "activity",
)

///|
pub let click : @proton_contract.Event[NotificationClick] = extension.event(
  "click",
)
