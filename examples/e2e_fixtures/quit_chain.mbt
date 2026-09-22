///|
let quit_chain_application : Ref[@proton.ApplicationContext?] = Ref(None)

///|
fn quit_chain_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
fn quit_chain_log(line : String) -> Unit {
  let path = quit_chain_env("PROTON_QUIT_CHAIN_LOG")
  guard path != "" else { return }
  let previous = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => ""
  }
  @mbfs.write_string_to_file(path, previous + line + "\n") catch {
    _ => ()
  }
}

///|
/// Exercises the application quit chain in an isolated headless application.
///
/// The harness waits for `PROTON_QUIT_CHAIN_READY` and then creates
/// `PROTON_QUIT_CHAIN_GATE`, so the quit request always happens after the
/// primary window exists. Supported modes are `quit0`, `quit3`, `exit7`,
/// `prevent-before-quit`, and `prevent-will-quit`.
pub async fn run_quit_chain() -> Unit {
  let mode = quit_chain_env("PROTON_QUIT_CHAIN_MODE")
  let gate = quit_chain_env("PROTON_QUIT_CHAIN_GATE")
  let ready = quit_chain_env("PROTON_QUIT_CHAIN_READY")
  let prevents_before_quit = mode == "prevent-before-quit"
  let prevents_will_quit = mode == "prevent-will-quit"
  @proton.html("Quit chain", "<h1>Quit chain</h1>")
  .identifier("dev.proton.e2e-quit-chain")
  .app_lifecycle(
    on_start=context => {
      quit_chain_application.val = Some(context)
      context
    },
    on_shutdown=fn(_) { () },
  )
  .on_before_quit(fn(_context) {
    quit_chain_log("before-quit")
    if prevents_before_quit {
      @proton.ApplicationQuitDecision::Prevent
    } else {
      @proton.ApplicationQuitDecision::Allow
    }
  })
  .on_will_quit(fn(_context) {
    quit_chain_log("will-quit")
    if prevents_will_quit {
      @proton.ApplicationQuitDecision::Prevent
    } else {
      @proton.ApplicationQuitDecision::Allow
    }
  })
  .on_quit(fn(_context, exit_code) {
    quit_chain_log("quit " + exit_code.to_string())
  })
  .window_lifecycle(
    on_ready=context => {
      @mbfs.write_string_to_file(ready, "ready") catch {
        _ => ()
      }
      ignore(
        context
        .task_group()
        .spawn(
          () => {
            while !@mbfs.path_exists(gate) {
              @async.sleep(10)
            }
            // Let primary window activation finish before the quit chain closes
            // the window again.
            @async.sleep(200)
            match quit_chain_application.val {
              Some(application) =>
                match mode {
                  "quit3" => application.quit(exit_code=3)
                  "exit7" => application.exit(exit_code=7)
                  _ => application.quit()
                }
              None => ()
            }
          },
          no_wait=true,
        ),
      )
    },
    on_close=fn(_) { () },
  )
  .run_or_abort()
}
