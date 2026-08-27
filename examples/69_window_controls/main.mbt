///|
struct Request {
  minimizable : Bool
  maximizable : Bool
  closable : Bool
  focusable : Bool
} derive(ToJson, FromJson)

///|
pub extend Request with ToJson::{to_json}

///|
pub extend Request with FromJson::{from_json}

///|
struct Reply {
  minimizable : Bool
  maximizable : Bool
  closable : Bool
  focusable : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-controls",
  js_namespace="windowControls",
)

///|
let command : @proton_contract.Command[Request, Reply] = contract.command("set")

///|
let close_command : @proton_contract.Command[Unit, Unit] = contract.command(
  "close",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let minimizable_state : Ref[Bool] = { val: true, }

///|
let maximizable_state : Ref[Bool] = { val: true, }

///|
let closable_state : Ref[Bool] = { val: true, }

///|
let focusable_state : Ref[Bool] = { val: true, }

///|
fn set_controls(request : Request) -> Reply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_minimizable(request.minimizable)
        minimizable_state.val = request.minimizable
        window.set_maximizable(request.maximizable)
        maximizable_state.val = request.maximizable
        window.set_closable(request.closable)
        closable_state.val = request.closable
        window.set_focusable(request.focusable)
        focusable_state.val = request.focusable
        Reply::{
          minimizable: request.minimizable,
          maximizable: request.maximizable,
          closable: request.closable,
          focusable: request.focusable,
          message: "Native window controls updated",
        }
      } catch {
        error =>
          Reply::{
            minimizable: minimizable_state.val,
            maximizable: maximizable_state.val,
            closable: closable_state.val,
            focusable: focusable_state.val,
            message: error.to_string(),
          }
      }
    None =>
      Reply::{
        minimizable: minimizable_state.val,
        maximizable: maximizable_state.val,
        closable: closable_state.val,
        focusable: focusable_state.val,
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(command, (_context, request) => set_controls(request))
  registrar.bind(close_command, (_context, _request) => {
    match window_slot.val {
      Some(window) => window.close()
      None => ()
    }
  })
}

///|
fn html() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Window Controls</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#20262b;background:#eef0f3}body{margin:0}main{max-width:780px;margin:auto;padding:42px 24px}header{border-bottom:1px solid #727b85;padding-bottom:20px}.eyebrow{color:#3f659b;font:700 11px ui-monospace,monospace;text-transform:uppercase}h1{margin:0;font-size:42px}.summary{color:#59636c;line-height:1.5}.panel{margin-top:22px;border:1px solid #727b85;background:#fafbfc;padding:24px}.window{border:2px solid #20262b;background:#dce3eb}.bar{height:38px;display:flex;justify-content:flex-end;align-items:center;border-bottom:1px solid #727b85;background:#c8d2dd}.bar span{width:40px;height:38px;display:grid;place-items:center;border-left:1px solid #727b85;font-weight:700}.bar span.off{color:#9da5ad;background:#e8ebef}.screen{min-height:170px;display:grid;place-items:center;color:#3f659b;font:700 13px ui-monospace,monospace}button{margin:18px 10px 0 0;padding:12px 16px;border:1px solid #3f659b;background:#dbe5f2;color:#20262b;font-weight:700;cursor:pointer}button.primary{background:#3f659b;color:white}#status{min-height:40px;color:#59636c;font:12px ui-monospace,monospace;line-height:1.5}</style></head>
    #|<body><main><header><p class="eyebrow">Native frame / manual test 69</p><h1>Window controls</h1><p class="summary">Toggle native minimize, maximize, close, and focus behavior. Programmatic close remains independent.</p></header><section class="panel"><div class="window"><div class="bar"><span id="minimize">−</span><span id="maximize">□</span><span id="close">×</span></div><div class="screen">Review the real native title-bar controls</div></div><button class="primary" data-min="true" data-max="true" data-close="true" data-focus="true">Enable all</button><button data-min="false" data-max="true" data-close="true" data-focus="true">Disable minimize</button><button data-min="true" data-max="false" data-close="true" data-focus="true">Disable maximize</button><button data-min="true" data-max="true" data-close="false" data-focus="true">Disable close</button><button data-min="true" data-max="true" data-close="true" data-focus="false">Disable focus</button><button data-min="false" data-max="false" data-close="false" data-focus="false">Disable all</button><button id="programmatic-close">Programmatic close</button><p id="status" role="status" aria-live="polite">Ready. All native controls are enabled.</p></section></main><script>const min=document.querySelector('#minimize'),max=document.querySelector('#maximize'),close=document.querySelector('#close'),status=document.querySelector('#status');const invoke=(minimizable,maximizable,closable,focusable)=>window.__MoonBit__.core.invokeOp('ext:windowControls/set',{minimizable,maximizable,closable,focusable});async function run(a,b,c,d){status.textContent='Updating native window...';try{const reply=await invoke(a,b,c,d);min.classList.toggle('off',!reply.minimizable);max.classList.toggle('off',!reply.maximizable);close.classList.toggle('off',!reply.closable);status.textContent=reply.message+(reply.focusable?' Focusable.':' Not focusable.')}catch(error){status.textContent='request failed: '+String(error)}}document.querySelectorAll('[data-min]').forEach(button=>button.addEventListener('click',()=>void run(button.dataset.min==='true',button.dataset.max==='true',button.dataset.close==='true',button.dataset.focus==='true')));document.querySelector('#programmatic-close').addEventListener('click',()=>void window.__MoonBit__.core.invokeOp('ext:windowControls/close',null))</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Window Controls", html(), width=820, height=560, debug=true)
  .identifier("dev.proton.window-controls")
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
