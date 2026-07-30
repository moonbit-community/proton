///|
struct MultiWindowResponseProbe {
  label : String
  request_id : String
  window : String
} derive(FromJson, Eq, Debug)

///|
struct MultiWindowPageProbe {
  url : String
  title : String
  label : String
  has_bridge : Bool
  response : MultiWindowResponseProbe
} derive(FromJson, Eq, Debug)

///|
struct MultiWindowProbe {
  a : MultiWindowPageProbe
  b : MultiWindowPageProbe
} derive(FromJson, Eq, Debug)

///|
async fn run_multi_window_scenario_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> ShutdownProbeResult {
  let (target_a, target_b) = wait_for_multi_window_targets(target, timeout)
  let browser = @client.connect_cdp_browser_target_with_timeout(
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  let page_a = @client.connect_cdp_page_target_with_timeout(
    cdp_target_from(target),
    target_id=target_a.target_id,
    timeout_ms=timeout,
  )
  let page_b = @client.connect_cdp_page_target_with_timeout(
    cdp_target_from(target),
    target_id=target_b.target_id,
    timeout_ms=timeout,
  )
  defer {
    browser.close()
    page_a.close()
    page_b.close()
  }
  let initial = run_multi_window_page_clients(
    page_a,
    page_b,
    target_a.target_id,
    target_b.target_id,
    timeout,
    Some(app.native_log_path),
  )
  let snapshot = snapshot_scenario_process_tree(app)
  close_page_target(browser, target_a.target_id)
  wait_for_multi_window_closed_browsers(app.native_log_path, 1, timeout)
  match app_exit_code(app.process) {
    Some(code) =>
      fail(
        "multi-window app exited after only one window closed: code=" +
        code.to_string() +
        app_output_suffix(app.output_path),
      )
    None => ()
  }
  let surviving = decode_probe(
    evaluate_json(page_b, multi_window_probe_expression(0), true),
    "surviving multi-window B",
  )
  assert_multi_window_page(surviving, "B")
  guard surviving.response.window == initial.b.response.window else {
    fail("surviving window B changed native window handles")
  }
  guard surviving.response.request_id != initial.b.response.request_id else {
    fail("surviving window B reused its previous request_id")
  }
  close_page_target(browser, target_b.target_id)
  wait_for_multi_window_closed_browsers(app.native_log_path, 2, timeout)
  let shutdown = wait_for_scenario_app_shutdown(
    app, target, snapshot, process_shutdown_timeout_ms,
  )
  assert_multi_window_closed_log(app.native_log_path)
  println(
    "MoonBit 45_bridge_multi_window sequential lifecycle passed: helpers=" +
    shutdown.helper_processes.to_string(),
  )
  shutdown
}

///|
async fn run_multi_window_page_clients(
  page_a : @client.CdpClient,
  page_b : @client.CdpClient,
  target_a : String,
  target_b : String,
  timeout : Int,
  native_log_path : String?,
) -> MultiWindowProbe {
  ignore(page_a.send_schema_command("Runtime.enable"))
  ignore(page_b.send_schema_command("Runtime.enable"))
  wait_for_ready(page_a, multi_window_ready_expression(), timeout)
  wait_for_ready(page_b, multi_window_ready_expression(), timeout)
  let (value_a, value_b) = @async.with_task_group(group => {
    let task_a = group.spawn(
      () => evaluate_json(page_a, multi_window_probe_expression(220), true),
      no_wait=true,
    )
    let task_b = group.spawn(
      () => evaluate_json(page_b, multi_window_probe_expression(20), true),
      no_wait=true,
    )
    (task_a.wait(), task_b.wait())
  })
  let result = MultiWindowProbe::{
    a: decode_probe(value_a, "multi-window A"),
    b: decode_probe(value_b, "multi-window B"),
  }
  assert_multi_window_probe(result, target_a, target_b)
  match native_log_path {
    Some(path) => {
      wait_for_multi_window_osr_paints(path, timeout)
      assert_multi_window_native_log(path)
    }
    None => ()
  }
  println("MoonBit 45_bridge_multi_window routing probe passed")
  result
}

///|
fn multi_window_probe_expression(delay_ms : Int) -> String {
  let expression =
    #|;(async () => {
    #|  const invoke = window.__MoonBit__?.core?.invokeOp;
    #|  const label = window.__bridgeMultiLabel;
    #|  const response = await invoke("ext:multi/identify", {
    #|    label,
    #|    delay_ms: DELAY,
    #|  });
    #|  return {
    #|    url: location.href,
    #|    title: document.title,
    #|    label,
    #|    has_bridge: typeof invoke === "function",
    #|    response,
    #|  };
    #|})()
  expression.replace_all(old="DELAY", new=delay_ms.to_string())
}

///|
fn assert_multi_window_probe(
  result : MultiWindowProbe,
  target_a : String,
  target_b : String,
) -> Unit raise {
  assert_multi_window_page(result.a, "A")
  assert_multi_window_page(result.b, "B")
  guard target_a != target_b else {
    fail("multi-window probe used the same CDP target for both windows")
  }
  guard result.a.response.request_id != result.b.response.request_id else {
    fail("multi-window responses reused the same request_id")
  }
  guard result.a.response.window != result.b.response.window else {
    fail("multi-window responses reported the same native window handle")
  }
}

///|
fn assert_multi_window_page(
  page : MultiWindowPageProbe,
  expected_label : String,
) -> Unit raise {
  guard page.url == "proton://app/" + expected_label else {
    fail("multi-window " + expected_label + " URL mismatch: " + page.url)
  }
  guard page.title == "Bridge Multi " + expected_label else {
    fail("multi-window " + expected_label + " title mismatch: " + page.title)
  }
  guard page.label == expected_label else {
    fail("multi-window " + expected_label + " JS label mismatch: " + page.label)
  }
  guard page.has_bridge else {
    fail("multi-window " + expected_label + " bridge was not installed")
  }
  guard page.response.label == expected_label else {
    fail(
      "multi-window " +
      expected_label +
      " response crossed windows: " +
      page.response.label,
    )
  }
  guard page.response.request_id != "" else {
    fail("multi-window " + expected_label + " response is missing request_id")
  }
  guard page.response.window != "" else {
    fail(
      "multi-window " + expected_label + " response is missing window handle",
    )
  }
}

///|
fn assert_multi_window_native_log(path : String) -> Unit raise {
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => fail("failed to read multi-window native log: " + path)
  }
  let request_ids : Map[String, Bool] = Map([])
  let browser_ids : Map[String, Bool] = Map([])
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("bridge_enqueue") && line.contains("op=ext:multi/identify") {
      match (log_field(line, "request="), log_field(line, "browser=")) {
        (Some(request_id), Some(browser_id)) => {
          request_ids[request_id] = true
          browser_ids[browser_id] = true
        }
        _ => ()
      }
    }
  }
  guard request_ids.length() >= 2 else {
    fail("native log did not prove two multi-window requests were enqueued")
  }
  guard browser_ids.length() >= 2 else {
    fail("native log did not prove requests came from distinct browser ids")
  }
  assert_multi_window_osr_paints(log)
}

