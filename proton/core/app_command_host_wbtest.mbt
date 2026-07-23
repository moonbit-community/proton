///|
test "app command host starts open and empty" {
  let host = AppCommandHost::new()
  @debug.assert_eq(host.registered_ops(), [])
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  @debug.assert_eq(host.registered_ops(), ["app:ping"])
  host.close()
}

///|
test "panic command host rejects registration after close" {
  let host = MbtProcessHost::new()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.close()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
test "command host close clears extension event sender" {
  let host = AppCommandHost::new()
  host.set_event_sender(fn(_event) { () })
  assert_true(host.event_sender is Some(_))

  host.close()
  assert_false(host.event_sender is Some(_))
  host.set_event_sender(fn(_event) { () })
  assert_false(host.event_sender is Some(_))
}

///|
test "panic command host rejects registration after sealing" {
  let host = AppCommandHost::new()
  host.op("app:ping", fn(_payload : Unit) { "pong" })
  host.seal_registrations()
  host.op("app:late", fn(_payload : Unit) { "late" })
}

///|
async test "runtime wake signal preserves notifications across wait races" {
  let signal = RuntimeWakeSignal::new()
  let revision = signal.revision()
  signal.notify()
  inspect(signal.revision(), content="1")
  let completed = @async.with_timeout_opt(10, () => {
    signal.wait_for_change(revision)
  })
  assert_true(completed is Some(_))
}

///|
async test "request context observes its shared runtime wake signal" {
  let signal = RuntimeWakeSignal::new()
  let context = AppCommandRequestContext::new(7L, wake_signal=signal)
  let revision = context.wake_revision()
  signal.notify()
  context.wait_for_wake(revision)
  inspect(context.window(), content="7")
  inspect(context.wake_revision(), content="1")
}
