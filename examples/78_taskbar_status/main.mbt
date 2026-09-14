///|
struct ProgressRequest {
  value : Double
  mode : String
} derive(ToJson, FromJson)

///|
pub extend ProgressRequest with ToJson::{to_json}

///|
pub extend ProgressRequest with FromJson::{from_json}

///|
struct OverlayRequest {
  visible : Bool
} derive(ToJson, FromJson)

///|
pub extend OverlayRequest with ToJson::{to_json}

///|
pub extend OverlayRequest with FromJson::{from_json}

///|
struct TooltipRequest {
  text : String
} derive(ToJson, FromJson)

///|
pub extend TooltipRequest with ToJson::{to_json}

///|
pub extend TooltipRequest with FromJson::{from_json}

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
let taskbar_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/taskbar-status",
  js_namespace="taskbarStatus",
)

///|
let set_progress_command : @proton_contract.Command[ProgressRequest, Reply] = taskbar_contract.command(
  "setProgress",
)

///|
let set_overlay_command : @proton_contract.Command[OverlayRequest, Reply] = taskbar_contract.command(
  "setOverlay",
)

///|
let set_tooltip_command : @proton_contract.Command[TooltipRequest, Reply] = taskbar_contract.command(
  "setTooltip",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let overlay_image : Ref[@proton.NativeImage?] = { val: None, }

///|
fn reply(ok : Bool, message : String) -> Reply {
  { ok, message, }
}

///|
fn progress_mode_from_name(name : String) -> @proton.ProgressBarMode? {
  match name {
    "automatic" => Some(@proton.ProgressBarMode::Automatic)
    "normal" => Some(@proton.ProgressBarMode::Normal)
    "indeterminate" => Some(@proton.ProgressBarMode::Indeterminate)
    "error" => Some(@proton.ProgressBarMode::Error)
    "paused" => Some(@proton.ProgressBarMode::Paused)
    "cleared" => Some(@proton.ProgressBarMode::Cleared)
    _ => None
  }
}

///|
/// Builds the 16x16 badge this example shows as a taskbar overlay: a red disc
/// with a white core, written as premultiplied RGBA pixels.
fn overlay_bitmap() -> (Bytes, Int, Int) {
  let size = 16
  let pixels = FixedArray::make(size * size * 4, b'\x00')
  let center = 7.5
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let dx = x.to_double() + 0.5 - center
      let dy = y.to_double() + 0.5 - center
      let distance_squared = dx * dx + dy * dy
      let offset = (y * size + x) * 4
      if distance_squared <= 56.25 {
        let core = distance_squared <= 9.0
        let red = if core { b'\xff' } else { b'\xd0' }
        let neutral = if core { b'\xff' } else { b'\x2b' }
        pixels[offset] = red
        pixels[offset + 1] = neutral
        pixels[offset + 2] = neutral
        pixels[offset + 3] = b'\xff'
      }
    }
  }
  (Bytes::from_array(pixels), size, size)
}

///|
/// Creates the overlay image once. The application owns the image and releases
/// it when the window closes.
fn overlay_icon() -> @proton.NativeImage raise @proton.NativeImageError {
  match overlay_image.val {
    Some(image) => image
    None => {
      let image = @proton.native_image()
      let (data, width, height) = overlay_bitmap()
      image.add_bitmap(data, width, height)
      overlay_image.val = Some(image)
      image
    }
  }
}

///|
fn release_overlay_icon() -> Unit {
  match overlay_image.val {
    Some(image) => image.destroy() catch { _ => () }
    None => ()
  }
  overlay_image.val = None
}

///|
fn set_progress(request : ProgressRequest) -> Reply {
  let mode = match progress_mode_from_name(request.mode) {
    Some(mode) => mode
    None => return reply(false, "unknown progress mode: " + request.mode)
  }
  match window_slot.val {
    Some(window) =>
      window.set_progress_bar(request.value, mode~) catch {
        error => return reply(false, error.message())
      }
    None => return reply(false, "window is not ready")
  }
  reply(
    true,
    "progress " +
    request.value.to_string() +
    " with mode " +
    request.mode +
    " applied",
  )
}

///|
fn set_overlay(request : OverlayRequest) -> Reply {
  let overlay = if request.visible {
    let image = overlay_icon() catch {
      error => return reply(false, error.message())
    }
    Some(image)
  } else {
    None
  }
  match window_slot.val {
    Some(window) =>
      window.set_overlay_icon(overlay, "unread messages") catch {
        error => return reply(false, error.message())
      }
    None => return reply(false, "window is not ready")
  }
  reply(
    true,
    if request.visible {
      "overlay icon shown"
    } else {
      "overlay icon cleared"
    },
  )
}

///|
fn set_tooltip(request : TooltipRequest) -> Reply {
  match window_slot.val {
    Some(window) =>
      window.set_thumbnail_tooltip(request.text) catch {
        error => return reply(false, error.message())
      }
    None => return reply(false, "window is not ready")
  }
  reply(true, "thumbnail tooltip set to \"" + request.text + "\"")
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_progress_command, (_context, request) => {
    set_progress(request)
  })
  registrar.bind(set_overlay_command, (_context, request) => {
    set_overlay(request)
  })
  registrar.bind(set_tooltip_command, (_context, request) => {
    set_tooltip(request)
  })
}

