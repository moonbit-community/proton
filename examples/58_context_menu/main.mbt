///|
struct ShowContextMenuRequest {
  x : Int
  y : Int
} derive(ToJson, FromJson)

///|
pub extend ShowContextMenuRequest with ToJson::{to_json}

///|
pub extend ShowContextMenuRequest with FromJson::{from_json}

///|
struct ShowContextMenuReply {
  opened : Bool
  message : String
} derive(ToJson, FromJson)

///|
pub extend ShowContextMenuReply with ToJson::{to_json}

///|
pub extend ShowContextMenuReply with FromJson::{from_json}

///|
let context_menu_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/context-menu",
  js_namespace="contextMenu",
)

///|
let show_context_menu_command : @proton_contract.Command[
  ShowContextMenuRequest,
  ShowContextMenuReply,
] = context_menu_contract.command("show")

///|
let window_slot : Ref[@proton.WindowHandle?] = { val: None }

///|
fn context_menu() -> @proton.Menu {
  @proton.Menu("Context Menu", items=[
    @proton.MenuItem::command(
      "context.inspect_coordinates",
      "Inspect Coordinates",
      key="c",
    ),
    @proton.MenuItem::separator(),
    @proton.MenuItem::submenu("More", items=[
      @proton.MenuItem::command("context.more", "More Action"),
      @proton.MenuItem::role(
        @proton.MenuItemRole::SelectAll,
        label="Select All",
        key="a",
      ),
    ]),
  ])
}

///|
fn show_context_menu(request : ShowContextMenuRequest) -> ShowContextMenuReply {
  match window_slot.val {
    Some(window) => {
      context_menu().popup(window, request.x, request.y) catch {
        error =>
          return ShowContextMenuReply::{
            opened: false,
            message: "popup failed: " + error.message(),
          }
      }
      ShowContextMenuReply::{
        opened: true,
        message: "opened at (" +
        request.x.to_string() +
        ", " +
        request.y.to_string() +
        ")",
      }
    }
    None =>
      ShowContextMenuReply::{ opened: false, message: "window is not ready" }
  }
}

