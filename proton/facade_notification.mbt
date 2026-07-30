///|
priv struct NotificationResultBroker {
  mut busy : Bool
  gate : @async.CondVar
  results : Array[@native.NativeNotificationResult]
  result_ready : @async.CondVar
}

///|
let notification_result_broker : NotificationResultBroker = NotificationResultBroker::{
  busy: false,
  gate: @async.CondVar::Cond(),
  results: [],
  result_ready: @async.CondVar::Cond(),
}

///|
async fn acquire_notification_result_slot() -> Unit {
  while notification_result_broker.busy {
    notification_result_broker.gate.wait()
  }
  notification_result_broker.busy = true
}

///|
fn release_notification_result_slot() -> Unit {
  notification_result_broker.busy = false
  notification_result_broker.gate.broadcast()
}

///|
fn publish_notification_result(
  result : @native.NativeNotificationResult,
) -> Unit {
  if notification_result_broker.busy {
    notification_result_broker.results.push(result)
    notification_result_broker.result_ready.broadcast()
  }
}

///|
async fn take_notification_result() -> @native.NativeNotificationResult {
  while notification_result_broker.results.length() == 0 {
    notification_result_broker.result_ready.wait()
  }
  let result = notification_result_broker.results[0]
  ignore(notification_result_broker.results.remove(0))
  result
}

///|
/// Failures while starting or waiting for native notification delivery.
pub(all) suberror NotificationDeliveryError {
  Native(@native.NativeError)
  WaitInterrupted(detail~ : String)
} derive(Debug, Eq)

///|
pub fn NotificationDeliveryError::message(
  self : NotificationDeliveryError,
) -> String {
  match self {
    Native(error) => error.message()
    WaitInterrupted(detail~) =>
      "notification delivery wait was interrupted: " + detail
  }
}

///|
/// Starts one native notification and waits until macOS reports authorization
/// and delivery completion.
#doc(hidden)
pub async fn notification_show_and_wait(
  title : String,
  body : String,
  payload? : String,
) -> @native.NativeNotificationResult raise NotificationDeliveryError {
  acquire_notification_result_slot() catch {
    error => raise WaitInterrupted(detail=@debug.render(Repr(error)))
  }
  defer release_notification_result_slot()
  @native.notification_show(title, body, payload?) catch {
    error => raise Native(error)
  }
  @async.protect_from_cancel(take_notification_result, resume_on_cancel=true) catch {
    error => raise WaitInterrupted(detail=@debug.render(Repr(error)))
  }
}
