///|
struct ControlRequest {
  target : String
  action : String
} derive(ToJson, FromJson)

///|
pub extend ControlRequest with ToJson::{to_json}

///|
pub extend ControlRequest with FromJson::{from_json}

///|
struct ControlReply {
  ok : Bool
  message : String
  host_focused : Bool
  host_devtools_opened : Bool
  view_focused : Bool
  view_devtools_opened : Bool
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/devtools-focus",
  js_namespace="devtoolsReview",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
let view_slot : Ref[@proton.ViewHandle?] = { val: None, }

///|
fn read_state(message : String, ok? : Bool = true) -> ControlReply {
  let (host_focused, host_devtools_opened) = match browser_slot.val {
    Some(browser) =>
      (
        browser.is_focused() catch {
          _ => false
        },
        browser.is_devtools_opened() catch {
          _ => false
        },
      )
    None => (false, false)
  }
  let (view_focused, view_devtools_opened) = match view_slot.val {
    Some(view) =>
      (
        view.is_focused() catch {
          _ => false
        },
        view.is_devtools_opened() catch {
          _ => false
        },
      )
    None => (false, false)
  }
  {
    ok,
    message,
    host_focused,
    host_devtools_opened,
    view_focused,
    view_devtools_opened,
  }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  if request.action == "refresh" {
    return read_state("State refreshed")
  }
  try {
    match request.target {
      "host" =>
        match browser_slot.val {
          Some(browser) =>
            match request.action {
              "focus" => browser.focus()
              "open" => browser.open_devtools()
              "close" => browser.close_devtools()
              "toggle" => browser.toggle_devtools()
              _ => return read_state("Unknown action", ok=false)
            }
          None => return read_state("Host browser is unavailable", ok=false)
        }
      "view" =>
        match view_slot.val {
          Some(view) =>
            match request.action {
              "focus" => view.focus()
              "open" => view.open_devtools()
              "close" => view.close_devtools()
              "toggle" => view.toggle_devtools()
              _ => return read_state("Unknown action", ok=false)
            }
          None =>
            return read_state("Web contents view is unavailable", ok=false)
        }
      _ => return read_state("Unknown target", ok=false)
    }
    read_state("{request.target}: {request.action}")
  } catch {
    error => read_state(error.to_string(), ok=false)
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(control_command, (_context, request) => control(request))
}

///|
let view_page =
  #|data:text/html,<html><head><meta charset='utf-8'><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;padding:48px;font-family:system-ui,sans-serif;background:%23f1f4f6;color:%231b242a;border:8px solid transparent;transition:border-color .15s}body.focused{border-color:%231f7a68}.eyebrow{font:700 11px monospace;color:%231f7a68}.badge{display:inline-block;padding:5px 8px;border:1px solid %2393a1a8;font:700 11px monospace}h1{font-size:38px;line-height:1.05;margin:16px 0}p{max-width:580px;line-height:1.6;color:%234c5b63}input{width:min(100%25,480px);height:44px;border:1px solid %2379848a;background:white;padding:0 12px;font-size:15px}</style></head><body><span class='eyebrow'>WEB CONTENTS VIEW / REVIEW 54</span><h1>Independent focus target</h1><span id='badge' class='badge'>window blur</span><p>Use the host controls to focus this view and open its own DevTools window. The green border and badge follow page focus events.</p><input placeholder='Type here after focusing the view'><script>const badge=document.querySelector('%23badge');function sync(){const focused=document.hasFocus();document.body.classList.toggle('focused',focused);badge.textContent=focused?'window focus':'window blur'}addEventListener('focus',sync);addEventListener('blur',sync);sync()</script></body></html>

///|
fn open_review_view(window : @proton.WindowHandle) -> Unit {
  let view = window.add_view(
    "review",
    @proton.view(view_page, x=400, y=0, width=700, height=700),
  ) catch {
    error => {
      println("add review view failed: " + error.message())
      return
    }
  }
  view_slot.val = Some(view)
}

///|
fn host_page() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Proton DevTools and Focus</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#192329;background:#e3e8ea}*{box-sizing:border-box}body{margin:0;width:400px;min-height:100vh;padding:28px;border-right:1px solid #8b989e;transition:box-shadow .15s}body.focused{box-shadow:inset 6px 0 #ba3d57}.eyebrow{font:700 11px monospace;color:#8f2941}h1{font-size:29px;line-height:1.08;margin:8px 0 12px}.copy{font-size:14px;line-height:1.55;color:#4d5b62}.page-focus{display:inline-block;padding:5px 8px;border:1px solid #8b989e;font:700 11px monospace}.target{margin-top:20px;padding-top:18px;border-top:1px solid #9ba6ab}.target h2{font-size:15px;margin:0 0 10px}.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}button{height:38px;border:1px solid #6f7d84;background:#f8fafb;color:#192329;font-weight:700;cursor:pointer}button.primary{background:#275c70;color:white;border-color:#275c70}.state{display:grid;grid-template-columns:1fr auto;gap:5px 12px;margin-top:18px;padding:12px;background:#f8fafb;border:1px solid #9ba6ab;font:12px/1.4 monospace}.value.true{color:#146b57;font-weight:700}.value.false{color:#8f2941;font-weight:700}#status{min-height:36px;font:12px/1.45 monospace;color:#275c70}.refresh{width:100%;margin-top:10px}</style></head>
    #|<body><span class="eyebrow">ELECTRON WEB CONTENTS / REVIEW 54</span><h1>Focus and DevTools</h1><span id="page-focus" class="page-focus">host window focus</span><p class="copy">Control the host browser and the independent view on the right. Each target owns its own DevTools state.</p><section class="target"><h2>Host browser</h2><div class="actions"><button data-target="host" data-action="focus">Focus page</button><button class="primary" data-target="host" data-action="toggle">Toggle DevTools</button><button data-target="host" data-action="open">Open DevTools</button><button data-target="host" data-action="close">Close DevTools</button></div></section><section class="target"><h2>Web contents view</h2><div class="actions"><button data-target="view" data-action="focus">Focus view</button><button class="primary" data-target="view" data-action="toggle">Toggle DevTools</button><button data-target="view" data-action="open">Open DevTools</button><button data-target="view" data-action="close">Close DevTools</button></div></section><div class="state"><span>Host focused</span><span id="host-focused" class="value">-</span><span>Host DevTools</span><span id="host-devtools" class="value">-</span><span>View focused</span><span id="view-focused" class="value">-</span><span>View DevTools</span><span id="view-devtools" class="value">-</span></div><button id="refresh" class="refresh">Refresh state</button><p id="status" role="status">Ready</p>
    #|<script>const status=document.querySelector('#status');function paint(id,value){const node=document.querySelector(id);node.textContent=String(value);node.className=`value ${value}`}function apply(reply){paint('#host-focused',reply.host_focused);paint('#host-devtools',reply.host_devtools_opened);paint('#view-focused',reply.view_focused);paint('#view-devtools',reply.view_devtools_opened);status.textContent=reply.message}async function run(target,action){status.textContent=`${target}: ${action}...`;try{apply(await window.__MoonBit__.core.invokeOp('ext:devtoolsReview/control',{target,action}));if(action!=='refresh')setTimeout(()=>void run(target,'refresh'),250)}catch(error){status.textContent=String(error)}}document.querySelectorAll('[data-action]').forEach(button=>button.onclick=()=>void run(button.dataset.target,button.dataset.action));document.querySelector('#refresh').onclick=()=>void run('host','refresh');const focusBadge=document.querySelector('#page-focus');function focusState(){const focused=document.hasFocus();document.body.classList.toggle('focused',focused);focusBadge.textContent=focused?'host window focus':'host window blur'}addEventListener('focus',focusState);addEventListener('blur',focusState);focusState();void run('host','refresh')</script></body></html>
  )
}

///|
async fn main {
  @proton.html(
    "DevTools and Focus",
    host_page(),
    width=1100,
    height=700,
    debug=true,
  )
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      browser_slot.val = Some(window.browser())
      open_review_view(window)
      window
    },
    on_close=fn(_window) {
      view_slot.val = None
      browser_slot.val = None
    },
  )
  .identifier("dev.proton.54-devtools-focus")
  .run_or_abort()
}
