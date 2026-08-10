///|
async fn main {
  let name = scenario_name()
  run_cdp_scenario_probe(name, cdp_target_text(), timeout_ms())
  println("CDP e2e passed: " + name)
}

///|
async fn run_cdp_scenario_probe(
  name : String,
  target : String,
  timeout : Int,
) -> Unit {
  ensure_supported_scenario(name)
  let _ = @client.wait_for_browser_endpoint(
    cdp_http_endpoint_from(target),
    timeout_ms=timeout,
  )
  run_connected_scenario_probe(name, target, timeout)
}

///|
async fn run_connected_scenario_probe(
  name : String,
  target : String,
  timeout : Int,
) -> Unit {
  if name == "45_bridge_multi_window" {
    run_multi_window_driver_probe(target, timeout)
    return
  }
  let page = if name == "54_devtools" {
    @client.connect_cdp_page_target_with_timeout(
      cdp_target_from(target),
      title="Proton DevTools API",
      timeout_ms=timeout,
    )
  } else {
    @client.connect_cdp_page_target_with_timeout(
      cdp_target_from(target),
      timeout_ms=timeout,
    )
  }
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, scenario_ready_expression(name), timeout)
  guard evaluate_bool(page, scenario_probe_expression(name), true) else {
    fail("CDP e2e probe failed for " + name)
  }
}
