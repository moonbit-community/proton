///|
struct SetSourceRequest {
  source : String
} derive(ToJson, FromJson)

///|
pub extend SetSourceRequest with ToJson::{to_json}

///|
pub extend SetSourceRequest with FromJson::{from_json}

///|
/// One appearance snapshot, in the shape the review page renders.
struct ThemeState {
  message : String
  dark_colors : Bool
  high_contrast_colors : Bool
  source : String
} derive(ToJson, FromJson)

///|
pub extend ThemeState with ToJson::{to_json}

///|
pub extend ThemeState with FromJson::{from_json}

///|
let native_theme_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/native-theme",
  js_namespace="nativeThemeReview",
)

///|
let set_source_command : @proton_contract.Command[SetSourceRequest, ThemeState] = native_theme_contract.command(
  "setSource",
)

///|
let read_command : @proton_contract.Command[Unit, ThemeState] = native_theme_contract.command(
  "read",
)

///|
let browser_slot : Ref[@proton.BrowserHandle?] = { val: None, }

///|
fn source_name(source : @proton.WindowThemePreference) -> String {
  match source {
    @proton.WindowThemePreference::System => "system"
    @proton.WindowThemePreference::Light => "light"
    @proton.WindowThemePreference::Dark => "dark"
  }
}

///|
fn source_from_name(name : String) -> @proton.WindowThemePreference? {
  match name {
    "system" => Some(@proton.WindowThemePreference::System)
    "light" => Some(@proton.WindowThemePreference::Light)
    "dark" => Some(@proton.WindowThemePreference::Dark)
    _ => None
  }
}

///|
fn state_from_theme(
  theme : @proton.NativeTheme,
  message : String,
) -> ThemeState {
  {
    message,
    dark_colors: theme.should_use_dark_colors(),
    high_contrast_colors: theme.should_use_high_contrast_colors(),
    source: source_name(theme.theme_source()),
  }
}

///|
fn unavailable_state(message : String) -> ThemeState {
  {
    message,
    dark_colors: false,
    high_contrast_colors: false,
    source: "unknown",
  }
}

///|
/// Reads the operating system appearance back instead of trusting the request.
fn read_state(message : String) -> ThemeState {
  let theme = @proton.native_theme() catch {
    error => return unavailable_state(message + ": " + error.message())
  }
  state_from_theme(theme, message)
}

///|
/// Pushes a snapshot into the page. The page is authoritative for nothing; it
/// only renders what the application sends, which is how an application that
/// owns a theme would drive its own renderer.
fn push_state(state : ThemeState) -> Unit {
  match browser_slot.val {
    Some(browser) =>
      browser.eval(
        "window.nativeThemeReview.apply(" + state.to_json().stringify() + ");",
      ) catch {
        _ => ()
      }
    None => ()
  }
}

///|
fn set_source(request : SetSourceRequest) -> ThemeState {
  let source = match source_from_name(request.source) {
    Some(source) => source
    None => return unavailable_state("unknown theme source: " + request.source)
  }
  @proton.native_theme_set_source(source) catch {
    error =>
      return unavailable_state(
        "setting the theme source failed: " + error.message(),
      )
  }
  let state = read_state("themeSource set to " + request.source)
  push_state(state)
  state
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(set_source_command, (_context, request) => set_source(request))
  registrar.bind(read_command, (_context, _request) => {
    let state = read_state("read back from the native query")
    push_state(state)
    state
  })
}

