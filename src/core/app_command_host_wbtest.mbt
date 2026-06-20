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
