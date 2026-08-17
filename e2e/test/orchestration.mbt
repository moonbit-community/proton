///|
let app_child_scenario_env = "MBT_PROTON_E2E_APP_CHILD"

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
  let cwd = e2e_host_path(cwd).normalize()
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
fn e2e_host_path(path : String) -> @path.Path {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path.replace_all(old="\\", new="/")
  }
}

///|
fn active_runtime_dist(root : String) -> String raise {
  let manifest_path = join_path(root, ".proton/runtime.json")
  guard @mbfs.path_exists(manifest_path) else {
    fail("CEF runtime is not configured; run proton_cli cef setup")
  }
  match read_runtime_dist(manifest_path) {
    Ok(dist) => resolve_path(root, dist)
    Err(message) => fail(message)
  }
}

///|
fn source_built_helper(root : String) -> String {
  join_path(
    root,
    "_build/native/debug/build/moonbit-community/proton/internal/cef_process/" +
    helper_executable_name(),
  )
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
    { "dist": String(dist), .. } if dist != "" => Ok(dist)
    Object(_) =>
      Err(
        "runtime manifest is missing a non-empty string dist field: " +
        manifest_path,
      )
    _ => Err("runtime manifest must be a JSON object: " + manifest_path)
  }
}

///|
fn app_process_env(
  root : String,
  output_root : String,
  scenario : String,
  cdp_port : Int,
) -> Map[String, String] raise {
  let runtime_dist = active_runtime_dist(root)
  let bin_dir = join_path(runtime_dist, "bin")
  let lib_dir = join_path(runtime_dist, "lib")
  let helper_path = source_built_helper(root)
  guard @mbfs.path_exists(bin_dir) else {
    fail(
      "native runtime bin directory does not exist: " +
      bin_dir +
      "\nRun proton_cli cef setup.",
    )
  }
  guard @mbfs.path_exists(helper_path) else {
    fail("native runtime helper does not exist: " + helper_path)
  }
  let path_key = path_env_key()
  let current_path = @env.get_env_var(path_key).unwrap_or("")
  let result : Map[String, String] = {
    "PROTON_RUNTIME_ROOT": runtime_dist,
    "PROTON_HELPER_PATH": helper_path,
    "PROTON_NATIVE_LOG": scenario_native_log_path(output_root, cdp_port),
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
fn scenario_native_log_path(output_root : String, cdp_port : Int) -> String {
  join_path(output_root, "native-" + cdp_port.to_string() + ".log")
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
  output_root : String,
  scenario : String,
  cdp_port : Int,
) -> SpawnedScenarioApp {
  let (program, args) = scenario_app_command()
  let output_path = join_path(
    output_root,
    "child-" + cdp_port.to_string() + ".log",
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
    extra_env=app_process_env(root, output_root, scenario, cdp_port),
    stdout=output,
    stderr=output,
    cancel_handler=app_cancel_handler(),
    no_wait=true,
  )
  SpawnedScenarioApp::{
    process,
    output_path,
    native_log_path: scenario_native_log_path(output_root, cdp_port),
  }
}

///|
fn scenario_app_command() -> (String, Array[String]) raise {
  let executable = current_test_executable()
  if @path.sep == '\\' {
    (executable, [])
  } else {
    isolated_app_command(executable, [])
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
  let executable = e2e_host_path(args[0]).normalize().to_string()
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
    #|  if command -v pgrep >/dev/null 2>&1; then
    #|    for child in $(pgrep -P "$1" 2>/dev/null); do
    #|      kill_tree "$child" "$2"
    #|    done
    #|  fi
    #|  kill "-$2" "$1" 2>/dev/null || true
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
) -> String {
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
    let browser_web_socket_url = Some(
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
    ) catch {
      _ => None
    }
    match browser_web_socket_url {
      Some(browser_web_socket_url) => {
        browser_ready = true
        let targets = discover_targets_for_poll(cdp_target_from(endpoint))
        let page_ready = targets.any(info => info.target_type == "page")
        if page_ready {
          return browser_web_socket_url
        }
        @async.sleep(100)
        elapsed = elapsed + 100
      }
      None => elapsed = elapsed + cdp_start_poll_timeout_ms
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
  let response = browser.send_command("Target.closeTarget", params={
    "targetId": target_id,
  })
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
  let child_path = e2e_host_path(child)
  if child_path.is_absolute() {
    child_path.normalize().to_string()
  } else if base == "" {
    child_path.normalize().to_string()
  } else {
    e2e_host_path(base).join(child_path).to_string()
  }
}

///|
fn join_path(base : String, child : String) -> String {
  resolve_path(base, child)
}

///|
async fn run_scenario_probe_once(
  root : String,
  output_root : String,
  name : String,
  timeout : Int,
) -> Unit {
  let port = choose_cdp_port()
  let target = port.to_string()
  @async.with_task_group(group => {
    let app = spawn_scenario_app(group, root, output_root, name, port)
    let mut stopped = false
    defer (if !stopped { app.process.cancel() })
    let browser_web_socket_url = wait_for_spawned_app_cdp(
      app,
      cdp_http_endpoint_from(target),
      timeout,
    )
    let shutdown = if name == "45_bridge_multi_window" {
      run_multi_window_scenario_probe(app, target, timeout)
    } else if name == "52_web_contents_view" {
      run_web_contents_view_scenario_probe(
        app, target, browser_web_socket_url, timeout,
      )
    } else if name == "54_devtools" {
      run_devtools_scenario_page_probe(app, target, timeout)
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
    } else if name == "56_i18n" {
      run_i18n_scenario_page_probe(app, target, timeout)
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
    } else {
      if name == "41_app_commands" {
        run_app_commands_full_probe(
          output_root,
          target,
          timeout,
          app.native_log_path,
        )
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
  let output_root = @fs.tmpdir(prefix="proton-e2e-")
  defer remove_dev_extension_tree(output_root)
  let operation_timeout = scenario_operation_timeout(name, timeout)
  let mut attempt = 0
  while attempt < 4 {
    let succeeded = try {
      run_e2e_operation_with_timeout(
        operation_timeout,
        "E2E scenario " + name,
        () => run_scenario_probe_once(root, output_root, name, timeout),
      )
      true
    } catch {
      error => {
        if attempt == 3 || !retryable_scenario_error_for(name, error) {
          raise error
        }
        // A transient pipe EAGAIN can recur for one or two attempts on a
        // loaded shared runner while it catches its breath; back off a little
        // between attempts so a clean probe has a real chance to run.
        println("MoonBit " + name + " transient attempt failed; retrying")
        @async.sleep(2000)
        false
      }
    }
    if succeeded {
      return
    }
    attempt = attempt + 1
  }
}

///|
fn scenario_operation_timeout(name : String, timeout : Int) -> Int {
  if name == "41_app_commands" {
    // These probes have separate startup and OSR paint waits. Their outer
    // guards must cover more than one phase-sized budget.
    timeout * 2
  } else if name == "52_web_contents_view" {
    // The view probe has separate startup, target, browser, page, ready,
    // paint, closed, and shutdown waits.  Its outer guard must cover several
    // phase-sized budgets: on a loaded CI runner these phases each approach
    // their own `timeout` while the app and CEF settle, so grant extra
    // headroom instead of failing the whole probe.
    timeout * 4
  } else {
    timeout
  }
}

///|
fn retryable_scenario_error(error : Error) -> Bool {
  retryable_scenario_error_for("", error)
}

///|
fn retryable_scenario_error_for(name : String, error : Error) -> Bool {
  match error {
    E2eOperationError::TimedOut(..) => true
    @io.ReaderClosed => true
    // A subprocess pipe read can transiently report a non-blocking errno such
    // as EAGAIN on a loaded CI runner; that is a transport condition, not a
    // scenario failure, so retry it instead of failing the whole E2E.
    @os_error.OSError(_, ..) as err => err.is_nonblocking_io_error()
    _ => retryable_startup_error_for(name, error)
  }
}

///|
fn retryable_startup_error_for(name : String, error : Error) -> Bool {
  let text = @debug.render(Repr(error)).to_lower()
  // Retry only failures emitted by the explicit startup waiters.  Transport
  // retry classification is handled by retryable_scenario_error using typed
  // errors; broad text matches such as "connection reset" would hide bugs.
  // The navigation waiter covers the page load right after Page.navigate,
  // which can stall on a loaded CI runner while the local server and CEF
  // settle.
  text.contains("scenario app exited before cdp became ready") ||
  text.contains("cdp endpoint did not start within") ||
  text.contains("cdp page target") ||
  (
    name == "52_web_contents_view" &&
    text.contains("scenario app did not exit within")
  ) ||
  text.contains("timed out waiting for navigation to") ||
  // The web-contents-view probe asserts on auxiliary log files (OSR paint
  // records, per-view event logs) that the child app writes asynchronously.
  // On a loaded shared runner those files can lag behind the probe fast enough
  // to miss the deadline even though the app behaved correctly, so treat these
  // as transient and let the heavy scenario retry cleanly.
  text.contains("native log did not record") ||
  text.contains("failed to read web contents view event log") ||
  text.contains("view event log missed")
}

///|
async fn run_self_hosted_scenarios() -> Unit {
  let root = repository_root()
  let timeout = timeout_ms()
  run_scenario_probe_with_retry(root, "41_app_commands", timeout)
  run_pending_lifecycle_probe(root, timeout)
  run_scenario_probe_with_retry(root, "38_async_extension_add", timeout)
  run_scenario_probe_with_retry(root, "39_sync_async_extensions", timeout)
  run_scenario_probe_with_retry(root, "40_event_broadcast", timeout)
  run_event_lifecycle_probe(root, timeout)
  run_scenario_probe_with_retry(root, "45_bridge_multi_window", timeout)
  run_scenario_probe_with_retry(root, "52_web_contents_view", timeout)
  run_scenario_probe_with_retry(root, "54_devtools", timeout)
  run_scenario_probe_with_retry(root, "56_i18n", timeout)
  run_scenario_probe_with_retry(root, "46_asset_sidecar_resources", timeout)
  run_dev_extension_scenario_with_retry(root, timeout)
  run_scenario_probe_with_retry(root, "42_attribute_codegen_commands", timeout)
}
