///|
let default_package = "app"

///|
let default_config_file = "moon.proton"

///|
pub(all) suberror BuildUsageError {
  InvalidArguments(message~ : String, usage_is_embedded~ : Bool)
} derive(Debug, Eq)

///|
pub(all) suberror BuildConfigError {
  NotFound(path~ : String?)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  InvalidRelease(message~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror BuildPathError {
  Missing(role~ : String, path~ : String)
  WrongKind(role~ : String, path~ : String, expected~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror BuildProcessError {
  Start(command~ : String, detail~ : String)
  Exit(command~ : String, code~ : Int)
} derive(Debug, Eq)

///|
pub fn BuildUsageError::message(self : BuildUsageError) -> String {
  match self {
    InvalidArguments(message~, ..) => message
  }
}

///|
pub fn BuildConfigError::message(self : BuildConfigError) -> String {
  match self {
    NotFound(path~) =>
      match path {
        Some(path) => "proton build config not found: " + path
        None => "proton build config not found: moon.proton"
      }
    Invalid(path~, error~) =>
      "invalid proton build config " + path + ": " + error.message()
    InvalidRelease(message~) => message
  }
}

///|
pub fn BuildPathError::message(self : BuildPathError) -> String {
  match self {
    Missing(role~, path~) => role + " does not exist: " + path
    WrongKind(role~, path~, expected~) =>
      role + " is not " + expected + ": " + path
  }
}

///|
pub fn BuildProcessError::message(self : BuildProcessError) -> String {
  match self {
    Start(command~, detail~) => "failed to run " + command + ": " + detail
    Exit(command~, code~) => command + " exited with code " + code.to_string()
  }
}

///|
impl Show for BuildUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BuildConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BuildPathError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BuildProcessError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
struct RawBuildOptions {
  app_package : String
  config_path : String?
  run_frontend_build : Bool
  moon_args : Array[String]
} derive(Debug, Eq)

///|
priv struct BuildProjectConfig {
  entry : @proton_config.ProjectEntry
  frontend : @proton_config.ProjectFrontendConfig?
}

///|
pub async fn run(cwd : String, args : Array[String]) -> Unit {
  if args.contains("-h") || args.contains("--help") {
    print_build_usage()
    return
  }
  let raw = parse_build_args(args)
  let cwd = @path.Path(cwd).resolve().to_string()
  let root = find_project_root_from(cwd)
  let config_path = resolve_build_config_path(cwd, root, raw)
  let config = load_project_config(config_path)
  validate_release_config(config)
  if raw.run_frontend_build {
    run_frontend_build(root, config)
  }
  validate_release_files(root, config)
  run_moon_build(root, raw.app_package, raw.moon_args)
}

///|
fn print_build_usage() -> Unit {
  println("Usage:")
  println(
    "  proton_cli [-C DIR] build [PACKAGE] [OPTIONS] [-- [MOON_BUILD_ARGS]...]",
  )
  println("")
  println("Options:")
  println(
    "  --config <path>          Proton project config (default: package/cwd/root moon.proton)",
  )
  println("  --no-frontend            Do not run frontend.before_build")
}

///|
fn parse_build_args(
  args : Array[String],
) -> RawBuildOptions raise BuildUsageError {
  let moon_args : Array[String] = []
  let mut app_package : String? = None
  let mut config_path : String? = None
  let mut run_frontend_build = true
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "--" {
      for value in args[index + 1:] {
        moon_args.push(value)
      }
      index = args.length()
    } else if arg == "--config" {
      config_path = Some(read_option_value(args, index, "--config"))
      index = index + 2
    } else if arg == "--no-frontend" {
      run_frontend_build = false
      index = index + 1
    } else if arg.has_prefix("-") {
      raise InvalidArguments(
        message="unknown build option: " + arg,
        usage_is_embedded=false,
      )
    } else {
      match app_package {
        None => {
          app_package = Some(arg)
          index = index + 1
        }
        Some(_) =>
          raise InvalidArguments(
            message="build accepts at most one package argument",
            usage_is_embedded=false,
          )
      }
    }
  }
  validate_moon_build_args(moon_args)
  RawBuildOptions::{
    app_package: app_package.unwrap_or(default_package),
    config_path,
    run_frontend_build,
    moon_args,
  }
}

///|
fn validate_moon_build_args(args : Array[String]) -> Unit raise BuildUsageError {
  for arg in args {
    if arg == "--target" || arg.has_prefix("--target=") {
      raise InvalidArguments(
        message="proton build always uses --target native; remove --target from MOON_BUILD_ARGS",
        usage_is_embedded=false,
      )
    }
  }
}

///|
fn read_option_value(
  args : Array[String],
  index : Int,
  flag : String,
) -> String raise BuildUsageError {
  if index + 1 >= args.length() {
    raise InvalidArguments(
      message=flag + " requires a value",
      usage_is_embedded=false,
    )
  } else {
    let value = args[index + 1]
    if value == "" {
      raise InvalidArguments(
        message=flag + " requires a value",
        usage_is_embedded=false,
      )
    } else {
      value
    }
  }
}

///|
fn resolve_build_config_path(
  cwd : String,
  root : String,
  raw : RawBuildOptions,
) -> String? {
  match raw.config_path {
    Some(path) => Some(resolve_path(cwd, path))
    None => {
      let package_config = package_config_path(cwd, raw.app_package)
      let cwd_config = join_path(cwd, default_config_file)
      let root_config = join_path(root, default_config_file)
      if path_exists(package_config) {
        Some(package_config)
      } else if path_exists(cwd_config) {
        Some(cwd_config)
      } else if path_exists(root_config) {
        Some(root_config)
      } else {
        None
      }
    }
  }
}

///|
fn package_config_path(cwd : String, app_package : String) -> String {
  resolve_path(cwd, join_path(app_package, default_config_file))
}

///|
fn load_project_config(
  config_path : String?,
) -> BuildProjectConfig raise BuildConfigError {
  match config_path {
    None => raise NotFound(path=None)
    Some(path) => {
      if !path_exists(path) {
        raise NotFound(path=Some(path))
      }
      read_project_config(path)
    }
  }
}

///|
async fn run_frontend_build(root : String, config : BuildProjectConfig) -> Unit {
  match config.frontend {
    None => ()
    Some(frontend) =>
      match frontend.before_build() {
        None => ()
        Some(command) => {
          let cwd = resolve_frontend_cwd(root, frontend.cwd(), command)
          println("Building frontend: " + command)
          println("Frontend cwd: " + cwd)
          let (program, args) = shell_command(command)
          let code = @process.run(program, args, cwd~) catch {
            err =>
              raise BuildProcessError::Start(
                command="frontend build",
                detail=@debug.render(@debug.to_repr(err)),
              )
          }
          if code != 0 {
            raise BuildProcessError::Exit(command="frontend build", code~)
          }
        }
      }
  }
}

///|
fn resolve_frontend_cwd(
  root : String,
  frontend_cwd : String?,
  command : String,
) -> String raise BuildPathError {
  ignore(command)
  match frontend_cwd {
    None => root
    Some(cwd) => {
      let path = resolve_path(root, cwd)
      if !path_exists(path) {
        raise Missing(role="frontend cwd", path~)
      }
      if !path_is_dir(path) {
        raise WrongKind(role="frontend cwd", path~, expected="a directory")
      }
      path
    }
  }
}

///|
fn validate_release_config(
  config : BuildProjectConfig,
) -> Unit raise BuildConfigError {
  match config.frontend {
    Some(frontend) =>
      match frontend.dist() {
        Some(_) => ()
        None =>
          raise InvalidRelease(
            message="frontend.dist is required for release builds when frontend is configured",
          )
      }
    None => ()
  }
  validate_production_entry_kind(config.entry, config.frontend)
}

///|
fn validate_release_files(
  root : String,
  config : BuildProjectConfig,
) -> Unit raise BuildPathError {
  match config.frontend {
    Some(frontend) =>
      match frontend.dist() {
        Some(dist) => {
          let path = resolve_path(root, dist)
          if !path_exists(path) {
            raise Missing(role="frontend dist", path~)
          }
          if !path_is_dir(path) {
            raise WrongKind(role="frontend dist", path~, expected="a directory")
          }
        }
        None => ()
      }
    None => ()
  }
  validate_production_entry_file(config.entry)
}

///|
fn validate_production_entry_kind(
  entry : @proton_config.ProjectEntry,
  frontend : @proton_config.ProjectFrontendConfig?,
) -> Unit raise BuildConfigError {
  match frontend {
    Some(_) =>
      match entry {
        File(_) | Asset(_) => ()
        Html(_) | Url(_) =>
          raise BuildConfigError::InvalidRelease(
            message="frontend production entry must use file or asset",
          )
      }
    None => ()
  }
}

///|
fn validate_production_entry_file(
  entry : @proton_config.ProjectEntry,
) -> Unit raise BuildPathError {
  match entry {
    File(path) | Asset(path) =>
      if !path_exists(path) {
        raise Missing(role="production entry", path~)
      } else if path_is_dir(path) {
        raise WrongKind(role="production entry", path~, expected="a file")
      }
    Html(_) | Url(_) => ()
  }
}

///|
fn read_project_config(
  path : String,
) -> BuildProjectConfig raise BuildConfigError {
  let project = @proton_config.load_project_config_from_file(path) catch {
    error => raise Invalid(path~, error~)
  }
  BuildProjectConfig::{ entry: project.entry(), frontend: project.frontend() }
}

///|
async fn run_moon_build(
  root : String,
  app_package : String,
  moon_args : Array[String],
) -> Unit {
  let args = moon_build_args(app_package, moon_args)
  println("Building Proton app: moon " + args.join(" "))
  let code = @process.run("moon", args, cwd=root) catch {
    err =>
      raise BuildProcessError::Start(
        command="MoonBit build",
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  if code != 0 {
    raise BuildProcessError::Exit(command="MoonBit build", code~)
  }
}

///|
fn moon_build_args(
  app_package : String,
  moon_args : Array[String],
) -> Array[String] {
  let args : Array[String] = ["build", app_package]
  for arg in moon_args {
    args.push(arg)
  }
  args.push("--target")
  args.push("native")
  args
}

///|
fn shell_command(command : String) -> (String, Array[String]) {
  if @path.sep == '\\' {
    ("cmd", ["/c", command])
  } else {
    ("sh", ["-c", command])
  }
}

///|
fn find_project_root_from(start : String) -> String {
  for dir = start; dir != ""; {
    if path_exists(join_path(dir, "moon.work")) ||
      path_exists(join_path(dir, "moon.mod")) {
      return dir
    }
    let parent = path_parent(dir)
    if parent == dir {
      return start
    }
    continue parent
  }
  start
}

///|
fn resolve_path(base : String, path : String) -> String {
  if path_input_is_absolute(path) {
    let candidate : @path.Path = path
    if candidate.is_absolute() {
      candidate.resolve().to_string()
    } else {
      path
    }
  } else {
    let path = normalize_relative_path_input(path)
    let base_path : @path.Path = base
    base_path.join(path).normalize().resolve().to_string()
  }
}

///|
fn path_input_is_absolute(path : String) -> Bool {
  path.has_prefix("\\") ||
  path.has_prefix("/") ||
  path.contains(":\\") ||
  path.contains(":/")
}

///|
fn normalize_relative_path_input(path : String) -> String {
  if @path.sep == '\\' {
    path.replace_all(old="\\", new="/")
  } else {
    path
  }
}

///|
fn join_path(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + child
  } else {
    base + @path.sep.to_string() + child
  }
}

///|
fn path_parent(path : String) -> String {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  let slash = normalized.rev_find("/")
  let backslash = normalized.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      normalized.unsafe_substring(start=0, end=index).to_string()
    _ => normalized.to_string()
  }
}

///|
fn path_exists(path : String) -> Bool {
  @mbfs.path_exists(path)
}

///|
fn path_is_dir(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}
