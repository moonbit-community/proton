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
}

///|
/// Hands Proton's event loop to `moonbitlang/async`.
///
/// Call this as the very first statement of `async fn main`, before any other
/// async work: `async` has to know about the loop before it starts waiting, and
/// installing it afterwards aborts the process.
///
/// ```moonbit skip
/// async fn main {
///   @proton.install_event_loop()
///   // ... the rest of the application
/// }
/// ```
pub fn install_event_loop() -> Unit raise AppRunError {
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
/// Whether the application has installed Proton's event loop.
///
/// Everything the facade does with a native runtime depends on it: the loop is
/// what drives the platform and what turns native work into a notification the
/// scheduler can wait on.
fn event_loop_is_installed() -> Bool {
  host_event_loop.installed
}

///|
/// The notification signal `poll` raises when native work arrives.
fn host_event_loop_signal() -> @core.RuntimeWakeSignal {
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
