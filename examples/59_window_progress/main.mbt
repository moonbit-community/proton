///|
struct SetProgressRequest {
  progress : Double
} derive(ToJson, FromJson)

///|
pub extend SetProgressRequest with ToJson::{to_json}

///|
pub extend SetProgressRequest with FromJson::{from_json}

///|
struct SetProgressReply {
  applied : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend SetProgressReply with ToJson::{to_json}

///|
pub extend SetProgressReply with FromJson::{from_json}

///|
let progress_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-progress",
  js_namespace="windowProgress",
)

///|
let set_progress_command : @proton_contract.Command[
  SetProgressRequest,
  SetProgressReply,
] = progress_contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
fn set_progress(request : SetProgressRequest) -> SetProgressReply {
  match window_slot.val {
    Some(window) => {
      window.set_progress_bar(request.progress) catch {
        error =>
          return SetProgressReply::{
            applied: false,
            message: "native call failed: " + error.message(),
          }
      }
      SetProgressReply::{ applied: true, message: "progress updated", }
    }
    None =>
      SetProgressReply::{ applied: false, message: "window is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_progress_command, (_context, request) => {
    set_progress(request)
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
    #|    <title>Window Progress</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101216; color: #f5f7fa; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #101216; }
    #|      button, input { font: inherit; }
    #|      main { width: min(760px, calc(100vw - 40px)); margin: 0 auto; padding: 48px 0; }
    #|      header { border-bottom: 1px solid #343943; padding-bottom: 24px; }
    #|      .eyebrow { margin: 0 0 10px; color: #66d9a8; font: 700 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: 42px; line-height: 1.05; }
    #|      .meter { display: grid; grid-template-columns: 116px minmax(0, 1fr); gap: 28px; align-items: center; padding: 42px 0 34px; }
    #|      .value { display: grid; place-items: center; width: 116px; aspect-ratio: 1; border: 1px solid #4a515e; border-radius: 8px; background: #191d24; color: #7ee2b8; font: 700 28px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .track { display: grid; gap: 15px; min-width: 0; }
    #|      label { color: #b9c0cb; font-size: 13px; }
    #|      input[type="range"] { width: 100%; accent-color: #22b77b; }
    #|      .bar { height: 12px; border: 1px solid #414854; border-radius: 4px; overflow: hidden; background: #171a20; }
    #|      .bar span { display: block; width: 35%; height: 100%; background: #22b77b; transition: width 100ms linear; }
    #|      .commands { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; border-top: 1px solid #343943; padding-top: 24px; }
    #|      button { min-height: 44px; border: 1px solid #4a515e; border-radius: 6px; padding: 0 14px; background: #20252d; color: #f5f7fa; cursor: pointer; }
    #|      button:hover { border-color: #66d9a8; background: #252c34; }
    #|      button:focus-visible, input:focus-visible { outline: 3px solid #66d9a866; outline-offset: 3px; }
    #|      button.primary { border-color: #22b77b; background: #17885e; }
    #|      button.primary:hover { background: #1d9c6c; }
    #|      #status { min-height: 24px; margin: 20px 0 0; color: #9da6b3; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      @media (max-width: 560px) { main { padding-top: 28px; } h1 { font-size: 34px; } .meter { grid-template-columns: 1fr; } .commands { grid-template-columns: 1fr; } }
    #|      @media (prefers-reduced-motion: reduce) { .bar span { transition: none; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Native surface / manual test 59</p>
    #|        <h1>Window progress</h1>
    #|      </header>
    #|      <section class="meter">
    #|        <output id="value" class="value" for="progress">35%</output>
    #|        <div class="track">
    #|          <label for="progress">Determinate progress</label>
    #|          <input id="progress" type="range" min="0" max="100" value="35" step="1">
    #|          <div class="bar" aria-hidden="true"><span id="fill"></span></div>
    #|        </div>
    #|      </section>
    #|      <div class="commands">
    #|        <button id="indeterminate" type="button">Indeterminate</button>
    #|        <button id="clear" type="button">Clear</button>
    #|        <button id="cycle" class="primary" type="button">Run cycle</button>
    #|      </div>
    #|      <p id="status" role="status" aria-live="polite">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const slider = document.querySelector("#progress");
    #|      const value = document.querySelector("#value");
    #|      const fill = document.querySelector("#fill");
    #|      const status = document.querySelector("#status");
    #|      const cycleButton = document.querySelector("#cycle");
    #|      let cycleTimer = 0;
    #|      const invoke = (progress) => window.__MoonBit__.core.invokeOp("ext:windowProgress/set", { progress });
    #|      function render(percent) {
    #|        slider.value = String(percent);
    #|        value.textContent = `${percent}%`;
    #|        fill.style.width = `${percent}%`;
    #|      }
    #|      async function apply(progress, label) {
    #|        status.textContent = `${label}...`;
    #|        try {
    #|          const reply = await invoke(progress);
    #|          status.textContent = reply.applied ? label : reply.message;
    #|        } catch (error) {
    #|          status.textContent = `request failed: ${String(error)}`;
    #|        }
    #|      }
    #|      function stopCycle() {
    #|        if (cycleTimer) window.clearInterval(cycleTimer);
    #|        cycleTimer = 0;
    #|        cycleButton.textContent = "Run cycle";
    #|      }
    #|      slider.addEventListener("input", () => {
    #|        stopCycle();
    #|        const percent = Number(slider.value);
    #|        render(percent);
    #|        void apply(percent / 100, `Determinate ${percent}%`);
    #|      });
    #|      document.querySelector("#indeterminate").addEventListener("click", () => {
    #|        stopCycle();
    #|        void apply(2, "Indeterminate");
    #|      });
    #|      document.querySelector("#clear").addEventListener("click", () => {
    #|        stopCycle();
    #|        void apply(-1, "Cleared");
    #|      });
    #|      cycleButton.addEventListener("click", () => {
    #|        if (cycleTimer) {
    #|          stopCycle();
    #|          void apply(-1, "Cycle stopped and cleared");
    #|          return;
    #|        }
    #|        let percent = 0;
    #|        cycleButton.textContent = "Stop cycle";
    #|        render(percent);
    #|        void apply(0, "Cycle 0%");
    #|        cycleTimer = window.setInterval(() => {
    #|          percent += 2;
    #|          if (percent > 100) {
    #|            stopCycle();
    #|            void apply(-1, "Cycle complete and cleared");
    #|            return;
    #|          }
    #|          render(percent);
    #|          void apply(percent / 100, `Cycle ${percent}%`);
    #|        }, 100);
    #|      });
    #|      void apply(0.35, "Determinate 35%");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Progress", html(), width=760, height=560, debug=true)
  .identifier("dev.proton.window-progress")
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
