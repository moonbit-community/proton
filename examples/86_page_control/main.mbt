///|
struct ControlRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend ControlRequest with ToJson::{to_json}

///|
pub extend ControlRequest with FromJson::{from_json}

///|
struct EntryRow {
  title : String
  url : String
  transition : String
  active : Bool
} derive(ToJson, FromJson)

///|
pub extend EntryRow with ToJson::{to_json}

///|
pub extend EntryRow with FromJson::{from_json}

///|
struct ControlReply {
  ok : Bool
  message : String
  active_index : Int
  css_key : Int64
  entries : Array[EntryRow]
} derive(ToJson, FromJson)

///|
pub extend ControlReply with ToJson::{to_json}

///|
pub extend ControlReply with FromJson::{from_json}

///|
let contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/page-control",
  js_namespace="pageControl",
)

///|
let control_command : @proton_contract.Command[ControlRequest, ControlReply] = contract.command(
  "control",
)

///|
/// The running application context, retained for command handlers.
let application_slot : Ref[@proton.ApplicationContext?] = { val: None, }

///|
/// The key of the stylesheet inserted through `BrowserHandle::insert_css`, or 0
/// while none is inserted.
let inserted_css : Ref[Int64] = { val: 0L, }

///|
/// Emits one review line for the terminal that started the example.
fn log_page_step(step : String) -> Unit {
  println("[page-control] " + step)
}

///|
/// Names the page transition of one history entry for the review output.
fn transition_name(transition : @proton.NavigationTransition) -> String {
  match transition {
    @proton.NavigationTransition::Link => "link"
    @proton.NavigationTransition::Typed => "typed"
    @proton.NavigationTransition::AutoBookmark => "auto-bookmark"
    @proton.NavigationTransition::AutoSubframe => "auto-subframe"
    @proton.NavigationTransition::ManualSubframe => "manual-subframe"
    @proton.NavigationTransition::Generated => "generated"
    @proton.NavigationTransition::AutoToplevel => "auto-toplevel"
    @proton.NavigationTransition::FormSubmit => "form-submit"
    @proton.NavigationTransition::Reload => "reload"
    @proton.NavigationTransition::Keyword => "keyword"
    @proton.NavigationTransition::KeywordGenerated => "keyword-generated"
    @proton.NavigationTransition::Other(code) => "other:" + code.to_string()
  }
}

///|
fn entry_rows(history : @proton.NavigationHistory) -> Array[EntryRow] {
  let rows : Array[EntryRow] = []
  for index, entry in history.entries {
    rows.push({
      title: entry.title,
      url: entry.url,
      transition: transition_name(entry.transition),
      active: index == history.active_index,
    })
  }
  rows
}

///|
/// Reads the main browser, or reports that the window is not ready.
fn main_browser() -> @proton.BrowserHandle? {
  match application_slot.val {
    None => None
    Some(context) =>
      match context.windows().find("main") {
        Some(window) => Some(window.browser())
        None => None
      }
  }
}

///|
fn state_reply(message : String, ok? : Bool = true) -> ControlReply {
  let browser = match main_browser() {
    Some(browser) => browser
    None =>
      return {
        ok: false,
        message: "Application window is not ready",
        active_index: -1,
        css_key: inserted_css.val,
        entries: [],
      }
  }
  let history = browser.navigation_history() catch {
    error => {
      log_page_step("navigation history failed: " + error.message())
      return {
        ok: false,
        message: error.message(),
        active_index: -1,
        css_key: inserted_css.val,
        entries: [],
      }
    }
  }
  let rows = entry_rows(history)
  {
    ok,
    message,
    active_index: history.active_index,
    css_key: inserted_css.val,
    entries: rows,
  }
}

