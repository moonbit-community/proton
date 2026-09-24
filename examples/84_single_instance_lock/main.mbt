///|
struct ControlRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend ControlRequest with ToJson::{to_json}

///|
pub extend ControlRequest with FromJson::{from_json}

///|
struct ControlReply {
  ok : Bool
  message : String
  has_lock : Bool
  activations : Int
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/single-instance-lock",
  js_namespace="singleInstanceLock",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
/// Reopen activations this instance received while it owned the identity.
let activations : Ref[Int] = { val: 0, }

///|
/// Emits one review line for the terminal that started the example.
fn log_lock_step(step : String) -> Unit {
  println("[single-instance] " + step)
}

///|
/// The browser profile this instance uses. Launching a second copy while the
/// first one is still running needs a different value because CEF owns the
/// profile exclusively.
fn demo_partition() -> String {
  match @env.get_env_var("PROTON_INSTANCE_DEMO_PARTITION") {
    Some(partition) if partition.trim() != "" => partition.trim().to_owned()
    _ => "demo"
  }
}

///|
fn state_reply(message : String, ok? : Bool = true) -> ControlReply {
  let has_lock = match application_slot.val {
    Some(context) => context.has_single_instance_lock()
    None => false
  }
  { ok, message, has_lock, activations: activations.val, }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  let context = match application_slot.val {
    Some(context) => context
    None => return state_reply("Application context is not ready", ok=false)
  }
  match request.action {
    "state" => state_reply("Single-instance state refreshed")
    "release" => {
      guard context.has_single_instance_lock() else {
        return state_reply(
          "This instance holds no single-instance lock",
          ok=false,
        )
      }
      context.release_single_instance_lock() catch {
        error => {
          log_lock_step("release failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_lock_step(
        "lock released; has_lock=" +
        context.has_single_instance_lock().to_string(),
      )
      state_reply("Lock released; the next launch becomes primary")
    }
    _ => state_reply("Unknown action", ok=false)
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(control_command, (_context, request) => control(request))
}

///|
fn page() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Single-Instance Lock</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101418; color: #eef3f6; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #101418; }
    #|      button { font: inherit; cursor: pointer; }
    #|      main { width: min(880px, calc(100vw - 40px)); margin: 0 auto; padding: 34px 0 46px; }
    #|      .eyebrow { margin: 0 0 10px; color: #58c7d8; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(26px, 4vw, 40px); letter-spacing: -.04em; }
    #|      .summary { margin: 12px 0 0; color: #9fb0bd; line-height: 1.55; }
    #|      code { padding: 1px 6px; border-radius: 4px; background: #1d242b; color: #cfe7ef; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .panel { margin-top: 22px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; min-height: 46px; padding: 0 16px; border-bottom: 1px solid #2b353d; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      .panel-body { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; padding: 16px; }
    #|      .action { min-height: 44px; padding: 0 14px; border: 1px solid #3a4a55; border-radius: 8px; background: #1b232a; color: #eef3f6; font-weight: 600; }
    #|      .action.danger { border-color: #7c3a33; background: #5f2d28; }
    #|      .state { display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 6px 16px; padding: 0 16px 16px; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .state dt { color: #8b9aa6; }
    #|      .state dd { margin: 0; color: #eef3f6; }
    #|      .status { margin-top: 16px; padding: 14px 16px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; color: #cfe7ef; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Electron app / review 84</p>
    #|        <h1>Single-instance lock</h1>
    #|        <p class="summary">
    #|          Run this example from a terminal. This instance owns the
    #|          application identity until you release it. A second copy that
    #|          runs side by side needs its own
    #|          <code>PROTON_INSTANCE_DEMO_PARTITION</code> because CEF owns the
    #|          browser profile exclusively; the terminal prints the partition
    #|          this instance uses.
    #|        </p>
    #|      </header>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Runtime lock</span><span id="lock-state">-</span></div>
    #|        <div class="panel-body">
    #|          <button class="action" id="state">Refresh state</button>
    #|          <button class="action danger" id="release">Release lock</button>
    #|        </div>
    #|        <dl class="state">
    #|          <dt>hasSingleInstanceLock</dt><dd id="has-lock">-</dd>
    #|          <dt>activations received</dt><dd id="activations">-</dd>
    #|        </dl>
    #|      </section>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      async function invoke(action) {
    #|        return window.__MoonBit__.core.invokeOp("ext:singleInstanceLock/control", { action });
    #|      }
    #|      function render(reply) {
    #|        document.querySelector("#has-lock").textContent = String(reply.has_lock);
    #|        document.querySelector("#activations").textContent = String(reply.activations);
    #|        document.querySelector("#lock-state").textContent = reply.has_lock ? "held" : "released";
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        try {
    #|          render(await invoke(action));
    #|        } catch (error) {
    #|          status.textContent = `${action} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      document.querySelector("#state").addEventListener("click", () => void run("state"));
    #|      document.querySelector("#release").addEventListener("click", () => void run("release"));
    #|      void run("state");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  let partition = demo_partition()
  @proton.html("Single-Instance Lock", page(), width=880, height=620)
  .identifier("com.example.proton.single-instance-lock")
  .single_instance()
  .session_partition(partition)
  .on_launch_input(fn(context, input) noraise {
    if input is @proton.RuntimeLaunchInput::Reopen {
      activations.val = activations.val + 1
      log_lock_step(
        "activation forwarded to this instance (" +
        activations.val.to_string() +
        ")",
      )
      match context.windows().find("main") {
        Some(window) => window.focus() catch { _ => () }
        None => ()
      }
    }
  })
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      log_lock_step(
        "started with has_single_instance_lock=" +
        context.has_single_instance_lock().to_string() +
        " partition=" +
        partition,
      )
      context
    },
    on_shutdown=fn(_context) {
      application_slot.val = None
      log_lock_step("lifecycle shutdown")
    },
  )
  .run_or_abort()
}
