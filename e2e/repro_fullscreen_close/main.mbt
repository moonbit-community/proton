///|
async fn main {
  let args = @env.args()
  let child_count = if args.contains("--views=2") {
    2
  } else if args.contains("--views=1") {
    1
  } else {
    0
  }
  let loaded = Ref(0)
  let runtime = @cef_store.resolve_default()
  @env.set_env_var("PROTON_RUNTIME_ROOT", runtime.runtime_root())
  @proton.html(
    "Fullscreen Close Reproduction",
    "<h1>Fullscreen close reproduction</h1><p>This window will enter fullscreen, exit fullscreen, then call window.close(). See the terminal for the result.</p>",
    width=800,
    height=520,
  )
  .titlebar_style(Overlay)
  .identifier("dev.proton.repro-fullscreen-close")
  .on_view_event(fn(_, event) noraise {
    if event is DidFinishLoad {
      loaded.val += 1
    }
  })
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      let views = Array::makei(child_count, i => {
        window.add_view(
          "child-\{i}",
          @proton.view(
            "data:text/html,<title>Child</title><h1>Close regression</h1>",
            x=20 + i * 240,
            y=150,
            width=220,
            height=200,
          ),
        )
      })
      context
      .task_group()
      .spawn(
        () => {
          while loaded.val < child_count {
            @async.sleep(10)
          }
          if args.contains("--show-inactive") {
            window.hide()
            window.show_inactive()
          }
          if args.contains("--refocus") {
            window.hide()
            window.focus()
          }
          if args.contains("--close-child-first") {
            for view in views {
              view.close()
            }
          }
          @async.sleep(1500)
          if !@env.args().contains("--direct-close") {
            println("REPRO: enter fullscreen")
            if @env.args().contains("--kiosk") {
              window.set_kiosk(true)
            } else {
              window.set_fullscreen(true)
            }
            @async.sleep(3000)
            guard window.is_fullscreen() else {
              abort("window did not enter fullscreen")
            }
            println("REPRO: exit fullscreen")
            if @env.args().contains("--kiosk") {
              window.set_kiosk(false)
            } else if @env.args().contains("--restore") {
              window.restore()
            } else {
              window.set_fullscreen(false)
            }
            @async.sleep(3000)
            guard !window.is_fullscreen() else {
              abort("window did not exit fullscreen")
            }
          }
          println("REPRO: window.close()")
          if args.contains("--native-close") {
            window.close()
          } else {
            window.browser().eval("window.close()")
          }
        },
        no_wait=true,
      )
      |> ignore
    },
    on_close=fn(_) { println("REPRO: window closed") },
  )
  .run_or_abort()
  println("REPRO: application exited normally")
}
