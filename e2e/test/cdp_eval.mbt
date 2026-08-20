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
fn is_transient_execution_context_error(error : Error) -> Bool {
  match error {
    @client.BrowserError::CommandFailed(
      -32000,
      "Cannot find default execution context"
    ) => true
    _ => false
  }
}

///|
async fn evaluate_bool_while_context_available(
  page : @client.CdpClient,
  expression : String,
) -> Bool {
  evaluate_bool(page, expression, false) catch {
    error if is_transient_execution_context_error(error) => false
    error => raise error
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
