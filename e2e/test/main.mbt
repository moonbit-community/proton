///|
async fn main {
  let name = scenario_name()
  ignore(
    @client.wait_for_browser_endpoint(
      cdp_http_endpoint(),
      timeout_ms=timeout_ms(),
    ),
  )
  let page = @client.connect_cdp_page_target_with_timeout(
    cdp_target(),
    timeout_ms=timeout_ms(),
  )
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, scenario_ready_expression(name), timeout_ms())
  guard evaluate_bool(page, scenario_probe_expression(name), true) else {
    fail("CDP e2e probe failed for " + name)
  }
  println("CDP e2e passed: " + name)
}
