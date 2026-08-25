///|
let page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Background Residency</title>
  #|    <style>
  #|      body {
  #|        max-width: 680px;
  #|        margin: 48px auto;
  #|        padding: 0 24px;
  #|        font: 16px/1.6 system-ui;
  #|        color: #17212b;
  #|      }
  #|      h1 { font-size: 28px; }
  #|      code { padding: 2px 6px; background: #f3f5f7; border-radius: 4px; }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <h1>Background Residency</h1>
  #|    <p>
  #|      Close this window. The application process stays alive without any
  #|      open windows.
  #|    </p>
  #|    <p>
  #|      Launch the same application again to send <code>Reopen</code> to the
  #|      existing process and create a new main window.
  #|    </p>
  #|    <p>
  #|      Use the platform Quit action, or stop the development command, to end
  #|      the background process.
  #|    </p>
  #|  </body>
  #|</html>

///|
async fn main {
  @proton.html("Background Residency", page, width=760, height=480)
  .identifier("com.example.proton.background-residency")
  .single_instance()
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .on_launch_input(async fn(context, input) noraise {
    if input is Reopen && context.windows().find("main") is None {
      ignore(context.windows().open("main")) catch {
        error => println("failed to reopen main window: " + error.message())
      }
    }
  })
  .run_or_abort()
}
