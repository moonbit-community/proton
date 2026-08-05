///|
/// Errors raised while locating or waiting for a local Chrome-family browser.
///
/// `BrowserNotFound` means no executable was found in the candidate list and no
/// explicit `browser_path` was provided. `BrowserNotReady(timeout_ms)` means a
/// browser process was started or an endpoint was polled, but no usable CDP
/// browser WebSocket URL appeared before the timeout.
pub(all) suberror BrowserLaunchError {
  BrowserNotFound
  BrowserNotReady(Int)
} derive(Eq, ToJson, Debug)

///|
/// Options used by `launch_browser`.
///
/// Set `browser_path` to force a specific Chrome or Edge executable, or leave it
/// as `None` to use `resolve_chrome_executable`. Use `port = 0` to let Chrome
/// choose an available debugging port and report it through `DevToolsActivePort`.
///
/// Field behavior:
///
/// - `user_data_dir` should be dedicated to automation or tests; avoid using a
///   daily browser profile.
/// - `headless` adds `--headless=new`.
/// - `url` is appended as the initial page URL when present.
/// - `timeout_ms` controls endpoint readiness waits, not browser process
///   lifetime.
/// - `extra_args` are appended after library-managed flags and before `url`.
/// - `extensions`, `proxy_server`, `proxy_bypass`, and the boolean flags map
///   directly to Chrome command-line switches.
///
/// # Example
/// ```mbt nocheck
/// let options = { ..default_launch_options(), headless: true, port: 9222 }
/// ```
pub(all) struct CdpLaunchOptions {
  browser_path : String?
  port : Int
  user_data_dir : String
  headless : Bool
  url : String?
  timeout_ms : Int
  extra_args : Array[String]
  extensions : Array[String]
  proxy_server : String?
  proxy_bypass : String?
  ignore_https_errors : Bool
  allow_file_access : Bool
  hide_scrollbars : Bool
} derive(Eq, ToJson, Debug)

///|
/// Information about a launched browser process and its CDP endpoint.
///
/// `web_socket_url` is ready to pass to `CdpClient::connect`. `endpoint` is the
/// HTTP discovery base URL, useful for `/json/version`, `/json/list`, and
/// `/json/protocol`.
///
/// `pid` is the process id returned by the async process spawner. The launcher
/// starts the process as an orphan and does not terminate it automatically.
/// Callers that need cleanup should close the browser through CDP or manage the
/// process outside this helper.
pub(all) struct CdpLaunchInfo {
  pid : Int
  port : Int
  endpoint : String
  web_socket_url : String
  user_data_dir : String
} derive(Eq, ToJson, Debug)

///|
// Parsed contents of Chrome's DevToolsActivePort file.
priv struct DevToolsActivePort {
  port : Int
  web_socket_path : String
}

///|
/// Return conservative launch defaults for local CDP testing.
///
/// The default profile directory is inside `_build`, uses port `9222`, opens
/// `about:blank`, and does not enable headless mode. Callers should override
/// `user_data_dir` when running concurrent tests.
///
/// These defaults are meant to be easy to inspect rather than invisible. In CI,
/// most callers should set `headless=true`, use `port=0`, and choose a unique
/// `user_data_dir` per test process.
pub fn default_launch_options() -> CdpLaunchOptions {
  {
    browser_path: None,
    port: 9222,
    user_data_dir: "_build/mbt-cdp-profile-9222",
    headless: false,
    url: Some("about:blank"),
    timeout_ms: 5000,
    extra_args: [],
    extensions: [],
    proxy_server: None,
    proxy_bypass: None,
    ignore_https_errors: false,
    allow_file_access: false,
    hide_scrollbars: false,
  }
}

///|
/// Launch a Chrome-family browser with remote debugging enabled.
///
/// The function creates the profile directory if needed, starts the browser as
/// an orphan process, then waits until a CDP browser WebSocket URL is available.
/// It raises `BrowserLaunchError::BrowserNotFound` when no executable can be
/// resolved, or `BrowserLaunchError::BrowserNotReady` when the endpoint is not
/// ready before `timeout_ms`.
///
/// With `port = 0`, Chrome chooses a free port and writes the selected endpoint
/// to `DevToolsActivePort`; this helper waits for that file. With an explicit
/// port, this helper polls the HTTP discovery endpoint until `/json/version`
/// exposes a browser WebSocket URL.
///
/// # Example
/// ```mbt nocheck
/// async test {
///   let info = launch_browser({ ..default_launch_options(), headless: true })
///   assert_true(info.web_socket_url.has_prefix("ws://"))
/// }
/// ```
pub async fn launch_browser(options : CdpLaunchOptions) -> CdpLaunchInfo {
  let browser_path = resolve_launch_browser_path(options)
  launch_browser_with_spawn(options, browser_path, spawn_browser_orphan)
}

