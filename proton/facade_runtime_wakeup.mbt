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
async fn RuntimeWakeup::wait(
  self : RuntimeWakeup,
  runtime : @native.Runtime,
) -> Unit raise AppRunError {
  while true {
    let revision = self.signal.revision()
    let delay = match runtime.next_wakeup_delay_ms() {
      Err(error) => raise native_run_error("read runtime wakeup delay", error)
      Ok(delay) => delay
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
