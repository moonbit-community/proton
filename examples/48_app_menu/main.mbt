///|
fn menu_bar() -> @proton.MenuBar {
  @proton.MenuBar::new(menus=[
    @proton.Menu::new("Demo", items=[
      @proton.MenuItem::command("demo.refresh", "Refresh Status", key="r"),
      @proton.MenuItem::command("demo.settings", "Open Settings", key=","),
      @proton.MenuItem::separator(),
      @proton.MenuItem::role("close", label="Close Window", key="w"),
    ]),
    @proton.Menu::new("Help", items=[
      @proton.MenuItem::command("help.about", "About Menu Example"),
    ]),
  ])
}

///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head>
    #|    <meta charset="utf-8">
    #|    <title>App Menu</title>
    #|    <style>
    #|      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px; color: #1f2937; }
    #|      h1 { margin: 0 0 12px; font-size: 34px; }
    #|      p { max-width: 720px; line-height: 1.5; }
    #|      #status { margin-top: 24px; padding: 18px 20px; border: 1px solid #cbd5e1; border-radius: 8px; background: #f8fafc; font-size: 18px; }
    #|      code { background: #e2e8f0; border-radius: 4px; padding: 2px 5px; }
    #|    </style>
    #|  </head>
    #|  <body>
    #|    <h1>App Menu</h1>
    #|    <p>Use the macOS menu bar. The <code>Demo</code> and <code>Help</code> menus are installed through the Proton facade menu API.</p>
    #|    <div id="status">Waiting for a menu command.</div>
    #|    <script>
    #|      window.__MoonBit__.events.on("menu.command", function(event) {
    #|        document.getElementById("status").textContent =
    #|          "Menu command: " + event.payload.command_id;
    #|      });
    #|    </script>
    #|  </body>
    #|</html>

  @proton.html("App Menu", html, width=900, height=640, debug=true)
  .menu(menu_bar())
  .run_or_abort()
}
