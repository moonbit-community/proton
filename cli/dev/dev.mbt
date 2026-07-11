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
pub(all) enum DevError {
  UsageError(String, Bool)
  CommandError(String)
}

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
pub async fn run(cwd : String, args : Array[String]) -> Result[Unit, DevError] {
  if args.contains("-h") || args.contains("--help") {
    print_dev_usage()
    return Ok(())
  }
  let raw = match parse_dev_args(args) {
    Ok(raw) => raw
    Err(error) => return Err(error)
  }
  let cwd = @path.Path(cwd).resolve().to_string()
  let root = find_project_root_from(cwd)
  let config_path = resolve_dev_config_path(cwd, root, raw)
  let frontend_config = match load_dev_frontend_config(config_path) {
    Ok(config) => config
    Err(message) => return Err(CommandError(message))
  }
  let frontend_url : String? = match raw.url {
    Some(url) => Some(url)
    None =>
      match frontend_config {
        Some(config) => config.dev_url()
        None => None
      }
  }
  match validate_frontend_dev_url(frontend_url, raw.ready_path) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
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
  let frontend_working_dir = match
    resolve_frontend_cwd(
      root,
      frontend_cwd,
      frontend_command,
      raw.start_frontend,
    ) {
    Ok(path) => path
    Err(error) => return Err(error)
  }
  let runtime = match ensure_dev_runtime(root, raw.setup_runtime) {
    Ok(runtime) => runtime
    Err(error) => return Err(error)
  }
  let env = dev_process_env(runtime, frontend_url, config_path)
  @async.with_task_group(group => {
    let frontend_process = match
      maybe_start_frontend(
        group,
        frontend_working_dir,
        frontend_command,
        raw.start_frontend,
        env,
      ) {
      Ok(process) => process
      Err(error) => return Err(error)
    }
    defer cancel_frontend(frontend_process)
    if raw.wait_for_dev_server {
      match
        wait_for_frontend(
          frontend_url,
          raw.ready_path,
          raw.timeout_ms,
          frontend_process,
        ) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    }
    let code = match run_app(root, raw.app_package, raw.app_args, env) {
      Ok(code) => code
      Err(error) => return Err(error)
    }
    if code == 0 {
      Ok(())
    } else {
      Err(CommandError("app exited with code " + code.to_string()))
    }
  })
}

///|
fn print_dev_usage() -> Unit {
  let usage =
    #|Usage:
    #|  proton_cli [-C DIR] dev [PACKAGE] [OPTIONS] [-- [APP_ARGS]...]
    #|
    #|Options:
    #|  --config <path>          Proton project config (default: package/cwd/root moon.proton)
    #|  --url <url>              Override frontend.dev_url
    #|  --command <command>      Override frontend.before_dev
    #|  --frontend-cwd <dir>     Override frontend.cwd
    #|  --timeout-ms <ms>        Dev server wait timeout (default: 30000)
    #|  --ready-path <path>      HTTP path that must return below 400
    #|  --no-dev-server-wait     Start the app without waiting for --url
    #|  --no-frontend            Do not start frontend.before_dev
    #|  --setup                  Run `proton_cli cef setup` if runtime is missing
    #|  --no-setup               Do not install the runtime automatically
    #|
  println(usage)
}

