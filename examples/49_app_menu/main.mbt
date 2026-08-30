///|
struct MenuStateRequest {
  action : String
} derive(ToJson, FromJson)

///|
pub extend MenuStateRequest with ToJson::{to_json}

///|
pub extend MenuStateRequest with FromJson::{from_json}

///|
struct MenuStateReply {
  enabled : Bool
  visible : Bool
  checked : Bool
  applied : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend MenuStateReply with ToJson::{to_json}

///|
pub extend MenuStateReply with FromJson::{from_json}

///|
let menu_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/app-menu",
  js_namespace="appMenu",
)

///|
let menu_state_command : @proton_contract.Command[
  MenuStateRequest,
  MenuStateReply,
] = menu_contract.command("state")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None, }

///|
let enabled_state : Ref[Bool] = { val: true, }

///|
let visible_state : Ref[Bool] = { val: true, }

///|
let checked_state : Ref[Bool] = { val: false, }

///|
fn menu_bar() -> @proton.MenuBar {
  @proton.MenuBar(menus=[
    @proton.Menu("State", items=[
      @proton.MenuItem::command(
        "state.enabled",
        if enabled_state.val {
          "Disable Review Action"
        } else {
          "Enable Review Action"
        },
        key="e",
      ),
      @proton.MenuItem::command(
        "state.visible",
        if visible_state.val {
          "Hide Optional Action"
        } else {
          "Show Optional Action"
        },
        key="v",
      ),
      @proton.MenuItem::command(
        "state.checked",
        "Checked Option",
        key="k",
        checked=checked_state.val,
      ),
      @proton.MenuItem::separator(),
      @proton.MenuItem::command(
        "demo.review",
        "Review Action",
        enabled=enabled_state.val,
      ),
      @proton.MenuItem::command(
        "demo.optional",
        "Optional Action",
        visible=visible_state.val,
      ),
    ]),
    @proton.Menu::role(@proton.MenuRole::Edit),
    @proton.Menu::role(@proton.MenuRole::Window),
    @proton.Menu::role(@proton.MenuRole::Help, items=[
      @proton.MenuItem::command("help.about", "About Menu State Review"),
    ]),
  ])
}

///|
fn menu_state_reply(applied : Bool, message : String) -> MenuStateReply {
  {
    enabled: enabled_state.val,
    visible: visible_state.val,
    checked: checked_state.val,
    applied,
    message,
  }
}

