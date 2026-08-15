///|
let process_shutdown_timeout_ms : Int = if @path.sep == '\\' {
  20000
} else {
  10000
}

///|
struct ProcessRow {
  pid : Int
  parent_pid : Int
  created_at : Int
  command : String
} derive(Eq, Debug)

///|
pub extend ProcessRow with Eq::{not_equal, equal}

///|
pub extend ProcessRow with Debug::{to_repr}

///|
struct ProcessRowJson {
  pid : Int
  parent_pid : Int
  created_at : Int
  command : String
} derive(FromJson, Eq, Debug)

///|
pub extend ProcessRowJson with Eq::{not_equal, equal}

///|
pub extend ProcessRowJson with Debug::{to_repr}

///|
pub extend ProcessRowJson with FromJson::{from_json}

///|
struct ProcessSnapshot {
  pids : Array[Int]
  helper_pids : Array[Int]
  commands : Map[Int, String]
  created_at : Map[Int, Int]
}

///|
struct ShutdownProbeResult {
  helper_processes : Int
} derive(Eq, Debug)

///|
pub extend ShutdownProbeResult with Eq::{not_equal, equal}

///|
pub extend ShutdownProbeResult with Debug::{to_repr}

///|
async fn finish_scenario_app(
  app : SpawnedScenarioApp,
  target : String,
) -> ShutdownProbeResult {
  finish_scenario_app_with_exit_timeout(
    app, target, process_shutdown_timeout_ms,
  )
}

///|
async fn finish_scenario_app_with_exit_timeout(
  app : SpawnedScenarioApp,
  target : String,
  exit_timeout : Int,
) -> ShutdownProbeResult {
  let snapshot = snapshot_scenario_process_tree(app)
  close_browser(target, process_shutdown_timeout_ms)
  wait_for_scenario_app_shutdown(app, target, snapshot, exit_timeout)
}

///|
async fn snapshot_scenario_process_tree(
  app : SpawnedScenarioApp,
) -> ProcessSnapshot {
  let snapshot = snapshot_process_tree(app.process.pid)
  guard snapshot.helper_pids.length() > 0 else {
    fail("headless process tree did not contain a cef_process helper")
  }
  snapshot
}

///|
async fn wait_for_scenario_app_shutdown(
  app : SpawnedScenarioApp,
  target : String,
  snapshot : ProcessSnapshot,
  exit_timeout : Int,
) -> ShutdownProbeResult {
  wait_for_app_exit(app, exit_timeout)
  wait_for_process_tree_stop(snapshot, exit_timeout)
  wait_for_cdp_endpoint_stop(
    cdp_http_endpoint_from(target),
    process_shutdown_timeout_ms,
  )
  ShutdownProbeResult::{ helper_processes: snapshot.helper_pids.length() }
}

///|
async fn finish_scenario_app_with_connected_browser(
  app : SpawnedScenarioApp,
  target : String,
  browser : @client.CdpClient,
) -> ShutdownProbeResult {
  let snapshot = snapshot_scenario_process_tree(app)
  close_connected_browser(browser)
  wait_for_scenario_app_shutdown(
    app, target, snapshot, process_shutdown_timeout_ms,
  )
}

///|
async fn snapshot_process_tree(root_pid : Int) -> ProcessSnapshot {
  let rows = list_processes()
  let commands : Map[Int, String] = Map([])
  let created_at : Map[Int, Int] = Map([])
  let mut root_row : ProcessRow? = None
  for row in rows {
    commands[row.pid] = row.command
    created_at[row.pid] = row.created_at
    if row.pid == root_pid {
      root_row = Some(row)
    }
  }
  guard root_row is Some(root_row) else {
    fail("headless root process was not present in the process snapshot")
  }
  let descendants : Array[ProcessRow] = []
  let pending = [root_row]
  while pending.length() > 0 {
    let parent = pending.pop().unwrap()
    for row in rows {
      if row.parent_pid == parent.pid &&
        process_row_can_descend_from(row, parent) &&
        row.pid != root_pid &&
        !descendants.any(existing => existing.pid == row.pid) {
        descendants.push(row)
        pending.push(row)
      }
    }
  }
  let pids = [root_pid]
  let helper_pids : Array[Int] = []
  for row in descendants {
    pids.push(row.pid)
    if process_command_is_helper(row.command) {
      helper_pids.push(row.pid)
    }
  }
  ProcessSnapshot::{ pids, helper_pids, commands, created_at }
}

///|
fn process_row_can_descend_from(
  child : ProcessRow,
  parent : ProcessRow,
) -> Bool {
  if @path.sep == '\\' && child.created_at > 0 && parent.created_at > 0 {
    child.created_at >= parent.created_at
  } else {
    true
  }
}

