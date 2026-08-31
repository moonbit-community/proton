///|
async fn evaluate_bool_in_context(
  world : @page.IsolatedWorld,
  expression : String,
) -> Bool {
  world.evaluate(expression) is True
}

///|
async fn run_devtools_scenario_page_probe(
  tasks : @async.TaskGroup[Unit],
  app : SpawnedScenarioApp,
  target : String,
  browser_web_socket_url : String,
  timeout : Int,
) -> ShutdownProbeResult {
  let (host, devtools) = wait_for_devtools_targets(app, target, timeout)
  let browser = @client.CdpClient::connect_with_timeout(
    tasks,
    browser_web_socket_url,
    timeout_ms=timeout,
  )
  let page = connect_spawned_page(
    tasks,
    app,
    target,
    timeout,
    title="Proton DevTools API",
  )
  wait_for_ready(page, scenario_ready_expression("54_devtools"), timeout)
  let isolated_world = page.create_isolated_world(
    "DevTools Performance Metrics",
  )
  guard evaluate_bool(page, scenario_probe_expression("54_devtools"), true) else {
    fail("DevTools disposed the main page bridge")
  }
  guard evaluate_bool_in_context(
    isolated_world, "typeof globalThis.__MoonBit__ === 'undefined'",
  ) else {
    fail("Proton bridge was injected into a DevTools isolated context")
  }
  guard host.target_id != devtools.target_id else {
    fail("DevTools must have an independent CEF browser target")
  }

  let snapshot = snapshot_scenario_process_tree(app)
  page.close()
  close_page_target(browser, host.target_id)
  let shutdown = wait_for_scenario_app_shutdown(
    app, target, snapshot, process_shutdown_timeout_ms,
  )
  println(
    "MoonBit 54_devtools lifecycle passed: helpers=" +
    shutdown.helper_processes.to_string(),
  )
  shutdown
}

///|
async fn wait_for_devtools_targets(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> (@client.CdpDiscoveredTarget, @client.CdpDiscoveredTarget) {
  let cdp_target = cdp_target_from(target)
  let mut elapsed = 0
  while elapsed <= timeout {
    let targets = discover_targets_for_poll(cdp_target)
    let mut host : @client.CdpDiscoveredTarget? = None
    let mut devtools : @client.CdpDiscoveredTarget? = None
    for item in targets {
      if item.title == "Proton DevTools API" {
        host = Some(item)
      } else if item.url.has_prefix("devtools://") {
        devtools = Some(item)
      }
    }
    match (host, devtools) {
      (Some(host), Some(devtools)) => return (host, devtools)
      _ => {
        @async.sleep(cdp_start_poll_timeout_ms)
        elapsed = elapsed + cdp_start_poll_timeout_ms
      }
    }
  }
  fail(
    "CEF host and DevTools targets did not become ready within " +
    timeout.to_string() +
    "ms" +
    app_diagnostic_suffix(app),
  )
}
