///|
let default_package = "app"

///|
let default_config_file = "moon.proton"

///|
let default_timeout_ms = 30000

///|
let ready_poll_interval_ms = 100

///|
let ready_probe_timeout_ms = 1000

///|
struct RawDevOptions {
  app_package : String
  config_path : String?
  url : String?
  command : String?
  frontend_cwd : String?
  timeout_ms : Int
  ready_path : String?
  wait_for_dev_server : Bool
  start_frontend : Bool
  setup_runtime : Bool
  app_args : Array[String]
} derive(Debug, Eq)

///|
struct DevRuntime {
  root : String
  bin_dir : String
  lib_dir : String
  helper_path : String
} derive(Debug, Eq)

///|
struct DevUrlEndpoint {
  url : String
  host : String
  port : Int
} derive(Debug, Eq)

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
      OptionArg(
        "package",
        default_values=[default_package],
        about="MoonBit application package",
      ),
      OptionArg(
        "config",
        allow_hyphen_values=true,
        about="Proton project config",
      ),
      OptionArg("url", about="Override frontend.dev_url"),
      OptionArg("command", about="Override frontend.before_dev"),
      OptionArg("frontend-cwd", about="Override frontend.cwd"),
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
  let root = find_project_root_from(cwd)
  let config_path = resolve_dev_config_path(cwd, root, raw)
  let frontend_config = load_dev_frontend_config(config_path)
  let frontend_url : String? = match raw.url {
    Some(url) => Some(url)
    None =>
      match frontend_config {
        Some(config) => config.dev_url()
        None => None
      }
  }
  validate_frontend_dev_url(frontend_url, raw.ready_path)
  let frontend_command : String? = match raw.command {
    Some(command) => Some(command)
    None =>
      match frontend_config {
        Some(config) => config.before_dev()
        None => None
      }
  }
  let frontend_cwd : String? = match raw.frontend_cwd {
    Some(cwd) => Some(cwd)
    None =>
      match frontend_config {
        Some(config) => config.cwd()
        None => None
      }
  }
  let frontend_working_dir = resolve_frontend_cwd(
    root,
    frontend_cwd,
    frontend_command,
    raw.start_frontend,
  )
  let runtime = ensure_dev_runtime(root, raw.setup_runtime)
  let env = dev_process_env(runtime, frontend_url, config_path)
  @async.with_task_group(group => {
    let frontend_process = maybe_start_frontend(
      group,
      frontend_working_dir,
      frontend_command,
      raw.start_frontend,
      env,
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
    let code = run_app(root, raw.app_package, raw.app_args, env)
    if code != 0 {
      raise DevProcessError::Exit(role="app", code~)
    }
  })
}

