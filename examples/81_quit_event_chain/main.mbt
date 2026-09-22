///|
struct QuitRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend QuitRequest with ToJson::{to_json}

///|
pub extend QuitRequest with FromJson::{from_json}

///|
struct QuitReply {
  ok : Bool
  before_quit_blocked : Bool
  will_quit_blocked : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend QuitReply with ToJson::{to_json}

///|
pub extend QuitReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/quit-event-chain",
  js_namespace="quitChain",
)

///|
let control_command : @proton_contract.Command[QuitRequest, QuitReply] = contract.command(
  "control",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
let block_before_quit : Ref[Bool] = { val: false, }

///|
let block_will_quit : Ref[Bool] = { val: false, }

///|
/// Emits one review line for the terminal that started the example.
fn log_chain_step(step : String) -> Unit {
  println("[quit-chain] " + step)
}

///|
fn state_reply(message : String, ok? : Bool = true) -> QuitReply {
  {
    ok,
    before_quit_blocked: block_before_quit.val,
    will_quit_blocked: block_will_quit.val,
    message,
  }
}

///|
fn toggle_reply(
  state : Ref[Bool],
  enabled : String,
  disabled : String,
) -> QuitReply {
  state.val = !state.val
  state_reply(if state.val { enabled } else { disabled })
}

///|
fn control(request : QuitRequest) -> QuitReply {
  let context = match application_slot.val {
    Some(context) => context
    None => return state_reply("Application context is not ready", ok=false)
  }
  match request.action {
    "state" => state_reply("Quit chain state refreshed")
    "toggle-before-quit" =>
      toggle_reply(
        block_before_quit, "before-quit now prevents the quit", "before-quit now allows the quit",
      )
    "toggle-will-quit" =>
      toggle_reply(
        block_will_quit, "will-quit now prevents the quit", "will-quit now allows the quit",
      )
    "close-window" =>
      match context.windows().find("main") {
        Some(window) => {
          window.close() catch {
            error =>
              return state_reply(
                "Main window close failed: " + error.message(),
                ok=false,
              )
          }
          state_reply("Main window close requested")
        }
        None => state_reply("Main window is not open", ok=false)
      }
    "quit" => {
      context.quit()
      state_reply("Orderly quit requested with exit code 0")
    }
    "quit-3" => {
      context.quit(exit_code=3)
      state_reply("Orderly quit requested with exit code 3")
    }
    "exit-7" => {
      context.exit(exit_code=7)
      state_reply("Forced exit requested with exit code 7")
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
    #|    <title>Quit Event Chain</title>
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
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1fr); gap: 14px; margin-top: 22px; }
    #|      .panel { border: 1px solid #2b353d; border-radius: 12px; background: #151b21; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; min-height: 46px; padding: 0 16px; border-bottom: 1px solid #2b353d; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      .panel-body { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; padding: 16px; }
    #|      .panel-body.wide { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    #|      .action { min-height: 44px; padding: 0 14px; border: 1px solid #3a4a55; border-radius: 8px; background: #1b232a; color: #eef3f6; font-weight: 600; }
    #|      .action.primary { border-color: #2f6f63; background: #20564d; }
    #|      .action.danger { border-color: #7c3a33; background: #5f2d28; }
    #|      .action[aria-pressed="true"] { border-color: #b8860b; background: #4a3a12; }
    #|      .state { display: grid; grid-template-columns: 190px minmax(0, 1fr); gap: 6px 16px; padding: 0 16px 16px; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .state dt { color: #8b9aa6; }
    #|      .state dd { margin: 0; color: #eef3f6; }
    #|      .status { margin-top: 16px; padding: 14px 16px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; color: #cfe7ef; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Electron app / review 81</p>
    #|        <h1>Quit event chain</h1>
    #|        <p class="summary">
    #|          Run this example from a terminal. Every step prints one
    #|          <code>[quit-chain]</code> line and the process exit status is the
    #|          code requested by the button you pressed.
    #|        </p>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><span>Cancelable steps</span><span id="step-state">idle</span></div>
    #|          <div class="panel-body">
    #|            <button class="action" id="toggle-before" aria-pressed="false">Block before-quit</button>
    #|            <button class="action" id="toggle-will" aria-pressed="false">Block will-quit</button>
    #|          </div>
    #|          <dl class="state">
    #|            <dt>before-quit</dt><dd id="before-state">allows the quit</dd>
    #|            <dt>will-quit</dt><dd id="will-state">allows the quit</dd>
    #|          </dl>
    #|        </section>
    #|        <section class="panel">
    #|          <div class="panel-head"><span>Terminate</span><span>exit codes</span></div>
    #|          <div class="panel-body wide">
    #|            <button class="action primary" id="quit">Quit (0)</button>
    #|            <button class="action primary" id="quit-3">Quit (3)</button>
    #|            <button class="action danger" id="exit-7">Exit (7)</button>
    #|          </div>
    #|          <dl class="state">
    #|            <dt>Quit</dt><dd>runs before-quit, closes windows, runs will-quit, then quit</dd>
    #|            <dt>Exit</dt><dd>destroys windows now, skips before-quit and will-quit, still reports quit</dd>
    #|            <dt>Last window</dt><dd><button class="action" id="close-window" style="min-height:30px">Close the window</button> and the quit chain starts automatically</dd>
    #|          </dl>
    #|        </section>
    #|      </div>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      const stepState = document.querySelector("#step-state");
    #|      const beforeButton = document.querySelector("#toggle-before");
    #|      const willButton = document.querySelector("#toggle-will");
    #|      async function invoke(action) {
    #|        return window.__MoonBit__.core.invokeOp("ext:quitChain/control", { action });
    #|      }
    #|      function render(reply) {
    #|        beforeButton.setAttribute("aria-pressed", String(reply.before_quit_blocked));
    #|        willButton.setAttribute("aria-pressed", String(reply.will_quit_blocked));
    #|        document.querySelector("#before-state").textContent = reply.before_quit_blocked
    #|          ? "prevents the quit"
    #|          : "allows the quit";
    #|        document.querySelector("#will-state").textContent = reply.will_quit_blocked
    #|          ? "prevents the quit"
    #|          : "allows the quit";
    #|        stepState.textContent = `${reply.before_quit_blocked ? "before-quit blocked" : "before-quit allowed"} / ${reply.will_quit_blocked ? "will-quit blocked" : "will-quit allowed"}`;
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        try {
    #|          render(await invoke(action));
    #|        } catch (error) {
    #|          status.textContent = `${action} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      beforeButton.addEventListener("click", () => void run("toggle-before-quit"));
    #|      willButton.addEventListener("click", () => void run("toggle-will-quit"));
    #|      document.querySelector("#quit").addEventListener("click", () => void run("quit"));
    #|      document.querySelector("#quit-3").addEventListener("click", () => void run("quit-3"));
    #|      document.querySelector("#exit-7").addEventListener("click", () => void run("exit-7"));
    #|      document.querySelector("#close-window").addEventListener("click", () => void run("close-window"));
    #|      void run("state");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Quit Event Chain", page(), width=900, height=700)
  .identifier("com.example.proton.quit-event-chain")
  .single_instance()
  // A prevented `will-quit` leaves the application running without windows.
  // Launching the same application again must reopen the main window.
  .on_launch_input(async fn(context, input) noraise {
    if input is @proton.RuntimeLaunchInput::Reopen &&
      context.windows().find("main") is None {
      ignore(context.windows().open("main")) catch {
        error => println("[quit-chain] reopen failed: " + error.to_string())
      }
    }
  })
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      context
    },
    on_shutdown=fn(_context) {
      application_slot.val = None
      log_chain_step("lifecycle shutdown")
    },
  )
  .on_before_quit(fn(_context) {
    log_chain_step("before-quit blocked=" + block_before_quit.val.to_string())
    if block_before_quit.val {
      @proton.ApplicationQuitDecision::Prevent
    } else {
      @proton.ApplicationQuitDecision::Allow
    }
  })
  .on_will_quit(fn(_context) {
    log_chain_step("will-quit blocked=" + block_will_quit.val.to_string())
    if block_will_quit.val {
      @proton.ApplicationQuitDecision::Prevent
    } else {
      @proton.ApplicationQuitDecision::Allow
    }
  })
  .on_quit(fn(_context, exit_code) {
    log_chain_step("quit exit_code=" + exit_code.to_string())
  })
  .run_or_abort()
}
