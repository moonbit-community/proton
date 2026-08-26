///|
struct Request {
  maximizable : Bool
} derive(ToJson, FromJson)

///|
pub extend Request with ToJson::{to_json}

///|
pub extend Request with FromJson::{from_json}

///|
struct Reply {
  maximizable : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-maximizable",
  js_namespace="windowMaximizable",
)

///|
let command : @proton_contract.Command[Request, Reply] = contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let state : Ref[Bool] = { val: true, }

///|
fn set_maximizable(request : Request) -> Reply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_maximizable(request.maximizable)
        state.val = request.maximizable
        Reply::{
          maximizable: request.maximizable,
          message: if request.maximizable {
            "Maximize control enabled"
          } else {
            "Maximize control disabled"
          },
        }
      } catch {
        error => Reply::{ maximizable: state.val, message: error.to_string(), }
      }
    None => Reply::{ maximizable: state.val, message: "window is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(command, (_context, request) => set_maximizable(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Window Maximizable</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#20262b;background:#eef0f3}body{margin:0}main{max-width:780px;margin:auto;padding:42px 24px}header{border-bottom:1px solid #727b85;padding-bottom:20px}.eyebrow{color:#3f659b;font:700 11px ui-monospace,monospace;text-transform:uppercase}h1{margin:0;font-size:42px;letter-spacing:0}.summary{color:#59636c;line-height:1.5}.panel{margin-top:22px;border:1px solid #727b85;background:#fafbfc;padding:24px}.window{border:2px solid #20262b;background:#dce3eb}.bar{height:38px;display:flex;justify-content:flex-end;align-items:center;border-bottom:1px solid #727b85;background:#c8d2dd}.bar span{width:40px;height:38px;display:grid;place-items:center;border-left:1px solid #727b85;font-weight:700}.bar span.off{color:#9da5ad;background:#e8ebef}.screen{min-height:170px;display:grid;place-items:center;color:#3f659b;font:700 13px ui-monospace,monospace}button{margin:18px 10px 0 0;padding:12px 16px;border:1px solid #3f659b;background:#dbe5f2;color:#20262b;font-weight:700;cursor:pointer}button.primary{background:#3f659b;color:white}#status{min-height:40px;color:#59636c;font:12px ui-monospace,monospace;line-height:1.5}</style></head>
    #|<body><main><header><p class="eyebrow">Native frame / manual test 70</p><h1>Window maximizable</h1><p class="summary">Toggle whether the native window can be manually maximized while preserving normal resizing.</p></header><section class="panel"><div class="window"><div class="bar"><span>−</span><span id="maximize">□</span><span>×</span></div><div class="screen">Review the real native maximize control</div></div><button class="primary" data-value="true">Enable maximize</button><button data-value="false">Disable maximize</button><p id="status" role="status" aria-live="polite">Ready. The native maximize control is enabled.</p></section></main><script>const icon=document.querySelector('#maximize'),status=document.querySelector('#status');const invoke=(maximizable)=>window.__MoonBit__.core.invokeOp('ext:windowMaximizable/set',{maximizable});async function run(value){status.textContent='Updating native window...';try{const reply=await invoke(value);icon.classList.toggle('off',!reply.maximizable);status.textContent=reply.message}catch(error){status.textContent='request failed: '+String(error)}}document.querySelectorAll('[data-value]').forEach(button=>button.addEventListener('click',()=>void run(button.dataset.value==='true')))</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Window Maximizable", html(), width=820, height=560, debug=true)
  .identifier("dev.proton.window-maximizable")
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
