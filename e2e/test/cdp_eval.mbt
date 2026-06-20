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
async fn wait_for_ready(
  page : @client.CdpClient,
  expression : String,
  timeout : Int,
) -> Unit {
  let attempts = timeout / 100
  for attempt in 0..<=attempts {
    if evaluate_bool(page, expression, false) {
      return
    }
    if attempt < attempts {
      @async.sleep(100)
    }
  }
  fail("CDP e2e timed out waiting for ready expression: " + expression)
}
