///|
extern "C" fn registration_failure_test(stage : Int32) -> Int32 = "proton_test_power_registration_failure"

///|
extern "C" fn pending_subscription_test(pid : Int32, cancel : Int32) -> Int32 = "proton_test_power_pending_subscription"

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
extern "C" fn full_listener() -> Int32 = "proton_test_power_full_listener"

///|
extern "C" fn close_listener() -> Unit = "proton_test_power_close_listener"

///|
async fn expect_unavailable(
  monitor : @monitor.PowerMonitor,
  timeout~ : Bool = false,
) -> Unit {
  monitor.with_watching(() => {
    fail("watch unexpectedly started")
    ()
  }) catch {
    @monitor.BackendUnavailable(detail~) => {
      assert_false(detail.is_empty())
      if timeout {
        assert_true(detail.contains("timed out"), msg=detail)
      }
    }
    error => raise error
  }
}

///|
async fn cancel_pending_watch(monitor : @monitor.PowerMonitor) -> Unit {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let ready = Ref(false)
      let owner = group.spawn(() => {
        monitor.with_watching(() => {
          ready.val = true
          @async.pause()
        })
      })
      // An unrelated task must advance while connection/startup is pending.
      @async.sleep(50)
      assert_false(ready.val)
      // No queued startup can outlive cancellation of this owner.
      for _ in 0..<2 {
        monitor.with_watching(() => {
          fail("concurrent watch entered")
          ()
        }) catch {
          @monitor.OperationFailed(operation~, detail~) => {
            assert_eq(operation, "with_watching")
            assert_true(detail.contains("already active"))
          }
          error => raise error
        }
      }
      ignore(monitor.power_source())
      owner.cancel()
    })
  })
}

///|
suberror BodyFailed

///|
async test "power watching scopes cancel, time out, release subscriptions and recover" {
  guard @async.platform is Linux else { return }
  let dir = @fs.tmpdir(prefix="proton-power-bus-")
  defer @fs.rmdir(dir, recursive=true)
  let address = "unix:path=" + dir + "/bus"
  let original = @env.get_env_var("DBUS_SYSTEM_BUS_ADDRESS")
  defer (match original {
    Some(value) => @env.set_env_var("DBUS_SYSTEM_BUS_ADDRESS", value)
    None => @env.unset_env_var("DBUS_SYSTEM_BUS_ADDRESS")
  })
  @env.set_env_var("DBUS_SYSTEM_BUS_ADDRESS", address)
  @async.with_timeout(20000, () => {
    @async.with_task_group(group => {
      let bus = start_bus(group, address)
      defer bus.cancel()
      let monitor = @monitor.PowerMonitor()
      defer monitor.destroy()
      assert_eq(
        registration_failure_test(0),
        0,
        msg="subscription failure must permit retry",
      )
      assert_eq(
        registration_failure_test(1),
        0,
        msg="partial registration must roll back",
      )
      assert_eq(
        pending_subscription_test(bus.pid, 0),
        0,
        msg="paused AddMatch must reach its startup deadline",
      )
      assert_eq(
        pending_subscription_test(bus.pid, 1),
        0,
        msg="paused AddMatch must cancel without waiting for the bus",
      )
      assert_eq(@process.run("kill", ["-STOP", bus.pid.to_string()]), 0)
      @async.protect_from_cancel(() => {
        defer @process.run("kill", ["-CONT", bus.pid.to_string()]) |> ignore
        cancel_pending_watch(monitor)
        // This must fail through the startup deadline, without external cancellation.
        @async.with_timeout(7000, () => {
          expect_unavailable(monitor, timeout=true)
        })
      })
      // Returning from the body and retrying exercise complete native teardown.
      for _ in 0..<2 {
        assert_eq(
          monitor.with_watching(() => {
            try monitor.destroy() catch {
              @monitor.OperationFailed(operation~, ..) =>
                assert_eq(operation, "destroy")
              error => raise error
            } noraise {
              _ => fail("destroy accepted an active watching scope")
            }
            expect_event(monitor, true)
            expect_event(monitor, false)
            42
          }),
          42,
        )
      }
      let active_body_cleaned = Ref(false)
      @async.with_task_group(group => {
        let ready : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
        let owner = group.spawn(() => {
          monitor.with_watching(() => {
            defer {
              active_body_cleaned.val = true
            }
            ready.put(())
            @async.pause()
          })
        })
        ready.get()
        owner.cancel()
      })
      assert_true(active_body_cleaned.val)
      // The same instance can start again after its active owner is cancelled.
      monitor.with_watching(() => {
        raise BodyFailed
        ()
      }) catch {
        BodyFailed => ()
        error => raise error
      }
      let body_cleaned = Ref(false)
      monitor.with_watching(() => {
        defer {
          body_cleaned.val = true
        }
        assert_eq(@process.run("kill", ["-TERM", bus.pid.to_string()]), 0)
        @async.pause()
      }) catch {
        @monitor.BackendUnavailable(_) => ()
        error => raise error
      }
      assert_true(
        body_cleaned.val,
        msg="disconnect must cancel and clean up body",
      )
      assert_eq(bus.wait(), 0)
      expect_unavailable(monitor)
      let restarted = start_bus(group, address)
      defer restarted.cancel()
      monitor.with_watching(() => expect_event(monitor, true))
      // A full local TCP accept queue exercises cancellation before authentication.
      let port = full_listener()
      assert_true(port > 0)
      defer close_listener()
      @env.set_env_var(
        "DBUS_SYSTEM_BUS_ADDRESS",
        "tcp:host=127.0.0.1,port=" + port.to_string(),
      )
      cancel_pending_watch(monitor)
      @env.set_env_var("DBUS_SYSTEM_BUS_ADDRESS", address)
      monitor.with_watching(() => expect_event(monitor, false))
    })
  })
}