///|
fn register_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(show_context_menu_command, (_context, request) => {
    show_context_menu(request)
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
    #|    <title>Context Menu Review</title>
    #|    <style>
    #|      :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #080c18; color: #edf4ff; }
    #|      * { box-sizing: border-box; }
    #|      body { margin: 0; min-height: 100vh; background: #080c18; background-image: linear-gradient(#15213a66 1px, transparent 1px), linear-gradient(90deg, #15213a66 1px, transparent 1px); background-size: 32px 32px; }
    #|      button, textarea { font: inherit; }
    #|      main { width: min(1080px, calc(100vw - 40px)); margin: 0 auto; padding: 36px 0 48px; }
    #|      header { display: flex; align-items: end; justify-content: space-between; gap: 24px; margin-bottom: 24px; }
    #|      .eyebrow { margin: 0 0 7px; color: #67e8f9; font: 700 11px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; }
    #|      h1 { margin: 0; font-size: clamp(29px, 5vw, 50px); line-height: .98; letter-spacing: -.045em; }
    #|      .summary { max-width: 510px; margin: 12px 0 0; color: #9eb0ca; line-height: 1.55; }
    #|      .badge { flex: none; border: 1px solid #1d4ed8; border-radius: 999px; padding: 8px 12px; background: #172554cc; color: #bfdbfe; font: 700 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .layout { display: grid; grid-template-columns: minmax(0, 1.65fr) minmax(270px, .8fr); gap: 16px; }
    #|      .panel { border: 1px solid #24324d; border-radius: 16px; background: #0c1324e8; box-shadow: 0 24px 70px #02061780; overflow: hidden; }
    #|      .panel-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; min-height: 49px; padding: 0 18px; border-bottom: 1px solid #24324d; color: #9eb0ca; font: 650 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .panel-head strong { color: #dbeafe; font-weight: 700; }
    #|      #surface { position: relative; min-height: 350px; padding: 26px; overflow: hidden; background: radial-gradient(circle at 50% 44%, #19396b 0, #101c36 38%, #0a1121 72%); }
    #|      #surface::before, #surface::after { content: ""; position: absolute; background: #5eead41f; pointer-events: none; }
    #|      #surface::before { inset: 0 50%; width: 1px; }
    #|      #surface::after { inset: 50% 0; height: 1px; }
    #|      .surface-copy { position: relative; z-index: 1; max-width: 450px; }
    #|      .surface-copy h2 { margin: 0 0 8px; font-size: 22px; letter-spacing: -.02em; }
    #|      .surface-copy p { margin: 0; color: #9eb0ca; line-height: 1.55; }
    #|      .selection-label { display: block; margin: 27px 0 8px; color: #67e8f9; font: 700 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .12em; }
    #|      textarea { position: relative; z-index: 1; width: min(100%, 480px); min-height: 86px; resize: none; border: 1px solid #36527e; border-radius: 10px; padding: 13px 14px; outline: none; background: #081121dd; color: #e0f2fe; line-height: 1.45; }
    #|      textarea:focus { border-color: #22d3ee; box-shadow: 0 0 0 3px #22d3ee26; }
    #|      #marker { position: absolute; z-index: 3; width: 18px; height: 18px; margin: -9px 0 0 -9px; border: 1px solid #fbbf24; border-radius: 50%; box-shadow: 0 0 0 4px #fbbf2424, 0 0 24px #f59e0b; opacity: 0; pointer-events: none; transition: opacity 120ms ease; }
    #|      #marker::before, #marker::after { content: ""; position: absolute; background: #fbbf24; }
    #|      #marker::before { left: 8px; top: -7px; width: 1px; height: 30px; }
    #|      #marker::after { left: -7px; top: 8px; width: 30px; height: 1px; }
    #|      #marker.visible { opacity: 1; }
    #|      .controls { display: flex; align-items: center; gap: 12px; padding: 15px 18px; border-top: 1px solid #24324d; }
    #|      button { min-height: 44px; border: 1px solid #2563eb; border-radius: 9px; padding: 0 15px; background: #1d4ed8; color: white; font-weight: 750; cursor: pointer; transition: transform 140ms ease, background 140ms ease; }
    #|      button:hover { background: #2563eb; }
    #|      button:active { transform: translateY(1px); }
    #|      button:focus-visible { outline: 3px solid #67e8f980; outline-offset: 2px; }
    #|      #status { min-width: 0; color: #a8bad2; font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; overflow-wrap: anywhere; }
    #|      .review { padding: 18px; }
    #|      .review h2 { margin: 0 0 14px; font-size: 16px; }
    #|      .checklist { display: grid; gap: 11px; margin: 0; padding: 0; list-style: none; counter-reset: review; }
    #|      .checklist li { position: relative; padding-left: 32px; color: #a8bad2; font-size: 13px; line-height: 1.45; counter-increment: review; }
    #|      .checklist li::before { content: counter(review); position: absolute; left: 0; top: 0; display: grid; place-items: center; width: 21px; height: 21px; border: 1px solid #36527e; border-radius: 6px; color: #67e8f9; font: 700 10px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      .log-title { margin-top: 23px; padding-top: 18px; border-top: 1px solid #24324d; }
    #|      #log { display: grid; gap: 7px; max-height: 152px; margin: 0; padding: 0; overflow: auto; list-style: none; }
    #|      #log li { border-left: 2px solid #22d3ee; padding: 7px 9px; background: #101b31; color: #c7d8ed; font: 11px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|      #log li.empty { border-color: #475569; color: #71829b; }
    #|      @media (max-width: 780px) { header { align-items: start; flex-direction: column; } .layout { grid-template-columns: 1fr; } #surface { min-height: 320px; } }
    #|      @media (prefers-reduced-motion: reduce) { *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; } }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <main>
    #|      <header>
    #|        <div>
    #|          <p class="eyebrow">Native surface / manual test 58</p>
    #|          <h1>Context menu<br>coordinate lab</h1>
    #|          <p class="summary">Review Proton's Electron-style <code>Menu.popup(window, x, y)</code> path: native placement, nested items, role actions, and renderer command events.</p>
    #|        </div>
    #|        <div class="badge">CSS PX · TOP LEFT</div>
    #|      </header>
    #|      <div class="layout">
    #|        <section class="panel">
    #|          <div class="panel-head"><strong>INTERACTION SURFACE</strong><span>right-click anywhere below</span></div>
    #|          <div id="surface" tabindex="0">
    #|            <div id="marker" aria-hidden="true"></div>
    #|            <div class="surface-copy">
    #|              <h2>Place the native menu precisely</h2>
    #|              <p>The amber crosshair records the exact <code>clientX/clientY</code> pair sent to MoonBit.</p>
    #|              <label class="selection-label" for="selection">Role action target</label>
    #|              <textarea id="selection">Focus this text, right-click inside it, then choose More → Select All.</textarea>
    #|            </div>
    #|          </div>
    #|          <div class="controls">
    #|            <button id="open" type="button">Open at surface center</button>
    #|            <div id="status" role="status" aria-live="polite">Waiting for a context-menu request.</div>
    #|          </div>
    #|        </section>
    #|        <aside class="panel review">
    #|          <h2>Manual review</h2>
    #|          <ol class="checklist">
    #|            <li>Right-click near each edge. The menu origin should follow the amber marker and stay on-screen.</li>
    #|            <li>Choose <strong>Inspect Coordinates</strong>. A <code>menu.command</code> entry should appear below.</li>
    #|            <li>Open <strong>More</strong> and choose <strong>More Action</strong> to verify nested command routing.</li>
    #|            <li>Focus the text field, right-click inside it, then choose <strong>More → Select All</strong>.</li>
    #|            <li>Use the button and confirm the popup opens at the surface crosshair.</li>
    #|          </ol>
    #|          <h2 class="log-title">Event log</h2>
    #|          <ol id="log"><li class="empty">No menu commands received yet.</li></ol>
    #|        </aside>
    #|      </div>
    #|    </main>
    #|    <script>
    #|      const status = document.querySelector("#status");
    #|      const surface = document.querySelector("#surface");
    #|      const marker = document.querySelector("#marker");
    #|      const log = document.querySelector("#log");
    #|      let lastPoint = { x: 0, y: 0 };
    #|      const invoke = (payload) => window.__MoonBit__.core.invokeOp("ext:contextMenu/show", payload);
    #|      function record(message) {
    #|        log.querySelector(".empty")?.remove();
    #|        const item = document.createElement("li");
    #|        item.textContent = message;
    #|        log.prepend(item);
    #|      }
    #|      function placeMarker(x, y) {
    #|        const rect = surface.getBoundingClientRect();
    #|        marker.style.left = `${x - rect.left}px`;
    #|        marker.style.top = `${y - rect.top}px`;
    #|        marker.classList.add("visible");
    #|      }
    #|      async function openMenu(x, y) {
    #|        lastPoint = { x, y };
    #|        placeMarker(x, y);
    #|        status.textContent = `Requesting native popup at (${x}, ${y})...`;
    #|        try {
    #|          const reply = await invoke({ x, y });
    #|          status.textContent = reply.message;
    #|        } catch (error) {
    #|          status.textContent = `request failed: ${String(error)}`;
    #|        }
    #|      }
    #|      surface.addEventListener("contextmenu", (event) => {
    #|        event.preventDefault();
    #|        void openMenu(Math.round(event.clientX), Math.round(event.clientY));
    #|      });
    #|      document.querySelector("#open").addEventListener("click", () => {
    #|        const rect = surface.getBoundingClientRect();
    #|        void openMenu(Math.round(rect.left + rect.width / 2), Math.round(rect.top + rect.height / 2));
    #|      });
    #|      window.__MoonBit__.events.on("menu.command", (event) => {
    #|        const command = event.payload.command_id;
    #|        const message = `${command} received for popup (${lastPoint.x}, ${lastPoint.y})`;
    #|        status.textContent = message;
    #|        record(message);
    #|      });
    #|    </script>
    #|  </body>
    #|</html>
  )
}

///|
async fn main {
  @proton.html("Context Menu", html(), width=900, height=680, debug=true)
  .identifier("dev.proton.context-menu")
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