///|
fn page() -> String {
  (
    $|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Taskbar status</title>
    $|<style>*{box-sizing:border-box}:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#1f2429;background:#eef1f2}body{margin:0;min-height:100vh;background:#eef1f2}header{padding:30px 38px 26px;background:#1c2226;color:#f7f9fa;border-bottom:5px solid #2f7d8f}.eyebrow{margin:0;font:700 11px/1.4 ui-monospace,SFMono-Regular,Consolas,monospace;color:#7fd8c0;text-transform:uppercase}h1{margin:6px 0 8px;font-size:30px}header p{margin:0;color:#c5ced2}main{padding:26px 38px 38px}h2{margin:0 0 12px;font-size:16px}h2+p{margin:-6px 0 12px;color:#5d6a72;font-size:13px}.row{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:26px}.row button{min-height:42px;padding:0 15px;border:1px solid #9aa5ab;border-radius:6px;background:#fff;color:#1f2429;font:600 14px/1 inherit;cursor:pointer}.row button:hover{border-color:#2f7d8f}.row button:focus-visible{outline:3px solid #2f7d8f66;outline-offset:2px}.row input{min-height:42px;padding:0 12px;border:1px solid #9aa5ab;border-radius:6px;background:#fff;font:14px/1 inherit;color:#1f2429;min-width:260px}#status{margin:0;padding:12px 16px;background:#fff;border:1px solid #a9b2b7;font:12px/1.6 ui-monospace,SFMono-Regular,Consolas,monospace;color:#1d4a5c}#log{margin:14px 0 0;padding:0;list-style:none;background:#fff;border:1px solid #a9b2b7}#log li{padding:10px 16px;border-bottom:1px solid #dde2e5;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#43535c}#log li:last-child{border-bottom:0}.note{margin:18px 0 0;padding-left:14px;border-left:4px solid #d6a537;color:#546168;font-size:13px;line-height:1.55}@media(max-width:780px){header,main{padding-left:20px;padding-right:20px}}</style></head>
    $|<body><header><p class="eyebrow">Electron app parity / Review 78</p><h1>Taskbar status</h1><p>Progress modes, overlay icon, and thumbnail tooltip on the Windows taskbar.</p></header>
    $|<main>
    $|<h2>Progress</h2><p>Uses <code>WindowHandle::set_progress_bar</code> with Electron's progress modes.</p>
    $|<div class="row"><button data-progress="0.25" data-mode="automatic">25%</button><button data-progress="0.75" data-mode="automatic">75%</button><button data-progress="2" data-mode="indeterminate">Indeterminate</button><button data-progress="0.6" data-mode="error">Error</button><button data-progress="0.6" data-mode="paused">Paused</button><button data-progress="-1" data-mode="cleared">Clear</button></div>
    $|<h2>Overlay icon</h2><p>A 16x16 native image the application builds from raw pixels.</p>
    $|<div class="row"><button id="overlay-on">Show badge</button><button id="overlay-off">Clear badge</button></div>
    $|<h2>Thumbnail tooltip</h2><p>Shown when the pointer rests over the taskbar thumbnail.</p>
    $|<div class="row"><input id="tooltip" value="Proton taskbar status"><button id="tooltip-apply">Apply tooltip</button></div>
    $|<p id="status" role="status" aria-live="polite">Ready.</p>
    $|<ul id="log"></ul>
    $|<p class="note">Hover the taskbar button after each step: the progress bar sits under the icon, the badge is the red disc in the corner, and the tooltip appears over the thumbnail. macOS and Linux accept the overlay and tooltip calls without changing anything, matching Electron.</p>
    $|</main>
    $|<script>const status=document.querySelector('#status'),log=document.querySelector('#log');const invoke=(name,payload)=>window.__MoonBit__.core.invokeOp('ext:taskbarStatus/'+name,payload);function record(message){status.textContent=message;const item=document.createElement('li');item.textContent=message;log.prepend(item);while(log.children.length>8)log.lastElementChild.remove()}async function send(name,payload){try{const data=await invoke(name,payload);record(data.ok?data.message:'failed: '+data.message)}catch(error){record(String(error))}}document.querySelectorAll('[data-progress]').forEach(button=>button.addEventListener('click',()=>void send('setProgress',{value:Number(button.dataset.progress),mode:button.dataset.mode})));document.querySelector('#overlay-on').addEventListener('click',()=>void send('setOverlay',{visible:true}));document.querySelector('#overlay-off').addEventListener('click',()=>void send('setOverlay',{visible:false}));document.querySelector('#tooltip-apply').addEventListener('click',()=>void send('setTooltip',{text:document.querySelector('#tooltip').value}));</script>
    $|</body></html>
  )
}

///|
async fn main {
  @proton.html("Taskbar Status", page(), width=900, height=760, debug=true)
  .identifier("dev.proton.78-taskbar-status")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      window
    },
    on_close=fn(_window) {
      window_slot.val = None
      release_overlay_icon()
    },
  )
  .run_or_abort()
}
