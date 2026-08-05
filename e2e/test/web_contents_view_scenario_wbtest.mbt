///|
struct WebContentsViewPageProbe {
  url : String
  title : String
  marker : String
} derive(FromJson, Eq, Debug)

///|
async fn run_web_contents_view_scenario_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> ShutdownProbeResult {
  let (host, left, right) = wait_for_web_contents_view_targets(
    app, target, timeout,
  )
  let browser = @client.connect_cdp_browser_target_with_timeout(
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  let page_left = @client.connect_cdp_page_target_with_timeout(
    cdp_target_from(target),
    target_id=left.target_id,
    timeout_ms=timeout,
  )
  let page_right = @client.connect_cdp_page_target_with_timeout(
    cdp_target_from(target),
    target_id=right.target_id,
    timeout_ms=timeout,
  )
  defer {
    browser.close()
    page_left.close()
    page_right.close()
  }
  ignore(page_left.send_schema_command("Runtime.enable"))
  ignore(page_right.send_schema_command("Runtime.enable"))
  wait_for_ready(page_left, web_contents_view_ready_expression(), timeout)
  wait_for_ready(page_right, web_contents_view_ready_expression(), timeout)
  let (left_value, right_value) = @async.with_task_group(group => {
    let task_left = group.spawn(
      () => evaluate_json(page_left, web_contents_view_probe_expression(), true),
      no_wait=true,
    )
    let task_right = group.spawn(
      () => {
        evaluate_json(page_right, web_contents_view_probe_expression(), true)
      },
      no_wait=true,
    )
    (task_left.wait(), task_right.wait())
  })
  assert_web_contents_view_page(
    decode_probe(left_value, "left web contents view"),
    "WCV Left",
    "left-marker",
    "data:text/html",
  )
  assert_web_contents_view_page(
    decode_probe(right_value, "right web contents view"),
    "WCV Right",
    "right-marker",
    "proton://view-right/",
  )
  guard left.target_id != right.target_id &&
    left.target_id != host.target_id &&
    right.target_id != host.target_id else {
    fail("web contents views must expose distinct CDP targets")
  }
  wait_for_web_contents_view_osr_paints(app.native_log_path, timeout)
  println("MoonBit 52_web_contents_view routing probe passed")

  // Close the left view through CDP; the host window and the right view must
  // survive it untouched.
  let snapshot = snapshot_scenario_process_tree(app)
  close_page_target(browser, left.target_id)
  wait_for_web_contents_view_closed_browsers(app.native_log_path, 1, timeout)
  match app_exit_code(app.process) {
    Some(code) =>
      fail(
        "web contents view app exited after one view closed: code=" +
        code.to_string() +
        app_output_suffix(app.output_path),
      )
    None => ()
  }
  let surviving = decode_probe(
    evaluate_json(page_right, web_contents_view_probe_expression(), true),
    "surviving right web contents view",
  )
  assert_web_contents_view_page(
    surviving, "WCV Right", "right-marker", "proton://view-right/",
  )

  // Closing the host window must tear down the remaining view with it and let
  // the app shut down cleanly.
  close_page_target(browser, host.target_id)
  let shutdown = wait_for_scenario_app_shutdown(
    app, target, snapshot, process_shutdown_timeout_ms,
  )
  assert_web_contents_view_closed_log(app.native_log_path)
  assert_web_contents_view_event_log(app.native_log_path)
  println(
    "MoonBit 52_web_contents_view sequential lifecycle passed: helpers=" +
    shutdown.helper_processes.to_string(),
  )
  shutdown
}

///|
async fn wait_for_web_contents_view_targets(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> (
  @client.CdpDiscoveredTarget,
  @client.CdpDiscoveredTarget,
  @client.CdpDiscoveredTarget,
) {
  let cdp_target = cdp_target_from(target)
  let mut elapsed = 0
  while elapsed <= timeout {
    let targets = @client.discover_targets(cdp_target) catch { _ => [] }
    let mut host : @client.CdpDiscoveredTarget? = None
    let mut left : @client.CdpDiscoveredTarget? = None
    let mut right : @client.CdpDiscoveredTarget? = None
    for item in targets {
      if item.target_type == "page" && item.web_socket_debugger_url is Some(_) {
        if item.title == "Web Contents View Host" {
          host = Some(item)
        } else if item.title == "WCV Left" {
          left = Some(item)
        } else if item.title == "WCV Right" {
          right = Some(item)
        }
      }
    }
    match (host, left, right) {
      (Some(host), Some(left), Some(right)) => return (host, left, right)
      _ => {
        @async.sleep(250)
        elapsed = elapsed + 250
      }
    }
    if elapsed >= timeout {
      let discovered = targets
        .map(item => item.target_type + ":" + item.title)
        .join(", ")
      fail(
        "CDP page targets did not become ready within " +
        timeout.to_string() +
        "ms: Web Contents View Host, WCV Left, WCV Right. discovered=[" +
        discovered +
        "]" +
        app_diagnostic_suffix(app),
      )
    }
  }
  abort("unreachable")
}

///|
fn web_contents_view_ready_expression() -> String {
  "document.readyState === 'complete' && document.title.length > 0"
}

///|
fn web_contents_view_probe_expression() -> String {
  let expression =
    #|;(() => ({
    #|  url: location.href,
    #|  title: document.title,
    #|  marker: document.body ? document.body.textContent.trim() : "",
    #|}))()
  expression
}

///|
fn assert_web_contents_view_page(
  page : WebContentsViewPageProbe,
  expected_title : String,
  expected_marker : String,
  expected_url_prefix : String,
) -> Unit raise {
  guard page.title == expected_title else {
    fail("web contents view title mismatch: " + page.title)
  }
  guard page.url.has_prefix(expected_url_prefix) else {
    fail("web contents view URL mismatch: " + page.url)
  }
  guard page.marker.contains(expected_marker) else {
    fail("web contents view marker mismatch: " + page.marker)
  }
}

///|
fn assert_web_contents_view_event_log(native_log_path : String) -> Unit raise {
  let path = native_log_path + ".view-events"
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => fail("failed to read web contents view event log: " + path)
  }
  guard log.contains("view_navigated url=data:text/html") else {
    fail("view event log missed the left view navigation: " + log)
  }
  guard log.contains("view_navigated url=proton://view-right/") else {
    fail("view event log missed the right view navigation: " + log)
  }
  guard log.contains("view_title_updated title=WCV Left") &&
    log.contains("view_title_updated title=WCV Right") else {
    fail("view event log missed view titles: " + log)
  }
  guard log.contains("view_loading_changed loading=true") &&
    log.contains("view_loading_changed loading=false") else {
    fail("view event log missed loading state changes: " + log)
  }
}

///|
async fn wait_for_web_contents_view_osr_paints(
  path : String,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    if count_web_contents_view_osr_paints(path) >= 2 {
      return
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail("native log did not record valid OSR paint for both web contents views")
}

///|
fn count_web_contents_view_osr_paints(path : String) -> Int {
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch { _ => "" }
  let browsers : Map[String, Bool] = Map([])
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("view_osr_paint") {
      match (log_field(line, "browser="), log_field(line, "size=")) {
        (Some(browser), Some("300x220")) => browsers[browser] = true
        _ => ()
      }
    }
  }
  browsers.length()
}

///|
async fn wait_for_web_contents_view_closed_browsers(
  path : String,
  expected : Int,
  timeout : Int,
) -> Unit {
  let mut elapsed = 0
  while elapsed <= timeout {
    if count_web_contents_view_closed_browsers(path) == expected {
      return
    }
    @async.sleep(100)
    elapsed = elapsed + 100
  }
  fail(
    "native log did not record " +
    expected.to_string() +
    " closed web contents view browsers within " +
    timeout.to_string() +
    "ms",
  )
}

///|
fn count_web_contents_view_closed_browsers(path : String) -> Int {
  let log = @mbfs.read_file_to_string(path, encoding="utf8") catch { _ => "" }
  let browsers : Map[String, Bool] = Map([])
  for raw_line in log.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    if line.contains("view_browser_before_close") {
      match log_field(line, "browser=") {
        Some(browser) => browsers[browser] = true
        None => ()
      }
    }
  }
  browsers.length()
}

///|
fn assert_web_contents_view_closed_log(path : String) -> Unit raise {
  guard count_web_contents_view_closed_browsers(path) == 2 else {
    fail(
      "native log did not prove both web contents views closed before shutdown",
    )
  }
}
