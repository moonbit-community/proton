///|
let default_package = "app"

///|
let default_config_file = "proton.project.json"

///|
let default_timeout_ms = 30000

///|
let ready_poll_interval_ms = 100

///|
let ready_probe_timeout_ms = 1000

///|
#derive(Debug, Eq)
struct RawDevOptions {
  app_package : String?
  config_path : String?
  moon_target_dir : String?
  url : String?
  command : String?
  frontend_path : String?
  timeout_ms : Int32
  ready_path : String?
  start_frontend : Bool
  app_args : Array[String]
}

///|
pub extend RawDevOptions with Eq::{not_equal, equal}

///|
pub extend RawDevOptions with Debug::{to_repr}

///|
#derive(Debug, Eq)
struct DevRuntime {
  root : String
  bin_dir : String
  platform : String
}

///|
pub extend DevRuntime with Eq::{not_equal, equal}

///|
pub extend DevRuntime with Debug::{to_repr}

///|
#derive(Debug, Eq)
struct DevUrlEndpoint {
  url : String
  host : String
  port : Int32
}

///|
pub extend DevUrlEndpoint with Eq::{not_equal, equal}

///|
pub extend DevUrlEndpoint with Debug::{to_repr}

///|
/// Returns the declarative `proton_cli dev` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "dev",
    about="Run a Proton app in development mode",
    flags=[
      FlagArg(
        "no-frontend",
        about="Do not start the configured frontend command",
      ),
    ],
    options=[
      OptionArg("package", about="MoonBit application package"),
      OptionArg("config", about="Proton project config"),
      OptionArg(
        "moon-target-dir",
        about="Target directory for the app's internal Moon invocation",
      ),
      OptionArg("url", about="Override frontend.dev_url"),
      OptionArg("command", about="Override frontend.before_dev"),
      OptionArg("frontend-path", about="Override frontend.path"),
      OptionArg(
        "timeout-ms",
        default_values=[default_timeout_ms.to_string()],
        about="Dev server wait timeout in milliseconds",
      ),
      OptionArg("ready-path", about="HTTP readiness probe path"),
    ],
    positionals=[
      PositionArg(
        "app-args",
        num_args=ValueRange(lower=0),
        about="Arguments passed to the application after --",
      ),
    ],
  )
}

///|
/// Runs the development workflow from parsed command matches.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  let raw = dev_options_from_matches(matches)
  let cwd = @path.Path(cwd).resolve().to_string()
  let config_path = resolve_dev_config_path(cwd, raw)
  let project = read_dev_project_config(config_path)
  let project_config = effective_dev_config(project.config, raw)
  project_config.validate() catch {
    error => raise Invalid(path=config_path, error~)
  }
  let frontend_config = project_config.frontend
  let project_base = project.base_dir
  let frontend_url = frontend_config
    .map(config => config.dev_url)
    .unwrap_or(None)
  let moon_target_dir = raw.moon_target_dir.map(path => {
    @fsutil.resolve_path(cwd, path)
  })
  let frontend_command = frontend_config
    .map(config => config.before_dev)
    .unwrap_or(None)
  validate_frontend_dev_url(frontend_url, raw.ready_path)
  let managed_frontend_command = managed_frontend_command(
    frontend_url,
    frontend_command,
    raw.start_frontend,
  )
  if raw.start_frontend {
    ensure_frontend_url_available(frontend_url)
  }
  let frontend_path = frontend_config.map(config => config.path).unwrap_or(None)
  let frontend_working_dir = resolve_frontend_path(
    project_base,
    frontend_path,
    managed_frontend_command is Some(_),
  )
  let backend = project_config.backend
  let backend_path = resolve_backend_path(
    project_base,
    backend.map(fn(config) { config.path }),
  )
  let app_package = backend
    .map(config => config.app_package)
    .unwrap_or(default_package)
  let (runtime, subprocess_path) = prepare_dev_installation()
  let snapshot_dir = @async_fs.tmpdir(prefix="proton-dev-config-")
  defer @async_fs.rmdir(snapshot_dir, recursive=true)
  let snapshot_path = @fsutil.path_join(snapshot_dir, "proton.project.json")
  @async_fs.write_file(
    snapshot_path,
    project_config.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  let app_env = dev_process_env(
    runtime, subprocess_path, frontend_url, project_base, snapshot_path,
  )
  let frontend_env = dev_frontend_process_env(
    app_env,
    @env.get_env_var("LD_PRELOAD"),
  )
  @async.with_task_group(group => {
    // Announce the wait before the frontend child starts writing to the
    // terminal, so its startup output cannot interleave with this line.
    announce_frontend_server_wait(frontend_url, raw.ready_path)
    let frontend_process = match managed_frontend_command {
      Some(command) =>
        Some(start_frontend(group, frontend_working_dir, command, frontend_env))
      None => None
    }
    defer cancel_frontend(frontend_process)
    wait_for_frontend(
      frontend_url,
      raw.ready_path,
      raw.timeout_ms,
      frontend_process,
    )
    let code = run_app(
      backend_path,
      app_package,
      raw.app_args,
      app_env,
      moon_target_dir,
    )
    if code != 0 {
      raise DevProcessError::Exit(role="app", code~)
    }
  })
}

