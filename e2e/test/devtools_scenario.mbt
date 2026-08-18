///|
async fn evaluate_bool_in_context(
  page : @client.CdpClient,
  expression : String,
  context_id : Int,
) -> Bool {
  let response = page.send_schema_command("Runtime.evaluate", params={
    "expression": expression,
    "contextId": context_id,
    "returnByValue": true,
  })
  match @client.cdp_response_result_json(response) {
    { "result": { "value": true, .. }, .. } => true
    _ => false
  }
}

///|
async fn run_devtools_scenario_page_probe(
  app : SpawnedScenarioApp,
  target : String,
  timeout : Int,
) -> Unit {
  let page = connect_spawned_page(
    app,
    target,
    timeout,
    title="Proton DevTools API",
  )
  defer page.close()
  ignore(page.send_schema_command("Runtime.enable"))
  wait_for_ready(page, scenario_ready_expression("54_devtools"), timeout)
  let frame_tree = @typed.PageGetFrameTreeResult::from_json(
    @client.cdp_response_result_json(
      page.send_schema_command("Page.getFrameTree"),
    ),
  )
  let isolated_context = @typed.PageCreateIsolatedWorldResult::from_json(
    @client.cdp_response_result_json(
      page.send_schema_command("Page.createIsolatedWorld", params={
        "frameId": frame_tree.frame_tree.frame.id.value,
        "worldName": "DevTools Performance Metrics",
        "grantUniveralAccess": false,
      }),
    ),
  )
  guard evaluate_bool(page, scenario_probe_expression("54_devtools"), true) else {
    fail("DevTools disposed the main page bridge")
  }
  guard evaluate_bool_in_context(
    page,
    "typeof globalThis.__MoonBit__ === 'undefined'",
    isolated_context.execution_context_id.value,
  ) else {
    fail("Proton bridge was injected into a DevTools isolated context")
  }
}
