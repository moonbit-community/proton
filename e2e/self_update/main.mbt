///|
/// Exercises signed updates through the public application lifecycle.
async fn main {
  let bundle = running_bundle()
  if require_env("PROTON_E2E_MODE") == "delayed-start" {
    record("loaded-old")
    while !@mbfs.path_exists(require_env("PROTON_E2E_RESUME")) {
      @async.sleep(10)
    }
    let endpoint = require_env("PROTON_E2E_ENDPOINT")
    let key = require_env("PROTON_E2E_KEY")
    let rejected = try {
      @proton.html("Obsolete application", "")
      .identifier("com.example.proton-updater-e2e")
      .headless()
      .single_instance()
      .update_channel(endpoint, [key], check_on_launch=false)
      .app_lifecycle(
        on_start=context => {
          record("obsolete-started")
          context.quit()
        },
        on_shutdown=_ => (),
      )
      .run()
      false
    } catch {
      error => error.message().contains("the running executable was replaced")
    }
    assert_true(rejected)
    record("obsolete-rejected")
    return
  }
  if @updater.current_revision() != 1UL {
    @proton.html("Updated application", "<h1>Updated</h1>")
    .identifier("com.example.proton-updater-e2e")
    .headless()
    .single_instance()
    .app_lifecycle(
      on_start=context => {
        assert_true(context.has_single_instance_lock())
        record("started-new")
        context.quit()
      },
      on_shutdown=_ => (),
    )
    .run()
    @updater.cleanup_previous()
    record("new-cleaned")
    return
  }
  let mode = require_env("PROTON_E2E_MODE")
  let before_count = Ref(0)
  let will_count = Ref(0)
  let app = @proton.html("Updater lifecycle", "<h1>Updater</h1>")
    .identifier("com.example.proton-updater-e2e")
    .headless()
    .single_instance()
    .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
    .update_channel(
      require_env("PROTON_E2E_ENDPOINT"),
      [require_env("PROTON_E2E_KEY")],
      check_on_launch=false,
    )
    .app_lifecycle(
      on_start=context => {
        let unavailable = try {
          context.quit_and_install()
          false
        } catch {
          _ => true
        }
        assert_true(unavailable)
        guard context.check_for_update() is Available(update) else {
          fail("expected an authenticated update")
        }
        update.download()
        assert_eq(@updater.current_revision(), 1UL)
        assert_eq(
          @mbfs.read_file_to_string("\{bundle}/Contents/Resources/version"),
          "0.1.0",
        )
        record("downloaded")
        if mode == "ordinary-quit" {
          context.quit()
        } else {
          context.quit_and_install()
          context.quit_and_install() // Duplicate requests must be harmless.
        }
        if mode == "prevent-before" || mode == "prevent-will" {
          ignore(
            context
            .task_group()
            .spawn(() => {
              // Retry until a second quit transaction starts. Success is measured
              // by callbacks, not by assuming a fixed delay completes cancellation.
              let counter = if mode == "prevent-before" {
                before_count
              } else {
                will_count
              }
              while counter.val < 2 {
                @async.sleep(1)
                context.quit_and_install()
              }
            }),
          )
        }
        context
      },
      on_shutdown=context => {
        if mode == "install" {
          let refused = try {
            context.release_single_instance_lock()
            false
          } catch {
            _ => true
          }
          assert_true(refused)
          assert_true(context.has_single_instance_lock())
        }
        assert_eq(@updater.current_revision(), 1UL)
        assert_eq(
          @mbfs.read_file_to_string("\{bundle}/Contents/Resources/version"),
          "0.1.0",
        )
        record("shutdown-old")
        if mode == "cleanup-failure" {
          fail("intentional update cleanup failure")
        }
      },
    )
    .on_before_quit(fn(context) {
      before_count.val = before_count.val + 1
      record("before-quit")
      if mode == "force-exit" {
        context.exit()
        @proton.ApplicationQuitDecision::Prevent
      } else if mode == "prevent-before" && before_count.val == 1 {
        record("prevented-before")
        @proton.ApplicationQuitDecision::Prevent
      } else {
        @proton.ApplicationQuitDecision::Allow
      }
    })
    .on_will_quit(fn(_context) {
      will_count.val = will_count.val + 1
      record("will-quit")
      if mode == "prevent-will" && will_count.val == 1 {
        record("prevented-will")
        @proton.ApplicationQuitDecision::Prevent
      } else {
        @proton.ApplicationQuitDecision::Allow
      }
    })
    .on_quit(fn(_context, _code) { record("quit") })
  app.run() catch {
    error => {
      guard mode == "cleanup-failure" &&
        error.message().contains("intentional update cleanup failure") else {
        raise error
      }
      record("cleanup-failed")
    }
  }
  guard mode == "ordinary-quit" || mode == "cleanup-failure" else {
    fail("update installation or forced exit returned from App::run")
  }
  assert_eq(@updater.current_revision(), 1UL)
  record("run-returned")
}

///|
fn running_bundle() -> String {
  parent(parent(parent(@env.args()[0])))
}

///|
fn record(event : String) -> Unit {
  let log = require_env("PROTON_E2E_LOG") catch {
    _ => abort("missing update log path")
  }
  let previous = @mbfs.read_file_to_string(log) catch { _ => "" }
  @mbfs.write_string_to_file(log, previous + event + "\n") catch {
    _ => abort("could not write update log")
  }
}

///|
fn require_env(name : String) -> String raise {
  match @env.get_env_var(name) {
    Some(value) => value
    None => fail("missing " + name)
  }
}

///|
fn parent(path : String) -> String {
  let native_path : @mbpath.Path = path
  native_path.dirname().to_string()
}
