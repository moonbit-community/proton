///|
#cfg(not(platform="windows"))
priv struct RuntimeWakeReader(@pipe.PipeRead)

///|
#cfg(platform="windows")
priv struct RuntimeWakeReader(@fs.File)

///|
priv struct RuntimeWakeup {
  reader : RuntimeWakeReader
  writer : @pipe.PipeWrite?
  signal : @core.RuntimeWakeSignal
  mut closed : Bool
}

///|
fn require_runtime_wakeup_feature(feature : String) -> Unit raise AppRunError {
  let runtime_info = match @native.runtime_info() {
    Err(error) => raise native_run_error("read native runtime features", error)
    Ok(info) => info
  }
  if !runtime_info.features.contains("managed_app_runner") ||
    !runtime_info.features.contains(feature) {
    raise NativeRuntimeError({
      status: -8,
      message: "the Proton app facade requires managed_app_runner and a runtime wakeup source",
    })
  }
}

///|
#cfg(not(platform="windows"))
fn RuntimeWakeup::new(
  runtime : @native.Runtime,
) -> RuntimeWakeup raise AppRunError {
  require_runtime_wakeup_feature("runtime_wakeup_fd")
  let (reader, writer) = @pipe.pipe() catch {
    error =>
      raise NativeRuntimeError({
        status: -6,
        message: "create runtime wakeup pipe failed: " +
        @debug.render(@debug.to_repr(error)),
      })
  }
  match runtime.set_wakeup_fd(writer.fd()) {
    Err(error) => {
      reader.close()
      writer.close()
      raise native_run_error("install runtime wakeup fd", error)
    }
    Ok(_) => ()
  }
  RuntimeWakeup::{
    reader: RuntimeWakeReader(reader),
    writer: Some(writer),
    signal: @core.RuntimeWakeSignal::new(),
    closed: false,
  }
}

///|
// Windows async pipes use overlapped handles owned by MoonBit's IOCP loop.
// Keep the native writer independent and open its named pipe as a normal
// file so blocking reads are delegated by the async filesystem runtime.
#cfg(platform="windows")
async fn RuntimeWakeup::new(
  runtime : @native.Runtime,
) -> RuntimeWakeup raise AppRunError {
  require_runtime_wakeup_feature("runtime_wakeup_source")
  let source = match runtime.prepare_wakeup_source() {
    Err(error) => raise native_run_error("prepare runtime wakeup source", error)
    Ok(source) => source
  }
  let reader = @fs.open(source, mode=@fs.ReadOnly) catch {
    error =>
      raise NativeRuntimeError({
        status: -6,
        message: "open runtime wakeup source failed: " +
        @debug.render(@debug.to_repr(error)),
      })
  }
  match runtime.activate_wakeup_source() {
    Err(error) => {
      reader.close()
      raise native_run_error("activate runtime wakeup source", error)
    }
    Ok(_) => ()
  }
  RuntimeWakeup::{
    reader: RuntimeWakeReader(reader),
    writer: None,
    signal: @core.RuntimeWakeSignal::new(),
    closed: false,
  }
}

///|
fn RuntimeWakeup::close(self : RuntimeWakeup) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  let RuntimeWakeReader(reader) = self.reader
  reader.close()
  match self.writer {
    Some(writer) => writer.close()
    None => ()
  }
}

///|
async fn RuntimeWakeup::wait(self : RuntimeWakeup) -> Unit raise AppRunError {
  let revision = self.signal.revision()
  let RuntimeWakeReader(reader) = self.reader
  let ready = @async.any([
    () => {
      let bytes = reader.read_some(max_len=256)
      match bytes {
        None =>
          raise NativeRuntimeError({
            status: -6,
            message: "runtime wakeup pipe closed unexpectedly",
          })
        Some(_) => {
          self.signal.notify()
          true
        }
      }
    },
    () => {
      self.signal.wait_for_change(revision)
      true
    },
  ]) catch {
    error => raise normalize_async_run_error(error)
  }
  if ready {
    return
  }
  raise NativeRuntimeError({
    status: -6,
    message: "runtime wakeup wait completed without a notification",
  })
}
