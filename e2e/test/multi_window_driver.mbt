///|
async fn run_multi_window_driver_probe(target : String, timeout : Int) -> Unit {
  let (target_a, target_b) = wait_for_multi_window_targets(target, timeout)
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
    page_a.close()
    page_b.close()
  }
  ignore(page_a.send_schema_command("Runtime.enable"))
  ignore(page_b.send_schema_command("Runtime.enable"))
  wait_for_ready(page_a, multi_window_ready_expression(), timeout)
  wait_for_ready(page_b, multi_window_ready_expression(), timeout)
  let (result_a, result_b) = @async.with_task_group(group => {
    let task_a = group.spawn(
      () => evaluate_bool(page_a, multi_window_driver_expression(220), true),
      no_wait=true,
    )
    let task_b = group.spawn(
      () => evaluate_bool(page_b, multi_window_driver_expression(20), true),
      no_wait=true,
    )
    (task_a.wait(), task_b.wait())
  })
  guard result_a && result_b else {
    fail("CDP e2e multi-window driver probe failed")
  }
  guard target_a.target_id != target_b.target_id else {
    fail("CDP e2e multi-window driver used the same target twice")
  }
}

///|
fn multi_window_ready_expression() -> String {
  "Boolean(window.__MoonBit__?.core?.invokeOp && window.__bridgeMultiLabel)"
}

///|
fn multi_window_driver_expression(delay_ms : Int) -> String {
  let expression =
    #|;(async () => {
    #|  const invoke = window.__MoonBit__?.core?.invokeOp;
    #|  const label = window.__bridgeMultiLabel;
    #|  if (location.href !== "proton://app/" + label) return false;
    #|  if (document.title !== "Bridge Multi " + label) return false;
    #|  if (typeof invoke !== "function") return false;
    #|  const response = await invoke("ext:multi/identify", {
    #|    label,
    #|    delay_ms: DELAY,
    #|  });
    #|  return response?.label === label &&
    #|    typeof response?.request_id === "string" &&
    #|    response.request_id.length > 0 &&
    #|    typeof response?.window === "string" &&
    #|    response.window.length > 0;
    #|})()
  expression.replace_all(old="DELAY", new=delay_ms.to_string())
}

///|
async fn wait_for_multi_window_targets(
  target : String,
  timeout : Int,
) -> (@client.CdpDiscoveredTarget, @client.CdpDiscoveredTarget) {
  let cdp_target = cdp_target_from(target)
  let mut elapsed = 0
  while elapsed <= timeout {
    let targets = @client.discover_targets(cdp_target) catch { _ => [] }
    let mut target_a : @client.CdpDiscoveredTarget? = None
    let mut target_b : @client.CdpDiscoveredTarget? = None
    for item in targets {
      if item.target_type == "page" && item.web_socket_debugger_url is Some(_) {
        if item.title == "Bridge Multi A" {
          target_a = Some(item)
        } else if item.title == "Bridge Multi B" {
          target_b = Some(item)
        }
      }
    }
    match (target_a, target_b) {
      (Some(a), Some(b)) => return (a, b)
      _ => {
        @async.sleep(250)
        elapsed = elapsed + 250
      }
    }
  }
  fail(
    "CDP page target did not become ready within " +
    timeout.to_string() +
    "ms: Bridge Multi A, Bridge Multi B",
  )
}
