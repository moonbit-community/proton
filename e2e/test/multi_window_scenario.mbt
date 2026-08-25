///|
struct MultiWindowResponseProbe {
  label : String
  page_instance : String
  window : String
} derive(FromJson, Eq, Debug)

///|
pub extend MultiWindowResponseProbe with Eq::{not_equal, equal}

///|
pub extend MultiWindowResponseProbe with Debug::{to_repr}

///|
pub extend MultiWindowResponseProbe with FromJson::{from_json}

///|
struct MultiWindowPageProbe {
  url : String
  title : String
  label : String
  has_bridge : Bool
  response : MultiWindowResponseProbe
} derive(FromJson, Eq, Debug)

///|
pub extend MultiWindowPageProbe with Eq::{not_equal, equal}

///|
pub extend MultiWindowPageProbe with Debug::{to_repr}

///|
pub extend MultiWindowPageProbe with FromJson::{from_json}

///|
struct MultiWindowProbe {
  a : MultiWindowPageProbe
  b : MultiWindowPageProbe
} derive(FromJson, Eq, Debug)

///|
pub extend MultiWindowProbe with Eq::{not_equal, equal}

///|
pub extend MultiWindowProbe with Debug::{to_repr}

///|
pub extend MultiWindowProbe with FromJson::{from_json}

///|
async fn run_multi_window_scenario_probe(
  tasks : @async.TaskGroup[Unit],
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> ShutdownProbeResult {
  let (target_a, target_b) = wait_for_multi_window_targets(target, timeout)
  let browser = @client.connect_cdp_browser_target_with_timeout(
    tasks,
    cdp_target_from(target),
    timeout_ms=timeout,
  )
  let page_a = @page.Page::connect(
    tasks,
    cdp_target_from(target),
    target_id=target_a.target_id,
    timeout_ms=timeout,
  )
  let page_b = @page.Page::connect(
    tasks,
    cdp_target_from(target),
    target_id=target_b.target_id,
    timeout_ms=timeout,
  )
  let initial = run_multi_window_page_clients(
    page_a,
    page_b,
    target_a.target_id,
    target_b.target_id,
    timeout,
  )
  let snapshot = snapshot_scenario_process_tree(app)
  close_page_target(browser, target_a.target_id)
  wait_for_page_target_closed(browser, target_a.target_id, timeout)
  match app_exit_code(app.process) {
    Some(code) =>
      fail(
        "multi-window app exited after only one window closed: code=" +
        code.to_string() +
        app_output_suffix(app.output_path),
      )
    None => ()
  }
  page_a.close()
  let surviving = decode_probe(
    evaluate_json(page_b, multi_window_probe_expression(0), true),
    "surviving multi-window B",
  )
  assert_multi_window_page(surviving, "B")
  guard surviving.response.window == initial.b.response.window else {
    fail("surviving window B changed native window handles")
  }
  guard surviving.response.page_instance == initial.b.response.page_instance else {
    fail("surviving window B changed its page instance")
  }
  close_page_target(browser, target_b.target_id)
  page_b.close()
  browser.close()
  let shutdown = wait_for_scenario_app_shutdown(
    app, target, snapshot, process_shutdown_timeout_ms,
  )
  println(
    "MoonBit 45_bridge_multi_window sequential lifecycle passed: helpers=" +
    shutdown.helper_processes.to_string(),
  )
  shutdown
}

///|
async fn run_multi_window_page_clients(
  page_a : @page.Page,
  page_b : @page.Page,
  target_a : String,
  target_b : String,
  timeout : Int,
) -> MultiWindowProbe {
  wait_for_ready(page_a, multi_window_ready_expression(), timeout)
  wait_for_ready(page_b, multi_window_ready_expression(), timeout)
  ignore(capture_headless_screenshot(page_a))
  ignore(capture_headless_screenshot(page_b))
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
  guard result.a.response.page_instance != result.b.response.page_instance else {
    fail("multi-window responses reported the same page instance")
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
  guard page.url == "https://proton.localhost/" else {
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
  guard page.response.page_instance != "" else {
    fail(
      "multi-window " + expected_label + " response is missing page instance",
    )
  }
  guard page.response.window != "" else {
    fail(
      "multi-window " + expected_label + " response is missing window handle",
    )
  }
}
