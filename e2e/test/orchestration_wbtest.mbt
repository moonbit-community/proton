///|
let cdp_start_poll_timeout_ms = 250

///|
let app_child_scenario_env = "MBT_PROTON_E2E_APP_CHILD"

///|
let app_child_test_selector = "scenario_app_wbtest.mbt:0-1"

///|
let scenario_run_mutex : @async.Mutex = @async.Mutex::Mutex()

///|
priv suberror E2eOperationError {
  TimedOut(description~ : String, timeout_ms~ : Int)
} derive(Debug)

///|
async fn[X] run_e2e_operation_with_timeout(
  timeout : Int,
  description : String,
  operation : async () -> X,
) -> X {
  match @async.with_timeout_opt(timeout, operation) {
    Some(result) => result
    None => raise E2eOperationError::TimedOut(description~, timeout_ms=timeout)
  }
}

///|
struct SpawnedScenarioApp {
  process : @process.Process
  output_path : String
  native_log_path : String
}

///|
async fn choose_cdp_port() -> Int {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  server.addr.port()
}

///|
fn current_working_directory() -> String raise {
  let cwd = @env.current_dir().unwrap_or("")
  guard cwd != "" else { fail("could not determine current directory") }
  let cwd = @path.Path(normalize_platform_path(cwd)).normalize()
  guard cwd.is_absolute() else {
    fail("current directory is not absolute: " + cwd.to_string())
  }
  cwd.to_string()
}

///|
fn repository_root() -> String raise {
  let mut current = @path.Path(current_working_directory())
  for ;; {
    let current_text = current.to_string()
    if @mbfs.path_exists(join_path(current_text, "moon.work")) {
      return current_text
    }
    let parent = current.dirname()
    if parent == current {
      fail("could not find repository root from " + current_text)
    }
    current = parent
  }
}

///|
fn normalize_platform_path(path : String) -> String {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path.replace_all(old="\\", new="/")
  }
}