///|
fn parse_dev_args(args : Array[String]) -> Result[RawDevOptions, DevError] {
  let app_args : Array[String] = []
  let mut app_package : String? = None
  let mut config_path : String? = None
  let mut url : String? = None
  let mut command : String? = None
  let mut frontend_cwd : String? = None
  let mut timeout_ms = default_timeout_ms
  let mut ready_path : String? = None
  let mut wait_for_dev_server = true
  let mut start_frontend = true
  let mut setup_runtime = false
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "--" {
      for value in args[index + 1:] {
        app_args.push(value)
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
    } else if arg == "--url" {
      match read_option_value(args, index, "--url") {
        Ok(value) => {
          url = Some(value)
          index = index + 2
        }
        Err(error) => return Err(error)
      }
    } else if arg == "--command" {
      match read_option_value(args, index, "--command") {
        Ok(value) => {
          command = Some(value)
          index = index + 2
        }
        Err(error) => return Err(error)
      }
    } else if arg == "--frontend-cwd" {
      match read_option_value(args, index, "--frontend-cwd") {
        Ok(value) => {
          frontend_cwd = Some(value)
          index = index + 2
        }
        Err(error) => return Err(error)
      }
    } else if arg == "--timeout-ms" {
      match read_option_value(args, index, "--timeout-ms") {
        Ok(value) =>
          match parse_non_negative_int(value, "--timeout-ms") {
            Ok(parsed) => {
              timeout_ms = parsed
              index = index + 2
            }
            Err(error) => return Err(error)
          }
        Err(error) => return Err(error)
      }
    } else if arg == "--ready-path" {
      match read_option_value(args, index, "--ready-path") {
        Ok(value) => {
          ready_path = Some(value)
          index = index + 2
        }
        Err(error) => return Err(error)
      }
    } else if arg == "--no-dev-server-wait" {
      wait_for_dev_server = false
      index = index + 1
    } else if arg == "--no-frontend" {
      start_frontend = false
      index = index + 1
    } else if arg == "--setup" {
      setup_runtime = true
      index = index + 1
    } else if arg == "--no-setup" {
      setup_runtime = false
      index = index + 1
    } else if arg.has_prefix("-") {
      return Err(UsageError("unknown dev option: " + arg, false))
    } else {
      match app_package {
        None => {
          app_package = Some(arg)
          index = index + 1
        }
        Some(_) =>
          return Err(UsageError("unexpected dev argument: " + arg, false))
      }
    }
  }
  Ok(RawDevOptions::{
    app_package: app_package.unwrap_or(default_package),
    config_path,
    url,
    command,
    frontend_cwd,
    timeout_ms,
    ready_path,
    wait_for_dev_server,
    start_frontend,
    setup_runtime,
    app_args,
  })
}

///|
fn read_option_value(
  args : Array[String],
  index : Int,
  name : String,
) -> Result[String, DevError] {
  if index + 1 >= args.length() {
    Err(UsageError("missing value for " + name, false))
  } else {
    let value = args[index + 1]
    if value == "" {
      Err(UsageError(name + " must not be empty", false))
    } else {
      Ok(value)
    }
  }
}

///|
fn parse_non_negative_int(
  value : String,
  label : String,
) -> Result[Int, DevError] {
  let parsed = @string.parse_int(value[:]) catch {
    _ =>
      return Err(UsageError(label + " must be a non-negative integer", false))
  }
  if parsed < 0 {
    Err(UsageError(label + " must be a non-negative integer", false))
  } else {
    Ok(parsed)
  }
}

