///|
struct WebContentsViewPageProbe {
  url : String
  title : String
  marker : String
} derive(FromJson, Eq, Debug)

///|
pub extend WebContentsViewPageProbe with Eq::{not_equal, equal}

///|
pub extend WebContentsViewPageProbe with Debug::{to_repr}

///|
pub extend WebContentsViewPageProbe with FromJson::{from_json}

///|
async fn run_web_contents_view_scenario_probe(
  tasks : @async.TaskGroup[Unit],
  app : SpawnedScenarioApp,
  target : String,
  browser_web_socket_url : String,
  event_path : String,
  timeout : Int,
) -> ShutdownProbeResult {
  let (host, left, right) = wait_for_web_contents_view_targets(
    app, target, timeout,
  )
  let browser = @client.CdpClient::connect_with_timeout(
    tasks,
    browser_web_socket_url,
    timeout_ms=timeout,
  )
  let page_left = connect_web_contents_view_page(tasks, left, timeout)
  let page_right = connect_web_contents_view_page(tasks, right, timeout)
  wait_for_ready(page_left, web_contents_view_ready_expression(), timeout)
  wait_for_ready(page_right, web_contents_view_ready_expression(), timeout)
  ignore(capture_headless_screenshot(page_left))
  ignore(capture_headless_screenshot(page_right))
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
  println("MoonBit 52_web_contents_view routing probe passed")

  // Close the left view through CDP; the host window and the right view must
  // survive it untouched.
  let snapshot = snapshot_scenario_process_tree(app)
  close_page_target(browser, left.target_id)
  wait_for_page_target_closed(browser, left.target_id, timeout)
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
  assert_web_contents_view_events(event_path)
  println(
    "MoonBit 52_web_contents_view sequential lifecycle passed: helpers=" +
    shutdown.helper_processes.to_string(),
  )
  shutdown
}

///|
async fn connect_web_contents_view_page(
  tasks : @async.TaskGroup[Unit],
  target : @client.CdpDiscoveredTarget,
  timeout : Int,
) -> @page.Page {
  match target.web_socket_debugger_url {
    Some(web_socket_url) =>
      @page.Page::connect_web_socket(tasks, web_socket_url, timeout_ms=timeout)
    None => fail("CDP page target has no WebSocket URL: " + target.target_id)
  }
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
    let targets = discover_targets_for_poll(cdp_target)
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
fn assert_web_contents_view_events(path : String) -> Unit raise {
  let events = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => fail("failed to read web contents view events: " + path)
  }
  guard events.contains("view_navigated url=data:text/html") else {
    fail("view events missed the left view navigation: " + events)
  }
  guard events.contains("view_navigated url=proton://view-right/") else {
    fail("view events missed the right view navigation: " + events)
  }
  guard events.contains("view_title_updated title=WCV Left") &&
    events.contains("view_title_updated title=WCV Right") else {
    fail("view events missed view titles: " + events)
  }
  guard events.contains("view_loading_changed loading=true") &&
    events.contains("view_loading_changed loading=false") else {
    fail("view events missed loading state changes: " + events)
  }
}
