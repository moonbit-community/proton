///|
// A Codex-style built-in browser: the host page (app/index.html with
// sidebar.css/sidebar.js sidecars, loaded through @proton.asset) renders the
// application UI while a web contents view fills the remaining content area
// as the embedded browser. View lifecycle events keep the sidebar in sync.

///|
struct NavigatePayload {
  url : String
} derive(ToJson, FromJson)

///|
pub extend NavigatePayload with ToJson::{to_json}

///|
pub extend NavigatePayload with FromJson::{from_json}

///|
struct NavigateReply {
  ok : Bool
  url : String
} derive(ToJson, FromJson)

///|
pub extend NavigateReply with ToJson::{to_json}

///|
pub extend NavigateReply with FromJson::{from_json}

///|
struct SimpleReply {
  ok : Bool
} derive(ToJson, FromJson)

///|
pub extend SimpleReply with ToJson::{to_json}

///|
pub extend SimpleReply with FromJson::{from_json}

///|
let browser_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/web-contents-view-browser",
  js_namespace="browser",
)

///|
let navigate_command : @proton_contract.Command[NavigatePayload, NavigateReply] = browser_contract.command(
  "navigate",
)

///|
let back_command : @proton_contract.Command[Json, SimpleReply] = browser_contract.command(
  "back",
)

///|
let forward_command : @proton_contract.Command[Json, SimpleReply] = browser_contract.command(
  "forward",
)

///|
let reload_command : @proton_contract.Command[Json, SimpleReply] = browser_contract.command(
  "reload",
)

///|
let sidebar_width = 288

///|
let panel_slot : Ref[@proton.ViewHandle?] = { val: None, }

///|
let host_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
fn normalize_url(url : String) -> String {
  if url.contains("://") || url.has_prefix("data:") || url.has_prefix("about:") {
    url
  } else {
    "https://" + url
  }
}

///|
fn navigate(payload : NavigatePayload) -> NavigateReply {
  let url = normalize_url(payload.url)
  match panel_slot.val {
    Some(view) => {
      view.load_url(url) catch {
        _ => return NavigateReply::{ ok: false, url, }
      }
      NavigateReply::{ ok: true, url, }
    }
    None => NavigateReply::{ ok: false, url, }
  }
}

///|
fn panel_command(action : (@proton.ViewHandle) -> Unit raise) -> SimpleReply {
  match panel_slot.val {
    Some(view) => {
      action(view) catch {
        _ => return SimpleReply::{ ok: false, }
      }
      SimpleReply::{ ok: true, }
    }
    None => SimpleReply::{ ok: false, }
  }
}

///|
fn browser_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    browser_contract,
    [
      navigate_command.contract_route(),
      back_command.contract_route(),
      forward_command.contract_route(),
      reload_command.contract_route(),
    ],
    fn(registrar) raise {
      registrar.bind(navigate_command, (_context, payload) => navigate(payload))
      registrar.bind(back_command, (_context, _payload) => {
        panel_command(view => view.back())
      })
      registrar.bind(forward_command, (_context, _payload) => {
        panel_command(view => view.forward())
      })
      registrar.bind(reload_command, (_context, _payload) => {
        panel_command(view => view.reload())
      })
    },
  )
}

///|
fn host_eval(script : String) -> Unit {
  match host_slot.val {
    Some(window) => window.browser().eval(script) catch { _ => () }
    None => ()
  }
}

///|
fn js_escape(text : String) -> String {
  text.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
fn sync_sidebar(url~ : String?, title~ : String?, error~ : String?) -> Unit {
  if url is Some(url) {
    host_eval("document.querySelector(\"#url\").value = \"\{js_escape(url)}\";")
  }
  if error is Some(error) {
    host_eval(
      "document.querySelector(\"#status\").textContent = \"\{js_escape(error)}\";",
    )
  } else if title is Some(title) {
    host_eval(
      "document.querySelector(\"#status\").textContent = \"\{js_escape(title)}\";",
    )
  }
}

///|
let start_page_url = "data:text/html,<body style='margin:0;background:rgb(30,32,36);color:rgb(220,224,230);font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh'><div style='text-align:center'><h1>Built-in Browser</h1><p>Pick a bookmark or enter a URL in the sidebar.</p></div></body>"

///|
fn open_panel(window : @proton.WindowHandle) -> Unit {
  let state = window.state() catch { _ => return }
  let view = window.add_view(
    "browser",
    @proton.view(
      start_page_url,
      width=state.width - sidebar_width,
      height=state.height,
      x=sidebar_width,
      y=0,
    ),
  ) catch {
    error => {
      println("add view failed: " + error.message())
      return
    }
  }
  panel_slot.val = Some(view)
}

///|
async fn main {
  @proton.asset(
    "Web Contents View Browser",
    "52_web_contents_view/app/index.html",
    width=1120,
    height=720,
    debug=true,
  )
  .titlebar_style(@proton.TitlebarStyle::Overlay)
  .capability(@proton_extension.capability(browser_extension()))
  .on_window_event(async fn(_window, event) noraise {
    match event {
      StateChanged(state) =>
        // Keep the embedded browser pinned to the right of the sidebar.
        match panel_slot.val {
          Some(view) =>
            view.set_bounds(
              x=sidebar_width,
              y=0,
              width=state.width - sidebar_width,
              height=state.height,
            ) catch {
              _ => ()
            }
          None => ()
        }
    }
  })
  .on_view_event(async fn(_view, event) noraise {
    // Keep the sidebar address bar and status line in sync with the page.
    match event {
      Navigated(url~) => sync_sidebar(url=Some(url), title=None, error=None)
      TitleUpdated(title~) =>
        sync_sidebar(url=None, title=Some(title), error=None)
      LoadFailed(url~, error_text~, ..) =>
        sync_sidebar(
          url=Some(url),
          title=None,
          error=Some("load failed: " + error_text),
        )
      LoadingChanged(..) => ()
    }
  })
  .window_lifecycle(
    on_ready=async fn(context) {
      let window = context.handle()
      host_slot.val = Some(window)
      open_panel(window)
    },
    on_close=fn(_state) {
      panel_slot.val = None
      host_slot.val = None
    },
  )
  .identifier("dev.proton.52-web-contents-view")
  .run_or_abort()
}
