///|
struct ProtectionRequest {
  enabled : Bool
} derive(ToJson, FromJson)

///|
pub extend ProtectionRequest with ToJson::{to_json}

///|
pub extend ProtectionRequest with FromJson::{from_json}

///|
struct ProtectionReply {
  enabled : Bool
  width : Int
  height : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend ProtectionReply with ToJson::{to_json}

///|
pub extend ProtectionReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/window-content-protection",
  js_namespace="windowContentProtection",
)

///|
let command : @proton_contract.Command[ProtectionRequest, ProtectionReply] = contract.command(
  "set",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let protection_state : Ref[Bool] = { val: false, }

///|
fn set_protection(request : ProtectionRequest) -> ProtectionReply {
  match window_slot.val {
    Some(window) =>
      try {
        window.set_content_protection(request.enabled)
        protection_state.val = request.enabled
        let state = window.state()
        ProtectionReply::{
          enabled: request.enabled,
          width: state.width,
          height: state.height,
          message: if request.enabled {
            "Capture protection enabled"
          } else {
            "Capture protection disabled"
          },
        }
      } catch {
        error =>
          ProtectionReply::{
            enabled: protection_state.val,
            width: 0,
            height: 0,
            message: error.to_string(),
          }
      }
    None =>
      ProtectionReply::{
        enabled: protection_state.val,
        width: 0,
        height: 0,
        message: "window is not ready",
      }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(command, (_context, request) => set_protection(request))
}

///|
fn html() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Window Content Protection</title>
    #|<style>body{margin:0;background:#eef2f1;color:#172522;font:16px system-ui,sans-serif}main{max-width:760px;margin:0 auto;padding:42px 24px}header{border-bottom:1px solid #70827c;padding-bottom:22px}h1{margin:0;font-size:40px;letter-spacing:0}.eyebrow{color:#1d7463;font:700 11px ui-monospace,monospace;text-transform:uppercase}.summary{color:#52645f;line-height:1.5}.panel{margin-top:24px;border:1px solid #70827c;background:#f9fbfa;padding:24px}.shield{min-height:180px;display:grid;place-items:center;border:3px solid #172522;background:repeating-linear-gradient(135deg,#d8e8e3 0,#d8e8e3 14px,#c9ddd6 14px,#c9ddd6 28px);text-align:center}.shield strong{display:block;font-size:24px}.shield span{display:block;margin-top:8px;color:#1d7463;font:700 11px ui-monospace,monospace;text-transform:uppercase}button{margin:18px 10px 0 0;padding:12px 16px;border:1px solid #1d7463;background:#dcebe6;color:#172522;font-weight:700;cursor:pointer}button.primary{background:#1d7463;color:white}#status{min-height:42px;margin-top:20px;color:#52645f;font:12px ui-monospace,monospace;line-height:1.5}</style></head>
    #|<body><main><header><p class="eyebrow">Native frame / manual test 68</p><h1>Window content protection</h1><p class="summary">Toggle the native capture-protection flag and inspect the result with a screen capture tool.</p></header><section class="panel"><div class="shield"><div><span id="label">Capture allowed</span><strong id="state">Unprotected</strong></div></div><button class="primary" data-enabled="true">Enable protection</button><button data-enabled="false">Disable protection</button><p id="status" role="status" aria-live="polite">Ready.</p></section></main><script>const state=document.querySelector('#state'),label=document.querySelector('#label'),status=document.querySelector('#status');const invoke=(enabled)=>window.__MoonBit__.core.invokeOp('ext:windowContentProtection/set',{enabled});async function run(enabled){status.textContent='Updating native window...';try{const reply=await invoke(enabled);state.textContent=reply.enabled?'Protected':'Unprotected';label.textContent=reply.enabled?'Capture blocked':'Capture allowed';status.textContent=`${reply.message} / ${reply.width} x ${reply.height}`}catch(error){status.textContent=`request failed: ${String(error)}`}}document.querySelectorAll('[data-enabled]').forEach(button=>button.addEventListener('click',()=>void run(button.dataset.enabled==='true')))</script></body></html>
  )
}

///|
async fn main {
  @proton.html(
    "Window Content Protection",
    html(),
    width=820,
    height=560,
    debug=true,
  )
  .identifier("dev.proton.window-content-protection")
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
