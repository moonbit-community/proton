///|
/// Proton's event loop, handed to `moonbitlang/async` so the two can share the
/// main thread.
///
/// AppKit and its peers insist on owning the process's main thread, and
/// `moonbitlang/async` wants a thread for its own loop. Installing this loop
/// settles the argument: every line of MoonBit, this `poll` included, keeps
/// running on the main thread, and `async` moves only its waiting half onto a
/// thread of its own.
priv struct ProtonEventLoop {
  signal : @core.RuntimeWakeSignal
  mut installed : Bool
  mut install_error : AppRunError?
}

///|
/// The process's host loop. There is one main thread, so there is one of these.
///
/// It is built at startup rather than on demand because `poll` may not
/// allocate a notification target the first time `async` calls it: the
/// scheduler is already running by then, and a waiter that missed the object it
/// was supposed to wait on would never be woken.
let host_event_loop : ProtonEventLoop = ProtonEventLoop::{
  signal: @core.RuntimeWakeSignal::new(),
  installed: false,
  install_error: None,
}

///|
/// Installs the loop before anything else in the process runs.
///
/// `fn init` is the one place guaranteed to run before `moonbitlang/async`
/// starts its loop, which is the deadline `set_external_event_loop` imposes --
/// installing afterwards aborts. Doing it here rather than asking every
/// application to spell it out as the first line of `async fn main` means the
/// requirement cannot be forgotten, and nothing in the language would have
/// caught forgetting it.
///
/// A failure is kept, not raised. `fn init` cannot raise, aborting would take
/// down a process that may never open a window, and `App::run` is the place
/// where a caller can be told properly.
fn init {
  install_event_loop() catch {
    error => host_event_loop.install_error = Some(error)
  }
}

///|
/// Hands Proton's event loop to `moonbitlang/async`. Call once, from `fn init`:
/// `async` aborts on a second install.
fn install_event_loop() -> Unit raise AppRunError {
  // Begin first. A failure here leaves nothing installed, whereas installing
  // first would hand `async` a loop that never started and turn every later
  // `poll` into the same error.
  @native.host_loop_begin() catch {
    error => raise native_run_error("start the host event loop", error)
  }
  @async.set_external_event_loop(host_event_loop)
  host_event_loop.installed = true
}

///|
/// Fails unless Proton's event loop is running.
///
/// Everything the facade does with a native runtime depends on it: the loop is
/// what drives the platform and what turns native work into a notification the
/// scheduler can wait on. The error is the one `fn init` hit, because that is
/// the only way this can be reached.
fn require_event_loop() -> Unit raise AppRunError {
  guard !host_event_loop.installed else { return }
  match host_event_loop.install_error {
    Some(error) => raise error
    None => raise RunnerError("Proton's event loop was never installed")
  }
}

///|
/// The notification Proton's event loop raises when native work arrives.
///
/// A host that drives an `@native.Runtime` of its own waits on this rather
/// than building a wakeup for it: `poll` runs on the main thread and reports
/// readiness for the whole process, not only for the runtime the facade owns,
/// so there is nothing left for a second wakeup to observe.
pub fn host_wake_signal() -> @core.RuntimeWakeSignal {
  host_event_loop.signal
}

///|
impl @extloop.ExternalEventLoop for ProtonEventLoop with fn poll(self, timeout?) {
  let ready = @native.host_loop_poll(timeout_ms?=timeout)
  // Only a mask with something in it is worth a notification. `poll` runs on
  // every turn of `async`'s loop, so notifying unconditionally would rouse the
  // runtime pump on every timer tick in the application and make it re-poll
  // native queues that nothing has touched.
  if !ready.is_timeout() {
    self.signal.notify()
  }
}

///|
impl @extloop.ExternalEventLoop for ProtonEventLoop with fn get_wakeup_callback_for_foreign_thread(
  _self,
) {
  // Runs on `async`'s waiting thread, where the contract forbids anything but a
  // direct C call: no allocation, and nothing that touches a refcount.
  () => @native.signal_wakeup()
}

///|
impl @extloop.ExternalEventLoop for ProtonEventLoop with fn terminate(_self) {
  @native.host_loop_end()
}
