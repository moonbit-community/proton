///|
let page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Application Activation</title>
  #|    <style>
  #|      body { font: 16px system-ui; margin: 32px; color: #17212b; }
  #|      h1 { font-size: 24px; }
  #|      pre { padding: 16px; background: #f3f5f7; border-radius: 6px; }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <h1>Application Activation</h1>
  #|    <pre id="activity">Primary instance running.</pre>
  #|  </body>
  #|</html>

///|
async fn main {
  @proton.html("Application Activation", page, width=760, height=480)
  .single_instance("com.example.proton.activation")
  .url_scheme("proton-example")
  .document_extension("proton-example")
  .last_window_closed_policy(@proton.LastWindowClosedPolicy::KeepRunning)
  .on_launch_input(async fn(context, input) noraise {
    println("activation: " + @debug.render(Repr(input)))
    if input is Reopen && context.windows().find("main") is None {
      ignore(context.windows().open("main")) catch {
        error => println("failed to reopen main window: " + error.message())
      }
    }
  })
  .run_or_abort()
}
