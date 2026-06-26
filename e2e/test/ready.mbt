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

///|
fn scenario_ready_expression(name : String) -> String {
  match name {
    "41_app_commands" =>
      "Boolean(window.__MoonBit__ && window.__MoonBit__.core && window.__MoonBit__.core.invokeOp)"
    _ => "document.readyState !== 'loading'"
  }
}
