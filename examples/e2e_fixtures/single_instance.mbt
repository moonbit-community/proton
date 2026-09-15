///|
pub async fn run_single_instance() -> Unit {
  let identifier = @env.get_env_var("PROTON_INSTANCE_TEST_IDENTIFIER").unwrap()
  let role = @env.get_env_var("PROTON_INSTANCE_TEST_ROLE").unwrap()
  @proton.html("Single instance", "<h1>Single instance</h1>")
  .identifier(identifier)
  .single_instance()
  .on_launch_input(fn(context, input) noraise {
    if input is @proton.RuntimeLaunchInput::Reopen {
      println("INSTANCE: activation handled")
      context.quit()
    }
  })
  .window_lifecycle(
    on_ready=_context => {
      guard role == "primary" else {
        abort("secondary unexpectedly created a runtime window")
      }
      @mbfs.write_string_to_file(
        @env.get_env_var("PROTON_INSTANCE_TEST_READY").unwrap(),
        "ready",
      ) catch {
        _ => abort("failed to write single-instance readiness marker")
      }
    },
    on_close=fn(_) { () },
  )
  .run_or_abort()
  println("INSTANCE: " + role + " exited")
}
