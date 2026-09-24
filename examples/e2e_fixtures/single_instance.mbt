///|
pub async fn run_single_instance() -> Unit {
  let identifier = @env.get_env_var("PROTON_INSTANCE_TEST_IDENTIFIER").unwrap()
  let role = @env.get_env_var("PROTON_INSTANCE_TEST_ROLE").unwrap()
  let application : Ref[@proton.ApplicationContext?] = Ref(None)
  let app = @proton.html("Single instance", "<h1>Single instance</h1>")
    .identifier(identifier)
    .single_instance()
    .on_launch_input(fn(context, input) noraise {
      if input is @proton.RuntimeLaunchInput::Reopen {
        println("INSTANCE: activation handled")
        context.quit()
      }
    })
    .app_lifecycle(
      on_start=context => {
        application.val = Some(context)
        context
      },
      on_shutdown=fn(_) { () },
    )
    .window_lifecycle(
      on_ready=context => {
        guard role == "primary" || role == "release" || role == "expect-primary" else {
          abort("secondary unexpectedly created a runtime window")
        }
        @mbfs.write_string_to_file(
          @env.get_env_var("PROTON_INSTANCE_TEST_READY").unwrap(),
          "ready",
        ) catch {
          _ => abort("failed to write single-instance readiness marker")
        }
        let app = application.val.unwrap()
        if role == "release" {
          assert_true(app.has_single_instance_lock())
          app.release_single_instance_lock() catch {
            error =>
              abort(
                "failed to release the single-instance lock: " + error.message(),
              )
          }
          assert_false(app.has_single_instance_lock())
          println("INSTANCE: lock released")
          @mbfs.write_string_to_file(
            @env.get_env_var("PROTON_INSTANCE_TEST_RELEASED").unwrap(),
            "released",
          ) catch {
            _ => abort("failed to write released marker")
          }
          // The released owner no longer receives activations, so the harness
          // stops it by creating this file instead of launching the app again.
          let stop = @env.get_env_var("PROTON_INSTANCE_TEST_STOP").unwrap()
          ignore(
            context
            .task_group()
            .spawn(
              () => {
                while !@mbfs.path_exists(stop) {
                  @async.sleep(20)
                }
                app.quit()
              },
              no_wait=true,
            ),
          )
        } else if role == "expect-primary" {
          assert_true(app.has_single_instance_lock())
          println("INSTANCE: primary lock held")
          app.quit()
        }
      },
      on_close=fn(_) { () },
    )
  // A released lock lets another process become primary, but CEF still owns
  // the session profile exclusively, so the successor runs with its own
  // partition instead of the shared profile.
  let app = match @env.get_env_var("PROTON_INSTANCE_TEST_PARTITION") {
    Some(partition) if partition != "" => app.session_partition(partition)
    _ => app
  }
  app.run_or_abort()
  println("INSTANCE: " + role + " exited")
}
