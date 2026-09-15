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
struct ButtonsRequest {
  visible : Bool
} derive(ToJson, FromJson)

///|
struct JumpListRequest {
  mode : String
} derive(ToJson, FromJson)

///|
pub extend JumpListRequest with ToJson::{to_json}

///|
pub extend JumpListRequest with FromJson::{from_json}

///|
pub extend ButtonsRequest with ToJson::{to_json}

///|
pub extend ButtonsRequest with FromJson::{from_json}

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
let set_buttons_command : @proton_contract.Command[ButtonsRequest, Reply] = taskbar_contract.command(
  "setButtons",
)

///|
let set_jump_list_command : @proton_contract.Command[JumpListRequest, Reply] = taskbar_contract.command(
  "setJumpList",
)

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
let overlay_image : Ref[@proton.NativeImage?] = { val: None, }

///|
/// The toolbar images outlive every call, so the example releases them when the
/// window closes instead of rebuilding them on each request.
let thumbar_images : Ref[Array[@proton.NativeImage]?] = { val: None, }

///|
/// The jump list tasks launch this example again with the argument they carry.
let executable_path : Ref[String] = { val: "", }

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
/// Draws the small white glyph a toolbar button shows. Pixels are premultiplied
/// RGBA, the layout `NativeImage::add_bitmap` expects.
fn glyph_bitmap(kind : String) -> (Bytes, Int, Int) {
  let size = 16
  let pixels = FixedArray::make(size * size * 4, b'\x00')
  for y = 0; y < size; y = y + 1 {
    for x = 0; x < size; x = x + 1 {
      let filled = match kind {
        "previous" => glyph_triangle_left(x, y)
        "play" => glyph_triangle_right(x, y)
        _ => glyph_triangle_right(x, y) || glyph_triangle_right(x - 6, y)
      }
      if filled {
        let offset = (y * size + x) * 4
        pixels[offset] = b'\xff'
        pixels[offset + 1] = b'\xff'
        pixels[offset + 2] = b'\xff'
        pixels[offset + 3] = b'\xff'
      }
    }
  }
  (Bytes::from_array(pixels), size, size)
}

///|
/// Distance of a row from the triangle's widest row, so the play and skip
/// glyphs share one shape.
fn glyph_row_inset(y : Int) -> Int {
  if y < 8 {
    7 - y
  } else {
    y - 8
  }
}

///|
fn glyph_triangle_right(x : Int, y : Int) -> Bool {
  x >= 4 && x <= 11 - glyph_row_inset(y)
}

///|
fn glyph_triangle_left(x : Int, y : Int) -> Bool {
  x <= 11 && x >= 4 + glyph_row_inset(y)
}

///|
fn thumbar_icon(
  kind : String,
) -> @proton.NativeImage raise @proton.NativeImageError {
  let image = @proton.native_image()
  let (data, width, height) = glyph_bitmap(kind)
  image.add_bitmap(data, width, height)
  image
}

///|
/// Creates the three toolbar images once. The middle button uses
/// `NoBackground`, so the review can compare the flag against the other two.
fn thumbar_buttons() -> Array[@proton.ThumbarButton] raise @proton.NativeImageError {
  let images = match thumbar_images.val {
    Some(images) => images
    None => {
      let images = [
        thumbar_icon("previous"),
        thumbar_icon("play"),
        thumbar_icon("next"),
      ]
      thumbar_images.val = Some(images)
      images
    }
  }
  [
    { id: "previous", icon: images[0], tooltip: "Previous track", flags: [], },
    {
      id: "play",
      icon: images[1],
      tooltip: "Play or pause",
      flags: [@proton.ThumbarButtonFlag::NoBackground],
    },
    { id: "next", icon: images[2], tooltip: "Next track", flags: [], },
  ]
}

