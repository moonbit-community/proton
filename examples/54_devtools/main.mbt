///|
let page =
  #|<!doctype html>
  #|<html lang="en">
  #|  <head>
  #|    <meta charset="utf-8">
  #|    <meta name="viewport" content="width=device-width, initial-scale=1">
  #|    <title>Proton DevTools API</title>
  #|    <style>
  #|      :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
  #|      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #111827; color: #f9fafb; }
  #|      main { width: min(680px, calc(100vw - 64px)); padding: 40px; border: 1px solid #374151; border-radius: 20px; background: #1f2937; box-shadow: 0 24px 60px #0006; }
  #|      h1 { margin-top: 0; font-size: 32px; }
  #|      code { color: #93c5fd; }
  #|      li { margin: 12px 0; line-height: 1.5; }
  #|      .status { display: inline-block; padding: 6px 10px; border-radius: 999px; background: #064e3b; color: #a7f3d0; font-size: 13px; }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <main>
  #|      <span class="status">open_devtools called</span>
  #|      <h1 id="probe-title">Proton DevTools API</h1>
  #|      <p>This example calls <code>BrowserHandle::open_devtools()</code> when the main window becomes ready.</p>
  #|      <ol>
  #|        <li>Confirm that a separate DevTools window opened automatically.</li>
  #|        <li>Use the Elements panel to inspect <code>#probe-title</code>.</li>
  #|        <li>Close DevTools and confirm that this window remains open.</li>
  #|      </ol>
  #|    </main>
  #|  </body>
  #|</html>
  #|

///|
fn main {
  @proton.run(() => {
    @proton.html("DevTools API", page, width=900, height=700, debug=true)
    .window_lifecycle(
      on_ready=context => {
        let browser = context.handle().browser()
        browser.open_devtools()
        browser
      },
      on_close=fn(browser) { browser.close_devtools() catch { _ => () } },
    )
    .run_or_abort()
  })
}