///|
fn is_absolute_path_for_separator(path : String, separator : Char) -> Bool {
  if path == "" {
    false
  } else if separator == '\\' {
    let drive = path[0]
    path[0] == '\\' ||
    (
      path.length() >= 3 &&
      ((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) &&
      path[1] == ':' &&
      path[2] == '\\'
    )
  } else {
    path[0] == '/'
  }
}

///|
fn active_runtime_dist(root : String) -> String raise {
  match @env.get_env_var("PROTON_NATIVE_DIST") {
    Some(value) if value.trim() != "" =>
      resolve_path(root, value.trim().to_owned())
    _ => {
      let manifest_path = join_path(root, ".proton/runtime.json")
      if @mbfs.path_exists(manifest_path) {
        match read_runtime_dist(manifest_path) {
          Ok(dist) => resolve_path(root, dist)
          Err(message) => fail(message)
        }
      } else {
        join_path(root, "native/dist")
      }
    }
  }
}

///|
fn read_runtime_dist(manifest_path : String) -> Result[String, String] {
  let text = @mbfs.read_file_to_string(manifest_path, encoding="utf8") catch {
    _ => return Err("failed to read runtime manifest: " + manifest_path)
  }
  let json = @json.parse(text) catch {
    _ => return Err("invalid runtime manifest JSON: " + manifest_path)
  }
  match json {
    Object(object) =>
      match object.get("dist") {
        Some(String(dist)) if dist != "" => Ok(dist)
        _ =>
          Err(
            "runtime manifest is missing a non-empty string dist field: " +
            manifest_path,
          )
      }
    _ => Err("runtime manifest must be a JSON object: " + manifest_path)
  }
}

///|
fn app_process_env(
  root : String,
  scenario : String,
  cdp_port : Int,
) -> Map[String, String] raise {
  let runtime_dist = active_runtime_dist(root)
  let bin_dir = join_path(runtime_dist, "bin")
  let lib_dir = join_path(runtime_dist, "lib")
  let helper_path = join_path(bin_dir, helper_executable_name())
  guard @mbfs.path_exists(bin_dir) else {
    fail(
      "native runtime bin directory does not exist: " +
      bin_dir +
      "\nRun proton_cli cef setup or set PROTON_NATIVE_DIST.",
    )
  }
  guard @mbfs.path_exists(helper_path) else {
    fail("native runtime helper does not exist: " + helper_path)
  }
  @mbfs.create_dir(join_path(root, "target")) catch {
    _ => ()
  }
  let path_key = path_env_key()
  let current_path = @env.get_env_var(path_key).unwrap_or("")
  let result : Map[String, String] = {
    "PROTON_NATIVE_DIST": runtime_dist,
    "PROTON_RUNTIME_ROOT": runtime_dist,
    "PROTON_HELPER_PATH": helper_path,
    "PROTON_NATIVE_LOG": scenario_native_log_path(root, cdp_port),
    "PROTON_REMOTE_DEBUGGING_PORT": cdp_port.to_string(),
    "PROTON_HEADLESS": "1",
    "PROTON_E2E_ASSET_SIDECAR_ENTRY": join_path(
      root, "examples/46_asset_sidecar_resources/app/app.html",
    ),
  }
  result[app_child_scenario_env] = scenario
  result[path_key] = prepend_env_path(bin_dir, current_path)
  if @path.sep != '\\' {
    // CEF must run from a normal system-linked executable on Unix. Moon's
    // default TCC runner uses a .rspfile process that aborts during CEF
    // shutdown, so nested Moon commands inherit an explicit host compiler.
    result["MOON_CC"] = match @env.get_env_var("MOON_CC") {
      Some(value) if value.trim() != "" => value
      _ => "cc"
    }
    result["LD_LIBRARY_PATH"] = prepend_env_path(
      lib_dir,
      prepend_env_path(
        bin_dir,
        @env.get_env_var("LD_LIBRARY_PATH").unwrap_or(""),
      ),
    )
    result["DYLD_LIBRARY_PATH"] = prepend_env_path(
      lib_dir,
      prepend_env_path(
        bin_dir,
        @env.get_env_var("DYLD_LIBRARY_PATH").unwrap_or(""),
      ),
    )
    if @mbfs.path_exists(join_path(bin_dir, "libcef.so")) {
      // Linux CEF wraps close(2) and must precede libc in the dynamic map.
      // Resolve the basename through LD_LIBRARY_PATH so paths with spaces work.
      result["LD_PRELOAD"] = prepend_env_path(
        "libcef.so",
        @env.get_env_var("LD_PRELOAD").unwrap_or(""),
      )
    }
  }
  result
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
fn scenario_native_log_path(root : String, cdp_port : Int) -> String {
  join_path(root, "target/proton-e2e-" + cdp_port.to_string() + ".log")
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
fn prepend_env_path(path : String, current : String) -> String {
  if current == "" {
    path
  } else {
    path + path_list_separator() + current
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
async fn[X] spawn_scenario_app(
  group : @async.TaskGroup[X],
  root : String,
  scenario : String,
  cdp_port : Int,
) -> SpawnedScenarioApp {
  let (program, args) = scenario_app_command(root)
  let output_path = join_path(
    root,
    "target/proton-e2e-child-" + cdp_port.to_string() + ".log",
  )
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let process = @process.spawn(
    group,
    program,
    args,
    cwd=root,
    extra_env=app_process_env(root, scenario, cdp_port),
    stdout=output,
    stderr=output,
    cancel_handler=app_cancel_handler(),
    no_wait=true,
  )
  SpawnedScenarioApp::{
    process,
    output_path,
    native_log_path: scenario_native_log_path(root, cdp_port),
  }
}

///|
fn scenario_app_command(root : String) -> (String, Array[String]) raise {
  if @path.sep == '\\' {
    (current_test_executable(), [app_child_test_selector])
  } else {
    // The Linux native test runner may execute a TCC-owned artifact that is
    // valid for the current process but not a standalone execve target.  Ask
    // Moon to run exactly the child test in an isolated, serially reused build
    // directory on Unix instead of attempting to re-exec the parent binary.
    isolated_app_command("moon", [
      "--target-dir",
      join_path(root, "target/proton-e2e-app-child"),
      "-C",
      root,
      "test",
      "e2e/test/scenario_app_wbtest.mbt",
      "--target",
      "native",
      "--no-parallelize",
      "--diagnostic-limit",
      "80",
    ])
  }
}

///|
fn isolated_app_command(
  program : String,
  args : Array[String],
) -> (String, Array[String]) {
  if @path.sep == '\\' {
    (program, args)
  } else {
    let command_args = [
      "-c",
      unix_app_session_script(),
      "proton-e2e-session",
      program,
    ]
    for arg in args {
      command_args.push(arg)
    }
    ("sh", command_args)
  }
}

///|
fn unix_app_session_script() -> String {
  (
    #|if command -v setsid >/dev/null 2>&1; then
    #|  exec setsid "$@"
    #|else
    #|  exec "$@"
    #|fi
  )
}

///|
fn current_test_executable() -> String raise {
  let args = @env.args()
  guard args.length() > 0 else { fail("test executable path is unavailable") }
  let executable = normalize_platform_path(args[0])
  let path = @path.Path(executable)
  if path.is_absolute() {
    executable
  } else {
    resolve_path(current_working_directory(), executable)
  }
}

///|
fn app_cancel_handler() -> @process.CancellationHandler {
  if @path.sep == '\\' {
    @process.CancellationHandler(async fn(pid) {
      ignore(
        @process.collect_output_merged(
          "taskkill",
          ["/pid", pid.to_string(), "/t", "/f"],
          no_console_window=true,
        ),
      )
    })
  } else {
    @process.CancellationHandler(async fn(pid) {
      if kill_isolated_unix_app_group(pid) != 0 {
        terminate_unix_app_tree(pid, "KILL")
      }
    })
  }
}

///|
extern "C" fn kill_isolated_unix_app_group(pid : Int) -> Int = "proton_e2e_kill_isolated_process_group"

///|
async fn terminate_unix_app_tree(pid : Int, signal : String) -> Unit {
  ignore(
    @process.run(
      "/bin/sh",
      [
        "-c",
        unix_app_tree_kill_script(),
        "proton-e2e-cancel",
        pid.to_string(),
        signal,
      ],
      inherit_env=false,
      no_console_window=true,
    ),
  )
}

///|
fn unix_app_tree_kill_script() -> String {
  (
    #|PATH=/usr/bin:/bin:/usr/sbin:/sbin
    #|export PATH
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
    #|parent="$1"
    #|signal="$2"
    #|parent_group=$(ps -o pgid= -p "$parent" 2>/dev/null | tr -d '[:space:]')
    #|caller_group=$(ps -o pgid= -p "$PPID" 2>/dev/null | tr -d '[:space:]')
    #|if [ -n "$parent_group" ] && [ "$parent_group" != "$caller_group" ]; then
    #|  kill "-$signal" -- "-$parent_group" 2>/dev/null || true
    #|else
    #|  kill_tree "$parent" "$signal"
    #|fi
  )
}

///|
async fn wait_for_spawned_app_cdp(
  app : SpawnedScenarioApp,
  endpoint : String,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  let mut browser_ready = false
  while elapsed <= timeout {
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "scenario app exited before CDP became ready: code=" +
          code.to_string() +
          app_diagnostic_suffix(app),
        )
      None => ()
    }
    let endpoint_ready = try {
      ignore(
        run_e2e_operation_with_timeout(
          cdp_start_poll_timeout_ms,
          "CDP browser endpoint probe",
          () => {
            @client.wait_for_browser_endpoint(
              endpoint,
              timeout_ms=cdp_start_poll_timeout_ms,
            )
          },
        ),
      )
      true
    } catch {
      _ => false
    }
    if endpoint_ready {
      browser_ready = true
      let page_ready = run_e2e_operation_with_timeout(
        cdp_start_poll_timeout_ms,
        "CDP page discovery probe",
        () => {
          let targets = @client.discover_targets(cdp_target_from(endpoint))
          targets.any(info => info.target_type == "page")
        },
      ) catch {
        _ => false
      }
      if page_ready {
        return
      }
      @async.sleep(100)
      elapsed = elapsed + 100
    } else {
      elapsed = elapsed + cdp_start_poll_timeout_ms
    }
  }
  if browser_ready {
    fail(
      "CDP page target did not become ready within " +
      timeout.to_string() +
      "ms" +
      app_diagnostic_suffix(app),
    )
  }
  fail(
    "CDP endpoint did not start within " +
    timeout.to_string() +
    "ms" +
    app_diagnostic_suffix(app),
  )
}

///|
fn app_exit_code(process : @process.Process) -> Int? {
  process.try_wait() catch {
    _ => Some(-1)
  }
}

///|
fn app_output_suffix(path : String) -> String {
  file_output_suffix(path, "Scenario output")
}

///|
fn app_diagnostic_suffix(app : SpawnedScenarioApp) -> String {
  app_output_suffix(app.output_path) +
  file_output_suffix(app.native_log_path, "Native log")
}

///|
fn file_output_suffix(path : String, label : String) -> String {
  let output = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return ""
  }
  if output == "" {
    ""
  } else {
    "\n" + label + ":\n" + output
  }
}

///|
async fn close_browser(target : String, timeout : Int) -> Unit {
  let browser = @client.connect_cdp_browser_target_with_timeout(
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  defer browser.close()
  close_connected_browser(browser)
}

///|
async fn close_connected_browser(browser : @client.CdpClient) -> Unit {
  let close_response = browser.send_command("Browser.close")
  match close_response.error {
    Some(error) =>
      fail(
        "Browser.close failed: " + error.code.to_string() + " " + error.message,
      )
    None => ()
  }
  // CEF's Alloy runtime acknowledges Browser.close but does not route the
  // Chrome-specific close request to CefBrowserHost::CloseBrowser.  Keep the
  // protocol request in the probe, then close every live page target through
  // the browser connection so that the native lifecycle is exercised and all
  // windows are covered.
  @async.sleep(cdp_start_poll_timeout_ms)
  let targets = browser.get_targets() catch { _ => return }
  for info in targets {
    if info.target_type == "page" {
      close_page_target(browser, info.target_id)
    }
  }
}

///|
async fn close_page_target(
  browser : @client.CdpClient,
  target_id : String,
) -> Unit {
  let response = browser.send_command(
    "Target.closeTarget",
    params=Json::object({ "targetId": Json::string(target_id) }),
  )
  match response.error {
    None => ()
    Some(error) if error.message.to_lower().contains("no target") => ()
    Some(error) =>
      fail(
        "Target.closeTarget failed: " +
        error.code.to_string() +
        " " +
        error.message,
      )
  }
}

///|
async fn wait_for_app_exit(app : SpawnedScenarioApp, timeout : Int) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    match app_exit_code(app.process) {
      Some(0) => return
      Some(code) =>
        fail(
          "scenario app exited with code=" +
          code.to_string() +
          app_output_suffix(app.output_path),
        )
      None => ()
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail(
    "scenario app did not exit within " +
    timeout.to_string() +
    "ms" +
    app_output_suffix(app.output_path),
  )
}

///|
fn resolve_path(base : String, child : String) -> String {
  let base = normalize_platform_path(base)
  let child = normalize_platform_path(child)
  if is_absolute_path_for_separator(child, @path.sep) {
    child
  } else if base == "" {
    child
  } else if base.has_suffix(@path.sep.to_string()) {
    base + child
  } else {
    base + @path.sep.to_string() + child
  }
}

///|
fn join_path(base : String, child : String) -> String {
  // The path facade can drop a Windows drive prefix while joining an
  // absolute base. E2E paths are simple relative children, so keep the
  // platform prefix with the controlled resolver above.
  resolve_path(base, child)
}

///|
async fn run_scenario_probe_once(
  root : String,
  name : String,
  timeout : Int,
) -> Unit {
  let port = choose_cdp_port()
  let target = port.to_string()
  @async.with_task_group(group => {
    let app = spawn_scenario_app(group, root, name, port)
    let mut stopped = false
    defer (if !stopped { app.process.cancel() })
    wait_for_spawned_app_cdp(app, cdp_http_endpoint_from(target), timeout)
    let shutdown = if name == "45_bridge_multi_window" {
      run_multi_window_scenario_probe(app, target, timeout)
    } else if name == "52_web_contents_view" {
      run_web_contents_view_scenario_probe(app, target, timeout)
    } else {
      if name == "41_app_commands" {
        run_app_commands_full_probe(root, target, timeout, app.native_log_path)
      } else if name == "40_event_broadcast" {
        run_event_scenario_page_probe(app, target, timeout)
      } else if name == "46_asset_sidecar_resources" {
        run_asset_sidecar_scenario_page_probe(app, target, timeout)
      } else {
        run_extension_scenario_page_probe(
          app,
          target,
          name,
          timeout,
          app.native_log_path,
        )
      }
      match app_exit_code(app.process) {
        Some(code) =>
          fail(
            "scenario app exited before the probe completed: code=" +
            code.to_string() +
            app_output_suffix(app.output_path),
          )
        None => ()
      }
      finish_scenario_app(app, target)
    }
    println(
      "MoonBit " +
      name +
      " headless shutdown passed: helpers=" +
      shutdown.helper_processes.to_string(),
    )
    stopped = true
  })
}

///|
async fn run_scenario_probe_with_retry(
  root : String,
  name : String,
  timeout : Int,
) -> Unit {
  let mut attempt = 0
  while attempt < 2 {
    let succeeded = try {
      run_e2e_operation_with_timeout(timeout, "E2E scenario " + name, () => {
        run_scenario_probe_once(root, name, timeout)
      })
      true
    } catch {
      error => {
        if attempt == 1 || !retryable_scenario_error(error) {
          raise error
        }
        println("MoonBit " + name + " transient attempt failed; retrying once")
        false
      }
    }
    if succeeded {
      return
    }
    @async.sleep(1000)
    attempt = attempt + 1
  }
}

///|
fn retryable_scenario_error(error : Error) -> Bool {
  match error {
    E2eOperationError::TimedOut(..) => true
    @io.ReaderClosed => true
    _ => retryable_startup_error(error)
  }
}

///|
fn retryable_startup_error(error : Error) -> Bool {
  let text = @debug.render(Repr(error)).to_lower()
  // Retry only failures emitted by the explicit startup waiters.  Transport
  // retry classification is handled by retryable_scenario_error using typed
  // errors; broad text matches such as "connection reset" would hide bugs.
  // The navigation waiter covers the page load right after Page.navigate,
  // which can stall on a loaded CI runner while the local server and CEF
  // settle.
  text.contains("scenario app exited before cdp became ready") ||
  text.contains("cdp endpoint did not start within") ||
  text.contains("cdp page target did not become ready within") ||
  text.contains("timed out waiting for navigation to")
}

///|
async test "headless 41_app_commands runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  let root = repository_root()
  let timeout = timeout_ms()
  run_scenario_probe_with_retry(root, "41_app_commands", timeout)
  run_pending_lifecycle_probe(root, timeout)
}

///|
async test "headless 38_async_extension_add runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  run_scenario_probe_with_retry(
    repository_root(),
    "38_async_extension_add",
    timeout_ms(),
  )
}