///|
async fn list_processes() -> Array[ProcessRow] {
  if @path.sep == '\\' {
    list_windows_processes()
  } else {
    list_unix_processes()
  }
}

///|
async fn list_unix_processes() -> Array[ProcessRow] {
  // Redirect `ps` output to a file instead of capturing it through a pipe:
  // a pipe read can surface a transient EAGAIN on a loaded runner and
  // truncate the tree, dropping the root process from the snapshot.
  let tmp_root = @fs.tmpdir(prefix="proton-e2e-ps-")
  let ps_log = join_path(tmp_root, "ps.out")
  let output = @process.redirect_to_file(
    ps_log,
    create_mode=@fs.CreateOrTruncate,
  )
  let code = @process.run(
    "ps",
    ["-axo", "pid=,ppid=,command="],
    stdout=output,
    stderr=output,
  )
  guard code == 0 else { fail("failed to inspect the Unix process tree") }
  let text = @mbfs.read_file_to_string(ps_log, encoding="utf8") catch {
    _ => fail("failed to read Unix process output")
  }
  let rows : Array[ProcessRow] = []
  for raw_line in text.replace_all(old="\r\n", new="\n").split("\n") {
    match parse_unix_process_row(raw_line) {
      Some(row) => rows.push(row)
      None => ()
    }
  }
  rows
}

///|
fn parse_unix_process_row(raw_line : StringView) -> ProcessRow? {
  let parts : Array[String] = []
  for raw_part in raw_line.trim().split(" ") {
    let part = raw_part.trim().to_owned()
    if part != "" {
      parts.push(part)
    }
  }
  guard parts.length() >= 3 else { return None }
  let pid = match parse_log_int(parts[0]) {
    Some(pid) => pid
    None => return None
  }
  let parent_pid = match parse_log_int(parts[1]) {
    Some(parent_pid) => parent_pid
    None => return None
  }
  Some(ProcessRow::{
    pid,
    parent_pid,
    created_at: 0,
    command: parts[2:].join(" "),
  })
}

///|
async fn list_windows_processes() -> Array[ProcessRow] {
  let script =
    #|[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    #|$OutputEncoding = [System.Text.Encoding]::UTF8
    #|Get-CimInstance Win32_Process |
    #|ForEach-Object {
    #|  [pscustomobject]@{
    #|    pid = [int]$_.ProcessId
    #|    parent_pid = [int]$_.ParentProcessId
    #|    created_at = if ($null -ne $_.CreationDate) {
    #|      [int64]([DateTimeOffset]$_.CreationDate).ToUnixTimeSeconds()
    #|    } else { 0 }
    #|    command = (("{0} {1}" -f $_.Name, $_.CommandLine).Trim())
    #|  }
    #|} | ConvertTo-Json -Compress
  let (code, output) = @process.collect_output_merged(
    "powershell",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
    no_console_window=true,
  )
  guard code == 0 else { fail("failed to inspect the Windows process tree") }
  let text = output.text() catch {
    _ => fail("failed to decode Windows process output")
  }
  if text.trim() == "" {
    return []
  }
  let json = @json.parse(text) catch {
    _ => fail("failed to parse Windows process output")
  }
  let rows : Array[ProcessRow] = []
  match json {
    Array(items) =>
      for item in items {
        rows.push(process_row_from_json(item))
      }
    Object(_) => rows.push(process_row_from_json(json))
    _ => fail("Windows process output was not an object or array")
  }
  rows
}

///|
fn process_row_from_json(json : Json) -> ProcessRow raise {
  let row : ProcessRowJson = decode_probe(json, "Windows process row")
  ProcessRow::{
    pid: row.pid,
    parent_pid: row.parent_pid,
    created_at: row.created_at,
    command: row.command,
  }
}

///|
fn process_command_is_helper(command : String) -> Bool {
  let command = command.to_lower()
  command.contains("cef_process.exe") || command.contains("cef_process")
}

