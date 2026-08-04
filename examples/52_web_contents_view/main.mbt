///|
let main_page =
  #|<!doctype html>
  #|<html>
  #|  <head>
  #|    <meta charset="utf-8" />
  #|    <title>Web Contents View</title>
  #|    <style>
  #|      body { font-family: -apple-system, sans-serif; margin: 24px; }
  #|      code { background: #f0f0f0; padding: 2px 6px; border-radius: 4px; }
  #|    </style>
  #|  </head>
  #|  <body>
  #|    <h1>Web Contents View</h1>
  #|    <p>
  #|      This window hosts two web contents views below, each backed by its own
  #|      native browser — the Electron <code>WebContentsView</code> model.
  #|    </p>
  #|    <p>
  #|      The demo moves the left view, swaps the stacking order, toggles
  #|      visibility, and navigates a view while the app runs.
  #|    </p>
  #|  </body>
  #|</html>
  #|

///|
let left_page_url = "data:text/html,<body style='margin:0;background:rgb(226,246,228);font-family:sans-serif'><h1 style='padding:24px'>Left view</h1></body>"

///|
let right_page_url = "data:text/html,<body style='margin:0;background:rgb(226,236,250);font-family:sans-serif'><h1 style='padding:24px'>Right view</h1></body>"

///|
let reloaded_page_url = "data:text/html,<body style='margin:0;background:rgb(250,240,220);font-family:sans-serif'><h1 style='padding:24px'>Right view reloaded</h1></body>"

///|
fn view_ids(window : @proton.WindowHandle) -> String {
  window.views().map(fn(view) { view.id() }).join(", ")
}

///|
async fn demo_views(window : @proton.WindowHandle) -> Unit {
  let left = window.add_view(
    "left",
    @native.ViewConfig::new(
      width=460,
      height=250,
      x=10,
      y=380,
      initial_url=left_page_url,
    ),
  )
  let right = window.add_view(
    "right",
    @native.ViewConfig::new(
      width=460,
      height=250,
      x=490,
      y=380,
      initial_url=right_page_url,
    ),
  )
  println("views: \{view_ids(window)}")

  @async.sleep(2000)
  // Electron-style setBounds: top-left origin inside the window content area.
  left.set_bounds(60, 340, 460, 290)
  left.set_z_order(1)
  let state = left.state()
  println(
    "left state: x=\{state.x} y=\{state.y} width=\{state.width} height=\{state.height} visible=\{state.visible} z=\{state.z_order}",
  )

  @async.sleep(2000)
  right.set_visible(false)

  @async.sleep(2000)
  right.set_visible(true)
  right.load_url(reloaded_page_url)

  @async.sleep(2000)
  window.remove_view("left")
  println("views after remove: \{view_ids(window)}")
}

///|
fn main {
  @proton.run(() => {
    @proton.html(
      "Web Contents View",
      main_page,
      width=960,
      height=640,
      debug=true,
    )
    .window_lifecycle(
      on_ready=async fn(context) {
        demo_views(context.handle()) catch {
          error => println("view demo failed: \{error}")
        }
      },
      on_close=fn(_state) {  },
    )
    .run_or_abort()
  })
}
