///|
struct HoldResult {
  pid : Int
} derive(ToJson)

///|
fn child_process_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/child-process-close-repro",
      "child",
      [@proton_command.AppCommandApiDescriptor::new("hold")],
      fn(context) raise {
        context.op_async("hold", async fn(_payload : Json) {
          @async.with_task_group(group => {
            let process = @process.spawn(
              group,
              "sh",
              ["-c", "trap 'exit 0' TERM; while :; do sleep 1; done"],
              inherit_env=true,
              cancel_handler=@process.graceful_cancel(timeout=1000),
              no_wait=true,
            )
            println("child_process_close_repro child pid=\{process.pid}")
            defer {
              println(
                "child_process_close_repro cancel child pid=\{process.pid}",
              )
              process.cancel()
            }
            for ;; {
              @async.sleep(1000)
            }
            HoldResult::{ pid: process.pid }
          })
        })
      },
    ),
  )
}

///|
fn main {
  @proton.run(() => {
    let app = @proton.html(
      "Child Process Close Repro",
      resource,
      width=760,
      height=520,
      debug=true,
    ).extension(child_process_extension())
    app.run_or_abort()
  })
}
