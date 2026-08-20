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
struct RawDevOptions {
  app_package : String?
  config_path : String?
  moon_target_dir : String?
  url : String?
  command : String?
  frontend_path : String?
  timeout_ms : Int
  ready_path : String?
  wait_for_dev_server : Bool
  start_frontend : Bool
  setup_runtime : Bool
  app_args : Array[String]
} derive(Debug, Eq)

///|
pub extend RawDevOptions with Eq::{not_equal, equal}

///|
pub extend RawDevOptions with Debug::{to_repr}

///|
struct DevRuntime {
  root : String
  bin_dir : String
  lib_dir : String
} derive(Debug, Eq)

///|
pub extend DevRuntime with Eq::{not_equal, equal}

///|
pub extend DevRuntime with Debug::{to_repr}

///|
struct DevUrlEndpoint {
  url : String
  host : String
  port : Int
} derive(Debug, Eq)

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
        "no-dev-server-wait",
        about="Start the app without waiting for the frontend URL",
      ),
      FlagArg(
        "no-frontend",
        about="Do not start the configured frontend command",
      ),
      FlagArg(
        "setup",
        negatable=true,
        about="Install the runtime automatically when it is missing",
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
  let project_config = load_dev_project_config(config_path)
  let frontend_config = match project_config {
    Some(config) => config.frontend()
    None => None
  }
  let project_base = project_config
    .map(fn(config) { config.base_dir() })
    .unwrap_or(cwd)
  let frontend_url : String? = match raw.url {
    Some(url) => Some(url)
    None =>
      match frontend_config {
        Some(config) => config.dev_url()
        None => None
      }
  }
  let moon_target_dir = raw.moon_target_dir.map(path => {
    @fsutil.resolve_path(cwd, path)
  })
  validate_frontend_dev_url(frontend_url, raw.ready_path)
  let frontend_command : String? = match raw.command {
    Some(command) => Some(command)
    None =>
      match frontend_config {
        Some(config) => config.before_dev()
        None => None
      }
  }
  let frontend_path : String? = match raw.frontend_path {
    Some(path) => Some(@fsutil.resolve_path(project_base, path))
    None =>
      match frontend_config {
        Some(config) => config.path()
        None => None
      }
  }
  let frontend_working_dir = resolve_frontend_path(
    project_base,
    frontend_path,
    frontend_command,
    raw.start_frontend,
  )
  let backend = match project_config {
    Some(config) => config.backend()
    None => None
  }
  let backend_path = resolve_backend_path(
    project_base,
    backend.map(fn(config) { config.path() }),
  )
  let app_package = match raw.app_package {
    Some(app_package) => app_package
    None =>
      match backend {
        Some(config) => config.app_package()
        None => default_package
      }
  }
  let proton_source = @build.resolve_proton_source(backend_path, app_package)
  let runtime_requirements = @build.resolve_proton_runtime_requirements(
    proton_source,
  )
  let runtime = ensure_dev_runtime(runtime_requirements, raw.setup_runtime)
  let helper_path = @build.build_cef_process(
    proton_source,
    backend_path,
    moon_target_dir?,
  )
  let app_env = dev_process_env(
    runtime, helper_path, frontend_url, project_base,
  )
  let frontend_env = dev_frontend_process_env(
    app_env,
    @env.get_env_var("LD_PRELOAD"),
  )
  @async.with_task_group(group => {
    // Announce the wait before the frontend child starts writing to the
    // terminal, so its startup output cannot interleave with this line.
    if raw.wait_for_dev_server {
      announce_frontend_server_wait(frontend_url, raw.ready_path)
    }
    let frontend_process = maybe_start_frontend(
      group,
      frontend_working_dir,
      frontend_command,
      raw.start_frontend,
      frontend_env,
    )
    defer cancel_frontend(frontend_process)
    if raw.wait_for_dev_server {
      wait_for_frontend(
        frontend_url,
        raw.ready_path,
        raw.timeout_ms,
        frontend_process,
      )
    }
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
      "no-dev-server-wait"? : Some(no_dev_server_wait)
      | (None with no_dev_server_wait = false),
      "no-frontend"? : Some(no_frontend)
      | (None with no_frontend = false),
      "setup"? : Some(setup_runtime)
      | (None with setup_runtime = false),
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
    wait_for_dev_server: !no_dev_server_wait,
    start_frontend: !no_frontend,
    setup_runtime,
    app_args,
  }
}

///|
fn parse_non_negative_int(
  value : String,
  label : String,
) -> Int raise DevUsageError {
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
  frontend_command : String?,
  start_frontend : Bool,
) -> String {
  if !start_frontend || frontend_command is None {
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
async fn resolve_dev_config_path(cwd : String, raw : RawDevOptions) -> String? {
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
async fn load_dev_project_config(
  config_path : String?,
) -> @proton_config.ProjectConfig? {
  match config_path {
    None => None
    Some(path) => {
      if !@fsutil.path_exists(path) {
        raise NotFound(path~)
      }
      Some(read_dev_project_config(path))
    }
  }
}

///|
async fn read_dev_project_config(
  path : String,
) -> @proton_config.ProjectConfig raise DevConfigError {
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
  loaded.config()
}

///|
async fn ensure_dev_runtime(
  requirements : String,
  setup_runtime : Bool,
) -> DevRuntime {
  resolve_dev_runtime(requirements) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      if setup_runtime {
        ignore(@cef_store.install_declared(requirements)) catch {
          error if @async.is_being_cancelled() => raise error
          error => raise Setup(detail=error.to_string())
        }
        resolve_dev_runtime(requirements)
      } else {
        raise SetupRequired(detail=error.to_string())
      }
  }
}

///|
async fn resolve_dev_runtime(requirements : String) -> DevRuntime {
  let runtime = @cef_store.resolve_declared(requirements)
  dev_runtime_from_root(runtime.runtime_root(), "Proton runtime store")
}

///|
async fn dev_runtime_from_root(
  runtime_root : String,
  label : String,
) -> DevRuntime {
  let bin_dir = @fsutil.path_join(runtime_root, "bin")
  let lib_dir = @fsutil.path_join(runtime_root, "lib")
  if !@fsutil.path_exists(runtime_root) {
    raise DirectoryMissing(label~, path=runtime_root)
  }
  DevRuntime::{ root: runtime_root, bin_dir, lib_dir }
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
async fn dev_process_env(
  runtime : DevRuntime,
  helper_path : String,
  frontend_url : String?,
  resource_dir : String,
) -> Map[String, String] {
  let env : Map[String, String] = {
    "PROTON_MODE": "dev",
    "PROTON_DEV": "1",
    "PROTON_HMR": "1",
    "PROTON_RUNTIME_ROOT": runtime.root,
    "PROTON_HELPER_PATH": helper_path,
    "PROTON_RESOURCE_DIR": resource_dir,
  }
  match frontend_url {
    Some(url) => env["PROTON_FRONTEND_URL"] = url
    None => ()
  }
  let path_key = path_env_key()
  env[path_key] = prepend_env_path(runtime.bin_dir, current_env_value(path_key))
  if @path.sep != '\\' {
    env["LD_LIBRARY_PATH"] = prepend_env_path(
      runtime.lib_dir,
      prepend_env_path(runtime.bin_dir, current_env_value("LD_LIBRARY_PATH")),
    )
    env["DYLD_LIBRARY_PATH"] = prepend_env_path(
      runtime.lib_dir,
      prepend_env_path(runtime.bin_dir, current_env_value("DYLD_LIBRARY_PATH")),
    )
    if @fsutil.path_exists(@fsutil.path_join(runtime.bin_dir, "libcef.so")) {
      // Keep the preload entry free of path separators so Linux runtime roots
      // containing spaces remain valid. LD_LIBRARY_PATH resolves this name.
      env["LD_PRELOAD"] = prepend_env_path(
        "libcef.so",
        current_env_value("LD_PRELOAD"),
      )
    }
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
/// Finalizes the environment for the app child process on Windows.
///
/// `@process.run` appends the inherited environment block after `extra_env`,
/// so the block handed to `moon` contains every overridden variable twice.
/// `moon` launches the app through Rust's process API, which rebuilds the
/// environment block and keeps the *last* duplicate of each variable; the
/// inherited original `Path` therefore shadows the prepended runtime `bin`
/// directory and the app exits immediately with 0xC0000135 because
/// CEF libraries are not on its DLL search path.
/// Returning a complete environment with the overrides applied and spawning
/// with `inherit_env=false` keeps exactly one entry per variable, so the
/// runtime `bin` directory survives the handoff.
#cfg(all(platform="windows", target="native"))
fn dev_app_spawn_env(
  overrides : Map[String, String],
) -> (Map[String, String], Bool) {
  let env = dev_windows_parent_env()
  for key, value in overrides {
    // Variable names are case-insensitive on Windows; drop any inherited
    // spelling of an overridden name so only one entry remains.
    for existing in env.keys().collect() {
      if existing != key && existing.to_lower() == key.to_lower() {
        env.remove(existing)
      }
    }
    env[key] = value
  }
  (env, false)
}

///|
/// Non-Windows platforms keep the existing behavior: the child inherits the
/// parent environment and `extra_env` carries the overrides, leaving the
/// established rpath and loader-variable handling untouched.
#cfg(any(not(platform="windows"), target="wasm"))
fn dev_app_spawn_env(
  overrides : Map[String, String],
) -> (Map[String, String], Bool) {
  (overrides, true)
}

///|
#cfg(all(platform="windows", target="native"))
extern "C" fn dev_windows_env_block() -> String = "proton_cli_dev_env_block"

///|
/// Reads the parent process environment block with the original variable
/// names and values preserved. The wide-character block is used instead of
/// `@env.get_env_vars` so non-ASCII values survive the round trip into the
/// child process environment.
#cfg(all(platform="windows", target="native"))
fn dev_windows_parent_env() -> Map[String, String] {
  let env : Map[String, String] = Map([])
  for entry in dev_windows_env_block().split("\u{0}") {
    match entry.split_once("=") {
      Some((key, value)) =>
        // Nameless entries are per-drive current-directory records such as
        // `=C:`; the child defaults them to its own working directory.
        if key != "" {
          env[key.to_owned()] = value.to_owned()
        }
      None => ()
    }
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
async fn[X] maybe_start_frontend(
  group : @async.TaskGroup[X],
  frontend_path : String,
  command : String?,
  start_frontend : Bool,
  env : Map[String, String],
) -> @process.Process? raise DevProcessError {
  if !start_frontend {
    return None
  }
  match command {
    None => None
    Some(command) => {
      @output.info("Starting frontend: " + command)
      @output.info("Frontend path: " + frontend_path)
      let (program, args) = shell_command(command)
      let process = @process.spawn(
        group,
        program,
        args,
        cwd=frontend_path,
        extra_env=env,
        cancel_handler=frontend_cancel_handler(),
        no_wait=true,
      ) catch {
        err =>
          raise Start(role="frontend command", detail=@debug.render(Repr(err)))
      }
      Some(process)
    }
  }
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
async fn terminate_unix_frontend_tree(pid : Int, signal : String) -> Unit {
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
  timeout_ms : Int,
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
fn frontend_exit_code(process : @process.Process?) -> Int? {
  match process {
    None => None
    Some(process) => process.try_wait() catch { _ => Some(-1) }
  }
}

///|
async fn tcp_ready(host : String, port : Int) -> Bool {
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
  let wait_url = append_ready_path(url, ready_path)
  let (scheme, rest) = match wait_url.split_once("://") {
    Some((scheme, rest)) => (scheme.to_owned().to_lower(), rest.to_owned())
    None => raise MissingScheme(url=wait_url)
  }
  let default_port = match scheme {
    "http" => 80
    "https" => 443
    _ => raise UnsupportedScheme(url=wait_url)
  }
  let authority = url_authority(rest)
  if !dev_url_authority_is_valid(authority) {
    raise InvalidOrigin(url=wait_url)
  }
  let (host, port) = parse_host_port(authority, default_port)
  DevUrlEndpoint::{ url: wait_url, host, port }
}

///|
fn url_authority(rest : String) -> String {
  let mut end = rest.length()
  for delimiter in ["/", "?", "#"] {
    match rest.find(delimiter) {
      Some(index) if index < end => end = index
      _ => ()
    }
  }
  rest.unsafe_substring(start=0, end~).to_string()
}

///|
fn dev_url_authority_is_valid(authority : String) -> Bool {
  if authority == "" || authority.contains("@") {
    return false
  }
  for ch in authority {
    let code = ch.to_int()
    if code <= 0x20 ||
      code >= 0x7f ||
      ch == '/' ||
      ch == '?' ||
      ch == '#' ||
      ch == '"' ||
      ch == '\\' {
      return false
    }
  }
  true
}

///|
fn parse_host_port(
  host_port : String,
  default_port : Int,
) -> (String, Int) raise DevServerError {
  if host_port.has_prefix("[") {
    match host_port.split_once("]") {
      Some((left, right)) => {
        let left = left.to_owned()
        let host = left.unsafe_substring(start=1, end=left.length())
        let port = if right == "" {
          default_port
        } else if right.has_prefix(":") {
          parse_port(right[1:].to_owned())
        } else {
          raise InvalidHost(authority=host_port)
        }
        if host == "" {
          raise EmptyHost
        } else {
          (host, port)
        }
      }
      None => raise InvalidHost(authority=host_port)
    }
  } else {
    match host_port.split_once(":") {
      Some((host, port_text)) => {
        let host = host.to_owned()
        if host == "" {
          raise EmptyHost
        } else {
          (host, parse_port(port_text.to_owned()))
        }
      }
      None =>
        if host_port == "" {
          raise EmptyHost
        } else {
          (host_port, default_port)
        }
    }
  }
}

///|
fn parse_port(text : String) -> Int raise DevServerError {
  let port = @string.parse_int(text[:]) catch {
    _ => raise InvalidPort(value=text)
  }
  if port <= 0 || port > 65535 {
    raise PortOutOfRange(value=text)
  } else {
    port
  }
}

///|
fn append_ready_path(url : String, ready_path : String?) -> String {
  match ready_path {
    None => url
    Some(path) =>
      if path == "" {
        url
      } else if path.has_prefix("/") {
        url_origin(url) + path
      } else {
        url_origin(url) + "/" + path
      }
  }
}

///|
fn url_origin(url : String) -> String {
  match url.split_once("://") {
    Some((scheme, rest)) => {
      let authority = url_authority(rest.to_owned())
      scheme.to_owned() + "://" + authority
    }
    None => url
  }
}

///|
async fn run_app(
  root : String,
  app_package : String,
  app_args : Array[String],
  env : Map[String, String],
  moon_target_dir : String?,
) -> Int raise DevProcessError {
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
  let (spawn_env, inherit_env) = dev_app_spawn_env(moon_env)
  let code = @process.run(
    "moon",
    moon_args,
    cwd=root,
    extra_env=spawn_env,
    inherit_env~,
  ) catch {
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
