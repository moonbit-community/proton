///|
priv struct RuntimeWakeup {
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
  signal : @core.RuntimeWakeSignal
  mut closed : Bool
}

///|
fn RuntimeWakeup::new(
  runtime : @native.Runtime,
) -> RuntimeWakeup raise AppRunError {
  let runtime_info = match @native.runtime_info() {
    Err(error) => raise native_run_error("read native runtime features", error)
    Ok(info) => info
  }
  if !runtime_info.features.contains("managed_app_runner") ||
    !runtime_info.features.contains("runtime_wakeup_fd") {
    raise NativeRuntimeError({
      status: -8,
      message: "the Proton app facade requires managed_app_runner and runtime_wakeup_fd support",
    })
  }
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
    reader,
    writer,
    signal: @core.RuntimeWakeSignal::new(),
    closed: false,
  }
}

///|
fn RuntimeWakeup::close(self : RuntimeWakeup) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.reader.close()
  self.writer.close()
}

///|
async fn RuntimeWakeup::wait(self : RuntimeWakeup) -> Unit raise AppRunError {
  let revision = self.signal.revision()
  let ready = @async.any([
    () => {
      match self.reader.read_some(max_len=256) {
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