///|
fn dev_options_from_matches(
  matches : @argparse.Matches,
) -> RawDevOptions raise DevUsageError {
  guard! matches.values
    is {
      "timeout-ms": [timeout, ..],
      "package"? : Some(app_package)
      | (None with app_package = []),
      "config"? : Some(config_path)
      | (None with config_path = []),
      "moon-target-dir"? : Some(moon_target_dir)
      | (None with moon_target_dir = []),
      "url"? : Some(url)
      | (None with url = []),
      "command"? : Some(command)
      | (None with command = []),
      "frontend-path"? : Some(frontend_path)
      | (None with frontend_path = []),
      "ready-path"? : Some(ready_path)
      | (None with ready_path = []),
      "app-args"? : Some(app_args)
      | (None with app_args = []),
      ..
    }
  guard matches.flags
    is {
      "no-frontend"? : Some(no_frontend)
      | (None with no_frontend = false),
      ..
    }
  RawDevOptions::{
    app_package: app_package.get(0),
    config_path: config_path.get(0),
    moon_target_dir: moon_target_dir.get(0),
    url: url.get(0),
    command: command.get(0),
    frontend_path: frontend_path.get(0),
    timeout_ms: parse_non_negative_int(timeout, "--timeout-ms"),
    ready_path: ready_path.get(0),
    start_frontend: !no_frontend,
    app_args,
  }
}

///|
fn parse_non_negative_int(
  value : String,
  label : String,
) -> Int32 raise DevUsageError {
  let parsed = @string.parse_int(value[:]) catch {
    _ => raise InvalidNonNegativeInteger(option=label, value~)
  }
  if parsed < 0 {
    raise InvalidNonNegativeInteger(option=label, value~)
  } else {
    parsed
  }
}

///|
async fn resolve_frontend_path(
  root : String,
  frontend_path : String?,
  start_frontend : Bool,
) -> String {
  if !start_frontend {
    return root
  }
  match frontend_path {
    None => root
    Some(configured_path) => {
      let path = @fsutil.resolve_path(root, configured_path)
      if !@fsutil.path_exists(path) {
        raise FrontendDirectoryMissing(path~)
      } else if !@fsutil.path_is_dir(path) {
        raise FrontendDirectoryNotDirectory(path~)
      } else {
        path
      }
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
        raise BackendDirectoryMissing(path~)
      } else if !@fsutil.path_is_dir(path) {
        raise BackendDirectoryNotDirectory(path~)
      } else {
        path
      }
    }
  }
}

///|
async fn resolve_dev_config_path(cwd : String, raw : RawDevOptions) -> String {
  let path = match raw.config_path {
    Some(path) => @fsutil.resolve_path(cwd, path)
    None => @fsutil.path_join(cwd, default_config_file)
  }
  guard @fsutil.path_exists(path) else { raise NotFound(path~) }
  path
}

///|
async fn read_dev_project_config(
  path : String,
) -> @project.Project raise DevConfigError {
  @project.load(path) catch {
    error => raise Invalid(path~, error~)
  }
}

