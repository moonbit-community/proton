///|
struct SetLimitRequest {
  kind : String
  width : Int
  height : Int
} derive(ToJson, FromJson)

///|
pub extend SetLimitRequest with ToJson::{to_json}

///|
pub extend SetLimitRequest with FromJson::{from_json}

///|
struct SetLimitReply {
  applied : Bool
  minimum : String
  maximum : String
  message : String
} derive(ToJson, FromJson)

///|
pub extend SetLimitReply with ToJson::{to_json}

///|
pub extend SetLimitReply with FromJson::{from_json}

///|
let limits_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-size-limits",
  js_namespace="windowSizeLimits",
)

///|
let set_limit_command : @proton_contract.Command[SetLimitRequest, SetLimitReply] = limits_contract.command(
  "set",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let minimum_limit : Ref[(Int, Int)] = { val: (0, 0), }

///|
let maximum_limit : Ref[(Int, Int)] = { val: (0, 0), }

///|
fn format_limit(limit : (Int, Int)) -> String {
  let (width, height) = limit
  if width == 0 && height == 0 {
    "none"
  } else {
    width.to_string() + " x " + height.to_string()
  }
}

///|
fn set_limit(request : SetLimitRequest) -> SetLimitReply {
  match window_slot.val {
    Some(window) => {
      if request.kind != "minimum" && request.kind != "maximum" {
        return SetLimitReply::{
          applied: false,
          minimum: format_limit(minimum_limit.val),
          maximum: format_limit(maximum_limit.val),
          message: "kind must be minimum or maximum",
        }
      }
      try {
        match request.kind {
          "minimum" => {
            window.set_minimum_size(request.width, request.height)
            minimum_limit.val = (request.width, request.height)
          }
          "maximum" => {
            window.set_maximum_size(request.width, request.height)
            maximum_limit.val = (request.width, request.height)
          }
          _ => ()
        }
        SetLimitReply::{
          applied: true,
          minimum: format_limit(minimum_limit.val),
          maximum: format_limit(maximum_limit.val),
          message: request.kind + " constraint updated",
        }
      } catch {
        error =>
          SetLimitReply::{
            applied: false,
            minimum: format_limit(minimum_limit.val),
            maximum: format_limit(maximum_limit.val),
            message: error.message(),
          }
      }
    }
    None =>
      SetLimitReply::{
        applied: false,
        minimum: format_limit(minimum_limit.val),
        maximum: format_limit(maximum_limit.val),
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_limit_command, (_context, request) => set_limit(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Window Size Limits</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #11100f; color: #f3eee8; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #11100f; }
    #|      button { font: inherit; }
    #|      main { width: min(850px, calc(100vw - 40px)); margin: 0 auto; padding: 42px 0 50px; }
    #|      header { padding-bottom: 24px; border-bottom: 1px solid #403930; }
    #|      .eyebrow { margin: 0 0 10px; color: #e7ad64; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; max-width: 620px; font-size: clamp(34px, 6vw, 54px); line-height: .98; letter-spacing: -.055em; }
    #|      .summary { max-width: 620px; margin: 14px 0 0; color: #b5a99d; line-height: 1.55; }
    #|      .limits { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 13px; margin-top: 20px; }
    #|      .limit { border: 1px solid #594b3f; border-radius: 10px; padding: 17px; background: #1a1714; }
    #|      .limit small { display: block; color: #ae9a87; font: 700 10px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .12em; text-transform: uppercase; }
    #|      .limit strong { display: block; margin-top: 9px; color: #ffe2b5; font: 700 24px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(260px, .8fr); gap: 16px; margin-top: 16px; }
    #|      .panel { border: 1px solid #403930; border-radius: 14px; background: #171411; overflow: hidden; }
    #|      .panel-head { display: flex; justify-content: space-between; gap: 12px; min-height: 48px; padding: 0 17px; align-items: center; border-bottom: 1px solid #403930; color: #b5a99d; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; }
    #|      .surface { min-height: 250px; padding: 27px; background: radial-gradient(circle at 70% 25%, #54351d 0, #2c2118 37%, #171411 76%); }
    #|      .surface h2 { margin: 0 0 9px; font-size: 23px; letter-spacing: -.03em; }
    #|      .surface p { max-width: 410px; margin: 0; color: #c6b8aa; line-height: 1.6; }
    #|      .controls { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 9px; padding: 15px 17px; border-top: 1px solid #403930; }
    #|      button { min-height: 43px; border: 1px solid #6b5745; border-radius: 8px; padding: 0 12px; background: #282019; color: #f5eadf; cursor: pointer; font-weight: 720; }
    #|      button:hover { border-color: #e7ad64; background: #372719; }
    #|      button:focus-visible { outline: 3px solid #e7ad6466; outline-offset: 3px; }
    #|      button.primary { border-color: #b97b37; background: #794b1e; }
    #|      button.primary:hover { background: #95602a; }
    #|      .review { padding: 20px; }
    #|      .review h2 { margin: 0 0 14px; font-size: 16px; }
    #|      .checklist { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    #|      .checklist li { position: relative; padding-left: 25px; color: #c6b8aa; font-size: 13px; line-height: 1.5; }
    #|      .checklist li::before { content: ""; position: absolute; left: 1px; top: 5px; width: 10px; height: 10px; border: 1px solid #d19350; border-radius: 3px; }
    #|      #status { min-height: 35px; margin: 18px 0 0; color: #e7ad64; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      @media (max-width: 720px) { .layout { grid-template-columns: 1fr; } }
    #|      @media (max-width: 480px) { main { padding-top: 28px; } .limits, .controls { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Native surface / manual test 62</p>
    #|        <h1>Window size limits</h1>
    #|        <p class="summary">Set live minimum and maximum bounds, resize against each edge, then clear both constraints without restarting the native window.</p>
    #|      </header>
    #|      <section class="limits">
    #|        <div class="limit"><small>Minimum size</small><strong id="minimum">none</strong></div>
    #|        <div class="limit"><small>Maximum size</small><strong id="maximum">none</strong></div>
    #|      </section>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>Window frame</strong><span>drag any edge</span></div>
    #|          <div class="surface"><h2>Constraints live outside the page</h2><p>The buttons below update the native frame. The renderer only mirrors the values returned by the typed command.</p></div>
    #|          <div class="controls">
    #|            <button id="min" class="primary" type="button">Minimum 480 x 360</button>
    #|            <button id="clear-min" type="button">Clear minimum</button>
    #|            <button id="max" class="primary" type="button">Maximum 1100 x 760</button>
    #|            <button id="clear-max" type="button">Clear maximum</button>
    #|          </div>
    #|        </section>
    #|        <aside class="panel review">
    #|          <h2>Manual review</h2>
    #|          <ul class="checklist">
    #|            <li>Set the minimum, then drag the lower-left corner smaller. The window should stop at 480 x 360.</li>
    #|            <li>Set the maximum, then drag the upper-right corner larger. The window should stop at 1100 x 760.</li>
    #|            <li>Clear each constraint independently and confirm the other one remains active.</li>
    #|            <li>On Windows above 100% display scaling, confirm the native frame obeys the same bounds.</li>
    #|            <li>On Linux, the exact resize affordance depends on the desktop window manager.</li>
    #|          </ul>
    #|          <p id="status" role="status" aria-live="polite">Ready. No live size constraints are set.</p>
    #|        </aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const minimum = document.querySelector("#minimum");
    #|      const maximum = document.querySelector("#maximum");
    #|      const status = document.querySelector("#status");
    #|      const invoke = (kind, width, height) => window.__MoonBit__.core.invokeOp("ext:windowSizeLimits/set", { kind, width, height });
    #|      function render(reply) {
    #|        minimum.textContent = reply.minimum;
    #|        maximum.textContent = reply.maximum;
    #|        status.textContent = reply.message;
    #|      }
    #|      async function setLimit(kind, width, height) {
    #|        status.textContent = `Updating ${kind} constraint...`;
    #|        try { render(await invoke(kind, width, height)); }
    #|        catch (error) { status.textContent = `request failed: ${String(error)}`; }
    #|      }
    #|      document.querySelector("#min").addEventListener("click", () => void setLimit("minimum", 480, 360));
    #|      document.querySelector("#clear-min").addEventListener("click", () => void setLimit("minimum", 0, 0));
    #|      document.querySelector("#max").addEventListener("click", () => void setLimit("maximum", 1100, 760));
    #|      document.querySelector("#clear-max").addEventListener("click", () => void setLimit("maximum", 0, 0));
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Size Limits", html(), width=850, height=640, debug=true)
  .identifier("dev.proton.window-size-limits")
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
