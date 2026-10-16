///|
// These tests each need a fresh process because CEF cannot restart after shutdown.
// The lifecycle E2E runner selects them explicitly with --index.
#skip
async test "cancelled window open retains a failed destroy for cleanup retry" {
  window_cleanup_failure(startup_failure=false)
}

///|
#skip
async test "startup and window cleanup failures retain both diagnostics" {
  window_cleanup_failure(startup_failure=true)
}

///|
async fn window_cleanup_failure(startup_failure~ : Bool) -> Unit {
  let session : Ref[RuntimeSession?] = Ref(None)
  let main_ready = Ref(false)
  let secondary_ready = Ref(false)
  let cancellation_seen = Ref(false)
  let destroy_calls = Ref(0)
  let app = html("Window cleanup", "<h1>Main</h1>")
    ..identifier("dev.proton.e2e-window-cleanup")
    ..headless()
    ..last_window_closed_policy(KeepRunning)
    ..add_window(
      "secondary",
      WindowConfig("Secondary", AppEntry::Html("<h1>Secondary</h1>")),
      open_on_start=false,
    )
    ..setup(context => {
      let gate = @env.get_env_var("PROTON_E2E_LIFECYCLE_GATE").unwrap()
      @mbfs.write_string_to_file(gate + ".ready", "ready")
      while !@mbfs.path_exists(gate) {
        @async.sleep(10)
      }
      if startup_failure {
        ignore(context.windows().open("secondary"))
      } else {
        let opening = context
          .task_group()
          .spawn(no_wait=true, () => ignore(context.windows().open("secondary")))
        while context.windows().find("secondary") is None {
          @async.sleep(1)
        }
        session.val = Some(context.windows().find("secondary").unwrap().session)
        opening.cancel()
        opening.wait() catch {
          error => {
            assert_true(error is @async.WaitedTaskAlreadyCancelled)
            cancellation_seen.val = true
          }
        }
      }
      assert_false(secondary_ready.val)
    })
    ..setup_window(context => {
      if context.handle().id() == "secondary" {
        secondary_ready.val = true
        session.val = Some(context.handle().session)
        fail("INJECTED_STARTUP_FAILURE")
      } else {
        main_ready.val = true
        fail("main activated after cleanup failure")
      }
    })
  try
    app.run_with_destroy(window => {
      if destroy_calls.val == 1 {
        let windows = session.val.unwrap().windows
        if windows.length() != 1 ||
          !windows[0].is_closed() ||
          !physical_equal(windows[0].window, window) {
          abort("failed window was not retained for cleanup retry")
        }
      }
      window.destroy(before_destroy=fn() raise @native.NativeError {
        destroy_calls.val += 1
        if destroy_calls.val == 1 {
          raise @native.NativeError::Status(
            status=-1,
            message="INJECTED_WINDOW_DESTROY_FAILURE",
          )
        }
        if destroy_calls.val != 2 {
          abort("unexpected native destroy attempt")
        }
      })
      // A completed destroy must be idempotent; Destroying alone is insufficient.
      window.destroy(before_destroy=() => {
        abort("successfully destroyed window entered native destruction again")
      })
    })
  catch {
    CleanupFailed(primary~, failures~) => {
      assert_eq(primary is Some(_), startup_failure)
      if primary is Some(message) {
        assert_true(message.contains("INJECTED_STARTUP_FAILURE"))
      }
      assert_eq(failures.length(), 1)
      assert_true(
        failures[0].message().contains("INJECTED_WINDOW_DESTROY_FAILURE"),
      )
    }
    error => fail("unexpected application error: " + error.message())
  } noraise {
    _ => fail("destroy failure did not escape the session")
  }
  assert_eq(destroy_calls.val, 2)
  assert_false(main_ready.val)
  assert_eq(secondary_ready.val, startup_failure)
  assert_eq(cancellation_seen.val, !startup_failure)
  let name = if startup_failure {
    "window-cleanup-startup"
  } else {
    "window-cleanup-cancel"
  }
  println("LIFECYCLE_PASSED " + name)
}
