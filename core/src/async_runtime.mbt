///|
priv type NativeAsyncExecutor

///|
#borrow(executor)
#owned(callback)
extern "C" fn native_async_executor_submit(
  executor : NativeAsyncExecutor,
  callback : async () -> Unit,
) -> Bool = "lepus_core_async_executor_submit"

///|
extern "C" fn native_async_executor_new(
  call_closure : FuncRef[(async () -> Unit) -> Unit],
  worker_count : Int,
) -> NativeAsyncExecutor = "lepus_core_async_executor_new"

///|
#borrow(executor)
extern "C" fn native_async_executor_close(
  executor : NativeAsyncExecutor,
) -> Unit = "lepus_core_async_executor_close"

///|
priv struct AsyncExecutor {
  native : NativeAsyncExecutor
  mut closed : Bool
}

///|
/// Creates a shared async runner pool for one op runtime.
///
/// Each submitted job runs inside a MoonBit async event loop on one worker
/// thread. This keeps webview callbacks short and gives async extension ops a
/// stable execution home without exposing native threads to extension authors.
fn AsyncExecutor::new(worker_count? : Int = 4) -> AsyncExecutor {
  let native = native_async_executor_new(
    fn(callback) { @async.run_async_main(callback) },
    worker_count,
  )
  AsyncExecutor::{ native, closed: false }
}

///|
/// Submits one async job to the executor.
///
/// The callback is owned by the native queue after this call. If the executor is
/// already closed or cannot accept the job, the callback is released natively
/// and `false` is returned.
fn AsyncExecutor::submit(
  self : AsyncExecutor,
  callback : async () -> Unit,
) -> Bool {
  guard !self.closed else { return false }
  native_async_executor_submit(self.native, callback)
}

///|
/// Stops accepting jobs and waits for already-running async jobs to finish.
fn AsyncExecutor::close(self : AsyncExecutor) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  native_async_executor_close(self.native)
}
