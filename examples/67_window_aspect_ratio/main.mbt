///|
struct AspectRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend AspectRequest with ToJson::{to_json}

///|
pub extend AspectRequest with FromJson::{from_json}

///|
struct AspectReply {
  applied : Bool
  ratio : Double
  width : Int
  height : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend AspectReply with ToJson::{to_json}

///|
pub extend AspectReply with FromJson::{from_json}

///|
let aspect_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-aspect-ratio",
  js_namespace="windowAspectRatio",
)

///|
let aspect_command : @proton_contract.Command[AspectRequest, AspectReply] = aspect_contract.command(
  "set",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let ratio_state : Ref[Double] = { val: 0.0, }

///|
fn reply(
  window : @proton.WindowHandle,
  applied : Bool,
  message : String,
) -> AspectReply raise {
  let state = window.state()
  AspectReply::{
    applied,
    ratio: ratio_state.val,
    width: state.width,
    height: state.height,
    message,
  }
}

///|
fn failed_reply(message : String) -> AspectReply {
  AspectReply::{
    applied: false,
    ratio: ratio_state.val,
    width: 0,
    height: 0,
    message,
  }
}

///|
fn set_ratio(request : AspectRequest) -> AspectReply {
  match window_slot.val {
    Some(window) =>
      try {
        match request.action {
          "wide" => {
            window.set_aspect_ratio(16.0 / 9.0)
            ratio_state.val = 16.0 / 9.0
            reply(window, true, "Interactive resize ratio set to 16:9")
          }
          "square" => {
            window.set_aspect_ratio(1.0)
            ratio_state.val = 1.0
            reply(window, true, "Interactive resize ratio set to 1:1")
          }
          "clear" => {
            window.set_aspect_ratio(0.0)
            ratio_state.val = 0.0
            reply(window, true, "Interactive resize ratio cleared")
          }
          "programmatic" => {
            window.set_size(900, 500)
            reply(window, true, "Programmatic set_size(900, 500) applied")
          }
          _ => failed_reply("unknown action")
        }
      } catch {
        error => failed_reply(error.to_string())
      }
    None => failed_reply("window is not ready")
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(aspect_command, (_context, request) => set_ratio(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Aspect Ratio</title>
    #|    <style>
    #|      :root { color-scheme: light; font-family: ui-sans-serif, system-ui, sans-serif; background: #edf1f4; color: #17232d; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #edf1f4; }
    #|      main { width: min(900px, calc(100vw - 36px)); margin: 0 auto; padding: 34px 0 44px; }
    #|      header { display: flex; justify-content: space-between; gap: 24px; align-items: end; padding-bottom: 22px; border-bottom: 1px solid #82909a; }
    #|      .eyebrow { margin: 0 0 9px; color: #16677a; font: 750 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: 44px; line-height: .96; letter-spacing: 0; }
    #|      .summary { max-width: 580px; margin: 14px 0 0; color: #50616c; line-height: 1.5; }
    #|      .ratio { min-width: 145px; border-left: 5px solid #d56b32; padding: 8px 0 7px 16px; }
    #|      .ratio small { display: block; color: #5d6e78; font: 750 10px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .ratio strong { display: block; margin-top: 8px; color: #16677a; font: 750 28px/1 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      .surface { display: grid; grid-template-columns: minmax(0, 1fr) 280px; margin-top: 20px; border: 1px solid #82909a; background: #f8fafb; }
    #|      .preview { min-height: 390px; display: grid; place-items: center; border-right: 1px solid #82909a; background: repeating-linear-gradient(135deg, #e3ebef 0, #e3ebef 12px, #d8e3e8 12px, #d8e3e8 24px); }
    #|      .frame { width: min(72%, 430px); aspect-ratio: 16 / 9; display: grid; place-items: center; border: 3px solid #17232d; background: #ffffffcc; box-shadow: 12px 12px 0 #16677a; text-align: center; }
    #|      .frame span { display: block; color: #d56b32; font: 750 11px/1 ui-monospace, SFMono-Regular, Consolas, monospace; text-transform: uppercase; }
    #|      .frame strong { display: block; margin-top: 9px; font-size: 22px; }
    #|      .controls { display: grid; align-content: start; gap: 12px; padding: 22px; }
    #|      .controls h2 { margin: 0 0 6px; font-size: 16px; }
    #|      button { min-height: 44px; border: 1px solid #63737d; padding: 0 12px; background: #e4ebee; color: #17232d; cursor: pointer; font: 700 13px/1 ui-sans-serif, system-ui, sans-serif; }
    #|      button:hover { border-color: #16677a; background: #d5e5e9; }
    #|      button.primary { border-color: #16677a; background: #16677a; color: #ffffff; }
    #|      button.primary:hover { background: #105466; }
    #|      #status { min-height: 64px; margin: 6px 0 0; padding-top: 15px; border-top: 1px solid #bbc5ca; color: #50616c; font: 12px/1.5 ui-monospace, SFMono-Regular, Consolas, monospace; }
    #|      @media (max-width: 700px) { header { display: block; } .ratio { width: 145px; margin-top: 18px; } .surface { grid-template-columns: 1fr; } .preview { min-height: 280px; border-right: 0; border-bottom: 1px solid #82909a; } }
    #|      @media (max-width: 440px) { h1 { font-size: 37px; } .frame { width: 78%; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div><p class="eyebrow">Native frame / manual test 67</p><h1>Window aspect ratio</h1><p class="summary">Constrain interactive native resizing while keeping programmatic size changes explicit.</p></div>
    #|        <div class="ratio"><small>Active ratio</small><strong id="ratio">freeform</strong></div>
    #|      </header>
    #|      <section class="surface">
    #|        <div class="preview"><div class="frame"><div><span>Resize the native frame</span><strong>Ratio lives outside the page</strong></div></div></div>
    #|        <div class="controls"><h2>Choose a constraint</h2><button class="primary" data-action="wide" type="button">Set 16:9</button><button data-action="square" type="button">Set 1:1 square</button><button data-action="programmatic" type="button">Programmatic 900 x 500</button><button data-action="clear" type="button">Clear ratio</button><p id="status" role="status" aria-live="polite">Ready. Interactive resizing is freeform.</p></div>
    #|      </section>
    #|    </main>
    #|    <script>
    #|      const ratio = document.querySelector("#ratio");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (action) => window.__MoonBit__.core.invokeOp("ext:windowAspectRatio/set", { action });
    #|      async function run(action) { status.textContent = "Updating native window..."; try { const reply = await invoke(action); ratio.textContent = reply.ratio === 0 ? "freeform" : (Math.abs(reply.ratio - 1) < 0.001 ? "1:1" : "16:9"); status.textContent = `${reply.message} / ${reply.width} x ${reply.height}`; } catch (error) { status.textContent = `request failed: ${String(error)}`; } }
    #|      document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => void run(button.dataset.action)));
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Aspect Ratio", html(), width=900, height=620, debug=true)
  .identifier("dev.proton.window-aspect-ratio")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      ratio_state.val = 0.0
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