///|
fn assert_multi_window_osr_paints(log : String) -> Unit raise {
  guard count_multi_window_osr_paints(log) >= 2 else {
    fail("native log did not prove valid OSR paint for both windows")
  }
}

///|
async fn wait_for_multi_window_osr_paints(path : String, timeout : Int) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    let log = @mbfs.read_file_to_string(path, encoding="utf8") catch { _ => "" }
    if count_multi_window_osr_paints(log) >= 2 {
      return
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail("native log did not record valid OSR paint for both windows")
}

///|
fn count_multi_window_osr_paints(log : String) -> Int {
  let browser_ids : Map[String, Bool] = Map([])
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("osr_paint") {
      match (log_field(line, "browser="), log_field(line, "size=")) {
        (Some(browser), Some(size)) =>
          match size.split_once("x") {
            Some((width, height)) =>
              match (parse_log_int(width), parse_log_int(height)) {
                (Some(width), Some(height)) if width > 1 && height > 1 =>
                  browser_ids[browser] = true
                _ => ()
              }
            None => ()
          }
        _ => ()
      }
    }
  }
  browser_ids.length()
}

///|
async fn wait_for_multi_window_closed_browsers(
  path : String,
  expected : Int,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    let counts = multi_window_closed_browser_counts(path)
    assert_closed_browser_counts_are_unique(counts)
    if counts.length() == expected {
      return
    }
    guard counts.length() < expected else {
      fail(
        "native log recorded more than " +
        expected.to_string() +
        " closed multi-window browsers",
      )
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail(
    "native log did not record " +
    expected.to_string() +
    " closed multi-window browsers within " +
    timeout.to_string() +
    "ms",
  )
}

///|
fn assert_multi_window_closed_log(path : String) -> Unit raise {
  let counts = multi_window_closed_browser_counts(path)
  assert_closed_browser_counts_are_unique(counts)
  guard counts.length() == 2 else {
    fail(
      "native log recorded " +
      counts.length().to_string() +
      " distinct closed multi-window browsers; expected 2",
    )
  }
}

///|
fn multi_window_closed_browser_counts(path : String) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return counts
  }
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("window_closed") {
      match log_field(line, "browser=") {
        Some(browser_id) =>
          counts[browser_id] = counts.get(browser_id).unwrap_or(0) + 1
        None => ()
      }
    }
  }
  counts
}

///|
fn assert_closed_browser_counts_are_unique(
  counts : Map[String, Int],
) -> Unit raise {
  for browser_id, count in counts {
    guard count == 1 else {
      fail(
        "native log recorded window_closed " +
        count.to_string() +
        " times for browser " +
        browser_id,
      )
    }
  }
}
