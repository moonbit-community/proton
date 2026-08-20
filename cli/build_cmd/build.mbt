///|
let default_package = "app"

///|
let default_config_file = "proton.project.json"

///|
pub(all) suberror BuildUsageError {
  InvalidArguments(message~ : String)
} derive(Debug, Eq)

///|
pub extend BuildUsageError with Eq::{not_equal, equal}

///|
pub extend BuildUsageError with Debug::{to_repr}

///|
pub extend BuildUsageError with Show::{to_string, output}

///|
pub(all) suberror BuildConfigError {
  NotFound(path~ : String?)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  InvalidRelease(message~ : String)
} derive(Debug, Eq)

///|
pub extend BuildConfigError with Eq::{not_equal, equal}

///|
pub extend BuildConfigError with Debug::{to_repr}

///|
pub extend BuildConfigError with Show::{to_string, output}

///|
pub(all) suberror BuildPathError {
  Missing(role~ : String, path~ : String)
  WrongKind(role~ : String, path~ : String, expected~ : String)
} derive(Debug, Eq)

///|
pub extend BuildPathError with Eq::{not_equal, equal}

///|
pub extend BuildPathError with Debug::{to_repr}

///|
pub extend BuildPathError with Show::{to_string, output}

///|
pub(all) suberror BuildProcessError {
  Start(command~ : String, detail~ : String)
  Exit(command~ : String, code~ : Int)
  InvalidOutput(command~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend BuildProcessError with Eq::{not_equal, equal}

///|
pub extend BuildProcessError with Debug::{to_repr}

///|
pub extend BuildProcessError with Show::{to_string, output}

///|
pub fn BuildUsageError::message(self : BuildUsageError) -> String {
  match self {
    InvalidArguments(message~) => message
  }
}

///|
pub fn BuildConfigError::message(self : BuildConfigError) -> String {
  match self {
    NotFound(path~) =>
      match path {
        Some(path) => "proton build config not found: " + path
        None => "proton build config not found: proton.project.json"
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
    InvalidOutput(command~, detail~) =>
      command + " returned invalid output: " + detail
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
  app_package : String?
  config_path : String?
  moon_target_dir : String?
  run_frontend_build : Bool
  moon_args : Array[String]
} derive(Debug, Eq)

///|
pub extend RawBuildOptions with Eq::{not_equal, equal}

///|
pub extend RawBuildOptions with Debug::{to_repr}

///|
priv struct BuildProjectConfig {
  base_dir : String
  backend : @proton_config.ProjectBackendConfig?
  frontend : @proton_config.ProjectFrontendConfig?
}

///|
/// Returns the declarative `proton_cli build` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "build",
    about="Build a Proton application for the native target",
    flags=[
      FlagArg(
        "no-frontend",
        about="Do not run the configured frontend build command",
      ),
    ],
    options=[
      OptionArg("package", about="MoonBit application package"),
      OptionArg("config", about="Proton project config"),
      OptionArg(
        "moon-target-dir",
        about="Target directory for the internal Moon build",
      ),
    ],
    positionals=[
      PositionArg(
        "moon-build-args",
        num_args=ValueRange(lower=0),
        about="Arguments passed to moon build after --",
      ),
    ],
  )
}

///|
/// Runs the build workflow from parsed command matches.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  run_with_options(cwd, build_options_from_matches(matches))
}

///|
/// Builds the application executable requested by the package workflow and
/// returns the artifact path reported by Moon.
pub async fn build_executable(
  cwd : String,
  app_package : String,
  config_path : String,
  release : Bool,
) -> String {
  let invocation = prepare_build(cwd, RawBuildOptions::{
    app_package: Some(app_package),
    config_path: Some(config_path),
    moon_target_dir: None,
    run_frontend_build: true,
    moon_args: [],
  })
  let executable = run_moon_build_only(
    invocation.backend_path,
    invocation.app_package,
    release,
  )
  executable
}

///|
async fn run_with_options(cwd : String, raw : RawBuildOptions) -> Unit {
  let invocation = prepare_build(cwd, raw)
  run_moon_build(
    invocation.backend_path,
    invocation.app_package,
    invocation.moon_args,
    invocation.moon_target_dir,
  )
  let moon_target_dir = invocation.moon_target_dir
  let proton_source = resolve_proton_source(
    invocation.backend_path,
    invocation.app_package,
  )
  ignore(
    build_cef_process(proton_source, invocation.backend_path, moon_target_dir?),
  )
}

///|
priv struct BuildInvocation {
  backend_path : String
  app_package : String
  moon_target_dir : String?
  moon_args : Array[String]
}

///|
async fn prepare_build(cwd : String, raw : RawBuildOptions) -> BuildInvocation {
  let cwd = @path.Path(cwd).resolve().to_string()
  let config_path = resolve_build_config_path(cwd, raw)
  let config = load_project_config(config_path)
  validate_release_config(config)
  if raw.run_frontend_build {
    run_frontend_build(config.base_dir, config)
  }
  validate_release_files(config.base_dir, config)
  let backend_path = resolve_backend_path(
    config.base_dir,
    config.backend.map(fn(backend) { backend.path() }),
  )
  let app_package = match raw.app_package {
    Some(app_package) => app_package
    None =>
      match config.backend {
        Some(backend) => backend.app_package()
        None => default_package
      }
  }
  let moon_target_dir = raw.moon_target_dir.map(path => {
    @fsutil.resolve_path(cwd, path)
  })
  BuildInvocation::{
    backend_path,
    app_package,
    moon_target_dir,
    moon_args: raw.moon_args,
  }
}

///|
fn unquote_build_plan_path(value : String) -> String {
  let value = value.trim().to_owned()
  if value.length() >= 2 &&
    (
      (value.has_prefix("'") && value.has_suffix("'")) ||
      (value.has_prefix("\"") && value.has_suffix("\""))
    ) {
    value[1:value.length() - 1].to_owned()
  } else {
    value
  }
}

///|
fn proton_source_from_build_plan(
  output : String,
  workspace_root : String,
) -> String? {
  let marker = "-pkg-sources moonbit-community/proton:"
  for line in output.replace(old="\r\n", new="\n").split("\n") {
    guard line.split_once(marker) is Some((_, suffix)) else { continue }
    let suffix = match suffix.split_once(" -target ") {
      Some((path, _)) => path
      None => suffix
    }
    let source = unquote_build_plan_path(suffix.to_owned())
    if source != "" {
      return Some(@fsutil.resolve_path(workspace_root, source))
    }
  }
  None
}

///|
pub async fn resolve_proton_source(
  backend_path : String,
  app_package : String,
) -> String {
  let (code, output) = @process.collect_output_merged(
    "moon",
    ["check", app_package, "--target", "native", "--dry-run"],
    cwd=backend_path,
    extra_env=native_moon_process_env(),
  ) catch {
    error =>
      raise BuildProcessError::Start(
        command="MoonBit dependency resolution",
        detail=@debug.render(Repr(error)),
      )
  }
  let text = output.text() catch {
    error =>
      raise BuildProcessError::InvalidOutput(
        command="MoonBit dependency resolution",
        detail=@debug.render(Repr(error)),
      )
  }
  guard code == 0 else {
    raise BuildProcessError::InvalidOutput(
      command="MoonBit dependency resolution",
      detail=text.trim().to_owned(),
    )
  }
  guard proton_source_from_build_plan(text, backend_path) is Some(source) else {
    raise BuildProcessError::InvalidOutput(
      command="MoonBit dependency resolution",
      detail="the application does not resolve moonbit-community/proton",
    )
  }
  guard @fsutil.path_is_file(@fsutil.path_join(source, "cef_requirements.json")) &&
    @fsutil.path_is_dir(@fsutil.path_join(source, "internal/cef_process")) else {
    raise BuildPathError::Missing(
      role="resolved Proton source containing internal/cef_process",
      path=source,
    )
  }
  source
}

///|
pub async fn resolve_default_project_proton_source(cwd : String) -> String {
  let invocation = prepare_build(cwd, RawBuildOptions::{
    app_package: None,
    config_path: None,
    moon_target_dir: None,
    run_frontend_build: false,
    moon_args: [],
  })
  resolve_proton_source(invocation.backend_path, invocation.app_package)
}

///|
pub async fn resolve_proton_runtime_requirements(source : String) -> String {
  let path = @fsutil.path_join(source, "cef_requirements.json")
  guard @fsutil.path_is_file(path) else {
    raise BuildPathError::Missing(
      role="resolved Proton CEF requirements",
      path~,
    )
  }
  path
}

///|
pub async fn resolve_project_runtime_requirements(cwd : String) -> String {
  resolve_proton_runtime_requirements(
    resolve_default_project_proton_source(cwd),
  )
}

///|
pub fn cef_process_install_path(bin_dir : String) -> String {
  let name = if @path.sep == '\\' { "cef_process.exe" } else { "cef_process" }
  @fsutil.resolve_path(bin_dir, name)
}

///|
fn native_moon_process_env_for(
  windows : Bool,
  configured_cc : String?,
) -> Map[String, String] {
  let env : Map[String, String] = Map([])
  if !windows {
    // Selecting a host compiler makes Moon build its C runtime from source
    // instead of linking libmoonbitrun.o, whose process-wide allocator symbols
    // would otherwise interpose on CEF and libc allocations.
    env["MOON_CC"] = match configured_cc {
      Some(value) if value.trim() != "" => value
      // Proton's shared native-stub package contains Objective-C sources even
      // on Linux, so its portable host-compiler default must be Clang.
      _ => "clang"
    }
  }
  env
}

///|
/// Returns the environment required for a Proton native Moon command.
pub fn native_moon_process_env() -> Map[String, String] {
  native_moon_process_env_for(@path.sep == '\\', @env.get_env_var("MOON_CC"))
}

///|
pub async fn build_cef_process(
  proton_source : String,
  backend_path : String,
  moon_target_dir? : String,
) -> String {
  ignore(resolve_proton_runtime_requirements(proton_source))
  let bin_dir = moon_target_dir.unwrap_or(
    @fsutil.path_join(backend_path, "_build"),
  )
  let args : Array[String] = [
    "install",
    "--path",
    @fsutil.path_join(proton_source, "internal/cef_process"),
    "--bin",
    bin_dir,
  ]
  match moon_target_dir {
    Some(target_dir) => {
      args.push("--target-dir")
      args.push(target_dir)
    }
    None => ()
  }
  @output.info("Installing CEF process helper: moon " + args.join(" "))
  let code = @process.run(
    "moon",
    args,
    cwd=backend_path,
    extra_env=native_moon_process_env(),
  ) catch {
    error =>
      raise BuildProcessError::Start(
        command="CEF process helper install",
        detail=@debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise BuildProcessError::Exit(command="CEF process helper install", code~)
  }
  let output = cef_process_install_path(bin_dir)
  guard @fsutil.path_is_file(output) else {
    raise BuildPathError::Missing(role="CEF process helper", path=output)
  }
  output
}

///|
fn build_options_from_matches(
  matches : @argparse.Matches,
) -> RawBuildOptions raise BuildUsageError {
  guard matches.values
    is {
      "moon-build-args"? : Some(moon_args)
      | (None with moon_args = []),
      "package"? : Some(app_package)
      | (None with app_package = []),
      "config"? : Some(config_path)
      | (None with config_path = []),
      "moon-target-dir"? : Some(moon_target_dir)
      | (None with moon_target_dir = []),
      ..
    }
  guard matches.flags
    is {
      "no-frontend"? : Some(no_frontend)
      | (None with no_frontend = false),
      ..
    }
  validate_moon_build_args(moon_args)
  RawBuildOptions::{
    app_package: app_package.get(0),
    config_path: config_path.get(0),
    moon_target_dir: moon_target_dir.get(0),
    run_frontend_build: !no_frontend,
    moon_args,
  }
}

///|
fn validate_moon_build_args(args : Array[String]) -> Unit raise BuildUsageError {
  for arg in args {
    if arg == "--target" || arg.has_prefix("--target=") {
      raise InvalidArguments(
        message="proton build always uses --target native; remove --target from the arguments after `--`",
      )
    }
  }
}

///|
async fn resolve_build_config_path(
  cwd : String,
  raw : RawBuildOptions,
) -> String? {
  match raw.config_path {
    Some(path) => Some(@fsutil.resolve_path(cwd, path))
    None => {
      let cwd_config = @fsutil.path_join(cwd, default_config_file)
      if @fsutil.path_exists(cwd_config) {
        Some(cwd_config)
      } else {
        None
      }
    }
  }
}

///|
async fn load_project_config(config_path : String?) -> BuildProjectConfig {
  match config_path {
    None => raise NotFound(path=None)
    Some(path) => {
      if !@fsutil.path_exists(path) {
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
          let cwd = resolve_frontend_path(root, frontend.path(), command)
          @output.info("Building frontend: " + command)
          @output.info("Frontend cwd: " + cwd)
          let (program, args) = shell_command(command)
          let code = @process.run(program, args, cwd~) catch {
            err =>
              raise BuildProcessError::Start(
                command="frontend build",
                detail=@debug.render(Repr(err)),
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
async fn resolve_frontend_path(
  root : String,
  frontend_path : String?,
  command : String,
) -> String {
  ignore(command)
  match frontend_path {
    None => root
    Some(configured_path) => {
      let path = @fsutil.resolve_path(root, configured_path)
      if !@fsutil.path_exists(path) {
        raise Missing(role="frontend path", path~)
      }
      if !@fsutil.path_is_dir(path) {
        raise WrongKind(role="frontend path", path~, expected="a directory")
      }
      path
    }
  }
}

///|
async fn resolve_backend_path(root : String, backend_path : String?) -> String {
  match backend_path {
    None => root
    Some(configured_path) => {
      let path = @fsutil.resolve_path(root, configured_path)
      if !@fsutil.path_exists(path) {
        raise Missing(role="backend path", path~)
      }
      if !@fsutil.path_is_dir(path) {
        raise WrongKind(role="backend path", path~, expected="a directory")
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
}

///|
async fn validate_release_files(
  root : String,
  config : BuildProjectConfig,
) -> Unit {
  match config.frontend {
    Some(frontend) =>
      match frontend.dist() {
        Some(dist) => {
          let path = @fsutil.resolve_path(root, dist)
          if !@fsutil.path_exists(path) {
            raise Missing(role="frontend dist", path~)
          }
          if !@fsutil.path_is_dir(path) {
            raise WrongKind(role="frontend dist", path~, expected="a directory")
          }
        }
        None => ()
      }
    None => ()
  }
}

///|
async fn read_project_config(
  path : String,
) -> BuildProjectConfig raise BuildConfigError {
  let source = @async_fs.read_file(path).text() catch {
    error =>
      raise Invalid(
        path~,
        error=@proton_config.ProjectConfigError::FileRead(
          path~,
          detail=@debug.render(Repr(error)),
        ),
      )
  }
  let loaded = @proton_config.load_project_config_from_text(
    source,
    @fsutil.path_parent(path),
    name=path,
  ) catch {
    error => raise Invalid(path~, error~)
  }
  let project = loaded.config()
  BuildProjectConfig::{
    base_dir: project.base_dir(),
    backend: project.backend(),
    frontend: project.frontend(),
  }
}

///|
async fn run_moon_build(
  root : String,
  app_package : String,
  moon_args : Array[String],
  moon_target_dir : String?,
) -> Unit {
  let args = moon_build_args_with_target_dir(
    app_package, moon_args, moon_target_dir,
  )
  @output.info("Building Proton app: moon " + args.join(" "))
  let code = @process.run(
    "moon",
    args,
    cwd=root,
    extra_env=native_moon_process_env(),
  ) catch {
    err =>
      raise BuildProcessError::Start(
        command="MoonBit build",
        detail=@debug.render(Repr(err)),
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
fn moon_build_args_with_target_dir(
  app_package : String,
  moon_args : Array[String],
  moon_target_dir : String?,
) -> Array[String] {
  let args : Array[String] = []
  match moon_target_dir {
    Some(target_dir) => {
      args.push("--target-dir")
      args.push(target_dir)
    }
    None => ()
  }
  for arg in moon_build_args(app_package, moon_args) {
    args.push(arg)
  }
  args
}

///|
fn moon_build_only_args(app_package : String, release : Bool) -> Array[String] {
  [
    "run",
    app_package,
    "--target",
    "native",
    if release {
      "--release"
    } else {
      "--debug"
    },
    "--build-only",
  ]
}

///|
fn artifact_path_from_build_output(
  output : String,
) -> String raise BuildProcessError {
  let json = @json.parse(output) catch {
    error =>
      raise InvalidOutput(
        command="MoonBit executable build",
        detail=@debug.render(Repr(error)),
      )
  }
  guard json is { "artifacts_path": Array(paths), .. } else {
    raise InvalidOutput(
      command="MoonBit executable build",
      detail="missing artifacts_path array",
    )
  }
  guard paths is [String(path)] else {
    raise InvalidOutput(
      command="MoonBit executable build",
      detail="expected exactly one executable artifact",
    )
  }
  path
}

///|
async fn run_moon_build_only(
  root : String,
  app_package : String,
  release : Bool,
) -> String {
  let args = moon_build_only_args(app_package, release)
  @output.info("Building Proton executable: moon " + args.join(" "))
  let (code, stdout) = @process.collect_stdout(
    "moon",
    args,
    cwd=root,
    extra_env=native_moon_process_env(),
  ) catch {
    error =>
      raise BuildProcessError::Start(
        command="MoonBit executable build",
        detail=@debug.render(Repr(error)),
      )
  }
  if code != 0 {
    raise BuildProcessError::Exit(command="MoonBit executable build", code~)
  }
  let output = stdout.text() catch {
    error =>
      raise BuildProcessError::InvalidOutput(
        command="MoonBit executable build",
        detail="failed to decode stdout: " + @debug.render(Repr(error)),
      )
  }
  artifact_path_from_build_output(output)
}

///|
fn shell_command(command : String) -> (String, Array[String]) {
  if @path.sep == '\\' {
    ("cmd", ["/c", command])
  } else {
    ("sh", ["-c", command])
  }
}
