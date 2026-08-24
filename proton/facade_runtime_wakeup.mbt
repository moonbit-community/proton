///|
/// The facade's view of the host event loop's notifications.
///
/// `ProtonEventLoop::poll` runs on the main thread and signals whenever native
/// work arrives, so waiting here is a plain scheduler wait -- there is no
/// descriptor left to drain. Waiting stays race-free through the revision:
/// capture it before checking the condition that may make waiting unnecessary,
/// and a notification that lands in between is still seen.
priv struct RuntimeWakeup {
  signal : @core.RuntimeWakeSignal
}

///|
/// Attaches to the running host loop. `App::run` has already refused to start
/// without one, so there is nothing left to fail here.
fn RuntimeWakeup::RuntimeWakeup() -> RuntimeWakeup {
  RuntimeWakeup::{ signal: host_event_loop_signal(), }
}

///|
fn RuntimeWakeup::revision(self : RuntimeWakeup) -> Int64 {
  self.signal.revision()
}

///|
/// Waits for native work or a scheduler notification newer than `revision`.
async fn RuntimeWakeup::wait_after(
  self : RuntimeWakeup,
  revision : Int64,
) -> Unit raise AppRunError {
  self.signal.wait_for_change(revision) catch {
    error => raise normalize_async_run_error(error)
  }
}
