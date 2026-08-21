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
  timeout : Int,
) -> Unit {
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
}
