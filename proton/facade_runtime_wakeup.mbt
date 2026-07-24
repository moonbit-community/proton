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
  let runtime_info = @native.runtime_info() catch {
    error => raise native_run_error("read native runtime features", error)
  }
  if !runtime_info.features.contains("managed_app_runner") ||
    !runtime_info.features.contains(feature) {
    raise RuntimeWakeupError(UnsupportedFeature(feature~))
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
      raise RuntimeWakeupError(
        PipeCreateFailed(detail=@debug.render(@debug.to_repr(error))),
      )
  }
  runtime.set_wakeup_fd(writer.fd()) catch {
    error => {
      reader.close()
      writer.close()
      raise native_run_error("install runtime wakeup fd", error)
    }
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
  let source = runtime.prepare_wakeup_source() catch {
    error => raise native_run_error("prepare runtime wakeup source", error)
  }
  let reader = @fs.open(source, mode=@fs.ReadOnly) catch {
    error =>
      raise RuntimeWakeupError(
        SourceOpenFailed(source~, detail=@debug.render(@debug.to_repr(error))),
      )
  }
  runtime.activate_wakeup_source() catch {
    error => {
      reader.close()
      raise native_run_error("activate runtime wakeup source", error)
    }
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
        None => raise RuntimeWakeupError(SourceClosed)
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
  raise RuntimeWakeupError(MissingNotification)
}
