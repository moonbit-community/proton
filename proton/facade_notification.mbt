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
let notification_extension_id = "moonbit-community/proton-notification"

///|
let notification_extension_namespace = "notification"

///|
fn notification_click_payload(payload : String?) -> Json {
  Json::object({
    "payload": match payload {
      Some(payload) => Json(payload)
      None => Json::null()
    },
  })
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
fn notification_result_event_supported(features : Array[String]) -> Bool {
  features.contains("notification_result")
}

///|
fn native_notification_result_supported() -> Bool raise @native.NativeError {
  let info = @native.runtime_info()
  notification_result_event_supported(info.features)
}

///|
/// Failures while starting or waiting for native notification delivery.
pub(all) suberror NotificationDeliveryError {
  NativeFailure(status~ : Int, detail~ : String)
  WaitInterrupted(detail~ : String)
  DeliveryFailed(message~ : String)
} derive(Debug, Eq)

///|
pub extend NotificationDeliveryError with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryError with Debug::{to_repr}

///|
pub fn NotificationDeliveryError::message(
  self : NotificationDeliveryError,
) -> String {
  match self {
    NativeFailure(status~, detail~) =>
      "native notification operation failed (" +
      status.to_string() +
      "): " +
      detail
    WaitInterrupted(detail~) =>
      "notification delivery wait was interrupted: " + detail
    DeliveryFailed(message~) => "notification was not delivered: " + message
  }
}

///|
/// Starts one native notification and waits for a completion event only on
/// platforms that advertise the `notification_result` runtime capability.
#doc(hidden)
pub async fn notification_show_and_wait(
  title : String,
  body : String,
  payload? : String,
) -> Unit raise NotificationDeliveryError {
  let waits_for_result = native_notification_result_supported() catch {
    error => raise NativeFailure(status=error.status(), detail=error.message())
  }
  if waits_for_result {
    acquire_notification_result_slot() catch {
      error => raise WaitInterrupted(detail=@debug.render(Repr(error)))
    }
    defer release_notification_result_slot()
  }
  @native.notification_show(title, body, payload?) catch {
    error => raise NativeFailure(status=error.status(), detail=error.message())
  }
  if waits_for_result {
    let result = @async.protect_from_cancel(take_notification_result) catch {
      error => raise WaitInterrupted(detail=@debug.render(Repr(error)))
    }
    match result {
      @native.NativeNotificationResult::Delivered => ()
      @native.NativeNotificationResult::Failed(message) =>
        raise DeliveryFailed(message~)
    }
  }
}

///|
#doc(hidden)
pub fn notification_supported() -> Bool raise NotificationDeliveryError {
  @native.notification_supported() catch {
    error => raise NativeFailure(status=error.status(), detail=error.message())
  }
}

///|
#doc(hidden)
pub fn notification_cleanup() -> Unit raise NotificationDeliveryError {
  @native.notification_cleanup() catch {
    error => raise NativeFailure(status=error.status(), detail=error.message())
  }
}
