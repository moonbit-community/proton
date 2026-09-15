///|
async fn main {
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
  .window_lifecycle(
    on_ready=context => {
      let window = context.handle()
      context
      .task_group()
      .spawn(
        () => {
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
          window.browser().eval("window.close()")
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
