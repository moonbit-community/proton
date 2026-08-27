///|
struct Request {
  minimizable : Bool
  maximizable : Bool
  closable : Bool
  focusable : Bool
  fullscreenable : Bool
  has_shadow : Bool
  ignore_mouse_events : Bool
  background_color : String
  kiosk : Bool
  visible_on_all_workspaces : Bool
  enabled : Bool
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
  fullscreenable : Bool
  has_shadow : Bool
  ignore_mouse_events : Bool
  background_color : String
  kiosk : Bool
  visible_on_all_workspaces : Bool
  enabled : Bool
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
let fullscreenable_state : Ref[Bool] = { val: true, }

///|
let has_shadow_state : Ref[Bool] = { val: true, }

///|
let ignore_mouse_events_state : Ref[Bool] = { val: false, }

///|
let background_color_state : Ref[String] = { val: "#dce3eb", }

///|
let kiosk_state : Ref[Bool] = { val: false, }

///|
let visible_on_all_workspaces_state : Ref[Bool] = { val: false, }

///|
let enabled_state : Ref[Bool] = { val: true, }

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
        window.set_fullscreenable(request.fullscreenable)
        fullscreenable_state.val = request.fullscreenable
        window.set_has_shadow(request.has_shadow)
        has_shadow_state.val = request.has_shadow
        window.set_ignore_mouse_events(request.ignore_mouse_events, false)
        ignore_mouse_events_state.val = request.ignore_mouse_events
        window.set_background_color(request.background_color)
        background_color_state.val = request.background_color
        window.set_kiosk(request.kiosk)
        kiosk_state.val = request.kiosk
        window.set_visible_on_all_workspaces(request.visible_on_all_workspaces)
        visible_on_all_workspaces_state.val = request.visible_on_all_workspaces
        window.set_enabled(request.enabled)
        enabled_state.val = request.enabled
        Reply::{
          minimizable: request.minimizable,
          maximizable: request.maximizable,
          closable: request.closable,
          focusable: request.focusable,
          fullscreenable: request.fullscreenable,
          has_shadow: request.has_shadow,
          ignore_mouse_events: request.ignore_mouse_events,
          background_color: request.background_color,
          kiosk: request.kiosk,
          visible_on_all_workspaces: request.visible_on_all_workspaces,
          enabled: request.enabled,
          message: "Native window controls updated",
        }
      } catch {
        error =>
          Reply::{
            minimizable: minimizable_state.val,
            maximizable: maximizable_state.val,
            closable: closable_state.val,
            focusable: focusable_state.val,
            fullscreenable: fullscreenable_state.val,
            has_shadow: has_shadow_state.val,
            ignore_mouse_events: ignore_mouse_events_state.val,
            background_color: background_color_state.val,
            kiosk: kiosk_state.val,
            visible_on_all_workspaces: visible_on_all_workspaces_state.val,
            enabled: enabled_state.val,
            message: error.to_string(),
          }
      }
    None =>
      Reply::{
        minimizable: minimizable_state.val,
        maximizable: maximizable_state.val,
        closable: closable_state.val,
        focusable: focusable_state.val,
        fullscreenable: fullscreenable_state.val,
        has_shadow: has_shadow_state.val,
        ignore_mouse_events: ignore_mouse_events_state.val,
        background_color: background_color_state.val,
        kiosk: kiosk_state.val,
        visible_on_all_workspaces: visible_on_all_workspaces_state.val,
        enabled: enabled_state.val,
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
    #|<body><main><header><p class="eyebrow">Native frame / manual test 69</p><h1>Window controls</h1><p class="summary">Review native frame capabilities and interaction controls. Kiosk includes a timed exit path.</p></header><section class="panel"><div class="window"><div class="bar"><span id="minimize">−</span><span id="maximize">□</span><span id="close">×</span></div><div class="screen">Review the real native title-bar controls</div></div><button class="primary" data-min="true" data-max="true" data-close="true" data-focus="true" data-full="true" data-shadow="true" data-ignore="false" data-color="#dce3eb" data-kiosk="false" data-workspaces="false" data-enabled="true">Enable all</button><button data-min="false" data-max="true" data-close="true" data-focus="true" data-full="true" data-shadow="true" data-ignore="false" data-color="#dce3eb" data-kiosk="false" data-workspaces="false" data-enabled="true">Disable minimize</button><button data-min="true" data-max="true" data-close="true" data-focus="true" data-full="true" data-shadow="true" data-ignore="true" data-color="#203040" data-kiosk="false" data-workspaces="true" data-enabled="false">Interaction test (auto-restore 5s)</button><button data-min="true" data-max="true" data-close="true" data-focus="true" data-full="true" data-shadow="true" data-ignore="false" data-color="#dce3eb" data-kiosk="true" data-workspaces="false" data-enabled="true">Enter kiosk (auto-exit 5s)</button><button data-min="true" data-max="true" data-close="true" data-focus="true" data-full="true" data-shadow="true" data-ignore="false" data-color="#dce3eb" data-kiosk="false" data-workspaces="false" data-enabled="true">Exit kiosk</button><button id="programmatic-close">Programmatic close</button><p id="status" role="status" aria-live="polite">Ready. All native controls are enabled.</p></section></main><script>const min=document.querySelector('#minimize'),max=document.querySelector('#maximize'),close=document.querySelector('#close'),status=document.querySelector('#status');const invoke=(v)=>window.__MoonBit__.core.invokeOp('ext:windowControls/set',v);async function run(button){status.textContent='Updating native window...';const v={minimizable:button.dataset.min==='true',maximizable:button.dataset.max==='true',closable:button.dataset.close==='true',focusable:button.dataset.focus==='true',fullscreenable:button.dataset.full==='true',has_shadow:button.dataset.shadow==='true',ignore_mouse_events:button.dataset.ignore==='true',background_color:button.dataset.color,kiosk:button.dataset.kiosk==='true',visible_on_all_workspaces:button.dataset.workspaces==='true',enabled:button.dataset.enabled==='true'};try{const reply=await invoke(v);min.classList.toggle('off',!reply.minimizable);max.classList.toggle('off',!reply.maximizable);close.classList.toggle('off',!reply.closable);status.textContent=reply.message+(reply.enabled?' Enabled.':' Disabled.')+(reply.kiosk?' Kiosk active.':'')}catch(error){status.textContent='request failed: '+String(error)}if(v.kiosk||!v.enabled||v.ignore_mouse_events){setTimeout(()=>{const exit=document.querySelector('[data-kiosk="false"]');void run(exit)},5000)}}document.querySelectorAll('[data-min]').forEach(button=>button.addEventListener('click',()=>void run(button)));document.querySelector('#programmatic-close').addEventListener('click',()=>void window.__MoonBit__.core.invokeOp('ext:windowControls/close',null))</script></body></html>
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
