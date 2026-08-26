///|
struct SetAttentionRequest {
  flash : Bool
} derive(ToJson, FromJson)

///|
pub extend SetAttentionRequest with ToJson::{to_json}

///|
pub extend SetAttentionRequest with FromJson::{from_json}

///|
struct SetAttentionReply {
  applied : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend SetAttentionReply with ToJson::{to_json}

///|
pub extend SetAttentionReply with FromJson::{from_json}

///|
let attention_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-attention",
  js_namespace="windowAttention",
)

///|
let set_attention_command : @proton_contract.Command[
  SetAttentionRequest,
  SetAttentionReply,
] = attention_contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
fn set_attention(request : SetAttentionRequest) -> SetAttentionReply {
  match window_slot.val {
    Some(window) => {
      window.flash_frame(request.flash) catch {
        error =>
          return SetAttentionReply::{
            applied: false,
            message: "native call failed: " + error.message(),
          }
      }
      SetAttentionReply::{
        applied: true,
        message: if request.flash {
          "attention started"
        } else {
          "attention stopped"
        },
      }
    }
    None =>
      SetAttentionReply::{ applied: false, message: "window is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_attention_command, (_context, request) => {
    set_attention(request)
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
    #|    <title>Window Attention</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101317; color: #f6f7f8; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #101317; }
    #|      button { font: inherit; }
    #|      main { width: min(720px, calc(100vw - 40px)); margin: 0 auto; padding: 48px 0; }
    #|      header { border-bottom: 1px solid #343a42; padding-bottom: 24px; }
    #|      .eyebrow { margin: 0 0 10px; color: #ffb45c; font: 700 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: 42px; line-height: 1.05; }
    #|      .signal { display: grid; grid-template-columns: 104px minmax(0, 1fr); gap: 28px; align-items: center; padding: 42px 0; }
    #|      .countdown { display: grid; place-items: center; width: 104px; aspect-ratio: 1; border: 1px solid #515862; border-radius: 8px; background: #1a1f25; color: #ffbd70; font: 700 36px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .state { min-width: 0; }
    #|      .state strong { display: block; margin-bottom: 8px; font-size: 18px; }
    #|      #status { min-height: 48px; margin: 0; color: #aeb6c0; font: 13px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .commands { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; border-top: 1px solid #343a42; padding-top: 24px; }
    #|      button { min-height: 46px; border: 1px solid #515862; border-radius: 6px; padding: 0 14px; background: #222830; color: #f6f7f8; cursor: pointer; }
    #|      button:hover { border-color: #ffb45c; background: #2a313a; }
    #|      button:focus-visible { outline: 3px solid #ffb45c66; outline-offset: 3px; }
    #|      button.primary { border-color: #d9822b; background: #9b4f16; }
    #|      button.primary:hover { background: #b45f1d; }
    #|      button.stop { border-color: #6b7887; background: #28313a; }
    #|      @media (max-width: 600px) { main { padding-top: 28px; } h1 { font-size: 34px; } .signal { grid-template-columns: 1fr; } .commands { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Native surface / manual test 60</p>
    #|        <h1>Window attention</h1>
    #|      </header>
    #|      <section class="signal">
    #|        <output id="countdown" class="countdown">--</output>
    #|        <div class="state">
    #|          <strong id="state">Ready</strong>
    #|          <p id="status" role="status" aria-live="polite">Choose a review mode.</p>
    #|        </div>
    #|      </section>
    #|      <div class="commands">
    #|        <button id="continuous" class="primary" type="button">Start in 3s</button>
    #|        <button id="timed" type="button">Run for 5s</button>
    #|        <button id="stop" class="stop" type="button">Stop</button>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const countdown = document.querySelector("#countdown");
    #|      const state = document.querySelector("#state");
    #|      const status = document.querySelector("#status");
    #|      let countdownTimer = 0;
    #|      let stopTimer = 0;
    #|      const invoke = (flash) => window.__MoonBit__.core.invokeOp("ext:windowAttention/set", { flash });
    #|      function clearTimers() {
    #|        if (countdownTimer) window.clearInterval(countdownTimer);
    #|        if (stopTimer) window.clearTimeout(stopTimer);
    #|        countdownTimer = 0;
    #|        stopTimer = 0;
    #|      }
    #|      async function apply(flash, label) {
    #|        try {
    #|          const reply = await invoke(flash);
    #|          state.textContent = reply.applied ? label : "Failed";
    #|          status.textContent = reply.message;
    #|          return reply.applied;
    #|        } catch (error) {
    #|          state.textContent = "Failed";
    #|          status.textContent = `request failed: ${String(error)}`;
    #|          return false;
    #|        }
    #|      }
    #|      function schedule(timed) {
    #|        clearTimers();
    #|        let remaining = 3;
    #|        countdown.textContent = String(remaining);
    #|        state.textContent = timed ? "Timed attention queued" : "Attention queued";
    #|        status.textContent = "Switch to another application before zero.";
    #|        countdownTimer = window.setInterval(async () => {
    #|          remaining -= 1;
    #|          countdown.textContent = remaining > 0 ? String(remaining) : "ON";
    #|          if (remaining > 0) return;
    #|          window.clearInterval(countdownTimer);
    #|          countdownTimer = 0;
    #|          const applied = await apply(true, timed ? "Attention active for 5s" : "Attention active");
    #|          if (applied && timed) {
    #|            stopTimer = window.setTimeout(async () => {
    #|              stopTimer = 0;
    #|              await apply(false, "Attention stopped");
    #|              countdown.textContent = "--";
    #|            }, 5000);
    #|          }
    #|        }, 1000);
    #|      }
    #|      document.querySelector("#continuous").addEventListener("click", () => schedule(false));
    #|      document.querySelector("#timed").addEventListener("click", () => schedule(true));
    #|      document.querySelector("#stop").addEventListener("click", async () => {
    #|        clearTimers();
    #|        countdown.textContent = "--";
    #|        await apply(false, "Attention stopped");
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Window Attention", html(), width=720, height=520, debug=true)
  .identifier("dev.proton.window-attention")
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