///|
async fn wait_for_process_tree_stop(
  snapshot : ProcessSnapshot,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  let mut remaining : Array[Int] = []
  while elapsed <= timeout {
    let rows = list_processes()
    let alive : Map[Int, Int] = Map([])
    for row in rows {
      alive[row.pid] = row.created_at
    }
    remaining = []
    for pid in snapshot.pids {
      match alive.get(pid) {
        Some(current_created_at) => {
          let expected_created_at = snapshot.created_at.get(pid).unwrap_or(0)
          if current_created_at == 0 ||
            expected_created_at == 0 ||
            current_created_at == expected_created_at {
            remaining.push(pid)
          }
        }
        None => ()
      }
    }
    if remaining.length() == 0 {
      return
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  let details : Array[String] = []
  for pid in remaining {
    details.push(
      pid.to_string() + ":" + snapshot.commands.get(pid).unwrap_or("unknown"),
    )
  }
  fail("headless process tree did not stop: " + details.join(", "))
}

///|
async fn wait_for_cdp_endpoint_stop(endpoint : String, timeout : Int) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    let running = try {
      ignore(
        @client.wait_for_browser_endpoint(
          endpoint,
          timeout_ms=cdp_start_poll_timeout_ms,
        ),
      )
      true
    } catch {
      _ => false
    }
    if !running {
      return
    }
    elapsed = elapsed + cdp_start_poll_timeout_ms
  }
  fail("CDP endpoint did not stop: " + endpoint)
}

///|
async fn run_pending_lifecycle_probe_once(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let name = "41_app_commands"
  let port = choose_cdp_port()
  let target = port.to_string()
  @async.with_task_group(group => {
    let app = spawn_scenario_app(group, root, output_root, name, port)
    let mut stopped = false
    defer (if !stopped { app.process.cancel() })
    ignore(
      wait_for_spawned_app_cdp(app, cdp_http_endpoint_from(target), timeout),
    )
    let page = connect_spawned_page(app, target, timeout)
    let mut page_open = true
    defer (if page_open { page.close() })
    let browser = @client.connect_cdp_browser_target_with_timeout(
      cdp_target_from(target),
      timeout_ms=timeout,
    )
    defer browser.close()
    ignore(page.send_schema_command("Runtime.enable"))
    wait_for_ready(page, scenario_ready_expression(name), timeout)
    let initial_slow_adds = count_native_log_entries(
      app.native_log_path,
      "bridge_enqueue",
      "op=ext:appCommands/slowAdd",
    )
    ignore(
      evaluate_json(
        page,
        (
          #|(() => {
          #|  const invoke = window.__MoonBit__?.core?.invokeOp;
          #|  if (typeof invoke !== "function") {
          #|    throw new Error("bridge is not installed");
          #|  }
          #|  window.__protonLifecyclePending = invoke("ext:appCommands/slowAdd", {
          #|    left: 7,
          #|    right: 8,
          #|    delay_ms: 8000,
          #|  }).catch(() => {});
          #|  return true;
          #|})()
        ),
        false,
      ),
    )
    wait_for_native_log_count(
      app.native_log_path,
      "bridge_enqueue",
      "op=ext:appCommands/slowAdd",
      initial_slow_adds + 1,
      timeout,
    )
    page.close()
    page_open = false
    let shutdown = finish_scenario_app_with_connected_browser(
      app, target, browser,
    )
    assert_pending_lifecycle_log(app.native_log_path)
    println(
      "MoonBit pending lifecycle passed: helpers=" +
      shutdown.helper_processes.to_string(),
    )
    stopped = true
  })
}

