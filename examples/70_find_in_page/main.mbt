///|
struct FindRequest {
  target : String
  text : String
  forward : Bool
  match_case : Bool
  find_next : Bool
} derive(ToJson, FromJson)

///|
pub extend FindRequest with ToJson::{to_json}

///|
pub extend FindRequest with FromJson::{from_json}

///|
struct StopRequest {
  target : String
  clear_selection : Bool
} derive(ToJson, FromJson)

///|
pub extend StopRequest with ToJson::{to_json}

///|
pub extend StopRequest with FromJson::{from_json}

///|
struct Reply {
  ok : Bool
  request_id : Int
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/find-in-page",
  js_namespace="findReview",
)

///|
let find_command : @proton_contract.Command[FindRequest, Reply] = contract.command(
  "find",
)

///|
let stop_command : @proton_contract.Command[StopRequest, Reply] = contract.command(
  "stop",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let view_slot : Ref[@proton.ViewHandle?] = { val: None, }

///|
fn target_find(request : FindRequest) -> Reply {
  try {
    let request_id = match request.target {
      "host" =>
        match window_slot.val {
          Some(window) =>
            window
            .browser()
            .find_in_page(
              request.text,
              forward=request.forward,
              match_case=request.match_case,
              find_next=request.find_next,
            )
          None =>
            return { ok: false, request_id: 0, message: "host unavailable", }
        }
      "view" =>
        match view_slot.val {
          Some(view) =>
            view.find_in_page(
              request.text,
              forward=request.forward,
              match_case=request.match_case,
              find_next=request.find_next,
            )
          None =>
            return { ok: false, request_id: 0, message: "view unavailable", }
        }
      _ => return { ok: false, request_id: 0, message: "unknown target", }
    }
    { ok: true, request_id, message: "find request started", }
  } catch {
    error => { ok: false, request_id: 0, message: error.to_string(), }
  }
}

///|
fn target_stop(request : StopRequest) -> Reply {
  try {
    match request.target {
      "host" =>
        match window_slot.val {
          Some(window) =>
            window
            .browser()
            .stop_find_in_page(clear_selection=request.clear_selection)
          None =>
            return { ok: false, request_id: 0, message: "host unavailable", }
        }
      "view" =>
        match view_slot.val {
          Some(view) =>
            view.stop_find_in_page(clear_selection=request.clear_selection)
          None =>
            return { ok: false, request_id: 0, message: "view unavailable", }
        }
      _ => return { ok: false, request_id: 0, message: "unknown target", }
    }
    {
      ok: true,
      request_id: 0,
      message: if request.clear_selection {
        "find stopped and selection cleared"
      } else {
        "find stopped and selection preserved"
      },
    }
  } catch {
    error => { ok: false, request_id: 0, message: error.to_string(), }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(find_command, (_context, request) => target_find(request))
  registrar.bind(stop_command, (_context, request) => target_stop(request))
}

///|
fn js_escape(text : String) -> String {
  text.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
fn show_result(target : String, result : @proton.FindInPageResult) -> Unit {
  match window_slot.val {
    Some(window) => {
      let message = target +
        " request=" +
        result.request_id.to_string() +
        " match=" +
        result.active_match_ordinal.to_string() +
        "/" +
        result.matches.to_string() +
        " rect=" +
        result.selection_x.to_string() +
        "," +
        result.selection_y.to_string() +
        " " +
        result.selection_width.to_string() +
        "x" +
        result.selection_height.to_string() +
        (if result.final_update { " final" } else { " updating" })
      window
      .browser()
      .eval(
        "document.querySelector(\"#status\").textContent = \"\{js_escape(message)}\";",
      ) catch {
        _ => ()
      }
    }
    None => ()
  }
}

///|
let view_url =
  #|data:text/html,<body style='font-family:system-ui,sans-serif;margin:0;padding:48px;background:%23f4f6f8;color:%2320282f'><p style='font:700 12px monospace;color:%23406a83'>WEB CONTENTS VIEW</p><h1>Find Proton in this view</h1><p>Proton keeps browser controls close to MoonBit.</p><p>Searching Proton highlights every matching word in this independent page.</p><p>The lowercase word proton is useful for reviewing case-sensitive search.</p><p>Proton Proton Proton</p></body>

///|
fn page() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Find in page</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#20282f;background:#e7ecef}*{box-sizing:border-box}body{margin:0;width:360px;min-height:100vh;padding:30px;border-right:1px solid #8c989f}h1{font-size:28px;margin:4px 0 12px}.eyebrow{font:700 11px monospace;color:#406a83}.copy{line-height:1.55;color:#4b5961}.controls{display:grid;gap:10px;margin-top:24px}input,select,button{height:40px;border:1px solid #738088;background:#f8fafb;color:#20282f;padding:0 12px}button{cursor:pointer;font-weight:700}button.primary{background:#315f78;color:white}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.check{display:flex;align-items:center;gap:8px;font-size:13px}.check input{width:16px;height:16px}#status{min-height:42px;font:12px/1.5 monospace;color:#315f78}</style></head>
    #|<body><p class="eyebrow">ELECTRON WEB CONTENTS / REVIEW 70</p><h1>Find in page</h1><p class="copy">Search Proton in this host page or the independent web contents view. Proton appears here several times; lowercase proton verifies case matching.</p><div class="controls"><select id="target"><option value="host">Host browser</option><option value="view">Web contents view</option></select><input id="text" value="Proton" aria-label="Search text"><label class="check"><input id="case" type="checkbox"> Match case</label><button class="primary" id="first">Find</button><div class="row"><button id="previous">Previous</button><button id="next">Next</button></div><div class="row"><button id="keep">Stop and keep</button><button id="clear">Stop and clear</button></div><p id="status" role="status">Ready</p></div>
    #|<script>const status=document.querySelector('#status');const payload=(forward,find_next)=>({target:document.querySelector('#target').value,text:document.querySelector('#text').value,forward,match_case:document.querySelector('#case').checked,find_next});async function find(forward,find_next){try{const reply=await window.__MoonBit__.core.invokeOp('ext:findReview/find',payload(forward,find_next));status.textContent=reply.ok?`request ${reply.request_id} started`:reply.message}catch(error){status.textContent=String(error)}}async function stop(clear_selection){try{const reply=await window.__MoonBit__.core.invokeOp('ext:findReview/stop',{target:document.querySelector('#target').value,clear_selection});status.textContent=reply.message}catch(error){status.textContent=String(error)}}document.querySelector('#first').onclick=()=>void find(true,true);document.querySelector('#previous').onclick=()=>void find(false,false);document.querySelector('#next').onclick=()=>void find(true,false);document.querySelector('#keep').onclick=()=>void stop(false);document.querySelector('#clear').onclick=()=>void stop(true);document.querySelector('#text').onkeydown=event=>{if(event.key==='Enter')void find(true,true)}</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Find In Page", page(), width=1100, height=700, debug=true)
  .with_view(
    "content",
    @proton.view(view_url, x=360, y=0, width=740, height=700),
  )
  .commands(register_commands)
  .on_browser_event(async fn(_browser, event) noraise {
    if event is @proton.BrowserEvent::FoundInPage(result~) {
      show_result("host", result)
    }
  })
  .on_view_event(async fn(_view, event) noraise {
    if event is @proton.ViewEvent::FoundInPage(result~) {
      show_result("view", result)
    }
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      view_slot.val = window.view("content")
      window
    },
    on_close=fn(_window) {
      view_slot.val = None
      window_slot.val = None
    },
  )
  .identifier("dev.proton.70-find-in-page")
  .run_or_abort()
}