///|
fn dev_options_from_matches(
  matches : @argparse.Matches,
) -> RawDevOptions raise DevUsageError {
  let timeout = @cli_args.required_value(matches, "timeout-ms")
  RawDevOptions::{
    app_package: @cli_args.required_value(matches, "package"),
    config_path: @cli_args.value(matches, "config"),
    url: @cli_args.value(matches, "url"),
    command: @cli_args.value(matches, "command"),
    frontend_cwd: @cli_args.value(matches, "frontend-cwd"),
    timeout_ms: parse_non_negative_int(timeout, "--timeout-ms"),
    ready_path: @cli_args.value(matches, "ready-path"),
    wait_for_dev_server: !@cli_args.flag(matches, "no-dev-server-wait"),
    start_frontend: !@cli_args.flag(matches, "no-frontend"),
    setup_runtime: @cli_args.flag(matches, "setup"),
    app_args: @cli_args.values(matches, "app-args"),
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
fn resolve_frontend_cwd(
  root : String,
  frontend_cwd : String?,
  frontend_command : String?,
  start_frontend : Bool,
) -> String raise DevConfigError {
  if !start_frontend || frontend_command is None {
    return root
  }
  match frontend_cwd {
    None => root
    Some(cwd) => {
      let path = resolve_path(root, cwd)
      if !path_exists(path) {
        raise FrontendDirectoryMissing(path~)
      } else if !path_is_dir(path) {
        raise FrontendDirectoryNotDirectory(path~)
      } else {
        path
      }
    }
  }
}

///|
fn resolve_dev_config_path(
  cwd : String,
  root : String,
  raw : RawDevOptions,
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
fn load_dev_frontend_config(
  config_path : String?,
) -> @proton_config.ProjectFrontendConfig? raise DevConfigError {
  match config_path {
    None => None
    Some(path) => {
      if !path_exists(path) {
        raise NotFound(path~)
      }
      read_dev_frontend_config(path)
    }
  }
}

///|
fn read_dev_frontend_config(
  path : String,
) -> @proton_config.ProjectFrontendConfig? raise DevConfigError {
  let project = @proton_config.load_project_config_from_file(path) catch {
    error => raise Invalid(path~, error~)
  }
  project.frontend()
}

///|
async fn ensure_dev_runtime(
  root : String,
  setup_runtime : Bool,
) -> DevRuntime raise DevRuntimeError {
  let native_dist_override = dev_native_dist_override(root)
  read_dev_runtime(root) catch {
    error =>
      match native_dist_override {
        Some(_) => raise NativeDistOverride(detail=error.message())
        None if setup_runtime => {
          @cef.setup_default(root) catch {
            error => raise Setup(detail=error.to_string())
          }
          read_dev_runtime(root)
        }
        None => raise SetupRequired(detail=error.message())
      }
  }
}

///|
async fn read_dev_runtime(root : String) -> DevRuntime raise DevRuntimeError {
  match dev_native_dist_override(root) {
    Some(path) => return dev_runtime_from_root(path, "PROTON_NATIVE_DIST")
    None => ()
  }
  let manifest_path = runtime_manifest_path(root)
  let text = @mbfs.read_file_to_string(manifest_path, encoding="utf8") catch {
    _ => raise ManifestMissing(path=manifest_path)
  }
  let json = @json.parse(text) catch {
    err =>
      raise ManifestInvalid(
        path=manifest_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  let platform = json_string_field(json, "platform", manifest_path)
  let expected_platform = @cef.current_platform_id() catch {
    error =>
      raise ManifestInvalid(
        path=manifest_path,
        detail="failed to detect host platform: " + error.to_string(),
      )
  }
  if platform != expected_platform {
    raise PlatformMismatch(expected=expected_platform, actual=platform)
  }
  let dist = json_string_field(json, "dist", manifest_path)
  dev_runtime_from_root(resolve_path(root, dist), "active Proton runtime")
}

///|
fn dev_native_dist_override(root : String) -> String? {
  match @sys.get_env_var("PROTON_NATIVE_DIST") {
    Some(value) => {
      let value = value.trim().to_owned()
      if value == "" {
        None
      } else {
        Some(resolve_path(root, value))
      }
    }
    None => None
  }
}

///|
fn dev_runtime_from_root(
  runtime_root : String,
  label : String,
) -> DevRuntime raise DevRuntimeError {
  let bin_dir = join_path(runtime_root, "bin")
  let lib_dir = join_path(runtime_root, "lib")
  let helper_path = join_path(bin_dir, helper_executable_name())
  if !path_exists(runtime_root) {
    raise DirectoryMissing(label~, path=runtime_root)
  }
  if !path_exists(helper_path) {
    raise HelperMissing(label~, path=helper_path)
  }
  DevRuntime::{ root: runtime_root, bin_dir, lib_dir, helper_path }
}

///|
fn runtime_manifest_path(root : String) -> String {
  join_path(join_path(root, ".proton"), "runtime.json")
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
fn json_string_field(
  json : Json,
  field : String,
  label : String,
) -> String raise DevRuntimeError {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => value
        _ => raise ManifestField(path=label, field~)
      }
    _ => raise ManifestInvalid(path=label, detail="root must be a JSON object")
  }
}

///|
fn helper_executable_name() -> String {
  if @path.sep == '\\' {
    "cef_process.exe"
  } else {
    "cef_process"
  }
}

///|
fn dev_process_env(
  runtime : DevRuntime,
  frontend_url : String?,
  config_path : String?,
) -> Map[String, String] {
  let env : Map[String, String] = {
    "PROTON_MODE": "dev",
    "PROTON_DEV": "1",
    "PROTON_HMR": "1",
    "PROTON_NATIVE_DIST": runtime.root,
    "PROTON_RUNTIME_ROOT": runtime.root,
    "PROTON_HELPER_PATH": runtime.helper_path,
  }
  match frontend_url {
    Some(url) => env["PROTON_FRONTEND_URL"] = url
    None => ()
  }
  match config_path {
    Some(path) => env["PROTON_CONFIG_PATH"] = path
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
  }
  env
}

///|
fn path_env_key() -> String {
  if @path.sep == '\\' {
    match @sys.get_env_var("Path") {
      Some(_) => "Path"
      None => "PATH"
    }
  } else {
    "PATH"
  }
}

///|
fn current_env_value(name : String) -> String {
  @sys.get_env_var(name).unwrap_or("")
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
  frontend_cwd : String,
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
      println("Starting frontend: " + command)
      println("Frontend cwd: " + frontend_cwd)
      let (program, args) = shell_command(command)
      let process = @process.spawn(
        group,
        program,
        args,
        cwd=frontend_cwd,
        extra_env=env,
        cancel_handler=frontend_cancel_handler(),
        no_wait=true,
      ) catch {
        err =>
          raise Start(
            role="frontend command",
            detail=@debug.render(@debug.to_repr(err)),
          )
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
      println("Waiting for frontend dev server: " + endpoint.url)
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
) -> Int raise DevProcessError {
  let moon_args : Array[String] = ["run", app_package, "--target", "native"]
  if app_args.length() > 0 {
    moon_args.push("--")
    for arg in app_args {
      moon_args.push(arg)
    }
  }
  println("Starting Proton app: moon " + moon_args.join(" "))
  let code = @process.run("moon", moon_args, cwd=root, extra_env=env) catch {
    err =>
      raise Start(role="MoonBit app", detail=@debug.render(@debug.to_repr(err)))
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
