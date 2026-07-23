///|
priv enum RuntimeWakeReader {
  Pipe(@pipe.PipeRead)
  File(@fs.File)
}

///|
priv struct RuntimeWakeup {
  reader : RuntimeWakeReader
  writer : @pipe.PipeWrite?
  signal : @core.RuntimeWakeSignal
  mut closed : Bool
}

///|
async fn RuntimeWakeup::new(
  runtime : @native.Runtime,
) -> RuntimeWakeup raise AppRunError {
  let runtime_info = match @native.runtime_info() {
    Err(error) => raise native_run_error("read native runtime features", error)
    Ok(info) => info
  }
  let has_wakeup_fd = runtime_info.features.contains("runtime_wakeup_fd")
  let has_wakeup_source = runtime_info.features.contains(
    "runtime_wakeup_source",
  )
  if !runtime_info.features.contains("managed_app_runner") ||
    (!has_wakeup_fd && !has_wakeup_source) {
    raise NativeRuntimeError({
      status: -8,
      message: "the Proton app facade requires managed_app_runner and a runtime wakeup source",
    })
  }
  if has_wakeup_fd {
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
    return RuntimeWakeup::{
      reader: Pipe(reader),
      writer: Some(writer),
      signal: @core.RuntimeWakeSignal::new(),
      closed: false,
    }
  }
  // Windows async pipes use overlapped handles owned by MoonBit's IOCP loop.
  // Keep the native writer independent and open its named pipe as a normal
  // file so blocking reads are delegated by the async filesystem runtime.
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
    reader: File(reader),
    writer: None,
    signal: @core.RuntimeWakeSignal::new(),
    closed: false,
  }
}

///|
fn RuntimeWakeup::close(self : RuntimeWakeup) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  match self.reader {
    Pipe(reader) => reader.close()
    File(reader) => reader.close()
  }
  match self.writer {
    Some(writer) => writer.close()
    None => ()
  }
}

///|
async fn RuntimeWakeup::wait(self : RuntimeWakeup) -> Unit raise AppRunError {
  let revision = self.signal.revision()
  let ready = @async.any([
    () => {
      let bytes = match self.reader {
        Pipe(reader) => reader.read_some(max_len=256)
        File(reader) => reader.read_some(max_len=256)
      }
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
