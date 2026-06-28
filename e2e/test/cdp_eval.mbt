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
