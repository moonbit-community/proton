///|
/// Runs one async op callback inside the MoonBit async event loop.
fn run_async_task(callback : async () -> Unit) -> Unit {
  @async.run_async_main(callback)
}