///|
// Resolve the executable path requested by the launch options.
async fn resolve_launch_browser_path(options : CdpLaunchOptions) -> String {
  match options.browser_path {
    Some(path) => path
    None => resolve_chrome_executable()
  }
}

///|
// Launch using an injected process spawner for deterministic tests.
async fn launch_browser_with_spawn(
  options : CdpLaunchOptions,
  browser_path : String,
  spawn_orphan : async (String, Array[String]) -> Int,
) -> CdpLaunchInfo {
  if !@fs.exists(options.user_data_dir) {
    @fs.mkdir(options.user_data_dir, recursive=true)
  }
  let user_data_dir = @fs.realpath(options.user_data_dir)
  let launch_options = { ..options, user_data_dir, }
  if launch_options.port == 0 {
    remove_devtools_active_port_file(launch_options.user_data_dir)
  }
  let args = chrome_launch_args(launch_options)
  let pid = spawn_orphan(browser_path, args)
  let (actual_port, web_socket_url) = if launch_options.port == 0 {
    let active_port = wait_for_devtools_active_port(
      launch_options.user_data_dir,
      timeout_ms=launch_options.timeout_ms,
    )
    (
      active_port.port,
      "ws://127.0.0.1:\{active_port.port}\{active_port.web_socket_path}",
    )
  } else {
    let endpoint = "http://127.0.0.1:\{launch_options.port}"
    (
      launch_options.port,
      wait_for_browser_endpoint(endpoint, timeout_ms=launch_options.timeout_ms),
    )
  }
  let endpoint = "http://127.0.0.1:\{actual_port}"
  {
    pid,
    port: actual_port,
    endpoint,
    web_socket_url,
    user_data_dir: launch_options.user_data_dir,
  }
}

///|
// Start the browser process using the async process package.
async fn spawn_browser_orphan(path : String, args : Array[String]) -> Int {
  @process.spawn_orphan(path, args)
}

///|
/// Build Chrome command-line arguments from launch options.
///
/// This helper is deterministic and does not touch the filesystem, so tests can
/// use it to verify launch configuration before starting a real browser.
///
/// Arguments are ordered with library-managed remote debugging and profile
/// flags first, optional feature flags next, caller-provided `extra_args` after
/// those, and the initial `url` last. Later Chrome flags may override earlier
/// flags according to Chrome's own command-line parsing rules.
pub fn chrome_launch_args(options : CdpLaunchOptions) -> Array[String] {
  let args : Array[String] = [
    "--remote-debugging-port=\{options.port}",
    "--user-data-dir=\{options.user_data_dir}",
    "--no-first-run",
    "--no-default-browser-check",
  ]
  if options.headless {
    args.push("--headless=new")
  }
  if options.proxy_server is Some(proxy_server) {
    args.push("--proxy-server=\{proxy_server}")
  }
  if options.proxy_bypass is Some(proxy_bypass) {
    args.push("--proxy-bypass-list=\{proxy_bypass}")
  }
  if options.ignore_https_errors {
    args.push("--ignore-certificate-errors")
  }
  if options.allow_file_access {
    args.push("--allow-file-access-from-files")
  }
  if options.hide_scrollbars {
    args.push("--hide-scrollbars")
  }
  if options.extensions.length() > 0 {
    args.push("--load-extension=\{options.extensions.join(",")}")
  }
  for arg in options.extra_args {
    args.push(arg)
  }
  if options.url is Some(url) {
    args.push(url)
  }
  args
}

///|
// Remove a stale DevToolsActivePort file before asking Chrome to choose a port.
async fn remove_devtools_active_port_file(user_data_dir : String) -> Unit {
  remove_devtools_active_port_file_with_remove(user_data_dir, @fs.remove)
}

///|
// Remove a stale DevToolsActivePort file with an injected remover for tests.
async fn remove_devtools_active_port_file_with_remove(
  user_data_dir : String,
  remove_file : async (StringView) -> Unit,
) -> Unit {
  let path = devtools_active_port_path(user_data_dir)
  if @fs.exists(path) && @fs.kind(path, follow_symlink=false) is Regular {
    remove_file(path) catch {
      _ => ()
    }
  }
}