///|
fn effective_dev_config(
  config : @proton_config.AppConfig,
  raw : RawDevOptions,
) -> @proton_config.AppConfig {
  let frontend = if raw.url is Some(_) ||
    raw.command is Some(_) ||
    raw.frontend_path is Some(_) {
    let frontend = config.frontend.unwrap_or(@proton_config.FrontendConfig())
    Some({
      ..frontend,
      dev_url: match raw.url {
        Some(value) => Some(value)
        None => frontend.dev_url
      },
      before_dev: match raw.command {
        Some(value) => Some(value)
        None => frontend.before_dev
      },
      path: match raw.frontend_path {
        Some(value) => Some(value)
        None => frontend.path
      },
    })
  } else {
    config.frontend
  }
  let backend = match raw.app_package {
    Some(app_package) => {
      let backend = config.backend.unwrap_or(
        @proton_config.BackendConfig(".", default_package),
      )
      Some({ ..backend, app_package, })
    }
    None => config.backend
  }
  { ..config, frontend, backend, }
}

///|
async fn prepare_dev_installation() -> (DevRuntime, String) {
  // A caller-supplied subprocess executable remains authoritative for source development.
  let custom_subprocess = @env.get_env_var("PROTON_SUBPROCESS_PATH")
    is Some(path) &&
    path.trim() != ""
  let runtime = @cef_store.setup_default(runtime_only=custom_subprocess)
  let subprocess = match @env.get_env_var("PROTON_SUBPROCESS_PATH") {
    Some(path) if path.trim() != "" => path
    _ => @cef_store.resolve_default_subprocess()
  }
  (
    dev_runtime_from_root(
      runtime.runtime_root(),
      runtime.platform(),
      "Proton runtime store",
    ),
    subprocess,
  )
}

///|
async fn dev_runtime_from_root(
  runtime_root : String,
  platform : String,
  label : String,
) -> DevRuntime {
  let bin_dir = @fsutil.path_join(runtime_root, "bin")
  if !@fsutil.path_exists(runtime_root) {
    raise DirectoryMissing(label~, path=runtime_root)
  }
  DevRuntime::{ root: runtime_root, bin_dir, platform, }
}

///|
fn validate_frontend_dev_url(
  frontend_url : String?,
  ready_path : String?,
) -> Unit raise DevServerError {
  match frontend_url {
    None => ()
    Some(url) => ignore(parse_dev_url_endpoint(url, ready_path))
  }
}

///|
fn dev_process_env(
  runtime : DevRuntime,
  subprocess_path : String,
  frontend_url : String?,
  resource_dir : String,
  project_config : String,
) -> Map[String, String] {
  let env : Map[String, String] = {
    "PROTON_MODE": "dev",
    "MOON_XLOG": @env.get_env_var("MOON_XLOG").unwrap_or("info"),
    "PROTON_LOG_OUTPUT": @env.get_env_var("PROTON_LOG_OUTPUT").unwrap_or(
      "stderr",
    ),
    "PROTON_RUNTIME_ROOT": runtime.root,
    "PROTON_SUBPROCESS_PATH": subprocess_path,
    "PROTON_RESOURCE_DIR": resource_dir,
    "PROTON_PROJECT_CONFIG": project_config,
  }
  match frontend_url {
    Some(url) => env["PROTON_FRONTEND_URL"] = url
    None => ()
  }
  if runtime.platform.has_prefix("win32-") {
    let path_key = path_env_key()
    env[path_key] = prepend_env_path(
      runtime.bin_dir,
      current_env_value(path_key),
    )
  } else if runtime.platform.has_prefix("linux-") {
    env["LD_LIBRARY_PATH"] = prepend_env_path(
      runtime.bin_dir,
      current_env_value("LD_LIBRARY_PATH"),
    )
    // Keep the preload entry free of path separators so runtime roots
    // containing spaces remain valid. LD_LIBRARY_PATH resolves this name.
    env["LD_PRELOAD"] = prepend_env_path(
      "libcef.so",
      current_env_value("LD_PRELOAD"),
    )
  }
  env
}

///|
fn dev_frontend_process_env(
  app_env : Map[String, String],
  parent_preload : String?,
) -> Map[String, String] {
  let env = app_env.copy()
  // Linux CEF preloading belongs to the Proton app only. Frontend commands
  // such as Node/Vite must retain the CLI process's original preload state.
  match parent_preload {
    Some(value) => env["LD_PRELOAD"] = value
    None => env.remove("LD_PRELOAD")
  }
  env
}

///|
fn path_env_key() -> String {
  if @path.sep == '\\' {
    match @env.get_env_var("Path") {
      Some(_) => "Path"
      None => "PATH"
    }
  } else {
    "PATH"
  }
}

