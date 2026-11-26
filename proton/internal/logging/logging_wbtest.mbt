///|
priv struct CaptureHandler {
  messages : Array[Json]
}

///|
impl @xlog.Handler for CaptureHandler with fn handle(self, entry) {
  self.messages.push(entry.fields.get("message").unwrap())
}

///|
suberror LoggingProbeError {
  Failed(String)
}

///|
fn run_logging_probe(path : String, fail~ : Bool) -> Unit raise {
  configure(Output::File(path))
  if @xlog.warn(category="proton.test") is Some(w) {
    w
    ..write_object_begin()
    ..write_object_field("message", "runtime probe")
    .write_object_end()
  }
  if fail {
    raise Failed("runtime failed during create window (-7): owner closed")
  }
}

///|
test "file logging remains active after runtime return and error propagation" {
  let logger = @xlog.global()
  defer {
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  logger.set_config(@xlog.Config(level=@xlog.Warn))
  for fail in [false, true] {
    let path = ".proton-logging-test-" +
      current_process_id().to_string() +
      "-" +
      fail.to_string() +
      ".log"
    defer (@fs.remove_file(path) catch { _ => () })
    try {
      run_logging_probe(path, fail~)
      if @xlog.error() is Some(w) {
        w
        ..write_object_begin()
        ..write_object_field("message", "application shutdown complete")
        .write_object_end()
      }
    } catch {
      Failed(detail) =>
        if @xlog.error() is Some(w) {
          w
          ..write_object_begin()
          ..write_object_field("message", detail)
          .write_object_end()
        }
      error => raise error
    }
    let contents = @fs.read_file_to_string(path)
    assert_true(contents.contains("category=proton.test"))
    assert_true(contents.contains("message=\"runtime probe\""))
    assert_true(
      contents.contains(
        if fail {
          "runtime failed during create window (-7): owner closed"
        } else {
          "application shutdown complete"
        },
      ),
    )
  }
}

///|
test "failed logging initialization preserves the current handler and filtering" {
  let logger = @xlog.global()
  defer {
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  let capture = CaptureHandler::{ messages: [], }
  logger.set_handler(capture)
  logger.set_config(@xlog.Config(level=@xlog.Error))
  let failed = try {
    configure(Output::File(""))
    false
  } catch {
    OpenFile(..) => true
    _ => false
  }
  assert_true(failed)
  if @xlog.warn() is Some(w) {
    w
    ..write_object_begin()
    ..write_object_field("message", "filtered")
    .write_object_end()
  }
  if @xlog.error() is Some(w) {
    w
    ..write_object_begin()
    ..write_object_field("message", "after initialization failure")
    .write_object_end()
  }
  assert_eq(capture.messages, [Json::string("after initialization failure")])
}