///|
// Return the DevToolsActivePort file path for a profile directory.
fn devtools_active_port_path(user_data_dir : String) -> String {
  "\{strip_trailing_path_separator(user_data_dir)}/DevToolsActivePort"
}

///|
// Remove one trailing path separator from a directory path.
fn strip_trailing_path_separator(path : String) -> String {
  match path.strip_suffix("/") {
    Some(path) => path.to_owned()
    None =>
      match path.strip_suffix("\\") {
        Some(path) => path.to_owned()
        None => path
      }
  }
}

///|
// Poll until Chrome writes DevToolsActivePort or the timeout expires.
async fn wait_for_devtools_active_port(
  user_data_dir : String,
  timeout_ms~ : Int,
) -> DevToolsActivePort {
  let path = devtools_active_port_path(user_data_dir)
  let deadline = @async.now() + timeout_ms.to_int64()
  for ;; {
    try parse_devtools_active_port(@fs.read_file(path).text()) catch {
      _ => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    } noraise {
      Some(info) => return info
      None => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    }
  }
}

///|
// Parse Chrome's two-line DevToolsActivePort file.
fn parse_devtools_active_port(raw : String) -> DevToolsActivePort? {
  match raw.split("\n").to_array() {
    [port_line, path_line, ..] =>
      match parse_debugging_port(port_line.trim().to_owned()) {
        Some(port) => {
          let path = path_line.trim().to_owned()
          if path == "" {
            None
          } else if path.has_prefix("/") {
            Some({ port, web_socket_path: path })
          } else {
            Some({ port, web_socket_path: "/\{path}" })
          }
        }
        None => None
      }
    _ => None
  }
}

///|
// Parse and validate a TCP debugging port number.
fn parse_debugging_port(value : String) -> Int? {
  if value == "" {
    return None
  }
  let mut port = 0
  for char in value {
    if !char.is_ascii_digit() {
      return None
    }
    port = port * 10 + (char.to_int() - '0'.to_int())
  }
  if port > 0 && port < 65536 {
    Some(port)
  } else {
    None
  }
}

///|
/// Resolve the first installed Chrome-family browser executable.
///
/// The candidate list includes common Chrome and Edge paths for Windows, macOS,
/// and Linux. Set `CdpLaunchOptions.browser_path` when the browser is installed
/// somewhere else.
///
/// This helper checks filesystem existence only. It does not launch the binary
/// or verify that the executable supports CDP flags.
pub async fn resolve_chrome_executable() -> String {
  resolve_first_existing(chrome_executable_candidates())
}

///|
// Resolve the first existing path from a candidate list.
async fn resolve_first_existing(candidates : Array[String]) -> String {
  for candidate in candidates {
    if @fs.exists(candidate) {
      return candidate
    }
  }
  raise BrowserLaunchError::BrowserNotFound
}

///|
/// Return the executable paths checked by `resolve_chrome_executable`.
///
/// The list is intentionally conservative and stable so tests can assert its
/// contents. Prefer explicit `browser_path` for portable application settings.
pub fn chrome_executable_candidates() -> Array[String] {
  [
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium",
    "/usr/bin/chromium-browser", "/snap/bin/chromium",
  ]
}

///|
/// Wait for an HTTP remote debugging endpoint to expose a browser WebSocket URL.
///
/// This is useful when another process launched Chrome and the MoonBit client
/// only needs to wait until `/json/version` is reachable.
///
/// `endpoint` should be an HTTP base URL such as `http://127.0.0.1:9222`.
/// The function polls until `discover_web_socket_url` succeeds or the timeout
/// expires.
///
/// # Example
/// ```mbt nocheck
/// async test {
///   let ws = wait_for_browser_endpoint("http://127.0.0.1:9222", timeout_ms=5000)
///   assert_true(ws.has_prefix("ws://"))
/// }
/// ```
pub async fn wait_for_browser_endpoint(
  endpoint : String,
  timeout_ms~ : Int,
) -> String {
  let deadline = @async.now() + timeout_ms.to_int64()
  for ;; {
    try discover_web_socket_url(Http(endpoint)) catch {
      _ => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    } noraise {
      url => return url
    }
  }
}
