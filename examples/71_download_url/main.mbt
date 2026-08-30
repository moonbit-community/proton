///|
struct StartRequest {
  url : String
  show_dialog : Bool
} derive(ToJson, FromJson)

///|
pub extend StartRequest with ToJson::{to_json}

///|
pub extend StartRequest with FromJson::{from_json}

///|
struct Reply {
  ok : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend Reply with ToJson::{to_json}

///|
pub extend Reply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/download-url",
  js_namespace="downloadReview",
)

///|
let start_command : @proton_contract.Command[StartRequest, Reply] = contract.command(
  "start",
)

///|
let cancel_command : @proton_contract.Command[Unit, Reply] = contract.command(
  "cancel",
)

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
let last_download_id : Ref[Int?] = { val: None, }

///|
let show_dialog : Ref[Bool] = { val: false, }

///|
fn temporary_directory() -> String {
  let variable = if @path.sep == '\\' { "TEMP" } else { "TMPDIR" }
  @env.get_env_var(variable).unwrap_or_else(() => {
    if @path.sep == '\\' {
      @env.current_dir().unwrap_or(".")
    } else {
      "/tmp"
    }
  })
}

///|
let automatic_download_path : String = {
  let directory = temporary_directory()
  if directory.has_suffix(@path.sep.to_string()) {
    directory + "proton-programmatic-download.txt"
  } else {
    directory + @path.sep.to_string() + "proton-programmatic-download.txt"
  }
}

///|
fn js_escape(text : String) -> String {
  text
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
}

///|
fn show_status(message : String) -> Unit {
  match browser_slot.val {
    Some(browser) =>
      browser.eval(
        "document.querySelector(\"#status\").dataset.nativeUpdate = \"true\"; document.querySelector(\"#status\").textContent = \"\{js_escape(message)}\";",
      ) catch {
        _ => ()
      }
    None => ()
  }
}

///|
fn start_download(request : StartRequest) -> Reply {
  match browser_slot.val {
    Some(browser) => {
      show_dialog.val = request.show_dialog
      try {
        browser.download_url(request.url)
        {
          ok: true,
          message: "Programmatic download requested; waiting for approval event",
        }
      } catch {
        error => { ok: false, message: error.to_string(), }
      }
    }
    None => { ok: false, message: "browser is not ready", }
  }
}

///|
fn cancel_download() -> Reply {
  match (browser_slot.val, last_download_id.val) {
    (Some(browser), Some(download_id)) =>
      try {
        browser.cancel_download(download_id)
        {
          ok: true,
          message: "Cancellation requested for download \{download_id}",
        }
      } catch {
        error => { ok: false, message: error.to_string(), }
      }
    (_, None) => { ok: false, message: "no download is available to cancel", }
    (None, _) => { ok: false, message: "browser is not ready", }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(start_command, (_context, request) => start_download(request))
  registrar.bind(cancel_command, (_context, _request) => cancel_download())
}

///|
fn page() -> String {
  (
    #|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Programmatic download</title>
    #|<style>:root{font-family:system-ui,sans-serif;color:#20282f;background:#e7ecef}*{box-sizing:border-box}body{margin:0}main{max-width:780px;margin:auto;padding:46px 24px}.eyebrow{font:700 11px ui-monospace,monospace;color:#315f78}h1{font-size:38px;margin:6px 0 12px}.summary{color:#4b5961;line-height:1.55}.panel{margin-top:26px;border:1px solid #7d8990;background:#f8fafb;padding:24px}.field{display:grid;gap:7px;margin-bottom:18px}label,legend{font-size:13px;font-weight:700}input[type=text]{width:100%;height:42px;border:1px solid #738088;background:white;padding:0 12px;color:#20282f}.choice{display:flex;gap:22px;border:0;padding:0;margin:0 0 18px}.choice label{font-weight:500}.actions{display:flex;gap:10px;flex-wrap:wrap}button{height:42px;border:1px solid #315f78;background:#edf2f5;color:#20282f;padding:0 16px;font-weight:700;cursor:pointer}button.primary{background:#315f78;color:white}#status{min-height:58px;margin:22px 0 0;padding-top:18px;border-top:1px solid #c4ccd1;color:#315f78;font:12px/1.55 ui-monospace,monospace;white-space:pre-wrap}</style></head>
    #|<body><main><p class="eyebrow">ELECTRON WEB CONTENTS / REVIEW 71</p><h1>Programmatic download</h1><p class="summary">Start a download from MoonBit without navigating this page. Review request approval, destination selection, progress, completion, and cancellation.</p><section class="panel"><div class="field"><label for="url">Download URL</label><input id="url" type="text" value="data:text/plain;charset=utf-8,Hello%20from%20Proton%20downloadUrl%0A"></div><fieldset class="choice"><legend>Destination</legend><label><input type="radio" name="destination" value="automatic" checked> Temporary review file</label><label><input type="radio" name="destination" value="dialog"> Save dialog</label></fieldset><div class="actions"><button class="primary" id="start">Start download</button><button id="large">Use 250 MB test URL</button><button id="cancel">Cancel active</button></div><p id="status" role="status" aria-live="polite">Ready. Automatic path: \{automatic_download_path}</p></section></main>
    #|<script>const status=document.querySelector('#status'),url=document.querySelector('#url');async function invoke(name,payload){return window.__MoonBit__.core.invokeOp('ext:downloadReview/'+name,payload)}document.querySelector('#start').onclick=async()=>{status.dataset.nativeUpdate='false';status.textContent='Starting programmatic download...';try{const reply=await invoke('start',{url:url.value,show_dialog:document.querySelector('input[name=destination]:checked').value==='dialog'});if(!reply.ok||status.dataset.nativeUpdate!=='true')status.textContent=reply.message}catch(error){status.textContent=String(error)}};document.querySelector('#large').onclick=()=>{url.value='https://speed.cloudflare.com/__down?bytes=250000000';status.textContent='250 MB URL selected. Start it, then use Cancel active while progress is visible.'};document.querySelector('#cancel').onclick=async()=>{try{const reply=await invoke('cancel',null);if(!reply.ok)status.textContent=reply.message}catch(error){status.textContent=String(error)}}</script></body></html>
  )
}

///|
async fn main {
  @proton.html(
    "Programmatic Download",
    page(),
    width=840,
    height=620,
    debug=true,
  )
  .commands(register_commands)
  .on_download_request(fn(_browser, request) {
    last_download_id.val = Some(request.id)
    let destination = if show_dialog.val {
      "system save dialog"
    } else {
      automatic_download_path
    }
    show_status(
      "Approved download \{request.id}\nURL: \{request.url}\nSuggested name: \{request.suggested_name}\nDestination: \{destination}",
    )
    if show_dialog.val {
      @proton.DownloadDecision::ShowSaveDialog
    } else {
      @proton.DownloadDecision::SaveTo(automatic_download_path)
    }
  })
  .on_download_event(fn(_browser, event) {
    last_download_id.val = Some(event.id)
    show_status(
      "Download \{event.id}: \{event.state}\nProgress: \{event.percent}%\nReceived: \{event.received_bytes} / \{event.total_bytes} bytes\nAutomatic path: \{automatic_download_path}",
    )
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      browser_slot.val = Some(window.browser())
      window
    },
    on_close=fn(_window) {
      browser_slot.val = None
      last_download_id.val = None
    },
  )
  .identifier("dev.proton.71-download-url")
  .run_or_abort()
}
