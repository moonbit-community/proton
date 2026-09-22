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
  windows : Int
  contents : Int
  gone : Int
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/process-events",
  js_namespace="processEvents",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
let created_windows : Array[String] = []

///|
let created_contents : Array[String] = []

///|
let gone_contents : Array[String] = []

///|
/// Emits one review line for the terminal that started the example.
fn log_process_step(step : String) -> Unit {
  println("[process-events] " + step)
}

///|
fn render_process_reason_name(
  reason : @proton.RenderProcessGoneReason,
) -> String {
  match reason {
    @proton.RenderProcessGoneReason::AbnormalExit => "abnormal-exit"
    @proton.RenderProcessGoneReason::Killed => "killed"
    @proton.RenderProcessGoneReason::Crashed => "crashed"
    @proton.RenderProcessGoneReason::OutOfMemory => "oom"
    @proton.RenderProcessGoneReason::LaunchFailed => "launch-failed"
    @proton.RenderProcessGoneReason::IntegrityFailure => "integrity-failure"
    @proton.RenderProcessGoneReason::Unknown => "unknown"
  }
}

///|
/// Describes one web contents the way the terminal review prints it.
fn web_contents_label(contents : @proton.WebContentsHandle) -> String {
  match contents {
    Browser(browser) => "browser:" + browser.window_id()
    View(view) => "view:" + view.window_id() + "/" + view.id()
  }
}

///|
fn state_reply(message : String, ok? : Bool = true) -> ControlReply {
  {
    ok,
    message,
    windows: created_windows.length(),
    contents: created_contents.length(),
    gone: gone_contents.length(),
  }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  let context = match application_slot.val {
    Some(context) => context
    None => return state_reply("Application context is not ready", ok=false)
  }
  let window = match context.windows().find("main") {
    Some(window) => window
    None => return state_reply("Main window is not open", ok=false)
  }
  match request.action {
    "state" => state_reply("Process event counts refreshed")
    "add-view" => {
      match window.view("probe") {
        Some(_) => return state_reply("Probe view already exists", ok=false)
        None => ()
      }
      let view = window.add_view(
        "probe",
        @proton.view(
          "data:text/html,<h1>Probe view</h1>",
          width=320,
          height=160,
        ),
      ) catch {
        error => return state_reply(error.message(), ok=false)
      }
      log_process_step("probe view created: " + view.id())
      state_reply("Probe view added")
    }
    "close-view" =>
      match window.view("probe") {
        Some(view) => {
          view.close() catch {
            error => return state_reply(error.message(), ok=false)
          }
          state_reply("Probe view closed")
        }
        None => state_reply("Probe view is not open", ok=false)
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
    #|    <title>Process Events</title>
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
    #|      .panel-body { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; padding: 16px; }
    #|      .action { min-height: 44px; padding: 0 14px; border: 1px solid #3a4a55; border-radius: 8px; background: #1b232a; color: #eef3f6; font-weight: 600; }
    #|      .action.primary { border-color: #2f6f63; background: #20564d; }
    #|      .state { display: grid; grid-template-columns: 200px minmax(0, 1fr); gap: 6px 16px; padding: 0 16px 16px; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .state dt { color: #8b9aa6; }
    #|      .state dd { margin: 0; color: #eef3f6; }
    #|      .status { margin-top: 16px; padding: 14px 16px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; color: #cfe7ef; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Electron app / review 83</p>
    #|        <h1>Process-level events</h1>
    #|        <p class="summary">
    #|          Run this example from a terminal. Session, window, and web contents
    #|          creation print one <code>[process-events]</code> line each.
    #|          <code>render-process-gone</code> needs a renderer that actually
    #|          dies: kill the <code>cef_process</code> helper that carries
    #|          <code>--type=renderer</code> and watch the terminal while this
    #|          application keeps running.
    #|        </p>
    #|      </header>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Web contents</span><span>creation events</span></div>
    #|        <div class="panel-body">
    #|          <button class="action primary" id="add-view">Add probe view</button>
    #|          <button class="action" id="close-view">Close probe view</button>
    #|          <button class="action" id="state">Refresh counts</button>
    #|        </div>
    #|        <dl class="state">
    #|          <dt>windows created</dt><dd id="windows">-</dd>
    #|          <dt>web contents created</dt><dd id="contents">-</dd>
    #|          <dt>renderers gone</dt><dd id="gone">-</dd>
    #|        </dl>
    #|      </section>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      async function invoke(action) {
    #|        return window.__MoonBit__.core.invokeOp("ext:processEvents/control", { action });
    #|      }
    #|      function render(reply) {
    #|        document.querySelector("#windows").textContent = String(reply.windows);
    #|        document.querySelector("#contents").textContent = String(reply.contents);
    #|        document.querySelector("#gone").textContent = String(reply.gone);
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        try {
    #|          render(await invoke(action));
    #|        } catch (error) {
    #|          status.textContent = `${action} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      for (const action of ["add-view", "close-view", "state"]) {
    #|        document.querySelector(`#${action}`).addEventListener("click", () => void run(action));
    #|      }
    #|      void run("state");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Process Events", page(), width=880, height=640)
  .identifier("com.example.proton.process-events")
  .single_instance()
  .session_partition("process-events")
  .on_session_created(fn(session) {
    log_process_step(
      "session-created partition=" +
      session.partition.unwrap_or("default") +
      " data=" +
      session.data_path.unwrap_or("temporary"),
    )
  })
  .on_window_created(fn(window) {
    created_windows.push(window.id())
    log_process_step("browser-window-created " + window.id())
  })
  .on_web_contents_created(fn(contents) {
    let label = web_contents_label(contents)
    created_contents.push(label)
    log_process_step("web-contents-created " + label)
  })
  .on_render_process_gone(fn(contents, details) {
    let line = web_contents_label(contents) +
      " reason=" +
      render_process_reason_name(details.reason) +
      " exit_code=" +
      details.exit_code.to_string()
    gone_contents.push(line)
    log_process_step("render-process-gone " + line)
  })
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      context
    },
    on_shutdown=fn(_context) {
      application_slot.val = None
      log_process_step("lifecycle shutdown")
    },
  )
  .run_or_abort()
}
