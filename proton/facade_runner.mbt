///|
/// Starts Proton's event loop and runs `main` on it.
///
/// An application should not use this. Write a plain `async fn main` and call
/// `install_event_loop` as its first statement instead:
///
/// ```moonbit skip
/// async fn main {
///   @proton.install_event_loop()
///   @proton.app().run_or_abort()
/// }
/// ```
///
/// This exists for a host that does not own the process entry point -- a test
/// harness, for one -- and so cannot make `main` async. Aborts on failure,
/// because a caller in that position has nowhere to report to.
pub fn run(main : async () -> Unit) -> Unit {
  install_event_loop() catch {
    error => abort("Proton event loop failed to start: " + error.message())
  }
  @async.run_async_main(main)
}
