///|
let app_main : Ref[(async () -> Unit)?] = Ref(None)

///|
fn app_runner_is_active() -> Bool {
  app_main.val is Some(_)
}

///|
fn app_thread_entry() -> Unit {
  match app_main.val {
    Some(main) => @async.run_async_main(main)
    None => abort("Proton application entry is not installed")
  }
}

///|
/// Runs a Proton application with the platform UI loop on the process main
/// thread and MoonBit async work on Proton's application thread.
///
/// Call this once from a synchronous `main`.
pub fn run(main : async () -> Unit) -> Unit {
  guard app_main.val is None else {
    abort("Proton application runner is already active")
  }
  app_main.val = Some(main)
  let entry : FuncRef[() -> Unit] = fn() { app_thread_entry() }
  @native.run_app(entry) catch {
    error => {
      app_main.val = None
      abort(
        "run Proton application failed: native error " +
        error.status().to_string() +
        ": " +
        error.message(),
      )
    }
  }
  app_main.val = None
}
