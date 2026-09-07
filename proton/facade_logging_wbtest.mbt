///|
priv struct RuntimeLogCapture {
  entries : Array[@xlog.Entry]
}

///|
impl @xlog.Handler for RuntimeLogCapture with fn handle(self, entry) {
  self.entries.push(entry)
}

///|
test "runtime failure logging retains operation status and reason without duplicates" {
  let logger = @xlog.global()
  defer {
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  let capture = RuntimeLogCapture::{ entries: [], }
  logger.set_handler(capture)
  logger.set_config(@xlog.Config(level=@xlog.Error))
  let failure_log = RuntimeFailureLog::{ primary_logged: false, }
  let error = RuntimeOperationFailed(
    action="create window",
    status=-7,
    detail="owner closed",
  )
  failure_log.report_primary(error)
  assert_eq(capture.entries.length(), 1)
  let entry = capture.entries[0]
  assert_true(entry.level == @xlog.Error)
  assert_eq(entry.category, Some("proton.runtime"))
  assert_eq(
    entry.fields.get("code"),
    Some(Json::string("runtime_operation_failed")),
  )
  assert_eq(
    entry.fields.get("error"),
    Some(Json::string("runtime failed during create window (-7): owner closed")),
  )
  ignore(failure_log.logged_remaining(error))
  assert_eq(capture.entries.length(), 1)
  ignore(
    failure_log.logged_remaining(
      CleanupFailed(primary=Some(error.message()), failures=[
        RuntimeDestroy(status=-8, detail="runtime busy"),
      ]),
    ),
  )
  assert_eq(capture.entries.length(), 2)
  assert_eq(
    capture.entries[1].fields.get("code"),
    Some(Json::string("cleanup_failed")),
  )
  assert_eq(
    capture.entries[1].fields.get("error"),
    Some(
      Json::string(
        "application teardown failed\n- failed to destroy runtime (-8): runtime busy",
      ),
    ),
  )
}

///|
test "runtime failures outside the dialog path retain complete diagnostics" {
  let logger = @xlog.global()
  defer {
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  let capture = RuntimeLogCapture::{ entries: [], }
  logger.set_handler(capture)
  logger.set_config(@xlog.Config(level=@xlog.Error))
  let failure_log = RuntimeFailureLog::{ primary_logged: false, }
  let error = ConfigurationError(
    InvalidSetting(name="browser_data_dir", message="not a directory"),
  )
  ignore(failure_log.logged_remaining(error))
  assert_eq(capture.entries.length(), 1)
  assert_eq(
    capture.entries[0].fields.get("error"),
    Some(
      Json::string(
        "application configuration failed: browser_data_dir: not a directory",
      ),
    ),
  )
}

///|
async test "repeated runtime logging startup preserves application changes" {
  let logger = @xlog.global()
  let was_started = runtime_logging_started.val
  defer {
    runtime_logging_started.val = was_started
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  runtime_logging_started.val = false
  start_runtime_logging("")
  let capture = RuntimeLogCapture::{ entries: [], }
  logger.set_handler(capture)
  logger.set_config(@xlog.Config(level=@xlog.Error))
  start_runtime_logging("")
  @xlog.warn() <? { "message": "filtered" }
  @xlog.error() <? { "message": "application handler retained" }
  assert_eq(capture.entries.length(), 1)
  assert_eq(
    capture.entries[0].fields.get("message"),
    Some(Json::string("application handler retained")),
  )
}

///|
async test "first runtime logging startup preserves root and category filtering" {
  let logger = @xlog.global()
  let was_started = runtime_logging_started.val
  defer {
    runtime_logging_started.val = was_started
    logger.set_handler(@xlog.Stdout())
    logger.set_config(@xlog.Config())
  }
  for level in [@xlog.Debug, @xlog.Error] {
    let config = @xlog.Config(level=@xlog.Warn)
    config.set_category_level("app.verbose", @xlog.Trace)
    config.set_category_level("app.quiet", @xlog.Fatal)
    logger.set_config(config)
    logger.set_level(level)
    runtime_logging_started.val = false
    start_runtime_logging("")
    let capture = RuntimeLogCapture::{ entries: [], }
    logger.set_handler(capture)
    @xlog.debug() <? { "message": "root debug" }
    @xlog.warn() <? { "message": "root warn" }
    @xlog.error() <? { "message": "root error" }
    @xlog.trace(category="app.verbose.child") <? { "message": "category trace" }
    @xlog.error(category="app.quiet.child") <? { "message": "filtered" }
    let messages = capture.entries.map(entry => {
      entry.fields.get("message").unwrap()
    })
    let expected : Array[Json] = if level == @xlog.Debug {
      ["root debug", "root warn", "root error", "category trace"]
    } else {
      ["root error", "category trace"]
    }
    assert_eq(messages, expected)
  }
}