///|
fn release_thumbar_icons() -> Unit {
  match thumbar_images.val {
    Some(images) =>
      for image in images {
        image.destroy() catch {
          _ => ()
        }
      }
    None => ()
  }
  thumbar_images.val = None
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
fn set_buttons(request : ButtonsRequest) -> Reply {
  let buttons = if request.visible {
    thumbar_buttons() catch {
      error => return reply(false, error.message())
    }
  } else {
    []
  }
  let applied = match window_slot.val {
    Some(window) =>
      window.set_thumbar_buttons(buttons) catch {
        error => return reply(false, error.message())
      }
    None => return reply(false, "window is not ready")
  }
  if !applied {
    return reply(false, "this platform does not show a taskbar toolbar")
  }
  reply(
    true,
    if request.visible {
      "toolbar shown; click its buttons and watch this log"
    } else {
      "toolbar buttons cleared"
    },
  )
}

///|
/// The standard Tasks category an application of this kind would ship: two
/// tasks separated by the one category that accepts a separator.
fn jump_list_tasks() -> @proton.JumpListCategory {
  let program = executable_path.val
  {
    kind: @proton.JumpListCategoryKind::Tasks,
    name: "",
    items: [
      {
        kind: @proton.JumpListItemKind::Task,
        path: program,
        arguments: "--play",
        title: "Play or pause",
        description: "Starts playback in a new instance",
        icon_path: program,
        icon_index: 0,
        working_directory: "",
      },
      {
        kind: @proton.JumpListItemKind::Separator,
        path: "",
        arguments: "",
        title: "",
        description: "",
        icon_path: "",
        icon_index: 0,
        working_directory: "",
      },
      {
        kind: @proton.JumpListItemKind::Task,
        path: program,
        arguments: "--settings",
        title: "Open settings",
        description: "Opens the settings window",
        icon_path: program,
        icon_index: 0,
        working_directory: "",
      },
    ],
  }
}

///|
/// A custom category. Windows hides custom categories when the user turns the
/// "recently opened items" privacy setting off, and reports that as
/// `CustomCategoryAccessDenied`.
fn jump_list_custom() -> @proton.JumpListCategory {
  let program = executable_path.val
  {
    kind: @proton.JumpListCategoryKind::Custom,
    name: "Recent sessions",
    items: [
      {
        kind: @proton.JumpListItemKind::Task,
        path: program,
        arguments: "--session=1",
        title: "Yesterday's session",
        description: "",
        icon_path: "",
        icon_index: 0,
        working_directory: "",
      },
      {
        kind: @proton.JumpListItemKind::Task,
        path: program,
        arguments: "--session=2",
        title: "This morning's session",
        description: "",
        icon_path: "",
        icon_index: 0,
        working_directory: "",
      },
    ],
  }
}

///|
fn set_jump_list(request : JumpListRequest) -> Reply {
  let categories = match request.mode {
    "tasks" => Some([jump_list_tasks()])
    "custom" => Some([jump_list_tasks(), jump_list_custom()])
    "remove" => None
    _ => return reply(false, "unknown jump list mode: " + request.mode)
  }
  let result = @proton.set_jump_list(categories) catch {
    error => return reply(false, error.message())
  }
  match result {
    @proton.JumpListResult::Ok =>
      reply(
        true,
        if request.mode == "remove" {
          "custom jump list removed"
        } else {
          "jump list set; right-click the taskbar button"
        },
      )
    @proton.JumpListResult::Unsupported =>
      reply(false, "this platform has no jump list")
    @proton.JumpListResult::CustomCategoryAccessDenied =>
      reply(
        false, "Windows blocked the custom category; enable recently opened items to review it",
      )
    other => reply(false, "jump list result: " + other.to_repr().to_string())
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
/// Reports a native taskbar button click in the review page.
fn report_click(id : String) -> Unit {
  match browser_slot.val {
    Some(browser) =>
      browser.eval(
        "window.taskbarStatus.record(\"taskbar button clicked: " +
        js_escape(id) +
        "\");",
      ) catch {
        _ => ()
      }
    None => ()
  }
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
  registrar.bind(set_buttons_command, (_context, request) => {
    set_buttons(request)
  })
  registrar.bind(set_jump_list_command, (_context, request) => {
    set_jump_list(request)
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
    $|<h2>Thumbnail toolbar</h2><p>Three buttons with generated glyphs. The middle button uses the <code>nobackground</code> flag, so it has no button border.</p>
    $|<div class="row"><button id="buttons-on">Show buttons</button><button id="buttons-off">Clear buttons</button></div>
    $|<h2>Jump list</h2><p>Tasks category with a separator, plus a custom "Recent sessions" category. Right-click the taskbar button to review it.</p>
    $|<div class="row"><button id="jumplist-tasks">Apply tasks</button><button id="jumplist-custom">Apply tasks + custom</button><button id="jumplist-remove">Remove jump list</button></div>
    $|<p id="status" role="status" aria-live="polite">Ready.</p>
    $|<ul id="log"></ul>
    $|<p class="note">Hover the taskbar button after each step: the progress bar sits under the icon, the badge is the red disc in the corner, and the tooltip appears over the thumbnail. macOS and Linux accept the overlay and tooltip calls without changing anything, matching Electron.</p>
    $|</main>
    $|<script>const status=document.querySelector('#status'),log=document.querySelector('#log');const invoke=(name,payload)=>window.__MoonBit__.core.invokeOp('ext:taskbarStatus/'+name,payload);function record(message){status.textContent=message;const item=document.createElement('li');item.textContent=message;log.prepend(item);while(log.children.length>8)log.lastElementChild.remove()}window.taskbarStatus={record};async function send(name,payload){try{const data=await invoke(name,payload);record(data.ok?data.message:'failed: '+data.message)}catch(error){record(String(error))}}document.querySelectorAll('[data-progress]').forEach(button=>button.addEventListener('click',()=>void send('setProgress',{value:Number(button.dataset.progress),mode:button.dataset.mode})));document.querySelector('#overlay-on').addEventListener('click',()=>void send('setOverlay',{visible:true}));document.querySelector('#overlay-off').addEventListener('click',()=>void send('setOverlay',{visible:false}));document.querySelector('#tooltip-apply').addEventListener('click',()=>void send('setTooltip',{text:document.querySelector('#tooltip').value}));document.querySelector('#buttons-on').addEventListener('click',()=>void send('setButtons',{visible:true}));document.querySelector('#buttons-off').addEventListener('click',()=>void send('setButtons',{visible:false}));document.querySelector('#jumplist-tasks').addEventListener('click',()=>void send('setJumpList',{mode:'tasks'}));document.querySelector('#jumplist-custom').addEventListener('click',()=>void send('setJumpList',{mode:'custom'}));document.querySelector('#jumplist-remove').addEventListener('click',()=>void send('setJumpList',{mode:'remove'}));</script>
    $|</body></html>
  )
}

///|
async fn main {
  let app = @proton.html(
    "Taskbar Status",
    page(),
    width=900,
    height=760,
    debug=true,
  )
  executable_path.val = app.path(@proton.AppPathKind::Executable) catch {
    _ => ""
  }
  app
  .identifier("dev.proton.78-taskbar-status")
  .commands(register_commands)
  .on_thumbar_button_click(fn(_window, id) noraise { report_click(id) })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      browser_slot.val = Some(window.browser())
      window
    },
    on_close=fn(_window) {
      window_slot.val = None
      browser_slot.val = None
      release_overlay_icon()
      release_thumbar_icons()
    },
  )
  .run_or_abort()
}
