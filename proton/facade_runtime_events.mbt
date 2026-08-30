///|
fn RuntimeEventPump::RuntimeEventPump(
  runtime : @native.Runtime,
  dialog_completions : DialogCompletionStore,
  cookie_completions : CookieCompletionStore,
) -> RuntimeEventPump {
  RuntimeEventPump::{
    runtime,
    dialog_completions,
    cookie_completions,
    session_events: [],
  }
}

///|
/// Pulls every currently available native event into its single MoonBit owner.
/// Dialog completions wake their registered waiter; all other events remain
/// queued for the runtime session.
fn RuntimeEventPump::poll_native_events(
  self : RuntimeEventPump,
) -> Bool raise AppRunError {
  let mut did_work = false
  let mut polling = true
  while polling {
    let event = self.runtime.poll_event() catch {
      error => raise native_run_error("poll event", error)
    }
    match event {
      None => polling = false
      Some(event) => {
        did_work = true
        if !self.dialog_completions.route_completion(event.dialog_completion()) &&
          !self.cookie_completions.route_completion(
            event.cookie_get_completion(),
          ) {
          self.session_events.push(event)
        }
      }
    }
  }
  did_work
}

///|
/// Dispatches queued non-dialog events without allowing another component to
/// consume the native queue. The inbox is cleared only after the whole batch
/// dispatches successfully.
fn RuntimeEventPump::drain_session_events(
  self : RuntimeEventPump,
  dispatch : (@native.RuntimeEvent) -> Unit raise AppRunError,
) -> Bool raise AppRunError {
  let did_work = self.poll_native_events()
  guard !self.session_events.is_empty() else { return did_work }
  let queued = self.session_events.copy()
  for event in queued {
    dispatch(event)
  }
  self.session_events.clear()
  true
}