///|
fn current_env_value(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
fn prepend_env_path(path : String, existing : String) -> String {
  if existing == "" {
    path
  } else if path == "" {
    existing
  } else {
    path + path_list_separator() + existing
  }
}

///|
fn path_list_separator() -> String {
  if @path.sep == '\\' {
    ";"
  } else {
    ":"
  }
}

///|
async fn[X] start_frontend(
  group : @async.TaskGroup[X],
  frontend_path : String,
  command : String,
  env : Map[String, String],
) -> @process.Process raise DevProcessError {
  @output.info("Starting frontend: " + command)
  @output.info("Frontend path: " + frontend_path)
  let (program, args) = @project.shell_command(command)
  @process.spawn(
    group,
    program,
    args,
    cwd=frontend_path,
    extra_env=env,
    cancel_handler=frontend_cancel_handler(),
    no_wait=true,
  ) catch {
    err => raise Start(role="frontend command", detail=@debug.render(Repr(err)))
  }
}

///|
fn managed_frontend_command(
  frontend_url : String?,
  frontend_command : String?,
  start_frontend : Bool,
) -> String? raise DevConfigError {
  if !start_frontend {
    return None
  }
  match (frontend_url, frontend_command) {
    (Some(_), None) => raise FrontendCommandMissing
    (_, command) => command
  }
}

///|
fn frontend_cancel_handler() -> @process.CancellationHandler {
  if @path.sep == '\\' {
    @process.CancellationHandler(async fn(pid) {
      ignore(
        @process.run(
          "taskkill",
          ["/pid", pid.to_string(), "/t", "/f"],
          no_console_window=true,
          cancel_handler=@process.hard_cancel(),
        ),
      )
    })
  } else {
    @process.CancellationHandler(async fn(pid) {
      terminate_unix_frontend_tree(pid, "TERM")
      @async.sleep(1000)
      terminate_unix_frontend_tree(pid, "KILL")
    })
  }
}

///|
async fn terminate_unix_frontend_tree(pid : Int32, signal : String) -> Unit {
  ignore(
    @process.run(
      "sh",
      [
        "-c",
        unix_frontend_tree_kill_script(),
        "proton-frontend-cancel",
        pid.to_string(),
        signal,
      ],
      no_console_window=true,
    ),
  )
}

///|
fn unix_frontend_tree_kill_script() -> String {
  (
    #|kill_tree() {
    #|  parent="$1"
    #|  signal="$2"
    #|  if command -v pgrep >/dev/null 2>&1; then
    #|    for child in $(pgrep -P "$parent" 2>/dev/null); do
    #|      kill_tree "$child" "$signal"
    #|    done
    #|  fi
    #|  kill "-$signal" "$parent" 2>/dev/null || true
    #|}
    #|kill_tree "$1" "$2"
  )
}

///|
/// Prints the dev-server wait line. Called before the frontend process
/// spawns: the child inherits the terminal, and its startup banner would
/// otherwise race with (and partially overwrite) this line.
async fn announce_frontend_server_wait(
  frontend_url : String?,
  ready_path : String?,
) -> Unit {
  match frontend_url {
    None => ()
    Some(url) => {
      let endpoint = parse_dev_url_endpoint(url, ready_path)
      @output.info("Waiting for frontend dev server: " + endpoint.url)
    }
  }
}

///|
async fn wait_for_frontend(
  frontend_url : String?,
  ready_path : String?,
  timeout_ms : Int32,
  frontend_process : @process.Process?,
) -> Unit {
  match frontend_url {
    None => ()
    Some(url) => {
      let endpoint = parse_dev_url_endpoint(url, ready_path)
      validate_ready_probe(ready_path)
      let mut elapsed = 0
      while elapsed <= timeout_ms {
        match frontend_exit_code(frontend_process) {
          Some(code) => raise DevServerError::FrontendExited(code~)
          None => ()
        }
        if server_ready(endpoint, ready_path) {
          return
        }
        @async.sleep(ready_poll_interval_ms)
        elapsed = elapsed + ready_poll_interval_ms
      }
      raise DevServerError::Timeout(url=endpoint.url)
    }
  }
}

///|
async fn validate_ready_probe(ready_path : String?) -> Unit {
  match ready_path {
    Some(_) =>
      if command_exists("curl") {
        ()
      } else {
        raise DevServerError::ReadyProbeUnavailable
      }
    None => ()
  }
}

///|
/// Rejects an occupied endpoint before Proton starts a managed frontend.
async fn ensure_frontend_url_available(frontend_url : String?) -> Unit {
  match frontend_url {
    None => ()
    Some(url) => {
      let endpoint = parse_dev_url_endpoint(url, None)
      if tcp_ready(endpoint.host, endpoint.port) {
        raise FrontendUrlInUse(url~)
      }
    }
  }
}

///|
async fn command_exists(command : String) -> Bool {
  let args = if @path.sep == '\\' {
    ["/c", "where", command, ">NUL", "2>NUL"]
  } else {
    ["-c", "command -v " + shell_quote(command) + " >/dev/null 2>&1"]
  }
  let program = if @path.sep == '\\' { "cmd" } else { "sh" }
  let code = @process.run(program, args, no_console_window=true) catch {
    _ => return false
  }
  code == 0
}

///|
fn shell_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\\''") + "'"
}

