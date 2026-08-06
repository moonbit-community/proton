///|
/// Runs `main` on Proton's event loop from a synchronous entry point.
///
/// An application does not need this. Proton installs its event loop during
/// process initialization, so an application is a plain `async fn main`:
///
/// ```moonbit skip
/// async fn main {
///   @proton.app().run_or_abort()
/// }
/// ```
///
/// This exists for a host that does not own the process entry point -- a test
/// harness, for one -- and so cannot make `main` async.
pub fn run(main : async () -> Unit) -> Unit {
  @async.run_async_main(main)
}
