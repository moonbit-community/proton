///|
struct Request {
  minimizable : Bool
} derive(ToJson, FromJson)

///|
pub extend Request with ToJson::{to_json}

///|
pub extend Request with FromJson::{from_json}

///|
struct Reply {
  minimizable : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-minimizable",
  js_namespace="windowMinimizable",
)

///|
let command : @proton_contract.Command[Request, Reply] = contract.command("set")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let state : Ref[Bool] = { val: true, }

///|
fn set_minimizable(request : Request) -> Reply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_minimizable(request.minimizable)
        state.val = request.minimizable
        Reply::{
          minimizable: request.minimizable,
          message: if request.minimizable {
            "Minimize control enabled"
          } else {
            "Minimize control disabled"
          },
        }
      } catch {
        error => Reply::{ minimizable: state.val, message: error.to_string(), }
      }
    None => Reply::{ minimizable: state.val, message: "window is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(command, (_context, request) => set_minimizable(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Window Minimizable</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#1b2528;background:#edf2f1}body{margin:0}main{max-width:760px;margin:auto;padding:42px 24px}header{border-bottom:1px solid #718084;padding-bottom:20px}.eyebrow{color:#23766b;font:700 11px ui-monospace,monospace;text-transform:uppercase}h1{margin:0;font-size:42px;letter-spacing:0}.summary{color:#526166;line-height:1.5}.panel{margin-top:22px;border:1px solid #718084;background:#fafcfb;padding:24px}.chrome{border:2px solid #1b2528;background:#dce7e4}.bar{height:38px;display:flex;justify-content:flex-end;align-items:center;border-bottom:1px solid #718084;background:#c5d4d0}.bar span{width:38px;height:38px;display:grid;place-items:center;border-left:1px solid #718084;font-weight:700}.bar span.off{color:#9aa5a3;background:#e7eeec}.screen{min-height:170px;display:grid;place-items:center;color:#23766b;font:700 13px ui-monospace,monospace}button{margin:18px 10px 0 0;padding:12px 16px;border:1px solid #23766b;background:#d7e9e4;color:#1b2528;font-weight:700;cursor:pointer}button.primary{background:#23766b;color:white}#status{min-height:40px;color:#526166;font:12px ui-monospace,monospace;line-height:1.5}</style></head>
    #|<body><main><header><p class="eyebrow">Native frame / manual test 69</p><h1>Window minimizable</h1><p class="summary">Toggle whether the native window can be manually minimized by the user.</p></header><section class="panel"><div class="chrome"><div class="bar"><span>−</span><span class="off" id="minimize">−</span><span>×</span></div><div class="screen">Use the native title bar to review the control</div></div><button class="primary" data-value="true">Enable minimize</button><button data-value="false">Disable minimize</button><p id="status" role="status" aria-live="polite">Ready. The native minimize control is enabled.</p></section></main><script>const button=document.querySelector('#minimize'),status=document.querySelector('#status');const invoke=(minimizable)=>window.__MoonBit__.core.invokeOp('ext:windowMinimizable/set',{minimizable});async function run(value){status.textContent='Updating native window...';try{const reply=await invoke(value);button.classList.toggle('off',!reply.minimizable);status.textContent=reply.message}catch(error){status.textContent='request failed: '+String(error)}}document.querySelectorAll('[data-value]').forEach(b=>b.addEventListener('click',()=>void run(b.dataset.value==='true')))</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Window Minimizable", html(), width=820, height=560, debug=true)
  .identifier("dev.proton.window-minimizable")
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
