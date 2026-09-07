///|
let runtime_logging_started : Ref[Bool] = Ref(false)

///|
async fn start_runtime_logging(directory : String) -> Unit raise AppRunError {
  guard !runtime_logging_started.val else { return }
  let packaged = packaged_application_manifest_path() is Some(_)
  let output = match @env.get_env_var("PROTON_LOG_OUTPUT") {
    None => if packaged { "file" } else { "stderr" }
    Some(value) => value.trim().to_owned().to_lower()
  }
  let selected = match output {
    "stderr" => @logging.Output::Stderr
    "file" => {
      guard packaged else {
        raise LoggingInitializationFailed(
          detail="file logging requires packaged application metadata",
        )
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
  @logging.configure(selected) catch {
    error =>
      raise LoggingInitializationFailed(detail=@debug.render(Repr(error)))
  }
  runtime_logging_started.val = true
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
