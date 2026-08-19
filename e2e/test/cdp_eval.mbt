///|
async fn evaluate_bool(
  page : @client.CdpClient,
  expression : String,
  await_promise : Bool,
) -> Bool {
  let response = page.send_schema_command("Runtime.evaluate", params={
    "expression": expression,
    "returnByValue": true,
    "awaitPromise": await_promise,
  })
  match @client.cdp_response_result_json(response) {
    { "result": { "value": true, .. }, .. } => true
    _ => false
  }
}

///|
async fn reload_page_and_wait(
  page : @client.CdpClient,
  expression : String,
  description : String,
  timeout : Int,
) -> Unit {
  page.clear_cdp_events()
  ignore(page.send_schema_command("Page.reload", timeout_ms=timeout))
  ignore(
    run_e2e_operation_with_timeout(
      timeout,
      "Page.loadEventFired after reload",
      () => page.recv_cdp_event(method_name="Page.loadEventFired"),
    ),
  )
  wait_for_cdp_expression(page, expression, description, timeout)
}