///|
fn resolve_frontend_cwd(
  root : String,
  frontend_cwd : String?,
  frontend_command : String?,
  start_frontend : Bool,
) -> Result[String, DevError] {
  if !start_frontend || frontend_command is None {
    return Ok(root)
  }
  match frontend_cwd {
    None => Ok(root)
    Some(cwd) => {
      let path = resolve_path(root, cwd)
      if !path_exists(path) {
        Err(CommandError("frontend cwd does not exist: " + path))
      } else if !path_is_dir(path) {
        Err(CommandError("frontend cwd is not a directory: " + path))
      } else {
        Ok(path)
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
) -> Result[@proton_config.ProjectFrontendConfig?, String] {
  match config_path {
    None => Ok(None)
    Some(path) => {
      if !path_exists(path) {
        return Err("proton dev config not found: " + path)
      }
      read_dev_frontend_config(path)
    }
  }
}

///|
fn read_dev_frontend_config(
  path : String,
) -> Result[@proton_config.ProjectFrontendConfig?, String] {
  @proton_config.load_project_config_from_file(path).map(fn(project) {
    project.frontend()
  })
}

///|
async fn ensure_dev_runtime(
  root : String,
  setup_runtime : Bool,
) -> Result[DevRuntime, DevError] {
  let native_dist_override = dev_native_dist_override(root)
  match read_dev_runtime(root) {
    Ok(runtime) => Ok(runtime)
    Err(message) =>
      match native_dist_override {
        Some(_) =>
          Err(
            CommandError(
              message +
              "\n\nPROTON_NATIVE_DIST is set; unset it or point it at a valid Proton runtime.",
            ),
          )
        None if setup_runtime =>
          match @cef.run_setup(root, []) {
            Ok(_) =>
              read_dev_runtime(root).map_err(fn(error) { CommandError(error) })
            Err(error) => Err(map_cef_error(error))
          }
        None =>
          Err(
            CommandError(
              message +
              "\n\nRun `proton_cli cef setup` first, or retry with `proton_cli dev --setup`.",
            ),
          )
      }
  }
}

///|
fn map_cef_error(error : @cef.CefError) -> DevError {
  match error {
    UsageError(message, usage_is_embedded) =>
      UsageError(message, usage_is_embedded)
    CommandError(message) => CommandError(message)
  }
}

///|
async fn read_dev_runtime(root : String) -> Result[DevRuntime, String] {
  match dev_native_dist_override(root) {
    Some(path) => return dev_runtime_from_root(path, "PROTON_NATIVE_DIST")
    None => ()
  }
  let manifest_path = runtime_manifest_path(root)
  let text = @mbfs.read_file_to_string(manifest_path, encoding="utf8") catch {
    _ => return Err("active Proton runtime is missing: " + manifest_path)
  }
  let json = @json.parse(text) catch {
    err =>
      return Err(
        "failed to parse active Proton runtime manifest: " +
        @debug.render(@debug.to_repr(err)),
      )
  }
  let platform = match json_string_field(json, "platform", manifest_path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let expected_platform = @cef.current_platform_id()
  if platform != expected_platform {
    return Err(
      "active Proton runtime platform mismatch: expected " +
      expected_platform +
      ", got " +
      platform,
    )
  }
  let dist = match json_string_field(json, "dist", manifest_path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
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
) -> Result[DevRuntime, String] {
  let bin_dir = join_path(runtime_root, "bin")
  let lib_dir = join_path(runtime_root, "lib")
  let helper_path = join_path(bin_dir, helper_executable_name())
  if !path_exists(runtime_root) {
    return Err(label + " directory is missing: " + runtime_root)
  }
  if !path_exists(helper_path) {
    return Err(label + " helper is missing: " + helper_path)
  }
  Ok(DevRuntime::{ root: runtime_root, bin_dir, lib_dir, helper_path })
}

///|
fn runtime_manifest_path(root : String) -> String {
  join_path(join_path(root, ".proton"), "runtime.json")
}

///|
fn validate_frontend_dev_url(
  frontend_url : String?,
  ready_path : String?,
) -> Result[Unit, DevError] {
  match frontend_url {
    None => Ok(())
    Some(url) =>
      parse_dev_url_endpoint(url, ready_path)
      .map(fn(_) { () })
      .map_err(fn(message) { CommandError(message) })
  }
}

///|
fn json_string_field(
  json : Json,
  field : String,
  label : String,
) -> Result[String, String] {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => Ok(value)
        _ => Err(label + " missing string field: " + field)
      }
    _ => Err(label + " must be a JSON object")
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
) -> Result[@process.Process?, DevError] {
  if !start_frontend {
    return Ok(None)
  }
  match command {
    None => Ok(None)
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
          return Err(
            CommandError(
              "failed to start frontend command: " +
              @debug.render(@debug.to_repr(err)),
            ),
          )
      }
      Ok(Some(process))
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
    @process.graceful_cancel(timeout=1000)
  }
}

///|
async fn wait_for_frontend(
  frontend_url : String?,
  ready_path : String?,
  timeout_ms : Int,
  frontend_process : @process.Process?,
) -> Result[Unit, DevError] {
  match frontend_url {
    None => Ok(())
    Some(url) => {
      let endpoint = match parse_dev_url_endpoint(url, ready_path) {
        Ok(endpoint) => endpoint
        Err(message) => return Err(CommandError(message))
      }
      match validate_ready_probe(ready_path) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      println("Waiting for frontend dev server: " + endpoint.url)
      let mut elapsed = 0
      while elapsed <= timeout_ms {
        match frontend_exit_code(frontend_process) {
          Some(code) =>
            return Err(
              CommandError(
                "frontend command exited before the dev server became ready: " +
                code.to_string(),
              ),
            )
          None => ()
        }
        if server_ready(endpoint, ready_path) {
          return Ok(())
        }
        @async.sleep(ready_poll_interval_ms)
        elapsed = elapsed + ready_poll_interval_ms
      }
      Err(
        CommandError(
          "timed out waiting for frontend dev server: " + endpoint.url,
        ),
      )
    }
  }
}

///|
async fn validate_ready_probe(ready_path : String?) -> Result[Unit, DevError] {
  match ready_path {
    Some(_) =>
      if command_exists("curl") {
        Ok(())
      } else {
        Err(
          CommandError(
            "--ready-path requires curl on PATH; install curl or omit --ready-path to use TCP readiness",
          ),
        )
      }
    None => Ok(())
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
) -> Result[DevUrlEndpoint, String] {
  let wait_url = append_ready_path(url, ready_path)
  let (scheme, rest) = match wait_url.split_once("://") {
    Some((scheme, rest)) => (scheme.to_owned().to_lower(), rest.to_owned())
    None =>
      return Err(
        "frontend dev URL must include http:// or https://: " + wait_url,
      )
  }
  let default_port = match scheme {
    "http" => 80
    "https" => 443
    _ => return Err("frontend dev URL must be http or https: " + wait_url)
  }
  let authority = url_authority(rest)
  if !dev_url_authority_is_valid(authority) {
    return Err("frontend dev URL has invalid origin: " + wait_url)
  }
  parse_host_port(authority, default_port).map(fn(parts) {
    let (host, port) = parts
    DevUrlEndpoint::{ url: wait_url, host, port }
  })
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
) -> Result[(String, Int), String] {
  if host_port.has_prefix("[") {
    match host_port.split_once("]") {
      Some((left, right)) => {
        let left = left.to_owned()
        let host = left.unsafe_substring(start=1, end=left.length())
        let port = if right == "" {
          Ok(default_port)
        } else if right.has_prefix(":") {
          parse_port(right[1:].to_owned())
        } else {
          Err("invalid frontend dev URL host: " + host_port)
        }
        if host == "" {
          Err("frontend dev URL host must not be empty")
        } else {
          port.map(fn(port) { (host, port) })
        }
      }
      None => Err("invalid frontend dev URL host: " + host_port)
    }
  } else {
    match host_port.split_once(":") {
      Some((host, port_text)) => {
        let host = host.to_owned()
        if host == "" {
          Err("frontend dev URL host must not be empty")
        } else {
          parse_port(port_text.to_owned()).map(fn(port) { (host, port) })
        }
      }
      None =>
        if host_port == "" {
          Err("frontend dev URL host must not be empty")
        } else {
          Ok((host_port, default_port))
        }
    }
  }
}

///|
fn parse_port(text : String) -> Result[Int, String] {
  let port = @string.parse_int(text[:]) catch {
    _ => return Err("frontend dev URL port must be an integer: " + text)
  }
  if port <= 0 || port > 65535 {
    Err("frontend dev URL port is out of range: " + text)
  } else {
    Ok(port)
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
) -> Result[Int, DevError] {
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
      return Err(
        CommandError(
          "failed to run MoonBit app: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  Ok(code)
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