///|
async fn run_pending_lifecycle_probe(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-lifecycle-")
  defer remove_dev_extension_tree(output_root)
  build_scenario_app_executable(root, output_root)
  let mut attempt = 0
  while attempt < 2 {
    let succeeded = try {
      run_e2e_operation_with_timeout(
        timeout,
        "41_app_commands pending lifecycle",
        () => run_pending_lifecycle_probe_once(root, output_root, timeout),
      )
      true
    } catch {
      error => {
        if attempt == 1 || !retryable_scenario_error(error) {
          raise error
        }
        println("MoonBit pending lifecycle attempt failed; retrying once")
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
async fn run_event_lifecycle_probe_once(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let name = "40_event_broadcast"
  let port = choose_cdp_port()
  let target = port.to_string()
  @async.with_task_group(group => {
    let app = spawn_scenario_app(group, root, output_root, name, port)
    let mut stopped = false
    defer (if !stopped { app.process.cancel() })
    ignore(
      wait_for_spawned_app_cdp(app, cdp_http_endpoint_from(target), timeout),
    )
    let page = connect_spawned_page(app, target, timeout)
    let mut page_open = true
    defer (if page_open { page.close() })
    let browser = @client.connect_cdp_browser_target_with_timeout(
      cdp_target_from(target),
      timeout_ms=timeout,
    )
    defer browser.close()
    ignore(page.send_schema_command("Runtime.enable"))
    wait_for_ready(page, scenario_ready_expression(name), timeout)
    let initial_starts = count_native_log_entries(
      app.native_log_path,
      "bridge_enqueue",
      "op=ext:ticker/start",
    )
    ignore(
      evaluate_json(
        page,
        (
          #|(() => {
          #|  window.__protonEventLifecyclePending = window.__MoonBit__.ticker.start({
          #|    run_id: 9102,
          #|    count: 5,
          #|    interval_ms: 1000,
          #|  }).catch(() => {});
          #|  return true;
          #|})()
        ),
        false,
      ),
    )
    wait_for_native_log_count(
      app.native_log_path,
      "bridge_enqueue",
      "op=ext:ticker/start",
      initial_starts + 1,
      timeout,
    )
    @async.sleep(250)
    page.close()
    page_open = false
    let shutdown = finish_scenario_app_with_connected_browser(
      app, target, browser,
    )
    assert_pending_lifecycle_log(app.native_log_path)
    assert_event_lifecycle_log(app.native_log_path)
    println(
      "MoonBit event lifecycle passed: helpers=" +
      shutdown.helper_processes.to_string(),
    )
    stopped = true
  })
}

///|
async fn run_event_lifecycle_probe(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-lifecycle-")
  defer remove_dev_extension_tree(output_root)
  build_scenario_app_executable(root, output_root)
  let mut attempt = 0
  while attempt < 2 {
    let succeeded = try {
      run_e2e_operation_with_timeout(
        timeout,
        "40_event_broadcast event lifecycle",
        () => run_event_lifecycle_probe_once(root, output_root, timeout),
      )
      true
    } catch {
      error => {
        if attempt == 1 || !retryable_scenario_error(error) {
          raise error
        }
        println("MoonBit event lifecycle attempt failed; retrying once")
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
async fn connect_spawned_page(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
  title? : String,
) -> @client.CdpClient {
  let mut elapsed = 0
  while elapsed <= timeout {
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "scenario app exited before a page target was ready: code=" +
          code.to_string() +
          app_output_suffix(app.output_path),
        )
      None => ()
    }
    let page = Some(
      run_e2e_operation_with_timeout(
        cdp_start_poll_timeout_ms,
        "CDP page connection probe",
        () => {
          @client.connect_cdp_page_target_with_timeout(
            cdp_target_from(target),
            title?,
            timeout_ms=cdp_start_poll_timeout_ms,
          )
        },
      ),
    ) catch {
      _ => None
    }
    match page {
      Some(page) => return page
      None => {
        @async.sleep(100)
        elapsed = elapsed + 100
      }
    }
  }
  fail(
    "CDP page target did not become ready within " +
    timeout.to_string() +
    "ms" +
    app_output_suffix(app.output_path),
  )
}

///|
fn count_native_log_entries(
  path : String,
  first : String,
  second : String,
) -> Int {
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return 0
  }
  let mut count = 0
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains(first) && line.contains(second) {
      count = count + 1
    }
  }
  count
}

///|
async fn wait_for_native_log_count(
  path : String,
  first : String,
  second : String,
  expected : Int,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    if count_native_log_entries(path, first, second) >= expected {
      return
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail(
    "native log did not record " +
    expected.to_string() +
    " matching entries for " +
    second,
  )
}

///|
fn assert_pending_lifecycle_log(path : String) -> Unit raise {
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => fail("failed to read lifecycle native log: " + path)
  }
  let mut pending_cleanup = false
  let mut stale_response_handled = false
  let mut queue_cleared = false
  let mut pending_cleared = false
  let mut window_closed = false
  let mut runtime_destroyed = false
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("bridge_pending_remove_browser") {
      let pending = log_int_field(line, "pending=").unwrap_or(0)
      let queued = log_int_field(line, "queued=").unwrap_or(0)
      if pending > 0 || queued > 0 {
        pending_cleanup = true
      }
    }
    if line.contains("bridge_pending_remove request=") ||
      line.contains("bridge_response_no_pending request=") ||
      line.contains("bridge_response_send_failed request=") {
      stale_response_handled = true
    }
    if line.contains("bridge_queue_clear removed=") {
      queue_cleared = true
    }
    if line.contains("bridge_pending_clear_all removed=") {
      pending_cleared = true
    }
    if line.contains("window_closed browser=") {
      window_closed = true
    }
    // Matches the managed marker too, which ends in the same words.
    if line.contains("runtime_destroy_complete") {
      runtime_destroyed = true
    }
  }
  guard pending_cleanup || stale_response_handled else {
    fail("native log did not prove pending response state was handled")
  }
  guard queue_cleared && pending_cleared else {
    fail("native log did not prove runtime bridge state was cleared")
  }
  guard window_closed && runtime_destroyed else {
    fail("native log did not prove window and runtime shutdown completed")
  }
}

///|
fn assert_event_lifecycle_log(path : String) -> Unit raise {
  guard count_native_log_entries(path, "bridge_enqueue", "op=ext:ticker/start") >
    0 else {
    fail("native log did not prove event lifecycle ticker request was enqueued")
  }
}
