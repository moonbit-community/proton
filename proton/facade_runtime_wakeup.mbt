///|
priv struct RuntimeWakeup {
  reader : @pipe.PipeRead
  writer : @pipe.PipeWrite
  signal : @core.RuntimeWakeSignal
  caller_pumps_runtime : Bool
  mut closed : Bool
}

///|
fn RuntimeWakeup::new(
  runtime : @native.Runtime,
) -> RuntimeWakeup raise AppRunError {
  let caller_pumps_runtime = match @native.runtime_info() {
    Err(error) => raise native_run_error("read native runtime features", error)
    Ok(info) => !info.features.contains("managed_app_runner")
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
    caller_pumps_runtime,
    closed: false,
  }
}

///|
/// Advances CEF only when the facade owns its external message pump.
fn RuntimeWakeup::pump(
  self : RuntimeWakeup,
  runtime : @native.Runtime,
) -> Result[Unit, @native.NativeError] {
  if self.caller_pumps_runtime {
    runtime.do_message_loop_work()
  } else {
    Ok(())
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
async fn RuntimeWakeup::wait(
  self : RuntimeWakeup,
  runtime : @native.Runtime,
) -> Unit raise AppRunError {
  while true {
    let revision = self.signal.revision()
    let delay = if self.caller_pumps_runtime {
      match runtime.next_wakeup_delay_ms() {
        Err(error) => raise native_run_error("read runtime wakeup delay", error)
        Ok(delay) => delay
      }
    } else {
      None
    }
    if delay is Some(0) {
      return
    }

    let waiters : Array[async () -> Bool] = [
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
    ]
    match delay {
      None => {
        let ready = @async.any(waiters) catch {
          error => raise normalize_async_run_error(error)
        }
        if ready {
          return
        }
      }
      Some(delay) => {
        waiters.push(() => {
          @async.sleep(delay)
          true
        })
        let ready = @async.any(waiters) catch {
          error => raise normalize_async_run_error(error)
        }
        if ready {
          return
        }
      }
    }
  }
}
