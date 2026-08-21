///|
/// `level` is a reserved severity hint: today it is only echoed back in the
/// activity event and is not forwarded to the native backend.
pub(all) struct NotificationRequest {
  title : String?
  body : String
  level : String?
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend NotificationRequest with Eq::{not_equal, equal}

///|
pub extend NotificationRequest with Debug::{to_repr}

///|
pub extend NotificationRequest with ToJson::{to_json}

///|
pub extend NotificationRequest with FromJson::{from_json}

///|
pub(all) struct NotificationReply {
  shown : Bool
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend NotificationReply with Eq::{not_equal, equal}

///|
pub extend NotificationReply with Debug::{to_repr}

///|
pub extend NotificationReply with ToJson::{to_json}

///|
pub extend NotificationReply with FromJson::{from_json}

///|
pub(all) struct NotificationActivity {
  operation : String
  title : String?
  level : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend NotificationActivity with Eq::{not_equal, equal}

///|
pub extend NotificationActivity with Debug::{to_repr}

///|
pub extend NotificationActivity with ToJson::{to_json}

///|
pub extend NotificationActivity with FromJson::{from_json}

///|
pub(all) struct NotificationClick {
  payload : String?
} derive(ToJson, FromJson, Debug, Eq)

///|
pub extend NotificationClick with Eq::{not_equal, equal}

///|
pub extend NotificationClick with Debug::{to_repr}

///|
pub extend NotificationClick with ToJson::{to_json}

///|
pub extend NotificationClick with FromJson::{from_json}

///|
pub let show : @proton_contract.Command[NotificationRequest, NotificationReply] = extension.command(
  "show",
)

///|
pub let activity : @proton_contract.Event[NotificationActivity] = extension.event(
  "activity",
)

///|
pub let click : @proton_contract.Event[NotificationClick] = extension.event(
  "click",
)
