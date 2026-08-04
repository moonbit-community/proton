///|
// A Codex-style built-in browser: the host page renders the application UI
// (a sidebar with navigation controls, an address bar, and bookmarks) while
// a web contents view fills the remaining content area as the embedded
// browser. View lifecycle events keep the sidebar in sync with the page.

///|
struct NavigatePayload {
  url : String
} derive(ToJson, FromJson)

///|
struct NavigateReply {
  ok : Bool
  url : String
} derive(ToJson, FromJson)

///|
struct SimpleReply {
  ok : Bool
} derive(ToJson, FromJson)

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
let panel_slot : Ref[@proton.ViewHandle?] = { val: None }

///|
let host_slot : Ref[@proton.WindowHandle?] = { val: None }

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
        _ => return NavigateReply::{ ok: false, url }
      }
      NavigateReply::{ ok: true, url }
    }
    None => NavigateReply::{ ok: false, url }
  }
}

///|
fn panel_command(action : (@proton.ViewHandle) -> Unit raise) -> SimpleReply {
  match panel_slot.val {
    Some(view) => {
      action(view) catch {
        _ => return SimpleReply::{ ok: false }
      }
      SimpleReply::{ ok: true }
    }
    None => SimpleReply::{ ok: false }
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
let sidebar_page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Web Contents View Browser</title>
  #|    <style>
  #|      * { box-sizing: border-box; }
  #|      body { margin: 0; font-family: -apple-system, sans-serif; background: #f5f5f7; }
  #|      #sidebar { position: fixed; left: 0; top: 0; bottom: 0; width: 288px;
  #|        padding: 36px 16px 16px; border-right: 1px solid #d8d8de; background: #f5f5f7;
  #|        display: flex; flex-direction: column; gap: 10px;
  #|        -webkit-app-region: drag; }
  #|      #sidebar input, #sidebar button { -webkit-app-region: no-drag; }
  #|      h1 { font-size: 15px; margin: 0 0 6px; color: #1d1d1f; }
  #|      #nav { display: flex; gap: 6px; }
  #|      #nav button { flex: 1; text-align: center; }
  #|      #bar { display: flex; gap: 6px; }
  #|      #url { flex: 1; padding: 6px 8px; border: 1px solid #c8c8cf; border-radius: 6px;
  #|        font-size: 13px; min-width: 0; }
  #|      button { padding: 6px 10px; border: 1px solid #c8c8cf; border-radius: 6px;
  #|        background: #fff; font-size: 13px; cursor: pointer; text-align: left; }
  #|      button:hover { background: #ececf0; }
  #|      #go { text-align: center; }
  #|      #status { font-size: 12px; color: #6e6e73; word-break: break-all; min-height: 16px; }
  #|      .hint { margin-top: auto; font-size: 11px; color: #8e8e93; line-height: 1.5; }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <div id="sidebar">
  #|      <h1>Built-in Browser</h1>
  #|      <div id="nav">
  #|        <button id="back" title="Back">&#8592;</button>
  #|        <button id="forward" title="Forward">&#8594;</button>
  #|        <button id="reload" title="Reload">&#10227;</button>
  #|      </div>
  #|      <div id="bar">
  #|        <input id="url" placeholder="example.com" />
  #|        <button id="go">Go</button>
  #|      </div>
  #|      <button data-url="https://example.com">Example</button>
  #|      <button data-url="https://moonbitlang.com">MoonBit</button>
  #|      <button data-url="https://developer.mozilla.org">MDN</button>
  #|      <button data-url="https://www.wikipedia.org">Wikipedia</button>
  #|      <div id="status"></div>
  #|      <p class="hint">
  #|        The area on the right is a web contents view: an independent native
  #|        browser hosted inside this window. Navigation events flow back into
  #|        the sidebar; back/forward/reload use per-view browser commands.
  #|      </p>
  #|    </div>
  #|    <script>
  #|      const status = document.querySelector("#status");
  #|      async function navigate(url) {
  #|        const reply = await window.__MoonBit__.browser.navigate({ url });
  #|        status.textContent = reply.ok ? reply.url : "failed: " + reply.url;
  #|      }
  #|      document.querySelector("#go").onclick = () => {
  #|        const input = document.querySelector("#url");
  #|        if (input.value.trim() !== "") navigate(input.value.trim());
  #|      };
  #|      document.querySelector("#url").onkeydown = (event) => {
  #|        if (event.key === "Enter") document.querySelector("#go").click();
  #|      };
  #|      for (const button of document.querySelectorAll("button[data-url]")) {
  #|        button.onclick = () => navigate(button.dataset.url);
  #|      }
  #|      document.querySelector("#back").onclick = () => window.__MoonBit__.browser.back();
  #|      document.querySelector("#forward").onclick = () => window.__MoonBit__.browser.forward();
  #|      document.querySelector("#reload").onclick = () => window.__MoonBit__.browser.reload();
  #|    </script>
  #|  </body>
  #|</html>
  #|

///|
fn open_panel(window : @proton.WindowHandle) -> Unit {
  let state = window.state() catch { _ => return }
  let view = window.add_view(
    "browser",
    @native.ViewConfig::new(
      width=state.width - sidebar_width,
      height=state.height,
      x=sidebar_width,
      y=0,
      initial_url=start_page_url,
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
fn main {
  @proton.run(() => {
    @proton.html(
      "Web Contents View Browser",
      sidebar_page,
      width=1120,
      height=720,
      debug=true,
    )
    .titlebar_style(@proton.TitlebarStyle::Overlay)
    .expose(browser_extension())
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
    .run_or_abort()
  })
}
