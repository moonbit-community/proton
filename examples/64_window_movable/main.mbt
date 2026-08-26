///|
struct MovableRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend MovableRequest with ToJson::{to_json}

///|
pub extend MovableRequest with FromJson::{from_json}

///|
struct MovableReply {
  applied : Bool
  movable : Bool
  x : Int
  y : Int
  width : Int
  height : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend MovableReply with ToJson::{to_json}

///|
pub extend MovableReply with FromJson::{from_json}

///|
let movable_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-movable",
  js_namespace="windowMovable",
)

///|
let movable_command : @proton_contract.Command[MovableRequest, MovableReply] = movable_contract.command(
  "run",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let movable_state : Ref[Bool] = { val: true, }

///|
fn snapshot(
  window : @proton.WindowHandle,
  applied : Bool,
  message : String,
) -> MovableReply raise {
  let state = window.state()
  MovableReply::{
    applied,
    movable: movable_state.val,
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    message,
  }
}

///|
fn failed_reply(message : String) -> MovableReply {
  MovableReply::{
    applied: false,
    movable: movable_state.val,
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    message,
  }
}

///|
fn run_action(request : MovableRequest) -> MovableReply {
  match window_slot.val {
    Some(window) =>
      try {
        match request.action {
          "disable" => {
            window.set_movable(false)
            movable_state.val = false
            snapshot(window, true, "Manual title-bar movement disabled")
          }
          "enable" => {
            window.set_movable(true)
            movable_state.val = true
            snapshot(window, true, "Manual title-bar movement enabled")
          }
          "nudge" => {
            let state = window.state()
            window.set_position(state.x + 48, state.y + 32)
            snapshot(
              window, true, "Moved programmatically by +48, +32 while the manual setting stayed unchanged",
            )
          }
          "center" => {
            window.center()
            snapshot(window, true, "Centered programmatically")
          }
          "read" => snapshot(window, true, "Read current native geometry")
          _ =>
            failed_reply(
              "action must be disable, enable, nudge, center, or read",
            )
        }
      } catch {
        error => failed_reply("native call failed: " + error.to_string())
      }
    None => failed_reply("window is not ready")
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(movable_command, (_context, request) => run_action(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Movable</title>
    #|    <style>
    #|      :root { color-scheme: light; font-family: Avenir Next, Avenir, Segoe UI, sans-serif; background: #dce5e1; color: #12211d; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #dce5e1; }
    #|      button { font: inherit; }
    #|      main { width: min(930px, calc(100vw - 40px)); margin: 0 auto; padding: 36px 0 48px; }
    #|      header { display: grid; grid-template-columns: minmax(0, 1fr) 230px; gap: 34px; align-items: end; padding: 0 4px 24px; border-bottom: 2px solid #19332b; }
    #|      .eyebrow { margin: 0 0 9px; color: #17614c; font: 750 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      h1 { margin: 0; font: 750 46px/.92 Georgia, Times New Roman, serif; letter-spacing: 0; }
    #|      .summary { max-width: 600px; margin: 18px 0 0; color: #40554e; line-height: 1.55; }
    #|      .drag-ticket { position: relative; border: 2px solid #19332b; padding: 17px 18px 15px; background: #eff4f1; box-shadow: 7px 7px 0 #19332b; }
    #|      .drag-ticket::before { content: "<->"; display: block; color: #d14f34; font: 800 28px/1 Georgia, serif; }
    #|      .drag-ticket small { display: block; margin-top: 11px; color: #52675f; font: 700 10px/1.3 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      .drag-ticket strong { display: block; margin-top: 5px; font-size: 16px; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(280px, .8fr); gap: 18px; margin-top: 20px; }
    #|      .panel { border: 1px solid #80968d; background: #f5f7f5cc; backdrop-filter: blur(12px); }
    #|      .panel-head { display: flex; justify-content: space-between; gap: 12px; min-height: 48px; padding: 0 17px; align-items: center; border-bottom: 1px solid #9bada6; color: #52675f; font: 700 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      .panel-head strong { color: #183a30; }
    #|      .stage { position: relative; min-height: 244px; padding: 26px; overflow: hidden; background-image: linear-gradient(#9bb0a733 1px, transparent 1px), linear-gradient(90deg, #9bb0a733 1px, transparent 1px); background-size: 28px 28px; }
    #|      .frame { position: absolute; inset: 46px 60px 48px 48px; border: 2px solid #19332b; background: #f8faf8; box-shadow: 12px 12px 0 #92a9a0; }
    #|      .frame-bar { display: flex; align-items: center; gap: 7px; height: 36px; padding: 0 12px; border-bottom: 2px solid #19332b; background: #d5e1dc; }
    #|      .frame-bar i { width: 9px; height: 9px; border: 1px solid #19332b; border-radius: 50%; background: #d14f34; }
    #|      .frame-bar i:nth-child(2) { background: #e9b84d; }
    #|      .frame-bar i:nth-child(3) { background: #4a9b78; }
    #|      .frame-copy { display: grid; place-items: center; min-height: 118px; padding: 18px; text-align: center; }
    #|      .frame-copy strong { color: #19332b; font: 740 17px/1.25 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      .frame-copy span { display: block; margin-top: 8px; color: #5e736b; font-size: 12px; }
    #|      .controls { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 9px; padding: 16px 17px; border-top: 1px solid #9bada6; }
    #|      button { min-height: 44px; border: 1px solid #526d63; padding: 0 12px; background: #e5ece8; color: #17382e; cursor: pointer; font-weight: 750; }
    #|      button:hover { background: #d5e3dd; border-color: #19332b; }
    #|      button:focus-visible { outline: 3px solid #d14f3466; outline-offset: 3px; }
    #|      button.primary { border-color: #b53d27; background: #d14f34; color: #fff8f3; }
    #|      button.primary:hover { background: #b9432d; }
    #|      .review { display: grid; align-content: start; gap: 18px; padding: 20px; }
    #|      .state { display: grid; grid-template-columns: 1fr auto; gap: 13px; align-items: center; padding-bottom: 17px; border-bottom: 1px solid #9bada6; }
    #|      .state small { color: #60746d; font: 700 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      .state strong { display: block; margin-top: 6px; font-size: 19px; }
    #|      .lamp { width: 18px; height: 18px; border: 2px solid #19332b; border-radius: 50%; background: #4a9b78; box-shadow: 0 0 0 5px #4a9b7830; }
    #|      .lamp.locked { background: #d14f34; box-shadow: 0 0 0 5px #d14f3430; }
    #|      .geometry { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    #|      .geometry div { border-left: 3px solid #4a9b78; padding-left: 9px; }
    #|      .geometry small { display: block; color: #60746d; font: 700 9px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .geometry strong { display: block; margin-top: 5px; font: 750 13px/1.2 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      #status { min-height: 52px; margin: 0; padding-top: 16px; border-top: 1px solid #9bada6; color: #17614c; font: 12px/1.5 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      @media (max-width: 760px) { header { grid-template-columns: 1fr; } .drag-ticket { width: min(100%, 300px); } .layout { grid-template-columns: 1fr; } }
    #|      @media (max-width: 480px) { main { padding-top: 26px; } h1 { font-size: 38px; } .controls { grid-template-columns: 1fr; } .frame { inset: 42px 26px 42px 26px; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native frame / manual test 64</p>
    #|          <h1>Hold the<br>window still.</h1>
    #|          <p class="summary">Disable only the user's title-bar drag gesture, then prove programmatic placement remains available. This matches Electron's platform behavior.</p>
    #|        </div>
    #|        <div class="drag-ticket"><small>Review gesture</small><strong>Drag the real title bar, not this page.</strong></div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Movement lab</strong><span>native frame outside renderer</span></div>
    #|          <div class="stage" aria-hidden="true">
    #|            <div class="frame">
    #|              <div class="frame-bar"><i></i><i></i><i></i></div>
    #|              <div class="frame-copy"><div><strong id="diagram-state">MANUAL MOVE: ENABLED</strong><span>Programmatic move always remains enabled</span></div></div>
    #|            </div>
    #|          </div>
    #|          <div class="controls">
    #|            <button id="disable" class="primary" type="button">Disable manual movement</button>
    #|            <button id="enable" type="button">Enable manual movement</button>
    #|            <button id="nudge" type="button">Programmatic nudge</button>
    #|            <button id="center" type="button">Center window</button>
    #|          </div>
    #|        </section>
    #|        <aside class="panel review">
    #|          <div class="state"><div><small>Manual title-bar drag</small><strong id="state-label">Enabled</strong></div><span id="lamp" class="lamp"></span></div>
    #|          <div class="geometry"><div><small>Position</small><strong id="position">--</strong></div><div><small>Size</small><strong id="size">--</strong></div></div>
    #|          <p id="status" role="status" aria-live="polite">Ready. Manual movement starts enabled.</p>
    #|        </aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const stateLabel = document.querySelector("#state-label");
    #|      const diagramState = document.querySelector("#diagram-state");
    #|      const lamp = document.querySelector("#lamp");
    #|      const position = document.querySelector("#position");
    #|      const size = document.querySelector("#size");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (action) => window.__MoonBit__.core.invokeOp("ext:windowMovable/run", { action });
    #|      function render(reply) {
    #|        stateLabel.textContent = reply.movable ? "Enabled" : "Disabled";
    #|        diagramState.textContent = `MANUAL MOVE: ${reply.movable ? "ENABLED" : "DISABLED"}`;
    #|        lamp.classList.toggle("locked", !reply.movable);
    #|        position.textContent = `${reply.x}, ${reply.y}`;
    #|        size.textContent = `${reply.width} x ${reply.height}`;
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        status.textContent = `Running ${action}...`;
    #|        try { render(await invoke(action)); }
    #|        catch (error) { status.textContent = `request failed: ${String(error)}`; }
    #|      }
    #|      document.querySelector("#disable").addEventListener("click", () => void run("disable"));
    #|      document.querySelector("#enable").addEventListener("click", () => void run("enable"));
    #|      document.querySelector("#nudge").addEventListener("click", () => void run("nudge"));
    #|      document.querySelector("#center").addEventListener("click", () => void run("center"));
    #|      void run("read");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Movable", html(), width=930, height=700, debug=true)
  .identifier("dev.proton.window-movable")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      movable_state.val = true
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
