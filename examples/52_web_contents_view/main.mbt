///|
// A Codex-style built-in browser: the host page renders the application UI
// (a sidebar with an address bar and bookmarks) while a web contents view
// fills the remaining content area as the embedded browser.

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
let browser_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/web-contents-view-browser",
  js_namespace="browser",
)

///|
let navigate_command : @proton_contract.Command[NavigatePayload, NavigateReply] = browser_contract.command(
  "navigate",
)

///|
let sidebar_width = 288

///|
let panel_slot : Ref[@proton.ViewHandle?] = { val: None }

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
fn browser_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    browser_contract,
    [navigate_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(navigate_command, (_context, payload) => navigate(payload))
    },
  )
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
  #|        display: flex; flex-direction: column; gap: 10px; }
  #|      h1 { font-size: 15px; margin: 0 0 6px; color: #1d1d1f; }
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
  #|        browser hosted inside this window. Sidebar buttons invoke a Proton
  #|        command that calls ViewHandle::load_url.
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
                sidebar_width,
                0,
                state.width - sidebar_width,
                state.height,
              ) catch {
                _ => ()
              }
            None => ()
          }
      }
    })
    .window_lifecycle(
      on_ready=async fn(context) { open_panel(context.handle()) },
      on_close=fn(_state) { panel_slot.val = None },
    )
    .run_or_abort()
  })
}
