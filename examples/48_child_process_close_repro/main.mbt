///|
struct HoldRequest {} derive(ToJson, FromJson)

///|
struct HoldResult {
  pid : Int
} derive(ToJson, FromJson)

///|
let child_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/child-process-close-repro",
  js_namespace="child",
)

///|
let hold_command : @proton_contract.Command[HoldRequest, HoldResult] = child_contract.command(
  "hold",
)

///|
fn child_process_extension() -> @proton_extension.Extension {
  @proton_extension.typed(child_contract, [hold_command.contract_route()], fn(
    _context,
    registrar,
  ) raise {
    registrar.bind(hold_command, hold_child_process)
  })
}

///|
async fn hold_child_process(
  context : @proton.CommandContext,
  _request : HoldRequest,
) -> HoldResult {
  let process = @process.spawn(
    context.task_group(),
    "sh",
    ["-c", "trap 'exit 0' TERM; while :; do sleep 1; done"],
    inherit_env=true,
    cancel_handler=@process.graceful_cancel(timeout=1000),
    no_wait=true,
  )
  println("child_process_close_repro child pid=\{process.pid}")
  defer {
    println("child_process_close_repro cancel child pid=\{process.pid}")
    process.cancel()
  }
  for ;; {
    @async.sleep(1000)
  }
  HoldResult::{ pid: process.pid }
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
