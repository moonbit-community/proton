///|
struct OpacityRequest {
  opacity : Double
} derive(ToJson, FromJson)

///|
pub extend OpacityRequest with ToJson::{to_json}

///|
pub extend OpacityRequest with FromJson::{from_json}

///|
struct OpacityReply {
  applied : Bool
  opacity : Double
  message : String
} derive(ToJson, FromJson)

///|
pub extend OpacityReply with ToJson::{to_json}

///|
pub extend OpacityReply with FromJson::{from_json}

///|
let opacity_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-opacity",
  js_namespace="windowOpacity",
)

///|
let opacity_command : @proton_contract.Command[OpacityRequest, OpacityReply] = opacity_contract.command(
  "set",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let opacity_state : Ref[Double] = { val: 1.0, }

///|
fn set_opacity(request : OpacityRequest) -> OpacityReply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_opacity(request.opacity)
        let bounded = if request.opacity < 0.0 {
          0.0
        } else if request.opacity > 1.0 {
          1.0
        } else {
          request.opacity
        }
        opacity_state.val = bounded
        OpacityReply::{
          applied: true,
          opacity: bounded,
          message: "Native window opacity updated",
        }
      } catch {
        error =>
          OpacityReply::{
            applied: false,
            opacity: opacity_state.val,
            message: "native call failed: " + error.to_string(),
          }
      }
    None =>
      OpacityReply::{
        applied: false,
        opacity: opacity_state.val,
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(opacity_command, (_context, request) => set_opacity(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Opacity</title>
    #|    <style>
    #|      :root { color-scheme: light; font-family: Charter, Georgia, serif; background: #f2eee5; color: #202522; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #f2eee5; }
    #|      button, input { font: inherit; }
    #|      main { width: min(880px, calc(100vw - 36px)); margin: 0 auto; padding: 34px 0 48px; }
    #|      header { display: grid; grid-template-columns: minmax(0, 1fr) 190px; gap: 32px; align-items: end; padding: 0 2px 24px; border-bottom: 1px solid #26322d; }
    #|      .eyebrow { margin: 0 0 8px; color: #a33e2f; font: 750 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: 0; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: 48px; line-height: .94; letter-spacing: 0; }
    #|      .summary { max-width: 540px; margin: 16px 0 0; color: #59645f; font: 15px/1.55 Avenir Next, Segoe UI, sans-serif; }
    #|      .meter { min-width: 190px; border-left: 5px solid #a33e2f; padding: 8px 0 6px 18px; }
    #|      .meter small { display: block; color: #69736f; font: 700 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .meter strong { display: block; margin-top: 7px; color: #26322d; font: 700 48px/.9 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      .surface { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(270px, .9fr); border: 1px solid #768079; margin-top: 20px; background: #faf8f2; }
    #|      .preview { position: relative; min-height: 330px; overflow: hidden; border-right: 1px solid #768079; background: #d7ddd8; }
    #|      .preview-band { position: absolute; left: 0; right: 0; height: 33.34%; }
    #|      .preview-band.one { top: 0; background: #c7d5cb; }
    #|      .preview-band.two { top: 33.33%; background: #d7bbb1; }
    #|      .preview-band.three { bottom: 0; background: #d8c894; }
    #|      .sample { position: absolute; inset: 54px 58px; display: grid; place-items: center; border: 2px solid #26322d; background: #f8f6f0; box-shadow: 12px 12px 0 #26322d; text-align: center; }
    #|      .sample span { display: block; color: #a33e2f; font: 750 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .sample strong { display: block; margin-top: 10px; font-size: 25px; }
    #|      .controls { display: grid; align-content: start; gap: 24px; padding: 24px; }
    #|      .control-label { display: flex; justify-content: space-between; gap: 12px; color: #58635e; font: 700 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      input[type="range"] { width: 100%; margin: 14px 0 0; accent-color: #a33e2f; cursor: pointer; }
    #|      .presets { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
    #|      button { min-height: 44px; border: 1px solid #59655f; padding: 0 11px; background: #e8e4da; color: #26322d; cursor: pointer; font: 750 13px/1 Avenir Next, Segoe UI, sans-serif; }
    #|      button:hover { border-color: #26322d; background: #dcd6c9; }
    #|      button:focus-visible, input:focus-visible { outline: 3px solid #a33e2f55; outline-offset: 3px; }
    #|      button.primary { border-color: #873427; background: #a33e2f; color: #fffaf5; }
    #|      button.primary:hover { background: #873427; }
    #|      #status { min-height: 58px; margin: 0; padding-top: 18px; border-top: 1px solid #aab1ac; color: #4a5c53; font: 12px/1.5 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      @media (max-width: 700px) { header { grid-template-columns: 1fr; } .meter { width: 190px; } .surface { grid-template-columns: 1fr; } .preview { border-right: 0; border-bottom: 1px solid #768079; } }
    #|      @media (max-width: 440px) { h1 { font-size: 39px; } .sample { inset: 58px 30px; } .presets { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native frame / manual test 65</p>
    #|          <h1>Window opacity</h1>
    #|          <p class="summary">Adjust the whole native window, including its frame and web contents, against the desktop behind it.</p>
    #|        </div>
    #|        <div class="meter"><small>Native opacity</small><strong id="meter">100%</strong></div>
    #|      </header>
    #|      <section class="surface">
    #|        <div class="preview" aria-hidden="true">
    #|          <div class="preview-band one"></div><div class="preview-band two"></div><div class="preview-band three"></div>
    #|          <div class="sample"><div><span>Reference surface</span><strong>See the desktop through this window</strong></div></div>
    #|        </div>
    #|        <div class="controls">
    #|          <div>
    #|            <div class="control-label"><span>Opacity</span><output id="value">1.00</output></div>
    #|            <input id="opacity" type="range" min="0.35" max="1" step="0.05" value="1" aria-label="Window opacity">
    #|          </div>
    #|          <div class="presets" role="group" aria-label="Opacity presets">
    #|            <button class="primary" data-opacity="1" type="button">100% opaque</button>
    #|            <button data-opacity="0.85" type="button">85% opacity</button>
    #|            <button data-opacity="0.60" type="button">60% opacity</button>
    #|            <button data-opacity="0.35" type="button">35% opacity</button>
    #|          </div>
    #|          <p id="status" role="status" aria-live="polite">Ready. The native window starts fully opaque.</p>
    #|        </div>
    #|      </section>
    #|    </main>
    #|    <script>
    #|      const slider = document.querySelector("#opacity");
    #|      const value = document.querySelector("#value");
    #|      const meter = document.querySelector("#meter");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (opacity) => window.__MoonBit__.core.invokeOp("ext:windowOpacity/set", { opacity });
    #|      function render(opacity, message) {
    #|        slider.value = opacity.toFixed(2);
    #|        value.value = opacity.toFixed(2);
    #|        meter.textContent = `${Math.round(opacity * 100)}%`;
    #|        status.textContent = message;
    #|        document.querySelectorAll("[data-opacity]").forEach((button) => button.classList.toggle("primary", Number(button.dataset.opacity) === opacity));
    #|      }
    #|      async function setOpacity(opacity) {
    #|        status.textContent = "Updating native window opacity...";
    #|        try {
    #|          const reply = await invoke(opacity);
    #|          render(reply.opacity, reply.message);
    #|        } catch (error) {
    #|          status.textContent = `request failed: ${String(error)}`;
    #|        }
    #|      }
    #|      slider.addEventListener("input", () => { value.value = Number(slider.value).toFixed(2); meter.textContent = `${Math.round(Number(slider.value) * 100)}%`; });
    #|      slider.addEventListener("change", () => void setOpacity(Number(slider.value)));
    #|      document.querySelectorAll("[data-opacity]").forEach((button) => button.addEventListener("click", () => void setOpacity(Number(button.dataset.opacity))));
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Opacity", html(), width=880, height=620, debug=true)
  .identifier("dev.proton.window-opacity")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      opacity_state.val = 1.0
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
