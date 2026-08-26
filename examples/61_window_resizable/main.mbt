///|
struct SetResizableRequest {
  resizable : Bool
} derive(ToJson, FromJson)

///|
pub extend SetResizableRequest with ToJson::{to_json}

///|
pub extend SetResizableRequest with FromJson::{from_json}

///|
struct SetResizableReply {
  applied : Bool
  resizable : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend SetResizableReply with ToJson::{to_json}

///|
pub extend SetResizableReply with FromJson::{from_json}

///|
let resizable_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-resizable",
  js_namespace="windowResizable",
)

///|
let set_resizable_command : @proton_contract.Command[
  SetResizableRequest,
  SetResizableReply,
] = resizable_contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let resizable_state : Ref[Bool] = { val: true, }

///|
fn set_resizable(request : SetResizableRequest) -> SetResizableReply {
  match window_slot.val {
    Some(window) => {
      window.set_resizable(request.resizable) catch {
        error =>
          return SetResizableReply::{
            applied: false,
            resizable: resizable_state.val,
            message: "native call failed: " + error.message(),
          }
      }
      resizable_state.val = request.resizable
      SetResizableReply::{
        applied: true,
        resizable: request.resizable,
        message: if request.resizable {
          "Resizing enabled"
        } else {
          "Resizing disabled"
        },
      }
    }
    None =>
      SetResizableReply::{
        applied: false,
        resizable: resizable_state.val,
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_resizable_command, (_context, request) => {
    set_resizable(request)
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
    #|    <title>Window Resizable</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #0d1117; color: #eef2f7; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #0d1117; }
    #|      button { font: inherit; }
    #|      main { width: min(820px, calc(100vw - 40px)); margin: 0 auto; padding: 42px 0 50px; }
    #|      header { display: flex; align-items: end; justify-content: space-between; gap: 24px; padding-bottom: 25px; border-bottom: 1px solid #2c3644; }
    #|      .eyebrow { margin: 0 0 10px; color: #8ed8ff; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(34px, 6vw, 54px); line-height: .98; letter-spacing: -.055em; }
    #|      .summary { max-width: 520px; margin: 14px 0 0; color: #9aa9bc; line-height: 1.55; }
    #|      .state-chip { flex: none; display: grid; gap: 6px; min-width: 156px; border: 1px solid #2d7aa3; border-radius: 12px; padding: 13px 15px; background: #102536; }
    #|      .state-chip small { color: #76b4d1; font: 700 10px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .12em; text-transform: uppercase; }
    #|      .state-chip strong { color: #d6f2ff; font-size: 17px; }
    #|      .state-chip.off { border-color: #5a6472; background: #1b2028; }
    #|      .state-chip.off small, .state-chip.off strong { color: #b8c1cc; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(250px, .8fr); gap: 16px; margin-top: 20px; }
    #|      .panel { border: 1px solid #2c3644; border-radius: 14px; background: #111821; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 48px; padding: 0 17px; border-bottom: 1px solid #2c3644; color: #9aa9bc; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .05em; text-transform: uppercase; }
    #|      .panel-head strong { color: #d8e1ec; }
    #|      .preview { position: relative; min-height: 278px; padding: 27px; background: radial-gradient(circle at 70% 24%, #16445d 0, #142330 35%, #111821 77%); }
    #|      .preview::after { content: ""; position: absolute; right: 0; bottom: 0; width: 72px; height: 72px; background: repeating-linear-gradient(135deg, transparent 0 7px, #8ed8ff44 8px 9px); opacity: .75; pointer-events: none; }
    #|      .preview-copy { position: relative; z-index: 1; max-width: 410px; }
    #|      .preview h2 { margin: 0 0 9px; font-size: 23px; letter-spacing: -.03em; }
    #|      .preview p { margin: 0; color: #a6b7c9; line-height: 1.6; }
    #|      .edge-note { display: inline-flex; align-items: center; gap: 8px; margin-top: 27px; color: #c8eaff; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .08em; text-transform: uppercase; }
    #|      .edge-note::before { content: ">"; display: grid; place-items: center; width: 24px; height: 24px; border: 1px solid #6eb9db; border-radius: 50%; color: #8ed8ff; font-size: 15px; }
    #|      .controls { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 9px; padding: 15px 17px; border-top: 1px solid #2c3644; }
    #|      button { min-height: 43px; border: 1px solid #405064; border-radius: 8px; padding: 0 12px; background: #1b2531; color: #e9f3fb; cursor: pointer; font-weight: 720; }
    #|      button:hover { border-color: #8ed8ff; background: #213546; }
    #|      button:focus-visible { outline: 3px solid #8ed8ff66; outline-offset: 3px; }
    #|      button.primary { border-color: #2d9bc8; background: #17678a; }
    #|      button.primary:hover { background: #1b7ca5; }
    #|      .review { padding: 20px; }
    #|      .review h2 { margin: 0 0 14px; font-size: 16px; }
    #|      .checklist { display: grid; gap: 13px; margin: 0; padding: 0; list-style: none; }
    #|      .checklist li { position: relative; padding-left: 26px; color: #a6b7c9; font-size: 13px; line-height: 1.5; }
    #|      .checklist li::before { content: ""; position: absolute; left: 1px; top: 5px; width: 10px; height: 10px; border: 1px solid #6eb9db; border-radius: 3px; }
    #|      .log-title { margin-top: 21px !important; padding-top: 18px; border-top: 1px solid #2c3644; }
    #|      #status { min-height: 34px; margin: 16px 0 0; color: #8ed8ff; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      @media (max-width: 720px) { header { align-items: start; flex-direction: column; } .state-chip { width: 100%; } .layout { grid-template-columns: 1fr; } }
    #|      @media (max-width: 460px) { main { padding-top: 28px; } .controls { grid-template-columns: 1fr; } }
    #|      @media (prefers-reduced-motion: reduce) { *, *::before, *::after { transition: none !important; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native surface / manual test 61</p>
    #|          <h1>Window<br>resizable</h1>
    #|          <p class="summary">A small review console for Electron-style live resizing. The control changes the native frame; the web page only reports the state.</p>
    #|        </div>
    #|        <div id="state-chip" class="state-chip">
    #|          <small>Native window</small>
    #|          <strong id="state-label">Resizable</strong>
    #|        </div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Window frame</strong><span>drag the lower-right edge</span></div>
    #|          <div class="preview">
    #|            <div class="preview-copy">
    #|              <h2>Can the frame breathe?</h2>
    #|              <p>Resize this application with the native border, then disable resizing and try again. Re-enable it without restarting the process.</p>
    #|              <div class="edge-note">Resize handle is outside the page</div>
    #|            </div>
    #|          </div>
    #|          <div class="controls">
    #|            <button id="enable" class="primary" type="button">Enable resizing</button>
    #|            <button id="disable" type="button">Disable resizing</button>
    #|            <button id="toggle" type="button">Toggle</button>
    #|          </div>
    #|        </section>
    #|        <aside class="panel review">
    #|          <h2>Manual review</h2>
    #|          <ul class="checklist">
    #|            <li>Drag the lower-right edge and confirm the native window changes size.</li>
    #|            <li>Choose <strong>Disable resizing</strong>; the edge should stop accepting a resize gesture.</li>
    #|            <li>Choose <strong>Enable resizing</strong> and resize again without restarting.</li>
    #|            <li>Resize while the page is narrow and wide; the content should remain usable.</li>
    #|            <li>On Windows at display scaling above 100%, confirm the frame and page stay aligned.</li>
    #|          </ul>
    #|          <h2 class="log-title">Bridge status</h2>
    #|          <p id="status" role="status" aria-live="polite">Ready. The native frame starts resizable.</p>
    #|        </aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const stateChip = document.querySelector("#state-chip");
    #|      const stateLabel = document.querySelector("#state-label");
    #|      const status = document.querySelector("#status");
    #|      let current = true;
    #|      const invoke = (resizable) => window.__MoonBit__.core.invokeOp("ext:windowResizable/set", { resizable });
    #|      function render(resizable, message) {
    #|        current = resizable;
    #|        stateLabel.textContent = resizable ? "Resizable" : "Fixed size";
    #|        stateChip.classList.toggle("off", !resizable);
    #|        status.textContent = message;
    #|      }
    #|      async function setResizable(resizable) {
    #|        status.textContent = resizable ? "Enabling native resizing..." : "Disabling native resizing...";
    #|        try {
    #|          const reply = await invoke(resizable);
    #|          render(reply.resizable, reply.message);
    #|        } catch (error) {
    #|          status.textContent = `request failed: ${String(error)}`;
    #|        }
    #|      }
    #|      document.querySelector("#enable").addEventListener("click", () => void setResizable(true));
    #|      document.querySelector("#disable").addEventListener("click", () => void setResizable(false));
    #|      document.querySelector("#toggle").addEventListener("click", () => void setResizable(!current));
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Resizable", html(), width=820, height=620, debug=true)
  .identifier("dev.proton.window-resizable")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      resizable_state.val = true
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
