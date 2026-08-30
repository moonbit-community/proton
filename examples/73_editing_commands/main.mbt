///|
struct EditRequest {
  target : String
  action : String
} derive(ToJson, FromJson)

///|
pub extend EditRequest with ToJson::{to_json}

///|
pub extend EditRequest with FromJson::{from_json}

///|
struct EditReply {
  ok : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend EditReply with ToJson::{to_json}

///|
pub extend EditReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/editing-commands",
  js_namespace="editingReview",
)

///|
let edit_command : @proton_contract.Command[EditRequest, EditReply] = contract.command(
  "edit",
)

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
let view_slot : Ref[@proton.ViewHandle?] = { val: None, }

///|
fn run_browser_edit(
  browser : @proton.BrowserHandle,
  action : String,
) -> Bool raise @proton.WindowSessionError {
  match action {
    "undo" => browser.undo()
    "redo" => browser.redo()
    "cut" => browser.cut()
    "copy" => browser.copy()
    "paste" => browser.paste()
    "paste_and_match_style" => browser.paste_and_match_style()
    "delete" => browser.delete()
    "select_all" => browser.select_all()
    _ => return false
  }
  true
}

///|
fn run_view_edit(
  view : @proton.ViewHandle,
  action : String,
) -> Bool raise @proton.WindowSessionError {
  view.focus()
  match action {
    "undo" => view.undo()
    "redo" => view.redo()
    "cut" => view.cut()
    "copy" => view.copy()
    "paste" => view.paste()
    "paste_and_match_style" => view.paste_and_match_style()
    "delete" => view.delete()
    "select_all" => view.select_all()
    _ => return false
  }
  true
}

