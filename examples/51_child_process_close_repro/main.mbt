///|
struct HoldRequest {} derive(ToJson, FromJson)

///|
pub extend HoldRequest with ToJson::{to_json}

///|
pub extend HoldRequest with FromJson::{from_json}

///|
struct HoldResult {
  pid : Int
} derive(ToJson, FromJson)

///|
pub extend HoldResult with ToJson::{to_json}

///|
pub extend HoldResult with FromJson::{from_json}

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
  HoldResult::{ pid: process.pid, }
}

///|
async fn main {
  let app = @proton.html(
    "Child Process Close Repro",
    resource,
    width=760,
    height=520,
    debug=true,
  ).capability(@proton_extension.capability(child_process_extension()))
  app.identifier("dev.proton.51-child-process-close-repro").run_or_abort()
}
