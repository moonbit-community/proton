///|
async fn start_runtime_logging() -> @logging.RuntimeLogging raise AppRunError {
  let config = @xlog.Config::from_env(level=@xlog.Warn) catch {
    error =>
      raise LoggingInitializationFailed(
        detail="invalid MOON_XLOG configuration: " +
          xlog_config_error_message(error),
      )
  }
  let packaged_identifier = packaged_application_identifier()
  let output = match @env.get_env_var("PROTON_LOG_OUTPUT") {
    None => if packaged_identifier is Some(_) { "file" } else { "stderr" }
    Some(value) => value.trim().to_owned().to_lower()
  }
  let selected = match output {
    "stderr" => @logging.Output::Stderr
    "file" => {
      guard packaged_identifier is Some(identifier) else {
        raise LoggingInitializationFailed(
          detail="file logging requires packaged application metadata",
        )
      }
      let directory = app_log_dir(identifier) catch {
        error => raise LoggingInitializationFailed(detail=error.message())
      }
      ensure_log_directory(directory)
      let filename = "proton-" +
        @logging.current_process_id().to_string() +
        ".log"
      @logging.Output::File(
        @mbpath.Path(directory).join(filename).normalize().to_string(),
      )
    }
    value =>
      raise LoggingInitializationFailed(
        detail="PROTON_LOG_OUTPUT must be stderr or file, got: " + value,
      )
  }
  @logging.RuntimeLogging(selected, config) catch {
    error =>
      raise LoggingInitializationFailed(detail=@debug.render(Repr(error)))
  }
}

///|
async fn packaged_application_identifier() -> String? raise AppRunError {
  guard packaged_application_manifest_path() is Some(path) else { return None }
  let source = @async_fs.read_file(path).text() catch {
    error =>
      raise LoggingInitializationFailed(
        detail="cannot read packaged application metadata: " + error.to_string(),
      )
  }
  Some(package_identifier_from_json(source))
}

///|
fn package_identifier_from_json(source : String) -> String raise AppRunError {
  let json = @json.parse(source) catch {
    error =>
      raise LoggingInitializationFailed(
        detail="invalid packaged application metadata: " + error.to_string(),
      )
  }
  guard json is Object(fields) else {
    raise LoggingInitializationFailed(
      detail="invalid packaged application metadata: expected an object",
    )
  }
  guard fields.get("identifier") is Some(String(identifier)) else {
    raise LoggingInitializationFailed(
      detail="invalid packaged application metadata: identifier is required",
    )
  }
  validate_app_identifier(identifier) catch {
    error => raise LoggingInitializationFailed(detail=error.message())
  }
  identifier
}

///|
async fn ensure_log_directory(path : String) -> Unit raise AppRunError {
  if @mbfs.path_exists(path) {
    guard log_path_is_directory(path) else {
      raise LoggingInitializationFailed(
        detail="application log path is not a directory: " + path,
      )
    }
    return
  }
  let parent : String = @mbpath.Path(path).dirname().normalize().to_string()
  guard parent != path else {
    raise LoggingInitializationFailed(
      detail="cannot resolve parent of application log directory: " + path,
    )
  }
  ensure_log_directory(parent)
  @async_fs.mkdir(path) catch {
    error => {
      if @mbfs.path_exists(path) && log_path_is_directory(path) {
        return
      }
      raise LoggingInitializationFailed(
        detail="cannot create application log directory: " + error.to_string(),
      )
    }
  }
}

///|
fn log_path_is_directory(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn xlog_config_error_message(error : @xlog.ConfigError) -> String {
  match error {
    @xlog.ConfigError::InvalidCategory(value) => "invalid category: " + value
    @xlog.ConfigError::InvalidDirective(value) => "invalid directive: " + value
    @xlog.ConfigError::InvalidLevel(value) => "invalid level: " + value
  }
}