///|
fn edit(request : EditRequest) -> EditReply {
  try {
    let known = match request.target {
      "host" =>
        match browser_slot.val {
          Some(browser) => run_browser_edit(browser, request.action)
          None => return { ok: false, message: "host browser is unavailable", }
        }
      "view" =>
        match view_slot.val {
          Some(view) => run_view_edit(view, request.action)
          None => return { ok: false, message: "view is unavailable", }
        }
      _ => return { ok: false, message: "unknown editing target", }
    }
    if known {
      { ok: true, message: request.action + " dispatched", }
    } else {
      { ok: false, message: "unknown editing command", }
    }
  } catch {
    error => { ok: false, message: error.to_string(), }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(edit_command, (_context, request) => edit(request))
}

///|
let view_page =
  #|data:text/html,<html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>View editor</title><style>*{box-sizing:border-box}html{font-family:system-ui,sans-serif;color:rgb(29,36,42);background:rgb(236,240,242)}body{margin:0;min-height:100vh;padding:26px 30px;border-left:1px solid rgb(143,154,160)}.eyebrow{font:700 11px monospace;color:rgb(20,111,90)}h1{margin:6px 0 22px;font-size:27px}.editors{display:grid;grid-template-columns:1fr 1fr;gap:12px}.panel{min-width:0}.panel-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px}.panel-head strong{font-size:13px}button{min-height:28px;padding:0 10px;border:1px solid rgb(111,124,131);border-radius:3px;background:white;color:rgb(29,36,42);font-weight:700;cursor:pointer}textarea,.rich{width:100%;height:300px;border:2px solid rgb(157,167,172);border-radius:3px;background:white;padding:14px;font:15px/1.55 system-ui,sans-serif;outline:none;resize:none}.rich{overflow:auto}.rich strong{color:rgb(171,52,82);font:700 20px Georgia,serif}.rich em{background:rgb(255,229,133);font-style:normal}.rich:focus,textarea:focus{border-color:rgb(20,111,90);box-shadow:0 0 0 3px rgba(20,111,90,.14)}.state{display:grid;grid-template-columns:auto 1fr;gap:5px 12px;margin-top:16px;padding:11px;border:1px solid rgb(157,167,172);background:white;font:12px/1.4 monospace}.state span:nth-child(even){overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:rgb(20,90,108)}.footer{margin-top:12px}</style></head><body><span class='eyebrow'>WEB CONTENTS VIEW TARGET / REVIEW 73</span><h1>Independent editing surface</h1><div class='editors'><section class='panel'><div class='panel-head'><strong>Plain text</strong><button data-focus='plain'>Focus</button></div><textarea id='plain'>View text starts here. Select a phrase, then use the command toolbar on the left.</textarea></section><section class='panel'><div class='panel-head'><strong>Rich text</strong><button data-focus='rich'>Focus</button></div><div id='rich' class='rich' contenteditable='true'><strong>Crimson source</strong><p><em>Highlighted phrase</em> for clipboard style review.</p><p>Paste here with matching style.</p></div></section></div><div class='state'><span>Active</span><span id='active'>none</span><span>Selection</span><span id='selection'>none</span></div><div class='footer'><button id='reset'>Reset view editors</button></div><script>const plain=document.getElementById('plain'),rich=document.getElementById('rich'),active=document.getElementById('active'),selection=document.getElementById('selection');const initialPlain=plain.value,initialRich=rich.innerHTML;function sync(){const element=document.activeElement;active.textContent=element===plain?'plain text':element===rich||rich.contains(element)?'rich text':element?.tagName?.toLowerCase()||'none';let selected='';if(element===plain)selected=plain.value.slice(plain.selectionStart,plain.selectionEnd);else selected=getSelection()?.toString()||'';selection.textContent=selected||'none'}document.querySelectorAll('[data-focus]').forEach(button=>button.onclick=()=>{(button.dataset.focus==='plain'?plain:rich).focus();sync()});document.getElementById('reset').onclick=()=>{plain.value=initialPlain;rich.innerHTML=initialRich;plain.focus();sync()};document.addEventListener('selectionchange',sync);plain.addEventListener('input',sync);rich.addEventListener('input',sync);plain.focus();sync()</script></body></html>

///|
fn host_page() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Editing commands</title>
    #|<style>*{box-sizing:border-box}:root{font-family:system-ui,sans-serif;color:#252e34;background:#e7ecee}body{margin:0;width:520px;min-height:100vh;padding:26px 28px;background:#f5f7f8}.eyebrow{font:700 11px monospace;color:#9a314d}h1{margin:6px 0 14px;font-size:27px}.targets{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-bottom:10px}.targets button.selected{background:#252e34;border-color:#252e34;color:white}.toolbar{display:grid;grid-template-columns:repeat(4,1fr);gap:7px;margin-bottom:18px}button{min-height:36px;border:1px solid #6f7c83;border-radius:3px;background:white;color:#252e34;font-weight:700;cursor:pointer}button.primary{background:#9a314d;border-color:#9a314d;color:white}.editors{display:grid;grid-template-columns:1fr 1fr;gap:12px}.panel{min-width:0}.panel-head{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px}.panel-head strong{font-size:13px}.focus{min-height:28px;padding:0 9px;font-size:11px}textarea,.rich{width:100%;height:190px;border:2px solid #9da7ac;border-radius:3px;background:white;padding:14px;font:15px/1.55 system-ui,sans-serif;outline:none;resize:none}.rich{overflow:auto}.rich strong{color:#146f5a;font:700 20px Georgia,serif}.rich em{background:#ffe585;font-style:normal}.rich:focus,textarea:focus{border-color:#9a314d;box-shadow:0 0 0 3px #9a314d24}.state{display:grid;grid-template-columns:auto 1fr;gap:5px 12px;margin-top:16px;padding:11px;border:1px solid #9da7ac;background:white;font:12px/1.4 monospace}.state span:nth-child(even){overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#315f78}.footer{display:flex;gap:8px;align-items:center;margin-top:12px}.footer button{padding:0 12px}#status{margin:0;font:12px/1.4 monospace;color:#9a314d}</style></head>
    #|<body><span class="eyebrow">COMMAND CONSOLE / REVIEW 73</span><h1>Editing commands</h1><div class="targets"><button class="selected" data-target="host">Host browser</button><button data-target="view">Web contents view</button></div><div class="toolbar"><button data-action="undo">Undo</button><button data-action="redo">Redo</button><button data-action="cut">Cut</button><button data-action="copy">Copy</button><button data-action="paste">Paste</button><button data-action="paste_and_match_style" class="primary">Paste match style</button><button data-action="delete">Delete</button><button data-action="select_all">Select all</button></div><div class="editors"><section class="panel"><div class="panel-head"><strong>Host plain text</strong><button class="focus" data-focus="plain">Focus</button></div><textarea id="plain">Host text starts here. Select a phrase, then run a command.</textarea></section><section class="panel"><div class="panel-head"><strong>Host rich text</strong><button class="focus" data-focus="rich">Focus</button></div><div id="rich" class="rich" contenteditable="true"><strong>Green source</strong><p><em>Highlighted phrase</em> for clipboard style review.</p><p>Paste here with matching style.</p></div></section></div><div class="state"><span>Target</span><span id="target-state">host browser</span><span>Active</span><span id="active">none</span><span>Selection</span><span id="selection">none</span></div><div class="footer"><button id="reset">Reset host editors</button><p id="status">Ready</p></div>
    #|<script>let target='host';const plain=document.querySelector('#plain'),rich=document.querySelector('#rich'),active=document.querySelector('#active'),selection=document.querySelector('#selection'),status=document.querySelector('#status'),targetState=document.querySelector('#target-state');const initialPlain=plain.value,initialRich=rich.innerHTML;function sync(){const element=document.activeElement;active.textContent=element===plain?'plain text':element===rich||rich.contains(element)?'rich text':element?.tagName?.toLowerCase()||'none';let selected='';if(element===plain)selected=plain.value.slice(plain.selectionStart,plain.selectionEnd);else selected=getSelection()?.toString()||'';selection.textContent=selected||'none'}async function run(action){status.textContent=target+': '+action+'...';try{const reply=await window.__MoonBit__.core.invokeOp('ext:editingReview/edit',{target,action});status.textContent=reply.message;setTimeout(sync,30)}catch(error){status.textContent=String(error)}}document.querySelectorAll('[data-action]').forEach(button=>{button.addEventListener('pointerdown',event=>event.preventDefault());button.addEventListener('click',()=>void run(button.dataset.action))});document.querySelectorAll('[data-target]').forEach(button=>button.onclick=()=>{target=button.dataset.target;targetState.textContent=target==='host'?'host browser':'web contents view';document.querySelectorAll('[data-target]').forEach(item=>item.classList.toggle('selected',item===button));status.textContent=targetState.textContent+' selected'});document.querySelectorAll('[data-focus]').forEach(button=>button.onclick=()=>{target='host';document.querySelector('[data-target="host"]').click();(button.dataset.focus==='plain'?plain:rich).focus();sync()});document.querySelector('#reset').onclick=()=>{plain.value=initialPlain;rich.innerHTML=initialRich;plain.focus();sync()};document.addEventListener('selectionchange',sync);plain.addEventListener('input',sync);rich.addEventListener('input',sync);plain.focus();sync()</script></body></html>
  )
}

///|
fn open_review_view(window : @proton.WindowHandle) -> Unit {
  let view = window.add_view(
    "editing",
    @proton.view(view_page, x=520, y=0, width=680, height=760),
  ) catch {
    error => {
      println("add editing view failed: " + error.message())
      return
    }
  }
  view_slot.val = Some(view)
}

///|
async fn main {
  @proton.html(
    "Editing Commands",
    host_page(),
    width=1200,
    height=760,
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
  .identifier("dev.proton.73-editing-commands")
  .run_or_abort()
}
