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
  ready : Bool
  appkit_supported : Bool
  active : Bool
  hidden : Bool
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/app-control",
  js_namespace="appControl",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
/// Emits one review line for the terminal that started the example.
fn log_app_step(step : String) -> Unit {
  println("[app-control] " + step)
}

///|
fn state_reply(message : String, ok? : Bool = true) -> ControlReply {
  match application_slot.val {
    None =>
      {
        ok,
        message,
        ready: @proton.is_ready(),
        appkit_supported: false,
        active: false,
        hidden: false,
      }
    Some(context) => {
      // The macOS AppKit group answers as a unit: a platform implements all of
      // it or reports every call as unsupported.
      let mut appkit_supported = true
      let active = context.is_active() catch {
        @proton.AppControlError::UnsupportedPlatform(_) => {
          appkit_supported = false
          false
        }
        error => {
          log_app_step(error.message())
          false
        }
      }
      let hidden = context.is_hidden() catch {
        @proton.AppControlError::UnsupportedPlatform(_) => {
          appkit_supported = false
          false
        }
        error => {
          log_app_step(error.message())
          false
        }
      }
      {
        ok,
        message,
        ready: @proton.is_ready(),
        appkit_supported,
        active,
        hidden,
      }
    }
  }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  let context = match application_slot.val {
    Some(context) => context
    None => return state_reply("Application context is not ready", ok=false)
  }
  match request.action {
    "state" => state_reply("Application state refreshed")
    "focus" => {
      context.focus() catch {
        error => {
          log_app_step("focus failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_app_step("focus requested")
      state_reply("Application focus requested")
    }
    "focus-steal" => {
      context.focus(steal=true) catch {
        error => {
          log_app_step("focus(steal) failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_app_step("focus(steal=true) requested")
      state_reply("Application focus requested with steal")
    }
    "hide" => {
      context.hide() catch {
        error => {
          log_app_step("hide failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_app_step("hide requested")
      state_reply("Application windows hidden")
    }
    "show" => {
      context.show() catch {
        error => {
          log_app_step("show failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_app_step("show requested")
      state_reply("Application windows shown without focusing")
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
    #|    <title>Application Control</title>
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
    #|        <p class="eyebrow">Electron app / review 82</p>
    #|        <h1>Application control</h1>
    #|        <p class="summary">
    #|          Run this example from a terminal. Every action prints one
    #|          <code>[app-control]</code> line. <code>hide</code>,
    #|          <code>show</code>, <code>isActive</code>, and
    #|          <code>isHidden</code> are the macOS AppKit group; other platforms
    #|          report them as unsupported, while <code>focus</code> is
    #|          available everywhere.
    #|        </p>
    #|      </header>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Activate</span><span id="appkit">checking…</span></div>
    #|        <div class="panel-body">
    #|          <button class="action primary" id="focus">Focus</button>
    #|          <button class="action" id="focus-steal">Focus with steal</button>
    #|          <button class="action" id="hide">Hide app</button>
    #|          <button class="action" id="show">Show app</button>
    #|        </div>
    #|        <dl class="state">
    #|          <dt>isReady</dt><dd id="ready">-</dd>
    #|          <dt>isActive</dt><dd id="active">-</dd>
    #|          <dt>isHidden</dt><dd id="hidden">-</dd>
    #|        </dl>
    #|      </section>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      async function invoke(action) {
    #|        return window.__MoonBit__.core.invokeOp("ext:appControl/control", { action });
    #|      }
    #|      function render(reply) {
    #|        document.querySelector("#ready").textContent = String(reply.ready);
    #|        document.querySelector("#active").textContent = reply.appkit_supported ? String(reply.active) : "unsupported";
    #|        document.querySelector("#hidden").textContent = reply.appkit_supported ? String(reply.hidden) : "unsupported";
    #|        document.querySelector("#appkit").textContent = reply.appkit_supported ? "AppKit group available" : "AppKit group unsupported";
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        try {
    #|          render(await invoke(action));
    #|        } catch (error) {
    #|          status.textContent = `${action} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      for (const action of ["focus", "focus-steal", "hide", "show"]) {
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
  log_app_step("is_ready before App::run = " + @proton.is_ready().to_string())
  @proton.html("Application Control", page(), width=880, height=620)
  .identifier("com.example.proton.app-control")
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      log_app_step(
        "is_ready in app_lifecycle.on_start = " + @proton.is_ready().to_string(),
      )
      // Readiness flips once startup finished: hooks completed and the initial
      // window is ready. The renderer may load before that happens, so the
      // terminal reports the transition instead of the first page readback.
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            while !@proton.is_ready() {
              @async.sleep(10)
            }
            log_app_step("is_ready after startup = true")
          },
          no_wait=true,
        ),
      )
      context
    },
    on_shutdown=fn(_context) {
      application_slot.val = None
      log_app_step("lifecycle shutdown")
    },
  )
  .run_or_abort()
}