///|
fn frontend_exit_code(process : @process.Process?) -> Int32? {
  match process {
    None => None
    Some(process) => process.try_wait() catch { _ => Some(-1) }
  }
}

///|
async fn tcp_ready(host : String, port : Int32) -> Bool {
  let result = @async.with_timeout_opt(ready_probe_timeout_ms, () => {
    let conn = @socket.Tcp::connect_to_host(host, port~)
    conn.close()
    true
  }) catch {
    _ => return false
  }
  match result {
    Some(true) => true
    _ => false
  }
}

///|
async fn server_ready(endpoint : DevUrlEndpoint, ready_path : String?) -> Bool {
  match ready_path {
    Some(_) => http_ready(endpoint.url)
    None => tcp_ready(endpoint.host, endpoint.port)
  }
}

///|
async fn http_ready(url : String) -> Bool {
  let (code, _) = @process.collect_output_merged("curl", [
    "-fsS",
    "--max-time",
    "2",
    "-o",
    dev_null_path(),
    url,
  ]) catch {
    _ => return false
  }
  code == 0
}

///|
fn dev_null_path() -> String {
  if @path.sep == '\\' {
    "NUL"
  } else {
    "/dev/null"
  }
}

///|
fn parse_dev_url_endpoint(
  url : String,
  ready_path : String?,
) -> DevUrlEndpoint raise DevServerError {
  let parsed = @proton_config.parse_http_url(url) catch {
    error =>
      match error {
        MissingScheme => raise DevServerError::MissingScheme(url~)
        UnsupportedScheme => raise DevServerError::UnsupportedScheme(url~)
        MissingHost => raise EmptyHost
        InvalidOrigin(_) => raise DevServerError::InvalidOrigin(url~)
        EmptyPort => raise InvalidPort(value="")
        ZeroPort => raise PortOutOfRange(value="0")
      }
  }
  let wait_url = match ready_path {
    Some(path) if path.has_prefix("/") => parsed.origin + path
    Some(path) if path != "" => parsed.origin + "/" + path
    _ => url
  }
  { url: wait_url, host: parsed.host, port: parsed.port, }
}

///|
async fn run_app(
  root : String,
  app_package : String,
  app_args : Array[String],
  env : Map[String, String],
  moon_target_dir : String?,
) -> Int32 raise DevProcessError {
  let moon_args : Array[String] = []
  match moon_target_dir {
    Some(target_dir) => {
      moon_args.push("--target-dir")
      moon_args.push(target_dir)
    }
    None => ()
  }
  moon_args.push("run")
  moon_args.push(app_package)
  moon_args.push("--target")
  moon_args.push("native")
  if app_args.length() > 0 {
    moon_args.push("--")
    for arg in app_args {
      moon_args.push(arg)
    }
  }
  @output.info("Starting Proton app: moon " + moon_args.join(" "))
  let moon_env = @build.native_moon_process_env()
  for key, value in env {
    moon_env[key] = value
  }
  let code = @process.run("moon", moon_args, cwd=root, extra_env=moon_env) catch {
    err => raise Start(role="MoonBit app", detail=@debug.render(Repr(err)))
  }
  code
}

///|
fn cancel_frontend(process : @process.Process?) -> Unit {
  match process {
    Some(process) => process.cancel()
    None => ()
  }
}
