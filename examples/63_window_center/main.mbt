///|
struct CenterRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend CenterRequest with ToJson::{to_json}

///|
pub extend CenterRequest with FromJson::{from_json}

///|
struct CenterReply {
  applied : Bool
  x : Int
  y : Int
  width : Int
  height : Int
  monitor_x : Int
  monitor_y : Int
  monitor_width : Int
  monitor_height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend CenterReply with ToJson::{to_json}

///|
pub extend CenterReply with FromJson::{from_json}

///|
let center_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-center",
  js_namespace="windowCenter",
)

///|
let center_command : @proton_contract.Command[CenterRequest, CenterReply] = center_contract.command(
  "run",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
fn snapshot(
  window : @proton.WindowHandle,
  message : String,
) -> CenterReply raise {
  let state = window.state()
  let monitor = state.monitor
  CenterReply::{
    applied: true,
    x: state.x,
    y: state.y,
    width: state.width,
    height: state.height,
    monitor_x: monitor.x,
    monitor_y: monitor.y,
    monitor_width: monitor.width,
    monitor_height: monitor.height,
    work_x: monitor.work_x,
    work_y: monitor.work_y,
    work_width: monitor.work_width,
    work_height: monitor.work_height,
    message,
  }
}

///|
fn failed_reply(message : String) -> CenterReply {
  CenterReply::{
    applied: false,
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    monitor_x: 0,
    monitor_y: 0,
    monitor_width: 0,
    monitor_height: 0,
    work_x: 0,
    work_y: 0,
    work_width: 0,
    work_height: 0,
    message,
  }
}

///|
fn center_window(request : CenterRequest) -> CenterReply {
  match window_slot.val {
    Some(window) =>
      try {
        match request.action {
          "center" => {
            window.center()
            snapshot(window, "Window centered in the current work area")
          }
          "read" => snapshot(window, "Read current native window state")
          _ => failed_reply("action must be center or read")
        }
      } catch {
        error => failed_reply(error.to_string())
      }
    None => failed_reply("window is not ready")
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(center_command, (_context, request) => center_window(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Center</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #121416; color: #f0f3f5; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #121416; }
    #|      button { font: inherit; }
    #|      main { width: min(860px, calc(100vw - 40px)); margin: 0 auto; padding: 42px 0 50px; }
    #|      header { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 28px; align-items: end; padding-bottom: 25px; border-bottom: 1px solid #3a4147; }
    #|      .eyebrow { margin: 0 0 10px; color: #6fb6e8; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; max-width: 560px; font-size: clamp(34px, 6vw, 54px); line-height: .98; letter-spacing: -.055em; }
    #|      .summary { max-width: 570px; margin: 14px 0 0; color: #a9b2b9; line-height: 1.55; }
    #|      .crosshair { display: grid; place-items: center; width: 112px; aspect-ratio: 1; border: 1px solid #72c58c; border-radius: 50%; background: #18251d; color: #b7ecc5; font: 700 26px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .crosshair::before { content: "+"; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(260px, .85fr); gap: 16px; margin-top: 20px; }
    #|      .panel { border: 1px solid #3a4147; border-radius: 8px; background: #181b1e; overflow: hidden; }
    #|      .panel-head { display: flex; justify-content: space-between; gap: 12px; min-height: 48px; padding: 0 17px; align-items: center; border-bottom: 1px solid #3a4147; color: #aeb6bc; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; }
    #|      .surface { min-height: 235px; padding: 27px; background: #1c2023; }
    #|      .coordinates { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 22px 16px; }
    #|      .coordinate { border-left: 2px solid #72c58c; padding-left: 10px; }
    #|      .coordinate.monitor { border-color: #e2a953; }
    #|      .coordinate.work { border-color: #6fb6e8; }
    #|      .coordinate small { display: block; color: #98a3aa; font: 700 10px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .11em; text-transform: uppercase; }
    #|      .coordinate strong { display: block; margin-top: 6px; color: #eef3f5; font: 700 17px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .controls { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 9px; padding: 15px 17px; border-top: 1px solid #3a4147; }
    #|      button { min-height: 43px; border: 1px solid #59636b; border-radius: 7px; padding: 0 12px; background: #252a2e; color: #f0f3f5; cursor: pointer; font-weight: 720; }
    #|      button:hover { border-color: #6fb6e8; background: #29343c; }
    #|      button:focus-visible { outline: 3px solid #6fb6e866; outline-offset: 3px; }
    #|      button.primary { border-color: #72c58c; background: #28643b; }
    #|      button.primary:hover { background: #337c4b; }
    #|      .readout { display: grid; align-content: start; gap: 18px; padding: 20px; }
    #|      .readout h2 { margin: 0; font-size: 16px; }
    #|      .legend { display: grid; gap: 11px; margin: 0; padding: 0; list-style: none; }
    #|      .legend li { display: grid; grid-template-columns: 10px minmax(0, 1fr); gap: 10px; align-items: center; color: #b7c0c6; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .legend span { width: 10px; height: 10px; border-radius: 50%; background: #72c58c; }
    #|      .legend .monitor-key { background: #e2a953; }
    #|      .legend .work-key { background: #6fb6e8; }
    #|      #status { min-height: 54px; margin: 0; padding-top: 17px; border-top: 1px solid #3a4147; color: #8bcdf5; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      @media (max-width: 720px) { header { grid-template-columns: 1fr; } .crosshair { width: 76px; } .layout { grid-template-columns: 1fr; } }
    #|      @media (max-width: 480px) { main { padding-top: 28px; } .coordinates, .controls { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native surface / manual test 63</p>
    #|          <h1>Center the frame</h1>
    #|          <p class="summary">Place the native window in the current display's usable work area. The page reports the frame and monitor geometry returned by the runtime.</p>
    #|        </div>
    #|        <div class="crosshair" aria-hidden="true"></div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Native geometry</strong><span>live snapshot</span></div>
    #|          <div class="surface">
    #|            <div class="coordinates">
    #|              <div class="coordinate"><small>Window position</small><strong id="position">--</strong></div>
    #|              <div class="coordinate"><small>Window size</small><strong id="size">--</strong></div>
    #|              <div class="coordinate monitor"><small>Monitor</small><strong id="monitor">--</strong></div>
    #|              <div class="coordinate work"><small>Work area</small><strong id="work">--</strong></div>
    #|            </div>
    #|          </div>
    #|          <div class="controls">
    #|            <button id="center" class="primary" type="button">Center window</button>
    #|            <button id="read" type="button">Read geometry</button>
    #|          </div>
    #|        </section>
    #|        <aside class="panel readout">
    #|          <h2>Geometry key</h2>
    #|          <ul class="legend">
    #|            <li><span></span><strong>Window frame</strong></li>
    #|            <li><span class="monitor-key"></span><strong>Current monitor</strong></li>
    #|            <li><span class="work-key"></span><strong>Usable work area</strong></li>
    #|          </ul>
    #|          <p id="status" role="status" aria-live="polite">Ready. Read the current native geometry.</p>
    #|        </aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const position = document.querySelector("#position");
    #|      const size = document.querySelector("#size");
    #|      const monitor = document.querySelector("#monitor");
    #|      const work = document.querySelector("#work");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (action) => window.__MoonBit__.core.invokeOp("ext:windowCenter/run", { action });
    #|      function render(reply) {
    #|        position.textContent = `${reply.x}, ${reply.y}`;
    #|        size.textContent = `${reply.width} x ${reply.height}`;
    #|        monitor.textContent = `${reply.monitor_width} x ${reply.monitor_height} @ ${reply.monitor_x}, ${reply.monitor_y}`;
    #|        work.textContent = `${reply.work_width} x ${reply.work_height} @ ${reply.work_x}, ${reply.work_y}`;
    #|        status.textContent = reply.message;
    #|      }
    #|      async function run(action) {
    #|        status.textContent = action === "center" ? "Centering the native frame..." : "Reading native geometry...";
    #|        try { render(await invoke(action)); }
    #|        catch (error) { status.textContent = `request failed: ${String(error)}`; }
    #|      }
    #|      document.querySelector("#center").addEventListener("click", () => void run("center"));
    #|      document.querySelector("#read").addEventListener("click", () => void run("read"));
    #|      void run("read");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Center", html(), width=860, height=650, debug=true)
  .identifier("dev.proton.window-center")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