///|
fn update_menu_state(request : MenuStateRequest) -> MenuStateReply {
  let previous_enabled = enabled_state.val
  let previous_visible = visible_state.val
  let previous_checked = checked_state.val
  match request.action {
    "enabled" => enabled_state.val = !enabled_state.val
    "visible" => visible_state.val = !visible_state.val
    "checked" => checked_state.val = !checked_state.val
    "reset" => {
      enabled_state.val = true
      visible_state.val = true
      checked_state.val = false
    }
    _ => return menu_state_reply(false, "unknown menu state action")
  }
  match window_slot.val {
    Some(window) =>
      try {
        window.set_menu(Some(menu_bar()))
        menu_state_reply(true, "native menu rebuilt")
      } catch {
        error => {
          enabled_state.val = previous_enabled
          visible_state.val = previous_visible
          checked_state.val = previous_checked
          menu_state_reply(
            false,
            "native menu update failed: " + error.to_string(),
          )
        }
      }
    None => {
      enabled_state.val = previous_enabled
      visible_state.val = previous_visible
      checked_state.val = previous_checked
      menu_state_reply(false, "window is not ready")
    }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(menu_state_command, (_context, request) => {
    update_menu_state(request)
  })
}

///|
fn html() -> String {
  (
    #|<!doctype html>
    #|<html lang="en">
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <meta name="viewport" content="width=device-width, initial-scale=1">
    #|    <title>App Menu State Review</title>
    #|    <style>
    #|      :root { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #eef2f5; color: #18212b; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; }
    #|      button { font: inherit; }
    #|      main { width: min(900px, calc(100vw - 40px)); margin: 0 auto; padding: 36px 0 48px; }
    #|      header { display: flex; align-items: end; justify-content: space-between; gap: 24px; padding-bottom: 22px; border-bottom: 1px solid #bac5cf; }
    #|      h1 { margin: 0; font-size: 38px; line-height: 1; letter-spacing: 0; }
    #|      .summary { max-width: 520px; margin: 12px 0 0; color: #536372; line-height: 1.55; }
    #|      .platform { flex: none; border: 1px solid #778899; padding: 8px 10px; background: #fff; color: #425363; font: 700 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.35fr) minmax(260px, .8fr); gap: 16px; margin-top: 18px; }
    #|      .panel { border: 1px solid #aebbc6; background: #fff; }
    #|      .panel h2 { margin: 0; padding: 14px 16px; border-bottom: 1px solid #c7d0d8; font-size: 14px; }
    #|      .states { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1px; background: #c7d0d8; }
    #|      .state { min-width: 0; padding: 18px 14px; background: #f8fafb; }
    #|      .state span { display: block; color: #687887; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .state strong { display: block; margin-top: 8px; color: #0b6b53; font-size: 18px; overflow-wrap: anywhere; }
    #|      .controls { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; padding: 16px; }
    #|      button { min-height: 42px; border: 1px solid #768797; padding: 0 13px; background: #fff; color: #243442; cursor: pointer; }
    #|      button:hover { background: #edf3f6; }
    #|      button.primary { border-color: #006b57; background: #007d66; color: white; }
    #|      #status { margin: 0; padding: 14px 16px; border-top: 1px solid #c7d0d8; color: #526473; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      ol { margin: 0; padding: 18px 22px 20px 40px; color: #4e5e6c; }
    #|      li { margin-bottom: 11px; line-height: 1.45; }
    #|      #log { max-height: 122px; margin: 0; padding: 12px 16px; overflow: auto; border-top: 1px solid #c7d0d8; list-style: none; color: #405363; font: 11px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      #log li { margin: 0 0 5px; }
    #|      @media (max-width: 720px) { header { align-items: start; flex-direction: column; } .layout { grid-template-columns: 1fr; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div><h1>Native menu state</h1><p class="summary">Use the macOS menu bar or the mirrored controls below. Every state change rebuilds the runtime menu through <code>WindowHandle.set_menu</code>.</p></div>
    #|        <div class="platform">EXAMPLE 49 / MANUAL REVIEW</div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <h2>Current definition</h2>
    #|          <div class="states"><div class="state"><span>REVIEW ACTION</span><strong id="enabled">Enabled</strong></div><div class="state"><span>OPTIONAL ACTION</span><strong id="visible">Visible</strong></div><div class="state"><span>CHECKED OPTION</span><strong id="checked">Off</strong></div></div>
    #|          <div class="controls"><button data-action="enabled">Toggle enabled</button><button data-action="visible">Toggle visible</button><button data-action="checked">Toggle checked</button><button class="primary" data-action="reset">Reset states</button></div>
    #|          <p id="status" role="status" aria-live="polite">Open the State menu to begin.</p>
    #|          <ul id="log"><li>No menu command received yet.</li></ul>
    #|        </section>
    #|        <aside class="panel"><h2>Manual review</h2><ol><li>Disable Review Action and confirm the native item cannot be selected.</li><li>Hide Optional Action and confirm it disappears without leaving a blank row.</li><li>Toggle Checked Option and confirm the native checkmark follows the page state.</li><li>Use the E, V, and K shortcuts and confirm the same updates occur.</li><li>Reset, then invoke Review Action and Optional Action to confirm command delivery.</li></ol></aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const enabled = document.querySelector('#enabled');
    #|      const visible = document.querySelector('#visible');
    #|      const checked = document.querySelector('#checked');
    #|      const status = document.querySelector('#status');
    #|      const log = document.querySelector('#log');
    #|      const invoke = (action) => window.__MoonBit__.core.invokeOp('ext:appMenu/state', { action });
    #|      function render(reply) {
    #|        enabled.textContent = reply.enabled ? 'Enabled' : 'Disabled';
    #|        visible.textContent = reply.visible ? 'Visible' : 'Hidden';
    #|        checked.textContent = reply.checked ? 'On' : 'Off';
    #|        status.textContent = reply.message;
    #|      }
    #|      async function update(action) {
    #|        status.textContent = 'Rebuilding native menu...';
    #|        try { render(await invoke(action)); } catch (error) { status.textContent = String(error); }
    #|      }
    #|      function record(command) {
    #|        if (log.children.length === 1 && log.firstElementChild.textContent.startsWith('No menu')) log.textContent = '';
    #|        const item = document.createElement('li');
    #|        item.textContent = command;
    #|        log.prepend(item);
    #|      }
    #|      document.querySelectorAll('[data-action]').forEach((button) => button.addEventListener('click', () => void update(button.dataset.action)));
    #|      window.__MoonBit__.events.on('menu.command', (event) => {
    #|        const command = event.payload.command_id;
    #|        record(command);
    #|        if (command.startsWith('state.')) void update(command.slice(6));
    #|        else status.textContent = `Menu command received: ${command}`;
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html(
    "App Menu State Review",
    html(),
    width=900,
    height=640,
    debug=true,
  )
  .menu(menu_bar())
  .identifier("dev.proton.49-app-menu")
  .commands(register_commands)
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      window_slot.val = Some(window)
      window
    },
    on_close=fn(_window) { window_slot.val = None },
  )
  .run_or_abort()
}
