///|
struct SkipTaskbarRequest {
  skip : Bool
} derive(ToJson, FromJson)

///|
pub extend SkipTaskbarRequest with ToJson::{to_json}

///|
pub extend SkipTaskbarRequest with FromJson::{from_json}

///|
struct SkipTaskbarReply {
  applied : Bool
  skip : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend SkipTaskbarReply with ToJson::{to_json}

///|
pub extend SkipTaskbarReply with FromJson::{from_json}

///|
let taskbar_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-skip-taskbar",
  js_namespace="windowSkipTaskbar",
)

///|
let taskbar_command : @proton_contract.Command[
  SkipTaskbarRequest,
  SkipTaskbarReply,
] = taskbar_contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let skip_state : Ref[Bool] = { val: false, }

///|
fn set_skip_taskbar(request : SkipTaskbarRequest) -> SkipTaskbarReply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_skip_taskbar(request.skip)
        skip_state.val = request.skip
        SkipTaskbarReply::{
          applied: true,
          skip: request.skip,
          message: if request.skip {
            "Taskbar omission requested"
          } else {
            "Taskbar presence requested"
          },
        }
      } catch {
        error =>
          SkipTaskbarReply::{
            applied: false,
            skip: skip_state.val,
            message: "native call failed: " + error.to_string(),
          }
      }
    None =>
      SkipTaskbarReply::{
        applied: false,
        skip: skip_state.val,
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(taskbar_command, (_context, request) => {
    set_skip_taskbar(request)
  })
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Taskbar Visibility</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Segoe UI, Avenir Next, sans-serif; background: #171a1d; color: #edf0ef; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #171a1d; }
    #|      button { font: inherit; }
    #|      main { width: min(780px, calc(100vw - 36px)); margin: 0 auto; padding: 42px 0 50px; }
    #|      header { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 28px; align-items: end; padding-bottom: 24px; border-bottom: 1px solid #51585c; }
    #|      .eyebrow { margin: 0 0 9px; color: #63c4aa; font: 750 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      h1 { margin: 0; max-width: 530px; font-size: 44px; line-height: .96; letter-spacing: 0; }
    #|      .summary { max-width: 560px; margin: 15px 0 0; color: #a8b0b3; line-height: 1.55; }
    #|      .tab-mark { display: grid; place-items: center; width: 118px; height: 76px; border: 1px solid #667075; background: #252a2e; color: #93e2cc; font: 750 12px/1 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      .panel { display: grid; grid-template-columns: minmax(0, 1fr) 250px; margin-top: 20px; border: 1px solid #51585c; background: #202428; }
    #|      .visual { position: relative; min-height: 280px; border-right: 1px solid #51585c; background: #2a3034; overflow: hidden; }
    #|      .desktop { position: absolute; inset: 30px 28px 62px; border: 1px solid #778188; background: #343c41; }
    #|      .window-shape { position: absolute; inset: 65px 73px 100px; border: 2px solid #d8dfdc; background: #1e2326; box-shadow: 9px 9px 0 #111416; }
    #|      .window-shape::before { content: ""; display: block; height: 27px; border-bottom: 1px solid #737d81; background: #333a3e; }
    #|      .taskbar { position: absolute; left: 28px; right: 28px; bottom: 25px; display: flex; align-items: center; gap: 8px; height: 38px; border: 1px solid #778188; padding: 0 10px; background: #121619; }
    #|      .start { width: 18px; height: 18px; border: 1px solid #899398; background: #353d42; }
    #|      .app-tab { min-width: 112px; height: 24px; border-bottom: 2px solid #63c4aa; background: #30383d; transition: opacity 120ms ease; }
    #|      .app-tab.hidden { opacity: .18; border-bottom-color: #596267; }
    #|      .controls { display: grid; align-content: start; gap: 20px; padding: 22px; }
    #|      .state small { display: block; color: #939da2; font: 700 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .state strong { display: block; margin-top: 8px; color: #eff4f2; font-size: 20px; }
    #|      .switch { display: grid; grid-template-columns: 1fr auto; gap: 14px; align-items: center; border: 1px solid #596368; padding: 14px; background: #292f33; cursor: pointer; }
    #|      .switch span { font-weight: 720; }
    #|      .switch input { position: absolute; opacity: 0; pointer-events: none; }
    #|      .track { position: relative; width: 44px; height: 24px; border: 1px solid #707a7f; border-radius: 12px; background: #3a4247; }
    #|      .track::after { content: ""; position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 50%; background: #c7cecb; transition: transform 120ms ease; }
    #|      .switch input:checked + .track { border-color: #57bca1; background: #286451; }
    #|      .switch input:checked + .track::after { transform: translateX(20px); background: #f0fff9; }
    #|      .switch:focus-within { outline: 3px solid #63c4aa55; outline-offset: 3px; }
    #|      #status { min-height: 58px; margin: 0; padding-top: 17px; border-top: 1px solid #51585c; color: #8bdac4; font: 12px/1.5 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      @media (max-width: 650px) { header { grid-template-columns: 1fr; } .tab-mark { width: 118px; } .panel { grid-template-columns: 1fr; } .visual { border-right: 0; border-bottom: 1px solid #51585c; } }
    #|      @media (max-width: 430px) { h1 { font-size: 36px; } .window-shape { inset-inline: 48px; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native shell / manual test 66</p>
    #|          <h1>Taskbar visibility</h1>
    #|          <p class="summary">Toggle whether the live application window asks to appear in the operating system taskbar.</p>
    #|        </div>
    #|        <div class="tab-mark">APP TAB</div>
    #|      </header>
    #|      <section class="panel">
    #|        <div class="visual" aria-hidden="true">
    #|          <div class="desktop"></div><div class="window-shape"></div>
    #|          <div class="taskbar"><span class="start"></span><span id="app-tab" class="app-tab"></span></div>
    #|        </div>
    #|        <div class="controls">
    #|          <div class="state"><small>Requested state</small><strong id="state">Shown in taskbar</strong></div>
    #|          <label class="switch"><span>Skip taskbar</span><span><input id="skip" type="checkbox"><i class="track"></i></span></label>
    #|          <p id="status" role="status" aria-live="polite">Ready. The native window starts with its normal taskbar presence.</p>
    #|        </div>
    #|      </section>
    #|    </main>
    #|    <script>
    #|      const checkbox = document.querySelector("#skip");
    #|      const state = document.querySelector("#state");
    #|      const appTab = document.querySelector("#app-tab");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (skip) => window.__MoonBit__.core.invokeOp("ext:windowSkipTaskbar/set", { skip });
    #|      function render(skip, message) {
    #|        checkbox.checked = skip;
    #|        state.textContent = skip ? "Omitted from taskbar" : "Shown in taskbar";
    #|        appTab.classList.toggle("hidden", skip);
    #|        status.textContent = message;
    #|      }
    #|      checkbox.addEventListener("change", async () => {
    #|        const requested = checkbox.checked;
    #|        status.textContent = "Updating native taskbar visibility...";
    #|        try {
    #|          const reply = await invoke(requested);
    #|          render(reply.skip, reply.message);
    #|        } catch (error) {
    #|          checkbox.checked = !requested;
    #|          status.textContent = `request failed: ${String(error)}`;
    #|        }
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html(
    "Window Taskbar Visibility",
    html(),
    width=780,
    height=590,
    debug=true,
  )
  .identifier("dev.proton.window-skip-taskbar")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      skip_state.val = false
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
