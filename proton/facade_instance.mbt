///|
fn resolved_app_activation(config : ResolvedAppConfig) -> @native.AppActivation {
  let urls : Array[String] = []
  let files : Array[String] = []
  let argv = @env.args()
  for index = 1; index < argv.length(); index = index + 1 {
    let argument = argv[index]
    if argument.has_prefix("-") {
      continue
    }
    if launch_argument_is_url(argument, config.url_schemes) {
      urls.push(argument)
    } else if launch_argument_is_document(argument, config.document_extensions) {
      let path : @mbpath.Path = argument
      files.push(path.resolve().to_string())
    }
  }
  @native.AppActivation(urls~, files~)
}

///|
fn launch_argument_is_url(
  argument : String,
  configured_schemes : Array[String],
) -> Bool {
  let lower = argument.to_lower()
  if lower.contains("://") {
    return true
  }
  match lower.find(":") {
    Some(index) if index > 0 => {
      let scheme = lower.unsafe_substring(start=0, end=index).to_string()
      configured_schemes.any(fn(configured) { configured.to_lower() == scheme })
    }
    _ => false
  }
}

///|
fn launch_argument_is_document(
  argument : String,
  configured_extensions : Array[String],
) -> Bool {
  guard @mbfs.path_exists(argument) else { return false }
  if configured_extensions.length() == 0 {
    return true
  }
  let lower = argument.to_lower()
  configured_extensions.any(fn(extension) {
    let extension = extension.trim().to_owned().to_lower()
    extension != "" &&
    lower.has_suffix(
      if extension.has_prefix(".") {
        extension
      } else {
        "." + extension
      },
    )
  })
}

///|
fn acquire_app_instance(
  config : ResolvedAppConfig,
) -> @native.AppInstanceAcquire? raise AppRunError {
  match config.instance_identifier {
    None => None
    Some(identifier) =>
      Some(
        @native.AppInstance::acquire(
          identifier,
          resolved_app_activation(config),
        ) catch {
          error => raise native_run_error("acquire app instance", error)
        },
      )
  }
}

///|
fn destroy_app_instance(
  instance : @native.AppInstance,
) -> Unit raise AppRunError {
  instance.destroy() catch {
    error => raise native_run_error("destroy app instance", error)
  }
}
