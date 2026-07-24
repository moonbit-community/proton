///|
let default_package = "app"

///|
let default_config_file = "moon.proton"

///|
pub(all) enum BuildError {
  UsageError(String, Bool)
  CommandError(String)
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
pub async fn run(
  cwd : String,
  args : Array[String],
) -> Result[Unit, BuildError] {
  if args.contains("-h") || args.contains("--help") {
    print_build_usage()
    return Ok(())
  }
  let raw = match parse_build_args(args) {
    Ok(raw) => raw
    Err(error) => return Err(error)
  }
  let cwd = @path.Path(cwd).resolve().to_string()
  let root = find_project_root_from(cwd)
  let config_path = resolve_build_config_path(cwd, root, raw)
  let config = match load_project_config(config_path) {
    Ok(config) => config
    Err(message) => return Err(CommandError(message))
  }
  match validate_release_config(config) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if raw.run_frontend_build {
    match run_frontend_build(root, config) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  match validate_release_files(root, config) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match run_moon_build(root, raw.app_package, raw.moon_args) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(())
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
) -> Result[RawBuildOptions, BuildError] {
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
      match read_option_value(args, index, "--config") {
        Ok(value) => {
          config_path = Some(value)
          index = index + 2
        }
        Err(error) => return Err(error)
      }
    } else if arg == "--no-frontend" {
      run_frontend_build = false
      index = index + 1
    } else if arg.has_prefix("-") {
      return Err(UsageError("unknown build option: " + arg, false))
    } else {
      match app_package {
        None => {
          app_package = Some(arg)
          index = index + 1
        }
        Some(_) =>
          return Err(
            UsageError("build accepts at most one package argument", false),
          )
      }
    }
  }
  match validate_moon_build_args(moon_args) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(RawBuildOptions::{
    app_package: app_package.unwrap_or(default_package),
    config_path,
    run_frontend_build,
    moon_args,
  })
}

///|
fn validate_moon_build_args(args : Array[String]) -> Result[Unit, BuildError] {
  for arg in args {
    if arg == "--target" || arg.has_prefix("--target=") {
      return Err(
        UsageError(
          "proton build always uses --target native; remove --target from MOON_BUILD_ARGS",
          false,
        ),
      )
    }
  }
  Ok(())
}

///|
fn read_option_value(
  args : Array[String],
  index : Int,
  flag : String,
) -> Result[String, BuildError] {
  if index + 1 >= args.length() {
    Err(UsageError(flag + " requires a value", false))
  } else {
    let value = args[index + 1]
    if value == "" {
      Err(UsageError(flag + " requires a value", false))
    } else {
      Ok(value)
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
) -> Result[BuildProjectConfig, String] {
  match config_path {
    None => Err("proton build config not found: moon.proton")
    Some(path) => {
      if !path_exists(path) {
        return Err("proton build config not found: " + path)
      }
      read_project_config(path)
    }
  }
}

///|
async fn run_frontend_build(
  root : String,
  config : BuildProjectConfig,
) -> Result[Unit, BuildError] {
  match config.frontend {
    None => Ok(())
    Some(frontend) =>
      match frontend.before_build() {
        None => Ok(())
        Some(command) => {
          let cwd = match resolve_frontend_cwd(root, frontend.cwd(), command) {
            Ok(cwd) => cwd
            Err(error) => return Err(error)
          }
          println("Building frontend: " + command)
          println("Frontend cwd: " + cwd)
          let (program, args) = shell_command(command)
          let code = @process.run(program, args, cwd~) catch {
            err =>
              return Err(
                CommandError(
                  "failed to run frontend build: " +
                  @debug.render(@debug.to_repr(err)),
                ),
              )
          }
          if code == 0 {
            Ok(())
          } else {
            Err(
              CommandError(
                "frontend build exited with code " + code.to_string(),
              ),
            )
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
) -> Result[String, BuildError] {
  ignore(command)
  match frontend_cwd {
    None => Ok(root)
    Some(cwd) => {
      let path = resolve_path(root, cwd)
      if !path_exists(path) {
        return Err(CommandError("frontend cwd does not exist: " + path))
      }
      if !path_is_dir(path) {
        return Err(CommandError("frontend cwd is not a directory: " + path))
      }
      Ok(path)
    }
  }
}

///|
fn validate_release_config(
  config : BuildProjectConfig,
) -> Result[Unit, BuildError] {
  match config.frontend {
    Some(frontend) =>
      match frontend.dist() {
        Some(_) => ()
        None =>
          return Err(
            CommandError(
              "frontend.dist is required for release builds when frontend is configured",
            ),
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
) -> Result[Unit, BuildError] {
  match config.frontend {
    Some(frontend) =>
      match frontend.dist() {
        Some(dist) => {
          let path = resolve_path(root, dist)
          if !path_exists(path) {
            return Err(CommandError("frontend dist does not exist: " + path))
          }
          if !path_is_dir(path) {
            return Err(
              CommandError("frontend dist is not a directory: " + path),
            )
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
) -> Result[Unit, BuildError] {
  match frontend {
    Some(_) =>
      match entry {
        File(_) | Asset(_) => ()
        Html(_) | Url(_) =>
          return Err(
            CommandError("frontend production entry must use file or asset"),
          )
      }
    None => ()
  }
  Ok(())
}

///|
fn validate_production_entry_file(
  entry : @proton_config.ProjectEntry,
) -> Result[Unit, BuildError] {
  match entry {
    File(path) | Asset(path) =>
      if !path_exists(path) {
        Err(CommandError("production entry does not exist: " + path))
      } else if path_is_dir(path) {
        Err(CommandError("production entry is not a file: " + path))
      } else {
        Ok(())
      }
    Html(_) | Url(_) => Ok(())
  }
}

///|
fn read_project_config(path : String) -> Result[BuildProjectConfig, String] {
  @proton_config.load_project_config_from_file(path)
  .map_err(fn(message) { "failed to load `" + path + "`: " + message })
  .map(fn(project) {
    BuildProjectConfig::{ entry: project.entry(), frontend: project.frontend() }
  })
}

///|
async fn run_moon_build(
  root : String,
  app_package : String,
  moon_args : Array[String],
) -> Result[Unit, BuildError] {
  let args = moon_build_args(app_package, moon_args)
  println("Building Proton app: moon " + args.join(" "))
  let code = @process.run("moon", args, cwd=root) catch {
    err =>
      return Err(
        CommandError(
          "failed to run MoonBit build: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  if code == 0 {
    Ok(())
  } else {
    Err(CommandError("MoonBit build exited with code " + code.to_string()))
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