///|
fn page() -> String {
  (
    $|<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Native theme</title>
    $|<style>*{box-sizing:border-box}:root{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#1f2529;background:#eef1f2}body{margin:0;min-height:100vh;background:#eef1f2}header{padding:30px 38px 26px;background:#1f2529;color:#f7f9fa;border-bottom:5px solid #2f7d8f}.eyebrow{margin:0;font:700 11px/1.4 ui-monospace,SFMono-Regular,Consolas,monospace;color:#7fd8c0;text-transform:uppercase}h1{margin:6px 0 8px;font-size:30px}header p{margin:0;color:#c5ced2}.summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:1px;background:#a9b2b7;border-bottom:1px solid #a9b2b7}.metric{min-width:0;padding:20px 24px;background:#fff}.metric span{display:block;margin-bottom:5px;color:#63707a;font-size:12px;font-weight:700;text-transform:uppercase}.metric strong{display:block;overflow-wrap:anywhere;font-size:19px}main{padding:26px 38px 38px}h2{margin:0 0 12px;font-size:17px}.controls{display:flex;flex-wrap:wrap;gap:10px;padding-bottom:22px}.controls button{min-height:42px;padding:0 16px;border:1px solid #9aa5ab;border-radius:6px;background:#fff;color:#1f2529;font:600 14px/1 inherit;cursor:pointer}.controls button:hover{border-color:#2f7d8f}.controls button.selected{border-color:#2f7d8f;background:#2f7d8f;color:#fff}.controls button:focus-visible{outline:3px solid #2f7d8f66;outline-offset:2px}.log{margin:0;padding:0;list-style:none;background:#fff;border:1px solid #a9b2b7}.log li{padding:11px 16px;border-bottom:1px solid #dde2e5;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#1d4a5c}.log li:last-child{border-bottom:0}.log:empty::after{content:"No nativeTheme event yet.";display:block;padding:11px 16px;color:#7b878d;font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}.note{margin:18px 0 0;padding-left:14px;border-left:4px solid #d6a537;color:#546168;font-size:13px;line-height:1.55}@media(max-width:780px){header,main{padding-left:20px;padding-right:20px}.summary{grid-template-columns:1fr}}</style></head>
    $|<body><header><p class="eyebrow">Electron app parity / Review 77</p><h1>Native theme</h1><p>nativeTheme query, themeSource, and the updated event.</p></header>
    $|<section class="summary"><div class="metric"><span>Dark colors</span><strong id="dark">-</strong></div><div class="metric"><span>High contrast</span><strong id="contrast">-</strong></div><div class="metric"><span>Theme source</span><strong id="source">-</strong></div></section>
    $|<main><h2>Application surface</h2><div class="controls"><button data-source="system">Theme source: system</button><button data-source="light">themeSource: light</button><button data-source="dark">themeSource: dark</button><button id="read">Read back</button></div>
    $|<h2>Native events received</h2><ul class="log" id="events"></ul>
    $|<p class="note">The renderer keeps following the operating system: <strong id="renderer">-</strong>. Proton does not override <code>prefers-color-scheme</code>, so a themeSource override changes the application snapshot and the window chrome, not the page media query.</p></main>
    $|<script>const dark=document.querySelector('#dark'),contrast=document.querySelector('#contrast'),source=document.querySelector('#source'),status=document.querySelector('#events'),media=window.matchMedia('(prefers-color-scheme: dark)'),renderer=document.querySelector('#renderer');function renderMedia(){renderer.textContent=media.matches?'prefers dark':'prefers light'}media.addEventListener('change',renderMedia);renderMedia();function markSource(name){document.querySelectorAll('[data-source]').forEach(button=>button.classList.toggle('selected',button.dataset.source===name))}window.nativeThemeReview={apply(state){if(!state)return;dark.textContent=state.dark_colors?'dark':'light';contrast.textContent=state.high_contrast_colors?'increased contrast':'standard contrast';source.textContent=state.source;markSource(state.source);const item=document.createElement('li');item.textContent=state.message;status.prepend(item);while(status.children.length>8)status.lastElementChild.remove()}};const invoke=(name,payload)=>window.__MoonBit__.core.invokeOp('ext:nativeThemeReview/'+name,payload);document.querySelectorAll('[data-source]').forEach(button=>button.addEventListener('click',async()=>{try{window.nativeThemeReview.apply(await invoke('setSource',{source:button.dataset.source}))}catch(error){const item=document.createElement('li');item.textContent=String(error);status.prepend(item)}}));document.querySelector('#read').addEventListener('click',async()=>{try{window.nativeThemeReview.apply(await invoke('read',null))}catch(error){const item=document.createElement('li');item.textContent=String(error);status.prepend(item)}});void invoke('read',null).then(state=>window.nativeThemeReview.apply(state)).catch(()=>{})</script></body></html>
  )
}

///|
async fn main {
  @proton.html("Native Theme", page(), width=900, height=720, debug=true)
  .identifier("dev.proton.77-native-theme")
  .commands(register_commands)
  .on_native_theme_change(fn(theme) noraise {
    let state = state_from_theme(
      theme,
      "updated event: source=" +
      source_name(theme.theme_source()) +
      ", dark=" +
      theme.should_use_dark_colors().to_string() +
      ", high contrast=" +
      theme.should_use_high_contrast_colors().to_string(),
    )
    push_state(state)
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      browser_slot.val = Some(window.browser())
      window
    },
    on_close=fn(_window) { browser_slot.val = None },
  )
  .run_or_abort()
}
