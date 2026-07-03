// Async native file dialogs. `pick_file_dialog` shows the panel through the
// non-blocking engine API and suspends its coroutine until the runtime pump
// sees the matching `dialog_completed` event, so the window, bridge and CEF
// message loop all stay live while the panel is open — unlike the synchronous
// `@native.open_file_dialog` family, which nests a modal run loop and freezes
// the host until the panel settles.

///|
priv enum DialogOutcome {
  Picked(String)
  Cancelled
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
  let outcome = if event.dialog_accepted() && event.dialog_path() is Some(path) {
    DialogOutcome::Picked(path)
  } else {
    DialogOutcome::Cancelled
  }
  let delivered = queue.try_put(outcome) catch { _ => false }
  ignore(delivered)
}

///|
/// Shows a native file panel and waits for the user to settle it without
/// blocking the runtime pump. Returns `Ok(None)` when the user cancels.
pub async fn pick_file_dialog(
  window : @native.WindowRef,
  title? : String,
  initial_path? : String,
  mode? : @native.FileDialogMode = OpenFile,
) -> Result[String?, String] {
  let request_id = next_dialog_request_id()
  let queue : @aqueue.Queue[DialogOutcome] = @aqueue.Queue(
    kind=@aqueue.Unbounded,
  )
  pending_dialogs.set(request_id, queue)
  match
    @native.begin_file_dialog(window, title, initial_path, mode, request_id) {
    Err(error) => {
      pending_dialogs.remove(request_id)
      return Err(native_error_message("begin file dialog", error))
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
  match outcome {
    Picked(path) => Ok(Some(path))
    Cancelled => Ok(None)
  }
}