///|
async test "headless 39_sync_async_extensions runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  run_scenario_probe_with_retry(
    repository_root(),
    "39_sync_async_extensions",
    timeout_ms(),
  )
}

///|
async test "headless 40_event_broadcast runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  let root = repository_root()
  let timeout = timeout_ms()
  run_scenario_probe_with_retry(root, "40_event_broadcast", timeout)
  run_event_lifecycle_probe(root, timeout)
}

///|
async test "headless 45_bridge_multi_window runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  let root = repository_root()
  let timeout = timeout_ms()
  run_scenario_probe_with_retry(root, "45_bridge_multi_window", timeout)
}

///|
async test "headless 52_web_contents_view runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  let root = repository_root()
  let timeout = timeout_ms()
  run_scenario_probe_with_retry(root, "52_web_contents_view", timeout)
}

///|
async test "headless 46_asset_sidecar_resources runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  run_scenario_probe_with_retry(
    repository_root(),
    "46_asset_sidecar_resources",
    timeout_ms(),
  )
}

///|
async test "headless 47_dev_extension_js runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  run_dev_extension_scenario_with_retry(repository_root(), timeout_ms())
}

///|
async test "headless 42_attribute_codegen_commands runs as a self-hosted e2e" {
  scenario_run_mutex.acquire()
  defer scenario_run_mutex.release()
  run_scenario_probe_with_retry(
    repository_root(),
    "42_attribute_codegen_commands",
    timeout_ms(),
  )
}
