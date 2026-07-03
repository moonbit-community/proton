// Async native dialogs. Each function starts a dialog through the non-blocking
// engine API and suspends its coroutine until the runtime pump sees the matching
// `dialog_completed` event, so the window, bridge and CEF message loop all stay
// live while the dialog is open.

///|
priv struct DialogOutcome {
  accepted : Bool
  path : String?
}

///|
let pending_dialogs : Map[UInt64, @aqueue.Queue[DialogOutcome]] = {}

///|
let dialog_request_counter : Ref[UInt64] = Ref(0)

///|
fn next_dialog_request_id() -> UInt64 {
  dialog_request_counter.val = dialog_request_counter.val + 1
  dialog_request_counter.val
}

///|
/// Settles the waiter of a `dialog_completed` runtime event. Events whose
/// waiter is gone (the request was cancelled meanwhile) are dropped.
fn settle_dialog_event(event : @native.RuntimeEvent) -> Unit {
  guard event.dialog_request() is Some(request_id) else { return }
  guard pending_dialogs.get(request_id) is Some(queue) else { return }
  pending_dialogs.remove(request_id)
  let outcome = DialogOutcome::{
    accepted: event.dialog_accepted(),
    path: event.dialog_path(),
  }
  let delivered = queue.try_put(outcome) catch { _ => false }
  ignore(delivered)
}

///|
async fn begin_dialog_and_wait(
  window : @native.WindowRef,
  title : String?,
  message : String?,
  path : String?,
  mode : @native.DialogMode,
  level : @native.DialogLevel,
) -> Result[DialogOutcome, String] {
  let request_id = next_dialog_request_id()
  let queue : @aqueue.Queue[DialogOutcome] = @aqueue.Queue(
    kind=@aqueue.Unbounded,
  )
  pending_dialogs.set(request_id, queue)
  match
    @native.begin_dialog(window, title, message, path, mode, level, request_id) {
    Err(error) => {
      pending_dialogs.remove(request_id)
      return Err(native_error_message("begin dialog", error))
    }
    Ok(_) => ()
  }
  let outcome = queue.get() catch {
    error => {
      // Cancelled while the panel is still up; its later completion event
      // finds no waiter and is dropped.
      pending_dialogs.remove(request_id)
      raise error
    }
  }
  Ok(outcome)
}

///|
/// Shows a native message dialog without blocking the runtime pump.
pub async fn show_message_dialog(
  window : @native.WindowRef,
  title : String?,
  message : String,
  level? : @native.DialogLevel = Info,
) -> Result[Unit, String] {
  match
    begin_dialog_and_wait(window, title, Some(message), None, Message, level) {
    Err(error) => Err(error)
    Ok(_) => Ok(())
  }
}

///|
/// Shows a native confirmation dialog without blocking the runtime pump.
pub async fn show_confirm_dialog(
  window : @native.WindowRef,
  title : String?,
  message : String,
  level? : @native.DialogLevel = Info,
) -> Result[Bool, String] {
  match
    begin_dialog_and_wait(window, title, Some(message), None, Confirm, level) {
    Err(error) => Err(error)
    Ok(outcome) => Ok(outcome.accepted)
  }
}

///|
/// Shows a native file panel and waits for the user to settle it without
/// blocking the runtime pump. Returns `Ok(None)` when the user cancels.
pub async fn pick_file_dialog(
  window : @native.WindowRef,
  title? : String,
  initial_path? : String,
  mode? : @native.DialogMode = OpenFile,
) -> Result[String?, String] {
  match begin_dialog_and_wait(window, title, None, initial_path, mode, Info) {
    Err(error) => Err(error)
    Ok(outcome) => if outcome.accepted { Ok(outcome.path) } else { Ok(None) }
  }
}
