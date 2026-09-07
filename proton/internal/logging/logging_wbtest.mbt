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
  @xlog.warn(category="proton.test") <? { "message": "runtime probe" }
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
      @xlog.error() <? { "message": "application shutdown complete" }
    } catch {
      Failed(detail) => @xlog.error() <? { "message": detail }
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
  @xlog.warn() <? { "message": "filtered" }
  @xlog.error() <? { "message": "after initialization failure" }
  assert_eq(capture.messages, [Json::string("after initialization failure")])
}