///|
fn control(request : ControlRequest) -> ControlReply {
  let browser = match main_browser() {
    Some(browser) => browser
    None => return state_reply("Application window is not ready", ok=false)
  }
  match request.action {
    "state" => {
      let reply = state_reply("History refreshed")
      log_page_step(
        "history entries=" +
        reply.entries.length().to_string() +
        " active_index=" +
        reply.active_index.to_string(),
      )
      reply
    }
    "insert-css" => {
      guard inserted_css.val == 0L else {
        return state_reply("A stylesheet is already inserted", ok=false)
      }
      let key = browser.insert_css(
        "html { --proton-review-css: inserted } body::after { content: 'inserted stylesheet'; position: fixed; left: 12px; bottom: 12px; padding: 6px 10px; border-radius: 6px; background: #20564d; color: #eef3f6; font: 12px ui-monospace, monospace; }",
      ) catch {
        error => {
          log_page_step("insert_css failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      inserted_css.val = key
      log_page_step("insert_css key=" + key.to_string())
      state_reply("Stylesheet inserted; the page shows the marker")
    }
    "remove-css" => {
      guard inserted_css.val != 0L else {
        return state_reply("No stylesheet is inserted", ok=false)
      }
      let key = inserted_css.val
      browser.remove_inserted_css(key) catch {
        error => {
          log_page_step("remove_inserted_css failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      inserted_css.val = 0L
      log_page_step("remove_inserted_css key=" + key.to_string())
      state_reply("Stylesheet removed; the marker is gone")
    }
    "second-page" => {
      browser.load_url(second_page()) catch {
        error => {
          log_page_step("load_url failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_page_step("loaded the second page")
      state_reply("Second page loaded; the history has two entries")
    }
    "back" => {
      browser.back() catch {
        error => {
          log_page_step("back failed: " + error.message())
          return state_reply(error.message(), ok=false)
        }
      }
      log_page_step("went back to the first page")
      state_reply("Moved back through the history")
    }
    _ => state_reply("Unknown action", ok=false)
  }
}

///|
/// The second document the review navigates to, so the history has two
/// entries.
fn second_page() -> String {
  "data:text/html,<title>Second page</title><h1>Second page</h1><p>Use Back to return.</p>"
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(control_command, (_context, request) => control(request))
}

///|
fn page() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>Page control</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101418; color: #eef3f6; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #101418; }
    #|      button { font: inherit; cursor: pointer; }
    #|      main { width: min(900px, calc(100vw - 40px)); margin: 0 auto; padding: 34px 0 46px; }
    #|      .eyebrow { margin: 0 0 10px; color: #58c7d8; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(26px, 4vw, 40px); letter-spacing: -.04em; }
    #|      .summary { margin: 12px 0 0; color: #9fb0bd; line-height: 1.55; }
    #|      code { padding: 1px 6px; border-radius: 4px; background: #1d242b; color: #cfe7ef; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .panel { margin-top: 22px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; min-height: 46px; padding: 0 16px; border-bottom: 1px solid #2b353d; color: #9fb0bd; font: 650 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .09em; }
    #|      .actions { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; padding: 16px; }
    #|      .action { min-height: 44px; padding: 0 14px; border: 1px solid #3a4a55; border-radius: 8px; background: #1b232a; color: #eef3f6; font-weight: 600; }
    #|      .action.primary { border-color: #2f6f63; background: #20564d; }
    #|      table { width: 100%; border-collapse: collapse; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      th, td { padding: 8px 16px; text-align: left; border-bottom: 1px solid #212a31; }
    #|      th { color: #8b9aa6; font-weight: 600; }
    #|      tr.active td { color: #7fd8c6; }
    #|      .status { margin-top: 16px; padding: 14px 16px; border: 1px solid #2b353d; border-radius: 12px; background: #151b21; color: #cfe7ef; font: 12px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <p class="eyebrow">Electron app / review 86</p>
    #|        <h1>Page history and inserted CSS</h1>
    #|        <p class="summary">
    #|          <code>ApplicationContext</code> exposes each browser's session
    #|          history through <code>navigation_history()</code>, matching
    #|          Electron's <code>webContents.navigationHistory</code>, and
    #|          injects page stylesheets with <code>insert_css</code> and
    #|          <code>remove_inserted_css</code>, matching
    #|          <code>webContents.insertCSS</code> and
    #|          <code>removeInsertedCSS</code>. Every action prints one
    #|          <code>[page-control]</code> line in the terminal.
    #|        </p>
    #|      </header>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Actions</span><span id="css">no stylesheet</span></div>
    #|        <div class="actions">
    #|          <button class="action" id="state">Refresh history</button>
    #|          <button class="action primary" id="second-page">Load second page</button>
    #|          <button class="action" id="back">Back</button>
    #|          <button class="action" id="insert-css">Insert CSS</button>
    #|          <button class="action" id="remove-css">Remove inserted CSS</button>
    #|        </div>
    #|      </section>
    #|      <section class="panel">
    #|        <div class="panel-head"><span>Navigation history</span><span id="active">-</span></div>
    #|        <table>
    #|          <thead>
    #|            <tr><th>#</th><th>title</th><th>url</th><th>transition</th></tr>
    #|          </thead>
    #|          <tbody id="rows"></tbody>
    #|        </table>
    #|      </section>
    #|      <p class="status" id="status" role="status">Ready.</p>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      const rows = document.querySelector("#rows");
    #|      async function invoke(action) {
    #|        return window.__MoonBit__.core.invokeOp("ext:pageControl/control", { action });
    #|      }
    #|      function cell(text) {
    #|        const td = document.createElement("td");
    #|        td.textContent = text;
    #|        return td;
    #|      }
    #|      function render(reply) {
    #|        rows.replaceChildren();
    #|        reply.entries.forEach((entry, index) => {
    #|          const tr = document.createElement("tr");
    #|          if (entry.active) tr.className = "active";
    #|          tr.append(cell(String(index)), cell(entry.title || "-"), cell(entry.url), cell(entry.transition));
    #|          rows.append(tr);
    #|        });
    #|        document.querySelector("#active").textContent = `${reply.active_index + 1} / ${reply.entries.length}`;
    #|        document.querySelector("#css").textContent = reply.css_key === 0 ? "no stylesheet" : `key ${reply.css_key}`;
    #|        status.textContent = reply.ok ? reply.message : `Failed: ${reply.message}`;
    #|      }
    #|      async function run(action) {
    #|        try {
    #|          render(await invoke(action));
    #|        } catch (error) {
    #|          status.textContent = `${action} failed: ${String(error)}`;
    #|        }
    #|      }
    #|      for (const action of ["state", "second-page", "back", "insert-css", "remove-css"]) {
    #|        document.querySelector(`#${action}`).addEventListener("click", () => void run(action));
    #|      }
    #|      void run("state");
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Page control", page(), width=900, height=760)
  .identifier("com.example.proton.page-control")
  .commands(register_commands)
  .app_lifecycle(
    on_start=context => {
      application_slot.val = Some(context)
      log_page_step("application started")
      // Report the startup history so the terminal shows the review surface
      // without a click. The primary window appears a moment after startup.
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            for attempt = 0; attempt < 400; attempt = attempt + 1 {
              let reply = state_reply("Startup history")
              if reply.entries.length() > 0 {
                log_page_step(
                  "startup entries=" +
                  reply.entries.length().to_string() +
                  " active_index=" +
                  reply.active_index.to_string(),
                )
                return
              }
              @async.sleep(25)
            }
            log_page_step("startup history stayed empty")
          },
          no_wait=true,
        ),
      )
      context
    },
    on_shutdown=fn(_context) {
      application_slot.val = None
      inserted_css.val = 0L
    },
  )
  .run_or_abort()
}
