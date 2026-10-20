///|
extern "C" fn registration_failure_test(stage : Int32) -> Int32 = "proton_test_power_registration_failure"

///|
async fn start_bus(
  group : @async.TaskGroup[Unit],
  address : String,
) -> @process.Process {
  let (reader, output) = @process.read_from_process()
  defer reader.close()
  let child = @process.spawn(
    group,
    "dbus-daemon",
    ["--session", "--nofork", "--address=" + address, "--print-address=1"],
    stdout=output,
  )
  // The daemon prints its address only after listening; no startup sleep.
  let announced = reader.read_until("\n")
  assert_true(
    announced is Some(_),
    msg="dbus-daemon exited before announcing its address",
  )
  child
}

///|
async fn expect_event(monitor : @monitor.PowerMonitor, sleeping : Bool) -> Unit {
  let status = @process.run("dbus-send", [
    "--system",
    "--type=signal",
    "/org/freedesktop/login1",
    "org.freedesktop.login1.Manager.PrepareForSleep",
    "boolean:" + sleeping.to_string(),
  ])
  assert_eq(status, 0, msg="sending PrepareForSleep failed")
  @async.with_timeout(5000, () => {
    while true {
      let events = monitor.drain_events()
      if !events.is_empty() {
        assert_eq(events.length(), 1, msg="expected exactly one power event")
        if sleeping {
          assert_true(events[0] is @monitor.Suspend, msg="expected Suspend")
        } else {
          assert_true(events[0] is @monitor.Resume, msg="expected Resume")
        }
        break
      }
      @async.sleep(1)
    }
  })
}

///|
fn start_unavailable(monitor : @monitor.PowerMonitor) -> Bool raise {
  try {
    monitor.start_watching()
    false
  } catch {
    @monitor.BackendUnavailable(detail~) => {
      assert_false(
        detail.is_empty(),
        msg="backend failure must retain its diagnostic",
      )
      true
    }
    error => raise error
  }
}

///|
async test "public power monitor receives signals, restarts, and recovers from a disconnected bus" {
  guard @async.platform is Linux else { return }
  let dir = @fs.tmpdir(prefix="proton-power-bus-")
  defer @fs.rmdir(dir, recursive=true)
  let address = "unix:path=" + dir + "/bus"
  let original = @env.get_env_var("DBUS_SYSTEM_BUS_ADDRESS")
  defer (match original {
    Some(value) => @env.set_env_var("DBUS_SYSTEM_BUS_ADDRESS", value)
    None => @env.unset_env_var("DBUS_SYSTEM_BUS_ADDRESS")
  })
  // libdbus caches this address. Restart the daemon at the same socket path.
  @env.set_env_var("DBUS_SYSTEM_BUS_ADDRESS", address)
  @async.with_timeout(15000, () => {
    @async.with_task_group(group => {
      let bus = start_bus(group, address)
      defer bus.cancel()
      let monitor = @monitor.PowerMonitor()
      defer monitor.destroy()
      assert_eq(
        registration_failure_test(0),
        0,
        msg="filter failure must roll back and permit retry",
      )
      assert_eq(
        registration_failure_test(1),
        0,
        msg="partial subscription failure must roll back and permit retry",
      )
      for _ in 0..<2 {
        monitor.start_watching()
        expect_event(monitor, true)
        expect_event(monitor, false)
        monitor.stop_watching()
        monitor.stop_watching()
      }
      monitor.start_watching()
      // SIGTERM and wait for actual exit before checking disconnection.
      assert_eq(@process.run("kill", ["-TERM", bus.pid.to_string()]), 0)
      assert_eq(bus.wait(), 0)
      @async.with_timeout(5000, () => {
        while !start_unavailable(monitor) {
          @async.sleep(1)
        }
      })
      assert_true(
        start_unavailable(monitor),
        msg="a failed start must not leave stale success state",
      )
      let restarted = start_bus(group, address)
      defer restarted.cancel()
      monitor.start_watching()
      expect_event(monitor, true)
      monitor.stop_watching()
    })
  })
}
